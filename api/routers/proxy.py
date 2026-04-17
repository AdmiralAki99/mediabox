"""HLS proxy router.

Fetches m3u8 manifests and video segments from CDN with a custom Referer header,
rewrites all URLs in the manifest to go back through this proxy, and serves them
to Qt Multimedia (FFmpeg backend) on localhost.

Three subtleties handled:
  1. FFmpeg validates segment extensions from the URL path — so segment proxy URLs
     must end with the real filename (e.g. /proxy/seg/seg-1.m4s?url=...&ref=...).
  2. fMP4 streams use #EXT-X-MAP:URI="init.mp4" for the init segment, and
     #EXT-X-KEY:URI="..." for encryption keys — these live inside # tag lines
     and must also be rewritten so the proxy adds the Referer when fetching them.
  3. Seeking on fMP4/CMAF HLS via setPosition() is unreliable in Qt's FFmpeg
     backend (decoder freezes without re-fetching the init segment).  Instead the
     caller passes _seek_ms=<ms> so the proxy trims the media playlist to start at
     the segment that contains the target time.  The player then loads naturally
     from the right segment with no setPosition() call needed.
"""
import re
import time
from urllib.parse import urljoin, quote, urlparse

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import Response, StreamingResponse

router = APIRouter(prefix="/proxy", tags=["Proxy"])

_client = httpx.AsyncClient(timeout=60, follow_redirects=True)
_BASE = "http://localhost:8000"

# 30s cache avoids re-fetching the manifest on every resume/reload; seek slices are not cached
_manifest_cache: dict[str, tuple[str, float]] = {}
_MANIFEST_TTL = 30.0

# HLS tag attributes that contain URIs needing rewrite
_URI_TAGS = ("EXT-X-MAP", "EXT-X-KEY", "EXT-X-MEDIA", "EXT-X-I-FRAME-STREAM-INF")


def _seg_proxy(abs_url: str, ref: str) -> str:
    """Return a /proxy/seg URL that includes the real filename in the path.

    FFmpeg's HLS demuxer checks the extension of the segment URI against its
    allowed_extensions list.  Our proxy path /proxy/seg has no extension and
    would be rejected.  Appending the original filename fixes that.
    """
    filename = urlparse(abs_url).path.rstrip("/").rsplit("/", 1)[-1] or "seg.ts"
    url_enc = quote(abs_url, safe="")
    ref_enc = quote(ref, safe="")
    return f"{_BASE}/proxy/seg/{filename}?url={url_enc}&ref={ref_enc}"


def _hls_proxy(abs_url: str, ref: str, seek_ms: int = 0) -> str:
    url_enc = quote(abs_url, safe="")
    ref_enc = quote(ref, safe="")
    seek_sfx = f"&_seek_ms={seek_ms}" if seek_ms > 0 else ""
    return f"{_BASE}/proxy/hls?url={url_enc}&ref={ref_enc}{seek_sfx}"


def _rewrite_tag_uris(line: str, base: str, ref: str) -> str:
    """Rewrite URI="..." inside HLS tag lines (#EXT-X-MAP, #EXT-X-KEY, etc.)."""
    def replacer(m: re.Match) -> str:
        uri = m.group(1)
        abs_url = uri if uri.startswith("http") else urljoin(base, uri)
        proxied = _seg_proxy(abs_url, ref)
        return f'URI="{proxied}"'
    return re.sub(r'URI="([^"]+)"', replacer, line)


