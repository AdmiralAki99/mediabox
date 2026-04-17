"""
AnipyService — async wrapper around the synchronous anipy-api library.

anipy-api is 100% synchronous. Every call to it must go through
asyncio.get_event_loop().run_in_executor() so the FastAPI event loop
is never blocked.

Providers available:
  "allanime"  — AllAnime GraphQL API (usually more complete)
  "animekai"  — AnimeKai scraping (good fallback)

Typical call flow:
  1. search(query)                        → list[AnimeSearchResult]
  2. get_episodes(provider, id, lang)     → list[AnimeEpisode]
  3. get_stream(provider, id, ep, lang)   → list[AnimeStream]
"""

import asyncio
import functools
from pathlib import Path
from typing import Any, Callable, Optional

from anipy_api.download import Downloader
from anipy_api.provider.base import Episode, LanguageTypeEnum
from anipy_api.provider.provider import get_provider

from models.schemas import AnimeEpisode, AnimeInfo, AnimeProvider, AnimeSearchResult, AnimeStream

# The two providers we expose; expand this list if anipy-api adds more.
_PROVIDER_NAMES = ["allanime", "animekai"]


class AnipyService:
    def __init__(self) -> None:
        # Instantiate providers once at startup; they hold no persistent connections
        # so this is cheap and does not need to be async.
        self._providers: dict[str, Any] = {}
        for name in _PROVIDER_NAMES:
            provider = get_provider(name)
            if provider is not None:
                self._providers[name] = provider

    def _get_provider(self, name: str) -> Any:
        provider = self._providers.get(name)
        if provider is None:
            available = list(self._providers.keys())
            raise ValueError(f"Unknown provider '{name}'. Available: {available}")
        return provider

    @staticmethod
    async def _run_sync(fn, *args) -> Any:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, functools.partial(fn, *args))

    @staticmethod
    def _lang(language: str) -> LanguageTypeEnum:
        return LanguageTypeEnum.DUB if language.lower() == "dub" else LanguageTypeEnum.SUB

    async def search(self, query: str) -> list[AnimeSearchResult]:
        # search all providers at once and merge by title so the frontend gets everything
        """
        # Fire both provider searches in parallel
        tasks = [
            self._run_sync(provider.get_search, query)
            for provider in self._providers.values()
        ]
        raw_results = await asyncio.gather(*tasks, return_exceptions=True)

        # Aggregate by lowercased title → {title: AnimeSearchResult}
        aggregated: dict[str, dict] = {}
        for provider_name, raw in zip(self._providers.keys(), raw_results):
            if isinstance(raw, Exception):
                continue  # skip failing providers gracefully
            for result in raw:
                key = result.name.lower()
                if key not in aggregated:
                    aggregated[key] = {
                        "name": result.name,
                        "providers": [
                            AnimeProvider(name=provider_name, identifier=result.identifier)
                        ],
                        "languages": [lang.value for lang in result.languages],
                    }
                else:
                    # Same anime found on another provider — add it to the list
                    aggregated[key]["providers"].append(
                        AnimeProvider(name=provider_name, identifier=result.identifier)
                    )
                    # Merge language sets
                    existing_langs = set(aggregated[key]["languages"])
                    for lang in result.languages:
                        existing_langs.add(lang.value)
                    aggregated[key]["languages"] = sorted(existing_langs)

        return [AnimeSearchResult(**v) for v in aggregated.values()]

    async def get_info(self, provider_name: str, identifier: str) -> AnimeInfo:
        """
        Fetch detailed anime metadata from the provider.

        Not all providers implement get_info — this method degrades gracefully
        and returns a minimal AnimeInfo if the call fails.
        """
        provider = self._get_provider(provider_name)
        try:
            info = await self._run_sync(provider.get_info, identifier)
            return AnimeInfo(
                name=getattr(info, "name", identifier),
                image=getattr(info, "image", None) or getattr(info, "cover", None),
                genres=list(getattr(info, "genres", []) or []),
                synopsis=getattr(info, "synopsis", None) or getattr(info, "description", None),
                release_year=getattr(info, "release_year", None) or getattr(info, "year", None),
                status=getattr(info, "status", None),
            )
        except Exception:
            # Provider doesn't support get_info or the call failed
            return AnimeInfo(name=identifier)

    async def get_episodes(
        self,
        provider_name: str,
        identifier: str,
        language: str = "sub",
    ) -> list[AnimeEpisode]:
        """
        Return all available episodes for an anime in the requested language.

        anipy-api's get_episodes() returns List[Union[int, float]] — plain
        episode numbers.  We wrap each in AnimeEpisode for a consistent shape.
        """
        provider = self._get_provider(provider_name)
        lang = self._lang(language)
        episodes = await self._run_sync(provider.get_episodes, identifier, lang)
        return [AnimeEpisode(number=float(ep)) for ep in episodes]

    async def get_stream(
        self,
        provider_name: str,
        identifier: str,
        episode: float,
        language: str = "sub",
    ) -> list[AnimeStream]:
        """
        Return ALL available stream qualities for an episode.

        We call provider.get_video() directly (bypassing Anime.get_video which
        would filter to a single quality) so the frontend can pick its own
        preferred resolution.

        ProviderStream has:
          .url          — HLS or direct video URL
          .resolution   — width in pixels (int), e.g. 1080, 720
          .language     — LanguageTypeEnum
          .subtitle     — Optional[Dict[str, ExternalSub]] (provider-supplied subs)
          .referrer     — Optional referrer header needed for playback
        """
        provider = self._get_provider(provider_name)
        lang = self._lang(language)

        # AllAnime uses "1" not "1.0" — whole numbers need to be ints
        ep_normalized: Episode = int(episode) if episode == int(episode) else episode

        streams = await self._run_sync(provider.get_video, identifier, ep_normalized, lang)

        result: list[AnimeStream] = []
        for stream in streams:
            # Extract external subtitle URLs if bundled with the stream
            subtitle_urls: list[str] = []
            if stream.subtitle:
                for sub in stream.subtitle.values():
                    url = getattr(sub, "url", None)
                    if url:
                        subtitle_urls.append(url)

            result.append(
                AnimeStream(
                    url=stream.url,
                    resolution=stream.resolution,
                    language=lang.value,
                    subtitles=subtitle_urls,
                    referrer=getattr(stream, "referrer", None),
                )
            )

        # Sort descending by resolution so the best quality comes first
        result.sort(key=lambda s: s.resolution or 0, reverse=True)
        return result

    async def download_episode(
        self,
        provider_name: str,
        identifier: str,
        episode: float,
        language: str,
        output_path: Path,
        progress_callback: Callable[[float], None],
        info_callback: Callable[[str], None],
    ) -> Path:
        """
        Download an anime episode to disk.

        Resolves the best-quality stream URL first, then hands it to
        anipy-api's Downloader which handles HLS segmenting, retries, and
        optional remuxing to .mp4.

        Both callbacks are called from the executor thread — the caller is
        responsible for making them thread-safe (e.g. via
        asyncio.run_coroutine_threadsafe).

        Args:
            output_path: Destination path WITHOUT extension.
                         Downloader appends the container suffix.
        Returns:
            The final file path with extension.
        """
        provider = self._get_provider(provider_name)
        lang = self._lang(language)
        ep_normalized: Episode = int(episode) if episode == int(episode) else episode

        # 1. Fetch all available streams and pick the highest resolution
        streams = await self._run_sync(provider.get_video, identifier, ep_normalized, lang)
        if not streams:
            raise ValueError(
                f"No streams found for {identifier} episode {episode} ({language})"
            )
        best_stream = max(streams, key=lambda s: s.resolution or 0)

        # 2. Run the synchronous Downloader in the thread pool.
        #    container=".mp4" tells it to remux the HLS stream into an mp4 file.
        downloader = Downloader(
            progress_callback=progress_callback,
            info_callback=info_callback,
        )

        final_path: Path = await self._run_sync(
            downloader.download,
            best_stream,
            output_path,
            ".mp4",   # container — requires ffmpeg
        )
        return final_path
