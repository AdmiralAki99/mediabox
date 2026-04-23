import logging
from typing import Optional

import httpx

from models.schemas import EbookFormat, EbookResult

logger = logging.getLogger(__name__)

_BASE       = "https://gutendex.com"
_MIME_EPUB  = "application/epub+zip"
_MIME_PDF   = "application/pdf"
_COVER_MIMES = ("image/jpeg", "image/png")


def _flip_author(name: str) -> str:
    if ", " in name:
        last, first = name.split(", ", 1)
        return f"{first} {last}"
    return name


def _parse_book(raw: dict) -> Optional[EbookResult]:
    formats_dict: dict[str, str] = raw.get("formats", {})

    ebook_formats: list[EbookFormat] = []
    if _MIME_EPUB in formats_dict:
        ebook_formats.append(EbookFormat(
            format="epub",
            size_mb=None,
            download_url=formats_dict[_MIME_EPUB],
        ))
    if _MIME_PDF in formats_dict:
        ebook_formats.append(EbookFormat(
            format="pdf",
            size_mb=None,
            download_url=formats_dict[_MIME_PDF],
        ))

    if not ebook_formats:
        return None

    cover_url: Optional[str] = None
    for mime in _COVER_MIMES:
        if mime in formats_dict:
            cover_url = formats_dict[mime]
            break

    authors = raw.get("authors", [])
    author = _flip_author(authors[0]["name"]) if authors else "Unknown"

    summaries = raw.get("summaries") or []
    description = summaries[0] if summaries else None

    return EbookResult(
        id=f"gutenberg:{raw['id']}",
        title=raw.get("title", "Unknown"),
        author=author,
        year=None,          # Gutenberg doesn't expose year reliably
        cover_url=cover_url,
        description=description,
        formats=ebook_formats,
        source="gutenberg",
    )


class GutenbergService:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self._http = client

    async def search(self, q: str, limit: int = 20) -> list[EbookResult]:
        try:
            r = await self._http.get(
                f"{_BASE}/books",
                params={"search": q, "mime_type": "application/epub+zip"},
                timeout=15,
                follow_redirects=True,
            )
            r.raise_for_status()
        except httpx.HTTPError as exc:
            logger.warning("Gutenberg search failed: %s", exc)
            return []

        results: list[EbookResult] = []
        for raw in r.json().get("results", []):
            book = _parse_book(raw)
            if book:
                results.append(book)
            if len(results) >= limit:
                break

        return results
