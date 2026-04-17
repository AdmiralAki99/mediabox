import asyncio

from curl_cffi.requests import AsyncSession

from cache import cache
from config import settings
from models.schemas import ChapterPage, ComicChapter, ComicResult

_BASE = "https://api.comick.dev"
_COVER_BASE = "https://meo.comick.pictures"

_STATUS: dict[int, str] = {
    1: "ongoing",
    2: "completed",
    3: "cancelled",
    4: "hiatus",
}

# Headers still sent alongside the TLS impersonation — belt + braces.
_HEADERS = {
    "Referer": "https://comick.io/",
    "Origin": "https://comick.io",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
}


class ComickService:
    def __init__(self) -> None:
        # impersonate="chrome124" makes curl-cffi send a Chrome 124 TLS
        # ClientHello — cipher suites, extensions, GREASE — not just the UA.
        self._session = AsyncSession(
            impersonate="chrome124",
            headers=_HEADERS,
            timeout=settings.REQUEST_TIMEOUT,
        )

    async def close(self) -> None:
        await self._session.close()

    @staticmethod
    def _cover_url(item: dict) -> str | None:
        covers = item.get("md_covers") or []
        if not covers:
            return None
        cover = covers[0]
        raw = cover.get("url") or cover.get("b2key") or ""
        if not raw:
            return None
        if raw.startswith("http"):
            return raw
        return f"{_COVER_BASE}/{raw}"

    @staticmethod
    def _parse_genres(item: dict) -> list[str]:
        """Genres arrive either as strings or as {id, name, slug} dicts."""
        raw = item.get("genres") or []
        result = []
        for g in raw:
            if isinstance(g, str):
                result.append(g)
            elif isinstance(g, dict):
                name = g.get("name") or g.get("slug") or ""
                if name:
                    result.append(name)
        return result

    def _parse_comic(self, item: dict) -> ComicResult:
        status = _STATUS.get(item.get("status") or 1, "ongoing")
        year_raw = item.get("year")
        try:
            year = int(year_raw) if year_raw is not None else None
        except (TypeError, ValueError):
            year = None
        desc = item.get("desc") or item.get("summary") or ""
        return ComicResult(
            id=item["hid"],
            slug=item["slug"],
            title=item.get("title") or item["slug"],
            description=desc,
            status=status,
            year=year,
            cover_url=self._cover_url(item),
            genres=self._parse_genres(item),
            country=item.get("country") or None,
        )

    @staticmethod
    def _parse_chapter(ch: dict) -> ComicChapter:
        chap_raw = ch.get("chap")
        chap_str = str(chap_raw) if chap_raw is not None else None
        vol_raw = ch.get("vol")
        vol_str = str(vol_raw) if vol_raw else None
        return ComicChapter(
            id=ch["hid"],
            title=ch.get("title") or None,
            chapter_number=chap_str,
            volume=vol_str,
            language=ch.get("lang", "en"),
            published_at=ch.get("created_at") or ch.get("updated_at") or "",
        )


    async def search_comics(self, query: str, limit: int = 20) -> list[ComicResult]:
        """
        Search comick.dev by title.

        The trailing slash on /v1.0/search/ is required by the server.
        t=false disables the tachiyomi-specific response format.
        """
        key = f"comic:search:{query.lower()}:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        params = {"q": query, "limit": limit, "page": 1, "t": "false"}
        response = await self._session.get(f"{_BASE}/v1.0/search/", params=params)
        response.raise_for_status()
        data = response.json()
        items = data if isinstance(data, list) else data.get("data", [])
        result = [
            self._parse_comic(item)
            for item in items
            if item.get("hid") and item.get("slug")
        ]
        cache.set(key, result, settings.CACHE_TTL_SEARCH)
        return result

    async def get_chapters(
        self,
        hid: str,
        language: str = "en",
        page_size: int = 300,
    ) -> list[ComicChapter]:
        """
        Fetch all chapters for a comic by its hid, using parallel page requests.

        Page 1 exposes `total`; remaining pages are fetched concurrently.
        """
        def _params(page: int) -> dict:
            return {"lang": language, "page": page, "limit": page_size, "chap-order": 0}

        first = await self._session.get(f"{_BASE}/comic/{hid}/chapters", params=_params(1))
        first.raise_for_status()
        body = first.json()
        first_page = body.get("chapters") or []
        total: int = body.get("total", len(first_page))
        all_chapters = [self._parse_chapter(ch) for ch in first_page]

        # Only paginate if the first page was full (more pages exist)
        if len(first_page) < page_size:
            return all_chapters

        remaining_pages = range(2, (total + page_size - 1) // page_size + 1)
        responses = await asyncio.gather(
            *[self._session.get(f"{_BASE}/comic/{hid}/chapters", params=_params(p))
              for p in remaining_pages],
            return_exceptions=True,
        )
        for resp in responses:
            if isinstance(resp, Exception):
                continue
            resp.raise_for_status()
            all_chapters.extend(
                self._parse_chapter(ch) for ch in (resp.json().get("chapters") or [])
            )
        return all_chapters

    async def get_chapter_pages(self, hid: str) -> list[ChapterPage]:
        """
        Fetch page image URLs for a chapter.

        ?tachiyomi=true causes the API to return full absolute image URLs.
        Response: {"chapter": {"images": [{"url": "https://..."}, ...]}}
        """
        response = await self._session.get(
            f"{_BASE}/chapter/{hid}", params={"tachiyomi": "true"}
        )
        response.raise_for_status()
        body = response.json()
        images = body.get("chapter", {}).get("images") or []
        pages = []
        for i, img in enumerate(images):
            url = img.get("url") or ""
            if not url:
                continue
            if not url.startswith("http"):
                url = f"{_COVER_BASE}/{url}"
            pages.append(ChapterPage(page_number=i + 1, url=url))
        return pages
