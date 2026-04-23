from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, Integer, String, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class HistoryItem(Base):
    __tablename__ = "history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)

    # Which kind of content is this row for?
    media_type: Mapped[str] = mapped_column(String)  # "movie" | "series" | "anime" | "manga"

    # IDs — only one set will be populated per row depending on media_type
    tmdb_id: Mapped[int | None] = mapped_column(Integer, nullable=True)          # movies & series
    anime_provider_id: Mapped[str | None] = mapped_column(String, nullable=True) # anipy-api identifier
    manga_id: Mapped[str | None] = mapped_column(String, nullable=True)          # MangaDex UUID

    title: Mapped[str] = mapped_column(String)

    # Position within the content (nullable because movies have no season)
    season_num: Mapped[int | None] = mapped_column(Integer, nullable=True)
    episode_num: Mapped[int | None] = mapped_column(Integer, nullable=True)
    chapter_id: Mapped[str | None] = mapped_column(String, nullable=True)        # manga chapter UUID

    progress_seconds: Mapped[int] = mapped_column(Integer, default=0)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    page_index: Mapped[int] = mapped_column(Integer, default=0)  # reader page bookmark

    # func.now() tells SQLAlchemy to use the DB's current timestamp at insert time
    watched_at: Mapped[datetime] = mapped_column(DateTime, default=func.now(), onupdate=func.now())


class BookBookmark(Base):
    __tablename__ = "book_bookmarks"

    book_id:    Mapped[str]   = mapped_column(String, primary_key=True)
    title:      Mapped[str]   = mapped_column(String, default="")
    author:     Mapped[str]   = mapped_column(String, default="")
    cover_url:  Mapped[str]   = mapped_column(String, default="")
    book_json:  Mapped[str]   = mapped_column(String, default="")  # full EbookResult JSON
    format:     Mapped[str]   = mapped_column(String, default="epub")  # "epub" | "pdf"
    cfi:        Mapped[str]   = mapped_column(String, default="")   # epub CFI for resume position
    progress:   Mapped[float] = mapped_column(Float, default=0.0)   # 0.0–1.0
    page_index: Mapped[int]   = mapped_column(Integer, default=0)
    total_pages: Mapped[int]  = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=func.now(), onupdate=func.now())


class Download(Base):
    __tablename__ = "downloads"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)

    # Which anime / episode is being downloaded
    provider_name: Mapped[str] = mapped_column(String)   # "allanime" | "animekai"
    identifier: Mapped[str] = mapped_column(String)       # provider-specific anime ID
    anime_title: Mapped[str] = mapped_column(String)
    episode: Mapped[float] = mapped_column(Float)         # float for specials (5.5)
    language: Mapped[str] = mapped_column(String)         # "sub" | "dub"

    # Result
    file_path: Mapped[str | None] = mapped_column(String, nullable=True)

    # Lifecycle — one of: queued | downloading | completed | failed
    status: Mapped[str] = mapped_column(String, default="queued")
    progress: Mapped[float] = mapped_column(Float, default=0.0)  # 0.0 – 100.0
    error_message: Mapped[str | None] = mapped_column(String, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=func.now(), onupdate=func.now())
