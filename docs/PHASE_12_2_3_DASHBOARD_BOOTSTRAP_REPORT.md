# Phase 12.2.3 — Dashboard Bootstrap & Startup Optimization Verification Report

## Executive Summary

Phase 12.2.3 optimizes the initial Home and Study startup network flow for Gochano / EkThikana. Prior to this phase, mounting the student Home screen resulted in a startup waterfall consisting of multiple independent HTTP requests (`/api/me`, `/api/ai/academic-health`, `/api/coach/daily`, `/api/focus/today`, `/api/ai/usage`, `/api/learning/recommendations`, and active Exam Rescue checks), causing unnecessary round-trips and layout shifts on mobile connections.

Phase 12.2.3 introduces a consolidated backend bootstrap service and endpoint (`GET /api/student/dashboard-bootstrap`), which aggregates canonical domain signals concurrently without recalculating business logic. The Flutter Home screen now fetches this aggregated payload in a single startup request and supplies the preloaded data to individual cards (`AcademicHealthCard`, `ZikuCoachCard`, `ZikuSessionCard`, `LearningRecommendationCard`), each of which adopts the payload in `initState`/`didUpdateWidget` when it lands. Dedicated card endpoints are preserved for standalone card mounts outside the Home screen and as the fallback for the first frames before the bootstrap resolves.

---

## 1. Startup Network Audit: Waterfall Elimination

| Surface | Pre-Phase 12.2.3 (Multiple Round Trips) | Phase 12.2.3 (Consolidated Bootstrap) |
|---|---|---|
| **Student Profile** | `GET /api/me` | Included in `profile` |
| **Academic Health** | `GET /api/ai/academic-health` | Included in `academicHealth` |
| **Study Coach** | `GET /api/coach/daily` | Included in `coach` |
| **Focus Engine** | `GET /api/focus/today` | Included in `focus` |
| **AI Usage** | `GET /api/ai/usage` | Included in `aiUsage` |
| **Recommendations** | `GET /api/learning/recommendations` | Included in `recommendation` |
| **Exam Rescue** | Query `users/{uid}/exam_rescue` | Included in `examRescue` |
| **Total Round Trips** | **5–7 independent client requests** | **1 consolidated `dashboard-bootstrap` request whose payload preloads every card. Dedicated card endpoints remain the fallback for standalone mounts and for the window before the payload lands (a card mounts before the bootstrap resolves, then adopts it in `didUpdateWidget`).** |

---

## 2. Backend Architecture & Implementation

### 2.1 Consolidated Bootstrap Service
`backend/app/services/dashboard_bootstrap_service.py` provides:
- **Concurrent Aggregation**: Uses `asyncio.to_thread()` and `asyncio.gather(..., return_exceptions=True)` to execute domain reads in parallel without blocking the main event loop.
- **Strict Canonical Reuse**: Directly invokes canonical service layers (`academic_health_service.get_academic_health`, `study_coach_service.daily_recommendation`, `focus_service.engine_today`, `ai_service.get_ai_usage`, `content_recommendation_service.get_recommendations`).
- **Section Isolation & Fault Tolerance**: Any failure in an individual domain section is caught and degraded gracefully (`{"available": False, ...}`) without failing the overall 200 HTTP response.
- **Privacy & Security**: Tokens, passwords, and raw private notes are never included in the bootstrap payload.

### 2.2 Student Router & Role Gate
- `backend/app/routers/student.py` mounts `GET /api/student/dashboard-bootstrap` protected by `require_student`.
- The user UID is derived strictly from the authenticated JWT token (`user.uid`); the client cannot request bootstrap data for another user.
- Mounted in `backend/app/main.py` under prefix `/api/student`.
- Added to `STUDENT_ONLY_PREFIXES` in `backend/tests/test_role_gate_coverage.py` to ensure static AST enforcement and dynamic 403 rejection for `general` users.

---

## 3. Flutter Client Integration

### 3.1 ApiService Client Method
`flutter_app/lib/services/api_service.dart` exposes:
```dart
static Future<Map<String, dynamic>> studentDashboardBootstrap() async {
  return _guard(() async {
    final res = await _get('/api/student/dashboard-bootstrap');
    final decoded = _decode(res);
    return Map<String, dynamic>.from(decoded);
  });
}
```

### 3.2 HomeScreen Conversion & Refresh Indicator
`flutter_app/lib/features/home/presentation/home_screen.dart` was converted to a `StatefulWidget`:
- Injects optional `bootstrapFn` (defaults to `ApiService.studentDashboardBootstrap`).
- Dispatches a single bootstrap call in `initState` for student roles.
- Supplies preloaded data to `buildModeCards(context, mode, _bootstrapData)`.
- Adds a `RefreshIndicator` wrapping the Home `ListView` so pulling to refresh updates the entire dashboard via `_loadBootstrap()`.
- Preserves all structural string tokens required by `home_mode_filtering_test.dart` and `ziku_focus_test.dart`.

