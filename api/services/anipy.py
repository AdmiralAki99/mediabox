import asyncio
import functools
from pathlib import Path
from typing import Any, Callable, Optional

from anipy_api.download import Downloader
from anipy_api.provider.base import Episode, LanguageTypeEnum
from anipy_api.provider.provider import get_provider

from models.schemas import AnimeEpisode, AnimeInfo, AnimeProvider, AnimeSearchResult, AnimeStream

_PROVIDER_NAMES = ["allanime", "animekai"]


class AnipyService:
    def __init__(self) -> None:
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
        # search is handled by AllAnimeService; this stub keeps the interface consistent
        return []

    async def get_info(self, provider_name: str, identifier: str) -> AnimeInfo:
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
            return AnimeInfo(name=identifier)

    async def get_episodes(
        self,
        provider_name: str,
        identifier: str,
        language: str = "sub",
    ) -> list[AnimeEpisode]:
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
        provider = self._get_provider(provider_name)
        lang = self._lang(language)

        # AllAnime uses "1" not "1.0" -- whole numbers need to be ints
        ep_normalized: Episode = int(episode) if episode == int(episode) else episode

        streams = await self._run_sync(provider.get_video, identifier, ep_normalized, lang)

        result: list[AnimeStream] = []
        for stream in streams:
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
        provider = self._get_provider(provider_name)
        lang = self._lang(language)
        ep_normalized: Episode = int(episode) if episode == int(episode) else episode

        streams = await self._run_sync(provider.get_video, identifier, ep_normalized, lang)
        if not streams:
            raise ValueError(
                f"No streams found for {identifier} episode {episode} ({language})"
            )
        best_stream = max(streams, key=lambda s: s.resolution or 0)

        downloader = Downloader(
            progress_callback=progress_callback,
            info_callback=info_callback,
        )

        final_path: Path = await self._run_sync(
            downloader.download,
            best_stream,
            output_path,
            ".mp4",
        )
        return final_path
