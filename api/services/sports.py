"""
SportsService — live sports data via the streami.su public API.

No authentication required.  Three endpoints, one async client.

Flow:
  1. get_sports()                        → sport categories (football, basketball, ...)
  2. get_matches(sport_id)               → live/upcoming matches for that sport
  3. get_stream(match_id, src)           → embed URL + viewer count (streami.su raw)
  4. resolve_sport_stream(match_id, src) → scrape embed page for m3u8 URLs

Resolution pipeline (browser-free, uses curl_cffi to bypass Cloudflare):
  a. Try streami.su/api/stream/{match_id}/{source_id} → {"embedUrl": "..."}
  b. Try streamed.su/api/stream/{match_id}/{source_id} as fallback
  c. Fetch the embed page with curl_cffi (impersonates Chrome TLS)
  d. Regex the response HTML/JS for .m3u8 URLs
  e. Also try the streamed.su watch page directly
  f. Return SportStreamResolved with de-duped URLs + correct Referer

Note: this works when the embed player includes the m3u8 URL statically in its
HTML/JS source.  If the player fetches the URL dynamically at runtime (pure JS
XHR/fetch), no m3u8 will be found — a headless browser would be needed for those
sources.  The proxy endpoint still allows playback once URLs are resolved.
"""

import json
import logging
import re

import httpx
from curl_cffi.requests import AsyncSession

from cache import cache
from models.schemas import Match, MatchSource, Sport, SportStream, SportStreamResolved

logger = logging.getLogger(__name__)

_SPORTS_TTL = 3600   # sport categories rarely change — cache 1 hour
_MATCHES_TTL = 60    # live match list — refresh every minute

_BASE_URL = "https://streami.su"

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

# Matches .m3u8 URLs in HTML/JS source — stops at quotes, spaces, angle-brackets
_M3U8_RE = re.compile(r'https?://[^\s\'"\\<>]+\.m3u8(?:[^\s\'"\\<>]*)?')

# Domains to filter out (analytics, tracking pixels, etc.)
_NOISE_DOMAINS = ("google", "analytics", "tracking", "doubleclick", "facebook")


def _referrer_for_urls(urls: list[str]) -> str:
    """
    Determine the correct Referer header for CDN segment requests.
    Mirrors the logic in gonwatch helpers.go openMpv():
      embedsports.top / poocloud.in / vdcast.live → https://embedsports.top/
      strmd.top                                   → https://strmd.top/
    """
    for url in urls:
        if any(d in url for d in ("embedsports.top", "poocloud.in", "vdcast.live")):
            return "https://embedsports.top/"
        if "strmd.top" in url:
            return "https://strmd.top/"
    return ""


def _extract_m3u8(text: str) -> list[str]:
    """Find all .m3u8 URLs in an HTML/JS blob, filtering noise."""
    found = _M3U8_RE.findall(text)
    return [u for u in found if not any(n in u for n in _NOISE_DOMAINS)]


