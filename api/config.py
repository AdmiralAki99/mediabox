from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    TMDB_BEARER_TOKEN: str = ""
    TMDB_BASE_URL: str = "https://api.themoviedb.org/3"
    MANGADEX_BASE_URL: str = "https://api.mangadex.org"
    DATABASE_URL: str = "sqlite+aiosqlite:///./mediabox.db"
    CACHE_TTL_SEARCH: int = 300
    CACHE_TTL_TRENDING: int = 1800
    REQUEST_TIMEOUT: int = 30
    DOWNLOAD_DIR: str = "./downloads"
    DEBUG: bool = False
    ZLIB_EMAIL: str = ""
    ZLIB_PASSWORD: str = ""
    ZLIB_DOMAIN: str = "singlelogin.re"  # override with your personal domain, e.g. 12345678.singlelogin.re
    NYT_BOOKS_API_KEY: str = ""


settings = Settings()
