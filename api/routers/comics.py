from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from models.schemas import ChapterPage, ComicChapter, ComicResult, SearchResponse
from services.rco import ReadComicService, _BASE as RCO_BASE

router = APIRouter(prefix="/comics", tags=["Comics"])


def _get_rco() -> ReadComicService:
    from main import rco_service
    return rco_service


@router.get("/genre/{genre}", response_model=SearchResponse[ComicResult])
async def comics_by_genre(
    genre: str,
    svc: ReadComicService = Depends(_get_rco),
):
    results = await svc.get_comics_by_genre(genre)
    return SearchResponse(results=results, total=len(results))


@router.get("/search", response_model=SearchResponse[ComicResult])
async def search_comics(
    q: str = Query(..., min_length=1),
    svc: ReadComicService = Depends(_get_rco),
):
    results = await svc.search_comics(q)
    return SearchResponse(results=results, total=len(results))


@router.get("/image")
async def proxy_image(
    url: str = Query(...),
    svc: ReadComicService = Depends(_get_rco),
):
    _allowed = (RCO_BASE, "https://2.bp.blogspot.com/", "https://blogger.googleusercontent.com/")
    if not any(url.startswith(p) for p in _allowed):
        raise HTTPException(status_code=400, detail="Image host not allowed")
    resp = await svc._session.get(url, headers={"Referer": f"{RCO_BASE}/"})
    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail="Image fetch failed")
    content_type = resp.headers.get("content-type", "image/jpeg")
    return StreamingResponse(iter([resp.content]), media_type=content_type)


@router.get("/chapter/pages", response_model=list[ChapterPage])
async def get_chapter_pages(
    id: str = Query(..., description="Full issue href from chapter listing"),
    svc: ReadComicService = Depends(_get_rco),
):
    return await svc.get_chapter_pages(id)


@router.get("/{slug}/meta")
async def comic_meta(
    slug: str,
    svc: ReadComicService = Depends(_get_rco),
):
    return await svc.get_comic_meta(slug)


@router.get("/{slug}/chapters", response_model=list[ComicChapter])
async def get_chapters(
    slug: str,
    svc: ReadComicService = Depends(_get_rco),
):
    return await svc.get_chapters(slug)
