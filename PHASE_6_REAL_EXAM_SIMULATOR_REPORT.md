# PHASE 6 - Ziku Real Exam Simulator Pro

The simulator stops being a room you can only enter with an AI paper. Any
paper can now be built by hand, sat under real-exam conditions (marks on
screen, pause only when the builder allowed it, progress written back to the
server while the clock runs), scored with negative marking, and reviewed
afterwards through the same Mistake Memory / Academic Health / Ziku Coach
path the quiz uses - with **"My Exams"** as the home for every past sitting
and a share code that hands out a paper without ever handing out marks.

## 1. What shipped

* **`exam_pro_service.py` (501 lines)** - the Phase 6 half of the exam
  domain: `save_progress`, `pause_attempt` / `resume_attempt`, `history`
  (with the `improvement` line), `latest_result`, `set_visibility` /
  `get_shared` (the share code), and `_hall_payload` (a resume payload in
  the exact shape `start_attempt` already returns, plus `status`,
  `resumed`, `remainingSeconds`, `savedAnswers`, `markedForReview`).
* **Eight routes** on the existing `exams` router - `GET /list`,
  `GET /history`, `GET /shared/{code}`, `GET /{id}/result`,
  `POST /{id}/save | pause | resume | share` - all `require_student`,
  all declared before `GET /{exam_id}` so the path parameter cannot swallow
  them (pinned by `static_paths_are_not_swallowed_by_the_path_parameter`).
* **Manual source (spec 6.1/6.2)** - `create_exam` now accepts
  `source: "manual"` with hand-typed question drafts in the same
  `{question, options[], correct, ...}` shape the upload parser produces,
  so one correction UI serves both paths. `allowPause` travels on the exam
  document and out through every public fetch.
* **"Careless mistake" wording (spec 6.6)** - the analysis now labels the
  third mistake type "Careless mistake" (storage key `memory` untouched, so
  every Phase 1 test and every existing row still matches).
* **Pro hall (`RealExamScreen`, 766 lines)** - the Phase 3 room with the
  spec's controls: `Question n / total` counter, `Marks: +1` /
  `Wrong: -0.25` badges beside the question, save-on-answer / flag / move
  and every 15 seconds (`answers + markedForReview + remainingSeconds`),
  pause (frozen clock, saved answers, resume button) and resume against the
  **server-rewritten deadline**, expired-resumed attempts auto-submitting
  at 0:00. `ExamHallScreen` is now a typedef alias of it - one room, every
  Phase 3 route and test intact.
* **Builder upgrades (`ExamSetupScreen`)** - `Exam title (optional)`, a
  fourth source **"Write your own"** (seeds blank rows in the correction
  editor), the **Pause exam Allowed / Not allowed** setting sent as
  `allowPause`, and a `My exams` app-bar action into the history list.
* **Correction editor upgrades (`ExamUploadScreen`)** - `manual` +
  `initialDrafts` (opens ready to type, app bar "Write your own") and an
  **Add question** button under the drafts list.
* **"My Exams" (`ExamHistoryScreen`, 369 lines)** - the student's own
  papers newest first, score badges, the `Improvement: +8%` stat beside the
  average, tap-through to `ExamResultScreen` for that attempt, an empty
  state, and a row menu **Share paper** that hands out the share code with
  the privacy line spelled out: *the paper travels, never your scores*.
* **Coach rebuild after an exam (spec 6.8)** - the result screen fires one
  background `coachRecalculate()` when a submit payload arrives on the real
  backend path (same contract as the quiz result screen; injected analysis
  seams and failures are ignored).
* **Seven API methods** - `resumeExam`, `saveExamProgress`, `pauseExam`,
  `examHistory`, `getExamResult`, `shareExam`, `getSharedExam` - written to
  the Phase 3 discipline (no `?` on any `_get(`/`_post(` line).
* **Tests** - `tests/test_exam_pro.py` (25) and
  `test/exam_pro_test.dart` (12).

## 2. Design

| Rule | Why |
| --- | --- |
| One room, two names | `ExamHallScreen` is a typedef of `RealExamScreen`, so Phase 3's routes, injection seams and tests run against the Pro implementation. A second hall would have forked the clock, the submit path and the no-answer-key guarantee. |
| The server owns the clock | Pause freezes `remainingSeconds` server-side and resume rewrites `deadlineAt`; the phone only counts down what the deadline says. A paused wall clock on the device would desync the moment two devices open the same attempt. |
| Save is a safety net, never a blocker | A failed save is swallowed (the submit still carries everything); pause saves first, then freezes; the periodic save runs on a `Timer.periodic` cancelled in `dispose()`. |
| Resume first, start second | The hall tries `resume` (404 or "no backend session yet" -> fresh start, any other verdict surfaced). Starting over an attempt the server still holds would orphan saved answers - the one case we refuse to paper over. |
| Sharing is read-only and answer-free | The share code is `base64url(uid|examId)`, defaults to `private`, and `GET /shared/{code}` returns redacted questions only: no answers, no scores, no attempts, no owner id. Personal marks can only ever leave the device through the student's own history read. |
| No duplicate scoring, no duplicate AI | Score, accuracy, time verdict, weak topics, mistake types and review dates still come from Phase 3's `get_analysis`; the phone renders them. AI Usage is untouched (quota is already spent through `AiFeature`; adding an activity type would have perturbed the usage dashboard). |
| Mistake Memory keys unchanged | Only the human label moved ("Careless mistake"); the storage type stays `memory`, so Phase 1 tests and every existing row keep matching. |

