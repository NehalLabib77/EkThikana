"""Derive committed coordinates for CommuteBD places from the OSM master set.

Why this exists
---------------
Every one of the 387 rows in ``places.csv`` and all 17 metro stations ship
with ``geocode_status = pending`` and no latitude/longitude. Without
coordinates the router cannot do three things it must do:

  * snap a student's actual location onto the transport network,
  * create walking transfers between a metro station and a nearby bus stop,
  * draw the journey on a map.

The CommuteBD Bangladesh Master dataset supplies ~27,000 named OSM features
with coordinates. This script matches the two by name and writes a small
committed asset, so the router has coordinates without shipping the 87 MB
master dataset or depending on a live geocoder at request time.

Usage
-----
    python scripts/build_commute_geocode_asset.py --master /path/to/CommuteBD_Bangladesh_Master_v1

Output
------
    data/commutebd/derived/place_coordinates.csv

Every row records where its coordinates came from and how confident the match
is, so a weak match can be excluded later rather than silently trusted. Places
that do not match are simply absent — the router treats a place without
coordinates as network-only (it can still be ridden through, it just cannot
anchor a walk or a snap).
"""
from __future__ import annotations

import argparse
import csv
import re
import unicodedata
import math
from collections import defaultdict
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
CORE = BACKEND / "data" / "commutebd" / "core_dataset" / "csv"
OUT_DIR = BACKEND / "data" / "commutebd" / "derived"

# Words that describe the *kind* of place rather than which place it is.
# "Farmgate Bus Stop" and "Farmgate" are the same location for our purposes.
_GENERIC = re.compile(
    r"\b(bus\s*stand|bus\s*stop|bus\s*terminal|stand|stop|station|metro\s*station"
    r"|railway\s*station|rail\s*station|terminal|ghat|mor|more|morh|circle"
    r"|intersection|crossing|roundabout|gate|bazar|bazaar|market|road|rd)\b"
)
# Bracketed qualifiers: "Abdullahpur (Jail)" -> "Abdullahpur".
_BRACKET = re.compile(r"\([^)]*\)")

# OSM feature classes that can plausibly be a transport node or a landmark a
# student would name. Excludes things like `fuel` or `atm` that would produce
# confident-looking but wrong matches.
# Features that are transport infrastructure. A weak name match is only
# trusted for these — see the subset tier in OsmIndex.lookup.
_TRANSPORT_FCLASS = {
    "bus_stop", "bus_station", "railway_station", "station", "halt",
    "ferry_terminal", "tram_stop", "subway_entrance", "taxi",
}

_USEFUL_FCLASS = {
    "bus_stop", "bus_station", "railway_station", "station", "halt",
    "ferry_terminal", "tram_stop", "subway_entrance", "taxi",
    "suburb", "neighbourhood", "quarter", "town", "village", "city",
    "university", "college", "school", "hospital", "marketplace",
}


def normalise(value: str) -> str:
    """Comparison key that *keeps* what is inside brackets.

    The dataset writes "Mirpur(10)" and "Azimpur (Dhakeswari)"; OSM writes
    "Mirpur 10". Deleting the bracketed part -- which is what this used to do
    -- reduced both to "mirpur" and "azimpur", throwing away the only thing
    that says *which* Mirpur. That is how Mirpur 10 ended up matched 126 km
    from Dhaka. The brackets go; their contents stay.
    """
    text = unicodedata.normalize("NFKC", value or "").lower().strip()
    text = re.sub(r"[^a-z0-9ঀ-৿]+", " ", text)
    return " ".join(text.split())


def _strip_bracket(value: str) -> str:
    """The name with any bracketed part removed, as a fallback.

    "Azimpur (Dhakeswari)" is listed in OSM simply as "Azimpur", so the
    bracketed form is tried first and this second. Returns a raw name, not a
    key, so it can be run through every matching tier in turn.
    """
    text = unicodedata.normalize("NFKC", value or "")
    return " ".join(_BRACKET.sub(" ", text).split())


def _unique(*values: str) -> list[str]:
    """Non-empty values in order, without repeats."""
    seen: list[str] = []
    for value in values:
        if value and value not in seen:
            seen.append(value)
    return seen


