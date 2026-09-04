# IMPLEMENTATION REPORT

## Final Fix + Verification Batch — Current State

**Date:** 2026-09-05
**Branch:** final-cleanup-release-v2

---

## 1. COMMUTEDB — RICKSHAW DEVICE BUG (VERIFIED)

### Root Cause
`_fetchModeFare()` in `commute_screen.dart` caught API/network errors and passed them to `friendlyErrorMessage()` from `gochano_states.dart`. That function maps ANY error containing "not found" or "404" to "This item is no longer available." — a message designed for material/resource errors, not commute fare errors.

### Exact Fix
`friendlyErrorMessage(error)` in `_fetchModeFare()` catch block replaced with `_fareErrorLabel(error)` — a commute-specific error handler that never produces "This item is no longer available."

### Files Changed
| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/life/presentation/commute/commute_screen.dart` | `_fareErrorLabel()` (lines 897–940): handles network errors, timeouts, and backend prose. Never maps to generic resource messages. Used at line 238 in `_fetchModeFare()`. |

### Mode Eligibility (verified in `fare_engine.py:143–168`)
| Mode | Max Distance | Justification |
|------|-------------|---------------|
| Bus | None | BRTA fare segments cover intra/inter-city routes |
| Metro | None | MRT Line 6 official station-pair fares |
| CNG | None | RULE_CNG_2015 has no max distance; labelled Historical |
| Rickshaw | 20 km | Dataset covers rows 1–20 km only |
| Auto | 20 km | Same dataset coverage as rickshaw |

### Response Contract
- **Supported:** `{"supported": true, "mode": "rickshaw", "fare": {...}, "distanceKm": 7.6, "drivingMinutes": 8}`
- **Unsupported (>20 km):** `{"supported": false, "mode": "rickshaw", "reason": "...", "distanceKm": 205.0}`
- **API/network error:** Flutter catch block produces context-appropriate message, never "This item is no longer available."

### Tests (28/28 passed)
`python -m pytest tests/test_commute_single_fare.py -v` — 28 passed, 0 failed

Key regression tests:
- `test_7km_rickshaw_is_supported` — 7.6 km rickshaw returns valid fare
- `test_7km_rickshaw_fare_range_is_plausible` — Fare range brackets ~Tk 129
- `test_exactly_20km_rickshaw_is_supported` — 20.0 km boundary accepted
- `test_20km_plus_rickshaw_is_rejected` — 20.1 km rejected
- `test_205km_rickshaw_is_rejected` — 205 km rejected
- `test_7km_auto_is_supported` — 7.6 km auto returns valid fare
- `test_205km_auto_is_rejected` — 205 km auto rejected

---

## 2. STUDY DISTRACTION — FINAL UI (VERIFIED + NEW HANDLER)

### Change Summary
Added `AppLifecycleState.resumed` handler to `DistractionView` so that returning from Usage Access settings automatically refreshes permission status, today's usage, and weekly usage.

### Files Changed
| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/study/presentation/distraction/distraction_view.dart` | Added `WidgetsBindingObserver` mixin, `addObserver`/`removeObserver` in `initState`/`dispose`, `didChangeAppLifecycleState` override that calls `_checkPermissionAndLoad()` on `resumed`. |

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Today's screen time from LOCAL 00:00 | ✅ | `usage_stats_service.dart:57` — `DateTime(now.year, now.month, now.day)` |
| Resets at local midnight | ✅ | Same line — queries from today's 00:00, not rolling 24h |
| 7-day chart Sun–Sat | ✅ | `getWeeklyScreenTime()` lines 104–106 — iterates 6 down to 0 |
| Real UsageStats only | ✅ | `UsageStats.queryUsageStats()` — no fabricated data |
| Unified App Activity list | ✅ | All apps together, no separate sections |
| Gochano appears once | ✅ | In unified list, not filtered out |
| No separate Gochano section | ✅ | No `_buildGochanoSection()` in current code |
| No separate Other Apps section | ✅ | No `_buildOtherAppsSection()` in current code |
| Highest usage first | ✅ | `sortedApps.sort((a, b) => b.value.compareTo(a.value))` |
| Ignore zero/negative usage | ✅ | `if (ms <= 0) continue` at line 72 |
| Row: [Icon] App Name [BAR] Duration | ✅ | `Row` with icon, name, bar, duration in `_buildAppRow` |
| Bar BESIDE app name | ✅ | Horizontal `Row` layout, not stacked |
| Only used colored portion visible | ✅ | `FractionallySizedBox` with `widthFactor: barFraction` |
| NO grey background track | ✅ | No background container behind the bar |
| Width = appUsage / highestUsageToday | ✅ | `(minutes / highestMinutes).clamp(0.0, 1.0)` |
| Rounded ends | ✅ | `BorderRadius.circular(4)` |
| Duration always visible | ✅ | `SizedBox(width: 55)` with `textAlign: TextAlign.end` |

