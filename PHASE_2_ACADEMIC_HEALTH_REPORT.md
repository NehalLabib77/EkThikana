# PHASE 2 — AI Academic Health Score + Focus Intelligence

**Date:** 2026-10-02
**Status:** Implemented end-to-end (backend + Flutter) and verified
**Scope:** `backend/`, `firebase/firestore.rules`, `flutter_app/`

---

## 1. What shipped

Phase 2 turns four things the app already records — quiz mastery, deep-work
sessions, the mistake queue and the exam-rescue plan — into one number a
student can read in a second, plus the two decisions that follow from it:
*what is weakest* and *what to do next*.

| Capability | Where it shows up |
| --- | --- |
| 0-100 Academic Health score, grade, headline, trend | Profile card → full screen, Home (Study mode) card |
| Four weighted metrics with a plain-language explanation | Academic Health screen |
| Weak topics merged from quiz averages **and** recorded mistakes | Academic Health screen |
| Deterministic advice + Ziku-authored advice, de-duplicated | Academic Health screen, `GET …/recommendations` |
| 7-day score history as a bar chart | Academic Health screen |
| Focus score (0-100), interruption counter, subject/topic on a session | Focus session start/complete/list, Academic Health |
| `GET /api/study/focus/today` | Today totals for a single day |
| Ziku knows the score | Chat system prompt + "Open Ziku" hand-off |

Nothing in Exam Rescue, Mistake Memory, Ziku chat, the AI Usage Dashboard or
Today was replaced — Phase 2 reads them and adds two entry points.

---

## 2. Score design

Four metrics, fixed weights, in `academic_health_service.py`:

| Key | Weight | Needs |
| --- | --- | --- |
| `consistency` | 0.25 | at least one deep-work session in the last 14 days |
| `understanding` | 0.30 | at least one quiz in the last 7 days |
| `revision` | 0.25 | at least one recorded mistake |
| `examReadiness` | 0.20 | always available (defaults to a "no plan" baseline; uses the active Exam Rescue plan when one exists) |

* **Renormalisation** — unavailable metrics drop out and the remaining
  weights are rescaled, so a student with only quizzes still gets a
  meaningful 0-100 instead of a 0. `coverage` and `missing` name what
  counted.
* **Bands** — `excellent ≥ 85`, `good ≥ 70`, `fair ≥ 55`, else
  `needs_attention`; `no_data` when nothing was measurable.
* **Trend** — compares with yesterday's `health_history` snapshot.
  `delta ≥ +2` → `up`, `≤ -2` → `down`, otherwise `stable`; a missing
  snapshot yields `direction: new`.
* **Windows** — quizzes 7 days (max 100 rows), focus 14 days (max 500 rows),
  tasks 400 rows. Corrupt focus durations (`> 86400s` or negative) read as 0,
  matching the client's `FocusSession` policy.
* **Snapshots** — one `users/{uid}/health_history/{dayKey}` document per day,
  written by the HTTP endpoint only (read-only when Ziku needs context).

Weak areas merge `quiz_results.topicScores` with `mistakes` and sort
`high priority → lowest quiz average → most mistakes`. The weak-topic
threshold is imported from `weak_topic_service.DEFAULT_WEAK_THRESHOLD` so
Mistake Memory and Academic Health can never disagree.

---

## 3. Backend

### New files

* `backend/app/services/academic_health_service.py` (1020 lines)
  — signal collection, metrics, weak areas, advice, history/trend, snapshot,
  `get_recommendations()` (health rules + `ai_recommendation_service` merged,
  capped at 6, de-duplicated), `chat_context_line()`.
* `backend/app/routers/academic_health.py` — three `require_student` GETs.
* `backend/tests/test_academic_health.py` — **36 tests**.

### Modified

| File | Change |
| --- | --- |
| `app/main.py` | `include_router(academic_health.router, prefix="/api/ai", tags=["AI Academic Health"])` |
| `app/schemas.py` | `FocusStartRequest` += `subject`, `topic`; `FocusPatchRequest.action` += `interruption`, += `interruptions`, `subject`, `topic` |
| `app/routers/part3.py` | focus subject/topic on start, interruption action, `_focus_score` on complete, new `GET /study/focus/today`, extra fields on `focus/list` |
| `app/services/ai_service.py` | `build_chat_system_prompt(…, academic_health=…)`, `_academic_health_context(uid)` used by `chat_generate` |
| `tests/conftest.py` | `app.services.academic_health_service.get_firestore` → `FakeFirestore` |
| `firebase/firestore.rules` | `match /health_history/{dayKey}` — read for the owner, **no client writes** |

