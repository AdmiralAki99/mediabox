import asyncio
import sys
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

API_DIR = Path(__file__).resolve().parents[2] / "api"
if str(API_DIR) not in sys.path:
    sys.path.insert(0, str(API_DIR))

from database import get_db
from models.db_models import Base
from routers.downloads import get_anipy_service


@pytest_asyncio.fixture
async def db_engine():
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def app(db_engine, monkeypatch):
    from main import app as fastapi_app

    session_factory = async_sessionmaker(db_engine, expire_on_commit=False)

    async def _get_db():
        async with session_factory() as session:
                yield session

    fastapi_app.dependency_overrides[get_db] = _get_db

    monkeypatch.setattr("database.AsyncSessionLocal", session_factory)
    monkeypatch.setattr("routers.downloads.AsyncSessionLocal", session_factory)

    yield fastapi_app
    fastapi_app.dependency_overrides.pop(get_db, None)


@pytest_asyncio.fixture
async def client(app):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture(autouse=True)
def _reset_module_globals():
    from routers import downloads as downloads_module
    from cache import cache

    downloads_module._cancelled.clear()
    cache._store.clear()
    yield
    downloads_module._cancelled.clear()
    cache._store.clear()


@pytest.fixture
def fake_anipy():
    from unittest.mock import AsyncMock
    return AsyncMock()


@pytest_asyncio.fixture
async def client_with_anipy(app, fake_anipy):
    app.dependency_overrides[get_anipy_service] = lambda: fake_anipy
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.pop(get_anipy_service, None)
