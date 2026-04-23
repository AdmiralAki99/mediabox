from typing import Optional
from urllib.parse import quote, urljoin

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse, Response

from models.schemas import MediaStream
from services.moviesapi import MoviesAPIService

router = APIRouter(prefix="/stream", tags=["Stream"])

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)


def get_http_client() -> httpx.AsyncClient:
    from main import stream_service
    return stream_service._http


def get_moviesapi_service() -> MoviesAPIService:
    from main import moviesapi_service
    return moviesapi_service


def _proxy_uri(uri: str, base_url: str, referer: Optional[str]) -> str:
    abs_url = uri if uri.startswith(("http://", "https://")) else urljoin(base_url, uri)
    result = f"/api/stream/proxy?url={quote(abs_url, safe='')}"
    if referer:
        result += f"&referer={quote(referer, safe='')}"
    return result


def _proxy_m3u8(content: str, base_url: str, referer: Optional[str]) -> str:
    import re
    lines = content.splitlines()
    out: list[str] = []

    for line in lines:
        s = line.strip()
        if not s:
            out.append(line)
        elif s.startswith("#"):
            # Rewrite URI="" in EXT-X-KEY, EXT-X-MAP, etc.
            out.append(re.sub(
                r'URI="([^"]*)"',
                lambda m: f'URI="{_proxy_uri(m.group(1), base_url, referer)}"',
                s,
            ))
        else:
            # Segment URL or variant playlist URL
            out.append(_proxy_uri(s, base_url, referer))

    return "\n".join(out)


@router.get("/proxy")
async def stream_proxy(
    url: str = Query(...),
    referer: Optional[str] = Query(None),
    client: httpx.AsyncClient = Depends(get_http_client),
) -> Response:
    headers: dict[str, str] = {"User-Agent": _UA}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")

    try:
        resp = await client.get(url, headers=headers, timeout=15, follow_redirects=True)
    except httpx.HTTPError:
        return RedirectResponse(url=url, status_code=302)

    ct = resp.headers.get("content-type", "")
    is_m3u8 = "mpegurl" in ct.lower() or url.lower().split("?")[0].endswith(".m3u8")

    if is_m3u8:
        body = _proxy_m3u8(resp.text, url, referer)
        return Response(body.encode(), status_code=resp.status_code,
                        media_type="application/vnd.apple.mpegurl")

    return Response(resp.content, status_code=resp.status_code,
                    media_type=ct or "application/octet-stream")


@router.get("/movie/{tmdb_id}", response_model=list[MediaStream])
async def resolve_movie_stream(
    tmdb_id: int,
    title: Optional[str] = Query(None),   # kept for frontend compat, not used
    year: Optional[str] = Query(None),     # kept for frontend compat, not used
    service: MoviesAPIService = Depends(get_moviesapi_service),
) -> list[MediaStream]:
    streams = await service.resolve_movie(tmdb_id)
    if not streams:
        raise HTTPException(status_code=404, detail="No streams resolved for this movie")
    return streams


@router.get("/series/{tmdb_id}/{season}/{episode}", response_model=list[MediaStream])
async def resolve_series_stream(
    tmdb_id: int,
    season: int,
    episode: int,
    title: Optional[str] = Query(None),   # kept for frontend compat, not used
    year: Optional[str] = Query(None),     # kept for frontend compat, not used
    service: MoviesAPIService = Depends(get_moviesapi_service),
) -> list[MediaStream]:
    streams = await service.resolve_tv(tmdb_id, season, episode)
    if not streams:
        raise HTTPException(status_code=404, detail="No streams resolved for this episode")
    return streams
