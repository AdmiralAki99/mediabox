"""
ReadComicService — scrapes readcomiconline.li for Western comics.

Uses curl-cffi (Chrome TLS impersonation) to bypass Cloudflare,
then parses HTML with BeautifulSoup.

Site conventions:
  Search:  GET /Search/Manga?keyword={q}
           → div.list-comic > div.item rows (title, cover img, slug href)
           → item div may have a title= attribute with Status / Summary metadata

  Series:  GET /Comic/{slug}
           → table.listing rows; each row td[0] has
             <a href="/Comic/{slug}/{issue}?id={n}">Issue Title</a>
             td[1] = publish date

  Pages:   GET /Comic/{slug}/{issue}?id={n}&readType=0&quality=hq
           → JS embeds per-page encoded image URLs. The page JS defines a
             substitution token (e.g. q1__2ucUs3_) that replaces 'e' chars in
             base64-encoded image paths. We:
             1) Extract the token from the inline helper function's replace call.
             2) Extract encoded URL blobs from *xnz variable assignments.
             3) Decode each blob: restore 'e', strip a fixed prefix/suffix via
                step1/step2, base64-decode, drop 4 chars at offset 13, append
                '=s1600' + auth query string, prepend blogspot CDN host.

Chapter ID format:
  The full href from the listing table including the ?id= query param,
  e.g. "/Comic/Batman-2016/Issue-1?id=12345".  Because this contains
  slashes it cannot be used as a URL path parameter — the pages router
  receives it as a query-string argument instead.
"""

import base64
import re

from bs4 import BeautifulSoup, Tag
from curl_cffi.requests import AsyncSession

from cache import cache
from config import settings
from models.schemas import ChapterPage, ComicChapter, ComicResult

_BASE = "https://readcomiconline.li"

_HEADERS = {
    "Referer": "https://readcomiconline.li/",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}