### Spec coverage

| Spec | Where it lives |
| --- | --- |
| 6.1 exam builder (title, 4 sources, settings incl. negative marking) | `ExamSetupScreen` + `create_exam` (`allowPause`, manual `questions[]`) |
| 6.2 question import (PDF/OCR/manual -> normalized shape) | Phase 3 upload pipeline + the seeded manual editor; both funnel into `ExamDraftQuestion` |
| 6.3 hall UI (no hints/explanations/answer key; title, `Question 12/50`, `Time Remaining`, `Marks: +1`, `Wrong: -0.25`, A-D, Previous/Next) | `RealExamScreen` - badges and counter added; the no-key guarantee is pinned by source scans and runtime `findsNothing` assertions |
| 6.4 controls (pause setting, submit early, auto-submit, save answers + time + progress) | `_saveProgress` (15s + on answer/flag/move), `_pause`/`_resume`, `_confirmAndSubmit`, expired auto-submit |
| 6.5 scoring (total, correct/wrong/skipped, negative marks) | Phase 3 `_result_payload` - unchanged |
| 6.6 analysis (Score %, Accuracy %, Time Management, Weak Topics, mistake types) | Phase 3 `get_analysis` + the "Careless mistake" label |
| 6.7 Mistake Memory auto-save | Phase 3 submit path - unchanged |
| 6.8 Ziku Coach after the exam | `ExamResultScreen._recalcCoach()` -> `POST /api/coach/recalculate` |
| 6.9 Exam history + improvement | `GET /api/exams/history` + `ExamHistoryScreen` |
| 6.10 community-ready DB (share, never expose marks) | `share`/`shared/{code}` + the share row menu; privacy enforced at the data layer (see Database) |

## 3. Backend

### New files

| File | Lines | What |
| --- | --- | --- |
| `backend/app/services/exam_pro_service.py` | 501 | `_latest_open_attempt`, `save_progress`, `pause_attempt`/`resume_attempt`, `_remaining_of`, `latest_result`, `history` (+ `improvement`/`bestPercentage`/`averagePercentage`), `_share_code`/`_decode_share`, `set_visibility`, `get_shared`, `_hall_payload` |
| `backend/tests/test_exam_pro.py` | 653 | 25 tests: save/pause/resume lifecycle, submitted conflicts, pause refused when `allowPause` is off, resume 404 -> fresh start, expired resume at 0 seconds, history improvement + own-results-only, `/list` and `/result` aliases, share/unshare/bad code/private paper, manual source, Careless label, path-parameter ordering, role gates, cross-student save isolation, submit after saves |

### Modified

| File | Change |
| --- | --- |
| `backend/app/services/exam_simulator_service.py` | `SOURCES` gains the manual branch; `create_exam(..., allow_pause)` -> `allowPause` on the doc; documents start `"visibility": "private"`, `"shareCode": ""`; `_public_exam` and the start payload carry `allowPause`; questions accept the `manual`/`upload`/`saved` sources; `_mistake_label` -> "Careless mistake" (type key `memory` unchanged) |
| `backend/app/routers/exams.py` | imports `exam_pro`; `ExamCreateRequest.allow_pause` (default `True`); schemas `ExamProgressRequest`, `ExamPauseRequest`, `ExamResumeRequest`, `ExamShareRequest`; eight new routes (aliases declared before `/{exam_id}`), `ExamError -> _raise` on each |

### Endpoints (student-only, camelCase out)

