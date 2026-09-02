"""SQLAlchemy ORM models for the CommuteDB PostgreSQL dataset.

These models mirror ``backend/data/commutebd/core_dataset/supabase_schema.sql``
plus the ``supabase_schema_ml_extension.sql`` extensions. The column names keep
the snake_case from the SQL (matching what the existing
``CommuteSupabaseRepository`` already returns) so the migration does not need
to touch the data dictionary shapes consumed by routers.

Phase 2 deliberately omits models for Firestore-backed data (users, study,
medicines, materials metadata, …). That is a separate phase per the migration
brief.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Optional
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    PrimaryKeyConstraint,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import DOUBLE_PRECISION, UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.connection import Base


# ---------------------------------------------------------------------------
# SQLite-friendly BigInteger primary key. SQLite only auto-increments columns
# declared as INTEGER PRIMARY KEY (rowid alias), so we swap the BigInteger
# type to Integer on that dialect. PostgreSQL keeps BigInteger.
# ---------------------------------------------------------------------------
_BigIntPK = BigInteger().with_variant(Integer(), "sqlite")


# ---------------------------------------------------------------------------
# Places & aliases
# ---------------------------------------------------------------------------


class Place(Base):
    __tablename__ = "places"

    place_id: Mapped[str] = mapped_column(Text, primary_key=True)
    name_en: Mapped[str] = mapped_column(Text, nullable=False)
    name_bn: Mapped[Optional[str]] = mapped_column(Text)
    normalized_name: Mapped[Optional[str]] = mapped_column(Text)
    latitude: Mapped[Optional[float]] = mapped_column(Numeric(12, 8))
    longitude: Mapped[Optional[float]] = mapped_column(Numeric(12, 8))
    geocode_status: Mapped[Optional[str]] = mapped_column(Text, default="pending")
    source_id: Mapped[Optional[str]] = mapped_column(Text)

    route_stops: Mapped[list["BrtaRouteStop"]] = relationship(back_populates="place")
    service_stops: Mapped[list["BusServiceStop"]] = relationship(back_populates="place")
    origin_reports: Mapped[list["UserFareReport"]] = relationship(
        foreign_keys="UserFareReport.origin_place_id",
        back_populates="origin_place",
    )
    destination_reports: Mapped[list["UserFareReport"]] = relationship(
        foreign_keys="UserFareReport.destination_place_id",
        back_populates="destination_place",
    )

    __table_args__ = (Index("idx_places_name", "normalized_name"),)


# ---------------------------------------------------------------------------
# BRTA bus routes & stops
# ---------------------------------------------------------------------------


class BrtaRoute(Base):
    __tablename__ = "brta_routes"

    route_id: Mapped[str] = mapped_column(Text, primary_key=True)
    route_code_en: Mapped[Optional[str]] = mapped_column(Text)
    route_code_bn: Mapped[Optional[str]] = mapped_column(Text)
    route_name_en: Mapped[Optional[str]] = mapped_column(Text)
    route_name_bn: Mapped[Optional[str]] = mapped_column(Text)
    origin_name_en: Mapped[Optional[str]] = mapped_column(Text)
    destination_name_en: Mapped[Optional[str]] = mapped_column(Text)
    total_distance_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    stop_count: Mapped[Optional[int]] = mapped_column(Integer)
    fare_per_km_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    minimum_fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    live_use: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    source_id: Mapped[Optional[str]] = mapped_column(Text)

    stops: Mapped[list["BrtaRouteStop"]] = relationship(
        back_populates="route",
        cascade="all, delete-orphan",
        order_by="BrtaRouteStop.stop_sequence",
    )
    fare_segments: Mapped[list["BrtaFareSegment"]] = relationship(back_populates="route")


class BrtaRouteStop(Base):
    __tablename__ = "brta_route_stops"

    route_id: Mapped[str] = mapped_column(
        Text,
        ForeignKey("brta_routes.route_id", ondelete="CASCADE"),
        primary_key=True,
    )
    stop_sequence: Mapped[int] = mapped_column(Integer, primary_key=True)
    place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    stop_name_en: Mapped[Optional[str]] = mapped_column(Text)
    stop_name_bn: Mapped[Optional[str]] = mapped_column(Text)
    cumulative_distance_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    segment_distance_from_previous_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    source_id: Mapped[Optional[str]] = mapped_column(Text)

    route: Mapped[BrtaRoute] = relationship(back_populates="stops")
    place: Mapped[Optional[Place]] = relationship(back_populates="route_stops")

    __table_args__ = (Index("idx_brta_route_stops_place", "place_id"),)


class BrtaFareSegment(Base):
    __tablename__ = "brta_fare_segments"

    segment_id: Mapped[int] = mapped_column(_BigIntPK, primary_key=True, autoincrement=True)
    route_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("brta_routes.route_id"))
    from_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    from_name_en: Mapped[Optional[str]] = mapped_column(Text)
    to_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    to_name_en: Mapped[Optional[str]] = mapped_column(Text)
    distance_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    fare_per_km_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    minimum_fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    source_id: Mapped[Optional[str]] = mapped_column(Text)

    route: Mapped[Optional[BrtaRoute]] = relationship(back_populates="fare_segments")


class BrtaGraphEdge(Base):
    __tablename__ = "brta_graph_edges"

    edge_id: Mapped[int] = mapped_column(_BigIntPK, primary_key=True, autoincrement=True)
    from_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    to_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    route_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("brta_routes.route_id"))
    distance_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    source_id: Mapped[Optional[str]] = mapped_column(Text)


# ---------------------------------------------------------------------------
# Bus services (community / non-BRTA)
# ---------------------------------------------------------------------------


class BusService(Base):
    __tablename__ = "bus_services"

    service_id: Mapped[str] = mapped_column(Text, primary_key=True)
    operator_name_en: Mapped[Optional[str]] = mapped_column(Text)
    operator_name_bn: Mapped[Optional[str]] = mapped_column(Text)
    variant_no_for_operator: Mapped[Optional[int]] = mapped_column(Integer)
    start_stop_raw: Mapped[Optional[str]] = mapped_column(Text)
    end_stop_raw: Mapped[Optional[str]] = mapped_column(Text)
    stop_count: Mapped[Optional[int]] = mapped_column(Integer)
    service_type: Mapped[Optional[str]] = mapped_column(Text)
    time_text: Mapped[Optional[str]] = mapped_column(Text)
    image_url: Mapped[Optional[str]] = mapped_column(Text)
    current_status: Mapped[Optional[str]] = mapped_column(Text)
    source_id: Mapped[Optional[str]] = mapped_column(Text)

    stops: Mapped[list["BusServiceStop"]] = relationship(
        back_populates="service",
        cascade="all, delete-orphan",
        order_by="BusServiceStop.stop_sequence",
    )


class BusServiceStop(Base):
    __tablename__ = "bus_service_stops"

    service_id: Mapped[str] = mapped_column(
        Text,
        ForeignKey("bus_services.service_id", ondelete="CASCADE"),
        primary_key=True,
    )
    stop_sequence: Mapped[int] = mapped_column(Integer, primary_key=True)
    stop_name_raw: Mapped[Optional[str]] = mapped_column(Text)
    normalized_stop_name: Mapped[Optional[str]] = mapped_column(Text)
    canonical_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    canonical_name_en: Mapped[Optional[str]] = mapped_column(Text)
    source_id: Mapped[Optional[str]] = mapped_column(Text)

    service: Mapped[BusService] = relationship(back_populates="stops")
    place: Mapped[Optional[Place]] = relationship(back_populates="service_stops")

    __table_args__ = (Index("idx_bus_service_stops_place", "canonical_place_id"),)


class ServiceRouteMatch(Base):
    __tablename__ = "service_route_matches"

    match_id: Mapped[int] = mapped_column(_BigIntPK, primary_key=True, autoincrement=True)
    service_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("bus_services.service_id"))
    best_brta_route_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("brta_routes.route_id"))
    match_score: Mapped[Optional[float]] = mapped_column(Numeric(6, 3))
    match_quality: Mapped[Optional[str]] = mapped_column(Text)
    verified: Mapped[Optional[bool]] = mapped_column(Boolean)
    warning: Mapped[Optional[str]] = mapped_column(Text)
    source_id: Mapped[Optional[str]] = mapped_column(Text)


# ---------------------------------------------------------------------------
# Metro stations & fares
# ---------------------------------------------------------------------------


class MetroStation(Base):
    __tablename__ = "metro_stations"

    station_id: Mapped[str] = mapped_column(Text, primary_key=True)
    line_id: Mapped[str] = mapped_column(Text, nullable=False)
    station_order: Mapped[int] = mapped_column(Integer, nullable=False)
    name_en: Mapped[str] = mapped_column(Text, nullable=False)
    name_bn: Mapped[Optional[str]] = mapped_column(Text)
    operational_status: Mapped[Optional[str]] = mapped_column(Text)
    live_routing_enabled: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    latitude: Mapped[Optional[float]] = mapped_column(Numeric(12, 8))
    longitude: Mapped[Optional[float]] = mapped_column(Numeric(12, 8))
    geocode_status: Mapped[Optional[str]] = mapped_column(Text)
    source_id: Mapped[Optional[str]] = mapped_column(Text)


class MetroFare(Base):
    __tablename__ = "metro_fares"

    line_id: Mapped[str] = mapped_column(Text)
    from_station_id: Mapped[Optional[str]] = mapped_column(
        Text, ForeignKey("metro_stations.station_id")
    )
    to_station_id: Mapped[Optional[str]] = mapped_column(
        Text, ForeignKey("metro_stations.station_id")
    )
    single_journey_fare_tk: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    mrt_rapid_pass_fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    live_usable: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    source_id: Mapped[Optional[str]] = mapped_column(Text)

    __table_args__ = (
        PrimaryKeyConstraint("line_id", "from_station_id", "to_station_id", name="pk_metro_fares"),
    )


# ---------------------------------------------------------------------------
# Fare rules (mode-level minimums / per-km formulas)
# ---------------------------------------------------------------------------


class FareRule(Base):
    __tablename__ = "fare_rules"

    fare_rule_id: Mapped[str] = mapped_column(Text, primary_key=True)
    mode: Mapped[str] = mapped_column(Text, nullable=False)
    coverage: Mapped[Optional[str]] = mapped_column(Text)
    effective_from: Mapped[Optional[str]] = mapped_column(Text)
    base_or_minimum_fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    included_distance_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    per_km_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    waiting_rule: Mapped[Optional[str]] = mapped_column(Text)
    other_rule: Mapped[Optional[str]] = mapped_column(Text)
    production_status: Mapped[Optional[str]] = mapped_column(Text)
    source_id: Mapped[Optional[str]] = mapped_column(Text)


# ---------------------------------------------------------------------------
# Reference / lookup tables referenced by ``COMMUTE_TABLES``
# ---------------------------------------------------------------------------


class Source(Base):
    __tablename__ = "sources"

    source_id: Mapped[str] = mapped_column(Text, primary_key=True)
    source_name: Mapped[Optional[str]] = mapped_column(Text)
    source_kind: Mapped[Optional[str]] = mapped_column(Text)


class StopAlias(Base):
    __tablename__ = "stop_aliases"

    alias_id: Mapped[int] = mapped_column(_BigIntPK, primary_key=True, autoincrement=True)
    raw_stop_name: Mapped[Optional[str]] = mapped_column(Text)
    normalized_stop_name: Mapped[Optional[str]] = mapped_column(Text)
    canonical_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    canonical_name_en: Mapped[Optional[str]] = mapped_column(Text)
    match_score: Mapped[Optional[float]] = mapped_column(Numeric(6, 3))
    match_method: Mapped[Optional[str]] = mapped_column(Text)
    needs_manual_review: Mapped[Optional[bool]] = mapped_column(Boolean)
    source_id: Mapped[Optional[str]] = mapped_column(Text)


class GeocodingQueue(Base):
    __tablename__ = "geocoding_queue"

    queue_id: Mapped[int] = mapped_column(_BigIntPK, primary_key=True, autoincrement=True)
    raw_name: Mapped[Optional[str]] = mapped_column(Text)
    normalized_name: Mapped[Optional[str]] = mapped_column(Text)
    status: Mapped[Optional[str]] = mapped_column(Text, default="pending")
    last_error: Mapped[Optional[str]] = mapped_column(Text)


class TransitNetworkPlan(Base):
    __tablename__ = "transit_network_plan"

    plan_id: Mapped[int] = mapped_column(_BigIntPK, primary_key=True, autoincrement=True)
    name: Mapped[Optional[str]] = mapped_column(Text)
    payload: Mapped[Optional[str]] = mapped_column(Text)


# ---------------------------------------------------------------------------
# User-generated data: fare reports + ML/crowd aggregates
# ---------------------------------------------------------------------------


class UserFareReport(Base):
    __tablename__ = "user_fare_reports"

    report_id: Mapped[UUID] = mapped_column(
        PG_UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )
    user_id_hash: Mapped[Optional[str]] = mapped_column(Text)
    trip_started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    trip_ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    origin_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    origin_text: Mapped[Optional[str]] = mapped_column(Text)
    origin_latitude: Mapped[Optional[float]] = mapped_column(Numeric(9, 6))
    origin_longitude: Mapped[Optional[float]] = mapped_column(Numeric(9, 6))
    destination_place_id: Mapped[Optional[str]] = mapped_column(
        Text, ForeignKey("places.place_id")
    )
    destination_text: Mapped[Optional[str]] = mapped_column(Text)
    destination_latitude: Mapped[Optional[float]] = mapped_column(Numeric(9, 6))
    destination_longitude: Mapped[Optional[float]] = mapped_column(Numeric(9, 6))
    transport_mode: Mapped[str] = mapped_column(Text, nullable=False)
    bus_service_id: Mapped[Optional[str]] = mapped_column(
        Text, ForeignKey("bus_services.service_id")
    )
    bus_name_user_entered: Mapped[Optional[str]] = mapped_column(Text)
    route_id_if_known: Mapped[Optional[str]] = mapped_column(
        Text, ForeignKey("brta_routes.route_id")
    )
    fare_paid_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    passenger_count: Mapped[Optional[int]] = mapped_column(Integer, default=1)
    payment_type: Mapped[Optional[str]] = mapped_column(Text)
    traffic_level: Mapped[Optional[str]] = mapped_column(Text)
    user_confidence: Mapped[Optional[str]] = mapped_column(Text)
    receipt_or_photo_url: Mapped[Optional[str]] = mapped_column(Text)
    device_location_verified: Mapped[Optional[bool]] = mapped_column(Boolean, default=False)
    moderation_status: Mapped[Optional[str]] = mapped_column(Text, default="pending")
    dedupe_key: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    # Extension columns (supabase_schema_ml_extension.sql).
    route_distance_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    estimated_duration_min: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    actual_duration_min: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    trip_minutes: Mapped[Optional[int]] = mapped_column(Integer)
    source_type: Mapped[Optional[str]] = mapped_column(Text, default="user_report")

    origin_place: Mapped[Optional[Place]] = relationship(
        foreign_keys=[origin_place_id], back_populates="origin_reports"
    )
    destination_place: Mapped[Optional[Place]] = relationship(
        foreign_keys=[destination_place_id], back_populates="destination_reports"
    )

    __table_args__ = (
        CheckConstraint("fare_paid_tk >= 0", name="user_fare_reports_fare_paid_tk_check"),
        CheckConstraint(
            "passenger_count IS NULL OR passenger_count > 0",
            name="user_fare_reports_passenger_count_check",
        ),
        UniqueConstraint("dedupe_key", name="idx_user_fare_reports_dedupe"),
        Index(
            "idx_user_fare_origin_dest",
            "origin_place_id",
            "destination_place_id",
            "transport_mode",
        ),
        Index(
            "idx_user_fare_reports_approved_mode_created",
            "transport_mode",
            "created_at",
        ),
    )


class CrowdFareAggregate(Base):
    __tablename__ = "crowd_fare_aggregates"

    aggregate_id: Mapped[int] = mapped_column(
        _BigIntPK, primary_key=True, autoincrement=True
    )
    transport_mode: Mapped[str] = mapped_column(Text, nullable=False)
    origin_place_id: Mapped[Optional[str]] = mapped_column(Text, ForeignKey("places.place_id"))
    destination_place_id: Mapped[Optional[str]] = mapped_column(
        Text, ForeignKey("places.place_id")
    )
    distance_bucket_km: Mapped[Optional[float]] = mapped_column(Numeric(10, 3))
    sample_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    p25_fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    median_fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    p75_fare_tk: Mapped[Optional[float]] = mapped_column(Numeric(10, 2))
    confidence: Mapped[Optional[str]] = mapped_column(Text)
    window_start: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    window_end: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        Index(
            "idx_crowd_fare_lookup",
            "transport_mode",
            "origin_place_id",
            "destination_place_id",
        ),
    )


class FareModelRegistry(Base):
    __tablename__ = "fare_model_registry"

    model_id: Mapped[str] = mapped_column(Text, primary_key=True)
    transport_mode: Mapped[str] = mapped_column(Text, nullable=False)
    model_version: Mapped[str] = mapped_column(Text, nullable=False)
    artifact_path: Mapped[str] = mapped_column(Text, nullable=False)
    training_row_count: Mapped[Optional[int]] = mapped_column(Integer)
    train_window_start: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    train_window_end: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    mae: Mapped[Optional[float]] = mapped_column(Numeric(10, 4))
    rmse: Mapped[Optional[float]] = mapped_column(Numeric(10, 4))
    median_absolute_error: Mapped[Optional[float]] = mapped_column(Numeric(10, 4))
    r2: Mapped[Optional[float]] = mapped_column(Numeric(8, 5))
    status: Mapped[Optional[str]] = mapped_column(Text, default="candidate")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


# Re-export commonly used names so callers can ``from app.database.models import X``.
__all__ = [
    "Place",
    "BrtaRoute",
    "BrtaRouteStop",
    "BrtaFareSegment",
    "BrtaGraphEdge",
    "BusService",
    "BusServiceStop",
    "ServiceRouteMatch",
    "MetroStation",
    "MetroFare",
    "FareRule",
    "Source",
    "StopAlias",
    "GeocodingQueue",
    "TransitNetworkPlan",
    "UserFareReport",
    "CrowdFareAggregate",
    "FareModelRegistry",
]


# ``Numeric`` aliases are kept so type-checkers don't warn about the unused
# import; the symbols are referenced by the string-form relationships above.
_ = (Decimal, Optional, DOUBLE_PRECISION)