def core_name(value: str) -> str:
    """Normalised name with generic place-type words removed."""
    stripped = " ".join(_GENERIC.sub(" ", normalise(value)).split())
    return stripped or normalise(value)


def tokens(value: str) -> frozenset[str]:
    # Single characters are too weak to match on.
    return frozenset(t for t in core_name(value).split() if len(t) > 1)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


class OsmIndex:
    """Name lookup over the OSM features, from strongest to weakest match."""

    def __init__(self) -> None:
        # Every candidate per name, not just the first seen. Bangladesh has
        # many places called "Mirpur 10", "Banani" and "New Market", and
        # keeping only whichever the OSM extract happened to list first put
        # Mirpur 10 more than a hundred kilometres from Dhaka -- which is
        # what made trip distances wrong.
        self.exact: dict[str, list[tuple[float, float, str]]] = defaultdict(list)
        self.core: dict[str, list[tuple[float, float, str]]] = defaultdict(list)
        self.by_token: dict[frozenset[str], list[tuple[float, float, str]]] = (
            defaultdict(list)
        )
        self._token_buckets: dict[str, list[tuple[frozenset[str], float, float, str]]] = (
            defaultdict(list)
        )

    def add(self, name: str, lat: str, lon: str, fclass: str) -> None:
        if not name or not lat or not lon:
            return
        try:
            latitude, longitude = float(lat), float(lon)
        except (TypeError, ValueError):
            return
        # Bangladesh bounding box — rejects obviously bad coordinates.
        if not (20.5 <= latitude <= 26.7 and 88.0 <= longitude <= 92.7):
            return

        normalised = normalise(name)
        if not normalised:
            return
        payload = (latitude, longitude, fclass or "")
        if payload not in self.exact[normalised]:
            self.exact[normalised].append(payload)
        if payload not in self.core[core_name(name)]:
            self.core[core_name(name)].append(payload)

        token_set = tokens(name)
        if token_set:
            if payload not in self.by_token[token_set]:
                self.by_token[token_set].append(payload)
            for token in token_set:
                self._token_buckets[token].append(
                    (token_set, latitude, longitude, fclass or "")
                )

    def candidates(self, name: str) -> tuple[list[tuple[float, float, str]], str]:
        """Every plausible coordinate for ``name``, and how it was matched.

        Returns the *whole* candidate set at the strongest tier that matched,
        so the caller can choose between same-named places using context this
        index does not have. Returns an empty list when nothing matched.

        The bracketed form is tried through every tier before the stripped
        form is tried through any of them: "Mirpur(10)" must not fall back to
        "Mirpur" while an exact "Mirpur 10" exists. Only when the specific
        name finds nothing at all does the general one get a turn -- which is
        what lets "Azimpur (Dhakeswari)" resolve as "Azimpur".
        """
        for candidate_name in _unique(name, _strip_bracket(name)):
            found, quality = self._candidates_for(candidate_name)
            if found:
                return found, quality
        return [], ""

    def _candidates_for(
        self, name: str
    ) -> tuple[list[tuple[float, float, str]], str]:
        """One name through every tier, strongest first."""
        normalised = normalise(name)
        if normalised in self.exact:
            return list(self.exact[normalised]), "exact"

        core = core_name(name)
        if core in self.core:
            return list(self.core[core]), "name"

        wanted = tokens(name)
        if not wanted:
            return [], ""
        if wanted in self.by_token:
            return list(self.by_token[wanted]), "tokens"

        # Weakest accepted match: every token of the query appears in the
        # candidate, and the candidate adds at most one extra token. That
        # allows "Mirpur 10" -> "Mirpur 10 Metro Station" but refuses
        # "Mirpur" -> "Mirpur 1" (a different place entirely).
        best_extra: int | None = None
        best: list[tuple[float, float, str]] = []
        seen: set[int] = set()
        for token in wanted:
            for candidate, lat, lon, fclass in self._token_buckets.get(token, ()):
                key = id(candidate)
                if key in seen:
                    continue
                seen.add(key)
                if not wanted.issubset(candidate):
                    continue
                extra = len(candidate - wanted)
                if extra > 1:
                    continue
                # The subset tier is the weakest, and it is where a wrong
                # answer is most likely: stripping "Bazar" from "Amin Bazar"
                # leaves "Amin", which can match a school of that name
                # kilometres away. Accept it only for features that are
                # actually transport infrastructure, where a name collision is
                # far less likely to be a different location.
                if fclass not in _TRANSPORT_FCLASS:
                    continue
                if best_extra is None or extra < best_extra:
                    best_extra, best = extra, [(lat, lon, fclass)]
                elif extra == best_extra:
                    best.append((lat, lon, fclass))
        return best, ("subset" if best else "")


