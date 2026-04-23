import asyncio
import logging
import re
import time
from typing import Optional

import httpx

from models.schemas import MediaStream

logger = logging.getLogger("mediabox.playwright")

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

# Stream tokens on cloudnestra typically last several hours; 1h is safe.
_CACHE_TTL_S = 3600
_cache: dict[str, tuple[list[MediaStream], float]] = {}

# In-flight deduplication: if two requests race for the same key (React
# StrictMode mounts effects twice in dev), the second waits for the first.
_in_flight: dict[str, asyncio.Event] = {}
_in_flight_result: dict[str, list[MediaStream]] = {}

# hides webdriver fingerprints so the player sites don't block headless chrome
_STEALTH_JS = """
Object.defineProperty(navigator, 'webdriver', {get: () => undefined});

const _pdfPlug = {
    name: 'Chrome PDF Viewer', filename: 'internal-pdf-viewer',
    description: 'Portable Document Format', length: 0,
    namedItem(n) { return n === 'Chrome PDF Viewer' ? this : null; },
    item(i)      { return i === 0 ? this : null; }
};
Object.defineProperty(navigator, 'plugins', {
    get: () => new Proxy([_pdfPlug], {
        get(t, p) {
            if (p === 'namedItem') return n => n === 'Chrome PDF Viewer' ? _pdfPlug : null;
            if (p === 'length') return 1;
            if (p === '0')      return _pdfPlug;
            return t[p];
        }
    })
});

const _origCE = document.createElement.bind(document);
document.createElement = function(tag) {
    const el = _origCE.apply(document, arguments);
    if (typeof tag === 'string' && tag.toLowerCase() === 'object')
        Object.defineProperty(el, 'onerror', {set(){}, get(){return null;}, configurable:true});
    return el;
};

if (!window.chrome)
    Object.defineProperty(window, 'chrome', {
        value: {runtime:{}, loadTimes:()=>({}), csi:()=>({}), app:{}},
        writable: false, configurable: true
    });

Object.defineProperty(navigator, 'languages', {get: () => ['en-US', 'en']});
document.hasFocus = () => true;
try {
    Object.defineProperty(document, 'hidden',          {get: () => false});
    Object.defineProperty(document, 'visibilityState', {get: () => 'visible'});
} catch(e) {}
try { Object.defineProperty(Notification, 'permission', {get: () => 'default'}); } catch(e) {}
"""

# JS snippet that clicks the first play-like element found in a frame.
_CLICK_PLAY_JS = """() => {
    const sels = [
        '[class*="play"]', '[id*="play"]',
        '.jw-display-icon-display', '.jw-icon-display',
        '.plyr__play-large', '.vjs-big-play-button',
        'button', 'video', 'body'
    ];
    for (const s of sels) {
        const el = document.querySelector(s);
        if (el) {
            el.dispatchEvent(new MouseEvent('click',
                {bubbles: true, cancelable: true, view: window}));
            return;
        }
    }
}"""



def _cache_key(tmdb_id: int, season: Optional[int], episode: Optional[int]) -> str:
    return f"{tmdb_id}:{season}:{episode}"


def _cache_get(key: str) -> Optional[list[MediaStream]]:
    entry = _cache.get(key)
    if entry and (time.monotonic() - entry[1]) < _CACHE_TTL_S:
        return entry[0]
    return None


def _cache_set(key: str, streams: list[MediaStream]) -> None:
    _cache[key] = (streams, time.monotonic())



async def _get_rcp_url(embed_url: str) -> Optional[str]:
    async with httpx.AsyncClient() as client:
        try:
            r = await client.get(
                embed_url,
                headers={"User-Agent": _UA, "Referer": "https://vidsrc.to/"},
                timeout=15,
                follow_redirects=True,
            )
        except httpx.HTTPError as exc:
            logger.warning("httpx embed fetch failed for %s: %s", embed_url, exc)
            return None

    if r.status_code != 200:
        logger.warning("embed page %s → HTTP %d", embed_url, r.status_code)
        return None

    hashes = re.findall(r'data-hash="([^"]+)"', r.text)
    if not hashes:
        logger.warning("No data-hash found in embed page: %s", embed_url)
        return None

    rcp_url = f"https://cloudnestra.com/rcp/{hashes[0]}"
    logger.debug("RCP URL: %s…", rcp_url[:80])
    return rcp_url


