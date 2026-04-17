"""
Anime router.

/anime/search              → AllAnimeService (streaming provider)
/anime/tmdb/search         → TMDB (posters, descriptions, ratings)
/anime/tmdb/trending       → TMDB
/anime/tmdb/top-rated      → TMDB
/anime/tmdb/airing-now     → TMDB
/anime/tmdb/action         → TMDB

/anime/{provider}/{id}/info
/anime/{provider}/{id}/episodes
/anime/{provider}/{id}/stream/{episode}

ROUTE ORDER IS IMPORTANT: concrete paths (/search, /tmdb/*) must be
registered before the parameterised paths (/{provider}/...) or FastAPI
will greedily match "tmdb" as a provider name.
"""

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query

from models.schemas import (
    AiringScheduleEntry,
    AnimeEpisode,
    AnimeInfo,
    AnimeSearchResult,
    AnimeStream,
    SearchResponse,
    Series,
)
from services.allanime import AllAnimeService
from services.tmdb import TMDBService

router = APIRouter(prefix="/anime", tags=["Anime"])


def get_allanime_service() -> AllAnimeService:
    from main import allanime_service
    return allanime_service


def get_tmdb_service() -> TMDBService:
    from main import tmdb_service
    return tmdb_service


@router.get("/schedule", response_model=list[AiringScheduleEntry])
async def get_anime_schedule(
    offset_days: int = Query(0, ge=0, le=6, description="0=today, 1=tomorrow, etc."),
) -> list[AiringScheduleEntry]:
    from datetime import datetime, timezone, timedelta
    now = datetime.now(timezone.utc)
    day_start = (now + timedelta(days=offset_days)).replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = day_start + timedelta(days=1)
    start_ts = int(day_start.timestamp())
    end_ts = int(day_end.timestamp())

    query = """
    query ($start: Int, $end: Int) {
      Page(perPage: 50) {
        airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
          airingAt
          episode
          media {
            id
            title { romaji english }
            coverImage { large }
            genres
            episodes
            status
          }
        }
      }
    }
    """
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://graphql.anilist.co",
            json={"query": query, "variables": {"start": start_ts, "end": end_ts}},
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()

    entries = data.get("data", {}).get("Page", {}).get("airingSchedules", [])
    result = []
    for e in entries:
        media = e.get("media") or {}
        title_obj = media.get("title") or {}
        result.append(AiringScheduleEntry(
            media_id=media.get("id", 0),
            title=title_obj.get("english") or title_obj.get("romaji") or "Unknown",
            cover_image=((media.get("coverImage") or {}).get("large")),
            episode=e.get("episode", 0),
            airing_at=e.get("airingAt", 0),
            total_episodes=media.get("episodes"),
            genres=(media.get("genres") or [])[:3],
            status=media.get("status") or "",
        ))
    return result


@router.get("/search", response_model=SearchResponse[AnimeSearchResult])
async def search_anime(
    q: str = Query(..., min_length=1),
    language: str = Query("sub", pattern="^(sub|dub)$"),
    service: AllAnimeService = Depends(get_allanime_service),
) -> SearchResponse[AnimeSearchResult]:
    results = await service.search(q, language)
    return SearchResponse(results=results, total=len(results))


@router.get("/tmdb/search", response_model=SearchResponse[Series])
async def search_anime_tmdb(
    q: str = Query(..., min_length=1),
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Series]:
    results = await service.search_anime(q)
    return SearchResponse(results=results, total=len(results))


@router.get("/tmdb/trending", response_model=SearchResponse[Series])
async def trending_anime_tmdb(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Series]:
    results = await service.get_trending_anime()
    return SearchResponse(results=results, total=len(results))


@router.get("/tmdb/top-rated", response_model=SearchResponse[Series])
async def top_rated_anime_tmdb(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Series]:
    results = await service.get_top_rated_anime()
    return SearchResponse(results=results, total=len(results))


@router.get("/tmdb/airing-now", response_model=SearchResponse[Series])
async def airing_now_anime_tmdb(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Series]:
    results = await service.get_airing_now_anime()
    return SearchResponse(results=results, total=len(results))


@router.get("/tmdb/action", response_model=SearchResponse[Series])
async def action_anime_tmdb(
    service: TMDBService = Depends(get_tmdb_service),
) -> SearchResponse[Series]:
    results = await service.get_action_anime()
    return SearchResponse(results=results, total=len(results))


# {provider} in the URL is kept for compatibility but only "allanime" is wired up

@router.get("/{provider}/{identifier}/info", response_model=AnimeInfo)
async def get_anime_info(
    provider: str,  # noqa: ARG001 — kept for URL compatibility, only "allanime" supported
    identifier: str,
    service: AllAnimeService = Depends(get_allanime_service),
) -> AnimeInfo:
    return await service.get_info(identifier)


@router.get("/{provider}/{identifier}/episodes", response_model=list[AnimeEpisode])
async def get_anime_episodes(
    provider: str,  # noqa: ARG001
    identifier: str,
    language: str = Query("sub", pattern="^(sub|dub)$"),
    service: AllAnimeService = Depends(get_allanime_service),
) -> list[AnimeEpisode]:
    try:
        return await service.get_episodes(identifier, language)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"AllAnime error: {exc}")


@router.get("/{provider}/{identifier}/stream/{episode}", response_model=list[AnimeStream])
async def get_anime_stream(
    provider: str,  # noqa: ARG001
    identifier: str,
    episode: float,
    language: str = Query("sub", pattern="^(sub|dub)$"),
    service: AllAnimeService = Depends(get_allanime_service),
) -> list[AnimeStream]:
    try:
        streams = await service.get_streams(identifier, episode, language)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"AllAnime error: {exc}")

    if not streams:
        raise HTTPException(
            status_code=404,
            detail=f"No streams found for episode {episode} ({language})",
        )
    return streams
