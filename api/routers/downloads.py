import asyncio
import re
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import AsyncSessionLocal, get_db
from models.db_models import Download
from models.schemas import DownloadRequest, DownloadStatus
from services.anipy import AnipyService

router = APIRouter(prefix="/downloads", tags=["Downloads"])

_cancelled: set[int] = set()


class DownloadCancelledError(Exception):
    pass



def get_anipy_service() -> AnipyService:
    from main import anipy_service
    return anipy_service


def _sanitize(name: str) -> str:
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name).strip() or "unknown"


def _episode_str(episode: float) -> str:
    return str(int(episode)) if episode == int(episode) else str(episode)


async def _update_download(download_id: int, **fields) -> None:
    async with AsyncSessionLocal() as session:
        row = await session.get(Download, download_id)
        if row is None:
            return  # row deleted (cancelled) — skip silently
        for key, value in fields.items():
            setattr(row, key, value)
        await session.commit()


async def _run_download(
    download_id: int,
    request: DownloadRequest,
    anipy: AnipyService,
) -> None:
    loop = asyncio.get_event_loop()
    await _update_download(download_id, status="downloading")

    # Build output directory and filename (no extension — Downloader adds it)
    title_dir = _sanitize(request.anime_title)
    ep_str = _episode_str(request.episode)
    filename = request.output_filename or f"episode_{ep_str}"
    output_dir = Path(settings.DOWNLOAD_DIR) / title_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / filename

    _last_pct: list[float] = [0.0]  # mutable container so the closure can write

    def progress_cb(pct: float) -> None:
        # Called from the worker thread — must not await directly
        if download_id in _cancelled:
            raise DownloadCancelledError(f"Download {download_id} cancelled")

        # Only write to DB when progress moves by ≥ 5% to limit SQLite churn
        if pct - _last_pct[0] >= 5.0 or pct >= 100.0:
            _last_pct[0] = pct
            asyncio.run_coroutine_threadsafe(
                _update_download(download_id, progress=round(pct, 1)),
                loop,
            )

    def info_cb(msg: str, exc_info=None) -> None:
        pass  # extend here to add structured logging if needed

    try:
        final_path = await anipy.download_episode(
            provider_name=request.provider_name,
            identifier=request.identifier,
            episode=request.episode,
            language=request.language,
            output_path=output_path,
            progress_callback=progress_cb,
            info_callback=info_cb,
        )
        await _update_download(
            download_id,
            status="completed",
            progress=100.0,
            file_path=str(final_path),
        )

    except DownloadCancelledError:
        # DELETE endpoint already cleaned up the DB record; just remove partial file
        partial = output_path.with_suffix(".mp4")
        if partial.exists():
            partial.unlink(missing_ok=True)
        _cancelled.discard(download_id)

    except Exception as exc:
        await _update_download(
            download_id,
            status="failed",
            error_message=str(exc)[:500],
        )



@router.post("", status_code=202, response_model=DownloadStatus)
async def queue_download(
    request: DownloadRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    anipy: AnipyService = Depends(get_anipy_service),
) -> DownloadStatus:
    row = Download(
        provider_name=request.provider_name,
        identifier=request.identifier,
        anime_title=request.anime_title,
        episode=request.episode,
        language=request.language,
        status="queued",
        progress=0.0,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)

    background_tasks.add_task(_run_download, row.id, request, anipy)
    return DownloadStatus.model_validate(row)


@router.get("", response_model=list[DownloadStatus])
async def list_downloads(
    db: AsyncSession = Depends(get_db),
) -> list[DownloadStatus]:
    result = await db.execute(
        select(Download).order_by(Download.created_at.desc())
    )
    rows = result.scalars().all()
    return [DownloadStatus.model_validate(r) for r in rows]


# NOTE: /file/{id} must come before /{id} — FastAPI matches routes top-to-bottom.
@router.get("/file/{download_id}")
async def get_download_file(
    download_id: int,
    db: AsyncSession = Depends(get_db),
) -> FileResponse:
    row = await db.get(Download, download_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Download not found")
    if row.status != "completed" or not row.file_path:
        raise HTTPException(status_code=409, detail=f"Download is {row.status}, not completed")
    path = Path(row.file_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail="File missing from disk")
    return FileResponse(path, media_type="video/mp4", filename=path.name)


@router.get("/{download_id}", response_model=DownloadStatus)
async def get_download(
    download_id: int,
    db: AsyncSession = Depends(get_db),
) -> DownloadStatus:
    row = await db.get(Download, download_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Download not found")
    return DownloadStatus.model_validate(row)


@router.delete("/{download_id}", status_code=204)
async def cancel_download(
    download_id: int,
    db: AsyncSession = Depends(get_db),
) -> None:
    row = await db.get(Download, download_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Download not found")

    if row.status == "downloading":
        _cancelled.add(download_id)  # signal the worker thread

    if row.status == "completed" and row.file_path:
        path = Path(row.file_path)
        path.unlink(missing_ok=True)
        # Remove the containing directory if it's now empty
        try:
            path.parent.rmdir()
        except OSError:
            pass  # directory not empty — leave it

    await db.delete(row)
    await db.commit()
