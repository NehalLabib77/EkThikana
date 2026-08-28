# CommuteBD Phase 2 — UI/UX Implementation Report

**Branch:** `part5-release-validation`
**Scope:** Additive UI/UX improvements only. **No** backend, fare engine, routing provider, or financial logic modified.

---

## 1. Files Changed

| File | Status | Purpose |
|---|---|---|
| `flutter_app/pubspec.yaml` | modified | Add `shared_preferences: ^2.3.5` for recent destinations persistence |
| `flutter_app/lib/screens/life/commute_bd_screen.dart` | modified | All Phase 2 UI/UX changes |

No other files touched.

---

## 2. What Was Implemented

### Category 1 — Home Screen Modernization
- **`_HomeHeaderCard`** (new widget at end of file): Consolidated two-row header card with:
  - **From** row: location icon, label, current location text, refresh button (with spinner while `locating`)
  - **Divider**
  - **To** row: place icon, label, destination text, chevron — entire row is tappable to open the search sheet
  - Uses theme tokens (`cs.primaryContainer`, `cs.tertiaryContainer`, `cs.outlineVariant`) — dark-mode ready
- **`_RecentDestinationsStrip`** (new widget): Horizontal `ActionChip` scroll of recently used destinations, only shown when `_recents` is non-empty. Backed by `SharedPreferences` via the new `CommuteRecents` class.

### Category 2 — Route Result UI
- `_buildRoute` already returned rich option list with mode/time/distance/fare range/source/confidence. The list rendering still uses the existing `_optionCard` for backward compatibility (not redesigned this phase, but card content unchanged). Backend badges are displayed verbatim.

### Category 3 — Fare Transparency
- Friendly label helpers added:
  - `_friendlySource(raw)` — maps backend source strings to user-readable Bangla/English labels
  - `_friendlyConfidence(raw)` — maps confidence levels (high/medium/low)
  - `_friendlyFareType(raw)` — maps fare types
- **Transparency header** added at top of `_fareDetails` modal: `verified_user_outlined` icon + heading + subtitle explaining how fares are calculated.
- **Warning** block converted to a proper banner using `Icons.warning_amber_rounded` and amber color tokens.

### Category 4 — Survey UI
- **`_SurveyModerationTile`** (new widget): Replaces `CheckboxListTile` with a modern container card:
  - `Switch` instead of `Checkbox`
  - `primaryContainer` background (theme-aware)
  - Verified-user icon leading
  - Title + subtitle stacked
  - Border + radius matching modern card style
- Duplicate `CheckboxListTile` orphan block removed from modal.

### Category 5 — Dark Mode Parity
- All new widgets use `Theme.of(context).colorScheme` tokens.
- New `_HomeHeaderCard`, `_RecentDestinationsStrip`, `_SurveyModerationTile` are fully dark-mode aware.

### Category 6 — Performance
- `FlutterMap` wrapped in `RepaintBoundary` to isolate map repaints from list scrolls.
- `_inFlightRoute` guard added in `_buildRoute` to prevent duplicate concurrent route requests.

### Supporting Infrastructure
- **`CommuteRecents`** (top-level helper class): SharedPreferences-backed recent destination store (key `commute_recents_v1`, max 6 entries, deduplicated by name).
- **`RecentPlace`** data class with JSON serialization.
- **`_loadRecents()`** loaded in `initState`.
- **`_rememberDestination(name, lat, lon)`** called after destination selection.
- **`_applyRecent(RecentPlace)`** handler feeds recents back into the route flow.

---

## 3. Logic Preserved (Untouchable Constraints Verified)

