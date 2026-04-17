from __future__ import annotations

import asyncio
import json
import re
from typing import Optional

import httpx

from models.schemas import AnimeEpisode, AnimeInfo, AnimeSearchResult, AnimeStream

_API  = "https://api.allanime.day/api"
_BASE = "https://allanime.day"
_REFR = "https://allmanga.to"
_UA   = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) "
    "Gecko/20100101 Firefox/121.0"
)

# queries ported from ani-cli
_SEARCH_GQL = (
    "query( $search: SearchInput $limit: Int $page: Int"
    " $translationType: VaildTranslationTypeEnumType"
    " $countryOrigin: VaildCountryOriginEnumType ) {"
    " shows( search: $search limit: $limit page: $page"
    " translationType: $translationType countryOrigin: $countryOrigin ) {"
    " edges { _id name availableEpisodes __typename } } }"
)

_EPISODES_GQL = (
    "query ($showId: String!) {"
    " show( _id: $showId ) { _id availableEpisodesDetail } }"
)

_INFO_GQL = (
    "query ($showId: String!) {"
    " show( _id: $showId ) {"
    " _id name description thumbnail genres status"
    " season { year quarter } } }"
)

_STREAM_GQL = (
    "query ($showId: String!, $translationType: VaildTranslationTypeEnumType!,"
    " $episodeString: String!) {"
    " episode( showId: $showId translationType: $translationType"
    " episodeString: $episodeString ) { episodeString sourceUrls } }"
)



def _decode(encoded: str) -> str:
    # XOR-56 per byte pair, figured this out from ani-cli source
    return (
        "".join(
            chr(int(encoded[i : i + 2], 16) ^ 56)
            for i in range(0, len(encoded) - 1, 2)
        )
        .replace("/clock", "/clock.json")
    )


def _parse_resolution(res_str: str) -> Optional[int]:
    m = re.match(r"(\d+)", str(res_str or ""))
    return int(m.group(1)) if m else None


def _expand_wixmp(url: str, language: str) -> list[AnimeStream]:
    # wixmp packs multiple resolutions into one URL — split them into separate streams
    # Strip the repackager prefix, preserve the CDN host
    direct = re.sub(r"^https?://repackager\.wixmp\.com/", "https://", url)
    # Strip .urlset/... suffix
    direct = re.sub(r"\.urlset.*$", "", direct)

    # Extract quality list from segment like /,1080p,720p,480p,/mp4/
    m = re.search(r"/,([^/]+),/mp4/", direct)
    if not m:
        return [AnimeStream(url=direct, language=language, referrer=_REFR)]

    qualities = [q for q in m.group(1).split(",") if q]
    streams: list[AnimeStream] = []
    for q in qualities:
        single = re.sub(r"/,[^/]+,/mp4/", f"/{q}/mp4/", direct)
        streams.append(
            AnimeStream(url=single, resolution=_parse_resolution(q), language=language, referrer=_REFR)
        )
    return sorted(streams, key=lambda s: s.resolution or 0, reverse=True)