async def _launch_and_capture(rcp_url: str) -> Optional[str]:
    try:
        from playwright.async_api import async_playwright
    except ImportError:
        logger.error(
            "playwright not installed — "
            "run: pip install playwright && playwright install chromium"
        )
        return None

    m3u8_event: asyncio.Event = asyncio.Event()
    captured: list[str] = []

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-dev-shm-usage",
                "--disable-blink-features=AutomationControlled",
                "--autoplay-policy=no-user-gesture-required",
            ],
        )
        context = await browser.new_context(
            user_agent=_UA,
            extra_http_headers={
                "Referer": "https://vidsrcme.ru/",
                "Origin":  "https://vidsrcme.ru",
            },
        )
        await context.add_init_script(_STEALTH_JS)
        page = await context.new_page()

        def on_request(req):
            if ".m3u8" in req.url and not m3u8_event.is_set():
                logger.debug("m3u8 intercepted: %s", req.url[:120])
                captured.append(req.url)
                m3u8_event.set()

        context.on("request", on_request)

        try:
            await page.goto(rcp_url, wait_until="domcontentloaded", timeout=20_000)

            # Give the player 4s to initialise (fetch TMDB poster, render play button)
            await page.wait_for_timeout(4_000)

            # Click play in main frame and all sub-frames
            for frame in page.frames:
                try:
                    await frame.evaluate(_CLICK_PLAY_JS)
                except Exception:
                    pass

            # Wait up to 25s for the first m3u8 request
            await asyncio.wait_for(m3u8_event.wait(), timeout=25.0)

        except asyncio.TimeoutError:
            logger.warning("25s timeout — no m3u8 from %s", rcp_url[:60])
        except Exception as exc:
            logger.error("Playwright error (%s): %s", rcp_url[:60], exc)
        finally:
            await browser.close()

    return captured[0] if captured else None


async def _resolve_embed(embed_url: str) -> list[MediaStream]:
    # Rewrite vidsrc.to → vidsrcme.ru (bypasses Cloudflare on vidsrc.to)
    embed_url = (
        embed_url
        .replace("https://vidsrc.to/embed/movie/", "https://vidsrcme.ru/embed/movie/")
        .replace("https://vidsrc.to/embed/tv/",    "https://vidsrcme.ru/embed/tv/")
    )
    # vidsrcme.ru requires a trailing slash
    if not embed_url.endswith("/"):
        embed_url += "/"

    rcp_url = await _get_rcp_url(embed_url)
    if not rcp_url:
        return []

    m3u8_url = await _launch_and_capture(rcp_url)
    if not m3u8_url:
        return []

    # The master playlist contains relative quality-variant paths; the
    # /stream/proxy endpoint resolves them and adds the required Referer header.
    return [MediaStream(
        url=m3u8_url,
        resolution=None,
        subtitles=[],
        referrer="https://cloudnestra.com/",
    )]



class PlaywrightResolverService:
    async def _resolve(self, key: str, embed_url: str) -> list[MediaStream]:
        if cached := _cache_get(key):
            logger.debug("Cache hit — %s", key)
            return cached

        if key in _in_flight:
            logger.debug("In-flight wait — %s", key)
            await _in_flight[key].wait()
            return _in_flight_result.get(key, [])

        event = asyncio.Event()
        _in_flight[key] = event
        try:
            streams = await _resolve_embed(embed_url)
            _in_flight_result[key] = streams
            if streams:
                _cache_set(key, streams)
            return streams
        finally:
            event.set()
            _in_flight.pop(key, None)
            _in_flight_result.pop(key, None)

    async def resolve_movie(self, tmdb_id: int) -> list[MediaStream]:
        return await self._resolve(
            _cache_key(tmdb_id, None, None),
            f"https://vidsrc.to/embed/movie/{tmdb_id}",
        )

    async def resolve_tv(self, tmdb_id: int, season: int, episode: int) -> list[MediaStream]:
        return await self._resolve(
            _cache_key(tmdb_id, season, episode),
            f"https://vidsrc.to/embed/tv/{tmdb_id}/{season}/{episode}",
        )
