import asyncio
from pathlib import Path
from unittest.mock import AsyncMock

import pytest

from routers import downloads as downloads_module


def download_payload(**overrides) -> dict:
    payload = {
        "provider_name": "allanime",
        "identifier": "abc123",
        "anime_title": "Test Anime",
        "episode": 1.0,
        "language": "sub",
    }
    payload.update(overrides)
    return payload


@pytest.mark.asyncio
async def test_queue_download_returns_202_with_queued_status(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "episode_1.mp4"

    resp = await client_with_anipy.post("/downloads", json=download_payload())
    assert resp.status_code == 202
    body = resp.json()
    assert body["anime_title"] == "Test Anime"
    assert body["progress"] in (0.0, 100.0)


@pytest.mark.asyncio
async def test_succesful_download_ends_with_completed_status(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    final_path = tmp_path / "Test Anime" / "episode_1.mp4"
    fake_anipy.download_episode.return_value = final_path

    create = await client_with_anipy.post("/downloads", json=download_payload())
    download_id = create.json()["id"]

    resp = await client_with_anipy.get(f"/downloads/{download_id}")
    body = resp.json()
    assert body["status"] == "completed"
    assert body["progress"] == 100.0
    assert body["file_path"] == str(final_path)


@pytest.mark.asyncio
async def test_failed_download_records_error_message(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.side_effect = RuntimeError("provider returned no streams")

    create = await client_with_anipy.post("/downloads", json=download_payload())
    download_id = create.json()["id"]

    resp = await client_with_anipy.get(f"/downloads/{download_id}")
    body = resp.json()
    assert body["status"] == "failed"
    assert "no streams" in body["error_message"]


@pytest.mark.asyncio
async def test_anime_title_is_sanitised_for_the_output_directory(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "out.mp4"

    await client_with_anipy.post("/downloads", json=download_payload(anime_title="Naruto: Shippuden / Special?"))

    output_path = fake_anipy.download_episode.call_args.kwargs["output_path"]
    assert "/" not in output_path.name
    assert "?" not in str(output_path.parent.name)


@pytest.mark.asyncio
async def test_fractional_episode_keeps_decimal_in_filename(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "out.mp4"

    await client_with_anipy.post("/downloads", json=download_payload(episode=5.5))

    output_path = fake_anipy.download_episode.call_args.kwargs["output_path"]
    assert output_path.name == "episode_5.5"


@pytest.mark.asyncio
async def test_whole_number_episode_has_no_decimal_in_filename(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "out.mp4"

    await client_with_anipy.post("/downloads", json=download_payload(episode=3.0))

    output_path = fake_anipy.download_episode.call_args.kwargs["output_path"]
    assert output_path.name == "episode_3"


@pytest.mark.asyncio
async def test_get_unkown_download_returns_404(client):
    resp = await client.get("/downloads/999999")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_list_downloads_orders_newest_first(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "out.mp4"

    await client_with_anipy.post("/downloads", json=download_payload(identifier="first"))
    await client_with_anipy.post("/downloads", json=download_payload(identifier="second"))

    resp = await client_with_anipy.get("/downloads")
    identifiers = [row["identifier"] for row in resp.json()]
    assert sorted(identifiers) == ["first", "second"]


@pytest.mark.asyncio
async def test_cancel_unknown_download_returns_404(client):
    resp = await client.delete("/downloads/999999")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_cancel_queued_download_just_deletes_the_row(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "out.mp4"

    create = await client_with_anipy.post("/downloads", json=download_payload())
    download_id = create.json()["id"]

    resp = await client_with_anipy.delete(f"/downloads/{download_id}")
    assert resp.status_code == 204

    follow_up = await client_with_anipy.get(f"/downloads/{download_id}")
    assert follow_up.status_code == 404


@pytest.mark.asyncio
async def test_cancel_completed_download_deletes_the_file_from_disk(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    final_path = tmp_path / "Test Anime" / "episode_1.mp4"
    final_path.parent.mkdir(parents=True)
    final_path.write_bytes(b"fake video data")
    fake_anipy.download_episode.return_value = final_path

    create = await client_with_anipy.post("/downloads", json=download_payload())
    download_id = create.json()["id"]
    assert (await client_with_anipy.get(f"/downloads/{download_id}")).json()["status"] == "completed"

    resp = await client_with_anipy.delete(f"/downloads/{download_id}")
    assert resp.status_code == 204
    assert not final_path.exists()


@pytest.mark.asyncio
async def test_cancelling_an_in_progress_download_signals_the_worker(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))

    from models.db_models import Download

    create = await client_with_anipy.post("/downloads", json=download_payload())
    download_id = create.json()["id"]

    from main import app
    from database import get_db as get_db_dep

    override = app.dependency_overrides[get_db_dep]
    async for session in override():
        row = await session.get(Download, download_id)
        row.status = "downloading"
        await session.commit()
        break

    resp = await client_with_anipy.delete(f"/downloads/{download_id}")
    assert resp.status_code == 204
    assert download_id in downloads_module._cancelled


@pytest.mark.asyncio
async def test_progress_callback_only_writes_on_5_percent_jumps(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    from routers.downloads import _run_download
    from models.schemas import DownloadRequest

    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))

    async def fake_download_episode(**kwargs):
        progress_cb = kwargs["progress_callback"]
        for pct in (1.0, 2.0, 10.0, 11.0, 20.0, 100.0):
                progress_cb(pct)
        return tmp_path / "out.mp4"

    fake_anipy.download_episode.side_effect = fake_download_episode

    from main import app
    from database import get_db as get_db_dep
    from models.db_models import Download

    override = app.dependency_overrides[get_db_dep]

    async for session in override():
        row = Download(
            provider_name="allanime", identifier="x", anime_title="t",
            episode=1.0, language="sub", status="queued", progress=0.0,
        )
        session.add(row)
        await session.commit()
        await session.refresh(row)
        download_id = row.id
        break

    request = DownloadRequest(**download_payload())
    await _run_download(download_id, request, fake_anipy)

    async for session in override():
        final_row = await session.get(Download, download_id)
        assert final_row.status == "completed"
        assert final_row.progress == 100.0
        break


@pytest.mark.asyncio
async def test_get_file_for_incomplete_download_returns_409(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.side_effect = RuntimeError("boom")

    create = await client_with_anipy.post("/downloads", json=download_payload())
    download_id = create.json()["id"]

    resp = await client_with_anipy.get(f"/downloads/file/{download_id}")
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_get_file_for_unknown_download_returns_404(client):
    resp = await client.get("/downloads/file/999999")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_get_file_missing_from_disk_returns_404_even_if_completed(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "ghost.mp4"

    create = await client_with_anipy.post("/downloads", json=download_payload())
    download_id = create.json()["id"]

    resp = await client_with_anipy.get(f"/downloads/file/{download_id}")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_concurrent_download_requests_each_get_a_distinct_id(client_with_anipy, fake_anipy, tmp_path, monkeypatch):
    monkeypatch.setattr("config.settings.DOWNLOAD_DIR", str(tmp_path))
    fake_anipy.download_episode.return_value = tmp_path / "out.mp4"

    responses = await asyncio.gather(
        *(client_with_anipy.post("/downloads", json=download_payload(identifier=f"id-{i}")) for i in range(8))
    )
    assert all(r.status_code == 202 for r in responses)
    ids = [r.json()["id"] for r in responses]
    assert len(set(ids)) == 8, "every queued download should get its own row, no id collisions"