| Method | Route | Returns |
| --- | --- | --- |
| GET | `/api/exams/list` | spec-shaped alias of `GET /api/exams` (papers list) |
| GET | `/api/exams/history?limit=1..50` | `exams[]` (`resultId`, `examId`, `attemptId`, `title`, `subject`, score/totalMarks/percentage/accuracy, counts, `timeManagementLabel`, `weakTopics`, `createdAt`, `dayKey`), `count`, **`improvement`** (newest% - previous%, `null` with <2 papers), `bestPercentage`, `averagePercentage` |
| GET | `/api/exams/{id}/result` | the submit payload for the latest (or `attemptId=`) finished attempt; 404 before anything is submitted |
| POST | `/api/exams/{id}/save` | `{saved: true, remainingSeconds}` - keeps answers, flags and remaining time; 409 once submitted |
| POST | `/api/exams/{id}/pause` | `{status: "paused", remainingSeconds}` - 403 when the paper was built with `allowPause: false` |
| POST | `/api/exams/{id}/resume` | start-shaped hall payload + `status`/`resumed`/`remainingSeconds`/`savedAnswers`/`markedForReview`; paused -> deadline rewritten from the frozen remainder; running -> deadline rules; **404 when nothing is open** (the client then starts fresh) |
| POST | `/api/exams/{id}/share` | `{examId, title, visibility: "link"/private", shareCode, shared}` - owner only |
| GET | `/api/exams/shared/{code}` | redacted paper: `title`, `subject`, `questionCount`, marks/pause settings, `questions[]` **without answers**; 404 for a bad, unshared or private paper |

### Database

**No new collection, no spec rename.** The spec's `exam_templates`,
`exam_questions`, `exam_attempts`, `exam_results` map onto the collections
Phase 3 already created and this phase kept:

| Spec name | Actual store |
| --- | --- |
| `exam_templates` | `users/{uid}/exams` (the paper document) |
| `exam_questions` | `users/{uid}/exam_questions` |
| `exam_attempts` | `users/{uid}/exam_attempts` |
| `exam_results` | `users/{uid}/exam_results` |

New **document fields only**: on `exams` - `allowPause` (bool, default
true), `visibility` (`"private"` until shared), `shareCode`, `sharedAt`.
Attempts keep Phase 3's `answers`/`markedForReview`/`remainingSeconds`
fields; save/pause/resume only rewrite them.

**Privacy by construction (spec 6.10):**
* `history` streams **only** `users/{uid}/exam_results` - there is no
  cross-user query, so comparing progress is opt-in by construction
  (`history_only_reads_the_callers_own_results`);
* `get_shared` returns `_redact_question` output only - no answer key, no
  scores, no attempts, no owner id - and refuses any paper that is not
  `visibility == "link"` (`a_private_paper_cannot_be_read_by_a_guessing_classmate`);
* `save_progress`/`pause`/`resume` resolve the attempt **inside the
  caller's** collection, so touching another student's attempt is a 404
  before any write (`saving_progress_never_touches_another_students_attempt`);
* the share code is opaque (`base64url(uid|examId)`) but is treated as a
  capability for the *paper* only - it never grants a score read;
* `firebase/firestore.rules` needed no change (everything is
  server-side under `require_student`).

### Integrations

* **Mistake Memory / Academic Health / Ziku Coach** - unchanged data path:
  submit still writes mistakes and results; Phase 6 adds the *trigger*
  (`coachRecalculate()` on the result screen) so the coach's cached profile
  and today's mission rebuild right after an exam - the same one-shot,
  fire-and-forget call the quiz result screen makes.
* **Quiz System / Exam Rescue / Focus Engine** - untouched.
* **AI Usage Tracking** - deliberately unchanged: no new
  `AI_ACTIVITY_TYPES`. Analysis AI still spends quota through `AiFeature`
  as it did in Phase 3, so the usage dashboard's numbers keep their
  meaning.

## 4. Flutter

### New

| File | Lines | What |
| --- | --- | --- |
| `lib/features/exams/presentation/real_exam_screen.dart` | 766 | the Pro hall: resume-first open, `Question n / total`, marks badges, save/pause/resume controls, paused card, `Pause + Submit` bottom bar (Submit only when pause is off) |
| `lib/features/exams/presentation/exam_history_screen.dart` | 369 | `ExamHistoryScreen`: history load, improvement/average stat cards, `GochanoListRow` rows with score badges, result drill-down, **Share paper** menu + code dialog, empty/error states; seams `historyFn`/`resultFn`/`analysisFn`/`shareFn` |
| `test/exam_pro_test.dart` | 607 | 12 tests |

### Modified

| File | Change |
| --- | --- |
| `lib/features/exams/presentation/exam_hall_screen.dart` | becomes `typedef ExamHallScreen = RealExamScreen;` (12 lines) - every Phase 3 call site keeps working |
| `lib/features/exams/exam_models.dart` | typedefs `ExamResumeFn`/`ExamSaveFn`/`ExamPauseFn`/`ExamHistoryFn`/`ExamResultFn`/`ExamShareFn`; `ExamHall` += `allowPause`, `status`, `resumed`, `remainingSeconds`, `savedAnswers`, `markedForReview`; `ExamDraftQuestion.empty()` |
| `lib/services/api_service.dart` | `resumeExam`, `saveExamProgress`, `pauseExam`, `examHistory`, `getExamResult`, `shareExam`, `getSharedExam` (the Phase 6 block, query-string discipline intact) |
| `lib/features/exams/presentation/exam_setup_screen.dart` | title field, `Write your own` source, pause Allowed/Not allowed, `My exams` app-bar action, manual+pause+history seams, hands off to `RealExamScreen` |
| `lib/features/exams/presentation/exam_upload_screen.dart` | `initialDrafts` + `manual` (seeded rows, "Write your own" app bar), **Add question** button |
| `lib/features/exams/presentation/exam_result_screen.dart` | `_recalcCoach()` - one background `coachRecalculate()` per screen when a real submit payload arrived |

