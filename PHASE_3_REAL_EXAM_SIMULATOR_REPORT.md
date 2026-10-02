# PHASE 3 - AI Real Exam Simulator

Full paper → real timer → server-graded result → Mistake Memory, Academic
Health and Ziku. Backend, Flutter, rules and tests are all in this phase;
Phases 1 (AI Mistake Memory) and 2 (AI Academic Health + Focus
Intelligence) are untouched apart from the two integration points listed in
§3.5.

---

## 1. What shipped

* **Papers in three ways** - AI-generated (`source: "ai"`), uploaded
  (`source: "upload"`, PDF/image/text parsed and hand-corrected first), or
  saved (`source: "saved"` = a previous exam's questions or the student's
  quiz questions).
* **A hall that behaves like an exam** - server-side deadline, countdown,
  question navigator with answered/flagged states, mark-for-review, submit
  confirmation, and auto-submit when the clock expires.
* **Server-side grading** - no answer key ever leaves the backend during an
  attempt; marks, negative marking, accuracy, weak topics and the time
  verdict are computed once, in one place.
* **A result worth reading** - score, accuracy, time management, weak topics
  with a concrete action, every wrong answer with its type and its +1/+7/+30
  day review dates, Ziku's three-day plan and a live Academic Health read.
* **Two entries** - a Home study card (`ExamSimulatorCard`) and a Study
  app-bar action, both opening the same setup screen.

---

## 2. Exam model and rules

| Rule | Behaviour |
| --- | --- |
| Question payload | `index, question, type, options, topic, marks, needsReview` - **no `correct`, no `explanation`** on `GET`/`start` (redaction is tested) |
| MCQ answers | Bare option letters (`A`, `B`, …). The Flutter hall maps option index → letter on submit; option text is never accepted as an answer |
| Correct marks | `correctMarks` if supplied, else `totalMarks / questionCount` |
| Wrong answer | `-penalty` when negative marking is on (default `0.25`), `0` when off |
| Blank answer | `skipMarks` (default `0`) - blanks never trigger a penalty |
| Total | Per-question scores summed and capped at `totalMarks`, never negative |
| Accuracy | `correct / attempted` (blanks excluded) |
| Time management | `good`: used ≤ 1.05 × limit **and** ≤ 10% unanswered · `fair`: ≤ 1.30 **and** ≤ 30% · else `poor`. Labels: `Good` / `Fair` / `Needs work`, plus a sentence (`timeManagementDetail`) |
| Weak topics | Topic accuracy below `DEFAULT_WEAK_THRESHOLD` (60), sorted worst-first |
| Mistake type | `concept` / `calculation` / `memory` via `classify_mistake_type` |
| Review ladder | `reviewDates` = today +1, +7, +30 days on every captured mistake |
| Upload parsing | PDF → `pdf_service.extract_pdf_text`, image → `ocr_service`, plain text → line parser; anything harder falls back to one AI call (`AiFeature.QUIZ`). Questions whose answer the parser is unsure of come back in `needsReview` |

---

## 3. Backend

### 3.1 New files

| File | Purpose |
| --- | --- |
| `backend/app/services/exam_simulator_service.py` | Create / upload / start / submit / analysis, grading, mistake capture, Ziku plan, read-only rescue lookup |
| `backend/app/routers/exams.py` | 7 endpoints + pydantic request schemas (`_CamelModel`) |
| `backend/tests/test_exam_simulator.py` | 45 tests (create ×13, upload ×6, hall ×4, submit ×10, analysis ×6, cross-module ×6) |

### 3.2 Modified

