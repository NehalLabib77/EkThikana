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


class GoogleRoutesProvider(MapRoutingProvider):
    """Google Maps Platform provider for routing and place search.

    Uses the Routes API (Compute Routes) for road routing and the Places API
    (New) for place autocomplete/search. Falls back to OSRM/Nominatim when
    Google is unavailable or unconfigured.
    """

    def __init__(self) -> None:
        settings = get_settings()
        self.api_key = settings.google_maps_server_api_key
        self._fallback = OsrmNominatimProvider()

    async def route(self, origin: Coordinate, destination: Coordinate) -> dict[str, Any]:
        if not self.api_key:
            return await self._fallback.route(origin, destination)

        url = "https://routes.googleapis.com/directions/v2:computeRoutes"
        body = {
            "origin": {
                "location": {
                    "latitude": origin.lat,
                    "longitude": origin.lon,
                }
            },
            "destination": {
                "location": {
                    "latitude": destination.lat,
                    "longitude": destination.lon,
                }
            },
            "travelMode": "DRIVE",
            "computeAlternativeRoutes": False,
            "routePreferences": "TRAFFIC_AWARE",
        }
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline",
        }
        try:
            async with httpx.AsyncClient(timeout=25) as client:
                response = await client.post(url, json=body, headers=headers)
            if response.status_code >= 400:
                raise RuntimeError(f"Google Routes API error ({response.status_code})")
            data = response.json()
            routes = data.get("routes") or []
            if not routes:
                raise RuntimeError("No route found")
            route = routes[0]
            distance_m = int(route.get("distanceMeters", 0))
            duration_sec = self._parse_duration(route.get("duration", "0s"))
            encoded = route.get("polyline", {}).get("encodedPolyline", "")
            coords = self._decode_polyline(encoded) if encoded else []
            return {
                "distanceKm": round(distance_m / 1000, 2),
                "durationMinutes": max(1, round(duration_sec / 60)),
                "polyline": coords,
                "provider": "Google Routes",
                "liveTraffic": False,
            }
        except Exception as exc:
            import logging
            logging.getLogger("gochano.commute.routing").warning(
                "Google Routes failed, falling back to OSRM: %s", exc
            )
            return await self._fallback.route(origin, destination)

    async def search(self, query: str, limit: int = 8) -> list[dict[str, Any]]:
        if not self.api_key:
            return await self._fallback.search(query, limit)

        url = "https://places.googleapis.com/v1/places:autocomplete"
        body = {
            "input": query,
            "locationBias": {
                "circle": {
                    "center": {"latitude": 23.8103, "longitude": 90.4125},
                    "radius": 50000.0,
                }
            },
            "languageCode": "en",
            "regionCode": "bd",
        }
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "suggestions.placePrediction.place,suggestions.placePrediction.placeId",
        }
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                response = await client.post(url, json=body, headers=headers)
            if response.status_code >= 400:
                raise RuntimeError(f"Google Places API error ({response.status_code})")
            data = response.json()
            suggestions = data.get("suggestions") or []
            results: list[dict[str, Any]] = []
            for item in suggestions[:limit]:
                pred = item.get("placePrediction", {})
                place = pred.get("place", {})
                fields = place.get("fields", {}) if isinstance(place, dict) else {}
                lat = fields.get("location", {}).get("latitude")
                lon = fields.get("location", {}).get("longitude")
                name = fields.get("displayName", {}).get("text", "")
                if lat is None or lon is None:
                    lat = None
                    lon = None
                results.append({
                    "displayName": name,
                    "lat": lat,
                    "lon": lon,
                    "type": fields.get("primaryType", "unknown"),
                    "provider": "Google Places",
                    "googlePlaceId": pred.get("placeId", ""),
                })
            return results
        except Exception as exc:
            import logging
            logging.getLogger("gochano.commute.routing").warning(
                "Google Places failed, falling back to Nominatim: %s", exc
            )
            return await self._fallback.search(query, limit)

    @staticmethod
    def _parse_duration(duration_str: str) -> float:
        """Parse Google's '123s' or '2m30s' duration format to seconds."""
        import re
        total = 0.0
        m = re.search(r"(\d+)m", duration_str)
        if m:
            total += int(m.group(1)) * 60
        m = re.search(r"(\d+)s", duration_str)
        if m:
            total += int(m.group(1))
        if total == 0:
            try:
                total = float(duration_str.replace("s", ""))
            except (ValueError, TypeError):
                total = 0.0
        return total

    @staticmethod
    def _decode_polyline(encoded: str) -> list[dict[str, float]]:
        """Decode Google encoded polyline to [{lat, lon}] list."""
        coords: list[dict[str, float]] = []
        index = 0
        lat = 0
        lon = 0
        while index < len(encoded):
            for value_var in ("lat", "lon"):
                shift = 0
                result = 0
                while True:
                    b = ord(encoded[index]) - 63
                    index += 1
                    result |= (b & 0x1F) << shift
                    shift += 5
                    if b < 0x20:
                        break
                dlat = ~(result >> 1) if result & 1 else result >> 1
                if value_var == "lat":
                    lat += dlat
                else:
                    lon += dlat
            coords.append({"lat": lat / 1e5, "lon": lon / 1e5})
        return coords


def get_routing_provider() -> MapRoutingProvider:
    provider = get_settings().routing_provider.lower()
    if provider == "google":
        return GoogleRoutesProvider()
    if provider == "osrm":
        return OsrmNominatimProvider()
    raise RuntimeError(f"Unsupported ROUTING_PROVIDER={provider}")