### Where the spec's screen shows up

| Spec 6.3 element | On screen |
| --- | --- |
| paper title | app bar (`Exam in progress` when the paper has none) |
| `Question 12/50` | brand badge in the clock card: `Question 12 / 50` |
| `Time Remaining: 42:35` | `Time remaining` caption + statistic clock (red at <= 60s) |
| `Marks: +1` / `Wrong: -0.25` | success/error badges beside the question text |
| options A-D, Previous/Next | unchanged Phase 3 widgets, plus `Mark for review` |

### Degradations (all tested)

* resume says "nothing open" (404) or the backend URL is missing -> fresh
  start; any other server verdict -> friendly error + `Try again`;
* a save or pause fails -> friendly error line, the paper keeps running;
* a resumed attempt whose deadline has already passed -> auto-submits at
  0:00 with the saved answers;
* history offline -> `ErrorState` + `Try again`; empty -> "No exams yet"
  with a way back;
* share fails -> dialog with the friendly message, list untouched;
* result opened from history with no analysis -> the row's own numbers
  stay on screen while the screen retries.

## 5. Verification

### Backend (`cd backend && .venv\Scripts\python.exe -m pytest -q`)

```
9 failed, 806 passed, 2 warnings in 30.61s
```

* `tests/test_exam_pro.py`: **25 passed**; `tests/test_exam_simulator.py`
  (Phase 3): **45 passed** - 70 exam tests together.
* The 9 failures are the pre-existing `tests/test_ai_attachment.py` set
  (same before this phase).
* Baseline 781 -> 806 passed (+25), zero new failures.

### Flutter (`cd flutter_app`)

```
dart analyze lib      -> No issues found!
flutter test          -> 1311 passed, 90 failed
```

* `test/exam_pro_test.dart`: **12 passed** (manual build + title + pause
  setting, pause-off hall, `My exams` entry, save-on-answer with flags and
  remaining time, pause/resume against the rewritten deadline, redacted
  payload, history rows + improvement + result drill-down, share dialog,
  empty history, three source contracts).
* Baseline 1299 passed / 90 failed -> **1311 passed / 90 failed**: +12 new
  tests; the 90 failing tests are *identical* to baseline (compared test by
  test from the runner's `[E]` lines - navigation / Quick Actions /
  relationship source-scan tests that were already red before this phase).
* `test/exam_simulator_test.dart` (Phase 3, untouched) still passes end to
  end against the aliased hall - including the clock, the submit payload,
  the no-answer-key assertions and the seven-route client scan.
* `dart analyze` on the whole package reports only the 13 pre-existing
  issues (4 in `test/dev_auth_test.dart`, the rest sealed-class/unused
  warnings); none in the files this phase touched.

### Protected surfaces re-run

Home mode filtering (15 study / 5 utility / 9 non-student items -
Phase 6 added **no** Home entries), exam-rescue Home gating, home banned-word
scan (`Focus` still absent, case-sensitive), study rebuild, ziku coach,
today command centre, translation smoke (bilingual pairs clean), API
contract scan - all unchanged relative to baseline.

## 6. Follow-ups (not blocking)

1. **Shared-paper viewer** - `GET /shared/{code}` and `getSharedExam()`
   are tested server-side and ready, but no screen redeems a code yet. The
   natural door is the setup screen ("Open a shared paper"): enter the
   code -> read-only preview -> *save a copy into my papers* (the copied
   paper stays `private` for the copier).
2. **Challenge a friend / compare progress** - needs a presence or friend
   graph plus an explicit opt-in surface; the data rule is already fixed
   (marks travel only through the owner's own history read), so this can be
   built without new privacy semantics.
3. **Share code ergonomics** - copy-to-clipboard and a rendered link on the
   dialog; today the code is `SelectableText` only.
4. **Cross-device conflicts** - if the same attempt is resumed elsewhere,
   a stale save returns 409 and currently surfaces as a friendly error
   line. A "reload from server" action would resolve it in one tap.
5. **Auto-save cadence** - 15 seconds + answer/flag/move; a flaky network
   could still lose the last 15 seconds if the app is force-killed, though
   the submit payload always carries the full answer set.
6. **History depth** - `limit` caps at 50; a month/subject filter would
   come from the existing `dayKey`/`subject` fields without a new endpoint.
