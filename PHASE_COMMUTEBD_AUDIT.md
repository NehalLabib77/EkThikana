# PHASE_COMMUTEBD_AUDIT — Verification-Only Audit

**Constraint:** No code was changed, no refactor was made, no architectural decision was altered. This document only describes what is currently true and where the **future implementation work** lives once we leave audit mode.

**Scope:** All CommuteBD files between `flutter_app/lib/screens/life/commute_bd_screen.dart`, `lib/services/{api_service.dart, financial_service.dart}`, the entire `backend/app/services/commute/` package, `backend/app/routers/commute.py`, `backend/app/services/storage_service.py` (consumed by ML), `backend/ml/train_fare_models.py`, `backend/app/main.py`, the CSV dataset under `backend/data/commutebd/core_dataset/csv/`, and `app/schemas.py` (`CommuteRouteRequest`, `CommuteFareReportRequest`, `CommutePlaceInput`, `CommuteRoutesRequest`).

---

## PHASE 1 — Complete Flow Trace

| Step | Where it runs | File:Function | What it does |
| --- | --- | --- | --- |
| 1. Mount screen | Flutter | `commute_bd_screen.dart:CommuteBDScreen` | Stateful screen with `MapController`, origin/destination markers, polyline overlay. |
| 2. Locate user | Device | `commute_bd_screen.dart:_locate()` | `Geolocator.isLocationServiceEnabled` → `checkPermission` / `requestPermission` → `getCurrentPosition(LocationAccuracy.high, 15s)`. Sets `origin` LatLng and label "Current location". |
| 3. Pick destination | UI modal | `commute_bd_screen.dart:_searchDestination()` + `_PlaceSearchSheet` | Opens bottom sheet with debounced (450 ms) text field → calls `ApiService.commuteSearch`. Shows `displayName` from Nominatim; user taps → `LatLng` set as destination. |
| 4. Backend route call | HTTP (auth-gated) | `routers/commute.py:route_trip` (POST `/api/commute/route`) | Pydantic-validated `CommuteRouteRequest` → builds `Coordinate(origin_lat, origin_lon)` + `Coordinate(dest_lat, dest_lon)`. |
| 5. Real map routing | External | `services/commute/routing.py:OsrmNominatimProvider.route` | Calls `${OSRM_BASE_URL}/route/v1/driving/lon,lat;lon,lat?overview=full&geometries=geojson`; extracts `distance/1000`, `duration/60`, full geojson polyline; provider tag `"OSRM"`, `liveTraffic=false`. |
| 6. Real geocoding | External | `routing.py:OsrmNominatimProvider.search` | Calls `${NOMINATIM_BASE_URL}/search?q=…&countrycodes=bd&format=jsonv2&limit=8`. Returns display name + lat/lon. |
| 7. Multi-mode fare | Service | `services/commute/fare_engine.py:FareEngine.options` | One orchestrator per request; fans out to bus / metro / cng / rickshaw / walk services, ranks by `_confidence_score` weighted blend. Returns up to ~7 candidate options with `badges`. |
| 8. Bus pricing | Service | `services/commute/data_repository.py:official_bus_fares` (+ `official_bus_one_transfer` if direct yields empty) | Reads `brta_fare_segments` directly; falls back to per-route `brta_routes.fare_per_km_tk` × `cumulative_distance_km` between `brta_route_stops` for the same route; tag `official_rule_calculation`, confidence `Authoritative`. |
| 9. Metro pricing | Service | `data_repository.py:metro_fare` | Hard gate on `operational_status == "in_service"`, `live_routing_enabled == "yes"`, `live_usable == "yes"`. Joins `metro_stations` + `metro_fares`. Confidence `Authoritative`. |
| 10. CNG / Rickshaw | Service | `fare_engine.py:CNGFareService.estimate` + `RickshawFareService.estimate` | Reads `fare_rules.csv` where `mode == "cng_autorickshaw"` (HISTORICAL legal meter rule). Layered with `crowd.aggregate` (Supabase `user_fare_reports`) and finally ML (gated). |
| 11. Walk option | Service | `fare_engine.py` | Added when `distance_km ≤ 2.5`; uses `distance/4.5*60` minutes; fare 0; confidence `High`. |
| 12. Display options | UI | `commute_bd_screen.dart:_optionCard` | Mode → emoji, badges (Recommended / Cheapest / Fastest), `৳low–high`, confidence + fareType subtitle. |
| 13. Tap → fare detail modal | UI | `commute_bd_screen.dart:_fareDetails` | Big fare number, fare type / source / confidence, warning, "actual fare" input, "Also submit fare report for moderation" checkbox. |
| 14. Save as expense | Firestore | `FinancialService.recordCommuteTrip` | Writes `commute_trips/<id>` AND mirror `financial_transactions/commute_<id>` in a batch (`type=expense`, `category=<mode>`, `title="$origin → $destination"`). |
| 15. Crowd fare report (optional) | HTTP POST | `routers/commute.py:report_fare` (`/api/commute/fare-report`) | Pydantic-validated `CommuteFareReportRequest`; dedupe key = `sha256(uid|mode|rounded_origin|rounded_dest|fare|YYYYMMddHHMM)`; inserts to Supabase `user_fare_reports` with `moderation_status="pending"`. **This row never becomes a published truth** until a moderator approves it. |
| 16. ML future gate | Storage/Supabase | `ml_fare.py:enabled_for` | Reads `user_fare_reports` count via service-role Supabase; only enabled when both `commute_ml_min_total_reports` and `commute_ml_min_mode_reports` thresholds pass; loads `models/commute/<mode>_quantiles.joblib` via `storage_service.download_bytes`. |

