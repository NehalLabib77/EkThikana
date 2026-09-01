"""Guards for fare-report quality control and for ML honesty.

Two things are being pinned here.

The first is that the crowdsourced dataset refuses what cannot be true. These
tests use real Dhaka numbers rather than round fixtures, because the bands
being checked are derived from the shipped ``fare_rules.csv`` and a fixture
that ignores that would prove nothing about the shipped behaviour.

The second is the one the spec is emphatic about: **nothing may present a
rule-based estimate as a model prediction, and the model must stay off until
the data actually exists.** The last group is a static guard over the fare
engine's own source, so it holds for code written after this file too.
"""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from app.services.commute.fare_quality import (
    duplicate_key,
    expected_fare_tk,
    remove_outliers,
    validate_report,
)
from app.services.commute.ml_status import readiness, summary_line


# ---------------------------------------------------------------------------
# Impossible fares
# ---------------------------------------------------------------------------


def test_a_plausible_rickshaw_fare_is_accepted():
    # Tk 17/km is the dataset's own rickshaw estimate, so 3 km at Tk 55 sits
    # almost exactly on it.
    verdict = validate_report(
        mode="rickshaw", fare_tk=55, distance_km=3.0, trip_minutes=18
    )

    assert verdict.accepted
    assert verdict.expected_tk == 51.0


def test_a_five_taka_twenty_kilometre_cng_trip_is_rejected():
    # The 2015 meter rule puts this near Tk 256. Tk 5 is not a cheap trip,
    # it is a typo.
    verdict = validate_report(mode="cng", fare_tk=5, distance_km=20.0)

    assert verdict.rejected
    assert "below the lowest plausible" in verdict.reasons[0]


def test_a_five_thousand_taka_bus_fare_is_rejected():
    verdict = validate_report(mode="bus", fare_tk=5000, distance_km=4.0)

    assert verdict.rejected
    assert "above the highest plausible" in verdict.reasons[0]


def test_a_metro_fare_above_the_published_cap_is_rejected():
    # MRT Line 6 is capped at Tk 100 by DMTCL. Tk 250 cannot have been paid.
    assert validate_report(mode="metro", fare_tk=250, distance_km=12.0).rejected


def test_a_walking_trip_cannot_have_a_fare():
    assert validate_report(mode="walk", fare_tk=20).rejected
    assert validate_report(mode="walk", fare_tk=0).accepted


def test_a_zero_or_negative_fare_is_rejected():
    assert validate_report(mode="bus", fare_tk=0).rejected
    assert validate_report(mode="bus", fare_tk=-10).rejected


# ---------------------------------------------------------------------------
# Impossible trips
# ---------------------------------------------------------------------------


def test_a_rickshaw_at_highway_speed_is_rejected():
    # 30 km in 20 minutes is 90 km/h. Not on a rickshaw.
    verdict = validate_report(
        mode="rickshaw", fare_tk=500, distance_km=30.0, trip_minutes=20
    )

    assert verdict.rejected
    assert "km/h" in verdict.reasons[0]


def test_a_trip_slower_than_walking_is_rejected():
    verdict = validate_report(
        mode="cng", fare_tk=200, distance_km=0.5, trip_minutes=600
    )

    assert verdict.rejected
    assert "slower than walking pace" in verdict.reasons[0]


def test_a_realistic_dhaka_bus_crawl_is_still_accepted():
    # 6 km in 55 minutes is 6.5 km/h -- miserable, and completely normal.
    # The speed check must not reject real Dhaka traffic.
    verdict = validate_report(
        mode="bus", fare_tk=15, distance_km=6.0, trip_minutes=55
    )

    assert verdict.accepted


def test_an_implausible_passenger_count_is_rejected():
    assert validate_report(
        mode="cng", fare_tk=200, distance_km=8.0, passenger_count=40
    ).rejected


# ---------------------------------------------------------------------------
# Suspect, not rejected
# ---------------------------------------------------------------------------


def test_an_unusually_expensive_but_possible_fare_is_flagged_not_discarded():
    # The 2015 meter puts 5 km at Tk 76. Tk 600 is eight times that -- steep
    # even for a downpour, but not physically impossible, so it is kept and
    # flagged rather than thrown away. An unusually expensive route is
    # exactly what a student wants warning about.
    verdict = validate_report(mode="cng", fare_tk=600, distance_km=5.0)

    assert verdict.verdict == "suspect"
    assert not verdict.rejected
    assert verdict.expected_tk == 76.0


def test_a_steep_but_ordinary_dhaka_cng_fare_is_accepted():
    # Tk 250 for 5 km is roughly three times the 2015 meter and completely
    # routine in practice. The band exists to catch the impossible, not to
    # second-guess what drivers actually charge.
    assert validate_report(mode="cng", fare_tk=250, distance_km=5.0).accepted


