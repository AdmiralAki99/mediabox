import time
from typing import Any

import httpx
from fastapi import APIRouter

router = APIRouter(prefix="/weather", tags=["weather"])

_cache: dict[str, Any] = {}
_cache_ts: float = 0.0
_CACHE_TTL = 1800  # seconds

def _wmo_condition(code: int) -> str:
    if code == 0:               return "CLEAR SKY"
    if code in (1,):            return "MAINLY CLEAR"
    if code == 2:               return "PARTLY CLOUDY"
    if code == 3:               return "OVERCAST"
    if code in (45, 48):        return "FOGGY"
    if code in (51, 53, 55):    return "DRIZZLE"
    if code in (56, 57):        return "FREEZING DRIZZLE"
    if code in (61, 63, 65):    return "RAIN"
    if code in (66, 67):        return "FREEZING RAIN"
    if code in (71, 73, 75):    return "SNOW"
    if code == 77:              return "SNOW GRAINS"
    if code in (80, 81, 82):    return "RAIN SHOWERS"
    if code in (85, 86):        return "SNOW SHOWERS"
    if code == 95:              return "THUNDERSTORM"
    if code in (96, 99):        return "THUNDERSTORM + HAIL"
    return "UNKNOWN"


def _fmt_time(iso: str) -> str:
    """'2024-04-11T06:34' → '6:34A'"""
    try:
        t   = iso[11:16]          # "06:34"
        h, m = int(t[:2]), t[3:]
        ampm = "A" if h < 12 else "P"
        h12  = h % 12 or 12
        return f"{h12}:{m}{ampm}"
    except Exception:
        return ""


@router.get("")
async def get_weather():
    global _cache, _cache_ts

    now = time.monotonic()
    if _cache and (now - _cache_ts) < _CACHE_TTL:
        return _cache

    async with httpx.AsyncClient(timeout=8) as client:
        try:
            geo      = (await client.get("https://ipapi.co/json/")).json()
            lat      = geo["latitude"]
            lon      = geo["longitude"]
            city     = geo.get("city", "")
            timezone = geo.get("timezone", "auto")
        except Exception:
            lat, lon, city, timezone = 51.5074, -0.1278, "London", "Europe/London"

        params = {
            "latitude":         lat,
            "longitude":        lon,
            "timezone":         timezone,
            "temperature_unit": "fahrenheit",
            "wind_speed_unit":  "mph",
            "forecast_days":    1,
            "current": ",".join([
                "temperature_2m",
                "relative_humidity_2m",
                "apparent_temperature",
                "wind_speed_10m",
                "uv_index",
                "weather_code",
            ]),
            "hourly": "temperature_2m",
            "daily":  "sunrise,sunset",
        }
        meteo = (await client.get(
            "https://api.open-meteo.com/v1/forecast", params=params
        )).json()

    cur  = meteo["current"]
    hrly = meteo["hourly"]
    dly  = meteo.get("daily", {})

    cur_hour     = int(cur["time"][11:13])
    hourly_temps = [round(t) for t in hrly["temperature_2m"]]

    # Next notable change: first hour after current where temp differs by ≥2°F
    next_change_hour = next_change_temp = None
    for i in range(cur_hour + 1, 24):
        if abs(hourly_temps[i] - hourly_temps[cur_hour]) >= 2:
            next_change_hour = i
            next_change_temp = hourly_temps[i]
            break

    sunrise_raw = (dly.get("sunrise") or [""])[0]
    sunset_raw  = (dly.get("sunset")  or [""])[0]

    _cache = {
        "city":              city,
        "temp":              round(cur["temperature_2m"]),
        "feels_like":        round(cur["apparent_temperature"]),
        "humidity":          round(cur["relative_humidity_2m"]),
        "wind_mph":          round(cur["wind_speed_10m"]),
        "uv_index":          round(cur.get("uv_index", 0)),
        "weather_code":      cur.get("weather_code", 0),
        "condition":         _wmo_condition(int(cur.get("weather_code", 0))),
        "sunrise":           _fmt_time(sunrise_raw),
        "sunset":            _fmt_time(sunset_raw),
        "hourly_temps":      hourly_temps,
        "current_hour":      cur_hour,
        "next_change_hour":  next_change_hour,
        "next_change_temp":  next_change_temp,
    }
    _cache_ts = now
    return _cache
