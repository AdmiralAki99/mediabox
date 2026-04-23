import httpx
from pydantic import BaseModel


class StreamResult(BaseModel):
    urls: list[str] = []
    subtitles: list[str] = []
    source_used: str = ""
    total_sources: int = 0
    referrer: str = ""


class StreamService:
    def __init__(self, http_client: httpx.AsyncClient) -> None:
        self._http = http_client
