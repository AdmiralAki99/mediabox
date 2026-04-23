import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from models.schemas import Match, Sport, SportStream, SportStreamResolved
from services.sports import SportsService

router = APIRouter(prefix="/sports", tags=["Sports"])

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)


def get_sports_service() -> SportsService:
    from main import sports_service
    return sports_service


def get_sports_http() -> httpx.AsyncClient:
    from main import _sports_http
    return _sports_http


@router.get("", response_model=list[Sport])
async def list_sports(
    service: SportsService = Depends(get_sports_service),
) -> list[Sport]:
    try:
        return await service.get_sports()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Sports API error: {exc}")


@router.get("/resolve/{match_id}/{source_id}", response_model=SportStreamResolved)
async def resolve_sport_stream(
    match_id: str,
    source_id: str,
    service: SportsService = Depends(get_sports_service),
) -> SportStreamResolved:
    try:
        result = await service.resolve_sport_stream(match_id, source_id)
        if not result.urls:
            raise HTTPException(status_code=404, detail="No stream URLs captured — match may not be live")
        return result
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Stream resolve error: {exc}")


@router.get("/proxy")
async def proxy_sports_hls(
    url: str = Query(..., description="HLS segment or manifest URL to proxy"),
    referrer: str = Query("", description="Referer header to send to the CDN"),
    client: httpx.AsyncClient = Depends(get_sports_http),
) -> StreamingResponse:
    headers: dict[str, str] = {"User-Agent": _UA}
    if referrer:
        headers["Referer"] = referrer
        # Strip trailing slash for Origin
        headers["Origin"] = referrer.rstrip("/")

    try:
        req = client.build_request("GET", url, headers=headers)
        resp = await client.send(req, stream=True, follow_redirects=True)
        resp.raise_for_status()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Upstream CDN error: {exc}")

    content_type = resp.headers.get("content-type", "application/octet-stream")
    # Always allow cross-origin so HLS.js can consume the response
    extra = {"Access-Control-Allow-Origin": "*"}
    if "content-length" in resp.headers:
        extra["content-length"] = resp.headers["content-length"]

    async def _iter():
        try:
            async for chunk in resp.aiter_bytes(65536):
                yield chunk
        except httpx.HTTPError:
            pass
        finally:
            await resp.aclose()

    return StreamingResponse(_iter(), media_type=content_type, headers=extra)


# Must come before /{sport_id}/matches — "stream" is a literal path segment here
@router.get("/stream/{match_id}/{source_id}", response_model=SportStream)
async def get_sport_stream(
    match_id: str,
    source_id: str,
    service: SportsService = Depends(get_sports_service),
) -> SportStream:
    try:
        return await service.get_stream(match_id, source_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Sports API error: {exc}")


@router.get("/{sport_id}/matches", response_model=list[Match])
async def list_matches(
    sport_id: str,
    service: SportsService = Depends(get_sports_service),
) -> list[Match]:
    try:
        return await service.get_matches(sport_id)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Sports API error: {exc}")