| File | Change |
| --- | --- |
| `backend/app/main.py` | `include_router(exams, prefix="/api/exams", tags=["AI Exam Simulator"])` |
| `backend/app/services/academic_health_service.py` | New `practiceExams` signal (`count7`, `avgAccuracy`, `total`, `weakTopics`) collected by `_collect_exams`; exam-readiness gains `min(count7×5, 15) × (avgAccuracy/100)` and the detail suffix `· N practice exam(s) (X% avg)` - only when `count7 > 0`, so every Phase 2 expectation still holds |
| `backend/app/routers/ai_study.py` | `quiz_history` items now carry `examId` so simulated papers appear in history |
| `backend/tests/conftest.py` | `exam_simulator_service.get_firestore` patched to `FakeFirestore`; router added to the patched-router tuple |
| `backend/tests/test_role_gate_coverage.py` | `/api/exams` added to `STUDENT_ONLY_PREFIXES` (static + runtime probe) |
| `firebase/firestore.rules` | Read-only-by-owner blocks for `exams`, `exam_questions`, `exam_attempts`, `exam_results` - all client writes `if false` (only the Admin SDK writes) |

### 3.3 Endpoints (all `require_student`, camelCase in and out)

| Method | Path | Input | Returns |
| --- | --- | --- | --- |
| `POST` | `/api/exams/create` | `{subject, source(ai\|upload\|saved), questionCount, totalMarks, timeLimitMinutes, negativeMarking{enabled,penalty}, correctMarks, skipMarks, difficulty, topic, title, questions[], sourceExamId, materialIds}` | exam object + **redacted** questions |
| `POST` | `/api/exams/upload` | multipart `file` + form `subject`, `questionCount` | `{filename, textSource(pdf_text\|ocr\|text), parser(ai\|line_parser), questionCount, questions[] (with answers), needsReview[], warnings[]}` |
| `GET` | `/api/exams` | `?limit=` | `{exams, count}` newest first |
| `GET` | `/api/exams/{exam_id}` | `?includeQuestions=` | exam + redacted questions + `attempts[]` + `results[]` |
| `POST` | `/api/exams/{exam_id}/start` | - | `{attemptId, startedAt, deadlineAt, timeLimitSeconds, totalMarks, negativeMarking, correctMarks, penalty, skipMarks, questions[]}` |
| `POST` | `/api/exams/{exam_id}/submit` | `{attemptId, answers[], timeSpentSeconds, markedForReview[], withAiAnalysis}` | result payload (`score, totalMarks, percentage, accuracy, correct/wrong/skipped, timeManagement(+Label/Detail), topicScores, weakTopics, mistakeCount, mistakes[], new/repeatedMistakes, pendingAnalysis, zikuPlan, zikuAnalysis, quizId`) |
| `GET` | `/api/exams/{exam_id}/analysis` | `?attemptId=&withAi=` | result payload **+** `weakTopicDetails[{topic,accuracy,action}]`, `mistakeTypes[{type,label,count}]`, `mistakesSaved{saved,new,repeated,pendingAnalysis,reviewDates}`, `health`, `rescue`, `zikuPlan{headline,days[],daysRemaining,…}`, `zikuPrompt`, `hasAiAnalysis` |

Query/form parameters stay camelCase (`includeQuestions`, `attemptId`,
`withAi`, `questionCount`); JSON bodies are camelCase via `_CamelModel`.

**Status codes:** `400` bad input / questions without answers / foreign
attempt · `403` non-student · `404` missing exam, attempt or result · `409`
already submitted, or paper without questions · `413` file > 10 MB · `415`
unsupported type · `422` no readable text / no questions extracted · `502`
AI failed · `503` Firestore unavailable.

### 3.4 Database schema

```
users/{uid}
  exams/{examId}                    examId, subject, title, topic, source,
                                    difficulty, questionCount, totalMarks,
                                    timeLimitMinutes, negativeMarking,
                                    correctMarks, penalty, createdAt
    exam_questions/{q_000}          index, question, type, options[],
                                    correct, topic, explanation,
                                    difficulty, marks, needsReview
  exam_attempts/{attemptId}         examId, status(running|submitted),
                                    startedAt, deadlineAt, timeLimitSeconds,
                                    submittedAt, timeSpentSeconds,
                                    markedForReview[], answers[]
  exam_results/{resultId}           examId, attemptId, subject, score,
                                    totalMarks, percentage, accuracy,
                                    correct/wrong/skippedCount,
                                    timeManagement(+Label/Detail),
                                    topicScores, topicAccuracy, weakTopics,
                                    mistakes[{index, topic, question,
                                    userAnswer, correctAnswer, type,
                                    explanation, difficulty, reviewDates}],
                                    mistakeCount, newMistakes,
                                    repeatedMistakes, pendingAnalysis,
                                    zikuPlan, zikuAnalysis, quizId, createdAt
  quiz_results/{quizId}             written by submit (score = integer
                                    percentage, topicScores, subjectId,
                                    examId, attemptId)  → Phase 2 metrics
  mistakes/{mistakeId}              written through Mistake Memory (Phase 1)
```

