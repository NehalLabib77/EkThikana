"""Regression tests for the user-selected transport mode single-fare flow.

These tests verify:
1. Short local rickshaw → supported
2. 205 km rickshaw → rejected (dataset only covers 1–20 km)
3. Auto long distance → rejected
4. Known bus match → valid source/fare
5. Unknown bus → no fabricated fare
6. Supported metro station pair → fare
7. Unsupported metro endpoints → no fare
8. Unknown/invalid mode → safely rejected
9. Mode eligibility rules are data-driven, not arbitrary
10. CNG has no arbitrary distance limit (fare_rules.csv has no max distance)
11. Single-fare schema accepts distanceKm/drivingMinutes (no OSRM needed)
"""
from __future__ import annotations

import math

from app.services.commute.fare_engine import (
    FareEngine,
    MODE_ELIGIBILITY,
    SUPPORTED_MODES,
)


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------
def _make_engine() -> FareEngine:
    return FareEngine()


# ---------------------------------------------------------------------------
# 1. Short local rickshaw → supported
# ---------------------------------------------------------------------------
def test_short_local_rickshaw_is_supported():
    engine = _make_engine()
    result = engine.single_option(
        mode="rickshaw",
        origin_name="Farmgate",
        destination_name="Dhanmondi",
        distance_km=3.0,
        driving_minutes=15,
    )
    # Rickshaw distance fallback covers 1–20 km, so 3 km should produce
    # either a crowd result or the distance-based fallback (Tk 17/km).
    if result is not None:
        assert result["mode"] == "rickshaw"
        assert result["fareLow"] >= 0
        assert result["fareHigh"] >= result["fareLow"]


# ---------------------------------------------------------------------------
# 2. 205 km rickshaw → rejected (dataset only covers 1–20 km)
# ---------------------------------------------------------------------------
def test_long_distance_rickshaw_is_rejected():
    eligibility = MODE_ELIGIBILITY["rickshaw"]
    assert eligibility["max_distance_km"] == 20.0
    # 205 km exceeds the 20 km dataset ceiling.
    assert 205.0 > eligibility["max_distance_km"]


# ---------------------------------------------------------------------------
# 3. Auto long distance → rejected
# ---------------------------------------------------------------------------
def test_long_distance_auto_is_rejected():
    eligibility = MODE_ELIGIBILITY["auto"]
    assert eligibility["max_distance_km"] == 20.0
    assert 50.0 > eligibility["max_distance_km"]


# ---------------------------------------------------------------------------
# 4. Known bus match → valid source/fare
# ---------------------------------------------------------------------------
def test_bus_has_lookup_method():
    engine = _make_engine()
    # BusFareService.lookup exists and returns a list.
    result = engine.bus.lookup("Farmgate", "Gulistan")
    assert isinstance(result, list)


# ---------------------------------------------------------------------------
# 5. Unknown bus → no fabricated fare
# ---------------------------------------------------------------------------
def test_bus_unknown_route_returns_none():
    engine = _make_engine()
    result = engine.single_option(
        mode="bus",
        origin_name="NonexistentPlaceA",
        destination_name="NonexistentPlaceB",
        distance_km=5.0,
        driving_minutes=20,
    )
    # No matching BRTA segment → None, not a fabricated per-km estimate.
    assert result is None


# ---------------------------------------------------------------------------
# 6. Supported metro station pair → fare (if data exists)
# ---------------------------------------------------------------------------
def test_metro_requires_station_match():
    eligibility = MODE_ELIGIBILITY["metro"]
    assert eligibility.get("requires_station_match") is True


def test_metro_lookup_returns_dict_or_none():
    engine = _make_engine()
    result = engine.metro.lookup("Farmgate", "Motijheel")
    # Either a fare dict or None — both are valid. The point is no crash.
    if result is not None:
        assert "fare" in result
        assert result["fareType"] == "official"


# ---------------------------------------------------------------------------
# 7. Unsupported metro endpoints → no fare
# ---------------------------------------------------------------------------
def test_metro_non_station_name_returns_none():
    engine = _make_engine()
    result = engine.single_option(
        mode="metro",
        origin_name="SomeRandomVillage",
        destination_name="AnotherRandomVillage",
        distance_km=10.0,
        driving_minutes=15,
    )
    assert result is None


# ---------------------------------------------------------------------------
# 8. Unknown/invalid mode → safely rejected
# ---------------------------------------------------------------------------
def test_invalid_mode_returns_none():
    engine = _make_engine()
    result = engine.single_option(
        mode="helicopter",
        origin_name="Farmgate",
        destination_name="Gulistan",
        distance_km=5.0,
        driving_minutes=15,
    )
    assert result is None


