import logging
import re

import httpx

from models.schemas import MediaStream

logger = logging.getLogger("mediabox.flixhq")

_BASE = "https://flixhq.to"
_DEC  = "https://dec.eatmynerds.live"
_UA   = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)
_HEADERS = {
    "User-Agent": _UA,
    "Referer": _BASE + "/",
    "X-Requested-With": "XMLHttpRequest",
}


class FlixHQService:
    def __init__(self, http: httpx.AsyncClient) -> None:
        self._http = http


    async def search(self, query: str) -> list[dict]:
        q = query.replace(" ", "-")
        resp = await self._http.get(
            f"{_BASE}/search/{q}",
            headers=_HEADERS,
            follow_redirects=True,
            timeout=15,
        )
        resp.raise_for_status()
        results = self._parse_search(resp.text)
        logger.debug("FlixHQ search %r → %d results", query, len(results))
        return results

    async def get_movie_streams(
        self, media_id: str, provider: str = "Vidcloud"
    ) -> list[MediaStream]:
        server_ids = await self._get_all_movie_server_ids(media_id, provider)
        for episode_id in server_ids:
            try:
                embed_link = await self._get_embed_link(episode_id)
                streams = await self._decrypt(embed_link)
                if streams:
                    return streams
            except Exception as exc:
                logger.warning("Movie server episode_id=%s failed: %s", episode_id, exc)
        return []

    async def get_tv_streams(
        self,
        media_id: str,
        season: int,
        episode: int,
        provider: str = "Vidcloud",
    ) -> list[MediaStream]:
        season_id  = await self._get_season_id(media_id, season)
        data_id    = await self._get_episode_data_id(season_id, episode)
        server_ids = await self._get_all_tv_server_ids(data_id, provider)
        for episode_id in server_ids:
            try:
                embed_link = await self._get_embed_link(episode_id)
                streams = await self._decrypt(embed_link)
                if streams:
                    return streams
            except Exception as exc:
                logger.warning("TV server episode_id=%s failed: %s", episode_id, exc)
        return []


    def _parse_search(self, html: str) -> list[dict]:
        results: list[dict] = []
        for chunk in html.split('class="flw-item"')[1:]:
            m = re.search(
                r'data-src="([^"]*)".*?'
                r'href="/(tv|movie)/watch-[^"]*?-(\d+)"[^>]*?title="([^"]*)".*?'
                r'class="fdi-item">([^<]*)',
                chunk, re.DOTALL,
            )
            if m:
                results.append({
                    "image": m.group(1),
                    "type":  m.group(2),
                    "id":    m.group(3),
                    "title": m.group(4),
                    "year":  m.group(5).strip(),
                })
        return results


    async def _get_all_movie_server_ids(
        self, media_id: str, provider: str
    ) -> list[str]:
        resp = await self._http.get(
            f"{_BASE}/ajax/movie/episodes/{media_id}",
            headers=_HEADERS,
            timeout=15,
        )
        resp.raise_for_status()
        flat = resp.text.replace("\n", " ")

        servers: list[tuple[str, str]] = []
        for m in re.finditer(r'href="([^"]*)"[^>]*?title="([^"]*)"', flat):
            url, name = m.group(1), m.group(2)
            # URL format: /watch/movie-title-{media_id}.{episode_id}
            ep_m = re.search(r'-(\d+)\.(\d+)$', url)
            if ep_m:
                servers.append((ep_m.group(2), name))

        if not servers:
            raise ValueError(f"No servers found for movie media_id={media_id}")

        preferred = [(eid, n) for eid, n in servers if provider.lower() in n.lower()]
        others    = [(eid, n) for eid, n in servers if provider.lower() not in n.lower()]
        ordered   = preferred + others
        logger.debug("Movie servers: %s", [(n, eid) for eid, n in ordered])
        return [eid for eid, _ in ordered]


    async def _get_season_id(self, media_id: str, season_number: int) -> str:
        resp = await self._http.get(
            f"{_BASE}/ajax/v2/tv/seasons/{media_id}",
            headers=_HEADERS,
            timeout=15,
        )
        resp.raise_for_status()
        # Pattern (from lobster): href="...-{season_id}">{Name}</a>
        seasons = re.findall(r'href=".*?-(\d+)">(.*?)</a>', resp.text, re.DOTALL)
        if not seasons:
            raise ValueError(f"No seasons found for media_id={media_id}")
        idx = season_number - 1
        if idx >= len(seasons):
            raise ValueError(
                f"Season {season_number} not found (show has {len(seasons)} season(s))"
            )
        logger.debug("Season %d → id=%s", season_number, seasons[idx][0])
        return seasons[idx][0]

    async def _get_episode_data_id(self, season_id: str, episode_number: int) -> str:
        resp = await self._http.get(
            f"{_BASE}/ajax/v2/season/episodes/{season_id}",
            headers=_HEADERS,
            timeout=15,
        )
        resp.raise_for_status()
        flat = resp.text.replace("\n", " ")
        episodes: list[tuple[str, str]] = []
        for chunk in flat.split('class="nav-item"')[1:]:
            m = re.search(r'data-id="(\d+)".*?title="([^"]*)"', chunk)
            if m:
                episodes.append((m.group(1), m.group(2)))
        if not episodes:
            raise ValueError(f"No episodes found for season_id={season_id}")
        idx = episode_number - 1
        if idx >= len(episodes):
            raise ValueError(
                f"Episode {episode_number} not found (season has {len(episodes)} episode(s))"
            )
        logger.debug("Episode %d → data_id=%s (%s)", episode_number, episodes[idx][0], episodes[idx][1])
        return episodes[idx][0]

    async def _get_all_tv_server_ids(
        self, data_id: str, provider: str
    ) -> list[str]:
        resp = await self._http.get(
            f"{_BASE}/ajax/v2/episode/servers/{data_id}",
            headers=_HEADERS,
            timeout=15,
        )
        resp.raise_for_status()
        flat = resp.text.replace("\n", " ")
        servers: list[tuple[str, str]] = []
        for chunk in flat.split('class="nav-item"')[1:]:
            m = re.search(r'data-id="(\d+)".*?title="([^"]*)"', chunk)
            if m:
                servers.append((m.group(1), m.group(2)))
        if not servers:
            raise ValueError(f"No servers found for data_id={data_id}")
        preferred = [(eid, n) for eid, n in servers if provider.lower() in n.lower()]
        others    = [(eid, n) for eid, n in servers if provider.lower() not in n.lower()]
        ordered   = preferred + others
        logger.debug("TV servers: %s", [(n, eid) for eid, n in ordered])
        return [eid for eid, _ in ordered]


    async def _get_embed_link(self, episode_id: str) -> str:
        resp = await self._http.get(
            f"{_BASE}/ajax/episode/sources/{episode_id}",
            headers=_HEADERS,
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        link = data.get("link")
        if not link:
            raise ValueError(f"No link in episode sources for episode_id={episode_id}: {data}")
        logger.debug("Embed link: %s…", link[:60])
        return link

    async def _decrypt(self, embed_link: str) -> list[MediaStream]:
        try:
            resp = await self._http.get(
                _DEC,
                params={"url": embed_link},
                headers={"User-Agent": _UA, "Referer": _BASE + "/"},
                timeout=20,
            )
            resp.raise_for_status()
            data = resp.json()
            base_url = data.get("file", "")
            if base_url:
                tracks = data.get("tracks", [])
                subtitles = [
                    t["file"]
                    for t in tracks
                    if t.get("file") and t.get("kind") in ("captions", "subtitles")
                ]
                logger.debug("dec.eatmynerds.live — base: %s…  subs: %d", base_url[:60], len(subtitles))
                return self._build_streams(base_url, subtitles, _BASE + "/")
        except Exception as exc:
            logger.debug("dec.eatmynerds.live failed (%s), trying Megacloud direct API", exc)

        return await self._megacloud_sources(embed_link)

    async def _megacloud_sources(self, embed_url: str) -> list[MediaStream]:
        m = re.search(r'https?://([^/?#]+)/(embed-\d+)/v\d+/e-\d+/([A-Za-z0-9_-]+)', embed_url)
        if not m:
            raise ValueError(f"Embed URL does not match Megacloud pattern: {embed_url[:80]}")

        origin     = f"https://{m.group(1)}"
        embed_type = m.group(2)   # e.g. "embed-1"
        embed_id   = m.group(3)
        api_url    = f"{origin}/{embed_type}/ajax/getSources?id={embed_id}"

        logger.debug("Megacloud direct API: %s", api_url)
        resp = await self._http.get(api_url, headers={
            "User-Agent": _UA,
            "Referer":    embed_url,
            "X-Requested-With": "XMLHttpRequest",
        }, timeout=15)
        resp.raise_for_status()
        data = resp.json()

        sources_raw = data.get("sources", [])
        encrypted   = data.get("encrypted", False)

        logger.debug(
            "Megacloud getSources: encrypted=%s sources_type=%s",
            encrypted, type(sources_raw).__name__,
        )

        # If sources is a string (base64) or encrypted flag is set, we can't decode without the AES key
        if encrypted or isinstance(sources_raw, str):
            raise ValueError(
                f"Megacloud sources for id={embed_id} are AES-encrypted — key extraction not yet implemented"
            )

        tracks = data.get("tracks", [])
        subtitles = [
            t["file"]
            for t in tracks
            if t.get("file") and t.get("kind") in ("captions", "subtitles")
        ]
        logger.debug("Megacloud direct — sources: %d  subs: %d", len(sources_raw), len(subtitles))

        streams: list[MediaStream] = []
        for src in sources_raw:
            file_url = src.get("file", "")
            if file_url:
                streams.extend(self._build_streams(file_url, subtitles, origin + "/"))
        return streams

    def _build_streams(
        self, base_url: str, subtitles: list[str], referrer: str
    ) -> list[MediaStream]:
        if "playlist.m3u8" in base_url:
            prefix = base_url.replace("/playlist.m3u8", "")
            return [
                MediaStream(url=f"{prefix}/{q}/index.m3u8", resolution=q,
                            subtitles=subtitles, referrer=referrer)
                for q in (1080, 720, 480, 360)
            ]
        return [MediaStream(url=base_url, resolution=None, subtitles=subtitles, referrer=referrer)]
