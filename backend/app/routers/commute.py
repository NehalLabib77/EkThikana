from __future__ import annotations

import hashlib
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError

from app.core.auth import CurrentUser, get_current_user
from app.database.repositories.fare_report_repository import insert_fare_report
from app.database.repositories.postgres_repository import CommutePostgresRepository
from app.schemas import CommuteFareReportRequest, CommuteRouteRequest, CommuteRoutesRequest, CommuteSingleFareRequest
from app.services.commute.data_repository import get_commute_repository
from app.services.commute.fare_engine import FareEngine, MODE_ELIGIBILITY, SUPPORTED_MODES
from app.services.commute.fare_quality import duplicate_key, validate_report
from app.services.commute.ml_status import readiness as ml_readiness
from app.services.commute.routing import Coordinate, get_routing_provider
from app.services.commute.service import get_commute_service

logger = logging.getLogger("gochano.commute")

router = APIRouter()


@router.get("/search")
async def search_places(
    q: str = Query(min_length=2, max_length=120),
    user: CurrentUser = Depends(get_current_user),
):
    repo = get_commute_repository()
    local = repo.search_local_places(q, limit=8)
    external: list[dict[str, Any]] = []
    try:
        provider = get_routing_provider()
        external = await provider.search(q, limit=8)
        for item in external:
            if item.get("googlePlaceId") and item.get("lat") and item.get("lon"):
                service = get_commute_service()
                canonical = await service.resolve_canonical_place(
                    name=item.get("displayName"),
                    lat=float(item["lat"]),
                    lon=float(item["lon"]),
                )
                if canonical:
                    item["canonicalPlaceId"] = canonical["placeId"]
                    item["canonicalName"] = canonical["name"]
    except Exception:
        pass
    return {"local": local, "geocoded": external}


@router.post("/route")
async def route_trip(
    body: CommuteRouteRequest,
    user: CurrentUser = Depends(get_current_user),
):
    origin = Coordinate(lat=body.origin_lat, lon=body.origin_lon)
    destination = Coordinate(lat=body.destination_lat, lon=body.destination_lon)

    try:
        route = await get_routing_provider().route(origin, destination)
    except RuntimeError as exc:
        message = str(exc)
        if "No route" in message:
            raise HTTPException(status_code=404, detail=message)
        raise HTTPException(status_code=503, detail=message)

    engine = FareEngine()
    options = engine.options(
        origin_name=body.origin_name,
        destination_name=body.destination_name,
        distance_km=float(route["distanceKm"]),
        driving_minutes=int(route["durationMinutes"]),
    )

    return {
        "origin": {
            "name": body.origin_name,
            "lat": body.origin_lat,
            "lon": body.origin_lon,
        },
        "destination": {
            "name": body.destination_name,
            "lat": body.destination_lat,
            "lon": body.destination_lon,
        },
        "distanceKm": route["distanceKm"],
        "durationMinutes": route["durationMinutes"],
        "polyline": route["polyline"],
        "routingProvider": route["provider"],
        "liveTraffic": False,
        "transportOptions": options,
        "disclaimer": (
            "Times are route estimates without fabricated live traffic. "
            "Fare cards disclose whether data is official, crowdsourced, historical, or unverified."
        ),
    }




