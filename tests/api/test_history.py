import asyncio

import pytest


def movie_payload(**overrides) -> dict:
    payload = {
        "media_type": "movie",
        "title": "The Dark Knight",
        "tmdb_id": 155,
        "progress_seconds": 0,
        "completed": False,
    }
    payload.update(overrides)
    return payload


@pytest.mark.asyncio
async def test_empty_history_returns_empty_list(client):
    resp = await client.get("/history")
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_create_history_item_retuns_201(client):
    resp = await client.post("/history", json=movie_payload())
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "The Dark Knight"
    assert body["tmdb_id"] == 155
    assert body["progress_seconds"] == 0
    assert "id" in body and "watched_at" in body


@pytest.mark.asyncio
async def test_created_item_appears_in_listing(client):
    await client.post("/history", json=movie_payload())
    resp = await client.get("/history")
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) == 1
    assert items[0]["title"] == "The Dark Knight"


@pytest.mark.asyncio
async def test_posting_same_content_again_updates_progres_not_creates_new_row(client):
    await client.post("/history", json=movie_payload(progress_seconds=100))
    await client.post("/history", json=movie_payload(progress_seconds=500, completed=True))

    resp = await client.get("/history")
    items = resp.json()
    assert len(items) == 1, "second post for the same movie should update, not duplicate"
    assert items[0]["progress_seconds"] == 500
    assert items[0]["completed"] is True


@pytest.mark.asyncio
async def test_different_episodes_of_same_series_are_seperate_rows(client):
    series = {
        "media_type": "series",
        "title": "Breaking Bad",
        "tmdb_id": 1396,
        "season_num": 1,
        "episode_num": 1,
    }
    await client.post("/history", json=series)
    await client.post("/history", json={**series, "episode_num": 2})

    resp = await client.get("/history")
    items = resp.json()
    assert len(items) == 2
    assert {i["episode_num"] for i in items} == {1, 2}


@pytest.mark.asyncio
async def test_media_type_filter_only_returns_matching_rows(client):
    await client.post("/history", json=movie_payload())
    await client.post("/history", json={"media_type": "manga", "title": "One Piece", "manga_id": "abc-123"})

    resp = await client.get("/history", params={"media_type": "manga"})
    items = resp.json()
    assert len(items) == 1
    assert items[0]["media_type"] == "manga"


@pytest.mark.asyncio
async def test_listing_caps_at_100_most_recent(client):
    for i in range(105):
        await client.post("/history", json=movie_payload(tmdb_id=i, title=f"movie-{i}"))

    resp = await client.get("/history")
    assert len(resp.json()) == 100


@pytest.mark.asyncio
async def test_delete_history_item_removes_it(client):
    create = await client.post("/history", json=movie_payload())
    item_id = create.json()["id"]

    resp = await client.delete(f"/history/{item_id}")
    assert resp.status_code == 204

    listing = await client.get("/history")
    assert listing.json() == []


@pytest.mark.asyncio
async def test_delete_unknown_history_item_returns_404(client):
    resp = await client.delete("/history/999999")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_clear_history_reports_count_and_empties_table(client):
    await client.post("/history", json=movie_payload(tmdb_id=1, title="a"))
    await client.post("/history", json=movie_payload(tmdb_id=2, title="b"))

    resp = await client.delete("/history")
    assert resp.status_code == 200
    assert resp.json() == {"deleted": 2}

    listing = await client.get("/history")
    assert listing.json() == []


@pytest.mark.asyncio
async def test_chapter_bookmark_returns_latest_match(client):
    await client.post(
        "/history",
        json={"media_type": "manga", "title": "One Piece", "manga_id": "m1", "chapter_id": "ch-1", "page_index": 3},
    )

    resp = await client.get("/history/chapter/ch-1")
    assert resp.status_code == 200
    assert resp.json()["page_index"] == 3


@pytest.mark.asyncio
async def test_chapter_bookmark_for_unknown_chapter_returns_null_body(client):
    resp = await client.get("/history/chapter/does-not-exist")
    assert resp.status_code == 200
    assert resp.json() is None


@pytest.mark.asyncio
async def test_concurent_upserts_for_the_same_item(client):
    results = await asyncio.gather(
        client.post("/history", json=movie_payload(progress_seconds=111)),
        client.post("/history", json=movie_payload(progress_seconds=222)),
    )
    assert all(r.status_code == 201 for r in results)

    listing = await client.get("/history")
    items = listing.json()
    assert len(items) in (1, 2)
    progress_values = {i["progress_seconds"] for i in items}
    assert progress_values <= {111, 222}


@pytest.mark.asyncio
async def test_concurrent_upserts_for_diferent_items_never_collide(client):
    results = await asyncio.gather(
        *(client.post("/history", json=movie_payload(tmdb_id=i, title=f"movie-{i}")) for i in range(10))
    )
    assert all(r.status_code == 201 for r in results)

    listing = await client.get("/history")
    assert len(listing.json())   == 10


@pytest.mark.asyncio
async def test_missing_required_field_returns_422(client):
    resp = await client.post("/history", json={"title": "no media_type"})
    assert resp.status_code == 422