**End-to-end verdict:** Every step is implemented; nothing in the chain is a stub. The only layers that conditionally no-op are ML (when report count < threshold or `joblib` missing in storage) and crowd statistics (when Supabase not configured or row count < 3). Both **fail gracefully** into the legal-rule / dataset fallback instead of fabricating data.

---

## PHASE 2 — Map & Location Contract

| Concern | Source of truth | Status |
| --- | --- | --- |
| Widget | `flutter_map` `FlutterMap` + `TileLayer` (OSM public tiles) inside screen `commute_bd_screen.dart` | ✅ Confirmed — User-Agent `com.ekthikana.ekthikana`, attribution rendered in overlay. |
| Controller | `flutter_map.MapController` (`mapController`) held by screen state; used in `_locate` (`move`), `_buildRoute` (`fitCamera` with bounds + 40 px padding) | ✅ Confirmed |
| Current location | `geolocator` package: `isLocationServiceEnabled` → `checkPermission` / `requestPermission` → `getCurrentPosition(LocationAccuracy.high, 15s timeLimit)` | ✅ Confirmed |
| Permission flow | Two-state reject handling: `denied` triggers re-request; `denied` / `deniedForever` after re-request → user-facing error in Bangla | ✅ Confirmed |
| Destination selection | Modal `_PlaceSearchSheet` (autocomplete) → `ApiService.commuteSearch` (debounced 450 ms) → user picks `displayName` → `LatLng` set as destination | ✅ Confirmed |
| Marker handling | `MarkerLayer` with origin (blue `my_location`) and destination (red `location_on`), sizes 48 / 52 | ✅ Confirmed |
| Route polyline | Backend returns `polyline: [{lat, lon}, …]` (already flipped to lat/lon, not OSRM lon/lat). Mapped to `LatLng` and rendered with `PolylineLayer` (stroke 5, color `#1976D2`) | ✅ Confirmed |
| Map re-center | On locate → `mapController.move(point, 14)`; on route → `fitCamera` to bounds; "Recent" button in app bar re-uses current origin | ✅ Confirmed |
| Tile provider | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` (configurable via `routing_user_agent` setting) | ✅ Confirmed |
| Geocoder integration | `OsrmNominatimProvider.search` → Nominatim (`OSM`) with `countrycodes=bd`, `Accept-Language: en,bn;q=0.8` | ✅ Confirmed |

---

## PHASE 3 — Fare-Engine Contract

| Mode | Code path | Inputs | Outputs (keys) | Confidence / Source |
| --- | --- | --- | --- | --- |
| Bus (direct) | `BusFareService.lookup` → `data_repository.official_bus_fares(origin, destination)` | place names | `routeId, fare, distanceKm, fromName, toName, source, fareType, confidence` | `fareType="official"`, `confidence="Authoritative"` |
| Bus (one transfer) | `BusFareService.one_transfer` → `data_repository.official_bus_one_transfer` | place names, limit=3 | `routeIds[2], transferPlaceId, transferName, fare, source, fareType, confidence, transfers` | `fareType="official"`, `confidence="Authoritative"`, `transfers=1` |
| Metro | `MetroFareService.lookup` → `data_repository.metro_fare` | place names | `lineId, fare, passFare, source, fareType, confidence` (only when stations both `operational_status=in_service`, `live_routing_enabled=yes`, `live_usable=yes`) | `fareType="official"`, `confidence="Authoritative"` |
| CNG (legal rule) | `CNGFareService.estimate` → `data_repository.cng_rule` first row | place names, `distance_km`, optional `waiting_minutes` | `low=median=high=ceil(base + max(0, km - included) × perKm)`, `fareType="historical"`, `confidence="Low"`, with warning string naming `effective_from` | Dataset-driven (see PHASE 4) |
| CNG (crowd) | `CrowdFareRepository.aggregate(mode="cng")` | last 180 days approved `user_fare_reports` filtered to origin+dest substring | `sampleCount, q25, median, q75, confidence, fareType, source` | `fareType="crowdsourced"`; `confidence` mapped `3–7→Low`, `8–19→Medium`, `≥20→High` |
| CNG (ML) | `MLFarePredictionService.predict(mode="cng")` (gated) | `distance_km`, `trip_minutes`, default `traffic="unknown"`, `hour=12`, `weekday=0` | `low, median, high, fareType="estimated", source="Verified-report quantile ML model", confidence="Medium", model="GradientBoostingRegressor quantile"` | Only if `enabled_for("cng")` true + `joblib` bundle in storage |
| Rickshaw | Rickshaw chain: crowd → ML → `data_repository.rickshaw_distance_fallback` | `distance_km`, place names | Same shape as CNG crowd/ML OR `{low, median, high, source, fareType="unverified", confidence="Low", warning="Low-confidence fallback from supplied synthetic/user-assumption rows."}` | last resort only |
| Walk | inline in `FareEngine.options` if `distance_km ≤ 2.5` | `distance_km`, `driving_minutes` | `{minutes=max(1, distance/4.5*60), fareLow=fareHigh=0, walkingKm, fareType="none", source="Walking estimate", confidence="High"}` | Hard rule |
| **Badges** | `FareEngine._rank` | all options | `Recommended` (min `_score` blend of time 38%, fare 32%, walk 10%, transfer 8%, confidence 12%), `Cheapest` (min `fareHigh`), `Fastest` (min `minutes`) | Score blended in `fare_engine.py:_rank` |

**Transport option dictionary (Flutter-visible keys):**

```
{
  "mode": "bus" | "metro" | "cng" | "rickshaw" | "walk",
  "label": "Bus" | "Metro" | "CNG" | "Rickshaw" | "Walk",
  "minutes": int,
  "fareLow": int,
  "fareHigh": int,
  "fareType": "official" | "official_rule_calculation" | "crowdsourced"
              | "estimated" | "historical" | "unverified" | "none",
  "source": string,                 # human-readable source label
  "confidence": "Authoritative" | "High" | "Medium" | "Low",
  "warning": optional string,       # only when low-confidence / historical
  "badges": ["Recommended" | "Cheapest" | "Fastest"],   # 1..3 entries
  "routeId": string | null,
  "transfers": 0 | 1,
  "walkingKm": float | null
}
```

---

## PHASE 4 — Rickshaw/Auto Rule (user's specific question)

**The "1 km = 17 tk" rule is NOT hardcoded.** It lives entirely in the dataset:

```
fare_rules.csv columns:
fare_rule_id, mode, coverage, effective_from, base_or_minimum_fare_tk,
included_distance_km, per_km_tk, waiting_rule, other_rule,
production_status, source_id
```

`data_repository.cng_rule()` selects the row where `mode == "cng_autorickshaw"`. The 17 tk/km (or whatever value is current) is the `per_km_tk` field. Reading list:

| Step | Action |
| --- | --- |
| Read | First row where `mode == cng_autorickshaw`. |
| Compute | `meter = ceil(base + max(0, km - included) * per_km)`. |
| Return | `low = median = high = meter`. |
| Tag | `fareType = "historical"`, `confidence = "Low"`, plus `warning = "Historical meter rule effective <effectiveFrom>; verify current legal rate before relying on it."`. |

In `FareEngine.options`, the historical row is only kept if neither crowd nor ML produced an estimate. The user's UI also explicitly surfaces the warning message so the label can never silently look authoritative.

A separate `rickshaw_distance_fallback` (read from `rickshaw_auto_estimated_fares.csv`) **is a low-confidence last resort** with `fareType = "unverified"`, `confidence = "Low"`, and the warning text "Low-confidence fallback from supplied synthetic/user-assumption rows." Rickshaw pricing runs in this order:

1. **`CrowdFareRepository.aggregate("rickshaw")`** — if Supabase configured **AND** at least 3 approved reports exist for the origin/destination substring pair.
2. **`MLFarePredictionService.predict("rickshaw")`** — if the crowd layer is empty AND `enabled_for("rickshaw")` returns true (per-mode report threshold) AND the joblib bundle can be downloaded.
3. **`data_repository.rickshaw_distance_fallback(distance_km)`** — picks the nearest row in `rickshaw_auto_estimated_fares.csv` by `distance_km` and synthesizes `{low, median, high} = {0.85×base rounded to 5 tk, base rounded to 5 tk, 1.20×base rounded to 5 tk}`.

**Conclusion:** any future tweak to "1 km = 17 tk" is a **single CSV cell edit** in `fare_rules.csv` (or a new row, picked first by `cng_rule`). No code change required.

---

## PHASE 5 — User Survey Contract

| Concern | File:Function / Supabase column | Status |
| --- | --- | --- |
| Survey trigger UI | `commute_bd_screen.dart:_fareDetails` AlertDialog from any option card tap | ✅ Confirmed |
| Modal fields | Mode (implicit from option), `label`, `fareType`, `source`, `confidence`, optional `warning` (rendered in warning color), **Actual Fare** numeric input (pre-filled if `fareLow == fareHigh`), **Also submit fare report for moderation** checkbox | ✅ Confirmed |
| Save as expense | `FinancialService.recordCommuteTrip` → batch write: `commute_trips/<id>` + mirror `financial_transactions/commute_<id>` (Firestore, not Supabase) | ✅ Confirmed |
| Crowd report endpoint | `POST /api/commute/fare-report` (router `report_fare`); schema `CommuteFareReportRequest` enforces `transport_mode ∈ {bus, metro, cng, rickshaw, bike, car, other}`, `fare_paid_tk 1..10000`, optional `trip_minutes 1..720`, optional `route_distance_km 0..300`, `traffic_level ∈ {unknown, light, normal, heavy}`, `payment_type ∈ {cash, card, mobile, pass, other}` | ✅ Confirmed |
| Dedupe key | `sha256(uid|mode|rounded_origin|rounded_dest|fare|minute_bucket)`; rounded = `lat,lon` to 4 decimals else `text.lower()`. Stored in column `dedupe_key` of Supabase table `user_fare_reports`; duplicate key yields 409. | ✅ Confirmed |
| Storage of free text | `origin_text`, `destination_text`, `bus_service_id`, `bus_name_user_entered`, `route_id_if_known`, `payment_type`, `traffic_level` are all stored raw (length-bounded in schema). | ✅ Confirmed |
| Privacy | `user_id_hash = sha256(uid)` is stored; raw uid never leaves the backend batch. | ✅ Confirmed |
| Moderation gating | New rows are inserted with `moderation_status = "pending"`. The `CrowdFareRepository.approved_fares` query only consumes rows with `moderation_status = "approved"`. | ✅ Confirmed |
| Pre-flight success UX | `showSuccess(context, 'Actual commute fare saved to Expense Tracker.')` | ✅ Confirmed |
| Trip-amount validation | `actualFare ≤ 0` raises `Exception('Actual fare must be greater than zero.')` in both Flutter and backend (the latter refuses `fare_paid_tk ≤ 0`). | ✅ Confirmed |

**Sub-flow:** Trip expense is **always** saved (Firestore). The crowd fare report (Supabase) is **only** saved when the user ticks the checkbox. Each storage layer is optional and never blocks the other. This means a user can record an expense in offline mode, then submit moderation crowd data later.

---

## PHASE 6 — Dataset Readiness

There are **19 CSV files** in `backend/data/commutebd/core_dataset/csv/`. The expected 11 datasets are all present. Below is the full readiness table for those + the 8 supporting CSVs we discovered.

| Dataset | Loaded? | Used? | Purpose | Missing fields | Recommendation |
| --- | --- | --- | --- | --- | --- |
| `places.csv` | yes | yes — `search_local_places`, `resolve_place_id`, `_resolve_metro_station` (name→id), `crowd.aggregate` (substring), `service._resolve_input` | Master place index | `latitude` / `longitude` often empty (status `"pending"`) | Continue relying on Nominatim to fill geocoding gaps. The repository already does this automatically in `service._resolve_input`. |
| `brta_routes.csv` | yes | yes — `_route_distance_fare` filters by `live_use ∈ {yes,true,1}` and reads `fare_per_km_tk`, `minimum_fare_tk` | Per-route rule | `live_use` left blank in stale rows drops the route | Add a CI check that `fare_per_km_tk` and `minimum_fare_tk` are numeric where `live_use=yes`. |
| `brta_route_stops.csv` | yes | yes — `_route_distance_fare`, `official_bus_route_distance_fares`, `official_bus_one_transfer` | Stop list with `cumulative_distance_km` | `segment_distance_from_previous_km` not currently read | Already accurate enough; `segment_distance_from_previous_km` is informational. |
| `brta_fare_segments.csv` | yes | yes — `official_bus_fares`, `official_bus_one_transfer` (O(1) `fare_index`) | Precomputed per-segment fares | The `fare_index` only kicks in when both legs have direct segments | Optionally seed **all-pairs** segment rows so the fall-through path doesn't pop up as often. |
| `fare_rules.csv` | yes | yes — `cng_rule` | Legal meter rule | `waiting_rule` is read but **never applied** (engine chooses not to invent numbers) | Fill `waiting_rule` with a machine-readable formula if/when one is needed. |
| `metro_stations.csv` | yes | yes — `metro_fare`, `_resolve_metro_station` | Station index with operational flags | `geocode_status` is informational only | None. |
| `metro_fares.csv` | yes | yes — `metro_fare` | Pairwise fare matrix | `live_usable` flag required (data must mark each pair) | Audit every pair to ensure both directions have `live_usable=yes`. |
| `bus_services.csv` | yes | **NOT** used in production fare path (only referenced through `supabase_repository.bus_route_via_services` for transit exploration) | Real-world services list | `image_url`, `time_text` are free text | Either wire this into a planned "services list" route or leave as future display data. The current code path does not depend on it. |
| `bus_service_stops.csv` | yes | **NOT** used directly in the fare engine | Stop sequences per service | `canonical_place_id` is the join key | Use only after `supabase_repository.bus_route_via_services` is promoted to a primary routing fallback. |
| `service_route_matches.csv` | yes | **NOT** used in the fare engine (only Supabase repository if extended) | Service ↔ BRTA route match table | `verified` column is `true/false` per row | Useful for ranking transit candidates but currently dormant. |
| `rickshaw_auto_estimated_fares.csv` | yes | yes — `rickshaw_distance_fallback` | Last-resort rickshaw/auto range | `calculation`, `fare_type` are documentation, not enforced | Will stay low-confidence by design; nothing to fix. |
| `brta_graph_edges.csv` | yes (auto-loaded by directory scan in future scripts) | ❌ **NOT** consumed by any code path we audited | Could feed a future real-network pathfinding | None | Park for later routing-graph research — none of the production logic depends on it. |
| `crowd_fare_aggregate_template.csv` | yes | ❌ used only as an export template, not as input | Snapshot export of `CrowdFareRepository.aggregate` | None | Keep as ops artifact. |
| `data_dictionary.csv` | yes | documentation only | Data definitions | None | Reference for content authors. |
| `geocoding_queue.csv` | yes | ❌ no consumer | Records pending geocoding work | None | Becomes the operational to-do once geocoder is rate-limited. |
| `sources.csv` | yes | documentation only | Provenance per row | None | Reference for content authors. |
| `stop_aliases.csv` | yes | ❌ no consumer | Alternate names for stops | None | Hook to `resolve_place_id` as another normalization step in the future. |
| `transit_network_plan.csv` | yes | ❌ no consumer | High-level network plan | None | Reference only. |
| `user_fare_reports_template.csv` | yes | documentation only | Schema of the submitted reports | None | Reference for content authors. |

**Effective mapping (production paths):**

- **Bus** ← `brta_fare_segments` (preferred), `brta_routes × brta_route_stops` (fallback rule)
- **Metro** ← `metro_fares × metro_stations`
- **CNG** ← `fare_rules.csv` + `crowd.aggregate` + ML
- **Rickshaw** ← `crowd.aggregate` + ML + `rickshaw_auto_estimated_fares.csv`
- **Walking** ← inline `distance/4.5×60`

**Datasets not contributing to live answer (yet):** `bus_services`, `bus_service_stops`, `service_route_matches`, `stop_aliases`, `brta_graph_edges`, `transit_network_plan`, `geocoding_queue`. These are intentionally **not in the critical path**, which is correct for current scope.

**Note about schema drift in `ml_fare.py`:** the model expects an ML artifact on **storage** under `models/commute/<mode>_quantiles.joblib` plus metadata `<mode>_metrics.json`. This artifact is **not** a CSV — it lives in Supabase Storage (or an equivalent object store) and is only loaded when the gate passes.

---

## PHASE 7 — ML Preparation Check

### Training pipeline (`backend/ml/train_fare_models.py`)

```
FEATURES = [
    "distance_km",
    "trip_minutes",
    "traffic_level_encoded",
    "hour",
    "weekday",
]
```

Three quantile regressors are fit on **`moderation_status == "approved"`** AND **`transport_mode == <mode>`** rows:

| Stage | What it does |
| --- | --- |
| `clean()` | Drops synthetic / duplicate rows; Coerces numeric range (`fare_paid_tk ∈ [1, 10000]`, `distance_km ∈ [0.05, 100]`, `trip_minutes ∈ [1, 720]`); Derives an IQR outlier filter on `fare / km` (`±2.5 × IQR`); Maps `created_at` → UTC `hour`, `weekday`; Encodes `traffic_level` (`unknown→0, light→1, normal→2, heavy→3`); Sorts chronologically and drops nulls. |
| `train()` | Chronological 80/20 split; trains q25/q50/q75 with `GradientBoostingRegressor(loss="quantile", n_estimators=180, max_depth=3, learning_rate=0.04)`; reports `MAE`, `RMSE`, `MedianAE`, `R2`. |
| `main()` | Refuses to train below `len(data) < 150` approved real `<mode>` rows; writes `<mode>_quantiles.joblib` + `<mode>_metrics.json` under `ml/artifacts/`. |

### Inference guardrails (`backend/app/services/commute/ml_fare.py`)

| Stage | Behaviour |
| --- | --- |
| `enabled_for(mode)` | Returns `False` unless both `total approved reports ≥ commute_ml_min_total_reports` AND `per-mode approved reports ≥ commute_ml_min_mode_reports`. Both come from settings (`get_settings()`). |
| `_load(mode)` | Downloads `models/commute/<mode>_quantiles.joblib` via `storage_service.download_bytes`; in-memory cache; returns `None` on any exception, **never** raises. |
| `predict(...)` | Builds a numeric row aligned to the saved feature order; rounds q25 ≤ median ≤ q75, snaps each to nearest 5 tk (floor 5); returns `{low, median, high, fareType="estimated", source, confidence="Medium", model}`. |

### Feature-mapping audit vs. the user's required feature list

| Required feature | Captured? | Where |
| --- | --- | --- |
| `distance_km` | ✅ | `route_distance_km` or fallback `distance_km` in cleaned DataFrame; row in `predict()` defaults to `max(0.05, float(distance_km))`. |
| `transport_type` | ✅ (implicit) | Per-mode artifact chosen at predict time. |
| `area` | ⚠️ Partial | **Not** explicitly captured; `origin_text` / `destination_text` are kept in raw reports and could be hashed into a feature (not yet wired in `train_fare_models.py`). |
| `time_of_day` | ✅ | `hour` derived from `created_at` UTC. |
| `day` | ✅ | `weekday` derived from `created_at` UTC. |
| `traffic_level` | ✅ | `traffic_level` literal (`unknown/light/normal/heavy`) → `traffic_level_encoded`. |
| `estimated_fare` | ⚠️ Not in training | Engine-reported `fareLow/fareHigh` is **not** fed back into the trainer. |
| `actual_fare` | ✅ (label) | `fare_paid_tk`. |

**Recommendation:** add `area` and `estimated_fare`-derived features **later**, after enough approved reports exist; currently the contract is already strong enough to start training rickshaw/cng the moment we have ≥ 150 approved real reports.

---

## PHASE 8 — Contract Table (GREEN / YELLOW / RED)

| Layer | File | Function | Input | Output | Status |
| --- | --- | --- | --- | --- | --- |
| Location | `flutter_app/lib/screens/life/commute_bd_screen.dart` | `_locate` | (none) | `LatLng origin` or `locationError` | 🟢 GREEN |
| Destination picker | `commute_bd_screen.dart` | `_searchDestination` + `_PlaceSearchSheet.search` | text query | `_PlaceResult` selected | 🟢 GREEN |
| HTTP client | `flutter_app/lib/services/api_service.dart` | `commuteRoute`, `commuteSearch`, `reportCommuteFare` | place coords/names | route JSON / geocoded list / accepted report | 🟢 GREEN (uses auth header) |
| Auth gating | `backend/app/routers/commute.py` | `search_places`, `route_trip`, `fare_report` | `Depends(get_current_user)` | gated | 🟢 GREEN |
| Geocoder | `routing.py` | `OsrmNominatimProvider.search` | string | list of `{displayName, lat, lon, type}` | 🟢 GREEN (Nominatim public; production note in docstring about SLA) |
| Router | `routing.py` | `OsrmNominatimProvider.route` | coords | `{distanceKm, durationMinutes, polyline, provider="OSRM", liveTraffic=false}` | 🟢 GREEN |
| Repository | `data_repository.py` | `get_commute_repository` (singleton via `lru_cache`) | filesystem | reads 11 CSVs | 🟢 GREEN |
| Bus direct | `data_repository.py` | `official_bus_fares` | origin, destination place names | list of `{routeId, fare, distanceKm, ...}` | 🟢 GREEN |
| Bus one-transfer | `data_repository.py` | `official_bus_one_transfer` | origin, destination, limit | list of `{routeIds, transferPlaceId, transferName, fare, ...}` | 🟢 GREEN |
| Metro | `data_repository.py` | `metro_fare` | origin, destination station names | `{lineId, fare, passFare, ...}` or `None` | 🟢 GREEN |
| CNG legal rule | `data_repository.py` | `cng_rule` | dataset | `{baseFare, includedDistanceKm, perKm, waitingRule, effectiveFrom, ...}` | 🟢 GREEN (waiting rule intentionally unused) |
| Rickshaw/auto fallback | `data_repository.py` | `rickshaw_distance_fallback` | distance_km | `{low, median, high, source, fareType="unverified", confidence="Low", warning="..."}` | 🟢 GREEN by design |
| Crowd layer | `services/commute/crowd.py` | `CrowdFareRepository.aggregate` | mode, origin_text, destination_text | `{sampleCount, q25, median, q75, confidence, fareType="crowdsourced", source}` or `None` | 🟢 GREEN (returns `None` if Supabase not configured) |
| Fare orchestrator | `fare_engine.py` | `FareEngine.options` | origin_name, destination_name, distance_km, driving_minutes | ranked list of 5–8 options, each with `badges` | 🟢 GREEN |
| Ranking | `fare_engine.py` | `FareEngine._rank` + `_confidence_score` | options | adds `badges`, sorts by recommended | 🟡 YELLOW (deterministic, but new modes will need scope checks) |
| ML gate | `ml_fare.py` | `enabled_for` (mode) | settings + Supabase counts | `bool` | 🟢 GREEN |
| ML inference | `ml_fare.py` | `predict` | distance_km, trip_minutes, hour, weekday, traffic_level | `{low, median, high, fareType="estimated", ...}` or `None` | 🟢 GREEN |
| ML training | `backend/ml/train_fare_models.py` | `clean` → `train` → `main` | approved reports CSV | joblib bundle + metrics | 🟢 GREEN (CLI; refuses < 150 rows) |
| Expense mirror | `flutter_app/lib/services/financial_service.dart` | `recordCommuteTrip` | origin, destination, mode, distanceKm, actualFare, date | batch write to Firestore | 🟢 GREEN |
| Crowd report ingest | `routers/commute.py` | `report_fare` | `CommuteFareReportRequest` | accepted + `reportId` / 409 dedupe / 503 storage | 🟢 GREEN |
| Modal survey | `commute_bd_screen.dart` | `_fareDetails` | option | user-entered actual fare + flag | 🟢 GREEN |
| Dedupe key | `routers/commute.py` | `report_fare` | uid, mode, origin, dest, fare, minute_bucket | hash | 🟢 GREEN |
| Search (Firestore + geo) | `commute_bd_screen.dart` | `_PlaceSearchSheet.search` | text | `_PlaceResult` list | 🟢 GREEN |
| Disclaimer | backend response | (string template) | n/a | returned to UI | 🟢 GREEN |
| Polyline transform | `commute_bd_screen.dart` | `_buildRoute` | `result['polyline']` | `List<LatLng>` | 🟢 GREEN |
| Cancellation cases | `route_trip` and `report_fare` | (error handlers) | various | 404/409/422/500 returned as `{"detail": "..."}` | 🟢 GREEN |

No RED items. Two deliberate YELLOW design choices: ranking weights in `_rank` are **opinionated** constants; the `waiting_rule` field in `fare_rules.csv` is intentionally not applied (engine would rather be silent than invent a number).

---

## Untouchable Constraints During Future Implementation

1. **Map architecture:** `flutter_map` (OSM tiles), `geolocator` for current location — **do not switch** to Google/Mapbox without a separate cost-and-keys discussion. The `OsrmNominatimProvider` is the only allowed default; configurable via `ROUTING_PROVIDER=osrm`.
2. **Fare computation logic:** the eight code paths in `data_repository.py` are the single source of truth. Any "1 km = 17 tk" rule must originate as a `fare_rules.csv` row, not as a Python literal.
3. **Database schema:** `user_fare_reports` columns, the `dedupe_key`, and the four-week `crowd_fare_reports` window (180 days default) must remain unchanged.
4. **Survey structure:** `_fareDetails` modal must keep the three feedback fields (actual fare, moderation toggle, post-submission status) and the post-trip success message.
5. **Auth flow:** all `/api/commute/*` writes are `Depends(get_current_user)`; the crowd report endpoint hashes the uid before persisting it (`user_id_hash`).

---

## Files Safe to Modify for Phase-2 Implementation

| File | What you may add |
| --- | --- |
| `backend/data/commutebd/core_dataset/csv/*.csv` | New rows, fixed values, second `cng_autorickshaw` rows with newer `effective_from`, `live_use=yes`, etc. |
| `backend/ml/train_fare_models.py` | Additional features (`area`, `estimated_fare`-derived), richer IQR bounds. |
| `backend/app/services/commute/ml_fare.py` | Cache TTL, alternative modes, telemetry. |
| `backend/app/services/commute/crowd.py` | Origin/destination vector retrieval (e.g., trip-pair clusters). |
| `flutter_app/lib/screens/life/commute_bd_screen.dart` | Empty-state copy, additional badges, longer disclaimer. **NOT** allowed to swap provider. |
| `flutter_app/lib/services/financial_service.dart` | Add derived columns to `commute_trips` doc (use `set(..., SetOptions(merge=true))`). |
| `flutter_app/lib/services/api_service.dart` | Add retry/backoff for transient errors only. |

## Files to Treat as Untouched

| File | Why |
| --- | --- |
| `backend/app/main.py` | Modifying app-wide middleware would cascade beyond commute. |
| `backend/app/core/auth.py`, `backend/app/core/config.py` | Auth/settings backbone — env vars only. |
| `backend/app/routers/commute.py` | Public API contract; only additive changes allowed. |
| `backend/app/services/commute/routing.py` | Real provider integration. |
| `backend/app/services/commute/data_repository.py` | Single-source-of-truth dataset adapter. |
| `backend/app/services/commute/supabase_repository.py` | Supabase adapter. |

---

## First Datasets to Connect and Recommended Implementation Order

1. **Crowd report drain** (`user_fare_reports` writes now route to Supabase). Verify end-to-end that the moderation status transitions into `approved`. (This is what unlocks PHASE 7 ML.)
2. **ML gate thresholds** in `Settings`: pick conservative defaults like `commute_ml_min_total_reports=300`, `commute_ml_min_mode_reports=150`. Wire to env vars.
3. **Train rickshaw** baseline: collect the first 150 approved rickshaw rows, run `train_fare_models.py --mode rickshaw`, publish `rickshaw_quantiles.joblib`.
4. **Train CNG**: same flow, but enrich the dataset using `route_id_if_known` if available.
5. **Promote bus_services / service_route_matches** as the next fare-engine extension (when we want to surface matched real-world operators). This is **after** steps 1–4 because it depends on having a richer reporting model.
6. **Geocode-queue automation** (`geocoding_queue.csv`): build a background worker that fills missing `places.latitude/longitude` via Nominatim one batch at a time, respecting the `User-Agent` policy.
7. **Stop-alias fusion**: hook `stop_aliases.csv` into `resolve_place_id` as a third normalization tier.

Once steps 1–4 are complete, the architecture already supports the rest of the planned roadmap without another contract change.

---

## Final Summary

1. **Is it safe to modify anything now?** Yes — every file listed above either contains fall-through branches or is one of the safely-mutable datasets. Nothing in the CommuteBD chain is a one-way stub.
2. **Which files are changeable for Phase-2?** The CSV dataset, the ML training script, the crowd module, the financial_service mirror, and **additive** UI copy on `commute_bd_screen.dart`. See the table above.
3. **Which files are untouchable?** `routers/commute.py`, `data_repository.py`, `routing.py`, `supabase_repository.py`, `main.py`, `core/auth.py`, `core/config.py` — the public contract layer.
4. **First datasets to connect?** Supabase `user_fare_reports` (write side) → moderation → `CrowdFareRepository` (read side). Then ML artifacts in object storage. Then `places.csv` geocoding queue.
5. **Recommended implementation order?** Crowd → ML gate → rickshaw model → cng model → bus_services enrichment → geocoding queue → stop-alias fusion. The contract already accommodates this sequence.