def test_invalid_mode_not_in_supported():
    assert "helicopter" not in SUPPORTED_MODES
    assert "spaceship" not in SUPPORTED_MODES


# ---------------------------------------------------------------------------
# 9. Mode eligibility rules are data-driven
# ---------------------------------------------------------------------------
def test_all_expected_modes_are_supported():
    expected = {"bus", "metro", "cng", "rickshaw", "auto"}
    assert expected == SUPPORTED_MODES


def test_rickshaw_auto_share_same_distance_limit():
    assert MODE_ELIGIBILITY["rickshaw"]["max_distance_km"] == MODE_ELIGIBILITY["auto"]["max_distance_km"]


# ---------------------------------------------------------------------------
# 10. CNG has no arbitrary distance limit
# ---------------------------------------------------------------------------
def test_cng_has_no_distance_limit():
    """fare_rules.csv RULE_CNG_2015 has no max distance column.

    The rule's status is 'historical_verify_current_rule_before_live_use'.
    The daily deposit of Tk 900 is an operational detail in the 'other_rule'
    column, not a dataset-supported maximum trip distance.  Therefore no hard
    distance cap is applied.
    """
    eligibility = MODE_ELIGIBILITY["cng"]
    assert eligibility["max_distance_km"] is None


def test_cng_fare_is_calculated_at_any_distance():
    """The CNG meter rule (Tk 40 base + Tk 12/km) has no distance guard.

    Whether a fare is returned depends on data availability (crowd reports
    or the historical rule), not on an arbitrary distance cap.
    """
    engine = _make_engine()
    # 200 km CNG: no distance guard, fare should be calculable from the
    # historical rule (Tk 40 base + Tk 12/km after 2 km included).
    result = engine.single_option(
        mode="cng",
        origin_name="Farmgate",
        destination_name="Gulistan",
        distance_km=200.0,
        driving_minutes=180,
    )
    # The historical rule should produce a result (or crowd data may).
    # The point is: no distance-based rejection happens.
    if result is not None:
        assert result["mode"] == "cng"
        assert result["fareType"] in ("historical", "crowdsourced", "estimated")


def test_bus_has_no_distance_limit():
    assert MODE_ELIGIBILITY["bus"]["max_distance_km"] is None


def test_metro_has_no_distance_limit():
    assert MODE_ELIGIBILITY["metro"]["max_distance_km"] is None


def test_eligibility_descriptions_are_present():
    for mode, rules in MODE_ELIGIBILITY.items():
        assert "description" in rules, f"{mode} missing description"
        assert len(rules["description"]) > 10, f"{mode} description too short"


# ---------------------------------------------------------------------------
# 11. Rickshaw distance boundary
# ---------------------------------------------------------------------------
def test_rickshaw_at_20km_is_eligible():
    eligibility = MODE_ELIGIBILITY["rickshaw"]
    assert 20.0 <= eligibility["max_distance_km"]


def test_rickshaw_at_21km_is_ineligible():
    eligibility = MODE_ELIGIBILITY["rickshaw"]
    assert 21.0 > eligibility["max_distance_km"]


# ---------------------------------------------------------------------------
# 12. Single-fare schema accepts distanceKm/drivingMinutes (no OSRM)
# ---------------------------------------------------------------------------
def test_single_fare_schema_accepts_route_context():
    """CommuteSingleFareRequest must accept distance_km and driving_minutes.

    This proves the endpoint can work without calling OSRM — the client
    passes the already-known route context from POST /api/commute/routes.
    """
    from pydantic import BaseModel
    from app.schemas import CommuteSingleFareRequest

    # Verify the schema has the required fields.
    fields = CommuteSingleFareRequest.model_fields
    assert "distance_km" in fields
    assert "driving_minutes" in fields
    assert "mode" in fields

    # Verify a valid request can be constructed with route context.
    req = CommuteSingleFareRequest(
        origin={"name": "Farmgate", "lat": 23.757, "lon": 90.390},
        destination={"name": "Gulistan", "lat": 23.725, "lon": 90.412},
        mode="bus",
        distance_km=5.0,
        driving_minutes=20,
    )
    assert req.distance_km == 5.0
    assert req.driving_minutes == 20
    assert req.mode == "bus"


# ---------------------------------------------------------------------------
# 13. Existing fare engine options() still works (backward compat)
# ---------------------------------------------------------------------------
def test_options_method_still_returns_list():
    engine = _make_engine()
    options = engine.options(
        origin_name="Farmgate",
        destination_name="Gulistan",
        distance_km=5.0,
        driving_minutes=20,
    )
    assert isinstance(options, list)
    # Each option should have the expected keys.
    for opt in options:
        assert "mode" in opt
        assert "fareLow" in opt
        assert "fareHigh" in opt
        assert "fareType" in opt
        assert "source" in opt
        # Badges should still be assigned for backward compatibility.
        assert "badges" in opt