### Endpoints (all `require_student`, plain dict responses)

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/api/ai/academic-health` | `examDate` / `exam_date` both accepted; garbage → `400` |
| GET | `/api/ai/academic-health/history?days=` | 1-42, ordered by `dayKey` |
| GET | `/api/ai/academic-health/recommendations` | health rules first, then Ziku |
| GET | `/api/study/focus/today` | `seconds/minutes/planned/sessions/interruptions/focusScore/bySubjectMinutes` + separately `active*` for a running session |
| POST | `/api/study/focus/start` | stores and returns `subject`, `topic` |
| PATCH | `/api/study/focus/{id}` | `action: "interruption"` (409 unless running/paused), complete returns `focusScore` + `interruptions`, idempotent path returns the stored score |

Focus score: `round(min(actual/planned, 1) * 100 - 5 * interruptions)`, clamped
0-100; an unplanned session scores 100 for simply happening.

### Payload shape

```
score, grade, headline, hasData, generatedAt, dayKey,
trend{direction, delta, previousScore},
metrics[{key, label, weight, score, available, detail}],
signals{quizzes, study, mistakes, tasks, exam, ai},
weakAreas[{topic, quizAverage, mistakes, repeated, due, priority, action}],
recommendations[{title, reason, priority, source: health|ai}],
coverage[], missing[]
```

### Ziku integration

`chat_generate` now prepends one read-only line to the system prompt:

```
Current academic health: score 76/100, weakest topic Networking (44%),
2 mistake(s) due for revision, 95 min of deep work today, Physics final in 5 day(s).
```

`chat_context_line()` calls `get_academic_health(uid, persist=False)` — **no
snapshot write, no extra AI call, no quota** — and swallows every failure so a
chat message can never fail because scoring did. `build_chat_system_prompt()`
still works with no arguments (its language-policy contract is unchanged).

---

## 4. Flutter

### New

* `lib/features/profile/presentation/academic_health_card.dart` — Profile/Home
  entry: score dial, headline, trend badge, failure state. Read hook injected.
* `lib/features/profile/presentation/academic_health_screen.dart` — score card,
  the four metric rows, today's numbers (deep work / focus score / mistakes
  due), weak topics, merged advice, 7-day bar chart, **Ask Ziku** hand-off
  (`academicHealthZikuQuestion()` prefers the weakest topic).
* `lib/features/study/presentation/focus/focus_view.dart` — `SessionGroup` +
  `groupSessions()` (trims, case-folds, blank → "Focus session", skips
  `running`, sums seconds, latest `dayKey`, sorted by total) and a grouped
  history view.
* `test/academic_health_test.dart` — 13 tests.

### Modified

| File | Change |
| --- | --- |
| `lib/services/api_service.dart` | `getAcademicHealth`, `getAcademicHealthHistory`, `getAcademicHealthRecommendations`, `getFocusToday`, `startFocus(+subject/topic)`, `patchFocus(+interruptions/subject/topic)` — all query strings passed via `query:`, never inside the path literal |
| `profile_screen.dart` | `const AcademicHealthCard()` inside the existing `if (role == 'student')` block |
| `home_screen.dart` | `const AcademicHealthCard()` at the end of the Study-mode card list |
| `test/home_mode_filtering_test.dart` | Study cards 7 → 9 (+ `AcademicHealthCard`) |
| `test/exam_rescue_active_experience_test.dart` | Study cards 7 → 9 |

Design constraints honoured: no literal `Focus` in `home_screen.dart` (the card
says "deep work"), no banned strings added to `profile_screen.dart`, no
`AnimationController`, every `IconButton` keeps its tooltip, no `Color(0x…)`.

---

## 5. Verification

### Backend

```
pytest -q   →   681 passed, 9 failed
```

The 9 failures are `tests/test_ai_attachment.py` only — they were failing
before Phase 2 and are untouched by it. Phase 1's 674 passing tests still
pass; Phase 2 adds `tests/test_academic_health.py` with 36 tests (29 for the
score/history/recommendations/focus surface + 7 for the Ziku context).

### Flutter

```
dart analyze lib        → No issues found
flutter test            → 1249 passed, 90 failed
```

Baseline before Phase 2 was **1200 passed / 91 failed**. Phase 2 adds 13 new
tests and fixes the previously uncompilable `focus_session_test.dart`
(missing `focus_view.dart`) → 36 more passes, one fewer failing file. The 90
remaining failures are the pre-existing shell/nav, Today/StudentContext,
related-chips, planner-row and `profile_structure` Study Workspace failures —
none of them are Phase 2 files. Confirmed by diffing `profile_screen.dart`
against `HEAD`: the 4 `profile_structure` failures reproduce without any of
Phase 1/2's changes.

Guard suites green: `api_contract_test`, `ai_usage_screen_test`,
`learning_brain_test`, `home_mode_filtering_test`,
`exam_rescue_active_experience_test`, `focus_session_test`.

### Protected surfaces (all re-run)

| Surface | Guard |
| --- | --- |
| Exam Rescue | `exam_rescue_*` suites + card counts 7→9 updated |
| Ziku chat | `test_ai_assistant_and_usage.py` language-policy tests (prompt unchanged by default) |
| Mistake Memory | `learning_brain_test.dart`, `tests/test_mistake_memory.py` |
| AI Usage Dashboard | `ai_usage_screen_test.dart` (still no `revision` metric) |
| Today / Home | `cross_module_connections_test`, `today_command_center_test` (unchanged failure set) |

---

## 6. Follow-ups (not blocking)

1. The four `profile_structure_test` Study Workspace / Monthly Money failures
   and the `today_command_center` StudentContext ones pre-date this phase and
   want a separate fix.
2. `tests/test_ai_attachment.py` (9 failures) predates Phase 1.
3. `focus_view.dart`'s `FocusView` is currently only reachable by the tests —
   it is ready to be mounted wherever the app wants a grouped focus history.