def test_an_unknown_mode_is_flagged_rather_than_rejected():
    # The app may gain a mode before this table does. Refusing the report
    # would lose real data over a table that is merely out of date.
    verdict = validate_report(mode="tempo", fare_tk=25, distance_km=4.0)

    assert verdict.verdict == "suspect"
    assert "tempo" in verdict.reasons[0]


def test_a_report_without_a_distance_says_what_was_not_checked():
    verdict = validate_report(mode="rickshaw", fare_tk=60)

    assert verdict.accepted
    assert "only the absolute fare range was checked" in verdict.reasons[0]
    assert verdict.expected_tk is None


def test_expected_fare_follows_the_shipped_rule():
    # RULE_CNG_2015: Tk 40 covers the first 2 km, then Tk 12/km.
    assert expected_fare_tk("cng", 2.0) == 40.0
    assert expected_fare_tk("cng", 10.0) == 40.0 + 8 * 12.0
    # RULE_BUS_DHAKA_METRO: Tk 10 minimum, Tk 2.45/km.
    assert expected_fare_tk("bus", 10.0) == 10.0 + 24.5
    assert expected_fare_tk("nonsense", 5.0) is None


# ---------------------------------------------------------------------------
# Outliers
# ---------------------------------------------------------------------------


def test_a_single_typo_is_pruned_from_a_consistent_sample():
    fares = [30.0, 30.0, 35.0, 30.0, 40.0, 30.0, 35.0, 5000.0]

    result = remove_outliers(fares)

    assert 5000.0 in result.removed
    assert result.removed_count == 1
    assert sorted(result.kept) == [30.0, 30.0, 30.0, 30.0, 35.0, 35.0, 40.0]


def test_pruning_uses_the_median_not_the_mean():
    # The mean of this sample is ~650 and its standard deviation is enormous,
    # so a mean/sigma rule would keep the 5000 by widening the band around
    # it. The median-based rule does not have that blind spot.
    fares = [30.0] * 8 + [5000.0]

    assert 5000.0 in remove_outliers(fares).removed


def test_a_genuinely_spread_sample_is_left_alone():
    # Real fares on a long route vary. Nothing here is impossible, so nothing
    # should be discarded.
    fares = [80.0, 100.0, 120.0, 90.0, 150.0, 110.0]

    assert remove_outliers(fares).removed == []


def test_a_tiny_sample_is_never_pruned():
    # With three points there is not enough information to call any of them
    # wrong; pruning would only manufacture confidence.
    fares = [30.0, 35.0, 900.0]

    result = remove_outliers(fares)

    assert result.removed == []
    assert result.kept == fares


def test_pruning_never_empties_the_sample():
    result = remove_outliers([10.0, 500.0, 10.0, 500.0])

    assert result.kept


# ---------------------------------------------------------------------------
# Duplicates
# ---------------------------------------------------------------------------


def _key(when, **overrides):
    payload = dict(
        user_id_hash="abc",
        mode="cng",
        origin="Mirpur 10",
        destination="Farmgate",
        fare_tk=250.0,
        when=when,
    )
    payload.update(overrides)
    return duplicate_key(**payload)


def test_a_retry_seconds_later_collides_with_the_original():
    # The bug the old minute-wide bucket had: 12:00:58 and 12:00:59 fell into
    # different buckets whenever the retry crossed a minute boundary, so the
    # duplicate slipped through the very constraint meant to stop it.
    first = _key(datetime(2026, 9, 1, 12, 0, 58, tzinfo=timezone.utc))
    retry = _key(datetime(2026, 9, 1, 12, 1, 2, tzinfo=timezone.utc))

    assert first == retry


def test_the_same_trip_hours_later_is_not_a_duplicate():
    morning = _key(datetime(2026, 9, 1, 8, 0, tzinfo=timezone.utc))
    evening = _key(datetime(2026, 9, 1, 19, 0, tzinfo=timezone.utc))

    assert morning != evening


def test_the_return_leg_is_not_a_duplicate():
    when = datetime(2026, 9, 1, 8, 0, tzinfo=timezone.utc)
    out = _key(when)
    back = _key(when, origin="Farmgate", destination="Mirpur 10")

    assert out != back


def test_a_different_fare_is_not_a_duplicate():
    when = datetime(2026, 9, 1, 8, 0, tzinfo=timezone.utc)

    assert _key(when) != _key(when, fare_tk=260.0)


def test_a_different_user_is_not_a_duplicate():
    when = datetime(2026, 9, 1, 8, 0, tzinfo=timezone.utc)

    assert _key(when) != _key(when, user_id_hash="xyz")


# ---------------------------------------------------------------------------
# ML readiness
# ---------------------------------------------------------------------------


