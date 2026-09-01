"""Quality validation for community-submitted fare reports.

A crowdsourced fare dataset is only as good as what it refuses to accept. Left
unchecked, three things poison it:

  * **Impossible fares** — ``5`` for a 20 km CNG trip, or ``5000`` for a
    two-stop bus ride. Usually a slip of the thumb, occasionally deliberate.
  * **Duplicates** — a double tap, or a retry after a request timed out,
    turning one trip into three data points and triple-weighting it.
  * **Outliers** — one genuine-looking but wildly atypical fare dragging a
    median that a student then trusts.

Every band below is derived from ``data/commutebd/core_dataset/csv/
fare_rules.csv``, which is the dataset shipped with the app, and each is
attributed in ``_REFERENCE``. Nothing here is tuned to make a number look
good; the tolerance factors are wide precisely so that this rejects what is
*impossible* rather than what is merely surprising.

Nothing in this module fabricates a fare. It only ever says "accept",
"flag for a human" or "reject, and here is why".
"""
from __future__ import annotations

from dataclasses import dataclass, field
from statistics import median
from typing import Any

# ---------------------------------------------------------------------------
# Reference fares, straight from the shipped dataset
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ModeReference:
    """What a fare for this mode should look like, and how far it may stray.

    ``base_tk`` + ``per_km_tk`` reproduces the rule the dataset states.
    Modelling the base separately matters: a 0.5 km CNG trip legitimately
    costs far more per kilometre than a 15 km one, so a flat taka-per-km band
    would reject every short hired trip in the city.
    """

    base_tk: float
    per_km_tk: float
    included_km: float

    # Multipliers applied to the reference fare. Asymmetric on purpose: in
    # Dhaka a hired fare is routinely negotiated well *above* the gazetted
    # meter and almost never far below it, so the ceiling is generous and the
    # floor is not.
    low_factor: float
    high_factor: float

    # Hard limits, independent of distance. These catch a report whose
    # distance was never recorded, where the reference model cannot help.
    absolute_min_tk: float
    absolute_max_tk: float

    # Fastest believable average speed door to door, used only when both a
    # distance and a duration were reported.
    max_kmh: float

    # Where the numbers came from.
    source: str


_REFERENCE: dict[str, ModeReference] = {
    # RULE_BUS_DHAKA_METRO: minimum Tk 10, Tk 2.45/km.
    "bus": ModeReference(
        base_tk=10.0,
        per_km_tk=2.45,
        included_km=0.0,
        low_factor=0.6,
        high_factor=3.0,
        absolute_min_tk=5.0,
        absolute_max_tk=800.0,
        max_kmh=60.0,
        source="RULE_BUS_DHAKA_METRO (BRTA metropolitan bus fare)",
    ),
    # RULE_METRO_MRT6: station-to-station matrix, Tk 20 minimum, Tk 100 cap.
    # The fare is a published matrix rather than a formula, so the band is
    # simply the published range.
    "metro": ModeReference(
        base_tk=20.0,
        per_km_tk=0.0,
        included_km=0.0,
        low_factor=1.0,
        high_factor=5.0,
        absolute_min_tk=15.0,
        absolute_max_tk=110.0,
        max_kmh=45.0,
        source="RULE_METRO_MRT6 (DMTCL published fare table)",
    ),
    # RULE_CNG_2015: Tk 40 covering the first 2 km, then Tk 12/km. Historical,
    # and universally exceeded in practice -- hence the wide ceiling.
    "cng": ModeReference(
        base_tk=40.0,
        per_km_tk=12.0,
        included_km=2.0,
        low_factor=0.5,
        high_factor=6.0,
        absolute_min_tk=20.0,
        absolute_max_tk=3000.0,
        max_kmh=60.0,
        source="RULE_CNG_2015 (2015 government meter gazette, historical)",
    ),
    # RULE_RICKSHAW_USER_ESTIMATE_17: Tk 17/km, explicitly labelled in the
    # dataset as a user-provided estimate rather than an official rule.
    "rickshaw": ModeReference(
        base_tk=0.0,
        per_km_tk=17.0,
        included_km=0.0,
        low_factor=0.4,
        high_factor=4.0,
        absolute_min_tk=5.0,
        absolute_max_tk=600.0,
        max_kmh=25.0,
        source="RULE_RICKSHAW_USER_ESTIMATE_17 (dataset estimate, not official)",
    ),
}

