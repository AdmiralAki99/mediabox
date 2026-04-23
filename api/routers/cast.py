import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

logger = logging.getLogger("mediabox.cast")
router = APIRouter(prefix="/cast", tags=["Cast"])


class CastDevice(BaseModel):
    name: str
    host: str
    port: int
    type: str  # "chromecast" | "dlna"


class CastRequest(BaseModel):
    device_name: str
    device_host: str
    device_port: int
    device_type: str
    stream_url: str
    title: str
    referrer: Optional[str] = None


def _discover_chromecasts() -> list[dict]:
    try:
        import pychromecast
        chromecasts, browser = pychromecast.get_chromecasts(timeout=5)
        pychromecast.discovery.stop_discovery(browser)
        return [
            {"name": cc.name, "host": cc.host, "port": cc.port, "type": "chromecast"}
            for cc in chromecasts
        ]
    except ImportError:
        logger.warning("pychromecast not installed — Chromecast discovery unavailable")
        return []
    except Exception as e:
        logger.warning("Chromecast discovery failed: %s", e)
        return []


def _discover_dlna() -> list[dict]:
    try:
        import upnpclient
        devices = upnpclient.discover(timeout=3)
        result = []
        for d in devices:
            if "MediaRenderer" in (d.device_type or ""):
                host = d.location.split("//")[-1].split(":")[0] if d.location else "unknown"
                result.append({"name": d.friendly_name, "host": host, "port": 0, "type": "dlna"})
        return result
    except ImportError:
        logger.warning("upnpclient not installed — DLNA discovery unavailable")
        return []
    except Exception as e:
        logger.warning("DLNA discovery failed: %s", e)
        return []


def _cast_chromecast(host: str, port: int, url: str, title: str) -> None:
    import pychromecast
    cast = pychromecast.Chromecast(host=host, port=port)
    cast.wait(timeout=10)
    mc = cast.media_controller
    mc.play_media(url, "video/mp4", title=title)
    mc.block_until_active(timeout=10)


def _cast_dlna(host: str, url: str, title: str) -> None:
    import upnpclient
    devices = upnpclient.discover(timeout=3)
    device = next((d for d in devices if "MediaRenderer" in (d.device_type or "")), None)
    if not device:
        raise RuntimeError("DLNA device not found")
    avt = device["AVTransport"]
    avt.SetAVTransportURI(
        InstanceID=0,
        CurrentURI=url,
        CurrentURIMetaData=f'<DIDL-Lite><item><title>{title}</title></item></DIDL-Lite>',
    )
    avt.Play(InstanceID=0, Speed="1")


@router.get("/devices", response_model=list[CastDevice])
async def discover_devices() -> list[CastDevice]:
    loop = asyncio.get_event_loop()
    cc_task = loop.run_in_executor(None, _discover_chromecasts)
    dlna_task = loop.run_in_executor(None, _discover_dlna)
    cc_devices, dlna_devices = await asyncio.gather(cc_task, dlna_task)
    all_devices = cc_devices + dlna_devices
    return [CastDevice(**d) for d in all_devices]


@router.post("/play", status_code=204)
async def cast_play(req: CastRequest) -> None:
    loop = asyncio.get_event_loop()
    try:
        if req.device_type == "chromecast":
            await loop.run_in_executor(None, _cast_chromecast, req.device_host, req.device_port, req.stream_url, req.title)
        elif req.device_type == "dlna":
            await loop.run_in_executor(None, _cast_dlna, req.device_host, req.stream_url, req.title)
        else:
            raise HTTPException(status_code=400, detail=f"Unknown device type: {req.device_type}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
