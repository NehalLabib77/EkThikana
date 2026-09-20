# Gochano Bus Seed Dataset — Data Quality Report

## What was prepared
This package turns the current CommuteBD community/reference bus-service data into a safe seed package for Gochano.

The existing stable `SVC####` IDs are preserved. This avoids breaking future `user_fare_reports.bus_service_id` references.

## Input / output counts
- Bus route variants: **156**
- Ordered bus-service stop rows: **3190**
- Canonical places: **387**
- Stops linked to a canonical place: **2518/3190 (78.9%)**
- Unlinked service-stop rows: **672**
- Alias rows requiring manual review: **130**
- Service→BRTA route-match candidates: **156**
- Verified service→BRTA matches: **0**
- OSM-assisted coordinate candidates: **42**

## Existing validation state
- Bus-service status distribution: `{'needs_validation': 156}`
- BRTA match-quality distribution: `{'low': 63, 'medium': 91, 'high': 2}`

No community route was promoted to official/verified status.

## Operators with multiple route variants
- BRTC: 9
- Alif: 4
- Trust Transport Services: 4
- Dhakar Chaka: 2
- FTCL: 2
- Jabale Noor Paribahan: 2
- Shikhor Paribahan: 2

Each variant must remain a separate `service_id`; do not collapse them by operator name.

## Safety decisions
- `bus_services_seed.csv` keeps `current_status=needs_validation`.
- `service_route_match_candidates.csv` keeps every match `verified=no`.
- OSM name/coordinate matches are suggestions only.
- Ambiguous place names are not auto-applied.
- BRTA official route/fare data remains a separate authoritative layer.
- Crowd fare reports must still pass the existing plausibility, dedupe, moderation and aggregation pipeline.

## Recommended next agent work
1. Load/preserve the two exact-schema seed CSVs.
2. Review alias candidates, especially high-similarity OSM candidates.
3. Review coordinate candidates before updating `places`.
4. Manually validate high/medium service→BRTA route matches.
5. Use verified route/stop matches to power Board / X stops / Exit UI.
6. Continue collecting real user fares with `bus_service_id`.

## Schema note for future bus-specific crowd fare suggestions
`user_fare_reports` already records `bus_service_id`, but `crowd_fare_aggregates` does not.
To show per-bus suggestions (for example Raida vs BRTC on the same origin/destination pair), the aggregation layer should eventually add nullable `bus_service_id` and group on it.

An optional, non-executed migration file is included for the coding agent.

## Coverage note
The 156-service seed is primarily Dhaka city/community route data. Do not label it as complete Bangladesh bus coverage.
Nationwide bus coverage should grow from additional regional seed data and validated user reports.

## Files
- `bus_services_seed.csv`
- `bus_service_stops_seed.csv`
- `bus_service_routes_seed.csv`
- `stop_alias_candidates.csv`
- `service_route_match_candidates.csv`
- `place_coordinate_candidates.csv`
- `sources_reference.csv`
- `import_bus_seed.sql`
- `OPTIONAL_agent_migration_bus_specific_crowd_fare.sql`
