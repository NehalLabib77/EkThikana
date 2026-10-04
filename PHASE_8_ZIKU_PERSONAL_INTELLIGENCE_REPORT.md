# PHASE 8 - Ziku Personal Intelligence Layer

Ziku stops being five screens a student has to remember to open and becomes
one **Personal Academic Operating System**. The same five systems Phase 4-7
already read - Mistake Memory, the Real Exam Simulator, the Ziku Focus Engine,
the Learning Community and the Study Coach - are now collapsed into five
things a student actually sees: **Your Learning Journey** (the Academic
Memory Timeline), the **AI daily brief** (morning headings + evening recap),
the **Student Learning Profile**, one **next best action** ranked out of every
system at once, and an **achievement scoreboard**. Nothing here re-analyses:
the layer is an aggregator that reads, ranks and caches, and the client only
renders what it is handed.

## 1. What shipped

### Backend

* **`ziku_intelligence_service.py` (2006 lines)** - the whole Phase 8
  domain. `build_journey` (90-day, seven-stream timeline + up to 8
  improvement trends split at the window midpoint), `daily_brief` (morning
  block + evening recap + one AI reflection line), `learning_personality`
  (preferred study time, learning style, strong/weak subjects, evidence),
  `next_best_action` (five candidate systems ranked, winner + up to 4
  alternatives), `achievements` (16 bars across 4 categories with
  write-once earned stamps), and `chat_line` (one cached sentence for
  Ziku Coach's system prompt). It owns every constant: `TIMELINE_DAYS=90`,
  `MAX_TIMELINE_EVENTS=80`, `MAX_TRENDS=8`, `MAX_ALTERNATIVES=4`,
  `EVENING_HOUR=18`, `PHASES`, `ACHIEVEMENTS`, `ACHIEVEMENT_CATEGORIES`.
* **`routers/ziku.py` (118 lines, 5 routes)** - all `require_student`
  GETs with `force` (and `phase` on the brief); `_phase_or_400` returns a
  400 for an unknown phase instead of a 500.
* **`study_coach_service.chat_context`** now appends `ziku_intel.chat_line`
  (lazy import, try/except) *before* the mission-steps clause, so Ziku
  Coach knows what the Personal OS already concluded - and still ends its
  prompt with `step(s).` and still carries the Phase 7 group hotspot line.
* **`tests/test_ziku_intelligence.py` (849 lines, 29 tests)** - the 401 /
  student-only gate across all five paths, the journey (empty-but-well-formed,
  seven streams, trend direction, per-day cache, newest-first + capped),
  the brief (phase 400, morning headings, evening progress / mistakes /
  tomorrow, AI-silent fallback, AI line, cached), the personality (preferred
  time from sessions, strong/weak split, style pick, cache), the
  recommendation (all five systems, highest score wins, imminent exam,
  cache), the achievements (bars for a new student, the four kinds, first
  step earned, regression never un-earns, sharpshooter needs 10 quizzes),
  and the coach hand-off (line present / absent).
* **`firestore.rules`** - a Phase 8 section: `learning_journeys/{dayKey}`,
  `ziku_briefs/{dayKey}`, `learning_personalities/{docId}`,
  `next_best_actions/{dayKey}`, `learning_achievements/{docId}` - all
  `read: isStudent() && uid == owner`, all writes `if false`. The client
  never writes a cache or an earned stamp.

### Flutter

* **`learning_journey_screen.dart` (563)** - "Your Learning Journey":
  headline card with the window and the up/down trend counts, a three-up
  stat row (active days / study hours / streak), the improvement-trend rows
  (first → last, delta, "higher is better"), the timeline (day key, tone,
  value with unit), the weak-topic list, and four doors back into the
  Personal OS (profile, achievements, revision queue, focus block).
* **`learning_personality_screen.dart` (487)** - the Student Learning
  Profile: the earned label, preferred study time with its share and
  evidence sentence, the learning style, strengths vs watch-outs, five
  evidence rows (quizzes, focus, streak, mistakes, practice/community) and
  the strong/weak subject list.
* **`ziku_achievements_screen.dart` (418)** - the scoreboard: earned/total
  with one progress bar, per-category badges, a "Next up" card, then every
  achievement with its own bar, current/target and an `Earned` / `Locked`
  badge.
* **`coach_dashboard_screen.dart` (1034 → 1334)** - a sixth section,
  **Personal OS**: the daily brief card (morning `why` + health/mission
  badges, evening summary, reflection line, tomorrow) and the next-best-action
  card (source, title, detail, minutes/score, the coach's own action button
  for `review` / `quiz` / `focus` / `rescue`, and what else was considered),
  followed by three always-visible doors into the screens above. Both cards
  come from new optional `briefFn` / `actionFn` seams that default to
  `ApiService.zikuBrief` / `ApiService.zikuNextBestAction` and **fail
  silently**: a Phase 8 failure leaves three rows and nothing else moves.
* **`api_service.dart` (2269)** - the five Phase 8 reads after
  `familyLinks()`: `zikuJourney`, `zikuBrief`, `zikuProfile`,
  `zikuNextBestAction`, `zikuAchievements` - all `_guard` + `_get` with the
  query as a separate argument, so the contract test sees clean paths.
* **Tests - `test/ziku_personal_intelligence_test.dart` (722, 16)**.

## 2. Design

| Rule | Why |
| --- | --- |
| Aggregate, never re-analyse | Every block is a rule over data the five systems already own. A second analysis pass would drift from the coach the moment either side changed. |
| Cache before compute | The journey, the personality, the morning block and the recommendation are built once a day; only the evening half and the achievement bars rebuild on read, because they report *today*. |
| The one AI spend is one line | The evening reflection costs a single `AiFeature.CHAT` call per student per day, with `_fallback_reflection` when the key or the quota is missing - the brief never blanks out. |
| Never raise into a card | Every reader is wrapped. A broken system degrades one field of the payload; it never takes the layer down. |
| Earned stamps are write-once | Progress is recomputed every read, but an achievement is stamped only when a bar first fills. A streak that later breaks does not un-earn anything. |
| The client renders, the server decides | Timeline order, trend direction, style label, candidate ranking and progress are all computed server-side. The screens contain no scoring logic. |
| Personal OS is a decoration on the dashboard | The two new dashboard cards load in the background and fail silently. The mission above them is untouched, so a Phase 8 outage cannot break Phase 4. |
| Student-only, twice | `require_student` on every route *and* `firestore.rules` read guards. A journey, a brief and a scoreboard are built from scores and mistakes, so no `general` role may read one. |
| Every networked widget takes a seam | The three screens and the two new dashboard reads take typedefs and fall back to `ApiService` - which is why these tests open no socket. |

### Spec coverage

| Phase 8 ask | Where it lives |
| --- | --- |
| Academic Memory Timeline - "Your Learning Journey" | `build_journey` + `GET /api/ziku/journey` + `LearningJourneyScreen` (nine sections: headline, stats, trends, timeline, weak topics, four doors) |
| AI daily brief - morning headings, evening recap | `daily_brief` / `_morning_block` / `_evening_block` + `GET /api/ziku/brief` (`phase=auto\|morning\|evening`) + the dashboard brief card |
| Student Learning Profile | `learning_personality` + `GET /api/ziku/profile` + `LearningPersonalityScreen` |
| Smart Recommendation Engine (5 systems → next best action) | `_coach_candidate` / `_mistake_candidate` / `_exam_candidate` / `_focus_candidate` / `_community_candidate` → `next_best_action` + `GET /api/ziku/next-best-action` + the dashboard action card |
| Achievement System (4 kinds, real milestones) | `ACHIEVEMENTS` (16) + `achievements()` + `GET /api/ziku/achievements` + `ZikuAchievementsScreen` |
| Ziku behaves like an operating system, not a chatbot | `chat_line` → `study_coach_service.chat_context`, so the coach starts from what the OS already knows |

## 3. Backend

### New

| File | What |
| --- | --- |
| `app/services/ziku_intelligence_service.py` (2006) | The Phase 8 service layer - journey, brief, personality, recommendation, achievements, coach line |
| `app/routers/ziku.py` (118) | 5 student-only GETs + phase validation |
| `tests/test_ziku_intelligence.py` (849) | 29 tests across the whole layer |

### Modified

* `app/main.py` - `ziku` import + `app.include_router(ziku.router,
  prefix="/api/ziku", tags=["Ziku Intelligence"])` behind a Phase 8 comment.
* `app/services/study_coach_service.py` - `chat_context` (L1024-1033)
  inserts `ziku_intel.chat_line(uid)` before `steps = brief.get(...)`.
* `tests/test_role_gate_coverage.py` - `"/api/ziku"` added to
  `STUDENT_ONLY_PREFIXES`.
* `firebase/firestore.rules` - the Phase 8 section (five paths, student
  read, nobody writes).

### Endpoints

**`/api/ziku`** (`routers/ziku.py`, all `require_student`)

```
GET /journey             force      the 90-day timeline + improvement trends
GET /brief               phase,force  morning + evening + one AI reflection
GET /profile             force      preferred time, style, strong/weak
GET /next-best-action    force      five systems ranked: winner + alternatives
GET /achievements        force      16 bars, 4 kinds, write-once stamps
```

`force=true` is what the screens' `Refresh` affordance uses; otherwise the
journey, the morning brief, the personality and the recommendation are cached
for the day, and the evening half + the achievement bars rebuild on read.

### Database (collection -> what)

| Collection | Written by | Read by |
| --- | --- | --- |
| `learning_journeys/{dayKey}` | backend (once a day) | `GET /journey` |
| `ziku_briefs/{dayKey}` | backend (morning + reflection) | `GET /brief` |
| `learning_personalities/current` | backend (once a day) | `GET /profile` |
| `next_best_actions/{dayKey}` | backend (once a day) | `GET /next-best-action`, `chat_line` |
| `learning_achievements/current` | backend (earned stamps only) | `GET /achievements` |

All five are `allow read: if isStudent() && request.auth.uid == uid;`
`allow create, update, delete: if false;` - a modified APK can read its own
journey and can never write a cache, a ranking or an earned stamp.

**Reads that feed the layer (no new data of their own):** `quiz_results`,
`exam_results`, `mistakes`, `focus_sessions`, `weekly_reports`,
`academic_health`, `community_posts` / `community_reputation`, `groups` -
all through the services that already own them.

### Integrations

* `study_coach_service.chat_context` (L1024) -> `ziku_intelligence_service.chat_line`:
  one sentence about today's recommendation in Ziku Coach's prompt. The
  insertion sits before the mission-steps clause, so `endswith("step(s).")`
  and the Phase 7 group-hotspot assertion both still hold.
* The evening reflection spends the existing `AiFeature.CHAT` quota through
  `ai_service.generate` - no new usage category, so the AI Usage dashboard
  stays truthful.
* `next_best_action` reads `study_coach_service.weakness_analysis`,
  `mistake_memory`, `exam_pro_service`, `focus_service.goal_minutes` /
  `calc_streak` and `community_service.group_insights_data` - five systems,
  one ranking, one payload.
* Nothing in this phase calls Firestore with query-order assumptions: rows
  are streamed and sorted in Python, so the in-memory test double and the
  real backend agree.

## 4. Flutter

### New

| File | Lines | What |
| --- | --- | --- |
| `lib/features/study/presentation/planner/learning_journey_screen.dart` | 563 | `LearningJourneyScreen` + `JourneyFn` seam |
| `.../learning_personality_screen.dart` | 487 | `LearningPersonalityScreen` + `PersonalityFn` seam |
| `.../ziku_achievements_screen.dart` | 418 | `ZikuAchievementsScreen` + `AchievementsFn` seam |
| `test/ziku_personal_intelligence_test.dart` | 722 | 16 Phase 8 tests (3 source scans + 13 widget) |

### Modified

* `coach_dashboard_screen.dart` (1034 → 1334) - `ZikuBriefFn` /
  `ZikuActionFn` typedefs, `briefFn:` / `actionFn:` constructor seams,
  `_loadBrief` / `_loadAction` fired unawaited after `_refresh` with a
  silent catch, and the `_personalOsSection` (brief card + action card +
  three doors) inserted between the weekly report and the Ask Ziku card.
  **No existing section, string or finder changed.**
* `api_service.dart` (2198 → 2269) - the five Phase 8 reads (L2189-2258).

### Seams

Every Phase 8 read is injectable: `LearningJourneyScreen(journeyFn:)`,
`LearningPersonalityScreen(profileFn:)`,
`ZikuAchievementsScreen(achievementsFn:)`, and
`CoachDashboardScreen(briefFn:, actionFn:)` - each falling back to its
`ApiService` method as a plain tear-off. That is why all 16 tests open no
socket, and why a failed Phase 8 read in a widget test renders the standard
`AiErrorBanner` + `Try again` instead of hanging.

## 5. Verification

### Backend (`cd backend && .venv\Scripts\python.exe -m pytest -q`)

```
9 failed, 871 passed, 2 warnings in 22.08s
```

* `tests/test_ziku_intelligence.py`: **29 passed** (1.65s).
* The 9 failures are the pre-existing `tests/test_ai_attachment.py` set
  (identical before this phase).
* Baseline Phase 7: `9 failed, 842 passed` -> **`9 failed, 871 passed`**
  (+29 = exactly the new Phase 8 suite), zero new failures.
* `tests/test_role_gate_coverage.py` and `tests/test_community.py` (the
  coach-line assertions) are inside the 871.

### Flutter (`cd flutter_app`)

```
dart analyze lib                                 -> No issues found!
dart analyze test/ziku_personal_intelligence_test.dart -> No issues found!
flutter test                                     -> 1352 passed, 90 failed
```

* `test/ziku_personal_intelligence_test.dart`: **16 passed** - the five
  route paths and the five `ziku*` methods, the dashboard's two Phase 8
  reads and its three doors, the Home freeze (`Your Learning Journey`,
  `Student Learning Profile`, `Personal OS`, `Next best action`, `Achievements`
  all absent from `home_screen.dart`), plus widget coverage of the journey
  (empty sentence, headline/trends/timeline/weak topics, failed read,
  door navigation), the profile (label, preferred time, evidence,
  strong/weak, empty state, failed read), the scoreboard (counts,
  categories, bars, Earned/Locked, empty state, failed read) and the
  dashboard section (brief + action + doors rendered, Phase 8 failure
  leaves exactly three doors with **no** error banner, doors open the
  pushed screens).
* Baseline Phase 7: **1336 passed / 90 failed** -> **1352 passed / 90
  failed**: +16 new tests. The 90 failing tests are *identical* to
  baseline - compared test by test from the runner's `[E]` lines (90
  unique on both sides, `Compare-Object` empty). No regression.
