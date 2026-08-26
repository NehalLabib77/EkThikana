from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from supabase import create_client

from app.core.auth import CurrentUser, get_current_user
from app.core.config import get_settings
from app.schemas import CommuteFareReportRequest, CommuteRouteRequest
from app.services.commute.data_repository import get_commute_repository
from app.services.commute.fare_engine import FareEngine
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


@router.get("/places/search")
async def search_commute_places(
    q: str = Query(min_length=2, max_length=120),
    user: CurrentUser = Depends(get_current_user),
):
    """Supabase-backed place search used by the CommuteBD screen.

    Delegates to :class:`CommuteService` so the route stays aligned with the
    service's own dataset status checks. Auth is enforced via the standard
    dependency; unauthenticated requests receive 401.
    """
    return get_commute_service().search_places(q)


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


def _supabase():
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=503,
            detail="Fare reporting storage is not configured",
        )
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


@router.post("/fare-report")
def report_fare(
    body: CommuteFareReportRequest,
    user: CurrentUser = Depends(get_current_user),
):
    if body.fare_paid_tk <= 0 or body.fare_paid_tk > 10000:
        raise HTTPException(status_code=400, detail="Fare is outside the accepted range")
    if body.trip_minutes is not None and not (1 <= body.trip_minutes <= 720):
        raise HTTPException(status_code=400, detail="Trip duration is invalid")

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
    minute_bucket = datetime.now(timezone.utc).strftime("%Y%m%d%H%M")
    dedupe = hashlib.sha256(
        (
            f"{user.uid}|{body.transport_mode}|{rounded_origin}|"
            f"{rounded_destination}|{body.fare_paid_tk:.2f}|{minute_bucket}"
        ).encode("utf-8")
    ).hexdigest()

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
        response = _supabase().table("user_fare_reports").insert(row).execute()
        data = getattr(response, "data", None) or []
        report_id = data[0].get("id") if data else None
    except Exception as exc:
        text = str(exc).lower()
        if "duplicate" in text or "dedupe_key" in text or "unique" in text:
            raise HTTPException(status_code=409, detail="Duplicate fare report")
        raise HTTPException(status_code=503, detail="Could not store fare report")

    return {
        "accepted": True,
        "reportId": report_id,
        "moderationStatus": "pending",
        "message": "Thank you. The report is pending moderation and is not published as truth yet.",
    }
