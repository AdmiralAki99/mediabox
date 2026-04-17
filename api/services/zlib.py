import logging
from typing import Optional

import httpx

from config import settings as _settings
from models.schemas import EbookFormat, EbookResult

logger = logging.getLogger(__name__)

# zlib keeps rotating domains so try a few in order
# the configured one goes first, rest are fallbacks
_AUTH_DOMAINS = [
    "singlelogin.re",
    "singlelogin.me",
    "z-lib.cv",
    "z-lib.fm",
    "z-library.sk",
]

_HEADERS = {
    "Content-Type": "application/x-www-form-urlencoded",
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    ),
}


class ZlibService:
    def __init__(self) -> None:
        self._http: Optional[httpx.AsyncClient] = None
        self._cookies: dict[str, str] = {}
        self._logged_in: bool = False
        self._domain: str = ""  # set after login, used for all search/download calls

    def _base(self) -> str:
        return f"https://{self._domain}"

    async def login(self, email: str, password: str) -> None:
        if not email or not password:
            logger.warning("ZLIB_EMAIL/ZLIB_PASSWORD not set — Z-Library disabled")
            return

        self._http = httpx.AsyncClient(headers=_HEADERS, follow_redirects=True)

        configured = _settings.ZLIB_DOMAIN
        domains = [configured] + [d for d in _AUTH_DOMAINS if d != configured]

        for domain in domains:
            try:
                r = await self._http.post(
                    f"https://{domain}/eapi/user/login",
                    data={"email": email, "password": password},
                    timeout=8,
                )
                if r.status_code == 404:
                    # eapi not on this domain, try next
                    logger.debug("no eapi on %s, skipping", domain)
                    continue
                r.raise_for_status()
                data = r.json()
                if not data.get("success"):
                    logger.debug("login rejected on %s: %s", domain, data)
                    continue

                user = data["user"]
                self._cookies = {
                    "remix_userid":  str(user["id"]),
                    "remix_userkey": user["remix_userkey"],
                }

                # the response includes the user's personal domain which is the only
                # place the search/download endpoints actually work
                personal = (user.get("personalDomain") or "").strip().lstrip("https://").rstrip("/")
                self._domain = personal if personal else domain
                self._logged_in = True

                logger.info(
                    "Z-Library login OK via %s → personal domain: %s "
                    "(user: %s, downloads left today: %d/%d)",
                    domain,
                    self._domain,
                    user.get("name", email),
                    user.get("downloads_limit", 10) - user.get("downloads_today", 0),
                    user.get("downloads_limit", 10),
                )
                return

            except httpx.HTTPStatusError as exc:
                logger.debug("Z-Library %s returned %s", domain, exc.response.status_code)
            except Exception as exc:
                logger.debug("Z-Library %s error: %s", domain, exc)

        logger.warning("Z-Library login failed on all %d domains", len(domains))

    async def close(self) -> None:
        if self._http:
            await self._http.aclose()

    async def search(self, q: str, limit: int = 20) -> list[EbookResult]:
        if not self._logged_in or not self._http:
            return []
        try:
            r = await self._http.post(
                f"{self._base()}/eapi/book/search",
                data={
                    "message":      q,
                    "extensions[]": ["epub", "pdf", "mobi"],
                    "limit":        min(limit, 50),
                    "page":         1,
                },
                cookies=self._cookies,
                timeout=15,
            )
            r.raise_for_status()
            books = r.json().get("books") or []
        except Exception as exc:
            logger.warning("Z-Library search failed: %s", exc)
            return []

        results: list[EbookResult] = []
        for book in books:
            ext     = (book.get("extension") or "").lower().strip()
            size    = book.get("filesize")
            size_mb = round(size / (1024 * 1024), 2) if size else None

            # store id/hash now, resolve to a real CDN url only when the user taps download
            resolve_url = f"zlib:{book['id']}/{book['hash']}"

            results.append(EbookResult(
                id=f"zlib:{book['id']}",
                title=book.get("title") or "",
                author=book.get("author") or "",
                year=int(book["year"]) if book.get("year") else None,
                cover_url=book.get("cover") or "",
                source="zlib",
                formats=[EbookFormat(
                    format=ext,
                    size_mb=size_mb,
                    download_url="",
                    resolve_url=resolve_url,
                )],
            ))
        return results

    async def resolve_download_url(self, resolve_url: str) -> str:
        if not self._logged_in or not self._http:
            raise RuntimeError("Z-Library not logged in")
        path = resolve_url.removeprefix("zlib:")
        try:
            r = await self._http.get(
                f"{self._base()}/eapi/book/{path}/file",
                cookies=self._cookies,
                timeout=15,
            )
            r.raise_for_status()
            data = r.json()
        except Exception as exc:
            raise RuntimeError(f"Z-Library file-info failed: {exc}")

        if not data.get("success"):
            raise ValueError(f"Z-Library file-info rejected: {data}")
        dl = (data.get("file") or {}).get("downloadLink") or ""
        if not dl:
            raise ValueError("no downloadLink in response")
        return dl
