from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError

from app.core.auth import CurrentUser, get_current_user
from app.database.repositories.fare_report_repository import insert_fare_report
from app.schemas import CommuteFareReportRequest, CommuteRouteRequest, CommuteRoutesRequest
from app.services.commute.data_repository import get_commute_repository
from app.services.commute.fare_engine import FareEngine
from app.services.commute.fare_quality import duplicate_key, validate_report
from app.services.commute.ml_status import readiness as ml_readiness
from app.services.commute.routing import Coordinate, get_routing_provider
from app.services.commute.service import get_commute_service

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
        external = await get_routing_provider().search(q, limit=8)
    except Exception:
        # Local dataset search remains useful during geocoder/network outage.
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
    try:
        return await get_commute_service().routes(body)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except RuntimeError as exc:
        message = str(exc)
        if "No route" in message:
            raise HTTPException(status_code=404, detail=message)
        raise HTTPException(status_code=503, detail=message)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=503, detail="CommuteBD route calculation is unavailable")


