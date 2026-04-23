import json
import logging
import urllib.parse

import httpx
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from models.schemas import MediaStream

logger = logging.getLogger(__name__)

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

_BASE_MA          = "https://ww2.moviesapi.to"
_BASE_FX          = "https://flixcdn.cyou"
_BASE_MOV2DAY_CDN = "https://cdn.mov2day.xyz"

_AES_KEY = bytes.fromhex("6b69656d7469656e6d75613931316361")  # kiemtienmua911ca
_AES_IV  = bytes.fromhex("313233343536373839306f6975797472")  # 1234567890oiuytr


def _decrypt(raw: bytes) -> dict:
    hex_str = raw.decode("ascii").strip()
    binary  = bytes.fromhex(hex_str)
    cipher  = Cipher(algorithms.AES(_AES_KEY), modes.CBC(_AES_IV), backend=default_backend())
    decryptor = cipher.decryptor()
    padded  = decryptor.update(binary) + decryptor.finalize()
    # PKCS7 unpad
    pad_len = padded[-1]
    return json.loads(padded[:-pad_len])


def _parse_fragment(video_url: str) -> tuple[str, list[str]]:
    if "#" not in video_url:
        raise ValueError(f"moviesapi returned no embed fragment — content likely unavailable: {video_url!r}")
    fragment = video_url.split("#", 1)[1]
    embed_id = fragment.split("&")[0]

    subs_raw = ""
    if "&" in fragment:
        qs = urllib.parse.parse_qs(fragment.split("&", 1)[1])
        subs_raw = qs.get("subs", ["[]"])[0]

    try:
        subs_list = json.loads(urllib.parse.unquote(subs_raw))
    except Exception:
        subs_list = []

    sub_urls: list[str] = []
    for s in subs_list:
        label   = s.get("label", "").lower()
        default = s.get("default", False)
        url     = s.get("url", "")
        if url and ("english" in label or default):
            sub_urls.append(url)

    return embed_id, sub_urls