def _rewrite_master(text: str, base: str, ref: str, seek_ms: int = 0) -> str:
    """Rewrite a master HLS playlist, keeping only the highest-bandwidth rendition.

    Qt's fMP4 HLS demuxer (ffmpeg backend) can trigger a 'sequence wrapped' error
    when it probes multiple quality streams simultaneously, causing codec context
    re-init failures and Invalid NAL unit size floods.  Serving a single rendition
    eliminates ABR switching entirely.

    seek_ms is threaded through to the media playlist URL so the media playlist
    proxy can trim segments to the seek position.
    """
    all_lines = text.splitlines()
    # Collect (bandwidth, inf_line_idx) for every #EXT-X-STREAM-INF entry
    entries = []
    i = 0
    while i < len(all_lines):
        line = all_lines[i].strip()
        if line.startswith("#EXT-X-STREAM-INF"):
            bw_m = re.search(r"BANDWIDTH=(\d+)", line)
            bw = int(bw_m.group(1)) if bw_m else 0
            entries.append((bw, i))
        i += 1

    if not entries:
        return _rewrite_media(text, base, ref, seek_ms)

    # Pick the highest-bandwidth rendition
    best_inf_idx = max(entries, key=lambda e: e[0])[1]

    out = []
    i = 0
    while i < len(all_lines):
        line = all_lines[i].strip()
        if line.startswith("#EXT-X-STREAM-INF"):
            if i == best_inf_idx:
                out.append(all_lines[i])
                i += 1
                # Next non-empty line is the rendition URI
                while i < len(all_lines) and not all_lines[i].strip():
                    i += 1
                if i < len(all_lines):
                    uri = all_lines[i].strip()
                    abs_url = uri if uri.startswith("http") else urljoin(base, uri)
                    # Thread seek_ms through to the media playlist
                    out.append(_hls_proxy(abs_url, ref, seek_ms))
                    i += 1
            else:
                i += 1  # skip this STREAM-INF line
                # Skip its URI line too
                while i < len(all_lines) and not all_lines[i].strip():
                    i += 1
                if i < len(all_lines) and not all_lines[i].strip().startswith("#"):
                    i += 1
        else:
            out.append(all_lines[i])
            i += 1
    return "\n".join(out)


def _rewrite_media(text: str, base: str, ref: str, seek_ms: int = 0) -> str:
    """Rewrite a media (non-master) HLS playlist, then optionally trim to seek_ms."""
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            lines.append(line)
            continue
        if stripped.startswith("#"):
            if "URI=" in stripped and any(t in stripped for t in _URI_TAGS):
                lines.append(_rewrite_tag_uris(line, base, ref))
            else:
                lines.append(line)
            continue
        abs_url = line if line.startswith("http") else urljoin(base, line)
        if ".m3u8" in abs_url.split("?")[0]:
            lines.append(_hls_proxy(abs_url, ref, seek_ms))
        else:
            lines.append(_seg_proxy(abs_url, ref))
    rewritten = "\n".join(lines)
    if seek_ms > 0:
        rewritten = _trim_media_to_seek(rewritten, seek_ms)
    return rewritten


def _trim_media_to_seek(text: str, seek_ms: int) -> str:
    """Trim a rewritten media playlist so playback starts at seek_ms.

    For fMP4/CMAF HLS, Qt's FFmpeg backend freezes when setPosition() is called
    because the decoder doesn't re-fetch the #EXT-X-MAP init segment mid-stream.
    The workaround is to return a manifest that starts at the right segment so the
    player never needs to seek — it just loads naturally from there.

    - The #EXT-X-MAP init segment line is always kept (required for fMP4 decode).
    - #EXT-X-MEDIA-SEQUENCE is updated to the new first-segment sequence number.
    - Precision is ±one segment duration (typically ±6 s) — acceptable for scrub.
    """
    lines = text.splitlines(keepends=False)

    # Pass 1: collect segment entries (extinf_line_idx, seg_line_idx, duration_ms)
    segments: list[tuple[int, int, int]] = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith("#EXTINF:"):
            dur_s = stripped[8:].split(",")[0].strip()
            try:
                dur_ms = int(float(dur_s) * 1000)
            except Exception:
                dur_ms = 0
            j = i + 1
            # Skip comment/empty lines to find the segment URI line
            while j < len(lines) and (not lines[j].strip() or lines[j].strip().startswith("#")):
                j += 1
            if j < len(lines):
                segments.append((i, j, dur_ms))
        i += 1

    if not segments:
        return text  # not a media playlist we can parse

    # Pass 2: find the first segment whose START time >= seek_ms
    # (i.e. the last segment whose start is still <= seek_ms)
    cumulative_ms = 0
    start_seg = 0
    for idx, (_ei, _si, dur_ms) in enumerate(segments):
        if cumulative_ms >= seek_ms:
            start_seg = idx
            break
        cumulative_ms += dur_ms
        start_seg = idx + 1
    # Clamp to valid range (always keep at least the last segment)
    start_seg = min(start_seg, len(segments) - 1)

    if start_seg == 0:
        return text  # seek is before first segment, nothing to trim

    first_keep_line = segments[start_seg][0]  # first #EXTINF line to include

    # Pass 3: rebuild header (everything before first_keep_line, minus
    # earlier #EXTINF / segment-URI lines, with updated MEDIA-SEQUENCE)
    header: list[str] = []
    for i in range(first_keep_line):
        stripped = lines[i].strip()
        if stripped.startswith("#EXTINF:"):
            continue  # drop segments before our start
        if not stripped.startswith("#") and stripped:
            continue  # drop segment URIs before our start
        if stripped.startswith("#EXT-X-MEDIA-SEQUENCE:"):
            try:
                base_seq = int(stripped.split(":")[1])
                header.append(f"#EXT-X-MEDIA-SEQUENCE:{base_seq + start_seg}")
            except Exception:
                header.append(lines[i])
        else:
            header.append(lines[i])

    tail = lines[first_keep_line:]
    return "\n".join(header + tail)