# Reported as a distinct mode by the app, priced by the same estimate.
_REFERENCE["auto"] = _REFERENCE["rickshaw"]

#: A trip nobody could physically have made in the time reported.
_MIN_PLAUSIBLE_KMH = 1.0


# ---------------------------------------------------------------------------
# Verdicts
# ---------------------------------------------------------------------------


@dataclass
class QualityVerdict:
    """What should happen to one report, and why.

    Three outcomes rather than two. ``rejected`` is for a report that cannot
    describe a real trip; ``suspect`` is for one that could be real but is far
    enough from the reference that a human should look before it counts as
    evidence. Silently discarding the second kind would quietly delete the
    very trips that most need recording -- an unusually expensive route is
    exactly what a student wants warning about.
    """

    verdict: str  # "accepted" | "suspect" | "rejected"
    reasons: list[str] = field(default_factory=list)
    expected_tk: float | None = None

    @property
    def accepted(self) -> bool:
        return self.verdict == "accepted"

    @property
    def rejected(self) -> bool:
        return self.verdict == "rejected"

    def to_dict(self) -> dict[str, Any]:
        return {
            "verdict": self.verdict,
            "reasons": list(self.reasons),
            "expectedTk": None if self.expected_tk is None else round(self.expected_tk, 2),
        }


def expected_fare_tk(mode: str, distance_km: float) -> float | None:
    """The dataset's own estimate for this trip, or None for unknown modes."""
    reference = _REFERENCE.get((mode or "").strip().lower())
    if reference is None or distance_km is None or distance_km <= 0:
        return None
    charged_km = max(0.0, float(distance_km) - reference.included_km)
    return reference.base_tk + charged_km * reference.per_km_tk


def validate_report(
    *,
    mode: str,
    fare_tk: float,
    distance_km: float | None = None,
    trip_minutes: int | None = None,
    passenger_count: int | None = None,
) -> QualityVerdict:
    """Check one report against physics and against the shipped fare rules."""
    normalised = (mode or "").strip().lower()
    reasons: list[str] = []

    # Walking is free by definition, so a paid walk is a mis-tagged mode
    # rather than a fare worth keeping.
    if normalised == "walk":
        if fare_tk and fare_tk > 0:
            return QualityVerdict("rejected", ["A walking trip cannot have a fare."])
        return QualityVerdict("accepted")

    if fare_tk is None or fare_tk <= 0:
        return QualityVerdict("rejected", ["Fare must be greater than zero."])

    reference = _REFERENCE.get(normalised)
    if reference is None:
        # An unknown mode is not evidence of anything. Flag rather than reject
        # -- the app may legitimately gain a mode before this table does.
        return QualityVerdict(
            "suspect",
            [f"No fare reference exists for the mode '{mode}'."],
        )

    if fare_tk < reference.absolute_min_tk:
        reasons.append(
            f"Tk {fare_tk:.0f} is below the lowest plausible {normalised} fare "
            f"(Tk {reference.absolute_min_tk:.0f})."
        )
    if fare_tk > reference.absolute_max_tk:
        reasons.append(
            f"Tk {fare_tk:.0f} is above the highest plausible {normalised} fare "
            f"(Tk {reference.absolute_max_tk:.0f})."
        )
    if reasons:
        return QualityVerdict("rejected", reasons)

    # A trip that could not have happened in the time reported.
    if distance_km and distance_km > 0 and trip_minutes and trip_minutes > 0:
        kmh = float(distance_km) / (float(trip_minutes) / 60.0)
        if kmh > reference.max_kmh:
            return QualityVerdict(
                "rejected",
                [
                    f"{distance_km:.1f} km in {trip_minutes} minutes is "
                    f"{kmh:.0f} km/h, which a {normalised} cannot sustain."
                ],
            )
        if kmh < _MIN_PLAUSIBLE_KMH:
            return QualityVerdict(
                "rejected",
                [
                    f"{distance_km:.1f} km in {trip_minutes} minutes is "
                    f"{kmh:.1f} km/h, slower than walking pace."
                ],
            )

    if passenger_count is not None and not (1 <= passenger_count <= 12):
        return QualityVerdict(
            "rejected",
            [f"A passenger count of {passenger_count} is not plausible."],
        )

    expected = expected_fare_tk(normalised, distance_km or 0)
    if expected is None or expected <= 0:
        # No distance was recorded, so only the absolute band could be
        # checked. Say so rather than implying a check that did not happen.
        return QualityVerdict(
            "accepted",
            ["No trip distance was reported, so only the absolute fare range was checked."],
        )

    floor = expected * reference.low_factor
    ceiling = expected * reference.high_factor

    if fare_tk < floor:
        return QualityVerdict(
            "suspect",
            [
                f"Tk {fare_tk:.0f} is well below the Tk {expected:.0f} the "
                f"{reference.source} implies for {distance_km:.1f} km."
            ],
            expected_tk=expected,
        )
    if fare_tk > ceiling:
        return QualityVerdict(
            "suspect",
            [
                f"Tk {fare_tk:.0f} is well above the Tk {expected:.0f} the "
                f"{reference.source} implies for {distance_km:.1f} km."
            ],
            expected_tk=expected,
        )

    return QualityVerdict("accepted", expected_tk=expected)


