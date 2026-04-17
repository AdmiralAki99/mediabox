"""
LibGenService — search Library Genesis via the two-step pipeline used by
libgen-cli (refs/libgen-cli-master):

  Step 1 — HTML search page → extract MD5 hashes via regex
            (same SearchHref / SearchMD5 patterns as the Go CLI)

  Step 2 — JSON API: json.php?ids={md5,...}&fields=...
            Returns structured metadata including coverurl, pages, language, etc.
            More reliable than HTML table scraping — independent of page layout.

Cover URL:  https://libgen.is/covers/{coverurl}
Download:   library.lol/main/{md5} resolved at read-time, or get.php fallback
Mirrors:    exact set from libgen-cli mirrors.go — libgen.is → libgen.rs → libgen.st → libgen.gs
"""

import logging
import re
from typing import Optional

import httpx

from models.schemas import EbookFormat, EbookResult

logger = logging.getLogger(__name__)

# Exact mirror set from libgen-cli/libgen/mirrors.go (SearchMirrors).
# libgen.li is intentionally excluded — its /search.php path returns 404.
_MIRRORS = [
    "https://libgen.li",
    "https://libgen.is",
    "https://libgen.rs",
    "https://libgen.st",
    "https://libgen.gs",
]

# Fields returned by json.php — matches JSONQuery const in the Go CLI
_JSON_FIELDS = (
    "id,title,author,filesize,extension,md5,"
    "year,language,pages,publisher,edition,coverurl"
)

_SUPPORTED_FORMATS = {"epub", "pdf", "mobi", "fb2", "azw3"}

# Cover images — use first mirror as base, fallback is just no cover
_COVER_BASE = "https://libgen.is/covers"

# Download: library.lol gives a direct CDN link; get.php is a simpler fallback
# We resolve library.lol at read-time in _resolve_download_url()
_LIBRARY_LOL = "https://library.lol/main"
_GET_PHP_BASE = "https://libgen.is/get.php"

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

# MD5 hash from any mirror's download link (libgen.is, libgen.li, etc.)
_HASH_RE = re.compile(r"""href=['"](?:book/index\.php|book\.php|/get\.php|/ads\.php)\?md5=([A-Za-z0-9]{32})""", re.IGNORECASE)

# Direct CDN download URL from library.lol detail page — libraryLolReg in const.go
_LOL_DL_RE = re.compile(r"https://download\.library\.lol/main/\d+/[A-Za-z0-9]+/[^\"]+", re.IGNORECASE)

# libgen.pm ads page — libgenPMReg in const.go: get.php?md5=<32>&key=<16>
_PM_KEY_RE  = re.compile(r"get\.php\?md5=[A-Za-z0-9]{32}&key=[A-Za-z0-9]{16}", re.IGNORECASE)


def _parse_size_mb(filesize_bytes: str) -> Optional[float]:
    try:
        return round(int(filesize_bytes) / (1024 * 1024), 2)
    except (ValueError, TypeError):
        return None