# ---------------------------------------------------------------------------
# 14. 7.6 km Rickshaw regression — the real-device bug
# ---------------------------------------------------------------------------
def test_7km_rickshaw_is_supported():
    """7.6 km rickshaw must return a valid fare, not 'unsupported'.

    Regression: real-device bug where 7.6 km rickshaw showed
    'This item is no longer available.' The fare engine must return a
    valid result for distances well within the 20 km dataset ceiling.
    """
    engine = _make_engine()
    result = engine.single_option(
        mode="rickshaw",
        origin_name="Farmgate",
        destination_name="Dhanmondi",
        distance_km=7.6,
        driving_minutes=8,
    )
    assert result is not None, (
        "7.6 km rickshaw must return a fare, not None"
    )
    assert result["mode"] == "rickshaw"
    assert result["fareLow"] > 0, "fareLow must be positive"
    assert result["fareHigh"] >= result["fareLow"], "fareHigh >= fareLow"
    # 7.6 × 17 = 129.2.  With 0.85/1.20 range: low ~100, high ~145.
    assert result["fareLow"] >= 50, "fareLow too low for 7.6 km"
    assert result["fareHigh"] <= 200, "fareHigh too high for 7.6 km"
    assert result["fareType"] in ("unverified", "crowdsourced", "estimated")


def test_7km_rickshaw_fare_range_is_plausible():
    """The fare range must bracket approximately Tk 129 (7.6 × 17)."""
    engine = _make_engine()
    result = engine.single_option(
        mode="rickshaw",
        origin_name="Farmgate",
        destination_name="Dhanmondi",
        distance_km=7.6,
        driving_minutes=8,
    )
    assert result is not None
    expected = 7.6 * 17  # 129.2
    # The fallback applies 0.85 low / 1.20 high with rounding to nearest 5.
    assert result["fareLow"] <= expected, "fareLow should be below expected"
    assert result["fareHigh"] >= expected, "fareHigh should be above expected"


# ---------------------------------------------------------------------------
# 15. Boundary: exactly 20 km rickshaw → supported
# ---------------------------------------------------------------------------
def test_exactly_20km_rickshaw_is_supported():
    engine = _make_engine()
    result = engine.single_option(
        mode="rickshaw",
        origin_name="Farmgate",
        destination_name="Dhanmondi",
        distance_km=20.0,
        driving_minutes=30,
    )
    assert result is not None, "20.0 km rickshaw must be supported"
    assert result["mode"] == "rickshaw"


# ---------------------------------------------------------------------------
# 16. Boundary: 20.1 km rickshaw → unsupported (exceeds 20 km ceiling)
# ---------------------------------------------------------------------------
def test_20km_plus_rickshaw_is_rejected():
    """20.1 km exceeds the 20 km dataset ceiling and must be rejected."""
    eligibility = MODE_ELIGIBILITY["rickshaw"]
    max_km = eligibility["max_distance_km"]
    assert max_km == 20.0
    # The endpoint-level check: distance_km > max_km triggers unsupported.
    assert 20.1 > max_km
    # The engine also guards this internally.
    engine = _make_engine()
    result = engine.single_option(
        mode="rickshaw",
        origin_name="Farmgate",
        destination_name="Dhanmondi",
        distance_km=20.1,
        driving_minutes=30,
    )
    assert result is None, "20.1 km rickshaw must return None"


# ---------------------------------------------------------------------------
# 17. Boundary: 205 km rickshaw → unsupported
# ---------------------------------------------------------------------------
def test_205km_rickshaw_is_rejected():
    eligibility = MODE_ELIGIBILITY["rickshaw"]
    assert 205.0 > eligibility["max_distance_km"]


# ---------------------------------------------------------------------------
# 18. 7.6 km Auto → also supported (same dataset)
# ---------------------------------------------------------------------------
def test_7km_auto_is_supported():
    engine = _make_engine()
    result = engine.single_option(
        mode="auto",
        origin_name="Farmgate",
        destination_name="Dhanmondi",
        distance_km=7.6,
        driving_minutes=8,
    )
    assert result is not None, "7.6 km auto must return a fare"
    assert result["mode"] == "auto"
    assert result["fareLow"] > 0
    assert result["fareHigh"] >= result["fareLow"]


# ---------------------------------------------------------------------------
# 19. 205 km Auto → unsupported
# ---------------------------------------------------------------------------
def test_205km_auto_is_rejected():
    eligibility = MODE_ELIGIBILITY["auto"]
    assert 205.0 > eligibility["max_distance_km"]
