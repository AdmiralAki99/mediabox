import asyncio
import json

from fastapi import APIRouter, Depends, HTTPException

from models.schemas import CastMember, Episode, Review, SearchResponse, Season, Series, SeriesMeta
from services.tmdb import TMDBService

router = APIRouter(prefix="/series", tags=["Series"])


def get_tmdb_service() -> TMDBService:
    from main import tmdb_service
    return tmdb_service


@router.get("/search", response_model=SearchResponse[Series])
async def search_series(
    q: str,
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Series]:
    results = await service.search_series(q)
    return SearchResponse(results=results, total=len(results))


@router.get("/trending", response_model=SearchResponse[Series])
async def trending_series(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Series]:
    results = await service.get_trending_series()
    return SearchResponse(results=results, total=len(results))


@router.get("/{series_id}/meta", response_model=SeriesMeta)
async def series_meta(
    series_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> SeriesMeta:
    return await service.get_series_meta(series_id)


@router.get("/{tmdb_id}/seasons", response_model=list[Season])
async def get_seasons(
    tmdb_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> list[Season]:
    return await service.get_seasons(tmdb_id)


@router.get("/{tmdb_id}/seasons/{season_number}/episodes", response_model=list[Episode])
async def get_episodes(
    tmdb_id: int,
    season_number: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> list[Episode]:
    return await service.get_episodes(tmdb_id, season_number)


@router.get("/{series_id}/credits", response_model=list[CastMember])
async def series_credits(
    series_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> list[CastMember]:
    return await service.get_series_credits(series_id)


@router.get("/{series_id}/reviews", response_model=list[Review])
async def series_reviews(
    series_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> list[Review]:
    return await service.get_series_reviews(series_id)


@router.get("/{series_id}/trailer")
async def series_trailer(
    series_id: int,
    service: TMDBService = Depends(get_tmdb_service),
):
    key = await service.get_trailer_key(series_id, "tv")
    if not key:
        raise HTTPException(status_code=404, detail="No trailer found")
    try:
        proc = await asyncio.create_subprocess_exec(
            "yt-dlp", "-j", "--no-playlist",
            "-f", "bestvideo[ext=mp4][height<=720]+bestaudio[ext=m4a]/best[ext=mp4][height<=720]/best",
            f"https://www.youtube.com/watch?v={key}",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="yt-dlp not installed on server")
    stdout, _ = await proc.communicate()
    if proc.returncode != 0:
        raise HTTPException(status_code=502, detail="Failed to resolve trailer stream")
    info = json.loads(stdout)
    url = info.get("url") or (info.get("formats") or [{}])[-1].get("url")
    if not url:
        raise HTTPException(status_code=502, detail="No stream URL in yt-dlp output")
    return {"url": url, "title": info.get("title", "Trailer"), "key": key}