@router.post("/fare-report")
def report_fare(
    body: CommuteFareReportRequest,
    user: CurrentUser = Depends(get_current_user),
):
    if body.fare_paid_tk <= 0 or body.fare_paid_tk > 10000:
        raise HTTPException(status_code=400, detail="Fare is outside the accepted range")
    if body.trip_minutes is not None and not (1 <= body.trip_minutes <= 720):
        raise HTTPException(status_code=400, detail="Trip duration is invalid")

    # Physics and the shipped fare rules, checked before the report can ever
    # count as evidence. A rejected report is refused with the actual reason
    # rather than a generic "invalid", so the student can fix a typo.
    verdict = validate_report(
        mode=body.transport_mode,
        fare_tk=float(body.fare_paid_tk),
        distance_km=body.route_distance_km,
        trip_minutes=body.trip_minutes,
        passenger_count=body.passenger_count,
    )
    if verdict.rejected:
        raise HTTPException(
            status_code=400,
            detail=verdict.reasons[0] if verdict.reasons else "Fare report is not plausible",
        )

    rounded_origin = (
        f"{body.origin_lat:.4f},{body.origin_lon:.4f}"
        if body.origin_lat is not None and body.origin_lon is not None
        else body.origin_text.strip().lower()
    )
    rounded_destination = (
        f"{body.destination_lat:.4f},{body.destination_lon:.4f}"
        if body.destination_lat is not None and body.destination_lon is not None
        else body.destination_text.strip().lower()
    )
    # An hour-wide window, not a minute-wide one. The duplicates that
    # actually occur are double taps and retries after a timeout, and a
    # minute bucket lets a retry at 12:00:59 land in a different bucket from
    # the original at 12:00:58 -- the exact case this key exists to stop.
    dedupe = duplicate_key(
        user_id_hash=user.uid,
        mode=body.transport_mode,
        origin=rounded_origin,
        destination=rounded_destination,
        fare_tk=float(body.fare_paid_tk),
        when=datetime.now(timezone.utc),
    )

    # Bus identity validation
    bus_service_id: str | None = (
        body.bus_service_id.strip() if body.bus_service_id and body.bus_service_id.strip() else None
    )
    bus_name_user_entered: str | None = (
        body.bus_name_user_entered.strip()
        if body.bus_name_user_entered and body.bus_name_user_entered.strip()
        else None
    )

    if body.transport_mode == "bus":
        # Reject ambiguous invalid payloads: neither supplied or both supplied
        if not bus_service_id and not bus_name_user_entered:
            raise HTTPException(
                status_code=400,
                detail="Bus fare report requires either a known bus_service_id or bus_name_user_entered for unlisted buses.",
            )
        if bus_service_id and bus_name_user_entered:
            raise HTTPException(
                status_code=400,
                detail="Ambiguous bus identity: cannot supply both bus_service_id and bus_name_user_entered.",
            )

        if bus_service_id:
            # Known bus submission: verify it exists in bus_services
            repo = CommutePostgresRepository()
            service = repo.get_bus_service(bus_service_id)
            if not service:
                raise HTTPException(
                    status_code=400,
                    detail=f"Unknown bus_service_id '{bus_service_id}' does not exist in bus_services.",
                )
            # bus_name_user_entered should be null/ignored
            bus_name_user_entered = None
        else:
            # Bus not listed: bus_service_id is null, bus_name_user_entered is non-empty
            bus_service_id = None
    else:
        # For non-bus modes: bus_service_id and bus_name_user_entered must not affect fare aggregation
        bus_service_id = None
        bus_name_user_entered = None

    row = {
        "user_id_hash": hashlib.sha256(user.uid.encode("utf-8")).hexdigest(),
        "origin_place_id": body.origin_place_id,
        "origin_text": body.origin_text.strip(),
        "origin_latitude": body.origin_lat,
        "origin_longitude": body.origin_lon,
        "destination_place_id": body.destination_place_id,
        "destination_text": body.destination_text.strip(),
        "destination_latitude": body.destination_lat,
        "destination_longitude": body.destination_lon,
        "transport_mode": body.transport_mode,
        "bus_service_id": body.bus_service_id,
        "bus_name_user_entered": body.bus_name_user_entered,
        "bus_service_id": bus_service_id,
        "bus_name_user_entered": bus_name_user_entered,
        "route_id_if_known": (body.route_id_if_known if body.route_id_if_known and " + " not in body.route_id_if_known else None),
        "fare_paid_tk": body.fare_paid_tk,
        "passenger_count": body.passenger_count,
        "payment_type": body.payment_type,
        "traffic_level": body.traffic_level,
        "trip_minutes": body.trip_minutes,
        "route_distance_km": body.route_distance_km,
        "device_location_verified": body.device_location_verified,
        "moderation_status": "pending",
        "dedupe_key": dedupe,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        inserted = insert_fare_report(row)
    except IntegrityError:
        raise HTTPException(status_code=409, detail="Duplicate fare report")
    except Exception:
        raise HTTPException(status_code=503, detail="Could not store fare report")

    return {
        "accepted": True,
        "reportId": inserted.get("reportId"),
        "moderationStatus": inserted.get("moderationStatus"),
        # A plausible-but-unusual fare is kept and flagged rather than
        # discarded: an unusually expensive route is exactly the thing a
        # student wants warning about later.
        "quality": verdict.to_dict(),
        "message": "Thank you. The report is pending moderation and is not published as truth yet.",
    }


@router.get("/ml-status")
def ml_status(user: CurrentUser = Depends(get_current_user)):
    """How far the fare model is from being trainable, with real counts."""
    return ml_readiness()


@router.get("/data-status")
def data_status():
    try:
        return get_commute_service().data_status()
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=503, detail="CommuteBD data source is unavailable")


