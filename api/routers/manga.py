"""
Manga router — search, chapter listing, and page URLs via MangaDex.

Route order matters:
  GET /search                    — concrete path, no conflict
  GET /chapter/{id}/pages        — "chapter" literal MUST come before /{manga_id}/...
  GET /{manga_id}/chapters       — parameterized; would swallow "chapter" if declared first
"""

from fastapi import APIRouter, Depends, HTTPException, Query

from models.schemas import Chapter, ChapterPage, MangaResult, MangaUpdateEntry, SearchResponse
from services.mangadex import MangaDexService

router = APIRouter(prefix="/manga", tags=["Manga"])


def get_mangadex_service() -> MangaDexService:
    from main import mangadex_service
    return mangadex_service


@router.get("/popular", response_model=SearchResponse[MangaResult])
async def popular_manga(
    limit: int = Query(20, ge=1, le=50),
    service: MangaDexService = Depends(get_mangadex_service),
) -> SearchResponse[MangaResult]:
    results = await service.get_popular_manga(limit)
    return SearchResponse(results=results, total=len(results))


@router.get("/top-rated", response_model=SearchResponse[MangaResult])
async def top_rated_manga(
    limit: int = Query(20, ge=1, le=50),
    service: MangaDexService = Depends(get_mangadex_service),
) -> SearchResponse[MangaResult]:
    results = await service.get_top_rated_manga(limit)
    return SearchResponse(results=results, total=len(results))


@router.get("/genre/{genre}", response_model=SearchResponse[MangaResult])
async def manga_by_genre(
    genre: str,
    limit: int = Query(20, ge=1, le=50),
    service: MangaDexService = Depends(get_mangadex_service),
) -> SearchResponse[MangaResult]:
    results = await service.get_manga_by_genre(genre, limit)
    return SearchResponse(results=results, total=len(results))


@router.get("/search", response_model=SearchResponse[MangaResult])
async def search_manga(
    q: str = Query(..., min_length=1, description="Manga title to search for"),
    limit: int = Query(20, ge=1, le=100, description="Number of results (max 100)"),
    service: MangaDexService = Depends(get_mangadex_service),
) -> SearchResponse[MangaResult]:
    """
    Search MangaDex for manga by title.

    Cover images are included in the response — no extra requests needed.
    Results are ordered by followed count (popularity).
    """
    results = await service.search_manga(q, limit)
    return SearchResponse(results=results, total=len(results))


@router.get("/latest", response_model=SearchResponse[MangaResult])
async def latest_manga(
    limit: int = Query(20, ge=1, le=50),
    service: MangaDexService = Depends(get_mangadex_service),
) -> SearchResponse[MangaResult]:
    results = await service.get_latest_manga(limit)
    return SearchResponse(results=results, total=len(results))


@router.get("/updates", response_model=list[MangaUpdateEntry])
async def manga_updates(
    limit: int = Query(30, ge=5, le=50),
    service: MangaDexService = Depends(get_mangadex_service),
) -> list[MangaUpdateEntry]:
    """Recent English chapter releases across all manga, with cover art."""
    return await service.get_recent_chapter_updates(limit)


# Must come before /{manga_id}/chapters or "chapter" gets matched as a manga_id
@router.get("/chapter/{chapter_id}/pages", response_model=list[ChapterPage])
async def get_chapter_pages(
    chapter_id: str,
    service: MangaDexService = Depends(get_mangadex_service),
) -> list[ChapterPage]:
    """
    Get all page image URLs for a chapter.

    URLs point to MangaDex's at-home CDN (geographically distributed).
    Pages are numbered 1-indexed and ordered correctly.

    - **chapter_id**: MangaDex chapter UUID (from GET /{manga_id}/chapters)
    """
    try:
        return await service.get_chapter_pages(chapter_id)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"MangaDex error: {exc}")


@router.get("/{manga_id}/chapters", response_model=list[Chapter])
async def get_chapters(
    manga_id: str,
    language: str = Query("en", description="Chapter language code, e.g. 'en', 'fr'"),
    service: MangaDexService = Depends(get_mangadex_service),
) -> list[Chapter]:
    """
    List available chapters for a manga in the requested language, sorted asc.

    External chapters (no hosted pages) are filtered out automatically.

    - **manga_id**: MangaDex manga UUID (from /manga/search)
    - **language**: ISO 639-1 language code (default: en)
    """
    try:
        return await service.get_chapters(manga_id, language)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"MangaDex error: {exc}")