class LibGenService:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self._http = client

    async def search(self, q: str, limit: int = 20) -> list[EbookResult]:
        """
        Search LibGen. Tries libgen.li first (single-pass HTML parse — json.php
        is broken there). Falls back to the classic two-step MD5 → json.php
        pipeline for the other mirrors.
        """
        # Fast path: libgen.li parses everything from HTML in one request
        results = await self._fetch_from_libgen_li(q, limit)
        if results:
            return results

        # Legacy path for other mirrors (libgen.is / .rs / .st / .gs)
        hashes = await self._fetch_hashes(q, limit)
        if not hashes:
            return []
        return await self._fetch_details(hashes)

    # ── libgen.li: single-pass HTML parser ───────────────────────────────────

    _TAG_RE   = re.compile(r"<[^>]+>")
    _ROW_RE   = re.compile(r"<tr[^>]*>(.*?)</tr>", re.DOTALL)
    _TD_RE    = re.compile(r"<td[^>]*>(.*?)</td>", re.DOTALL)
    _FILE_RE  = re.compile(r'href="/file\.php\?id=(\d+)"')
    _SIZE_RE  = re.compile(r"([\d.]+)\s*(MB|kB|KB|GB)", re.IGNORECASE)
    _MD5_RE   = re.compile(r"/ads\.php\?md5=([A-Za-z0-9]{32})")

    async def _fetch_from_libgen_li(self, q: str, limit: int) -> list[EbookResult]:
        """Parse all metadata from libgen.li HTML in a single request."""
        res = 25 if limit <= 25 else (50 if limit <= 50 else 100)
        try:
            r = await self._http.get(
                "https://libgen.li/index.php",
                params={"req": q, "res": res, "view": "simple",
                        "column": "def", "lg_topic": "libgen",
                        "phrase": "1", "open": "0"},
                headers={"User-Agent": _UA, "Referer": "https://libgen.li/"},
                timeout=10,
                follow_redirects=True,
            )
            r.raise_for_status()
        except Exception as exc:
            logger.info("LibGen libgen.li failed: %s", exc)
            return []

        results: list[EbookResult] = []
        for row_html in self._ROW_RE.findall(r.text):
            tds = self._TD_RE.findall(row_html)
            if len(tds) < 9:
                continue

            # Title — text inside <b> before any nested tags
            b = re.search(r"<b>(.*?)</b>", tds[0], re.DOTALL)
            if not b:
                continue
            # Split on first '<' to discard nested anchor tags and their mangled attributes
            title = b.group(1).split("<")[0].strip()
            if not title:
                continue

            # Format — td[7]
            fmt = self._TAG_RE.sub("", tds[7]).strip().lower()
            if fmt not in _SUPPORTED_FORMATS:
                continue

            # File ID + download URL — td[6]
            fid = self._FILE_RE.search(tds[6])
            if not fid:
                continue
            file_id = fid.group(1)
            download_url = f"https://libgen.li/file.php?id={file_id}"

            # Author — td[1]
            author = self._TAG_RE.sub("", tds[1]).strip().rstrip(",").strip() or "Unknown"

            # Year — td[3]
            yr = self._TAG_RE.sub("", tds[3]).strip()
            year: Optional[int] = int(yr) if yr.isdigit() and int(yr) > 1000 else None

            # Size — td[6] link text e.g. "3 MB" / "781 kB"
            size_mb: Optional[float] = None
            sm = self._SIZE_RE.search(self._TAG_RE.sub("", tds[6]))
            if sm:
                val, unit = float(sm.group(1)), sm.group(2).lower()
                size_mb = round(val / 1024 if unit == "kb" else
                                val * 1024 if unit == "gb" else val, 2)

            # MD5 — td[8] (for cover URL)
            md5m = self._MD5_RE.search(tds[8])
            md5 = md5m.group(1).lower() if md5m else None

            results.append(EbookResult(
                id=f"libgen:{md5 or file_id}",
                title=title,
                author=author,
                year=year,
                cover_url=None,  # OL title-based lookup produces too many 404s
                description=None,
                formats=[EbookFormat(format=fmt, size_mb=size_mb, download_url=download_url)],
                source="libgen",
            ))
            if len(results) >= limit:
                break

        if results:
            logger.info("LibGen: parsed %d results from libgen.li HTML", len(results))
        return results

    # ── Step 1: search page → MD5 hashes (legacy mirrors) ────────────────────

    async def _fetch_hashes(self, q: str, limit: int) -> list[str]:
        res = 25 if limit <= 25 else (50 if limit <= 50 else 100)
        params = {"req": q, "res": res, "view": "simple",
                  "column": "def", "lg_topic": "libgen", "phrase": "1", "open": "0"}

        for mirror in _MIRRORS:
            if "libgen.li" in mirror:
                continue  # handled by _fetch_from_libgen_li
            try:
                r = await self._http.get(
                    f"{mirror}/search.php", params=params,
                    headers={"User-Agent": _UA, "Referer": f"{mirror}/"},
                    timeout=5, follow_redirects=True,
                )
                r.raise_for_status()
                seen: set[str] = set()
                unique: list[str] = []
                for h in _HASH_RE.findall(r.text):
                    if h not in seen:
                        seen.add(h); unique.append(h)
                    if len(unique) >= limit:
                        break
                if unique:
                    logger.info("LibGen: found %d hashes via %s", len(unique), mirror)
                    return unique
            except Exception as exc:
                logger.info("LibGen search mirror %s failed: %s", mirror, exc)

        logger.warning("LibGen: all search mirrors failed for q=%r", q)
        return []

    # ── Step 2: json.php batch → metadata + cover ─────────────────────────────

    async def _fetch_details(self, hashes: list[str]) -> list[EbookResult]:
        ids = ",".join(hashes)

        items: list[dict] = []
        for mirror in _MIRRORS:
            try:
                r = await self._http.get(
                    f"{mirror}/json.php",
                    params={"ids": ids, "fields": _JSON_FIELDS},
                    headers={"User-Agent": _UA, "Referer": f"{mirror}/"},
                    timeout=5,
                )
                r.raise_for_status()
                items = r.json()
                if items:
                    logger.info("LibGen: fetched details from %s", mirror)
                    break
            except Exception as exc:
                logger.info("LibGen json.php mirror %s failed: %s", mirror, exc)

        if not items:
            return []

        results: list[EbookResult] = []
        for item in items:
            ext = (item.get("extension") or "").lower().strip()
            if ext not in _SUPPORTED_FORMATS:
                continue

            md5 = (item.get("md5") or "").lower().strip()
            if not md5:
                continue

            year_str = (item.get("year") or "").strip()
            year: Optional[int] = None
            if year_str.isdigit() and int(year_str) > 1000:
                year = int(year_str)

            # coverurl from json.php is a bare filename, e.g. "1029362-G.jpg"
            cover_raw = (item.get("coverurl") or "").strip()
            cover_url = f"{_COVER_BASE}/{cover_raw}" if cover_raw else None

            results.append(EbookResult(
                id=f"libgen:{md5}",
                title=(item.get("title") or "Unknown").strip() or "Unknown",
                author=(item.get("author") or "Unknown").strip() or "Unknown",
                year=year,
                cover_url=cover_url,
                description=None,
                formats=[EbookFormat(
                    format=ext,
                    size_mb=_parse_size_mb(item.get("filesize") or ""),
                    download_url=f"{_LIBRARY_LOL}/{md5}",
                )],
                source="libgen",
            ))

        return results

    # ── Download URL resolution (library.lol → actual CDN link) ──────────────

    async def resolve_download_url(self, md5: str) -> str:
        """
        Resolve a LibGen MD5 to a direct CDN URL via library.lol.
        Tries main → fiction → scimag collections in order.
        Falls back to libgen.is/get.php?md5={md5} if all library.lol paths fail.
        Mirrors libraryLolReg logic from libgen-cli/libgen/download.go.
        """
        for collection in ("main", "fiction", "scimag"):
            lol_page = f"https://library.lol/{collection}/{md5}"
            try:
                r = await self._http.get(
                    lol_page,
                    headers={"User-Agent": _UA, "Referer": "https://libgen.is/"},
                    timeout=8,
                    follow_redirects=True,
                )
                if r.status_code == 404:
                    continue
                r.raise_for_status()
                m = _LOL_DL_RE.search(r.text)
                if m:
                    logger.info("library.lol/%s resolved MD5 %s", collection, md5)
                    return m.group(0)
            except Exception as exc:
                logger.info("library.lol/%s resolve failed for %s: %s", collection, md5, exc)

        # Second fallback: libgen.pm/ads/{md5} → parse key → libgen.pm/get.php
        try:
            r = await self._http.get(
                f"https://libgen.pm/ads/{md5}",
                headers={"User-Agent": _UA, "Referer": "https://libgen.pm/"},
                timeout=8,
                follow_redirects=True,
            )
            r.raise_for_status()
            m = _PM_KEY_RE.search(r.text)
            if m:
                dl = f"https://libgen.pm/{m.group(0)}"
                logger.info("libgen.pm resolved MD5 %s → %s", md5, dl)
                return dl
        except Exception as exc:
            logger.info("libgen.pm resolve failed for %s: %s", md5, exc)

        # Last resort: libgen.is/get.php redirect
        logger.info("All resolvers failed for %s; using get.php last resort", md5)
        return f"{_GET_PHP_BASE}?md5={md5}"