class SportsService:
    def __init__(self) -> None:
        self._client = httpx.AsyncClient(
            base_url=_BASE_URL,
            timeout=15,
            headers={"User-Agent": _UA},
        )

    async def close(self) -> None:
        await self._client.aclose()

    async def get_sports(self) -> list[Sport]:
        """
        Return all available sport categories.

        Response is a flat JSON array:
          [{"id": "football", "name": "Football"}, ...]
        """
        if (hit := cache.get("sports:categories")) is not None:
            return hit
        response = await self._client.get("/api/sports")
        response.raise_for_status()
        result = [Sport(id=s["id"], name=s["name"]) for s in response.json()]
        cache.set("sports:categories", result, _SPORTS_TTL)
        return result

    async def get_matches(self, sport_id: str) -> list[Match]:
        """
        Return live/upcoming matches for one sport category.

        Response array shape:
          [{"id": "...", "title": "...", "sources": [{"source": "...", "id": "..."}]}]
        """
        key = f"sports:matches:{sport_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(f"/api/matches/{sport_id}")
        response.raise_for_status()
        matches = []
        for m in response.json():
            sources = [
                MatchSource(source=s["source"], id=s["id"])
                for s in m.get("sources", [])
            ]
            matches.append(Match(id=m["id"], title=m["title"], sources=sources))
        cache.set(key, matches, _MATCHES_TTL)
        return matches

    async def get_stream(self, match_id: str, source_id: str) -> SportStream:
        """
        Resolve the embed/stream URL for a specific match source.

        Response is an array; we use the first element:
          [{"embedUrl": "https://...", "viewers": 42}]
        """
        response = await self._client.get(f"/api/stream/{match_id}/{source_id}")
        if response.status_code == 404:
            raise ValueError("Stream not available — match may not be live yet")
        response.raise_for_status()
        data = response.json()
        if not data:
            raise ValueError("No stream found for this source")
        first = data[0]
        return SportStream(
            embed_url=first["embedUrl"],
            viewers=first.get("viewers", 0),
        )

    async def resolve_sport_stream(
        self, match_id: str, source_id: str
    ) -> SportStreamResolved:
        """
        Browser-free stream resolution using curl_cffi (Chrome TLS impersonation).

        1. Try streami.su/api/stream for the embed URL.
        2. Try streamed.su/api/stream as fallback.
        3. Fetch the embed URL + the streamed.su watch page with curl_cffi.
        4. Regex each response for .m3u8 URLs embedded in the page source.

        Works when the embed player includes the stream URL statically in HTML/JS.
        Returns an empty URL list if the player loads the URL dynamically (JS-only).
        """
        embed_url: str | None = None

        # ── Step 1: streami.su embed URL ──────────────────────────────────────
        try:
            r = await self._client.get(f"/api/stream/{match_id}/{source_id}")
            if r.status_code == 200:
                data = r.json()
                if data and isinstance(data, list):
                    embed_url = data[0].get("embedUrl")
                    if embed_url:
                        logger.info("Sports: embed URL from streami.su: %s", embed_url[:80])
        except Exception as exc:
            logger.debug("Sports: streami.su stream API unavailable: %s", exc)

        # ── Step 2: streamed.su API fallback ──────────────────────────────────
        if not embed_url:
            try:
                async with AsyncSession(impersonate="chrome124") as sess:
                    r = await sess.get(
                        f"https://streamed.su/api/stream/{match_id}/{source_id}",
                        headers={"Referer": "https://streamed.su/"},
                        timeout=10,
                    )
                    if r.status_code == 200:
                        data = r.json()
                        if data and isinstance(data, list):
                            embed_url = data[0].get("embedUrl")
                            if embed_url:
                                logger.info("Sports: embed URL from streamed.su: %s", embed_url[:80])
            except Exception as exc:
                logger.debug("Sports: streamed.su API: %s", exc)

        # ── Step 3: scrape for .m3u8 URLs ─────────────────────────────────────
        # Build list of pages to check — embed URL first (if available), then
        # the streamed.su watch page as a final fallback.
        pages: list[tuple[str, str]] = []
        if embed_url:
            pages.append((embed_url, "https://streamed.su/"))
        pages.append((f"https://streamed.su/watch/{match_id}", "https://streamed.su/"))

        all_urls: list[str] = []
        async with AsyncSession(impersonate="chrome124") as sess:
            for page_url, referer in pages:
                if all_urls:
                    break
                try:
                    logger.info("Sports: scraping %s", page_url)
                    r = await sess.get(
                        page_url,
                        headers={"Referer": referer, "User-Agent": _UA},
                        timeout=15,
                    )
                    found = _extract_m3u8(r.text)
                    if found:
                        logger.info("Sports: found %d m3u8 URL(s) in page source", len(found))
                        all_urls.extend(found)
                    else:
                        # Try __NEXT_DATA__ JSON (Next.js embedded initial props)
                        m = re.search(
                            r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
                            r.text, re.DOTALL,
                        )
                        if m:
                            found = _extract_m3u8(m.group(1))
                            if found:
                                logger.info(
                                    "Sports: found %d m3u8 URL(s) in __NEXT_DATA__", len(found)
                                )
                                all_urls.extend(found)
                except Exception as exc:
                    logger.debug("Sports: scraping %s failed: %s", page_url, exc)

        # Deduplicate while preserving order
        seen: set[str] = set()
        deduped = [u for u in all_urls if not (u in seen or seen.add(u))]  # type: ignore[func-returns-value]

        if not deduped:
            logger.warning(
                "Sports: no m3u8 URLs found for %s/%s — embed player likely uses dynamic JS",
                match_id, source_id,
            )

        return SportStreamResolved(
            urls=deduped,
            referrer=_referrer_for_urls(deduped),
            source_used="stream",
        )