@router.get("/places/search")
def search_places_supabase(
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=15, ge=1, le=20),
    user: CurrentUser = Depends(get_current_user),
):
    try:
        return get_commute_service().search_places(q, limit=limit)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=503, detail="CommuteBD place search is unavailable")


@router.get("/places/map")
def mapped_places(
    limit: int = Query(default=500, ge=1, le=2000),
    north: float | None = Query(default=None, ge=-90, le=90),
    south: float | None = Query(default=None, ge=-90, le=90),
    east: float | None = Query(default=None, ge=-180, le=180),
    west: float | None = Query(default=None, ge=-180, le=180),
    user: CurrentUser = Depends(get_current_user),
):
    """Places with known coordinates, for picking a trip straight off a map.

    Needs no database: the coordinates are derived from the OpenStreetMap
    master because the shipped place rows have none.
    """
    try:
        return get_commute_service().mapped_places(
            limit=limit, north=north, south=south, east=east, west=west
        )
    except Exception:
        raise HTTPException(
            status_code=503, detail="CommuteBD map places are unavailable"
        )


@router.get("/nearby-stops")
def nearby_stops(
    lat: float = Query(ge=-90, le=90),
    lng: float = Query(ge=-180, le=180),
    radius_m: int = Query(default=1500, ge=100, le=10000),
    user: CurrentUser = Depends(get_current_user),
):
    try:
        return get_commute_service().nearby_stops(lat, lng, radius_m)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=503, detail="CommuteBD nearby-stop lookup is unavailable")


@router.post("/routes")
async def routes_supabase(
    body: CommuteRoutesRequest,
    user: CurrentUser = Depends(get_current_user),
):
    # Log input coordinates for diagnostics (no secrets, no Firebase IDs).
    _o = body.origin
    _d = body.destination
    logger.info(
        "Route request: origin=(place_id=%s, name=%s, lat=%s, lon=%s) "
        "dest=(place_id=%s, name=%s, lat=%s, lon=%s)",
        _o.place_id, _o.name, _o.lat, _o.lon,
        _d.place_id, _d.name, _d.lat, _d.lon,
    )
    try:
        result = await get_commute_service().routes(body)
        logger.info(
            "Route OK: distance=%s km, duration=%s min, polyline_pts=%s",
            result.get("distanceKm"),
            result.get("estimatedDurationMin"),
            len(result.get("polyline") or []),
        )
        return result
    except ValueError as exc:
        # Coordinate resolution failed — give the user a specific message.
        logger.warning("Route resolution failed: %s", exc)
        raise HTTPException(status_code=422, detail=str(exc))
    except RuntimeError as exc:
        message = str(exc)
        logger.warning("Route runtime error: %s", message)
        if "No route" in message:
            raise HTTPException(status_code=404, detail=message)
        raise HTTPException(status_code=503, detail=message)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Route calculation failed unexpectedly")
        raise HTTPException(
            status_code=503,
            detail=(
                "Road route is temporarily unavailable. "
                "Please try a different origin or destination."
            ),
        )