class _Crowd:
    """A stand-in report database with a known, stated number of reports."""

    def __init__(self, enabled=True, total=0, per_mode=None, raises=False):
        self.enabled = enabled
        self._total = total
        self._per_mode = per_mode or {}
        self._raises = raises

    def count_approved(self, *, mode=None):
        if self._raises:
            raise RuntimeError("database unreachable")
        return self._per_mode.get(mode, 0) if mode else self._total


def test_readiness_reports_the_real_shortfall():
    report = readiness(_Crowd(total=12, per_mode={"rickshaw": 9, "cng": 3}))

    assert report["active"] is False
    assert report["dataAvailable"] is True
    assert report["totalApprovedReports"] == 12
    assert report["thresholds"]["totalApprovedReports"] == 500
    assert report["modes"]["rickshaw"]["shortfall"] == 141
    assert report["modes"]["cng"]["shortfall"] == 147
    # The shortfall must be stated, not implied.
    assert any("488 short" in blocker for blocker in report["blockers"])


def test_an_unreachable_database_reports_unknown_not_zero():
    # "We have no reports" and "we cannot see how many reports we have" are
    # different facts, and only one of them is a reason to keep collecting.
    report = readiness(_Crowd(enabled=False))

    assert report["active"] is False
    assert report["dataAvailable"] is False
    assert report["reason"] == "database_unavailable"
    assert "unknown, not zero" in report["blockers"][0]
    assert "totalApprovedReports" not in report


def test_a_failing_count_query_also_reports_unknown():
    report = readiness(_Crowd(raises=True))

    assert report["dataAvailable"] is False
    assert report["reason"] == "count_query_failed"


def test_readiness_names_what_fares_are_actually_based_on_today():
    report = readiness(_Crowd(total=12, per_mode={"rickshaw": 9, "cng": 3}))

    assert report["fareLabelInUse"] == "rule-based and crowdsourced estimates only"


def test_readiness_only_activates_when_every_threshold_is_met():
    # Meeting the total but not a per-mode minimum must not flip it on.
    partial = readiness(_Crowd(total=900, per_mode={"rickshaw": 800, "cng": 4}))
    assert partial["active"] is False
    assert partial["modes"]["rickshaw"]["ready"] is True
    assert partial["modes"]["cng"]["ready"] is False

    full = readiness(_Crowd(total=900, per_mode={"rickshaw": 500, "cng": 400}))
    assert full["active"] is True
    assert full["blockers"] == []
    assert full["fareLabelInUse"] == "quantile model on approved reports"


def test_the_summary_line_never_claims_zero_when_it_means_unknown():
    assert "unknown" in summary_line(readiness(_Crowd(enabled=False)))
    assert "inactive" in summary_line(readiness(_Crowd(total=3)))


# ---------------------------------------------------------------------------
# No fabricated ML
# ---------------------------------------------------------------------------


def test_the_model_refuses_to_load_below_the_threshold():
    from app.services.commute.ml_fare import MLFarePredictionService

    service = MLFarePredictionService()
    service.crowd = _Crowd(total=10, per_mode={"rickshaw": 5, "cng": 2})

    assert service.enabled_for("rickshaw") is False
    assert service.enabled_for("cng") is False
    # And it produces nothing rather than a plausible-looking guess.
    assert service.predict(mode="rickshaw", distance_km=4.0) is None


def test_the_model_is_never_used_for_published_fares():
    # Bus and metro fares are published. Predicting them would replace a
    # known number with a guess.
    from app.services.commute.ml_fare import MLFarePredictionService

    service = MLFarePredictionService()
    service.crowd = _Crowd(total=9000, per_mode={"bus": 9000, "metro": 9000})

    assert service.enabled_for("bus") is False
    assert service.enabled_for("metro") is False


def test_no_rule_based_estimate_is_labelled_as_a_model_prediction():
    # A static guard over the fare engine's own source: only ml_fare.py may
    # attach a model-sounding source string to a fare. If a rule-based branch
    # ever starts calling itself a model, this fails.
    engine = Path("app/services/commute/fare_engine.py").read_text(encoding="utf-8")

    for claim in ("ML model", "ML Estimate", "quantile ML", "predicted by", "AI estimate"):
        assert claim not in engine, f"fare_engine.py must not claim '{claim}'"


def test_the_only_model_labelled_source_lives_behind_the_activation_gate():
    ml = Path("app/services/commute/ml_fare.py").read_text(encoding="utf-8")

    # The model names itself honestly ...
    assert "Verified-report quantile ML model" in ml
    # ... and its own output is still typed as an estimate, not as official.
    assert '"fareType": "estimated"' in ml
    # ... and predict() cannot return without _load(), which is gated.
    assert "bundle = self._load(mode)" in ml
    assert "if not bundle:\n            return None" in ml