class AllAnimeService:

    def __init__(self, http: httpx.AsyncClient) -> None:
        self._http = http
        self._headers = {"User-Agent": _UA, "Referer": _REFR}

    async def _gql(self, query: str, variables: dict) -> dict:
        resp = await self._http.get(
            _API,
            params={"query": query, "variables": json.dumps(variables)},
            headers=self._headers,
            timeout=15,
        )
        resp.raise_for_status()
        return resp.json()

    async def search(
        self, query: str, language: str = "sub"
    ) -> list[AnimeSearchResult]:
        data = await self._gql(
            _SEARCH_GQL,
            {
                "search": {
                    "allowAdult": False,
                    "allowUnknown": False,
                    "query": query,
                },
                "limit": 40,
                "page": 1,
                "translationType": language,
                "countryOrigin": "ALL",
            },
        )
        edges = (data.get("data") or {}).get("shows", {}).get("edges") or []
        results: list[AnimeSearchResult] = []
        for edge in edges:
            avail = edge.get("availableEpisodes") or {}
            langs = [lang for lang in ("sub", "dub") if avail.get(lang, 0)]
            results.append(
                AnimeSearchResult(
                    name=edge["name"],
                    providers=[{"name": "allanime", "identifier": edge["_id"]}],
                    languages=langs or ["sub"],
                )
            )
        return results

    async def get_info(self, identifier: str) -> AnimeInfo:
        try:
            data = await self._gql(_INFO_GQL, {"showId": identifier})
            show = (data.get("data") or {}).get("show") or {}
            year_raw = (show.get("season") or {}).get("year")
            return AnimeInfo(
                name=show.get("name") or identifier,
                image=show.get("thumbnail"),
                genres=list(show.get("genres") or []),
                synopsis=show.get("description"),
                release_year=int(year_raw) if year_raw else None,
                status=show.get("status"),
            )
        except Exception:
            return AnimeInfo(name=identifier)

    async def get_episodes(
        self, identifier: str, language: str = "sub"
    ) -> list[AnimeEpisode]:
        data = await self._gql(_EPISODES_GQL, {"showId": identifier})
        detail = (
            (data.get("data") or {}).get("show", {}).get("availableEpisodesDetail")
            or {}
        )
        eps = detail.get(language) or []
        return sorted(
            [AnimeEpisode(number=float(e)) for e in eps],
            key=lambda e: e.number,
        )

    async def get_streams(
        self, identifier: str, episode: float, language: str = "sub"
    ) -> list[AnimeStream]:
        # AllAnime stores episode strings as "1" not "1.0"
        ep_str = str(int(episode)) if episode == int(episode) else str(episode)
        data = await self._gql(
            _STREAM_GQL,
            {
                "showId": identifier,
                "translationType": language,
                "episodeString": ep_str,
            },
        )
        source_urls = (
            (data.get("data") or {}).get("episode", {}).get("sourceUrls") or []
        )

        # Decode all provider paths first (pure CPU, no I/O)
        paths: list[str] = []
        for src in source_urls:
            raw = src.get("sourceUrl", "")
            if not raw.startswith("--"):
                continue
            try:
                paths.append(_decode(raw[2:]))  # strip "--" prefix then XOR-56 decode
            except Exception:
                continue

        # Resolve all providers in parallel — each is an independent HTTP fetch
        results = await asyncio.gather(
            *[self._resolve_path(p, language) for p in paths],
            return_exceptions=True,
        )
        all_streams: list[AnimeStream] = [
            stream
            for result in results
            if isinstance(result, list)
            for stream in result
        ]

        # Deduplicate by URL, sort best quality first
        seen: set[str] = set()
        unique: list[AnimeStream] = []
        for s in all_streams:
            if s.url not in seen:
                seen.add(s.url)
                unique.append(s)
        unique.sort(key=lambda s: s.resolution or 0, reverse=True)
        return unique

    async def _resolve_path(self, path: str, language: str) -> list[AnimeStream]:
        # fast4speed gives a direct URL, everything else needs a fetch
        if "tools.fast4speed.rsvp" in path:
            url = path if path.startswith("http") else f"https:{path}"
            return [AnimeStream(url=url, language=language, referrer=_REFR)]

        # All other providers: fetch from allanime.day
        try:
            resp = await self._http.get(
                f"{_BASE}{path}",
                headers=self._headers,
                timeout=15,
                follow_redirects=True,
            )
            resp.raise_for_status()
            data = resp.json()
        except Exception:
            return []

        links = data.get("links") or []
        referer: str = data.get("Referer") or _REFR
        streams: list[AnimeStream] = []

        for obj in links:
            url = obj.get("link") or obj.get("url") or ""
            if not url:
                continue

            res_str = obj.get("resolutionStr") or ""
            resolution = _parse_resolution(res_str)

            # wixmp repackager → expand to per-quality direct MP4 URLs
            if "repackager.wixmp.com" in url:
                streams.extend(_expand_wixmp(url, language))
                continue

            # HLS master playlist (hianime / Luf-Mp4)
            if "master.m3u8" in url or obj.get("hls"):
                streams.append(
                    AnimeStream(
                        url=url,
                        resolution=resolution,
                        language=language,
                        referrer=referer,
                    )
                )
                continue

            # Plain MP4 (sharepoint / S-mp4)
            streams.append(
                AnimeStream(
                    url=url,
                    resolution=resolution,
                    language=language,
                    referrer=referer,
                )
            )

        return streams