@router.get("/bus-services/search")
def search_bus_services(
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=10, ge=1, le=30),
    user: CurrentUser = Depends(get_current_user),
):
    """Search bus services by operator name, service type, or stop name."""
    try:
        repo = get_commute_repository()
        repo = CommutePostgresRepository()
        return {
            "query": q,
            "results": repo.search_bus_services(q, limit=limit),
        }
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=503, detail="Bus service search is unavailable")


@router.get("/bus-services/{service_id}")
def get_bus_service(
    service_id: str,
    user: CurrentUser = Depends(get_current_user),
):
    """Get a single bus service by ID with its ordered stops."""
    try:
        repo = get_commute_repository()
        repo = CommutePostgresRepository()
        result = repo.get_bus_service(service_id)
        if not result:
            raise HTTPException(status_code=404, detail=f"Bus service '{service_id}' not found")
        return result
    except HTTPException:
        raise
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=503, detail="Bus service lookup is unavailable")


@router.get("/bus-services/direct-match")
async def direct_bus_match(
    origin_place_id: str = Query(min_length=1, max_length=80),
    destination_place_id: str = Query(min_length=1, max_length=80),
    limit: int = Query(default=6, ge=1, le=15),
    user: CurrentUser = Depends(get_current_user),
):
    """Find bus services that travel directly from origin to destination.

    A direct match means the bus service has stops at both places with
    the origin appearing before the destination in the stop sequence.

    Accepts either canonical CommuteBD place IDs (PLCxxxx) or free-text
    place names. Free-text names are resolved to canonical IDs before matching.
    """
    try:
        service = get_commute_service()
        repo = CommutePostgresRepository()

        origin_resolved = await service.resolve_canonical_place(
            place_id=origin_place_id if origin_place_id.startswith("PLC") else None,
            name=origin_place_id if not origin_place_id.startswith("PLC") else None,
        )
        dest_resolved = await service.resolve_canonical_place(
            place_id=destination_place_id if destination_place_id.startswith("PLC") else None,
            name=destination_place_id if not destination_place_id.startswith("PLC") else None,
        )

        origin_id = origin_resolved["placeId"] if origin_resolved else origin_place_id
        dest_id = dest_resolved["placeId"] if dest_resolved else destination_place_id

        return {
            "originPlaceId": origin_id,
            "destinationPlaceId": dest_id,
            "originResolved": origin_resolved is not None,
            "destinationResolved": dest_resolved is not None,
            "results": repo.direct_bus_match(
                origin_id, dest_id, limit=limit
            ),
        }
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=503, detail="Bus direct match is unavailable")


@router.post("/resolve-place")
async def resolve_place(
    body: CommuteRoutesRequest,
    user: CurrentUser = Depends(get_current_user),
):
    """Resolve user-selected place input to canonical CommuteBD place IDs.

    Accepts Google Places results, geocoded coordinates, or free-text names
    and maps them to the nearest canonical CommuteBD place ID.

    This is the bridge between external place providers and the internal
    bus matching system.
    """
    try:
        service = get_commute_service()
        origin = await service.resolve_canonical_place(
            place_id=body.origin.place_id,
            name=body.origin.name,
            lat=body.origin.lat,
            lon=body.origin.lon,
        )
        dest = await service.resolve_canonical_place(
            place_id=body.destination.place_id,
            name=body.destination.name,
            lat=body.destination.lat,
            lon=body.destination.lon,
        )
        return {
            "origin": origin,
            "destination": dest,
            "hasCanonicalPair": origin is not None and dest is not None,
        }
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Place resolution failed: {exc}")


@router.get("/bus-services/{service_id}")
def get_bus_service(
    service_id: str,
    user: CurrentUser = Depends(get_current_user),
):
    """Get a single bus service by ID with its ordered stops."""
    try:
        repo = CommutePostgresRepository()
        result = repo.get_bus_service(service_id)
        if not result:
            raise HTTPException(status_code=404, detail=f"Bus service '{service_id}' not found")
        return result
    except HTTPException:
        raise
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=503, detail="Bus service lookup is unavailable")