# ---------------------------------------------------------------------------
# Choosing between same-named places
# ---------------------------------------------------------------------------
#
# Bangladesh has many places sharing a name. Taking whichever the OSM extract
# listed first put "Mirpur 10" 126 km from Dhaka, "Banani" 155 km and "New
# Market" 138 km away -- so every trip through them reported a wildly wrong
# distance.
#
# A place is where its route-mates are. Two passes use that:
#
#   1. Names with exactly one candidate are unambiguous. They become anchors.
#   2. An ambiguous place picks the candidate closest to the centroid of the
#      anchored places it shares a bus route with. Repeat, since each round
#      anchors more places and sharpens the next.
#
# Nothing is snapped to Dhaka. Genuinely intercity places -- Sayedpur is 248 km
# from Dhaka and correctly so -- resolve to their own routes' centre, which is
# the whole point of using the network rather than a fixed reference point.


def route_neighbours(core: Path) -> dict[str, set[str]]:
    """place_id -> the other place_ids it shares a route or service with."""
    groups: dict[str, list[str]] = defaultdict(list)

    for row in read_csv(core / "brta_route_stops.csv"):
        route, place = row.get("route_id"), row.get("place_id")
        if route and place:
            groups[f"route:{route}"].append(place)

    for row in read_csv(core / "bus_service_stops.csv"):
        service, place = row.get("service_id"), row.get("canonical_place_id")
        if service and place:
            groups[f"service:{service}"].append(place)

    neighbours: dict[str, set[str]] = defaultdict(set)
    for members in groups.values():
        unique = set(members)
        # A route with hundreds of stops says little about any one of them,
        # and the quadratic expansion is wasted work.
        if len(unique) < 2 or len(unique) > 400:
            continue
        for place in unique:
            neighbours[place].update(unique - {place})
    return neighbours


def _centroid(points: list[tuple[float, float]]) -> tuple[float, float] | None:
    if not points:
        return None
    return (
        sum(p[0] for p in points) / len(points),
        sum(p[1] for p in points) / len(points),
    )


def _distance_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    radius = 6371.0
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat = lat2 - lat1
    dlon = math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(h))


#: A stop this far from the agreed centre of its route is almost certainly a
#: name collision rather than a real hop. Generous, because CommuteBD does
#: carry genuine long-distance routes.
_MAX_NEIGHBOUR_KM = 120.0

#: How tightly the neighbours must agree before their consensus is worth
#: trusting. Above this they are spread along a long route and say nothing
#: about whether any one member is misplaced.
_CONSENSUS_SPREAD_KM = 60.0

#: Fewer neighbours than this is an opinion, not a consensus.
_MIN_NEIGHBOURS_FOR_CONSENSUS = 3


