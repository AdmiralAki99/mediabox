"""
MangaDexService — all manga data via the MangaDex public REST API.

No authentication required.  Base: https://api.mangadex.org

Endpoints used:
  GET /manga                      — search
  GET /manga/{id}/feed            — chapter list
  GET /at-home/server/{chapter_id} — per-chapter page URLs

MangaDex response conventions:
  - Top-level wrapper: {"result": "ok", "data": [...], "total": N}
  - Localized strings: {"en": "Title", "ja": "タイトル"} — always prefer "en"
  - Relationships: [{type, id, attributes}] — cover_art included when
    includes[]=cover_art is sent with the search request
  - Cover URL: https://uploads.mangadex.org/covers/{manga_id}/{filename}
  - Chapter page URL: {baseUrl}/data/{hash}/{filename}
"""

import asyncio

import httpx

from cache import cache
from config import settings
from models.schemas import Chapter, ChapterPage, MangaResult, MangaUpdateEntry

COVERS_BASE = "https://uploads.mangadex.org/covers"

# MangaDex tag UUIDs for common genres
_GENRE_TAGS: dict[str, str] = {
    "action":       "391b0423-d847-456f-aff0-8b0cfc03066b",
    "romance":      "423e2eae-a7a2-4a8b-ac03-a8351462d71d",
    "fantasy":      "cdc58593-87dd-415e-bbc0-2ec27bf404cc",
    "isekai":       "ace04997-f6bd-436e-b261-779182193d3d",
    "horror":       "cdad7e68-1419-41dd-bdce-27753074a640",
    "comedy":       "4d32cc48-9f00-4cca-9b5a-a839f0764984",
    "adventure":    "87cc87cd-a395-47af-b27a-93258283bbc6",
    "thriller":     "07251805-a27e-4d59-b488-f0bfbec15168",
    "supernatural": "eabc5b4c-6aff-42f3-b657-3e90cbd00b75",
    "slice-of-life":"e5301a23-ebd9-49dd-a0cb-2add944c7fe9",
    "mystery":      "ee968100-4191-4968-93d3-f68d863pak",
    "sci-fi":       "256c8bd9-4904-4360-bf4f-508a76d67183",
    "drama":        "b9af3a63-f058-46de-a9a0-e0c13906197a",
}


