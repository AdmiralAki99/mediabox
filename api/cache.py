import time
from typing import Any


class SimpleCache:
    def __init__(self) -> None:
        self._store: dict[str, tuple[Any, float]] = {}

    def get(self, key: str) -> Any | None:
        entry = self._store.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if time.monotonic() < expires_at:
            return value

        del self._store[key] # expired
        return None

    def set(self, key: str, value: Any, ttl: int) -> None:
        self._store[key] = (value, time.monotonic() + ttl)

    def delete(self, key: str) -> None:
        self._store.pop(key, None)


# Simple cache to reference all over the place
cache = SimpleCache()