def drop_implausible(
    resolved: dict[str, tuple[float, float, str, str, bool]],
    neighbours: dict[str, set[str]],
) -> tuple[dict[str, tuple[float, float, str, str, bool]], list[str]]:
    """Remove placements the route network positively contradicts.

    Some names have exactly one candidate in the OSM extract and it is the
    wrong one -- Dhaka's Banani and New Market are simply not in there under
    those names, so the only match is a same-named place elsewhere. Choosing
    between candidates cannot fix that, because there is nothing to choose
    from, and a wrong coordinate is worse than none: a place without one still
    routes as a network node, while one pinned 150 km away corrupts every
    distance and fare passing through it.

    The test is deliberately a majority one. Asking "is this far from its
    nearest neighbour" drops a *correct* stop whose neighbours happen to be
    the misplaced ones. So a placement is only rejected when its neighbours
    agree with each other and it disagrees with all of them -- which also
    leaves genuine long-distance routes alone, since there the neighbours are
    spread out too and no consensus forms.
    """
    dropped: list[str] = []

    for place_id, value in list(resolved.items()):
        mates = [
            (resolved[other][0], resolved[other][1])
            for other in neighbours.get(place_id, ())
            if other in resolved and other != place_id
        ]
        # Too few to form an opinion. Keeping it is the conservative choice.
        if len(mates) < _MIN_NEIGHBOURS_FOR_CONSENSUS:
            continue

        centre = _centroid(mates)
        if centre is None:
            continue

        # Do the neighbours actually agree on where they are? If they are
        # scattered, this is a long route and distance proves nothing.
        spread = sorted(_distance_km(mate, centre) for mate in mates)
        median_spread = spread[len(spread) // 2]
        if median_spread > _CONSENSUS_SPREAD_KM:
            continue

        if _distance_km((value[0], value[1]), centre) > _MAX_NEIGHBOUR_KM:
            dropped.append(place_id)
            del resolved[place_id]

    return resolved, dropped


def resolve_places(
    index: "OsmIndex",
    places: list[dict[str, str]],
    neighbours: dict[str, set[str]],
    rounds: int = 4,
) -> dict[str, tuple[float, float, str, str, bool]]:
    """place_id -> (lat, lon, fclass, quality, disambiguated).

    ``disambiguated`` records whether the place had rival candidates that had
    to be chosen between, so the output can be audited.
    """
    options: dict[str, tuple[list[tuple[float, float, str]], str]] = {}
    for place in places:
        place_id = place.get("place_id")
        name = place.get("name_en") or ""
        if not place_id or not name:
            continue
        found, quality = index.candidates(name)
        if found:
            options[place_id] = (found, quality)

    resolved: dict[str, tuple[float, float, str, str, bool]] = {}

    # Pass 1 -- a single candidate is not a choice, it is a fact.
    for place_id, (found, quality) in options.items():
        if len(found) == 1:
            lat, lon, fclass = found[0]
            resolved[place_id] = (lat, lon, fclass, quality, False)

    # Pass 2 -- everything else is placed among the neighbours it travels with.
    for _ in range(rounds):
        progressed = False
        for place_id, (found, quality) in options.items():
            if place_id in resolved:
                continue
            known = [
                (resolved[other][0], resolved[other][1])
                for other in neighbours.get(place_id, ())
                if other in resolved
            ]
            centre = _centroid(known)
            if centre is None:
                continue
            lat, lon, fclass = min(
                found, key=lambda c: _distance_km((c[0], c[1]), centre)
            )
            resolved[place_id] = (lat, lon, fclass, quality, True)
            progressed = True
        if not progressed:
            break

    # Anything still unresolved has rival candidates and no anchored
    # neighbour to judge them by. Falling back to the first would reinstate
    # exactly the bug this function exists to fix, so it is left out and the
    # place stays findable by name instead.
    return resolved


def build_index(master: Path) -> OsmIndex:
    index = OsmIndex()

    stops = master / "transport" / "bus_stops_osm.csv"
    if stops.exists():
        for row in read_csv(stops):
            index.add(row.get("stop_name", ""), row.get("latitude", ""),
                      row.get("longitude", ""), "bus_stop")

    points = master / "transport" / "osm_transport_points.csv"
    if points.exists():
        for row in read_csv(points):
            index.add(row.get("name", ""), row.get("latitude", ""),
                      row.get("longitude", ""), row.get("fclass", ""))

    hubs = master / "transport" / "transport_hubs_osm.csv"
    if hubs.exists():
        for row in read_csv(hubs):
            index.add(row.get("name", ""), row.get("latitude", ""),
                      row.get("longitude", ""), row.get("transport_type", ""))

    places = master / "places" / "osm_places.csv"
    if places.exists():
        for row in read_csv(places):
            index.add(row.get("name", ""), row.get("latitude", ""),
                      row.get("longitude", ""), row.get("fclass", ""))

    key_places = master / "places" / "osm_key_places.csv"
    if key_places.exists():
        for row in read_csv(key_places):
            fclass = row.get("type", "")
            if fclass and fclass not in _USEFUL_FCLASS:
                continue
            index.add(row.get("name_en_or_local", ""), row.get("latitude", ""),
                      row.get("longitude", ""), fclass)

    return index


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--master",
        required=True,
        type=Path,
        help="path to the extracted CommuteBD_Bangladesh_Master_v1 directory",
    )
    args = parser.parse_args()

    master: Path = args.master
    if not master.exists():
        print(f"master dataset not found: {master}")
        return 1

    print(f"reading OSM features from {master} …")
    index = build_index(master)
    print(f"  indexed {len(index.exact)} distinct names")

    rows: list[dict[str, str]] = []
    stats: dict[str, int] = defaultdict(int)

    places = read_csv(CORE / "places.csv")
    neighbours = route_neighbours(CORE)
    print(f"  route neighbours known for {len(neighbours)} places")

    resolved = resolve_places(index, places, neighbours)
    resolved, dropped = drop_implausible(resolved, neighbours)
    if dropped:
        print(f"  dropped {len(dropped)} placement(s) the route network contradicts")

    for place in places:
        stats["places_total"] += 1
        hit = resolved.get(place.get("place_id", ""))
        if hit is None:
            continue
        lat, lon, fclass, quality, disambiguated = hit
        stats[f"places_{quality}"] += 1
        if disambiguated:
            stats["places_disambiguated"] += 1
        rows.append(
            {
                "node_kind": "place",
                "node_id": place["place_id"],
                "name_en": place["name_en"],
                "latitude": f"{lat:.7f}",
                "longitude": f"{lon:.7f}",
                "osm_fclass": fclass,
                "match_quality": quality,
                "source": "CommuteBD_Bangladesh_Master_v1 (OpenStreetMap)",
            }
        )

    # MRT Line 6 runs through Dhaka, so its stations are anchored to the
    # centroid of the stations that resolved unambiguously rather than being
    # left to the same first-match accident.
    metro_rows = read_csv(CORE / "metro_stations.csv")
    metro_options = {
        row["station_id"]: index.candidates(row["name_en"])
        for row in metro_rows
        if row.get("station_id") and row.get("name_en")
    }
    metro_anchor = _centroid(
        [(c[0][0], c[0][1]) for c, _ in metro_options.values() if len(c) == 1]
    )

    for station in metro_rows:
        stats["metro_total"] += 1
        found, quality = metro_options.get(station.get("station_id", ""), ([], ""))
        if not found:
            continue
        if len(found) > 1 and metro_anchor is not None:
            lat, lon, fclass = min(
                found, key=lambda c: _distance_km((c[0], c[1]), metro_anchor)
            )
            stats["metro_disambiguated"] += 1
        else:
            lat, lon, fclass = found[0]
        stats[f"metro_{quality}"] += 1
        rows.append(
            {
                "node_kind": "metro",
                "node_id": station["station_id"],
                "name_en": station["name_en"],
                "latitude": f"{lat:.7f}",
                "longitude": f"{lon:.7f}",
                "osm_fclass": fclass,
                "match_quality": quality,
                "source": "CommuteBD_Bangladesh_Master_v1 (OpenStreetMap)",
            }
        )

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / "place_coordinates.csv"
    with out.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "node_kind", "node_id", "name_en", "latitude", "longitude",
                "osm_fclass", "match_quality", "source",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    places_matched = sum(v for k, v in stats.items()
                         if k.startswith("places_") and k != "places_total")
    metro_matched = sum(v for k, v in stats.items()
                        if k.startswith("metro_") and k != "metro_total")

    print()
    print(f"wrote {out.relative_to(BACKEND)}  ({len(rows)} rows)")
    print(f"  places: {places_matched}/{stats['places_total']} "
          f"({100 * places_matched // max(stats['places_total'], 1)}%)")
    print(f"  metro : {metro_matched}/{stats['metro_total']}")
    print("  by match quality:")
    for quality in ("exact", "name", "tokens", "subset"):
        total = stats.get(f"places_{quality}", 0) + stats.get(f"metro_{quality}", 0)
        if total:
            print(f"    {quality:8} {total}")
    print()
    print("Unmatched places are not an error: the router treats a place")
    print("without coordinates as network-only. It can still be ridden")
    print("through; it just cannot anchor a walking transfer or a snap.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
