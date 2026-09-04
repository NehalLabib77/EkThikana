from __future__ import annotations

import logging
from functools import lru_cache
from typing import Any

from app.schemas import CommutePlaceInput, CommuteRoutesRequest
from app.services.commute import journey_service
from app.services.commute.fare_engine import FareEngine
from app.services.commute.fare_labels import clean_option
from app.services.commute.graph_builder import load_coordinates, load_mapped_places
from app.services.commute.routing import Coordinate, MapRoutingProvider, get_routing_provider
from app.database.repositories.postgres_repository import CommutePostgresRepository

logger = logging.getLogger("gochano.commute")


class CommuteService:
    """Application service for the PostgreSQL-backed CommuteBD endpoints."""

    def __init__(
        self,
        repo: CommutePostgresRepository | None = None,
        routing_provider: MapRoutingProvider | None = None,
    ) -> None:
        self.repo = repo or CommutePostgresRepository()
        self.routing = routing_provider or get_routing_provider()
        self.fare_engine = FareEngine(repo=self.repo)

    def data_status(self) -> dict[str, Any]:
        return self.repo.data_status()

    def search_places(self, query: str, limit: int = 15) -> dict[str, Any]:
        return {
            "source": "postgres",
            "query": query,
            "results": self.repo.search_places(query, limit=limit),
        }

    def mapped_places(
        self,
        *,
        limit: int = 500,
        north: float | None = None,
        south: float | None = None,
        east: float | None = None,
        west: float | None = None,
    ) -> dict[str, Any]:
        """Places that can be shown as pins on a map.

        Served from the derived coordinate asset rather than the database:
        every place row ships with `geocode_status: pending`, so the database
        knows no coordinates at all and a map built from it would be empty.

        A bounding box keeps the payload proportional to what the student is
        actually looking at. `available` is false when the asset is missing,
        so the app can say the map has no data instead of showing a blank
        map and implying there is nothing there.
        """
        places = load_mapped_places()

        if None not in (north, south, east, west):
            places = tuple(
                place
                for place in places
                if south <= float(place["lat"]) <= north
                and west <= float(place["lon"]) <= east
            )

        capped = places[: max(1, min(limit, 2000))]
        return {
            "available": bool(load_mapped_places()),
            "source": "derived from the CommuteBD OpenStreetMap master",
            "count": len(capped),
            "totalWithCoordinates": len(load_mapped_places()),
            "truncated": len(capped) < len(places),
            "places": list(capped),
        }

    def nearby_stops(self, lat: float, lon: float, radius_m: int = 1500) -> dict[str, Any]:
        return {
            "source": "postgres",
            "center": {"lat": lat, "lon": lon},
            "radiusM": radius_m,
            "results": self.repo.nearby_stops(lat, lon, radius_m),
        }

    #: Geocoded coordinates keyed by the name that was looked up. Process-wide
    #: on purpose: a place's coordinates do not change between requests, and
    #: the public geocoder's rate limit is the binding constraint here.
    _geocode_cache: dict[str, tuple[float, float] | None] = {}

    async def _geocode_once(self, name: str) -> tuple[float, float] | None:
        """Geocode a place name at most once per process.

        Returns None when the provider cannot answer -- including when it
        rate-limits us. A failed lookup for one endpoint must not take down
        the whole route request; the caller reports which place could not be
        located, which is far more useful than a provider status code.

        A negative result is cached too. Re-asking a rate-limited provider for
        a name it has already refused is how a single failure turns into a
        sustained one.
        """
        key = name.strip().lower()
        if key in self._geocode_cache:
            return self._geocode_cache[key]

        try:
            external = await self.routing.search(name, limit=1)
        except Exception as exc:
            logger.warning("Geocoding failed for %r: %s", name, exc)
            self._geocode_cache[key] = None
            return None

        result = (
            (float(external[0]["lat"]), float(external[0]["lon"])) if external else None
        )
        self._geocode_cache[key] = result
        return result

    async def _resolve_input(self, item: CommutePlaceInput) -> dict[str, Any]:
        place: dict[str, Any] | None = None
        if item.place_id:
            place = self.repo.get_place(item.place_id)
            logger.debug(
                "DB lookup place_id=%s → %s",
                item.place_id,
                "found" if place else "NOT FOUND",
            )
        elif item.name:
            results = self.repo.search_places(item.name, limit=5)
            if results:
                first = results[0]
                place = self.repo.get_place(str(first["placeId"]))
                logger.debug(
                    "Name search '%s' → place_id=%s → %s",
                    item.name,
                    first.get("placeId"),
                    "found" if place else "NOT FOUND",
                )

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

        # Every place row in the shipped dataset is marked
        # `geocode_status: pending`, so *nothing* has coordinates in the
        # database. Sending each one to the public Nominatim endpoint meant a
        # geocode on every single route request, and Nominatim rate-limits at
        # roughly one call a second -- which is why planning a trip returned
        # "Geocoding provider error (429)".
        #
        # `place_coordinates.csv` already holds coordinates derived from the
        # OSM master for 154 of those places. Reading them here removes the
        # network call entirely for anything the derivation covered.
        if (lat is None or lon is None) and place_id:
            derived = load_coordinates().get(str(place_id))
            if derived:
                lat, lon = derived
                logger.debug("CSV fallback place_id=%s → (%s, %s)", place_id, lat, lon)
            else:
                logger.debug("CSV fallback: place_id=%s NOT in place_coordinates.csv", place_id)

        # Only genuinely unknown places reach the geocoder now, and the
        # answers are cached so the same place is never looked up twice.
        if (lat is None or lon is None) and name:
            external = await self._geocode_once(name)
            if external:
                lat, lon = external
                logger.debug("Nominatim '%s' → (%s, %s)", name, lat, lon)
            else:
                logger.debug("Nominatim '%s' → no result", name)

        if lat is None or lon is None:
            label = name or place_id or "the selected place"
            logger.warning(
                "Could not resolve coordinates for '%s' (place_id=%s). "
                "DB=%s, CSV=%s, Nominatim=%s",
                label, place_id,
                "found" if place else "not found",
                "hit" if (place_id and load_coordinates().get(str(place_id))) else "miss",
                "checked",
            )
            raise ValueError(
                f"Could not find where {label} is on the map. "
                "Try a nearby landmark instead."
            )
        return {
            "placeId": place_id,
            "name": name or place_id or "Selected place",
            "lat": float(lat),
            "lon": float(lon),
            "source": "postgres" if place else "input/geocoder",
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
            # Internal source ids and the raw confidence word are pipeline
            # detail. `USER_PROVIDED_ASSUMPTION` was being printed on a fare
            # card, which tells a student nothing they can act on.
            results.append({**clean_option(option), "category": category})
        return results

    async def routes(self, body: CommuteRoutesRequest) -> dict[str, Any]:
        origin = await self._resolve_input(body.origin)
        destination = await self._resolve_input(body.destination)

        route = await self.routing.route(
            Coordinate(lat=origin["lat"], lon=origin["lon"]),
            Coordinate(lat=destination["lat"], lon=destination["lon"]),
        )

        # Use canonical human-readable names for FareEngine. The PostgreSQL
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

        # Multimodal journey planning over the transport graph. This is
        # additive: `recommendations` (per-mode fare options for the whole
        # trip) keeps its existing shape and meaning, and `journeys` adds the
        # complete origin-to-destination itineraries. A client that has not
        # been updated is unaffected.
        journeys: dict[str, Any] = {"available": False, "reason": "not_attempted",
                                    "journeys": []}
        try:
            journeys = journey_service.plan(
                self.repo,
                origin_name=str(origin["name"]),
                origin_lat=float(origin["lat"]),
                origin_lon=float(origin["lon"]),
                destination_name=str(destination["name"]),
                destination_lat=float(destination["lat"]),
                destination_lon=float(destination["lon"]),
            )
        except Exception:
            # A routing failure must not take down fare lookup, which is
            # useful on its own.
            logger.exception("Multimodal journey planning failed")
            journeys = {"available": False, "reason": "planner_error", "journeys": []}

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
            "journeyPlanning": {
                "available": journeys.get("available", False),
                "reason": journeys.get("reason"),
                "outsideCoverage": journeys.get("outsideCoverage"),
                "coverageRadiusKm": journeys.get("coverageRadiusKm"),
                "graph": journeys.get("graph"),
            },
            "journeys": journeys.get("journeys", []),
            "dataSource": "postgres",
            "disclaimer": (
                "Route time is a map estimate without fabricated live traffic. "
                "Each fare result preserves its official, crowdsourced, historical, or estimated source label."
            ),
        }


@lru_cache
def get_commute_service() -> CommuteService:
    return CommuteService()
