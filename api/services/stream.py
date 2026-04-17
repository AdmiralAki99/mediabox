"""
StreamService — placeholder stub.

Resolution logic removed. Only the StreamResult model and the httpx client
holder remain so main.py and the proxy endpoint keep working.
Resolution endpoints will be re-added incrementally.
"""

import httpx
from pydantic import BaseModel


class StreamResult(BaseModel):
    urls: list[str] = []
    subtitles: list[str] = []
    source_used: str = ""
    total_sources: int = 0
    referrer: str = ""


class StreamService:
    """Holds the shared httpx client used by the proxy endpoint."""

    def __init__(self, http_client: httpx.AsyncClient) -> None:
        self._http = http_client
