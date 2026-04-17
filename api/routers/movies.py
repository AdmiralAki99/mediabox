import asyncio
import json

from fastapi import APIRouter, Depends, HTTPException

from models.schemas import CastMember, Movie, MovieMeta, Review, SearchResponse
from services.tmdb import TMDBService

router = APIRouter(prefix="/movies", tags=["Movies"])


def get_tmdb_service() -> TMDBService:
    from main import tmdb_service
    return tmdb_service


@router.get("/search", response_model=SearchResponse[Movie])
async def search_movies(
    q: str,
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Movie]:
    results = await service.search_movies(q)
    return SearchResponse(results=results, total=len(results))


@router.get("/trending", response_model=SearchResponse[Movie])
async def trending_movies(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Movie]:
    results = await service.get_trending_movies()
    return SearchResponse(results=results, total=len(results))


@router.get("/upcoming", response_model=SearchResponse[Movie])
async def upcoming_movies(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Movie]:
    results = await service.get_upcoming_movies()
    return SearchResponse(results=results, total=len(results))


@router.get("/now-playing", response_model=SearchResponse[Movie])
async def now_playing_movies(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Movie]:
    results = await service.get_now_playing_movies()
    return SearchResponse(results=results, total=len(results))


@router.get("/top-rated", response_model=SearchResponse[Movie])
async def top_rated_movies(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Movie]:
    results = await service.get_top_rated_movies()
    return SearchResponse(results=results, total=len(results))


@router.get("/genre/{genre_id}", response_model=SearchResponse[Movie])
async def movies_by_genre(
    genre_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Movie]:
    results = await service.get_movies_by_genre(genre_id)
    return SearchResponse(results=results, total=len(results))


@router.get("/{movie_id}/meta", response_model=MovieMeta)
async def movie_meta(
    movie_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> MovieMeta:
    return await service.get_movie_meta(movie_id)


@router.get("/{movie_id}/credits", response_model=list[CastMember])
async def movie_credits(
    movie_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> list[CastMember]:
    return await service.get_movie_credits(movie_id)


@router.get("/{movie_id}/reviews", response_model=list[Review])
async def movie_reviews(
    movie_id: int,
    service: TMDBService = Depends(get_tmdb_service),
) -> list[Review]:
    return await service.get_movie_reviews(movie_id)


@router.get("/{movie_id}/trailer")
async def movie_trailer(
    movie_id: int,
    service: TMDBService = Depends(get_tmdb_service),
):
    key = await service.get_trailer_key(movie_id, "movie")
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
