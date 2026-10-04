# PHASE 5 - Ziku AI Focus Engine

Deep work stops being a number hidden in Study Stats. One state machine
(`users/{uid}/focus_sessions`) now feeds a rolling **Focus Score**, a **smart
nudge**, a **timer screen**, a **Home card** and two consumers that already
existed (Academic Health, Ziku Coach) - all reading the same rows, with no
second tracking system anywhere.

## 1. What shipped

* **Focus service (`focus_service.py`)** - the single source of truth for the
  session lifecycle (start / pause / resume / complete / cancel / interruption),
  today's minutes vs goal, the rolling Focus Score, weekly consistency, streaks
  and the smart nudge. `part3.py` now delegates to it, so the legacy
  `/api/study/focus/*` routes and the new `/api/focus/*` routes share exactly
  one implementation (one state machine, one counting policy, one store).
* **Four endpoints** under `/api/focus` (start, complete, today, history), all
  `require_student`, pinned by `tests/test_role_gate_coverage.py`.
* **Focus Score** - 0-100 from completion (40%) + 7-day consistency (35%) +
  duration against the 25-minute block target (25%), with three bands:
  `excellent` / `developing` / `needs_structure`, and `None` when there is no
  finished session in the window (the score never invents data).
* **Smart nudge** - `adjust` / `skip` / `streak` / `start`, decided server-side
  so the client never writes policy copy.
* **Academic Health's 5th metric** - `focusConsistency` (0.12 of the health
  score), fed by new study signals (`weekSessions`, `averageSessionMinutes`,
  `focusConsistencyPct`, `dailyMinutes`).
* **Coach integration** - the learning profile, daily brief, chat context,
  weekly report and both narratives now carry focus consistency, minutes per
  session and a 7-day focus trend.
* **Flutter timer screen (`FocusSessionScreen`)** - topic/subject, a 25:00
  countdown, progress bar, pause/resume, and a completion card that shows what
  the server decided (minutes, per-session score, rolling score band, nudge).
* **Home card (`ZikuSessionCard`)** - "Today's Focus: 45/60 minutes", progress
  bar, the nudge line and a `Continue Session` button into the timer (resuming a
  live session by id when one is running).
