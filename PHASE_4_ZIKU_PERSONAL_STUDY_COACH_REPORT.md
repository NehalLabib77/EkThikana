# PHASE 4 - Ziku Personal Study Coach

Ziku stops being a chatbot you have to prompt. The coach reads what Phase 1-3
already produced (Mistake Memory, Academic Health, Exam Rescue, the Real Exam
Simulator, quiz mastery), decides what matters **today**, and puts one card on
Home, one dashboard behind it, and one line inside every Ziku answer.

## 1. What shipped

* **Home card (`ZikuCoachCard`)** - greeting, Academic Health number, today's
  priority with the *reason* behind it, the mission as a checklist, and one
  `Start Mission` button into the dashboard.
* **Coach Dashboard (`CoachDashboardScreen`)** - health + exam readiness, today's
  mission with a real destination per step, weak/strong topics, study pattern,
  recent improvement, the weekly report (AI paragraph + rule-based fallback) and
  a one-tap hand-off into Ziku with a question built from the priority topic.
* **Four backend endpoints** under `/api/coach` (profile, daily, weekly-report,
  recalculate), all `require_student`, all cache-first.
* **Ziku chat context** - the system prompt now carries a `Personalised plan:`
  line (health score, today's focus, exam countdown, mission size) so the
  assistant answers with the student's real plan in hand.
* **Live recommendations** - saving a quiz result fires `POST /api/coach/recalculate`
  so the profile and today's mission rebuild instead of staying stale until
  tomorrow.
* **Security** - the three cache collections are student-read, backend-write
  only (`firebase/firestore.rules`); `/api/coach` is pinned to students in
  `tests/test_role_gate_coverage.py`.

Nothing in this phase recomputes a score, re-derives mastery or writes to a
collection another service owns.

## 2. Coach design

| Rule | Why |
| --- | --- |
| Aggregator, not an analytics engine | Academic Health owns the score, Mistake Memory owns repetition, `weak_topic_service` owns mastery, Exam Rescue owns the countdown. The coach only reads them (`persist=False`, so opening the coach never writes a `health_history` snapshot). |
| Offline first | Profile, weakness tiers and the daily mission are pure rules: they work with no AI key and cost no quota. |
| AI once per week | Only the weekly narrative is AI-authored; a failure caches the rule-based sentence instead of retrying on every open. |
| Cache before compute | Chat asks for context on every message, so `chat_context()` reads today's cache first and only builds after the day rolls over. |
| Never raise into chat | Every reader is wrapped: a broken subsystem degrades the advice, it never takes the assistant down. |

### Weakness tiers (`weakness_analysis`)

* **high** - an urgent gap (repeated mistake or overdue revision) **and** an exam
  inside 14 days.
* **medium** - an urgent gap without a near exam, or a quiz average below 60.
* **low** - an old gap that is no longer repeating and no longer scoring badly.
* A topic the quiz engine calls strong is filtered out first, so a live gap
  never sits under a topic that is already fine.
* Reasons are ordered exam → repeated → overdue → recorded → quiz average, and
  capped at three, because the tier is decided by the exam, not the tally.

### Daily mission (`daily_recommendation`)

At most four steps, built from the top priority only:

1. `rescue` - only with an active Exam Rescue plan inside its final week
   (carries the plan's own daily target minutes);
2. `review` - the top gap;
3. `quiz` - 20 MCQ inside the last week before an exam, otherwise 15;
4. `focus` - a 25 minute block, always present, so a student with no signal
   still gets something to do.

If there is no priority at all the mission keeps the focus step and the `why`
explains that (no urgent gaps / take one quiz).

## 3. Backend

### New files

| File | Lines | What |
| --- | --- | --- |
| `backend/app/services/study_coach_service.py` | 947 | `build_learning_profile`, `weakness_analysis`, `daily_recommendation`, `weekly_report` (async), `recalculate`, `chat_context` |
| `backend/app/routers/coach.py` | 69 | the four endpoints, all `require_student` |
| `backend/tests/test_study_coach.py` | 722 | 27 tests (auth gate, caching, tiers, mission rules, AI fallback, chat context) |

### Modified

| File | Change |
| --- | --- |
| `backend/app/main.py` | imports `coach` and mounts `app.include_router(coach.router, prefix="/api/coach", tags=["AI Study Coach"])` |
| `backend/app/services/ai_service.py` | `_coach_context(uid)`, new `coach_context=` parameter on `build_chat_system_prompt`, the `Personalised plan: ...` line, passed from `chat_generate` |
| `backend/tests/conftest.py` | patches `study_coach_service.get_firestore` (and `weak_topic_service.get_firestore`, which fixed an import-order staleness: readers now share the active fake DB instead of the first test's frozen one) |
| `backend/tests/test_role_gate_coverage.py` | `/api/coach` in `STUDENT_ONLY_PREFIXES` (401 without auth, 403 for a non-student) |
| `firebase/firestore.rules` | student read, no client write for the three collections below |

### Endpoints (student-only, camelCase out, `?force=true` rebuilds the cache)

| Method | Route | Returns |
| --- | --- | --- |
| GET | `/api/coach/profile` | the learning profile (cached per day) |
| GET | `/api/coach/daily` | today's brief: greeting, health, priority, mission, exam |
| GET | `/api/coach/weekly-report` | the 7-day report (async, AI narrative) |
| POST | `/api/coach/recalculate` | `{profile, daily, recalculatedAt}` - force rebuild |

### Database

Three collections, one doc shape each, all under `users/{uid}/`:

| Collection | Doc id | Contents | Written by |
| --- | --- | --- | --- |
| `learning_profiles` | `current` | health score/grade/headline, trend, weak/strong topics, repeated/due totals, quiz average, `studyPattern`, `examReadiness`, `upcomingExam` | backend (daily) |
| `daily_coach_recommendations` | ISO day (`2026-10-02`) | `greetingKey`, `healthScore`, `priority{topic,why,reasons[],mistakes,occurrences,repeated,due,quizAverage}`, `why`, `mission[≤4]`, `exam` | backend (daily) |
| `weekly_reports` | ISO week (`2026-W40`) | window totals, `scoreDelta`, `improvement[]`, weak/strong area, `recommendation`, `narrative`, `aiGenerated` | backend (weekly) |

Reads are `allow read: if isStudent() && request.auth.uid == uid;` and
`allow create, update, delete: if false;` - a client can never hand itself a
kinder recommendation.

### Ziku chat context

`chat_context(uid)` is cache-first and read-only. It returns e.g.

```
Study coach: Academic Health 56/100; today's focus is Optics (6 mistake(s),
1 repeated, quiz average 40%); Physics Final in 5 day(s); mission has 4 step(s).
```

and `None` when there is no signal at all (an empty profile with no priority
would otherwise put "mission has 1 step" in every message). In
`build_chat_system_prompt` it is appended as
`Personalised plan: {context} Use it to steer the advice and to open with what
matters today...` - the "Never reply in Banglish" policy is untouched.

## 4. Flutter

### New

| File | Lines | What |
| --- | --- | --- |
| `lib/features/study/presentation/planner/ziku_coach_card.dart` | 302 | the Home card (injected `briefFn` → `ApiService.coachDailyBrief`, `onOpenPlan`, `friendlyErrorMessage` fallback, `coachGreeting` / `coachZikuQuestion` helpers) |
| `lib/features/study/presentation/planner/coach_dashboard_screen.dart` | 1021 | the dashboard: health, mission, topics, pattern, improvement, weekly report, Ask Ziku; three injectable readers + `onOpenPlan` |
| `test/ziku_coach_test.dart` | 604 | 18 tests |

### Modified

| File | Change |
| --- | --- |
| `lib/features/home/presentation/home_screen.dart` | study-mode card list: `ZikuCoachCard(onOpenPlan: onOpenDestination)` after `ExamSimulatorCard` (11 → 13 items) |
| `lib/features/study/presentation/ai/quiz_result_screen.dart` | after a real save, fire-and-forget `ApiService.coachRecalculate()` (skipped when `saveResultFn` is injected, so tests never POST) |
| `lib/services/api_service.dart` | the four coach readers (`coachProfile`, `coachDailyBrief`, `coachWeeklyReport`, `coachRecalculate` + `fetchCoachDailyBrief` / `fetchCoachWeeklyReport`) |
| `test/home_mode_filtering_test.dart`, `test/exam_rescue_active_experience_test.dart` | study card count 11 → 13, `ZikuCoachCard` asserted |

### Mission steps and where they go

| Step | Destination |
| --- | --- |
| `review` | `LearningBrainScreen` |
| `quiz` | `QuizGeneratorScreen(initialTopic: <priority topic>)` |
| `rescue` | pops the dashboard and switches the shell to the Plan tab (`onOpenPlan(2)`); no button when no shell callback is available |
| `focus` | **no button** - there is no focus-session screen mounted in the app today, and a button that goes nowhere is worse than a line in a plan |

### Degradations (all tested)

* card read fails → friendly sentence, no `Start Mission`;
* profile read fails → `AiErrorBanner` + `Try again`;
* weekly narrative fails → inline `Retry report`, the mission above it still works;
* `hasData == false` → empty state, mission still rendered (the focus step
  keeps the screen useful on day one).

## 5. Verification

### Backend (`cd backend && .venv\Scripts\python.exe -m pytest -q`)

```
9 failed, 753 passed, 2 warnings in 19.56s
```

* `test_study_coach.py`: **27 passed**.
* The 9 failures are the pre-existing `tests/test_ai_attachment.py` set (same
  before this phase).
* Baseline 726 → 753 passed (+27), zero new failures.

### Flutter (`cd flutter_app`)

```
dart analyze lib      → No issues found!
flutter test          → 1291 passed, 90 failed
```

* `test/ziku_coach_test.dart`: **18 passed** (card, dashboard, mission routing,
  degradations, source guards).
* Baseline 1273 passed / 90 failed → 1291 passed / 90 failed: **+18 new tests,
  the same 90 pre-existing failures** (navigation/Quick Actions/relationship
  source-scan tests that were already red before Phase 4).
* `dart analyze` on the three files touched here reports no new issues.

### Protected surfaces re-run

Home mode filtering, exam-rescue Home gating, cross-module connections, today
command centre, profile structure, accessibility audit - all unchanged relative
to baseline.

## 6. Follow-ups (not blocking)

1. **Focus session screen** - `focus_view.dart` exists but is mounted nowhere,
   so the mission's focus step has no button. Mounting it (and routing
   `action == 'focus'` to it) is the single highest-value follow-up.
2. **Exam / rescue completion** - quiz save already triggers `recalculate`;
   finishing a practice exam and editing an Exam Rescue plan should call it too.
3. **Backend-authored English** - `why`, mission titles/details, weakness
   reasons and metric labels arrive in English (same as Phase 2's `weakAreas`).
   Localising them server-side would complete the EN/BN parity for this screen.
4. **Weekly metric labels** - `improvement[].label` comes from
   `health.METRIC_LABELS`; a Bengali map would let the movement rows speak the
   student's language.
5. **Next surfaces for the same data** - the profile payload is already shaped
   for a Parent Dashboard view, for AI Study Groups (share a mission, not a
   score) and for Career Guidance (sustained strong topics over a term).
