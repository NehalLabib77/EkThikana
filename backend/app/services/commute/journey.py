"""Turns a graph path into a journey a student can follow.

The routing engine works in node ids and edge weights. A student needs
sentences and place names. This module is the translation layer, and it is
where spec §1–§3 are enforced: **no internal identifier ever reaches the
response.** Every step names a real place, and every fare states where its
number came from.

It also produces the three route strategies. They are three searches over the
same graph, deduplicated: if CHEAPEST and RECOMMENDED find the same journey,
one result is returned carrying both labels rather than two identical cards.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from app.services.commute.graph import (
    Edge,
    Mode,
    Objective,
    RoutePath,
    TransportGraph,
)

# How a mode is described to a student.
MODE_LABELS: dict[Mode, str] = {
    Mode.WALK: "Walk",
    Mode.RICKSHAW: "Rickshaw",
    Mode.CNG: "CNG",
    Mode.BUS: "Bus",
    Mode.METRO: "Metro",
    Mode.TRAIN: "Train",
    Mode.BOAT: "Launch",
}

# How a fare's provenance is described (spec §24).
FARE_TYPE_LABELS: dict[str, str] = {
    "official": "Official",
    "calculated": "Calculated",
    "crowdsourced": "Reported by riders",
    "historical": "Historical rule",
    "estimated": "Estimated",
    "none": "Free",
}


@dataclass
class JourneyLeg:
    """One continuous stretch on a single mode."""

    mode: Mode
    from_name: str
    to_name: str
    distance_km: float
    minutes: float
    fare_tk: float
    fare_type: str
    fare_source: str
    fare_confidence: str
    service_name: str | None
    instruction: str
    is_transfer_from_previous: bool
    transfer_minutes: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "mode": self.mode.value,
            "modeLabel": MODE_LABELS.get(self.mode, self.mode.value.title()),
            "from": self.from_name,
            "to": self.to_name,
            "distanceKm": round(self.distance_km, 2),
            "durationMinutes": int(round(self.minutes)),
            "fareTk": round(self.fare_tk, 2),
            "fareType": self.fare_type,
            "fareLabel": FARE_TYPE_LABELS.get(self.fare_type, "Estimated"),
            "fareSource": self.fare_source,
            "fareConfidence": self.fare_confidence,
            "serviceName": self.service_name,
            "instruction": self.instruction,
            "isTransfer": self.is_transfer_from_previous,
            "transferMinutes": int(round(self.transfer_minutes)),
        }


@dataclass
class Journey:
    """A complete origin-to-destination journey, ready to render."""

    legs: list[JourneyLeg]
    objectives: list[Objective] = field(default_factory=list)
    origin_name: str = ""
    destination_name: str = ""

    @property
    def total_fare(self) -> float:
        return sum(leg.fare_tk for leg in self.legs)

    @property
    def total_minutes(self) -> float:
        return sum(leg.minutes + leg.transfer_minutes for leg in self.legs)

    @property
    def total_distance_km(self) -> float:
        return sum(leg.distance_km for leg in self.legs)

    @property
    def total_walk_km(self) -> float:
        return sum(leg.distance_km for leg in self.legs if leg.mode is Mode.WALK)

    @property
    def transfer_count(self) -> int:
        return sum(1 for leg in self.legs if leg.is_transfer_from_previous)

    @property
    def mode_summary(self) -> list[str]:
        """"Rickshaw → Metro → Walk" — the at-a-glance sequence (spec §33)."""
        out: list[str] = []
        for leg in self.legs:
            label = MODE_LABELS.get(leg.mode, leg.mode.value.title())
            if not out or out[-1] != label:
                out.append(label)
        return out

    @property
    def fare_certainty(self) -> str:
        """The weakest link in the fare total.

        A journey is only as trustworthy as its least certain leg, so a trip
        with one official metro fare and one negotiated rickshaw fare must not
        present as official.
        """
        types = {leg.fare_type for leg in self.legs if leg.fare_type != "none"}
        if not types:
            return "none"
        for weakest in ("estimated", "historical", "crowdsourced", "calculated"):
            if weakest in types:
                return weakest
        return "official"

    def to_dict(self) -> dict[str, Any]:
        return {
            "objectives": [o.value for o in self.objectives],
            "category": self.objectives[0].value if self.objectives else "alternative",
            "origin": self.origin_name,
            "destination": self.destination_name,
            "totalFareTk": round(self.total_fare, 2),
            "totalDurationMinutes": int(round(self.total_minutes)),
            "totalDistanceKm": round(self.total_distance_km, 2),
            "totalWalkKm": round(self.total_walk_km, 2),
            "transfers": self.transfer_count,
            "modeSummary": self.mode_summary,
            "fareCertainty": self.fare_certainty,
            "fareCertaintyLabel": FARE_TYPE_LABELS.get(self.fare_certainty, "Estimated"),
            "legs": [leg.to_dict() for leg in self.legs],
        }


# ---------------------------------------------------------------------------
# Path -> Journey
# ---------------------------------------------------------------------------


def _instruction(
    edge: Edge,
    from_name: str,
    to_name: str,
    distance_km: float | None = None,
) -> str:
    """A sentence the student can act on (spec §23).

    Built only from data we actually have. No platform numbers, no gate
    numbers, no compass directions — none of which are in the dataset.
    """
    label = MODE_LABELS.get(edge.mode, edge.mode.value)
    # A leg can be several merged edges, so the distance shown must be the
    # leg's total rather than the first edge's. Passing the wrong one
    # produced "Walk about 0 m" on a 0.8 km walk.
    distance = edge.distance_km if distance_km is None else distance_km

    if edge.mode is Mode.WALK:
        metres = int(round(distance * 1000))
        if metres < 1000:
            # Round to the nearest 10 m: "about 137 m" implies a precision
            # straight-line distance between two stops does not have.
            return f"Walk about {max(10, round(metres / 10) * 10)} m to {to_name}."
        return f"Walk about {distance:.1f} km to {to_name}."
    if edge.mode is Mode.METRO:
        line = edge.service_name or "the metro"
        return f"Board {line} at {from_name} and get off at {to_name}."
    if edge.mode is Mode.BUS:
        if edge.service_name:
            return f"Take the {edge.service_name} bus from {from_name} to {to_name}."
        return f"Take a bus from {from_name} towards {to_name}."
    if edge.mode is Mode.TRAIN:
        service = f" ({edge.service_name})" if edge.service_name else ""
        return f"Board the train{service} at {from_name} and get off at {to_name}."
    if edge.mode is Mode.BOAT:
        return f"Take the launch from {from_name} to {to_name}."
    if edge.mode.is_hired:
        return f"Take a {label.lower()} to {to_name}."
    return f"{label} to {to_name}."


def path_to_journey(path: RoutePath, graph: TransportGraph) -> Journey:
    """Collapse consecutive same-service legs and attach human names."""
    policy = graph.policy
    legs: list[JourneyLeg] = []
    previous_mode: Mode | None = None

    # Merge runs of the same mode *and* same service into one leg: riding
    # four consecutive bus stops is one instruction, not four.
    merged: list[list[Edge]] = []
    for edge in path.edges:
        if (
            merged
            and merged[-1][-1].mode == edge.mode
            and merged[-1][-1].service_id == edge.service_id
            and merged[-1][-1].route_id == edge.route_id
        ):
            merged[-1].append(edge)
        else:
            merged.append([edge])

    for run in merged:
        first, last = run[0], run[-1]
        from_name = graph.nodes[first.from_node].name
        to_name = graph.nodes[last.to_node].name

        distance = sum(e.distance_km for e in run)
        minutes = sum(e.minutes for e in run)
        fare = sum(e.fare_tk for e in run)

        is_transfer = previous_mode is not None and first.mode != previous_mode
        boarding = policy.waiting_for(first.mode)
        transfer_time = (policy.transfer_minutes if is_transfer else 0.0) + boarding

        legs.append(
            JourneyLeg(
                mode=first.mode,
                from_name=from_name,
                to_name=to_name,
                distance_km=distance,
                minutes=minutes,
                fare_tk=fare,
                # The weakest fare in the run governs the whole leg.
                fare_type=_weakest_fare_type([e.fare_type for e in run]),
                fare_source=first.fare_source,
                fare_confidence=first.fare_confidence,
                service_name=first.service_name,
                instruction=_instruction(first, from_name, to_name, distance),
                is_transfer_from_previous=is_transfer,
                transfer_minutes=transfer_time,
            )
        )
        previous_mode = first.mode

    origin = graph.nodes[path.edges[0].from_node].name if path.edges else ""
    destination = graph.nodes[path.edges[-1].to_node].name if path.edges else ""
    return Journey(legs=legs, origin_name=origin, destination_name=destination)


def _weakest_fare_type(types: list[str]) -> str:
    order = ["estimated", "historical", "crowdsourced", "calculated", "official", "none"]
    for candidate in order:
        if candidate in types:
            return candidate
    return "estimated"


# ---------------------------------------------------------------------------
# The three strategies
# ---------------------------------------------------------------------------


def plan_journeys(
    graph: TransportGraph,
    origin_node: str,
    destination_node: str,
) -> list[Journey]:
    """Recommended, Cheapest and Fastest — deduplicated.

    Spec §8: never return three identical routes under different labels. When
    two objectives find the same journey it is returned once, carrying both
    labels, and the UI can say so.
    """
    found: dict[tuple, Journey] = {}
    order: list[tuple] = []

    for objective in (Objective.RECOMMENDED, Objective.CHEAPEST, Objective.FASTEST):
        path = graph.find_route(origin_node, destination_node, objective)
        if path is None or not path.edges:
            continue
        signature = path.signature()
        if signature in found:
            found[signature].objectives.append(objective)
            continue
        journey = path_to_journey(path, graph)
        journey.objectives = [objective]
        found[signature] = journey
        order.append(signature)

    return [found[s] for s in order]


def compare_journeys(journeys: list[Journey]) -> list[dict[str, Any]]:
    """Differences against the recommended option (spec §45).

    Gives the UI "saves ৳65, takes 21 min longer" instead of making the
    student subtract two numbers themselves.
    """
    if not journeys:
        return []
    baseline = journeys[0]
    out: list[dict[str, Any]] = []
    for journey in journeys:
        payload = journey.to_dict()
        if journey is not baseline:
            payload["fareDeltaTk"] = round(journey.total_fare - baseline.total_fare, 2)
            payload["durationDeltaMinutes"] = int(
                round(journey.total_minutes - baseline.total_minutes)
            )
        else:
            payload["fareDeltaTk"] = 0
            payload["durationDeltaMinutes"] = 0
        out.append(payload)
    return out


def explain(journey: Journey, alternatives: list[Journey]) -> str | None:
    """Why this journey is the recommended one (spec §44).

    Generated only from real measured differences. Returns None rather than
    inventing a reason when there is nothing meaningful to say.
    """
    if Objective.RECOMMENDED not in journey.objectives or not alternatives:
        return None

    cheapest = min(alternatives, key=lambda j: j.total_fare)
    fastest = min(alternatives, key=lambda j: j.total_minutes)

    saved_vs_fastest = fastest.total_fare - journey.total_fare
    slower_than_fastest = journey.total_minutes - fastest.total_minutes
    if saved_vs_fastest > 20 and slower_than_fastest <= 15:
        return (
            f"Only {int(round(slower_than_fastest))} minutes slower than the "
            f"fastest option, but about ৳{int(round(saved_vs_fastest))} cheaper."
        )

    faster_than_cheapest = cheapest.total_minutes - journey.total_minutes
    extra_vs_cheapest = journey.total_fare - cheapest.total_fare
    if faster_than_cheapest > 15 and extra_vs_cheapest <= 60:
        return (
            f"About {int(round(faster_than_cheapest))} minutes faster than the "
            f"cheapest option for around ৳{int(round(extra_vs_cheapest))} more."
        )

    if journey.transfer_count < min(a.transfer_count for a in alternatives):
        return "Fewer changes of transport than the alternatives."

    return None