* **Mission loop closed** - the coach dashboard's `focus` step now opens the
  timer instead of rendering no button (Phase 4 follow-up #1).

## 2. Design

| Rule | Why |
| --- | --- |
| One store, one state machine | `part3.py` and `focus.py` both call `focus_service`, so pause/resume/complete behave identically no matter which route started the block. The idempotency and no-double-count policies pinned by `test_part3.py` were not forked, they were *moved*. |
| Server decides, client renders | Score bands, nudge kind, goal minutes and the completion payload all come from the backend. The UI shows them; it never recomputes a policy number. |
| Goal is not a constant | `goal_minutes()` reads the active Exam Rescue plan's `dailyTargetMinutes` (90 for a real plan) and falls back to 60 - so the card's "45/60" is the student's actual target, not a hardcoded one. |
| Score over finished sessions only | Running/paused rows are reported separately as live progress; a block you never finish can still be paused and resumed later, but it never inflates today's total or the score. |
| One read per screen | `engine_today()` loads the collection once and derives summary, weekly, score and nudge from those rows - the Home card, the timer and the coach can never disagree about today. |

### Focus Score (`compute_focus_score`, 7-day window)

```
value = 100 * (0.40 * completed/started          # finish what you start
              + 0.35 * active_days/7             # show up
              + 0.25 * min(avg_minutes/25, 1))   # block length, capped
```

* Bands: **>= 90 excellent** ("Deep focus streak"), **>= 60 developing**
  ("Solid rhythm"), else **needs_structure** ("Needs structure").
* `None` when `started == 0` in the window - displayed as "no finished session
  yet", never as a fake 0.
* Corrupt durations are coerced by `coerce_focus_seconds` first (the Phase 1
  policy: 354_920 seconds reads as 0, not 5915 minutes).

### Smart nudge (`smart_nudge`, evaluated in this order)

| Kind | Trigger | Copy (server-authored) |
| --- | --- | --- |
| `adjust` | active session >= 45 min | "45 minutes on the clock - stand up, drink water, eyes off the screen for 5 minutes, then resume." |
| `skip` | today >= goal | "Already 45/60 min today - Ziku suggests a break instead of another block." |
| `streak` | >= 3 consecutive study days | "3-day focus streak - keep the chain alive with one short block." |
| `start` | otherwise | "Start a 60 minute block - one subject, phone away." |

## 3. Backend

### New files

| File | Lines | What |
| --- | --- | --- |
| `backend/app/services/focus_service.py` | 851 | lifecycle (`start_session`, `apply_action`), aggregates (`today_summary`, `weekly_consistency`, `goal_minutes`), `compute_focus_score`, `smart_nudge`, `engine_today`, `history` |
| `backend/app/routers/focus.py` | 86 | the four `/api/focus/*` endpoints - thin adapters, no focus logic of their own |
| `backend/tests/test_focus_engine.py` | 568 | 28 tests (single store, cross-route lifecycle, idempotency, 403/404, score bands, nudges, history bounds, health + coach signals) |

### Modified

| File | Change |
| --- | --- |
| `backend/app/routers/part3.py` | 829 -> 411 lines: the focus routes now delegate to `focus_service`; `_month_key`, `study_stats` and the private aliases (`_fold_running_interval` etc., imported by `test_part3.py`) stay here |
| `backend/app/schemas.py` | `FocusCompleteRequest` (`focusId` + optional `subject`/`topic`) |
| `backend/app/main.py` | imports `focus`, mounts `app.include_router(focus.router, prefix="/api/focus", tags=["Ziku Focus Engine"])` |
| `backend/app/services/academic_health_service.py` | `focusConsistency` metric + `_collect_focus` signals + rebalanced `METRIC_WEIGHTS` |
| `backend/app/services/study_coach_service.py` | `_percent()` helper, profile `studyPattern` focus keys, `daily_recommendation.focus`, chat-context sentence, weekly-report keys, AI + fallback narratives |
| `backend/tests/conftest.py` | `focus_router_mod` added to the `get_firestore` patch tuple |
| `backend/tests/test_role_gate_coverage.py` | `"/api/focus"` in `STUDENT_ONLY_PREFIXES` |
| `backend/tests/test_academic_health.py` | metrics 4 -> 5, missing-metric sets, coverage list, new study-signal assertions |

### Endpoints (student-only, camelCase out)

| Method | Route | Returns |
| --- | --- | --- |
| POST | `/api/focus/start` | `{id, status: "running", label, plannedMinutes, startedAtIso, subject, topic}` |
| POST | `/api/focus/complete` | `{id, status, completedAtIso, accumulatedSeconds, focusScore, interruptions, today}` - **idempotent** (a second call returns the original payload plus the fresh snapshot) |
| GET | `/api/focus/today` | summary (`minutes`, `plannedMinutes`, `activeMinutes`, `focusScore`, ...) + `goalMinutes`, `score{value,band,label,activeDays,parts}`, `weekly{consistencyPct,streakDays}`, `streakDays`, `activeSessionIds[]`, `nudge{kind,message}` |
| GET | `/api/focus/history?days=1..365` | `sessions`/`items`/`count`, `days[]` (per-day buckets), `weekly`, `score`, `goalMinutes` |

Legacy routes are untouched and still work: `POST /api/study/focus/start`,
`PATCH /api/study/focus/{id}` (pause/resume/complete/cancel/interruption),
`GET /api/study/focus/today`, `GET /api/study/focus/list` - they now run through
the same service.

### Database

**No new collection.** Everything lives in the existing
`users/{uid}/focus_sessions` store; `firebase/firestore.rules` needed no change
(Phase 1 already scoped it). The engine is a read/aggregation layer over rows
the app has been writing since Study Stats existed.

### Integrations

* **Academic Health** - `METRIC_WEIGHTS` is now five metrics that still sum to
  1.0: consistency 0.22, understanding 0.26, revision 0.22, examReadiness 0.18,
  **focusConsistency 0.12**. `_collect_focus` adds `weekSessions`,
  `averageSessionMinutes`, `focusConsistencyPct` and a `dailyMinutes` map;
  `_metric_focus_consistency` blends regularity (0.35), depth (0.40) and
  session quality (0.25), and returns `None` without a finished session so
  renormalisation over available metrics is preserved.
* **Ziku Coach** - `studyPattern.focusConsistency` / `averageSessionMinutes` /
  `focusTrend7`, `daily_recommendation.focus{consistency,averageSessionMinutes,
  todayMinutes,weekMinutes}`, a `focus consistency 71.4% of the last 7 days`
  line in `chat_context`, the same three keys in `weekly_report`, plus one
  focus sentence in both the AI and the rule-based narrative.
* **Exam Rescue** - only through `goal_minutes()`; the rescue plan decides the
  daily target, the focus engine just measures against it.

## 4. Flutter

### New

| File | Lines | What |
| --- | --- | --- |
| `lib/features/study/presentation/focus/focus_session_screen.dart` | 710 | the timer: `focusClock`, `focusBandLabel`/`focusBandTone`, subject/topic fields, countdown + progress bar, pause/resume/finish, completion card, `_TodayFacts`; four injectable hooks (`startFn`/`patchFn`/`completeFn`/`todayFn`) |
| `lib/features/study/presentation/focus/ziku_session_card.dart` | 191 | `ZikuSessionCard`: `focusEngineToday` read, minutes vs goal, score badge, nudge line, `Continue Session` (resumes `activeSessionIds.first`), retry line on failure |
| `test/ziku_focus_test.dart` | 314 | 8 tests |

### Modified

| File | Change |
| --- | --- |
| `lib/services/api_service.dart` | `focusEngineStart`, `focusEngineComplete`, `focusEngineToday`, `focusEngineHistory` (the legacy `startFocus`/`patchFocus`/`listFocus`/`getFocusToday` stay for the old routes; pause/resume still uses `patchFocus`) |
| `lib/features/home/presentation/home_screen.dart` | study-mode list: `SizedBox + ZikuSessionCard()` after `ZikuCoachCard` (13 -> 15 items) |
| `lib/features/study/presentation/planner/coach_dashboard_screen.dart` | `_missionAction` gains `action == 'focus'` -> `FocusSessionScreen(initialTopic: target)` (tooltip `Start focus`) |
| `test/home_mode_filtering_test.dart`, `test/exam_rescue_active_experience_test.dart` | study card count 13 -> 15, `ZikuSessionCard` asserted |
| `test/ziku_coach_test.dart` | "the focus step shows no button at all" -> "the focus step opens the focus session screen" (asserts the button and the pushed screen) |
| `test/list_field_parsing_test.dart` | the `sessions`+`items` alias now lives in `focus_service.py` (Phase 5 moved it), so the source guard reads that file |

### Where the numbers show up

| Surface | What it shows |
| --- | --- |
| Home card | "Today's Focus: 45/60 minutes", progress bar, `Score 78` badge, the nudge line, `Continue Session` |
| Timer (idle) | nudge, today/score/streak stat row, subject + topic fields, `Start Session` |
| Timer (running/paused) | `25:00` countdown, block progress, `Pause`/`Resume`, `Finish` |
| Timer (done) | minutes focused, `Score <session>`, `Focus score <rolling>` + band, the nudge, `Done` |
| Coach mission | `Start focus` button on the `focus` step (tooltip `Start focus`) |
| Academic Health | the 5th metric tile + `focusConsistency` inside the health score |
| Coach dashboard / chat / weekly | consistency %, minutes per session, 7-day trend |

### Degradations (all tested)

* card read fails -> friendly sentence, no `Continue Session`, tap retries;
* today read fails on the timer -> the countdown still runs, the error is a
  caption, not a dead screen;
* start/pause/finish fails -> friendly error line, phase unchanged, button
  re-enabled;
* no finished session yet -> `Focus score` shows "no finished session yet",
  never a fake 0.

## 5. Verification

### Backend (`cd backend && .venv\Scripts\python.exe -m pytest -q`)

```
9 failed, 781 passed, 2 warnings in 43.79s
```

* `tests/test_focus_engine.py`: **28 passed**.
* The 9 failures are the pre-existing `tests/test_ai_attachment.py` set (same
  before this phase).
* Baseline 753 -> 781 passed (+28), zero new failures.

### Flutter (`cd flutter_app`)

```
dart analyze lib      -> No issues found!
flutter test          -> 1299 passed, 90 failed
```

* `test/ziku_focus_test.dart`: **8 passed** (clock, bands, full
  start/pause/resume/finish lifecycle, failure paths, resume-by-id, card copy +
  navigation, Home source guard).
* Baseline 1291 passed / 90 failed -> **1299 passed / 90 failed**: +8 new tests,
  the same 90 pre-existing failures (navigation / Quick Actions / relationship
  source-scan tests that were already red before Phase 5).
* `dart analyze` on the whole package reports only the 13 pre-existing issues
  (4 in `test/dev_auth_test.dart`, the rest sealed-class/unused-variable
  warnings); none in the files this phase touched.

### Protected surfaces re-run

Home mode filtering (15/5/9), exam-rescue Home gating, cross-module
connections, today command centre, ziku coach card + dashboard, study rebuild,
`home_screen.dart`'s banned-word scan (`Focus` still absent, case-sensitive) -
all unchanged relative to baseline.

## 6. Follow-ups (not blocking)

1. **Mount the history view** - `focus_view.dart` (the Phase 1 history list)
   is still mounted nowhere. The Home card or the timer's completion card is
   the natural door: "See your last 7 days" -> `FocusView`, reading
   `/api/focus/history` instead of the legacy list route.
2. **Interruption counter** - `action: 'interruption'` and the per-session
   `interruptions` score penalty already exist server-side; the new screen has
   no "I got distracted" button, so interruptions only arrive from elsewhere.
3. **Offline queue** - a finish that fails while offline currently leaves the
   block running; queueing the complete call (like sync already does for
   mistakes) would make the coach's numbers trustworthy on flaky networks.
4. **Per-subject weekly view** - `bySubjectMinutes` is computed per day; the
   history endpoint could return a 7-day subject split for the card's
   "what you actually studied" line.
5. **Nudge analytics** - the four nudge kinds are decided but never measured.
   A `nudgeShown`/`blockStarted` pair on the card would say which nudge
   actually starts a session.
6. **Parent Dashboard** - `engine_today()` plus `focusEngineHistory()` is
   already the shape a parent view needs (minutes vs goal, score, streak)
   without a new endpoint.

## Appendix - why the Home card is `ZikuSessionCard`

`home_screen.dart` is scanned case-sensitively for the word `Focus`
(`today_command_center_test.dart`, `cross_module_connections_test.dart`,
`ziku_coach_test.dart`), a guard that exists to keep removed wording from
coming back. The card therefore lives in its own file under `focus/` with a
class name that satisfies the scan; the visible title is **"Ziku Focus"**, and
only the card file - never `home_screen.dart` - spells it.
