# Mediabox

A self-hosted media centre application built for the Raspberry Pi CM5. Streams movies, TV series, anime, manga, comics, ebooks, and academic papers — all from a single app with no subscription required.

---

## What it does

| Category | Source |
|----------|--------|
| Movies & TV | TMDB metadata + stream resolution via MoviesAPI |
| Anime | AllAnime GraphQL API (direct, no scraping library) |
| Manga | MangaDex REST API |
| Comics | ReadComicOnline + Comick |
| Ebooks | Z-Library + Project Gutenberg + NYT Bestsellers |
| Academic papers | arXiv (search, PDF proxy, HTML reader) |
| Sports | Live match listings and stream resolution |
| Weather | Open-Meteo (no API key needed) |

Everything runs locally on the device — no cloud, no tracking, no monthly fee.

---

## Architecture

```
┌─────────────────────────┐     HTTP      ┌──────────────────────────┐
│   Qt/QML frontend       │ ──────────── │   FastAPI backend         │
│   (PySide6)             │  localhost    │   (Python, uvicorn)       │
│                         │   :8000       │                           │
│  • QML UI               │              │  • REST API               │
│  • Python bridge layer  │              │  • SQLite (watch history) │
│  • WebEngineView player │              │  • In-memory TTL cache    │
│  • Virtual keyboard     │              │  • HLS proxy & rewriter   │
└─────────────────────────┘              └──────────────────────────┘
```

The Qt app and API server ship as a single double-click executable — the frontend launches the backend as a subprocess on startup and shuts it down on exit.

---

## Tech stack

**Backend**
- Python 3.11, FastAPI, uvicorn
- SQLAlchemy (async) + aiosqlite for watch history and bookmarks
- httpx for async HTTP, curl-cffi for Cloudflare-protected endpoints
- AES-128-CBC stream decryption (cryptography library) for MoviesAPI
- Custom HLS manifest rewriter and seek-trimmer (no ffmpeg needed for playback)

**Frontend**
- PySide6 / Qt Quick (QML) — runs natively on ARM64 Linux and Windows x64
- QtWebEngine for video playback (HLS via the proxy layer)
- epub.js embedded reader for ebooks, served over a local token endpoint
- Qt Virtual Keyboard with a custom theme for touchscreen use on the Pi

**Build & release**
- PyInstaller bundles both the API server and Qt app into a self-contained binary
- Inno Setup produces a one-click Windows installer
- GitHub Actions builds and publishes releases automatically on every version tag

---

## Getting started

### Prerequisites

- Python 3.11+
- API keys (free tiers are fine):
  - [TMDB](https://www.themoviedb.org/settings/api) — movies and TV metadata
  - [NYT Books](https://developer.nytimes.com/) — bestseller lists (optional)
  - Z-Library account — ebook search (optional)

### Run in development

```bash
# Clone
git clone https://github.com/your-username/mediabox.git
cd mediabox

# Backend
cd api
python3 -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env   # fill in your API keys
uvicorn main:app --reload --port 8000

# Frontend (separate terminal)
cd app-qt
python3 -m venv venv && source venv/bin/activate
pip install PySide6 httpx
python main.py
```

### Build a release (Windows)

```powershell
# One-time: create build venvs
cd api && python -m venv venv_build
venv_build\Scripts\pip install -r requirements.txt pyinstaller pyinstaller-hooks-contrib

cd ..\app-qt && python -m venv venv
venv\Scripts\pip install PySide6 httpx pyinstaller pyinstaller-hooks-contrib

# Build installer
cd ..
.\build-win.ps1 -MakeInstaller
# → installer\Output\Mediabox-Setup-1.0.0.exe
```

Or push a tag and let CI handle it:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

GitHub Actions builds Windows + Linux ARM64 binaries and publishes them to the releases page automatically.

---

## Project structure

```
mediabox/
├── api/                  # FastAPI backend
│   ├── routers/          # One file per content type (movies, anime, manga, …)
│   ├── services/         # API clients and scraping logic
│   ├── models/           # Pydantic schemas and SQLAlchemy models
│   ├── cache.py          # In-memory TTL cache
│   └── config.py         # Settings loaded from .env
├── app-qt/               # PySide6 frontend
│   ├── qml/              # All UI (pages, components)
│   ├── bridge.py         # Python ↔ QML bridge (exposed as `api` object in QML)
│   └── main.py           # App entry point
├── installer/            # Inno Setup config for Windows installer
├── .github/workflows/    # CI/CD — automated release builds
└── build-win.ps1         # Local Windows build script
```

---

## Environment variables

| Variable | Description |
|----------|-------------|
| `TMDB_BEARER_TOKEN` | TMDB API v4 bearer token |
| `NYT_BOOKS_API_KEY` | NYT Books API key (optional) |
| `ZLIB_EMAIL` | Z-Library account email (optional) |
| `ZLIB_PASSWORD` | Z-Library account password (optional) |
| `ZLIB_DOMAIN` | Personal Z-Library domain (auto-discovered on login) |
| `DEBUG` | Set to `true` for verbose logging |

---

## License

Apache-2.0
