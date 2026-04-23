from datetime import datetime
from typing import Generic, Optional, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class Movie(BaseModel):
    id: int
    title: str
    overview: str
    release_date: str
    rating: float
    poster_path: Optional[str] = None


class SearchResponse(BaseModel, Generic[T]):
    results: list[T]
    total: int


class MovieMeta(BaseModel):
    backdrop_path: Optional[str] = None
    genres: list[str] = []
    runtime: Optional[int] = None
    overview: str = ""
    tagline: str = ""
    production_companies: list[str] = []
    budget: Optional[int] = None
    revenue: Optional[int] = None
    spoken_languages: list[str] = []


class SeriesMeta(BaseModel):
    backdrop_path: Optional[str] = None
    genres: list[str] = []
    status: Optional[str] = None
    last_air_date: Optional[str] = None
    overview: str = ""
    tagline: str = ""
    production_companies: list[str] = []
    networks: list[str] = []
    created_by: list[str] = []
    number_of_seasons: Optional[int] = None
    number_of_episodes: Optional[int] = None


class Review(BaseModel):
    author: str
    rating: Optional[float] = None
    content: str
    created_at: str


class CastMember(BaseModel):
    id: int
    name: str
    character: str
    profile_path: Optional[str] = None


class Series(BaseModel):
    id: int
    title: str
    overview: str
    first_air_date: str
    rating: float
    poster_path: Optional[str] = None
    country: Optional[str] = None


class Season(BaseModel):
    series_id: int         # parent — lets the frontend always know where this came from
    season_number: int
    title: str
    overview: str
    episode_count: int
    release_date: str


class Episode(BaseModel):
    episode_id: int
    episode_number: int
    season_number: int
    title: str
    overview: str
    release_date: str
    runtime: Optional[int] = None  # TMDB often omits this


class StreamResult(BaseModel):
    urls: list[str]
    subtitles: list[str]
    source_used: str
    total_sources: int


class MediaStream(BaseModel):
    url: str
    resolution: Optional[int] = None   # 1080, 720, 480, 360 — or None for non-HLS
    subtitles: list[str] = []          # VTT/SRT URLs from the embed provider
    referrer: Optional[str] = None     # Referer header required for HLS requests


class AnimeProvider(BaseModel):
    name: str        # e.g. "allanime", "animekai"
    identifier: str  # provider-specific opaque ID


class AnimeSearchResult(BaseModel):
    name: str
    providers: list[AnimeProvider]
    languages: list[str]  # e.g. ["sub", "dub"]


class AnimeEpisode(BaseModel):
    # float to handle specials like 5.5
    number: float


class AnimeStream(BaseModel):
    url: str
    resolution: Optional[int] = None  # width in pixels, e.g. 1080, 720
    language: str                     # "sub" or "dub"
    subtitles: list[str] = []         # external SRT/VTT URLs if provided by source
    referrer: Optional[str] = None    # Referer header required for playback (some providers)


class AnimeInfo(BaseModel):
    name: str
    image: Optional[str] = None
    genres: list[str] = []
    synopsis: Optional[str] = None
    release_year: Optional[int] = None
    status: Optional[str] = None


class MangaResult(BaseModel):
    id: str                           # MangaDex UUID
    title: str
    description: str
    status: str                       # "ongoing" | "completed" | "hiatus" | "cancelled"
    year: Optional[int] = None
    rating: Optional[float] = None   # Not returned by search endpoint; fetched separately
    cover_url: Optional[str] = None  # https://uploads.mangadex.org/covers/{id}/{filename}
    tags: list[str] = []


class Chapter(BaseModel):
    id: str                              # MangaDex chapter UUID
    title: Optional[str] = None
    chapter_number: Optional[str] = None  # "1", "12.5" — string because MangaDex uses strings
    volume: Optional[str] = None
    language: str                        # e.g. "en"
    pages: int                           # 0 = external chapter (filtered out before returning)
    published_at: str                    # ISO 8601 datetime string


class ChapterPage(BaseModel):
    page_number: int   # 1-indexed
    url: str           # Full CDN URL: {baseUrl}/data/{hash}/{filename}


class MangaUpdateEntry(BaseModel):
    chapter_id: str
    chapter_number: Optional[str] = None
    chapter_title: Optional[str] = None
    published_at: str                    # ISO 8601 datetime string
    manga_id: str
    manga_title: str
    cover_url: Optional[str] = None


