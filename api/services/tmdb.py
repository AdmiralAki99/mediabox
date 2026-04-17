import httpx

from cache import cache
from config import settings
from models.schemas import CastMember, Episode, Movie, MovieMeta, Review, Season, Series, SeriesMeta


class TMDBService:
    def __init__(self) -> None:
        self._client = httpx.AsyncClient(
            base_url=settings.TMDB_BASE_URL,
            headers={"Authorization": f"Bearer {settings.TMDB_BEARER_TOKEN}"},
            timeout=settings.REQUEST_TIMEOUT,
        )

    async def close(self) -> None:
        await self._client.aclose()

    def _parse_movie(self, data: dict) -> Movie:
        return Movie(
            id=data["id"],
            title=data.get("title", data.get("name", "")),
            overview=data.get("overview", ""),
            release_date=data.get("release_date", ""),
            rating=data.get("vote_average", 0.0),
            poster_path=data.get("poster_path"),
        )

    async def search_movies(self, query: str) -> list[Movie]:
        key = f"movies:search:{query.lower()}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/search/movie",
            params={"query": query, "include_adult": "true", "language": "en-US", "page": "1"},
        )
        response.raise_for_status()
        result = [self._parse_movie(m) for m in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_SEARCH)
        return result

    async def get_trending_movies(self) -> list[Movie]:
        key = "movies:trending"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get("/trending/movie/week")
        response.raise_for_status()
        result = [self._parse_movie(m) for m in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_now_playing_movies(self) -> list[Movie]:
        key = "movies:now_playing"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get("/movie/now_playing", params={"language": "en-US", "page": "1"})
        response.raise_for_status()
        result = [self._parse_movie(m) for m in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_top_rated_movies(self) -> list[Movie]:
        key = "movies:top_rated"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get("/movie/top_rated", params={"language": "en-US", "page": "1"})
        response.raise_for_status()
        result = [self._parse_movie(m) for m in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_movies_by_genre(self, genre_id: int) -> list[Movie]:
        key = f"movies:genre:{genre_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/discover/movie",
            params={"with_genres": str(genre_id), "sort_by": "popularity.desc", "language": "en-US", "page": "1"},
        )
        response.raise_for_status()
        result = [self._parse_movie(m) for m in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_movie_credits(self, movie_id: int) -> list[CastMember]:
        key = f"movies:credits:{movie_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(f"/movie/{movie_id}/credits")
        response.raise_for_status()
        cast_data = response.json().get("cast", [])[:20]
        result = [
            CastMember(
                id=p["id"],
                name=p["name"],
                character=p.get("character", ""),
                profile_path=p.get("profile_path"),
            )
            for p in cast_data
        ]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    def _parse_series(self, data: dict) -> Series:
        country = data.get("origin_country") or []
        return Series(
            id=data["id"],
            title=data.get("name", data.get("title", "")),
            overview=data.get("overview", ""),
            first_air_date=data.get("first_air_date", ""),
            rating=data.get("vote_average", 0.0),
            poster_path=data.get("poster_path"),
            country=country[0] if country else None,
        )

    async def search_series(self, query: str) -> list[Series]:
        key = f"series:search:{query.lower()}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/search/tv",
            params={"query": query, "include_adult": "true", "language": "en-US", "page": "1"},
        )
        response.raise_for_status()
        result = [self._parse_series(s) for s in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_SEARCH)
        return result

    async def get_trending_series(self) -> list[Series]:
        key = "series:trending"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get("/trending/tv/week")
        response.raise_for_status()
        result = [self._parse_series(s) for s in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_seasons(self, tmdb_id: int) -> list[Season]:
        key = f"series:seasons:{tmdb_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(f"/tv/{tmdb_id}", params={"language": "en-US"})
        response.raise_for_status()
        seasons_data = response.json().get("seasons", [])
        return [
            Season(
                series_id=tmdb_id,
                season_number=s["season_number"],
                title=s.get("name", ""),
                overview=s.get("overview", ""),
                episode_count=s.get("episode_count", 0),
                release_date=s.get("air_date") or "",
            )
            for s in seasons_data
            if s["season_number"] != 0
        ]

    async def search_anime(self, query: str) -> list[Series]:
        key = f"anime:tmdb:search:{query.lower()}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/search/tv",
            params={"query": query, "include_adult": "false", "language": "en-US", "page": "1"},
        )
        response.raise_for_status()
        result = [
            self._parse_series(s)
            for s in response.json().get("results", [])
            if s.get("original_language") == "ja"
        ]
        cache.set(key, result, settings.CACHE_TTL_SEARCH)
        return result

    async def get_trending_anime(self) -> list[Series]:
        key = "anime:tmdb:trending"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/discover/tv",
            params={
                "with_original_language": "ja",
                "with_genres": "16",
                "sort_by": "popularity.desc",
                "language": "en-US",
                "page": "1",
            },
        )
        response.raise_for_status()
        result = [self._parse_series(s) for s in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_top_rated_anime(self) -> list[Series]:
        key = "anime:tmdb:top_rated"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/discover/tv",
            params={
                "with_original_language": "ja",
                "with_genres": "16",
                "sort_by": "vote_average.desc",
                "vote_count.gte": "200",
                "language": "en-US",
                "page": "1",
            },
        )
        response.raise_for_status()
        result = [self._parse_series(s) for s in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_airing_now_anime(self) -> list[Series]:
        key = "anime:tmdb:airing_now"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/discover/tv",
            params={
                "with_original_language": "ja",
                "with_genres": "16",
                "sort_by": "popularity.desc",
                "with_status": "0",  # 0 = returning series (currently airing)
                "language": "en-US",
                "page": "1",
            },
        )
        response.raise_for_status()
        result = [self._parse_series(s) for s in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_action_anime(self) -> list[Series]:
        key = "anime:tmdb:action"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            "/discover/tv",
            params={
                "with_original_language": "ja",
                "with_genres": "16,28",  # Animation + Action
                "sort_by": "popularity.desc",
                "language": "en-US",
                "page": "1",
            },
        )
        response.raise_for_status()
        result = [self._parse_series(s) for s in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_upcoming_movies(self) -> list[Movie]:
        key = "movies:upcoming"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get("/movie/upcoming", params={"language": "en-US", "page": "1"})
        response.raise_for_status()
        result = [self._parse_movie(m) for m in response.json().get("results", [])]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_movie_meta(self, movie_id: int) -> MovieMeta:
        key = f"movies:meta:{movie_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(f"/movie/{movie_id}", params={"language": "en-US"})
        response.raise_for_status()
        data = response.json()
        result = MovieMeta(
            backdrop_path=data.get("backdrop_path"),
            genres=[g["name"] for g in data.get("genres", [])],
            runtime=data.get("runtime") or None,
            overview=data.get("overview", ""),
            tagline=data.get("tagline", ""),
            production_companies=[c["name"] for c in data.get("production_companies", [])[:4]],
            budget=data.get("budget") or None,
            revenue=data.get("revenue") or None,
            spoken_languages=[lang["english_name"] for lang in data.get("spoken_languages", [])],
        )
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_series_meta(self, series_id: int) -> SeriesMeta:
        key = f"series:meta:{series_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(f"/tv/{series_id}", params={"language": "en-US"})
        response.raise_for_status()
        data = response.json()
        result = SeriesMeta(
            backdrop_path=data.get("backdrop_path"),
            genres=[g["name"] for g in data.get("genres", [])],
            status=data.get("status"),
            last_air_date=data.get("last_air_date") or None,
            overview=data.get("overview", ""),
            tagline=data.get("tagline", ""),
            production_companies=[c["name"] for c in data.get("production_companies", [])[:3]],
            networks=[n["name"] for n in data.get("networks", [])[:3]],
            created_by=[p["name"] for p in data.get("created_by", [])],
            number_of_seasons=data.get("number_of_seasons"),
            number_of_episodes=data.get("number_of_episodes"),
        )
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_movie_reviews(self, movie_id: int) -> list[Review]:
        key = f"movies:reviews:{movie_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            f"/movie/{movie_id}/reviews", params={"language": "en-US", "page": "1"}
        )
        response.raise_for_status()
        result = [
            Review(
                author=r.get("author", ""),
                rating=r.get("author_details", {}).get("rating"),
                content=r.get("content", "")[:600],
                created_at=(r.get("created_at") or "")[:10],
            )
            for r in response.json().get("results", [])[:5]
        ]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_series_reviews(self, series_id: int) -> list[Review]:
        key = f"series:reviews:{series_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(
            f"/tv/{series_id}/reviews", params={"language": "en-US", "page": "1"}
        )
        response.raise_for_status()
        result = [
            Review(
                author=r.get("author", ""),
                rating=r.get("author_details", {}).get("rating"),
                content=r.get("content", "")[:600],
                created_at=(r.get("created_at") or "")[:10],
            )
            for r in response.json().get("results", [])[:5]
        ]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_series_credits(self, series_id: int) -> list[CastMember]:
        key = f"series:credits:{series_id}"
        if (hit := cache.get(key)) is not None:
            return hit
        response = await self._client.get(f"/tv/{series_id}/credits")
        response.raise_for_status()
        result = [
            CastMember(
                id=p["id"],
                name=p["name"],
                character=p.get("character", ""),
                profile_path=p.get("profile_path"),
            )
            for p in response.json().get("cast", [])[:20]
        ]
        cache.set(key, result, settings.CACHE_TTL_TRENDING)
        return result

    async def get_trailer_key(self, tmdb_id: int, media_type: str) -> str | None:
        """Return the YouTube key for the first official Trailer, or None."""
        endpoint = f"/{media_type}/{tmdb_id}/videos"
        response = await self._client.get(endpoint, params={"language": "en-US"})
        response.raise_for_status()
        results = response.json().get("results", [])
        for video in results:
            if video.get("type") == "Trailer" and video.get("site") == "YouTube":
                return video.get("key")
        return None

    async def get_episodes(self, tmdb_id: int, season_number: int) -> list[Episode]:
        response = await self._client.get(
            f"/tv/{tmdb_id}/season/{season_number}",
            params={"language": "en-US"},
        )
        response.raise_for_status()
        episodes_data = response.json().get("episodes", [])
        return [
            Episode(
                episode_id=e["id"],
                episode_number=e["episode_number"],
                season_number=e["season_number"],
                title=e.get("name", ""),
                overview=e.get("overview", ""),
                release_date=e.get("air_date") or "",
                runtime=e.get("runtime"),
            )
            for e in episodes_data
        ]