class MangaDexService:
    def __init__(self) -> None:
        self._client = httpx.AsyncClient(
            base_url=settings.MANGADEX_BASE_URL,
            timeout=settings.REQUEST_TIMEOUT,
            headers={"User-Agent": "mediabox/0.1 (personal media server)"},
        )

    async def close(self) -> None:
        await self._client.aclose()

    @staticmethod
    def _localised(d: dict) -> str:
        if not d:
            return ""
        return d.get("en") or d.get("ja-ro") or next(iter(d.values()), "")

    def _parse_manga(self, manga: dict) -> MangaResult:
        attrs = manga["attributes"]

        # Cover art filename lives inside the relationships array.
        # It's only populated when we send includes[]=cover_art in the request.
        cover_url = None
        for rel in manga.get("relationships", []):
            if rel.get("type") == "cover_art":
                rel_attrs = rel.get("attributes") or {}
                filename = rel_attrs.get("fileName")
                if filename:
                    cover_url = f"{COVERS_BASE}/{manga['id']}/{filename}"
                break

        tags = [
            self._localised(t.get("attributes", {}).get("name", {}))
            for t in attrs.get("tags", [])
            if t.get("attributes", {}).get("name")
        ]
        # Drop empty tag names
        tags = [t for t in tags if t]

        return MangaResult(
            id=manga["id"],
            title=self._localised(attrs.get("title", {})) or manga["id"],
            description=self._localised(attrs.get("description", {})),
            status=attrs.get("status", "unknown"),
            year=attrs.get("year"),
            rating=None,   # requires a separate /statistics endpoint — omitted
            cover_url=cover_url,
            tags=tags,
        )

    @staticmethod
    def _parse_chapter(chapter: dict) -> Chapter:
        attrs = chapter["attributes"]
        return Chapter(
            id=chapter["id"],
            title=attrs.get("title") or None,
            chapter_number=attrs.get("chapter") or None,
            volume=attrs.get("volume") or None,
            language=attrs.get("translatedLanguage", ""),
            pages=attrs.get("pages", 0),
            published_at=attrs.get("publishAt", ""),
        )

    def _browse_params(self, limit: int, **extra) -> list:
        params = [
            ("limit", limit),
            ("includes[]", "cover_art"),
            ("contentRating[]", "safe"),
            ("contentRating[]", "suggestive"),
        ]
        for k, v in extra.items():
            params.append((k, v))
        return params

    async def get_popular_manga(self, limit: int = 20) -> list[MangaResult]:
        key = f"manga:popular:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        params = self._browse_params(limit, **{"order[followedCount]": "desc"})
        response = await self._client.get("/manga", params=params)
        response.raise_for_status()
        result = [self._parse_manga(m) for m in response.json().get("data", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_top_rated_manga(self, limit: int = 20) -> list[MangaResult]:
        key = f"manga:top_rated:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        params = self._browse_params(limit, **{"order[rating]": "desc"})
        response = await self._client.get("/manga", params=params)
        response.raise_for_status()
        result = [self._parse_manga(m) for m in response.json().get("data", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_manga_by_genre(self, genre: str, limit: int = 20) -> list[MangaResult]:
        tag_id = _GENRE_TAGS.get(genre.lower())
        if not tag_id:
            return []
        key = f"manga:genre:{genre}:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        params = self._browse_params(
            limit,
            **{"order[followedCount]": "desc", "includedTags[]": tag_id}
        )
        response = await self._client.get("/manga", params=params)
        response.raise_for_status()
        result = [self._parse_manga(m) for m in response.json().get("data", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_latest_manga(self, limit: int = 20) -> list[MangaResult]:
        key = f"manga:latest:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        params = [
            ("limit", limit),
            ("includes[]", "cover_art"),
            ("contentRating[]", "safe"),
            ("contentRating[]", "suggestive"),
            ("order[latestUploadedChapter]", "desc"),
        ]
        response = await self._client.get("/manga", params=params)
        response.raise_for_status()
        result = [self._parse_manga(m) for m in response.json().get("data", [])]
        cache.set(key, result, 300)  # 5-min — changes frequently
        return result

    async def search_manga(self, query: str, limit: int = 20) -> list[MangaResult]:
        """
        Search MangaDex for manga by title.

        Uses includes[]=cover_art so the cover image filename is embedded in the
        search response — no extra requests needed per result.

        Query params are built as a list of tuples so httpx correctly renders
        multi-value params like contentRating[]=safe&contentRating[]=suggestive.
        """
        key = f"manga:search:{query.lower()}:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        params = [
            ("title", query),
            ("limit", limit),
            ("includes[]", "cover_art"),
            ("contentRating[]", "safe"),
            ("contentRating[]", "suggestive"),
            ("order[followedCount]", "desc"),
        ]
        response = await self._client.get("/manga", params=params)
        response.raise_for_status()
        result = [self._parse_manga(m) for m in response.json().get("data", [])]
        cache.set(key, result, settings.CACHE_TTL_SEARCH)
        return result

    async def get_chapters(
        self,
        manga_id: str,
        language: str = "en",
    ) -> list[Chapter]:
        """
        Fetch ALL chapters for a manga, using parallel page requests.

        Page 1 is fetched first to discover the total count; all remaining
        pages are then fired concurrently so large chapter lists (500+ entries
        spanning multiple pages) download in parallel instead of sequentially.
        """
        _page_size = 500  # MangaDex hard maximum

        def _params(offset: int) -> list:
            return [
                ("translatedLanguage[]", language),
                ("limit", _page_size),
                ("offset", offset),
                ("order[chapter]", "asc"),
                ("contentRating[]", "safe"),
                ("contentRating[]", "suggestive"),
            ]

        # Fetch page 1 — response includes `total` so we know how many pages remain
        first = await self._client.get(f"/manga/{manga_id}/feed", params=_params(0))
        first.raise_for_status()
        body = first.json()
        all_chapters = [self._parse_chapter(c) for c in body.get("data", [])]
        total: int = body.get("total", len(all_chapters))

        # Remaining page offsets (500, 1000, 1500, …)
        remaining = range(_page_size, total, _page_size)
        if remaining:
            responses = await asyncio.gather(
                *[self._client.get(f"/manga/{manga_id}/feed", params=_params(off))
                  for off in remaining],
                return_exceptions=True,
            )
            for resp in responses:
                if isinstance(resp, Exception):
                    continue
                resp.raise_for_status()
                all_chapters.extend(
                    self._parse_chapter(c) for c in resp.json().get("data", [])
                )

        return all_chapters

    async def get_recent_chapter_updates(self, limit: int = 30) -> list[MangaUpdateEntry]:
        """
        Return recently published English chapters with their manga covers.

        Two requests:
          1. GET /chapter — latest EN chapters, includes manga attributes via relationship
          2. GET /manga?ids[]=... — batch cover art for all unique manga in the list
        """
        params = [
            ("limit", min(limit, 50)),
            ("translatedLanguage[]", "en"),
            ("order[publishAt]", "desc"),
            ("includes[]", "manga"),
            ("contentRating[]", "safe"),
            ("contentRating[]", "suggestive"),
        ]
        resp = await self._client.get("/chapter", params=params)
        resp.raise_for_status()
        chapters = resp.json().get("data", [])

        entries: list[dict] = []
        manga_ids: list[str] = []
        seen: set[str] = set()

        for ch in chapters:
            attrs = ch.get("attributes", {})
            manga_rel = next(
                (r for r in ch.get("relationships", []) if r["type"] == "manga"), None
            )
            if not manga_rel:
                continue
            manga_id = manga_rel["id"]
            manga_attrs = manga_rel.get("attributes") or {}
            title = self._localised(manga_attrs.get("title") or {}) or manga_id
            entries.append({
                "chapter_id": ch["id"],
                "chapter_number": attrs.get("chapter"),
                "chapter_title": attrs.get("title") or None,
                "published_at": attrs.get("publishAt", ""),
                "manga_id": manga_id,
                "manga_title": title,
                "cover_url": None,
            })
            if manga_id not in seen:
                seen.add(manga_id)
                manga_ids.append(manga_id)

        # Batch-fetch covers for all unique manga in one request
        if manga_ids:
            cover_params: list = [
                ("includes[]", "cover_art"),
                ("limit", len(manga_ids)),
                ("contentRating[]", "safe"),
                ("contentRating[]", "suggestive"),
            ]
            for mid in manga_ids:
                cover_params.append(("ids[]", mid))
            cover_resp = await self._client.get("/manga", params=cover_params)
            if cover_resp.status_code == 200:
                cover_map: dict[str, str] = {}
                for m in cover_resp.json().get("data", []):
                    for rel in m.get("relationships", []):
                        if rel["type"] == "cover_art":
                            fn = (rel.get("attributes") or {}).get("fileName")
                            if fn:
                                cover_map[m["id"]] = f"{COVERS_BASE}/{m['id']}/{fn}"
                            break
                for e in entries:
                    e["cover_url"] = cover_map.get(e["manga_id"])

        return [MangaUpdateEntry(**e) for e in entries]

    async def get_chapter_pages(self, chapter_id: str) -> list[ChapterPage]:
        """
        Fetch page image URLs for a chapter from MangaDex's at-home CDN.

        The at-home server response gives us:
          - baseUrl  — CDN host chosen based on your location
          - chapter.hash  — chapter-specific hash
          - chapter.data  — list of filenames (high quality)

        Page URL = {baseUrl}/data/{hash}/{filename}
        """
        response = await self._client.get(f"/at-home/server/{chapter_id}")
        response.raise_for_status()
        body = response.json()

        chapter_data = body["chapter"]
        hash_ = chapter_data["hash"]
        filenames: list[str] = chapter_data["data"]  # high-quality pages

        # Use uploads.mangadex.org directly — at-home nodes are community-run
        # and frequently return 404 for chapters they haven't cached yet.
        return [
            ChapterPage(
                page_number=i + 1,
                url=f"https://uploads.mangadex.org/data/{hash_}/{filename}",
            )
            for i, filename in enumerate(filenames)
        ]