# ---------------------------------------------------------------------------
# Outlier removal
# ---------------------------------------------------------------------------


@dataclass
class OutlierResult:
    kept: list[float]
    removed: list[float]

    @property
    def removed_count(self) -> int:
        return len(self.removed)


def remove_outliers(fares: list[float], *, threshold: float = 3.5) -> OutlierResult:
    """Drop fares too far from the median to be evidence.

    Uses the median absolute deviation rather than the standard deviation:
    the mean and the standard deviation are both dragged by the very outlier
    being looked for, so a single Tk 5,000 typo in a sample of thirty Tk 30
    fares would widen the band enough to hide itself.

    Samples smaller than four are returned untouched -- with three points
    there is not enough information to call any of them wrong, and pruning
    would only manufacture false confidence.
    """
    values = [float(f) for f in fares if f is not None]
    if len(values) < 4:
        return OutlierResult(kept=values, removed=[])

    centre = median(values)
    deviations = [abs(value - centre) for value in values]
    mad = median(deviations)

    if mad == 0:
        # Most of the sample is identical. Anything that is not is either a
        # different trip or a mistake; either way it is not evidence about
        # this one. Fall back to a proportional band around the median.
        kept = [v for v in values if abs(v - centre) <= max(5.0, centre * 0.5)]
        removed = [v for v in values if v not in kept]
        return OutlierResult(kept=kept, removed=removed)

    # 0.6745 rescales the MAD so the threshold is comparable to a standard
    # deviation for normally distributed data.
    kept: list[float] = []
    removed: list[float] = []
    for value in values:
        score = 0.6745 * abs(value - centre) / mad
        (removed if score > threshold else kept).append(value)

    # Never prune away the evidence entirely.
    if not kept:
        return OutlierResult(kept=values, removed=[])
    return OutlierResult(kept=kept, removed=removed)


# ---------------------------------------------------------------------------
# Duplicate detection
# ---------------------------------------------------------------------------


def duplicate_key(
    *,
    user_id_hash: str,
    mode: str,
    origin: str,
    destination: str,
    fare_tk: float,
    when,
    bucket_hours: int = 1,
) -> str:
    """A stable key for "the same person reporting the same trip twice".

    The window is an hour, not a minute. The duplicates that actually occur
    are double taps and retries after a timeout, and a minute-wide bucket lets
    a retry at 12:00:59 land in a different bucket from the original at
    12:00:58 -- which is exactly the case the constraint exists to stop.
    A genuine second identical trip on the same route within the hour is rare
    enough to be worth losing; the return leg has its endpoints reversed and
    keys differently, so commuting is unaffected.
    """
    import hashlib

    hours = max(1, int(bucket_hours))
    bucket = when.replace(
        hour=(when.hour // hours) * hours,
        minute=0,
        second=0,
        microsecond=0,
    )
    raw = (
        f"{user_id_hash}|{(mode or '').strip().lower()}|"
        f"{(origin or '').strip().lower()}|{(destination or '').strip().lower()}|"
        f"{float(fare_tk):.2f}|{bucket.isoformat()}"
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


__all__ = [
    "ModeReference",
    "OutlierResult",
    "QualityVerdict",
    "duplicate_key",
    "expected_fare_tk",
    "remove_outliers",
    "validate_report",
]
