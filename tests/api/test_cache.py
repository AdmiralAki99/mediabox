import asyncio
import time

import pytest

from cache import SimpleCache


def test_get_on_empty_cache_retuns_none():
    cache = SimpleCache()
    assert cache.get("missing") is None


def test_set_then_get_returns_the_value():
    cache = SimpleCache()
    cache.set("key", {"a": 1}, ttl=60)
    assert cache.get("key") == {"a": 1}


def test_set_overwrites_existing_value():
    cache = SimpleCache()
    cache.set("key", "first", ttl=60)
    cache.set("key", "second", ttl=60)
    assert cache.get("key") == "second"


def test_delete_removes_the_key():
    cache = SimpleCache()
    cache.set("key", "value", ttl=60)
    cache.delete("key")
    assert cache.get("key") is None


def test_delete_on_missing_key_does_not_raise():
    cache = SimpleCache()
    cache.delete("never-set")


def test_value_still_present_just_before_ttl_expires():
    cache = SimpleCache()
    cache.set("key", "value", ttl=1)
    assert cache.get("key") == "value"


def test_value_expires_after_ttl(monkeypatch):
    fake_now = [1000.0]
    monkeypatch.setattr(time, "monotonic", lambda: fake_now[0])

    cache = SimpleCache()
    cache.set("key", "value", ttl=10)

    fake_now[0] += 5
    assert cache.get("key") == "value", "shoud still be valid at half the TTL"

    fake_now[0] += 6
    assert cache.get("key") is None, "should be expired just past the TTL"


def test_expired_entry_is_actualy_evicted_from_the_store(monkeypatch):
    fake_now = [0.0]
    monkeypatch.setattr(time, "monotonic", lambda: fake_now[0])

    cache = SimpleCache()
    cache.set("key", "value", ttl=5)
    fake_now[0] = 100.0

    assert cache.get("key") is None
    assert "key" not in cache._store


def test_zero_ttl_is_immediatly_expired(monkeypatch):
    fake_now = [50.0]
    monkeypatch.setattr(time, "monotonic", lambda: fake_now[0])

    cache = SimpleCache()
    cache.set("key", "value", ttl=0)
    assert cache.get("key") is None


def test_independant_caches_do_not_share_state():
    a = SimpleCache()
    b = SimpleCache()
    a.set("key", "from-a", ttl=60)
    assert b.get("key") is None


@pytest.mark.asyncio
async def test_concurrent_sets_on_different_keys_all_land():
    cache = SimpleCache()

    async def write(i: int) -> None:
        cache.set(f"key-{i}", i, ttl=60)

    await asyncio.gather(*(write(i) for i in range(50)))

    for i in range(50):
            assert cache.get(f"key-{i}") == i


@pytest.mark.asyncio
async def test_concurrent_writers_to_the_same_key_last_writer_wins():
    cache = SimpleCache()

    async def write(value: int) -> None:
        await asyncio.sleep(0)
        cache.set("shared", value, ttl=60)

    await asyncio.gather(*(write(i) for i in range(20)))

    assert cache.get("shared") in range(20)


@pytest.mark.asyncio
async def test_many_concurent_readers_see_a_consistent_value():
    cache = SimpleCache()
    cache.set("shared", "stable", ttl=60)

    async def read() -> str | None:
        await asyncio.sleep(0)
        return cache.get("shared")

    results = await asyncio.gather(*(read() for _ in range(100)))
    assert all(r == "stable" for r in results)