class DownloadRequest(BaseModel):
    provider_name: str
    identifier: str         # anipy-api provider-specific anime ID
    anime_title: str        # used for the directory name under DOWNLOAD_DIR
    episode: float
    language: str = "sub"
    output_filename: Optional[str] = None  # override the generated filename


class DownloadStatus(BaseModel):
    id: int
    provider_name: str
    identifier: str
    anime_title: str
    episode: float
    language: str
    file_path: Optional[str] = None
    status: str             # queued | downloading | completed | failed
    progress: float         # 0.0 – 100.0
    error_message: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class Sport(BaseModel):
    id: str    # e.g. "football", "basketball"
    name: str  # human-readable label


class MatchSource(BaseModel):
    source: str  # provider name, e.g. "StreamedSU"
    id: str      # source-specific stream ID used in the /api/stream call


class Match(BaseModel):
    id: str
    title: str
    sources: list[MatchSource]


class SportStream(BaseModel):
    embed_url: str  # direct playable or embeddable URL
    viewers: int    # current viewer count on that source


class SportStreamResolved(BaseModel):
    urls: list[str]
    referrer: str
    source_used: str


class ComicResult(BaseModel):
    id: str                        # hid — comick.io hash identifier
    slug: str                      # URL slug (used for chapter-list endpoint)
    title: str
    description: str
    status: str                    # "ongoing" | "completed" | "hiatus" | "cancelled"
    year: Optional[int] = None
    cover_url: Optional[str] = None
    genres: list[str] = []
    country: Optional[str] = None  # "us" | "jp" | "kr" | "cn" …


class ComicChapter(BaseModel):
    id: str                              # hid (chapter hash — used to fetch pages)
    title: Optional[str] = None
    chapter_number: Optional[str] = None
    volume: Optional[str] = None
    language: str
    published_at: str


class EbookFormat(BaseModel):
    format: str                    # "epub" | "pdf" | "mobi" | "fb2"
    size_mb: Optional[float] = None
    download_url: str = ""         # direct file URL (Gutenberg); empty when resolve_url is set
    resolve_url: Optional[str] = None  # book page URL; if set, call /books/resolve?url=... first


class EbookResult(BaseModel):
    id: str                        # "gutenberg:{id}" or "libgen:{md5}"
    title: str
    author: str
    year: Optional[int] = None
    cover_url: Optional[str] = None
    description: Optional[str] = None
    formats: list[EbookFormat] = []
    source: str                    # "gutenberg" | "libgen"


class ArxivCategory(BaseModel):
    id: str    # e.g. "cs.AI"
    label: str # e.g. "Artificial Intelligence"


class ArxivPaper(BaseModel):
    id: str                      # "2401.12345" (clean, no version suffix)
    arxiv_url: str               # "https://arxiv.org/abs/2401.12345"
    pdf_url: str                 # "https://arxiv.org/pdf/2401.12345"
    title: str
    abstract: str
    authors: list[str]
    published: str               # ISO 8601
    updated: str                 # ISO 8601
    primary_category: str        # "cs.AI"
    categories: list[str]        # all categories, e.g. ["cs.AI", "cs.LG"]
    comment: Optional[str] = None


class ArxivSearchResult(BaseModel):
    papers: list[ArxivPaper]
    total: int
    offset: int


class AiringScheduleEntry(BaseModel):
    media_id: int
    title: str
    cover_image: Optional[str] = None
    episode: int
    airing_at: int                    # Unix timestamp
    total_episodes: Optional[int] = None
    genres: list[str] = []
    status: str


class HistoryItemCreate(BaseModel):
    media_type: str                       # "movie" | "series" | "anime" | "manga"
    title: str
    tmdb_id: Optional[int] = None
    anime_provider_id: Optional[str] = None
    manga_id: Optional[str] = None
    season_num: Optional[int] = None
    episode_num: Optional[int] = None
    chapter_id: Optional[str] = None
    progress_seconds: int = 0
    completed: bool = False
    page_index: int = 0


class HistoryItemResponse(BaseModel):
    id: int
    media_type: str
    title: str
    tmdb_id: Optional[int] = None
    anime_provider_id: Optional[str] = None
    manga_id: Optional[str] = None
    season_num: Optional[int] = None
    episode_num: Optional[int] = None
    chapter_id: Optional[str] = None
    progress_seconds: int
    completed: bool
    watched_at: datetime
    page_index: int = 0

    # This tells Pydantic to read from ORM objects (SQLAlchemy rows),
    # not just plain dicts. Without this, from_orm() would fail.
    model_config = {"from_attributes": True}