def _rewrite_manifest(text: str, manifest_url: str, ref: str, seek_ms: int = 0) -> str:
    base = manifest_url.rsplit("/", 1)[0] + "/"
    if "#EXT-X-STREAM-INF" in text:
        return _rewrite_master(text, base, ref, seek_ms)
    return _rewrite_media(text, base, ref, seek_ms)


@router.get("/hls")
async def proxy_hls(
    url: str,
    ref: str = "",
    _t: str = "",       # cache-busting param from QML player — ignored by proxy
    _seek_ms: str = "",  # seek target in ms; triggers manifest trimming
) -> Response:
    """Fetch an HLS master or media playlist, rewrite all embedded URIs.

    When _seek_ms is given the media playlist is trimmed to start at the segment
    containing that position, so the player never needs to call setPosition().
    """
    seek_ms = int(_seek_ms) if _seek_ms else 0
    now = time.monotonic()

    # Only use the cache for non-seek requests (seek manifests are unique per position)
    if not seek_ms:
        cached = _manifest_cache.get(url)
        if cached and now < cached[1]:
            return Response(
                content=cached[0],
                media_type="application/vnd.apple.mpegurl",
                headers={"Cache-Control": "no-cache", "Access-Control-Allow-Origin": "*"},
            )

    headers = {"Referer": ref} if ref else {}
    r = await _client.get(url, headers=headers)
    rewritten = _rewrite_manifest(r.text, url, ref, seek_ms)

    if not seek_ms:
        _manifest_cache[url] = (rewritten, now + _MANIFEST_TTL)

    return Response(
        content=rewritten,
        media_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-cache", "Access-Control-Allow-Origin": "*"},
    )


@router.get("/seg/{filename}")
async def proxy_segment(filename: str, url: str, ref: str = "") -> StreamingResponse:
    """Stream a single HLS segment or init/key file with Referer.

    Uses streaming (not buffered) so Qt's FFmpeg backend receives the first bytes
    immediately — buffering the full segment (2-10 MB) before returning caused Qt's
    HLS demuxer to hit its internal timeout and report 'Error when loading first
    segment', triggering runaway reload loops.
    """
    headers = {"Referer": ref} if ref else {}
    r = await _client.send(_client.build_request("GET", url, headers=headers), stream=True)

    # fMP4 segments (.m4s) must be served as video/mp4.
    raw_ct = r.headers.get("content-type", "").split(";")[0].strip()
    if not raw_ct or raw_ct in ("application/octet-stream", "binary/octet-stream"):
        raw_ct = "video/mp4" if filename.endswith((".m4s", ".mp4")) else "video/mp2t"

    async def _stream():
        try:
            async for chunk in r.aiter_bytes(chunk_size=65536):
                yield chunk
        finally:
            await r.aclose()

    return StreamingResponse(_stream(), media_type=raw_ct, status_code=r.status_code)


@router.get("/video/{filename}")
async def proxy_video(request: Request, filename: str, url: str, ref: str = ""):
    """Stream a direct video file through the proxy with Referer; forwards Range for seeking."""
    req_headers: dict[str, str] = {}
    if ref:
        req_headers["Referer"] = ref
    range_hdr = request.headers.get("range")
    if range_hdr:
        req_headers["Range"] = range_hdr

    r = await _client.send(_client.build_request("GET", url, headers=req_headers), stream=True)
    ct = r.headers.get("content-type", "video/mp4").split(";")[0]
    resp_headers: dict[str, str] = {"Accept-Ranges": "bytes"}
    for h in ("content-range", "content-length"):
        if h in r.headers:
            resp_headers[h.title()] = r.headers[h]

    async def _stream():
        try:
            async for chunk in r.aiter_bytes(chunk_size=65536):
                yield chunk
        finally:
            await r.aclose()

    return StreamingResponse(
        _stream(), media_type=ct, status_code=r.status_code, headers=resp_headers
    )