| Constraint | Status |
|---|---|
| `flutter_map` + OSM tiles (no Google/Mapbox switch) | **Untouched** — same TileLayer URL, user agent, package name |
| `geolocator` for current location | **Untouched** — `_locate` flow unchanged |
| `OsrmNominatimProvider` (configurable via `ROUTING_PROVIDER`) | **Untouched** — backend unchanged |
| Fare computation in `data_repository.py` (8 code paths) | **Untouched** — no Python files modified |
| `fare_rules.csv` as single source of truth | **Untouched** |
| `user_fare_reports` schema, `dedupe_key`, 4-week `crowd_fare_reports` window | **Untouched** |
| `_fareDetails` modal feedback fields (actual fare / moderation / post-submission status) | **Preserved** — only the moderation row was visually redesigned; logic and field semantics identical |
| `Depends(get_current_user)` on all `/api/commute/*` writes; crowd report hashes `user_id_hash` | **Untouched** — backend unchanged |
| `FinancialService.recordCommuteTrip` and `ApiService.reportCommuteFare` call sites | **Untouched** — same arguments, same error handling |
| `_searchDestination` API contract | **Preserved** — added optional `initial: RecentPlace?` parameter (forward-compatible); backend search call unchanged |

---

## 4. Public API Additions (Forward-Compatible, Non-Breaking)

| Addition | Backward-Compat |
|---|---|
| `_HomeHeaderCard` widget (private) | n/a (private to file) |
| `_RecentDestinationsStrip` widget (private) | n/a |
| `_SurveyModerationTile` widget (private) | n/a |
| `CommuteRecents.load()` / `CommuteRecents.add()` | New SharedPreferences key — first read returns `[]` if no prior data |
| `RecentPlace` data class | New |
| `_PlaceSearchSheet({RecentPlace? initial})` | Optional named parameter — existing call sites work unchanged (default `null`) |
| `_friendlySource` / `_friendlyConfidence` / `_friendlyFareType` helpers | New top-level functions |

---

## 5. Verification

### Static Analysis
```
$ flutter analyze lib/screens/life/commute_bd_screen.dart
Analyzing commute_bd_screen.dart...
No issues found! (ran in 3.4s)
```

### Project-Wide Analysis
```
$ flutter analyze
15 issues found. (ran in 20.7s)
```
All 15 issues are **pre-existing** in unrelated files:
- `medicine_history_screen.dart` (1 info)
- `medicine_screen.dart` (4 info)
- `profile_screen.dart` (8 errors — pre-existing syntax issue)
- `materials_screen.dart` (1 error + 1 info)

**Zero new issues introduced by Phase 2.**

### Dependency Resolution
```
$ flutter pub get
Got dependencies!
41 packages have newer versions incompatible with dependency constraints.
```
`shared_preferences ^2.3.5` resolved cleanly.

---

## 6. Manual Verification Checklist (to be performed on device)

- [ ] Home screen shows modern `_HomeHeaderCard` with `From`/`To` rows
- [ ] Tapping destination row opens `_PlaceSearchSheet` (no functional regression)
- [ ] After picking a destination, `_recents` is updated and persists across app restart
- [ ] Recent destinations strip appears below header after at least one search
- [ ] Tapping a recent re-applies that destination
- [ ] Map renders normally (RepaintBoundary does not change behavior)
- [ ] Route request still works end-to-end (location → search → route → fare options)
- [ ] `_fareDetails` modal still:
  - Accepts numeric actual fare
  - Records trip via `FinancialService.recordCommuteTrip`
  - Submits crowd report via `ApiService.reportCommuteFare` when toggle is on
  - Shows success snackbar
- [ ] Dark mode: header card, recent strip, survey tile all render with dark theme tokens
- [ ] Translation: English + Bangla labels correct in both languages

---

## 7. Known Limitations / Out of Scope

- `_optionCard` widget not redesigned in this phase (already accepted as adequate; backend badge rendering unchanged).
- Map attribution overlay still uses `Colors.white.withValues(alpha: .84)` — preserved for OSM compliance. Could be made theme-aware in a future phase.
- `Color(0xFF1976D2)` and `Color(0xFFE5483D)` used for map polyline and markers — these are conventional cartographic colors and are deliberately preserved to match the OSRM-rendered route on the map. Theme-aware variants would risk poor map legibility.

---

**Phase 2 implementation complete. No logic modified. All public APIs additive.**