### 3.3 Card Component Preload Support (`initialData`)
The following cards now accept an optional `initialData` parameter:
1. `AcademicHealthCard`: Initializes with `initialData` score, grade, headline, and trend. Falls back to `_read()` if null.
2. `ZikuCoachCard`: Adopts the `coach` section as its brief (greeting, priority, why, mission, health badge). Falls back to `GET /api/coach/daily` if null; `didUpdateWidget` adopts the payload when the bootstrap lands after mount, and a late dedicated read can no longer overwrite it.
3. `ZikuSessionCard`: Initializes with `initialData` minutes completed, goal minutes, and focus score. Falls back to `_read()` if null.
4. `LearningRecommendationCard`: Renders items directly from `initialData` when available; shrinks to `SizedBox.shrink()` when unavailable or empty. Falls back to `LearningApiService.recommendations()` if null.

---

## 4. Verification & Test Results

### 4.1 Backend Test Results (`backend/tests/test_dashboard_bootstrap.py`)
All 8 backend tests passed:
- `test_bootstrap_requires_auth`: 401 for a missing token and for an unverifiable token.
- `test_bootstrap_rejects_non_student_role`: 403 `Student account required` for non-student users.
- `test_bootstrap_returns_all_sections`: 200 returning every section (`profile`, `academicHealth`, `coach`, `focus`, `aiUsage`, `recommendation`, `examRescue`, `generatedAt`) plus an ISO-8601 `generatedAt`.
- `test_bootstrap_ignores_uid_query_parameter`: `?uid=` cannot select another user; the payload always carries the token's UID.
- `test_bootstrap_delegates_to_service_sections`: the router surfaces whatever a service section returns (section-level monkeypatch round-trip).
- `test_bootstrap_isolates_section_failures`: `_get_focus` throwing and `study_coach_service.daily_recommendation` throwing degrade to their documented defaults while healthy sections keep their real values.
- `test_bootstrap_payload_excludes_sensitive_fields`: no credential keys, and seeded password hashes, reset tokens, raw notes and transcripts never reach the payload.
- `test_bootstrap_concurrent_requests_are_isolated`: 4 students on a `threading.Barrier(4)` each receive exactly their own payload, with no cross-user leakage.

Full backend suite status (live run):
```
942 tests collected
933 passed, 9 failed
(9 failures are the pre-existing `test_ai_attachment.py` baseline for the
non-existent POST /api/ai/attachment-question route; 0 regressions)
```

`GET /api/student/dashboard-bootstrap` is also enforced by
`tests/test_role_gate_coverage.py`: `/api/student` is in `STUDENT_ONLY_PREFIXES`,
so both the static AST gate and the runtime 403 probe cover it.

### 4.2 Flutter Test Results (live runs)
1. `flutter test test/dashboard_bootstrap_test.dart`: **4/4 PASSED**
   - `Home uses bootstrap for initial dashboard load and eliminates waterfalls`
   - `Partial section degradation leaves remaining cards intact`
   - `Non-student mode never triggers bootstrap endpoint`
   - `Standalone cards without bootstrap preserve dedicated fallback endpoints`
2. `flutter test test/home_mode_filtering_test.dart`: **9/9 PASSED**.
3. `flutter test test/ziku_focus_test.dart`: **8/8 PASSED**.
4. `flutter test test/ziku_coach_test.dart`: **18/18 PASSED**.
5. Full Flutter test suite: **1,377 passed / 98 failed**. The HEAD `5a0bb7f`
   baseline for the same test files is **99 failed**, and a set comparison shows
   **0 new failures** — every remaining failure is pre-existing.

### 4.3 Static Code Analysis & Formatting
- `flutter analyze lib`: `No issues found!`
- `git diff --check`: 0 errors on every edited file except the CRLF-authored
  `backend/tests/test_role_gate_coverage.py` (added lines keep HEAD's CRLF ending);
  `git -c core.whitespace=cr-at-eol diff --check` → **0 errors**.
- All six `docs/PHASE_12_2*.md` reports are LF (0 CR bytes).

---

## 5. Artifacts and Modified Files

### Backend
- `backend/app/services/dashboard_bootstrap_service.py` (New service)
- `backend/app/routers/student.py` (New router)
- `backend/app/main.py` (Registered student router)
- `backend/tests/test_dashboard_bootstrap.py` (New test suite, 8 tests)
- `backend/tests/test_role_gate_coverage.py` (Added `/api/student` to role gate coverage)
- `backend/tests/conftest.py` (Registered mock firestore patch for dashboard bootstrap service)

### Frontend (Flutter)
- `flutter_app/lib/services/api_service.dart` (Added `studentDashboardBootstrap`)
- `flutter_app/lib/services/firestore_service.dart` (Guarded `profileStream()` so a headless/test build without Firebase resolves to `Stream.empty()` instead of throwing during a widget build)
- `flutter_app/lib/features/home/presentation/home_screen.dart` (Converted to `StatefulWidget`, integrated bootstrap & `RefreshIndicator`)
- `flutter_app/lib/features/profile/presentation/academic_health_card.dart` (Added `initialData` support)
- `flutter_app/lib/features/study/presentation/planner/ziku_coach_card.dart` (Added `initialData` support + late-adoption guard)
- `flutter_app/lib/features/study/presentation/focus/ziku_session_card.dart` (Added `initialData` support)
- `flutter_app/lib/features/study/presentation/memory/learning_recommendation_card.dart` (Added `initialData` support)
- `flutter_app/test/dashboard_bootstrap_test.dart` (New test suite, 4 tests)
