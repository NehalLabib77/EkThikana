from __future__ import annotations

from functools import lru_cache
from typing import Any

from app.schemas import CommutePlaceInput, CommuteRoutesRequest
from app.services.commute.fare_engine import FareEngine
from app.services.commute.routing import Coordinate, MapRoutingProvider, get_routing_provider
from app.services.commute.supabase_repository import CommuteSupabaseRepository


class CommuteService:
    """Application service for Supabase-backed CommuteBD endpoints."""

    def __init__(
        self,
        repo: CommuteSupabaseRepository | None = None,
        routing_provider: MapRoutingProvider | None = None,
    ) -> None:
        self.repo = repo or CommuteSupabaseRepository()
        self.routing = routing_provider or get_routing_provider()
        self.fare_engine = FareEngine(repo=self.repo)

    def data_status(self) -> dict[str, Any]:
        return self.repo.data_status()

    def search_places(self, query: str, limit: int = 15) -> dict[str, Any]:
        return {
            "source": "supabase",
            "query": query,
            "results": self.repo.search_places(query, limit=limit),
        }

    def nearby_stops(self, lat: float, lon: float, radius_m: int = 1500) -> dict[str, Any]:
        return {
            "source": "supabase",
            "center": {"lat": lat, "lon": lon},
            "radiusM": radius_m,
            "results": self.repo.nearby_stops(lat, lon, radius_m),
        }

    async def _resolve_input(self, item: CommutePlaceInput) -> dict[str, Any]:
        place: dict[str, Any] | None = None
        if item.place_id:
            place = self.repo.get_place(item.place_id)
        elif item.name:
            results = self.repo.search_places(item.name, limit=5)
            if results:
                first = results[0]
                place = self.repo.get_place(str(first["placeId"]))

        name = item.name or (str(place.get("name_en")) if place else "")
        place_id = item.place_id or (str(place.get("place_id")) if place else None)
        lat = item.lat
        lon = item.lon
        if lat is None and place:
            try:
                lat = float(place["latitude"]) if place.get("latitude") is not None else None
            except Exception:
                lat = None
        if lon is None and place:
            try:
                lon = float(place["longitude"]) if place.get("longitude") is not None else None
            except Exception:
                lon = None

        # Many imported place rows are intentionally pending geocoding. If
        # coordinates are missing, resolve only the coordinates through the
        # configured real geocoder; retain the canonical dataset place id.
        if (lat is None or lon is None) and name:
            external = await self.routing.search(name, limit=1)
            if external:
                lat = float(external[0]["lat"])
                lon = float(external[0]["lon"])

        if lat is None or lon is None:
            raise ValueError(f"Coordinates are unavailable for {name or place_id or 'selected place'}")
        return {
            "placeId": place_id,
            "name": name or place_id or "Selected place",
            "lat": float(lat),
            "lon": float(lon),
            "source": "supabase" if place else "input/geocoder",
        }

    @staticmethod
    def _recommendations(options: list[dict[str, Any]]) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for option in options:
            badges = [str(v) for v in option.get("badges") or []]
            if "Recommended" in badges:
                category = "recommended"
            elif "Cheapest" in badges:
                category = "cheapest"
            elif "Fastest" in badges:
                category = "fastest"
            else:
                category = "alternative"
            results.append({**option, "category": category})
        return results

    async def routes(self, body: CommuteRoutesRequest) -> dict[str, Any]:
        origin = await self._resolve_input(body.origin)
        destination = await self._resolve_input(body.destination)

        route = await self.routing.route(
            Coordinate(lat=origin["lat"], lon=origin["lon"]),
            Coordinate(lat=destination["lat"], lon=destination["lon"]),
        )

        # Use canonical human-readable names for FareEngine. The Supabase
        # repository resolves those names back to place IDs for BRTA fare
        # lookup, while MetroFareService can match station names directly.
        options = self.fare_engine.options(
            origin_name=str(origin["name"]),
            destination_name=str(destination["name"]),
            distance_km=float(route["distanceKm"]),
            driving_minutes=int(route["durationMinutes"]),
        )

        transit_candidates: list[dict[str, Any]] = []
        if origin.get("placeId") and destination.get("placeId"):
            try:
                transit_candidates = self.repo.bus_route_via_services(
                    str(origin["placeId"]),
                    str(destination["placeId"]),
                    limit=6,
                )
            except Exception:
                transit_candidates = []

        return {
            "origin": origin,
            "destination": destination,
            "distanceKm": route["distanceKm"],
            "estimatedDurationMin": route["durationMinutes"],
            "polyline": route["polyline"],
            "routingProvider": route["provider"],
            "liveTraffic": False,
            "recommendations": self._recommendations(options),
            "transitCandidates": transit_candidates,
            "dataSource": "supabase",
            "disclaimer": (
                "Route time is a map estimate without fabricated live traffic. "
                "Each fare result preserves its official, crowdsourced, historical, or estimated source label."
            ),
        }


@lru_cache
def get_commute_service() -> CommuteService:
    return CommuteService()
