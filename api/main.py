import asyncio
import logging
import time
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import settings
from database import init_db
from services.allanime import AllAnimeService
from services.anipy import AnipyService
from services.arxiv import ArxivService
from services.gutenberg import GutenbergService
from services.rco import ReadComicService
from services.zlib import ZlibService
from services.mangadex import MangaDexService
from services.moviesapi import MoviesAPIService
from services.sports import SportsService
from services.stream import StreamService
from services.tmdb import TMDBService

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("mediabox")

tmdb_service: TMDBService
stream_service: StreamService
allanime_service: AllAnimeService
anipy_service: AnipyService  # only used in the downloads router
moviesapi_service: MoviesAPIService
mangadex_service: MangaDexService
rco_service: ReadComicService
sports_service: SportsService
gutenberg_service: GutenbergService
zlib_service: ZlibService
arxiv_service: ArxivService
_books_http: httpx.AsyncClient
_sports_http: httpx.AsyncClient
_arxiv_http: httpx.AsyncClient


@asynccontextmanager
async def lifespan(app: FastAPI):
    global tmdb_service, stream_service, allanime_service, anipy_service, moviesapi_service, mangadex_service, rco_service, sports_service, gutenberg_service, zlib_service, arxiv_service, _books_http, _sports_http, _arxiv_http
    await init_db()
    Path(settings.DOWNLOAD_DIR).mkdir(parents=True, exist_ok=True)
    tmdb_service = TMDBService()
    _stream_http = httpx.AsyncClient()
    stream_service = StreamService(_stream_http)
    _allanime_http = httpx.AsyncClient()
    allanime_service = AllAnimeService(_allanime_http)
    anipy_service = AnipyService()
    _moviesapi_http = httpx.AsyncClient()
    moviesapi_service = MoviesAPIService(_moviesapi_http)
    mangadex_service = MangaDexService()
    rco_service = ReadComicService()
    sports_service = SportsService()
    _books_http = httpx.AsyncClient()
    gutenberg_service = GutenbergService(_books_http)
    zlib_service = ZlibService()
    # do this in the background, zlib login can be slow and isn't critical for startup
    asyncio.create_task(zlib_service.login(settings.ZLIB_EMAIL, settings.ZLIB_PASSWORD))
    _sports_http = httpx.AsyncClient(timeout=120)  # sports HLS proxying needs extra time
    _arxiv_http = httpx.AsyncClient(headers={"User-Agent": "mediabox/0.1 (personal)"})
    arxiv_service = ArxivService(_arxiv_http)
    logger.info("Mediabox API started")
    yield
    await tmdb_service.close()
    await _stream_http.aclose()
    await _allanime_http.aclose()
    await _moviesapi_http.aclose()
    await mangadex_service.close()
    await rco_service.close()
    await sports_service.close()
    await zlib_service.close()
    await _books_http.aclose()
    await _sports_http.aclose()
    await _arxiv_http.aclose()
    logger.info("Mediabox API stopped")


app = FastAPI(title="Mediabox API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.monotonic()
    try:
        response = await call_next(request)
    except Exception:
        duration_ms = (time.monotonic() - start) * 1000
        logger.exception("%s %s → 500 (%.0fms)", request.method, request.url.path, duration_ms)
        raise
    duration_ms = (time.monotonic() - start) * 1000
    logger.info("%s %s → %d (%.0fms)", request.method, request.url.path, response.status_code, duration_ms)
    return response


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled %s on %s %s", type(exc).__name__, request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


from routers import anime, arxiv, books, cast, comics, downloads, history, manga, movies, proxy, series, settings_router, sports, stream, weather  # noqa: E402

app.include_router(movies.router)
app.include_router(series.router)
app.include_router(anime.router)
app.include_router(manga.router)
app.include_router(comics.router)
app.include_router(downloads.router)
app.include_router(history.router)
app.include_router(stream.router)
app.include_router(sports.router)
app.include_router(books.router)
app.include_router(arxiv.router)
app.include_router(cast.router)
app.include_router(proxy.router)
app.include_router(weather.router)
app.include_router(settings_router.router)


@app.get("/health", tags=["Health"])
async def health() -> dict:
    return {"status": "ok", "version": "0.1.0"}