Firestore rules: every one of the four Phase 3 collections is
`allow read: if request.auth.uid == uid` and `allow write: if false` - the
client reads its own paper and never writes a mark.

### 3.5 Integrations

* **Mistake Memory (Phase 1)** - `submit_attempt` runs
  `mistake_memory_service.capture_mistakes(...)`; `exam_results.mistakes[]`
  carries the same type/`reviewDates`, so the result screen and the Learning
  Brain can never disagree. `pendingAnalysis` is reported instead of
  blocking the score.
* **Academic Health (Phase 2)** - analysis returns the live
  `get_academic_health(uid, persist=False)` as `health`, and submitting
  feeds the new `practiceExams` signal (`count7`, `avgAccuracy`, weak
  topics) into exam readiness. Existing 39 Phase 2 tests still pass.
* **Quiz system** - every submit writes a `quiz_results` document, so
  Understanding, weak topics and quiz history see simulated papers;
  `quiz_history` items now include `examId`.
* **Exam Rescue** - `_active_rescue(...)` is read-only and only moves Ziku's
  Day 3 when a rescue plan for that subject is still live (never after the
  real exam date). It never writes back to the rescue plan.
* **Ziku** - deterministic 3-day plan ships with every result
  (`zikuPlan.days`); the AI paragraph (`AiFeature.CHAT`) is generated once
  per attempt, cached on the result, and only produced when `withAi=true`
  and it is still empty. All AI goes through one seam, `_ai_generate`
  (tests patch it).
* **Role gate** - `/api/exams` is in `STUDENT_ONLY_PREFIXES`.

---

## 4. Flutter

### 4.1 New

| File | Role |
| --- | --- |
| `lib/features/exams/exam_models.dart` | `ExamPaper`, `ExamQuestion` (redacted by construction), `ExamDraftQuestion` (editable, carries the answer key), `ExamHall`, `ExamPickResult`, and the seven injected function typedefs |
| `lib/features/exams/exam_ui.dart` | `examClock`, `examLetter`, `examDurationLabel`, `examErrorBox`, `examLoading`, `ExamChoiceTile`, `ExamStatLine` |
| `lib/features/exams/exam_simulator_card.dart` | Home entry card (`openSetup` injectable for tests) |
| `lib/features/exams/presentation/exam_setup_screen.dart` | Source (AI / upload / saved picker), subject, topic, questions, marks, time, negative marking, difficulty → `createExam` → hall |
| `lib/features/exams/presentation/exam_upload_screen.dart` | File pick **or** paste text → `uploadExamPaper` → per-question correction (question, options, answer key, topic, explanation) → returns drafts to setup; refuses to hand back an unanswered draft |
| `lib/features/exams/presentation/exam_hall_screen.dart` | Countdown from the server deadline (`Timer.periodic`), navigator grid, option tiles / short-answer field, mark for review, submit dialog, auto-submit at zero, then `pushReplacement` to the result |
| `lib/features/exams/presentation/exam_result_screen.dart` | Score card, weak topics + action, mistakes (answer vs correct, explanation, review dates, type rollup, pending count), Ziku plan + on-demand AI paragraph, live health rows, links to `AiAssistantScreen(prefilledQuestion:)`, Academic Health and Learning Brain |
| `test/exam_simulator_test.dart` | 24 tests (see §5) |

### 4.2 Modified

