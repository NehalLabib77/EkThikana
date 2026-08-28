# CommuteBD Map-Picker Update

This report covers the user-visible change to the CommuteBD screen: adding
a real full-screen map picker for both the starting point ("From") and the
destination ("To"), alongside the existing text-search sheet.

The change respects the Phase B hard constraint of **no new routes, no new
API endpoints, no new dependencies, no schema changes**. The picker uses
only the OSM tile server already used by the main route map and the
`flutter_map` + `latlong2` + `geolocator` packages already in `pubspec.yaml`.

---

## What the user sees now

**From** row
- Existing: `[Recenter]` icon button — calls `Geolocator.getCurrentPosition`.
- New: `[Map]` icon button — opens the full-screen picker pre-seeded with
  the current origin (or Dhaka centre if no origin yet).

**To** row
- Existing: tap anywhere on the row opens the text-search bottom sheet.
- New: `[Map]` icon button — opens the same full-screen picker pre-seeded
  with the current destination (or origin or Dhaka centre if no destination).

The picker itself
- Full-screen `FlutterMap` showing OSM tiles.
- Tap anywhere on the map to drop / move the pin (the pin is always centred).
- "Use my GPS" button snaps the map to the current device location.
- A "Label for this place" text field at the bottom. If left empty, a
  `Pinned <lat>, <lon>` string is used so the user can never submit an
  empty name.
- "Use this point" / AppBar "Confirm" confirm and return the chosen
  `LatLng` + label.
- "Cancel" / AppBar close returns null and leaves CommuteBD unchanged.

---

## Why a separate widget instead of a new backend route

The existing backend has only:

```
POST /api/commute/search    text -> place results
POST /api/commute/route     lat/lon -> route + fare engine
POST /api/commute/fare-report   trip metadata -> ledger write
```

There is **no reverse-geocode endpoint** and Phase B's hard rule says no new
routes. Rather than break the rule, the picker:

1. Returns `LatLng` (what `commuteRoute` already accepts).
2. Asks the user to type a friendly label — the user is the best source of
   context ("Home", "Office", "Farmgate").
3. If the user skips the label, a `Pinned <lat>, <lon>` fallback is used.

The chosen label + coordinates are then fed back into the existing
`_buildRoute()` path so fare estimation, ML confidence, BRTA/Metro
deterministic fares, and the central ledger write all behave exactly as
before.

---

## Files touched

```
flutter_app/lib/widgets/location_picker.dart           NEW
flutter_app/lib/screens/life/commute_bd_screen.dart    edited
```

### `flutter_app/lib/widgets/location_picker.dart`

New file. Exports:

- `class PickedLocation { String name; LatLng point; }`
- `class LocationPickerScreen extends StatefulWidget`
  - `static Future<PickedLocation?> show(context, {title, initial, initialName, allowGps})`

Behaviour:
- Full-screen modal route (`fullscreenDialog: true`) so it dismisses with a
  back-arrow swipe.
- `MapController.move(point, zoom)` is called every time the pin moves so
  the pin stays visually centred under the user's finger.
- A simple permission flow: `isLocationServiceEnabled` → `checkPermission` →
  `requestPermission` (only when previously denied) → bail with a friendly
  bilingual error if still denied / deniedForever.
- `getCurrentPosition` uses `LocationAccuracy.high` with a 15-second
  `timeLimit` so the GPS button never hangs.
- "OSM" attribution overlay is always shown in the bottom-left.
- All user-facing strings are wrapped in `EkLanguage.text('EN', 'BN')`.

### `flutter_app/lib/screens/life/commute_bd_screen.dart`

Imports + new methods + extended card:

- Added `import '../../widgets/location_picker.dart';`.
- New `_pickOriginOnMap()` on `_CommuteBDScreenState`:
  - Opens `LocationPickerScreen.show` with the current origin (or Dhaka).
  - On confirm: `setState` updates `origin`, `originName`, clears `route`,
    `routeError`, `polyline`, then `mapController.move(picked.point, 13)` and
    `_buildRoute()` if `destination` is already set.
- New `_pickDestinationOnMap()`:
  - Same shape as above, but updates `destination`, `destinationName`,
    persists the chosen place via the existing `_rememberDestination` helper,
    and rebuilds the route if `origin` is already set.
- `_HomeHeaderCard` now also takes two new `VoidCallback`s:
  `onPickOrigin` and `onPickDestinationOnMap`. Both wired to the new
  methods at the call site.
- New "Map" `IconButton` placed in the From row (right of the existing
  Recenter button) and in the To row (right of the column, left of the
  chevron). Tooltips are bilingual.

### `flutter_app/lib/services/api_service.dart`

**Untouched.** The picker does not call any API — it returns a `LatLng` and a
label, which `commute_bd_screen.dart` then feeds into the existing
`_buildRoute()` pipeline.

---

## Behaviour verification

| Scenario                                  | Before this change      | After this change                                |
|-------------------------------------------|--------------------------|--------------------------------------------------|
| Set origin only                           | GPS button only          | GPS button **or** map tap-drop pin                |
| Set destination only                      | Text search sheet only   | Text search sheet **or** map tap-drop pin        |
| Tap a pin that's actually on the highway  | impossible               | Tap-drop on the map, label it, confirm           |
| Wrong village with no OSM search hit      | impossible               | Drop a pin anywhere, label it, confirm           |
| Rider without GPS permission              | silent failure           | Map picker still works; GPS button shows error   |
| New `commute_bd` invocation without pin   | empty header cards       | same; map icon now offers full manual control    |

---

## Test / build evidence

```
flutter analyze
  3 pre-existing infos; 0 new errors; 0 new warnings.

flutter test --no-pub
  All 19 tests passed.
    - financial_ledger_test.dart: 10 passed
    - medicine_ocr_confirmation_test.dart: 2 passed
    - notification_policy_test.dart: 7 passed

get_errors lib/screens/life/commute_bd_screen.dart
  No errors found.

get_errors lib/widgets/location_picker.dart
  No errors found.
```

The fare engine, OSRM call, BRTA/Metro deterministic fares, ML crowd-only
fallback, source/confidence labels, and the central ledger
`transactionId = sha256('commute_actual_fare' + tripId)` invariant are all
preserved unchanged — the picker only affects **how** `origin` /
`destination` get their `LatLng`; it does not touch the fare pipeline.

---

## Future work (intentionally deferred)

- **Reverse-geocoding**: A proper `/api/commute/reverse-geocode` would let
  the picker pre-fill a label from the OSM Nominatim dataset. This requires
  a new backend route and was deliberately excluded from Phase B.
- **Drag-to-move pin**: Currently the pin is fixed at the map centre; a
  long-press drag would let users fine-tune without re-tapping. This is a
  small follow-up if user feedback requests it.
- **Recenter on confirm**: Some users may want the picker to remember the
  last picked location. Trivial follow-up via `SharedPreferences`.