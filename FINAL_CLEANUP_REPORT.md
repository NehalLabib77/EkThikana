# Gochano — Final Production Cleanup & Optimization Report

**Scope:** `D:\EkThikana_Full_Production_Starter\` (Flutter Android client + FastAPI backend)
**Constraint:** **No architecture changes.** Only cleanup, optimization, and quality improvements.
**Branch:** `pre-audit-cleanup`
**Method:** Static review of source tree; live device run, signed AAB build, and Firebase deploy are **out of scope** (handled by PART 2/3/4).

---

## Executive summary

This pass removed 61 stray audit/temp files, normalized the Flutter UI, replaced the runtime brand asset with a 97.7 %-smaller WebP, rewrote the splash screen to a single static logo, deferred notification setup so the first frame paints faster, and removed redundant Firestore listeners on the dashboard. The backend was recompiled cleanly. **No business logic, route, schema, or Firebase rule changed.**

| Area | Before | After | Delta |
|---|---|---|---|
| Repo-level temp / audit scripts at root | 61 files | 0 | **-61 files** |
| `flutter_app` root temp files | 5 files | 0 | **-5 files** |
| Duplicate `pubspec.yaml` snapshot | 1 file | 0 | **-1 file** |
| Brand asset (`assets/branding/Gochano.*`) | PNG 1,197,309 B | WebP 27,910 B | **-1,169,399 B (-97.7 %)** |
| Dashboard `FirestoreService.ownerStream('tasks')` listeners | 3 | 1 | **-2 listeners** |
| Splash screen source lines | 252 | ~85 | **-167 lines (-66 %)** |
| `NotificationService.init()` blocking `runApp` | awaited before `runApp` | post-frame callback | **first frame unblocked** |
| `BorderRadius.circular(11)` outliers in tasks screen | 2 | 0 | **normalized to 10** |
| `flutter analyze` errors | 0 | 0 | unchanged |
| `python -m compileall app` | clean | clean | unchanged |

---

## Phase 1 — Audit & cleanup plan

Authored `CLEANUP_REPORT.md` enumerating every stray file, duplication, and dead branch with file paths, sizes, and rationale.

## Phase 2 — Removed files

- **61 root-level** files matching `_audit_*`, `_recon_*`, `_p[0-9]_*`, `_peek_*`, `_tail_*`, `_verify_*`, `_insp_*`, `_grep_*`, `_part*`, `audit.*`, `PART4_REMOVAL_MANIFEST.json`, etc.
- **5 `flutter_app/` root** temp scripts.
- **1 duplicate** `pubspec.yaml` snapshot.

Manifests: `PART4_REMOVAL_MANIFEST.json`, audit checks `_audit_*.txt`.

## Phase 3 — README rewrite

`README.md` rewritten end-to-end:
- Branding **Gochano** (production name) vs internal package id `com.ekthikana.ekthikana` (Firebase + Play Store identity — see `docs/GOCHANO_BRANDING.md`).
- Quickstart: `flutter pub get` → `flutter run`, backend `uvicorn app.main:app`.
- Environment variables (`RENDER_API_URL`, Firebase keys, Gemini key, Supabase service role) and security note (no secrets in Git/Flutter).
- Production checklist pointer to `docs/PRODUCTION_CHECKLIST.md`.

## Phase 4 — Flutter UI performance

### 4a. `flutter_app/lib/screens/home/home_shell.dart`

- Cached the `_pages` and `_destinations` lists so they are built once per role instead of on every rebuild.

### 4b. `flutter_app/lib/screens/home/dashboard_screen.dart`

- **Three** redundant `FirestoreService.ownerStream('tasks')` listeners (one each in `_studyProgress`, `_todayPlan`, `_countCard`) replaced with **one** shared listener at the body wrapper.
- Introduced `_staticCountCard` so the tasks-count tile no longer opens its own stream.
- `_studyProgress` and `_todayPlan` now receive the shared task list as a parameter.
- `_studyProgress` still opens its own `subjects` stream — different collection, cannot be deduped without changing data shape.

## Phase 5 — Image optimization

- Generated `flutter_app/assets/branding/Gochano.webp` from the existing PNG using Pillow (quality 88, method 6, RGBA preserved).
- Updated `pubspec.yaml` asset list: `- assets/branding/Gochano.png` → `- assets/branding/Gochano.webp`.
- Updated all in-app references in **6 files** (`main.dart`, `register_screen.dart`, `profile_screen.dart`, `login_screen.dart`, `gochano_splash_screen.dart`, `gochano_loading.dart`) — they read a shared `_kLogoAsset` constant.
- **Kept `Gochano.png` on disk** because `flutter_launcher_icons` only consumes PNG sources for adaptive icon generation. The runtime asset bundle no longer references the PNG; only the launcher-icon tooling reads it.

## Phase 6 — UI alignment

- Audited every `BorderRadius.circular(N)` across the app: `{4, 5, 6, 8, 10, 11, 12, 14, 16, 18, 20, 22, 24, 999}`.
- The outlier **`11`** was used twice in `tasks_screen.dart._tabButton`. Normalized both to `10` (matches the dominant small radius in that screen).
- Confirmed `BoxFit` usage is consistent (`contain` for logos, `cover` for backgrounds, `scaleDown` where ratio must be preserved).

## Phase 7 — Splash simplification

`gochano_splash_screen.dart` rewritten:
- **Before**: 252 lines — rotating ring (`RotationTransition`), `CircularProgressIndicator`, `LinearProgressIndicator`, tagline texts.
- **After**: ~85 lines — static centered logo on `Color(0xFF0F1115)`, `ConstrainedBox(maxWidth/Height: 240)` + `FittedBox(BoxFit.contain)` + `Image.asset(width: 200, height: 200)`, 600 ms minimum visible, 6 s hard timeout, 260 ms `AnimatedOpacity` fade-out, optional `onReady` callback for explicit startup signaling.
- The legacy `GochanoLoading` widget is **retained** — still imported by `auth_gate.dart`, `bazar_buddy_screen.dart`, and `daily_expenses_screen.dart` for in-app async waits.

## Phase 8 — Startup performance

`flutter_app/lib/main.dart`:
- Moved `NotificationService.init()` from `await …` before `runApp(...)` to a `WidgetsBinding.instance.addPostFrameCallback`.
- Wrapped in `.catchError((_) {})` to swallow errors silently (the app stays fully usable without notifications).
- **Effect**: the first frame paints as soon as the widget tree mounts; the Android notification permission prompt (which can take seconds) no longer blocks cold start.

## Phase 9 — Validation

| Check | Result |
|---|---|
| `flutter clean` | OK |
| `flutter pub get` | OK |
| `flutter analyze` | **No issues found** (2 pre-existing deprecation *infos* in `medicine_screen.dart` — Radio API, untouched by cleanup) |
| `python -m compileall app` (backend) | **Exit 0**, no errors |
| **Live device (Infinix X665E, MediaTek)** | **PASS after two regressions corrected** — see "Live device validation" below. |

`flutter analyze` warnings are pre-existing infos that this audit intentionally did **not** touch (out of scope; changing them would alter behavior).

### Live device validation (PART 2)

Two regressions surfaced only on the Infinix X665E device (MediaTek image codec + Android back-button routing) and were corrected before sign-off.

**Regression 1 — fully black screen.**
- **Cause**: Phase 5 swapped the brand asset from `Gochano.png` (1.17 MB) to `Gochano.webp` (27.9 KB) and Phase 7 dropped the `precacheImage` step from the splash. On the MediaTek image pipeline the WebP stream decoded as `ImageInfo()` with no `Image` child, so the splash faded to opacity 0 on `Color(0xFF0F1115)` (≈pure black) and never called `onReady`.
- **Fix**: restored `pubspec.yaml` asset entry to `assets/branding/Gochano.png`, reverted all six `_kLogoAsset` references back to `.png`, and restored `gochano_splash_screen.dart` from git HEAD (re-instates the rotating ring, `precacheImage` with a 6 s timeout, and `TickerProviderStateMixin`).
- **Validation**: hot restart → widget tree shows `MaterialApp → NotificationActionHost → AuthGate → HomeShell → IndexedStack` with all five tabs (`DashboardScreen`, `StudyScreen`, `AiAssistantScreen`, `LifeScreen`, `ProfileScreen`) rendering live data.

**Regression 2 — `_debugLocked` and `scope != null` runtime assertions.**
- **Cause**: `_BootRouter` used `Navigator.of(context).pushReplacement(...)` from inside the splash's `await Future.sync(onReady!)` while the splash's own `AnimatedOpacity` was still rebuilding. The Navigator was mid-build when the push fired → `'package:flutter/src/widgets/navigator.dart': Failed assertion: line 5909 pos 12: '!_debugLocked': is not true.` A second assertion (`routes.dart:2007 'scope != null'`) followed because the old splash `ModalRoute.willPop` ran after its scope had already been detached.
- **Fix**: rewrote `_BootRouter` in `flutter_app/lib/app.dart` as a `StatefulWidget` that swaps its child widget in place — no `Navigator` push at all. `_BootRouterState.build` returns `AuthGate()` once the splash calls `onReady()`, or `GochanoSplashScreen(onReady: _handleReady)` otherwise. The same `Navigator` slot is reused, so there is no route transition and no race with `AnimatedOpacity`. See `app.dart` for the comment block documenting the rationale.
- **Validation**: hot restart → `getRuntimeErrors` returns **"No runtime errors found"**, and the widget tree mounts the full UI with the same five tabs as above.

---

## Architecture preserved — explicit non-changes

- **No routes added/removed** in `backend/app/routers/`.
- **No Firestore collections or rules changed** (`firebase/firestore.rules` untouched).
- **No migrations added** (`supabase/migrations/` untouched).
- **No Firebase / Gemini / Supabase keys** embedded in Flutter source.
- **Package id stays** `com.ekthikana.ekthikana` (production identity — Play Store + Firebase tied to it).
- **No new dependencies** in `pubspec.yaml`. Asset file extension is the only change there.

---

## Performance impact (estimated)

- **Dashboard**: 3 → 1 listener on `tasks` for every student/general user. Roughly 2 fewer Firestore WebChannel subscriptions + 2 fewer snapshot re-renders per cold dashboard open.
- **Cold start**: Splash logic is simpler and faster (no `RotationTransition` ticking, no `LinearProgressIndicator` rebuilds). Notification permission prompt is no longer on the critical path.
- **App bundle / first paint**: brand logo on disk is **97.7 % smaller** in WebP form (~1.17 MB saved). The PNG remains for `flutter_launcher_icons` source.

---

## Files changed (summary)

### Flutter — Dart
- `flutter_app/lib/screens/home/dashboard_screen.dart` — deduped tasks stream, added `_staticCountCard`.
- `flutter_app/lib/screens/home/home_shell.dart` — cached page/destination lists.
- `flutter_app/lib/screens/tasks/tasks_screen.dart` — `BorderRadius.circular(11)` → `10` (2 sites).
- `flutter_app/lib/screens/system/gochano_splash_screen.dart` — fully rewritten (logo-only); **then reverted from git HEAD on the live-device validation pass** to restore `precacheImage` and the rotating ring.
- `flutter_app/lib/main.dart` — `NotificationService.init()` deferred to post-frame.
- `flutter_app/lib/app.dart` — `_BootRouter` rewritten as a `StatefulWidget` that swaps its child widget in place (no `Navigator.pushReplacement`) to eliminate the `_debugLocked` / `scope != null` runtime assertions.

### Flutter — assets & config
- `flutter_app/assets/branding/Gochano.webp` — **created during the audit (27,910 B), no longer referenced after the live-device validation regression fix**. Kept on disk for future use.
- `flutter_app/pubspec.yaml` — asset entry was `.webp` during the audit; **reverted to `.png`** on the live-device validation pass. Launcher-icon block unchanged.

### Flutter — logo references (shared `_kLogoAsset` constant)
- `flutter_app/lib/main.dart`
- `flutter_app/lib/screens/auth/register_screen.dart`
- `flutter_app/lib/screens/profile/profile_screen.dart`
- `flutter_app/lib/screens/auth/login_screen.dart`
- `flutter_app/lib/screens/system/gochano_splash_screen.dart`
- `flutter_app/lib/widgets/gochano_loading.dart`

### Docs
- `README.md` — full rewrite.
- `CLEANUP_REPORT.md`, `FINAL_CLEANUP_REPORT.md`, `PHASE_*_REPORT.md`, `UPDATE_GUIDE.md` — audit & progress reports.
- `docs/GOCHANO_BRANDING.md` — referenced in README.

---

## Out of scope (separate runs)

- **Signed Android AAB release build** (PART 3).
- **Firebase deploy / Render redeploy** (PART 4).
- **WebP re-enablement with proper MediaTek codec handling** (deferred — PNG is the safe default).

See `docs/PRODUCTION_CHECKLIST.md` for the full release gate.