### Color Rules (verified in `distraction_view.dart:412–422`)

**Other apps:**
| Minutes | Color |
|---------|-------|
| ≤ 38 | Green (`context.colors.success`) |
| 39–70 | Amber (`context.colors.warning`) |
| > 70 | Red (`context.colors.error`) |

**Gochano (reversed):**
| Minutes | Color |
|---------|-------|
| ≤ 38 | Red |
| 39–70 | Amber |
| > 70 | Green |

### Usage Access
- Profile row: clickable in both states (Granted / Permission required) — `profile_screen.dart:789–792`
- Tap opens Android Usage Access settings
- On return, re-checks permission via `_checkUsageAccess()`
- On `AppLifecycleState.resumed`: re-checks permission + refreshes data (NEW)

### Privacy (verified)
- No Firebase/backend/analytics/Groq/Gemini writes for usage data
- `usage_stats_service.dart` imports ONLY `package:usage_stats/usage_stats.dart`

---

## 3. COMMUNITY ADMIN VERIFICATION (END-TO-END)

### Tab Order (verified)
`Chat(0) | Projects(1) | Resources(2) | Overview(3)` — `group_detail_screen.dart:129–138`

### Admin Detection (verified in `group_detail_screen.dart:83–88`)
```dart
final adminIds = ((data['adminIds'] as List?) ?? const []).map((e) => e.toString()).toList();
final ownerId = data['ownerId']?.toString() ?? '';
final isAdmin = adminIds.contains(FirestoreService.uid) ||
    (ownerId.isNotEmpty && ownerId == FirestoreService.uid);
```
- Uses `adminIds` (plural array) from Firestore
- Falls back to `ownerId` for legacy groups

### Backend Admin Check (verified in `groups.py:36–37`)
```python
def _is_admin(data, uid):
    return uid in (data.get("adminIds") or [])
```

### Admin-Gated Operations (verified)
| Operation | File:Line | Gated by |
|-----------|-----------|----------|
| Turn chat on/off | `group_detail_screen.dart:101` | `if (isAdmin)` |
| Reset invite code | `group_detail_screen.dart:111` | `if (isAdmin)` |
| New project FAB | `group_detail_screen.dart:596` | `isAdmin` |
| Project edit/delete | `group_detail_screen.dart:733` | `if (isAdmin)` |
| Task FAB | `group_detail_screen.dart:1058` | `widget.isAdmin` |
| Task edit/delete/assign | `group_detail_screen.dart:1259` | `if (isAdmin)` |
| Toggle complete | `group_detail_screen.dart:1194` | `isAdmin \|\| isMyTask` |

### Invite Code Copy Button (verified)
- `group_detail_screen.dart:277–284` — `IconButton` with `Icons.copy_rounded`
- Copies to clipboard with bilingual snackbar

### UNRESOLVED: Firestore Security Rules

**`isGroupAdmin` uses singular `adminId`** (`firestore.rules:51–54`):
```javascript
function isGroupAdmin(groupId) {
    return isStudent()
        && groupId is string
        && request.auth.uid == get(...).data.adminId;  // SINGULAR
}
```
Backend stores `adminIds` (plural array). The rule is inconsistent with the data structure.

**Project/task subcollections have NO explicit rules:**
- `groups/{id}/projects` — not defined
- `groups/{id}/projects/{id}/tasks` — not defined

These subcollections are governed by Firestore's default deny rules. The client-side `FirestoreService` CRUD calls would be blocked unless:
1. The deployed rules differ from the repo
2. There's a backend proxy for these writes
3. Custom rules are configured outside this repo

**This means:** The `isGroupAdmin` function only affects `group_messages` delete (line 162–164). Project/task operations cannot succeed through client-side Firestore writes with the current rules in this repo.

### Normal Member Not Promoted (verified)
- `adminIds` is set only during group creation (`groups.py:54`)
- No UI path promotes a normal member
- Backend only adds/removes `adminIds` via trusted backend operations

---

## 4. ANDROID WARNING CORRECTION (VERIFIED)

### Classification