| File | Change |
| --- | --- |
| `lib/services/api_service.dart` | `createExam`, `uploadExamPaper` (multipart), `listExams`, `getExam`, `startExam`, `submitExam`, `getExamAnalysis` - all through `_guard`, query strings only via `query:` (never in the path literal, per `api_contract_test`) |
| `lib/features/home/presentation/home_screen.dart` | `const ExamSimulatorCard()` in the Study Mode card list |
| `lib/features/study/presentation/study_screen.dart` | Study app-bar `IconActionButton` → `ExamSetupScreen` |
| `test/home_mode_filtering_test.dart` | Study card count 9 → 11 (spacer + card) + asserts `ExamSimulatorCard` |
| `test/exam_rescue_active_experience_test.dart` | Study card count 9 → 11 |

Accessibility and design-system rules held: no `AnimationController`, no
decorative animation widgets, no raw `IconButton` without a tooltip, no
`Color(0x…)` (everything through `context.colors`), icons carry semantic
labels, the countdown is a `liveRegion`, and every navigator tile is a
`Semantics(button: true, selected: …)`.

---

## 5. Verification

### Backend (`cd backend && .venv\Scripts\python.exe -m pytest -q`)

```
726 passed, 9 failed
```

* `tests/test_exam_simulator.py` → **45 passed** (5 consecutive clean runs).
* The 9 failures are the pre-existing `tests/test_ai_attachment.py` suite
  (`/api/ai/attachment-question` was never implemented - 404) and are out of
  scope; the baseline before Phase 3 was `681 passed / 9 failed`, so this is
  **+45 tests with no regressions**.
* One flake was found and fixed at source: `datetime.now()` only advances
  every ~15 ms on Windows, so two creates in the same tick tied on
  `createdAt` and `test_list_exams_returns_newest_first` could see the older
  paper first. The test now sleeps past one clock tick with a comment; five
  consecutive full-file runs are green.

### Flutter (`cd flutter_app`)

```
dart analyze lib           → No issues found!
flutter test               → 1273 passed, 90 failed   (baseline 1249 / 90)
```

* `test/exam_simulator_test.dart` → **24 passed**: model/clock/letter
  helpers, redaction-by-construction, the seven routes and their `query:`
  style, Home/Study entry points, setup (AI create → hall, error surfacing,
  upload gate), upload (correction, paste path, refusing an unanswered
  draft, handing drafts back), hall (clock, letter answers, flags,
  confirmation, submit payload, auto-submit, failed start), result (score,
  weak-topic action, mistakes + review dates, plan, health rows, on-demand
  AI paragraph, unreachable backend) and the entry card.
* The 90 remaining failures are the same pre-existing set as the baseline
  (shell/nav, Today/StudentContext, related chips, planner rows, 4
  `profile_structure`, `dev_auth_test` load error) - **no new failures**.
* `test/a11y/accessibility_audit_test.dart` and the design-system ownership
  tests pass inside that run.

---

## 6. Follow-ups (not blocking)

1. **Resume an attempt** - `start` always opens a new attempt; a student who
   kills the app mid-paper starts over (the deadline would have expired
   anyway, but an explicit "resume" would be kinder).
2. **Review every question** - the analysis currently ships the wrong
   answers; a per-question review mode (right/wrong, correct key, note)
   would need `includeReview=true` on the analysis endpoint.
3. **Short-answer grading** - exact-match only; stemming/normalisation (and
   an "ask Ziku to mark this" path) would cut false negatives.
4. **Percentile / class comparison** - the score is self-referential; a
   cohort percentile needs a shared, privacy-safe aggregate.
5. **Reminder before the deadline** - schedule a local/FCM nudge when a
   rescue plan or an exam paper has a date attached.
6. **Bengali review** - every new string is EN/BN paired, but the Bengali
   should get a native-speaker pass alongside the rest of the app.
7. **Offline grace** - the deadline is authoritative on the server, so a
   dropped connection mid-paper still scores what was submitted; an explicit
   "reconnecting" state would make that less scary.