class MoviesAPIService:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self._http = client

    def _headers_for(self, origin: str) -> dict[str, str]:
        return {
            "User-Agent": _UA,
            "Referer":    origin + "/",
            "Origin":     origin,
        }

    async def _fetch_video_data(self, embed_id: str) -> dict:
        url = f"{_BASE_FX}/api/v1/video?id={embed_id}"
        r = await self._http.get(url, headers=self._headers_for(_BASE_FX), timeout=15)
        r.raise_for_status()
        return _decrypt(r.content)

    async def _resolve_mov2day(self, video_url: str) -> list[MediaStream]:
        import re

        # Step 1: cdn embed URL (skip the player.mov2day.xyz shell page)
        parts     = video_url.rstrip("/").split("/")
        suffix    = "/".join(parts[-4:])   # e.g. tv/10085/1/1
        embed_cdn = f"{_BASE_MOV2DAY_CDN}/embed/{suffix}"

        cdn_hdrs = {**self._headers_for("https://player.mov2day.xyz"), "Accept": "text/html,*/*"}
        cdn_r = await self._http.get(embed_cdn, headers=cdn_hdrs, timeout=12, follow_redirects=True)

        # Step 2: extract iframe src (brightpathsignals.com embed URL)
        iframes = re.findall(r'<iframe[^>]+src=["\']([^"\']+)["\']', cdn_r.text)
        if not iframes:
            logger.warning("mov2day: no iframe in cdn embed %s", embed_cdn)
            return []
        bps_url    = iframes[0]
        bps_origin = "/".join(bps_url.split("/")[:3])   # https://brightpathsignals.com

        # Step 3: fetch brightpathsignals.com player page and extract CONFIG
        bps_hdrs = {**self._headers_for(_BASE_MOV2DAY_CDN), "Accept": "text/html,*/*"}
        bps_r = await self._http.get(bps_url, headers=bps_hdrs, timeout=12, follow_redirects=True)

        cfg_match = re.search(r'const CONFIG\s*=\s*(\{[\s\S]*?\});', bps_r.text)
        if not cfg_match:
            logger.warning("mov2day: no CONFIG block in %s", bps_url)
            return []
        config = json.loads(cfg_match.group(1))
        logger.debug("mov2day CONFIG for %s: sources=%s token=%s...",
                     suffix, config.get("availableSources"), str(config.get("playToken", ""))[:12])

        # Step 4: call the source API to get the stream URL
        src_path  = config.get("sourceApiUrl", "/embed/source-api.php")
        src_url   = bps_origin + src_path if src_path.startswith("/") else src_path
        sources   = config.get("availableSources") or ["justhd"]

        api_hdrs = {
            **self._headers_for(bps_origin),
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "application/json, */*",
        }

        stream_url = ""
        for source in sources:
            # API expects the ID as "tmdb" or "imdb" key, not "mediaId"
            id_key = config.get("idType", "tmdb")   # "tmdb" or "imdb"
            params = {
                "source":      source,
                "mediaType":   config.get("mediaType", "tv"),
                id_key:        config.get("mediaId"),
                "season":      config.get("season", ""),
                "episode":     config.get("episode", ""),
                "playToken":   config.get("playToken", ""),
                "playTokenTs": config.get("playTokenTs", ""),
            }
            api_r = await self._http.get(src_url, params=params, headers=api_hdrs, timeout=15)
            logger.debug("mov2day source API [%s] → %d: %r", source, api_r.status_code, api_r.text[:300])

            if api_r.status_code == 404:
                logger.debug("mov2day: source '%s' has no entry for this content", source)
                continue
            if api_r.status_code != 200:
                logger.warning("mov2day: source API [%s] unexpected %d", source, api_r.status_code)
                continue

            # Parse JSON — look for stream URL under common keys
            try:
                data = api_r.json()
            except Exception:
                # Might be a raw m3u8 URL or non-JSON
                m3u8s = re.findall(r'(https?://[^\s"\'`<>]+\.m3u8[^\s"\'`<>]*)', api_r.text)
                if m3u8s:
                    stream_url = m3u8s[0]
                    break
                continue

            stream_url = (
                data.get("url") or
                data.get("stream") or
                data.get("link") or
                data.get("src") or
                (data.get("sources") or [{}])[0].get("file") or
                (data.get("sources") or [{}])[0].get("src") or
                ""
            )
            if stream_url:
                break

        if not stream_url:
            logger.warning("mov2day: no stream URL resolved from %s (sources=%s)", bps_url, sources)
            return []

        logger.info("mov2day: resolved %s → %s", suffix, stream_url[:80])
        return [MediaStream(url=stream_url, subtitles=[], referrer=bps_origin + "/")]

    async def resolve_movie(self, tmdb_id: int) -> list[MediaStream]:
        url = f"{_BASE_MA}/api/movie/{tmdb_id}"
        r = await self._http.get(url, headers=self._headers_for(_BASE_MA), timeout=15)
        r.raise_for_status()

        ma = r.json()
        try:
            embed_id, sub_urls = _parse_fragment(ma.get("video_url", ""))
        except ValueError as e:
            logger.warning("movie %d: %s", tmdb_id, e)
            alt_url = ma.get("video_url", "")
            if "mov2day.xyz" in alt_url:
                return await self._resolve_mov2day(alt_url)
            return []
        logger.debug("movie %d → embed_id=%s  subs=%d", tmdb_id, embed_id, len(sub_urls))

        video_data = await self._fetch_video_data(embed_id)
        source = video_data.get("source", "")
        if not source:
            logger.warning("movie %d: decrypted response has no 'source' key", tmdb_id)
            return []

        return [MediaStream(
            url       = source,
            subtitles = sub_urls,
            referrer  = _BASE_FX + "/",
        )]

    async def resolve_tv(self, tmdb_id: int, season: int, episode: int) -> list[MediaStream]:
        url = f"{_BASE_MA}/api/tv/{tmdb_id}/{season}/{episode}"
        r = await self._http.get(url, headers=self._headers_for(_BASE_MA), timeout=15)
        r.raise_for_status()

        ma = r.json()
        try:
            embed_id, sub_urls = _parse_fragment(ma.get("video_url", ""))
        except ValueError as e:
            logger.warning("tv %d S%02dE%02d: %s", tmdb_id, season, episode, e)
            alt_url = ma.get("video_url", "")
            if "mov2day.xyz" in alt_url:
                return await self._resolve_mov2day(alt_url)
            return []
        logger.debug(
            "tv %d S%02dE%02d → embed_id=%s  subs=%d",
            tmdb_id, season, episode, embed_id, len(sub_urls),
        )

        video_data = await self._fetch_video_data(embed_id)
        source = video_data.get("source", "")
        if not source:
            logger.warning(
                "tv %d S%02dE%02d: decrypted response has no 'source' key",
                tmdb_id, season, episode,
            )
            return []

        return [MediaStream(
            url       = source,
            subtitles = sub_urls,
            referrer  = _BASE_FX + "/",
        )]