@router.post("/single-fare")
async def single_fare(
    body: CommuteSingleFareRequest,
    user: CurrentUser = Depends(get_current_user),
):
    """Return the fare for one user-selected transport mode.

    This endpoint does NOT recalculate the OSRM route.  The caller is
    expected to have already obtained distance and duration from
    ``POST /api/commute/routes`` and passes them here.  The endpoint
    uses origin/destination names and place IDs for dataset matching
    (bus segment lookup, metro station resolution) but does not call
    any routing service.

    Returns either a supported fare result or an unsupported response with
    a clear reason — never a fabricated zero fare.
    """
    mode = body.mode.strip().lower()
    if mode not in SUPPORTED_MODES:
        raise HTTPException(
            status_code=422,
            detail=f"Transport mode '{mode}' is not supported. "
            f"Supported modes: {', '.join(sorted(SUPPORTED_MODES))}",
        )

    distance_km = body.distance_km
    driving_minutes = body.driving_minutes

    # Extract origin/destination names for fare service lookups (bus segment
    # matching, metro station resolution, CNG/rickshaw crowd aggregation).
    # These are the human-readable names the caller already has from the
    # route result — no geocoding or routing is performed.
    origin_name = body.origin.name or ""
    destination_name = body.destination.name or ""

    # Check eligibility before calling the fare engine.
    eligibility = MODE_ELIGIBILITY.get(mode, {})
    max_km = eligibility.get("max_distance_km")
    if max_km is not None and distance_km > max_km:
        return {
            "supported": False,
            "mode": mode,
            "reason": (
                f"{mode.title()} fare estimation is not supported for "
                f"this distance ({distance_km:.1f} km). "
                f"{mode.title()} data in the CommuteBD dataset covers "
                f"trips up to {max_km:.0f} km."
            ),
            "distanceKm": distance_km,
            "eligibility": eligibility.get("description", ""),
        }

    engine = FareEngine()
    option = engine.single_option(
        mode=mode,
        origin_name=origin_name,
        destination_name=destination_name,
        distance_km=distance_km,
        driving_minutes=driving_minutes,
    )

    if option is None and mode == "bus" and body.bus_service_id:
        from app.services.commute.crowd import CrowdFareRepository
        crowd_repo = CrowdFareRepository()
        crowd_agg = crowd_repo.aggregate_for_bus_service(
            bus_service_id=body.bus_service_id,
            origin_place_id=body.origin.place_id,
            destination_place_id=body.destination.place_id,
            origin_text=origin_name,
            destination_text=destination_name,
        )
        if crowd_agg:
            option = {
                "low": crowd_agg["p25Fare"],
                "median": crowd_agg["medianFare"],
                "high": crowd_agg["p75Fare"],
                "fareType": "crowdsourced",
                "fareLabel": "Community estimate",
                "source": f"Community estimate ({crowd_agg['sampleCount']} reports)",
                "confidence": crowd_agg.get("confidence", "Medium"),
                "sampleCount": crowd_agg["sampleCount"],
                "busServiceId": body.bus_service_id,
            }

    if option is None:
        reason_parts = []
        if mode == "metro":
            reason_parts.append(
                "No supported metro station pair was found for this route. "
                "Metro fares are only available between operational MRT Line 6 "
                "stations."
            )
        elif mode == "bus":
            reason_parts.append(
                "No valid bus fare data was found for this route. "
                "Bus fares require matching BRTA fare segments."
            )
        else:
            reason_parts.append(
                f"No supported fare data was found for {mode.title()} on this route."
            )
        return {
            "supported": False,
            "mode": mode,
            "reason": " ".join(reason_parts),
            "distanceKm": distance_km,
            "eligibility": eligibility.get("description", ""),
        }

    from app.services.commute.fare_labels import clean_option
    cleaned = clean_option(option)
    return {
        "supported": True,
        "mode": mode,
        "fare": cleaned,
        "distanceKm": distance_km,
        "drivingMinutes": driving_minutes,
    }


