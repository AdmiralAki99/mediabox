import asyncio
import logging
from pathlib import Path

from dotenv import set_key
from fastapi import APIRouter

from config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/settings", tags=["Settings"])

# .env sits one level up from this file
_ENV_FILE = Path(__file__).parent.parent / ".env"

# which keys the frontend is allowed to R/W
_ALLOWED = {"TMDB_BEARER_TOKEN", "ZLIB_EMAIL", "ZLIB_PASSWORD", "ZLIB_DOMAIN", "NYT_BOOKS_API_KEY"}


@router.get("")
async def get_settings():
    return {
        "TMDB_BEARER_TOKEN":     "***" if settings.TMDB_BEARER_TOKEN else "",
        "TMDB_BEARER_TOKEN_SET": bool(settings.TMDB_BEARER_TOKEN),
        "ZLIB_EMAIL":            settings.ZLIB_EMAIL,
        "ZLIB_PASSWORD":         "***" if settings.ZLIB_PASSWORD else "",
        "ZLIB_PASSWORD_SET":     bool(settings.ZLIB_PASSWORD),
        "ZLIB_DOMAIN":           settings.ZLIB_DOMAIN,
        "NYT_BOOKS_API_KEY":     "***" if settings.NYT_BOOKS_API_KEY else "",
        "NYT_BOOKS_API_KEY_SET": bool(settings.NYT_BOOKS_API_KEY),
    }


@router.put("")
async def update_settings(body: dict):
    changed = []
    zlib_touched = False

    for raw_key, value in body.items():
        key = raw_key.upper()
        # skip blanks and round-tripped masked values
        if not value or value == "***" or key not in _ALLOWED:
            continue

        if _ENV_FILE.exists():
            set_key(str(_ENV_FILE), key, value)

        # update in memory so it takes effect without a restart
        try:
            object.__setattr__(settings, key, value)
        except Exception:
            pass

        changed.append(key)
        if key in ("ZLIB_EMAIL", "ZLIB_PASSWORD", "ZLIB_DOMAIN"):
            zlib_touched = True

    if zlib_touched:
        asyncio.create_task(_relogin_zlib())

    return {"updated": changed}


@router.post("/zlib/relogin")
async def zlib_relogin():
    asyncio.create_task(_relogin_zlib())
    return {"status": "login started"}


async def _relogin_zlib():
    try:
        from main import zlib_service
        zlib_service._logged_in = False
        await zlib_service.login(settings.ZLIB_EMAIL, settings.ZLIB_PASSWORD)
    except Exception as exc:
        logger.warning("zlib re-login failed: %s", exc)