class ReadComicService:
    def __init__(self) -> None:
        # impersonate="chrome124" sends a real Chrome TLS ClientHello,
        # bypassing Cloudflare's TLS fingerprinting check.
        self._session = AsyncSession(
            impersonate="chrome124",
            headers=_HEADERS,
            timeout=settings.REQUEST_TIMEOUT,
        )
        self._warmed_up = False

    async def _warm_up(self) -> None:
        """Visit homepage once to collect Cloudflare cookies before searching."""
        if self._warmed_up:
            return
        try:
            await self._session.get(f"{_BASE}/", timeout=15)
            self._warmed_up = True
        except Exception:
            pass

    async def close(self) -> None:
        await self._session.close()

    # ── Helpers ───────────────────────────────────────────────────────────────

    @staticmethod
    def _strip_tags(text: str) -> str:
        """Remove any residual HTML tags from a plain-text field."""
        return re.sub(r"<[^>]+>", "", text).strip()

    @staticmethod
    def _to_rich_html(element: Tag) -> str:
        """
        Extract inner HTML from a BeautifulSoup element, keeping only the tags
        that QML's Text.RichText supports: b/strong, i/em, u, br, p, ul, ol, li.
        Everything else is unwrapped (content kept, tag stripped).
        Style/class/id attributes are also removed.
        """
        _KEEP = {"b", "strong", "i", "em", "u", "br", "p", "ul", "ol", "li", "span"}
        html = element.decode_contents()
        # Normalise <br> variants
        html = re.sub(r"<br\s*/?>", "<br/>", html, flags=re.I)
        # Strip style/class/id attributes
        html = re.sub(r'\s+(?:style|class|id|href|target)="[^"]*"', "", html)
        # Unwrap unsupported block/inline elements but keep their text
        html = re.sub(
            r"</?(?:div|section|article|aside|header|footer|figure|table"
            r"|tr|td|th|thead|tbody|h[1-6]|blockquote|pre|code)[^>]*>",
            " ", html, flags=re.I,
        )
        # Collapse whitespace
        html = re.sub(r"[ \t]{2,}", " ", html)
        html = re.sub(r"(\s*<br/>\s*){3,}", "<br/><br/>", html)
        return html.strip()

    @staticmethod
    def _cover_url(img_tag) -> str | None:
        if not img_tag:
            return None
        # data-src holds the real URL on lazy-loaded pages; src may be a blank placeholder
        src = img_tag.get("data-src") or img_tag.get("src") or ""
        if not src:
            return None
        return src if src.startswith("http") else f"{_BASE}{src}"

    @staticmethod
    def _parse_item_meta(item_div) -> dict:
        """
        Extract status, genres, and description from a search result item.

        rco encodes per-comic metadata in the outer div's title= attribute:
          "Status: Ongoing; Genres: Action, Crime; Summary: Batman is..."
        Genres may also appear as <a class="dotUnder"> inside <p> tags.
        """
        meta: dict = {"status": "ongoing", "genres": [], "description": ""}

        title_attr = item_div.get("title", "")
        if title_attr:
            m = re.search(r"Status:\s*([^;]+)", title_attr, re.I)
            if m:
                meta["status"] = ReadComicService._strip_tags(m.group(1)).lower()
            m = re.search(r"Summary:\s*(.+?)(?:;|$)", title_attr, re.I | re.S)
            if m:
                meta["description"] = ReadComicService._strip_tags(m.group(1))

        for p in item_div.find_all("p"):
            genres = [a.text.strip() for a in p.find_all("a", class_="dotUnder")]
            if genres:
                meta["genres"] = genres
                break

        return meta

    # ── Public API ────────────────────────────────────────────────────────────

    def _parse_list_items(self, soup, limit: int = 20) -> list[ComicResult]:
        """Parse the standard div.list-comic > div.item grid used on search, genre, and list pages."""
        results: list[ComicResult] = []
        for item in soup.select("div.list-comic > div.item")[:limit]:
            a_title = item.find("a", class_="title") or item.find("a")
            if not a_title:
                continue
            href = a_title.get("href", "")
            parts = [p for p in href.strip("/").split("/") if p]
            if len(parts) < 2:
                continue
            slug = parts[-1]
            title = a_title.text.strip()
            cover = self._cover_url(item.find("img"))
            meta = self._parse_item_meta(item)
            results.append(ComicResult(
                id=slug, slug=slug, title=title,
                description=meta["description"], status=meta["status"],
                year=None, cover_url=cover, genres=meta["genres"], country="us",
            ))
        return results

    async def search_comics(self, query: str, limit: int = 20) -> list[ComicResult]:
        key = f"rco:search:{query.lower()}:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        await self._warm_up()
        r = await self._session.get(f"{_BASE}/Search/Comic", params={"keyword": query})
        r.raise_for_status()
        soup = BeautifulSoup(r.text, "lxml")
        results = self._parse_list_items(soup, limit)
        cache.set(key, results, settings.CACHE_TTL_SEARCH)
        return results

    async def get_comic_meta(self, slug: str) -> dict:
        """Scrape the comic detail page for richer metadata: description, genres, status, views."""
        key = f"rco:meta:{slug}"
        if (hit := cache.get(key)) is not None:
            return hit
        await self._warm_up()
        r = await self._session.get(f"{_BASE}/Comic/{slug}")
        r.raise_for_status()
        soup = BeautifulSoup(r.text, "lxml")

        meta: dict = {
            "description": "",
            "genres": [],
            "status": "",
            "views": "",
            "other_names": "",
            "year": "",
        }

        # Info table — readcomiconline uses table rows with field : value pairs
        for table_sel in ["table.table", ".barContentInfo table", ".col-info table"]:
            info_table = soup.select_one(table_sel)
            if info_table:
                for row in info_table.find_all("tr"):
                    cells = row.find_all("td")
                    if len(cells) < 2:
                        continue
                    label = cells[0].get_text(strip=True).lower().rstrip(":")
                    val_cell = cells[1]
                    val = val_cell.get_text(" ", strip=True)

                    if "status" in label:
                        meta["status"] = self._strip_tags(val)
                    elif "genre" in label:
                        meta["genres"] = [self._strip_tags(a.get_text(strip=True)) for a in val_cell.find_all("a")]
                    elif "view" in label:
                        meta["views"] = self._strip_tags(val)
                    elif "other" in label or "alternative" in label:
                        meta["other_names"] = self._strip_tags(val)
                    elif "year" in label:
                        meta["year"] = self._strip_tags(val)
                    elif "summary" in label or "description" in label:
                        meta["description"] = self._to_rich_html(val_cell)  # keep HTML for styling
                break

        # Description — try several selectors if not in table
        if not meta["description"]:
            for sel in ["p.pdesc", ".description", ".summary", "div.desc", ".barContentInfo p"]:
                el = soup.select_one(sel)
                if el:
                    rich = self._to_rich_html(el)
                    if len(el.get_text(strip=True)) > 30:
                        meta["description"] = rich
                        break

        # Genre links as fallback
        if not meta["genres"]:
            meta["genres"] = list(dict.fromkeys(
                self._strip_tags(a.get_text(strip=True))
                for a in soup.select(".genres a, .genre a, a[href*='Genre']")
                if a.get_text(strip=True)
            ))

        cache.set(key, meta, settings.CACHE_TTL_TRENDING)
        return meta

    async def get_comics_by_genre(self, genre: str, limit: int = 20) -> list[ComicResult]:
        """Scrape /Genre/{genre} — same item grid as search results."""
        key = f"rco:genre:{genre.lower()}:{limit}"
        if (hit := cache.get(key)) is not None:
            return hit
        await self._warm_up()
        r = await self._session.get(f"{_BASE}/Genre/{genre}")
        r.raise_for_status()
        soup = BeautifulSoup(r.text, "lxml")
        results = self._parse_list_items(soup, limit)
        cache.set(key, results, settings.CACHE_TTL_TRENDING)
        return results

    async def get_chapters(
        self, slug: str, language: str = "en", page_size: int = 300
    ) -> list[ComicChapter]:
        r = await self._session.get(f"{_BASE}/Comic/{slug}")
        r.raise_for_status()
        soup = BeautifulSoup(r.text, "lxml")

        chapters: list[ComicChapter] = []
        listing = soup.find("table", class_="listing")
        if not listing:
            return []

        for row in listing.find_all("tr"):
            cells = row.find_all("td")
            if not cells:
                continue
            a = cells[0].find("a")
            if not a:
                continue
            href = a.get("href", "")   # e.g. "/Comic/Batman-2016/Issue-1?id=12345"
            label = a.text.strip()
            date = cells[1].text.strip() if len(cells) > 1 else ""

            # "Batman (2016) Issue #1" → "1"
            m = re.search(r"[Ii]ssue\s*#?\s*(\d+(?:\.\d+)?)", label)
            issue_num = m.group(1) if m else None

            chapters.append(ComicChapter(
                id=href,          # full relative URL + ?id= — used by get_chapter_pages
                title=label,
                chapter_number=issue_num,
                volume=None,
                language="en",
                published_at=date,
            ))

        # rco lists newest-first; reverse so Issue #1 comes first
        chapters.reverse()
        return chapters

    # image URLs are base64-encoded with junk chars injected — reverse-engineered from the site JS

    @staticmethod
    def _step1(s: str) -> str:
        return s[15:33] + s[50:]

    @staticmethod
    def _step2(s: str) -> str:
        return s[: len(s) - 11] + s[-2] + s[-1]

    @staticmethod
    def _baeu(s: str) -> str:
        """Decode one encoded image blob into a full https URL."""
        # Reverse b/h obfuscation (net-zero when called after token→e substitution,
        # but kept for correctness in case the page encodes them separately).
        s = s.replace("pw_.g28x", "b").replace("d2pr.x_27", "h")
        if s.startswith("https"):
            return s

        q_idx = s.find("?")
        query_part = s[q_idx:] if q_idx >= 0 else ""
        is_s0 = "=s0?" in s
        marker = "=s0?" if is_s0 else "=s1600?"
        encoded = s[: s.find(marker)]

        encoded = ReadComicService._step1(encoded)
        encoded = ReadComicService._step2(encoded)

        # Pad to a multiple of 4 before decoding
        pad = (4 - len(encoded) % 4) % 4
        raw = base64.b64decode(encoded + "=" * pad)
        decoded = raw.decode("utf-8", errors="replace")

        # Drop 4 chars at positions 13-16
        decoded = decoded[:13] + decoded[17:]

        # Reattach size suffix (strip last 2 chars first — they're padding artefacts)
        decoded = decoded[:-2] + ("=s0" if is_s0 else "=s1600")

        return "https://2.bp.blogspot.com/" + decoded + query_part

    @staticmethod
    def _decode_pages(html: str) -> list[str]:
        """
        Extract and decode all page image URLs from an rco chapter page.

        The site's JS obfuscates image blobs in *xnz variable assignments,
        one blob per page, ending with ==s1600?rhlupa=… or ==s0?rhlupa=….
        The substitution token is declared as: l.replace(/TOKEN/g, 'e').

        Falls back to the legacy lstImages.push("url") pattern.
        """
        # 1. Find per-request substitution token
        token_m = re.search(r"l\.replace\(/([^/]+)/g,\s*'e'\)", html)
        if token_m:
            token = token_m.group(1)
            # 2. Extract encoded blobs from *xnz variable assignments
            blobs = re.findall(
                r"xnz\s*=\s*'([^']+?=+(?:s1600|s0)\?rhlupa=[^']+)'", html
            )
            if blobs:
                seen: set[str] = set()
                urls: list[str] = []
                for blob in blobs:
                    decoded = ReadComicService._baeu(blob.replace(token, "e"))
                    if decoded.startswith("https") and decoded not in seen:
                        seen.add(decoded)
                        urls.append(decoded)
                if urls:
                    return urls

        # Legacy: lstImages.push("url") or var lstImages = [...]
        urls = re.findall(r'lstImages\.push\(["\']([^"\']+)["\']\)', html)
        if not urls:
            lm = re.search(r'var\s+lstImages\s*=\s*\[([^\]]+)\]', html)
            if lm:
                urls = re.findall(r'"([^"]+)"', lm.group(1))
        return urls

    async def get_chapter_pages(self, issue_href: str) -> list[ChapterPage]:
        """
        issue_href is the full relative URL stored as the chapter ID,
        e.g. "/Comic/Batman-2016/Issue-1?id=12345".

        readType=0 embeds all page URLs in the JS at once.
        quality=hq requests high-resolution scans.
        """
        sep = "&" if "?" in issue_href else "?"
        url = f"{_BASE}{issue_href}{sep}readType=0&quality=hq"
        r = await self._session.get(url)
        r.raise_for_status()

        images = self._decode_pages(r.text)
        pages: list[ChapterPage] = []
        for i, img_url in enumerate(images):
            if not img_url:
                continue
            if not img_url.startswith("http"):
                img_url = f"{_BASE}{img_url}"
            pages.append(ChapterPage(page_number=i + 1, url=img_url))

        return pages
