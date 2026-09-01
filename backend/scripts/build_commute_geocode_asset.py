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
    text = unicodedata.normalize("NFKC", value or "").lower().strip()
    text = _BRACKET.sub(" ", text)
    text = re.sub(r"[^a-z0-9ঀ-৿]+", " ", text)
    return " ".join(text.split())


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
        self.exact: dict[str, tuple[float, float, str]] = {}
        self.core: dict[str, tuple[float, float, str]] = {}
        self.by_token: dict[frozenset[str], tuple[float, float, str]] = {}
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
        self.exact.setdefault(normalised, payload)
        self.core.setdefault(core_name(name), payload)

        token_set = tokens(name)
        if token_set:
            self.by_token.setdefault(token_set, payload)
            for token in token_set:
                self._token_buckets[token].append(
                    (token_set, latitude, longitude, fclass or "")
                )

    def lookup(self, name: str) -> tuple[float, float, str, str] | None:
        """Returns (lat, lon, fclass, match_quality) or None."""
        normalised = normalise(name)
        if normalised in self.exact:
            lat, lon, fclass = self.exact[normalised]
            return lat, lon, fclass, "exact"

        core = core_name(name)
        if core in self.core:
            lat, lon, fclass = self.core[core]
            return lat, lon, fclass, "name"

        wanted = tokens(name)
        if not wanted:
            return None
        if wanted in self.by_token:
            lat, lon, fclass = self.by_token[wanted]
            return lat, lon, fclass, "tokens"

        # Weakest accepted match: every token of the query appears in the
        # candidate, and the candidate adds at most one extra token. That
        # allows "Mirpur 10" -> "Mirpur 10 Metro Station" but refuses
        # "Mirpur" -> "Mirpur 1" (a different place entirely).
        best: tuple[int, float, float, str] | None = None
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
                if best is None or extra < best[0]:
                    best = (extra, lat, lon, fclass)
        if best is not None:
            # The subset tier is the weakest, and it is where a wrong answer
            # is most likely: stripping "Bazar" from "Amin Bazar" leaves
            # "Amin", which can match a school of that name kilometres away.
            # Accept it only for features that are actually transport
            # infrastructure, where a name collision is far less likely to be
            # a different location.
            if best[3] not in _TRANSPORT_FCLASS:
                return None
            return best[1], best[2], best[3], "subset"
        return None


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

    for place in read_csv(CORE / "places.csv"):
        hit = index.lookup(place["name_en"])
        stats["places_total"] += 1
        if hit is None:
            continue
        lat, lon, fclass, quality = hit
        stats[f"places_{quality}"] += 1
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

    for station in read_csv(CORE / "metro_stations.csv"):
        hit = index.lookup(station["name_en"])
        stats["metro_total"] += 1
        if hit is None:
            continue
        lat, lon, fclass, quality = hit
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