| Warning | Classification | Evidence |
|---------|---------------|----------|
| KGP in app | UPSTREAM/DEPENDENCY BLOCKED | Requires Flutter 3.47+ for built-in Kotlin |
| usage_stats KGP | UPSTREAM/DEPENDENCY BLOCKED | `usage_stats 2.0.1` is latest version; upstream migration pending |
| FlutterLoader metadata | HARMLESS/EXPECTED | Generated by Flutter engine, not app code |
| `libclassroom_prod` | UNRESOLVED/RUNTIME-GENERATED SOURCE | Not in any source file; expected `libgochano` per package name |
| Impeller opt-out | REQUIRES FRESH-DEVICE VERIFICATION | No source opt-out found; earlier device log showed warning |
| FlutterRenderer Width zero | HARMLESS/EXPECTED | Informational log during widget initialization |

### `libclassroom_prod` Investigation
- `pubspec.yaml` name: `gochano`
- Expected AOT library: `libgochano_flutter_artifacts.so`
- Actual warning: `libclassroom_prod_android_library_flutter_artifacts.so`
- Source files searched: all manifests, build.gradle.kts, pubspec.yaml, Flutter SDK — zero matches
- Classification: UNRESOLVED — requires fresh-device verification

### Impeller Investigation
- No `EnableImpeller` meta-data in any AndroidManifest.xml
- No `--no-enable-impeller` in launch arguments
- Earlier device log showed opt-out warning
- Classification: REQUIRES FRESH-DEVICE VERIFICATION

---

## 5. REPORT CLEANUP — STALE CLAIMS REMOVED

The following outdated claims have been removed from this report:

| Stale Claim | Current Truth |
|-------------|---------------|
| Old `Ziku.png` AI icon | `GochanoArt.featureAi` SVG illustration |
| Old Community tab order `Overview | Resources | Chat | Projects` | `Chat | Projects | Resources | Overview` |
| Old separate Gochano Usage section | Unified app list |
| Old Other Apps section | Unified app list |
| Old 0–30 / 31–60 / >60 color thresholds | 38 / 70 thresholds |
| Old "Gochano filtered from Other Apps" logic | Gochano included in unified list |
| Duplicate CommuteBD fix sections | Single consolidated section |
| `friendlyErrorMessage` in fare flow | `_fareErrorLabel` commute-specific handler |

---

## 6. TEST RESULTS

### Backend
| Suite | Result |
|-------|--------|
| `python -m pytest tests/test_commute_single_fare.py -v` | **28/28 passed** |

### Flutter
| Suite | Result |
|-------|--------|
| `flutter analyze` | **0 errors**, 3 pre-existing info warnings (all in `group_detail_screen.dart`) |
| `flutter test` | **292/292 passed** |
| `flutter build apk --debug` | **Built successfully** |

### Build Warnings (pre-existing, not introduced)
```
WARNING: Your Android app project: app applies the Kotlin Gradle Plugin...
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): usage_stats
```

---

## 7. FILES CHANGED THIS SESSION

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/study/presentation/distraction/distraction_view.dart` | Added `WidgetsBindingObserver` mixin to `_DistractionViewState`. Added `initState`/`dispose` observer management. Added `didChangeAppLifecycleState` override — refreshes permission + data on `AppLifecycleState.resumed`. |

**Total:** 1 file changed, 16 insertions, 1 deletion

---

## 8. GIT STATUS

```
 M flutter_app/lib/features/study/presentation/distraction/distraction_view.dart
```

`git -c core.whitespace=cr-at-eol diff --check` — No whitespace errors
`git diff --stat` — 1 file changed, 16 insertions(+), 1 deletion(-)

---

## 9. UNRESOLVED ISSUES

1. **Firestore security rules for project/task subcollections** — `groups/{id}/projects` and `groups/{id}/projects/{id}/tasks` have no explicit rules. Client-side Firestore writes would be blocked by default deny. Requires investigation of deployed rules or backend proxy.

2. **`isGroupAdmin` singular vs plural mismatch** — Firestore rule uses `data.adminId` (singular) but backend stores `adminIds` (plural array). Only affects `group_messages` delete.

3. **`libclassroom_prod` library origin** — Not found in any source file. Requires fresh-device verification with clean build.

4. **Impeller opt-out** — No source opt-out found. Requires fresh-device verification.

---

## 10. REAL-DEVICE CHECKS STILL NEEDED

- Commute: 7.6 km Rickshaw shows fare on device (not "no longer available")
- Commute: >20 km Rickshaw shows clear unsupported message
- Commute: Network error shows "Could not load fare estimate"
- Distraction: Returning from Usage Access settings refreshes data
- Distraction: Color thresholds correct on device
- Community: Admin can create/edit/delete projects and tasks
- Community: Normal member cannot access admin actions
- Community: Invite code copy button works

---

## 11. NO COMMIT/PUSH/DEPLOY CONFIRMATION

Confirmed. No git commit, push, or deploy operations performed.
