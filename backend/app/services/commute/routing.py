from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

import httpx

from app.core.config import get_settings


@dataclass(frozen=True)
class Coordinate:
    lat: float
    lon: float


def haversine_km(a: Coordinate, b: Coordinate) -> float:
    radius = 6371.0088
    p1 = math.radians(a.lat)
    p2 = math.radians(b.lat)
    dlat = math.radians(b.lat - a.lat)
    dlon = math.radians(b.lon - a.lon)
    h = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))


class MapRoutingProvider:
    async def route(self, origin: Coordinate, destination: Coordinate) -> dict[str, Any]:
        raise NotImplementedError

    async def search(self, query: str, limit: int = 8) -> list[dict[str, Any]]:
        raise NotImplementedError


class OsrmNominatimProvider(MapRoutingProvider):
    """Real OSM-compatible routing/geocoding provider.

    The public endpoints are useful for development. Production deployments
    should set OSRM_BASE_URL/NOMINATIM_BASE_URL to a provider with an SLA or
    a self-hosted deployment.
    """

    def __init__(self) -> None:
        settings = get_settings()
        self.osrm = settings.osrm_base_url.rstrip("/")
        self.nominatim = settings.nominatim_base_url.rstrip("/")
        self.user_agent = settings.routing_user_agent

    async def route(self, origin: Coordinate, destination: Coordinate) -> dict[str, Any]:
        url = (
            f"{self.osrm}/route/v1/driving/"
            f"{origin.lon},{origin.lat};{destination.lon},{destination.lat}"
        )
        params = {
            "overview": "full",
            "geometries": "geojson",
            "steps": "false",
            "alternatives": "false",
        }
        async with httpx.AsyncClient(timeout=25) as client:
            response = await client.get(url, params=params, headers={"User-Agent": self.user_agent})
        if response.status_code >= 400:
            raise RuntimeError(f"Routing provider error ({response.status_code})")
        data = response.json()
        routes = data.get("routes") or []
        if not routes:
            raise RuntimeError("No route found")
        route = routes[0]
        coords = route.get("geometry", {}).get("coordinates") or []
        return {
            "distanceKm": round(float(route.get("distance", 0)) / 1000, 2),
            "durationMinutes": max(1, round(float(route.get("duration", 0)) / 60)),
            "polyline": [
                {"lat": float(pair[1]), "lon": float(pair[0])}
                for pair in coords
                if isinstance(pair, list) and len(pair) >= 2
            ],
            "provider": "OSRM",
            "liveTraffic": False,
        }

    async def search(self, query: str, limit: int = 8) -> list[dict[str, Any]]:
        params = {
            "q": query,
            "format": "jsonv2",
            "limit": str(max(1, min(limit, 10))),
            "countrycodes": "bd",
            "addressdetails": "1",
        }
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.get(
                f"{self.nominatim}/search",
                params=params,
                headers={
                    "User-Agent": self.user_agent,
                    "Accept-Language": "en,bn;q=0.8",
                },
            )
        if response.status_code == 429:
            # Public Nominatim allows roughly one call a second. A raw status
            # code told the student nothing they could act on.
            raise RuntimeError(
                "The map lookup service is busy right now. Wait a few seconds "
                "and try again."
            )
        if response.status_code >= 400:
            raise RuntimeError(f"Map lookup failed ({response.status_code})")
        items = response.json()
        return [
            {
                "displayName": item.get("display_name", ""),
                "lat": float(item["lat"]),
                "lon": float(item["lon"]),
                "type": item.get("type"),
                "provider": "OpenStreetMap/Nominatim",
            }
            for item in items
            if item.get("lat") and item.get("lon")
        ]


def get_routing_provider() -> MapRoutingProvider:
    provider = get_settings().routing_provider.lower()
    if provider == "osrm":
        return OsrmNominatimProvider()
    raise RuntimeError(f"Unsupported ROUTING_PROVIDER={provider}")
