from typing import Literal

from pydantic import BaseModel, Field


class GroupCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    description: str = Field(default="", max_length=240)


class GroupJoin(BaseModel):
    invite_code: str = Field(min_length=4, max_length=20)


class AiNoteRequest(BaseModel):
    action: Literal["cleanup", "summary", "explain", "key_topics"]
    text: str = Field(min_length=1, max_length=50000)


class PdfQuestionRequest(BaseModel):
    material_id: str
    question: str = Field(min_length=2, max_length=1000)
    page: int | None = Field(default=None, ge=1)


class StudyPlanRequest(BaseModel):
    max_items: int = Field(default=8, ge=1, le=20)


class ReportRequest(BaseModel):
    target_type: Literal["material", "note"]
    target_id: str = Field(min_length=1, max_length=200)
    reason: Literal["spam", "copyright", "inappropriate", "misleading", "other"]
    details: str = Field(default="", max_length=1000)


class CommuteRouteRequest(BaseModel):
    origin_name: str = Field(min_length=1, max_length=160)
    origin_lat: float = Field(ge=-90, le=90)
    origin_lon: float = Field(ge=-180, le=180)
    destination_name: str = Field(min_length=1, max_length=160)
    destination_lat: float = Field(ge=-90, le=90)
    destination_lon: float = Field(ge=-180, le=180)


class CommuteFareReportRequest(BaseModel):
    origin_place_id: str | None = Field(default=None, max_length=80)
    origin_text: str = Field(min_length=1, max_length=180)
    origin_lat: float | None = Field(default=None, ge=-90, le=90)
    origin_lon: float | None = Field(default=None, ge=-180, le=180)
    destination_place_id: str | None = Field(default=None, max_length=80)
    destination_text: str = Field(min_length=1, max_length=180)
    destination_lat: float | None = Field(default=None, ge=-90, le=90)
    destination_lon: float | None = Field(default=None, ge=-180, le=180)
    transport_mode: Literal["bus", "metro", "cng", "rickshaw", "bike", "car", "other"]
    fare_paid_tk: float = Field(gt=0, le=10000)
    passenger_count: int = Field(default=1, ge=1, le=20)
    trip_minutes: int | None = Field(default=None, ge=1, le=720)
    route_distance_km: float | None = Field(default=None, gt=0, le=300)
    traffic_level: Literal["unknown", "light", "normal", "heavy"] = "unknown"
    payment_type: Literal["cash", "card", "mobile", "pass", "other"] = "cash"
    bus_service_id: str | None = Field(default=None, max_length=80)
    bus_name_user_entered: str | None = Field(default=None, max_length=120)
    route_id_if_known: str | None = Field(default=None, max_length=80)
    device_location_verified: bool = False


class CommutePlaceInput(BaseModel):
    place_id: str | None = Field(default=None, max_length=80)
    name: str | None = Field(default=None, max_length=180)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)


class CommuteRoutesRequest(BaseModel):
    origin: CommutePlaceInput
    destination: CommutePlaceInput
