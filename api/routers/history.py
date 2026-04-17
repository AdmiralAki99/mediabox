from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.db_models import HistoryItem
from models.schemas import HistoryItemCreate, HistoryItemResponse

router = APIRouter(prefix="/history", tags=["History"])


@router.get("", response_model=list[HistoryItemResponse])
async def get_history(
    media_type: str | None = None,   # optional ?media_type= filter
    db: AsyncSession = Depends(get_db),
) -> list[HistoryItemResponse]:
    query = select(HistoryItem).order_by(HistoryItem.watched_at.desc()).limit(100)
    if media_type:
        query = query.where(HistoryItem.media_type == media_type)
    result = await db.execute(query)
    rows = result.scalars().all()
    return [HistoryItemResponse.model_validate(row) for row in rows]


@router.post("", response_model=HistoryItemResponse, status_code=201)
async def upsert_history(
    payload: HistoryItemCreate,
    db: AsyncSession = Depends(get_db),
) -> HistoryItemResponse:
    # Build a query to find an existing row for this exact content.
    # We match on all the identifier fields — whichever are set.
    query = select(HistoryItem).where(
        HistoryItem.media_type == payload.media_type,
        HistoryItem.tmdb_id == payload.tmdb_id,
        HistoryItem.anime_provider_id == payload.anime_provider_id,
        HistoryItem.manga_id == payload.manga_id,
        HistoryItem.season_num == payload.season_num,
        HistoryItem.episode_num == payload.episode_num,
        HistoryItem.chapter_id == payload.chapter_id,
    )
    result = await db.execute(query)
    existing = result.scalars().first()

    if existing:
        # Update the fields that can change over time
        existing.progress_seconds = payload.progress_seconds
        existing.completed = payload.completed
        existing.title = payload.title
        existing.page_index = payload.page_index
        item = existing
    else:
        # First time seeing this content — create a new row
        item = HistoryItem(**payload.model_dump())
        db.add(item)

    await db.commit()
    await db.refresh(item)  # reload from DB so watched_at reflects the DB value
    return HistoryItemResponse.model_validate(item)


@router.get("/chapter/{chapter_id}", response_model=HistoryItemResponse | None)
async def get_chapter_bookmark(
    chapter_id: str,
    db: AsyncSession = Depends(get_db),
) -> HistoryItemResponse | None:
    result = await db.execute(
        select(HistoryItem).where(HistoryItem.chapter_id == chapter_id)
            .order_by(HistoryItem.watched_at.desc())
    )
    item = result.scalars().first()
    return HistoryItemResponse.model_validate(item) if item else None


@router.delete("/{item_id}", status_code=204)
async def delete_history_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
) -> None:
    result = await db.execute(select(HistoryItem).where(HistoryItem.id == item_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="History item not found")
    await db.delete(item)
    await db.commit()


@router.delete("", status_code=200)
async def clear_history(
    db: AsyncSession = Depends(get_db),
) -> dict:
    result = await db.execute(delete(HistoryItem))
    await db.commit()
    return {"deleted": result.rowcount}