* Protected surfaces re-run inside the same full run and unchanged:
  home banned-word scan and the 15-item study list (Phase 8 added **no**
  Home entries), translation smoke, API contract scan (the five `/api/ziku`
  paths are picked up automatically), theme parity, accessibility audit,
  physical-defects regression, `ziku_coach_test` (the dashboard's new
  section is additive: `76`, `Optics` and `Ask Ziku` still each find one
  widget).

## 6. Follow-ups (not blocking)

1. **Journey date range picker** - the timeline is fixed at the 90-day
   window and the newest 80 events. `force` already exists, so a
   "load earlier" affordance is client-only once the payload exposes a
   cursor.
2. **Brief phase switch in the UI** - the API accepts `phase=auto|morning|
   evening` and always returns both halves; the dashboard card shows the
   resolved phase but does not yet offer a manual morning/evening toggle.
3. **Recommendation destinations** - the action card reuses the coach's
   action buttons for `review`, `quiz`, `focus` and `rescue`; `community`
   (join/ask your group) currently renders without a button even though the
   destination exists in the Community tab.
4. **Achievement sharing** - the scoreboard is read-only today. A share
   sheet would need a rendered card (client-side) rather than a shared link,
   since the collection is student-read-only.
5. **Personality history** - `learning_personalities/current` keeps one
   profile. Watching the label change over a term needs either a per-day
   path (the rules already cover `{docId}`) or a client-side log.
