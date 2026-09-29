# Gochano Top-10 Competition Upgrade: Flagship Workflow Architecture Plan
## Feature Flagship: Exam Rescue (পরীক্ষা উদ্ধার)
**Phase T1 — Architecture Audit, Discovery & Execution Plan**

---

### Executive Summary

Gochano's evolution from a set of modular student utilities into a unified **"Student Life Operating System"** hinges on deep interconnectedness. Rather than creating another siloed screen, **Exam Rescue** connects six existing core pillars of Gochano:
1. **Study Materials** (PDF/DOCX/Notes stored in Backblaze B2 & Firestore)
2. **AI Cascade Engine** (GROQ primary $\to$ Gemini fallback $\to$ OpenRouter tertiary)
3. **Planner & Schedule System** (`PlanView` date strip and daily agendas)
4. **Task/Assignment Management** (Firestore `tasks` collection with offline-first persistence)
5. **Interactive Quiz Generator** (`QuizGeneratorScreen` and `quiz_results` subcollection)
6. **Learning Insights & Weak-Topic Loop** (`weak_topic_service.py` analysis)

This audit establishes the exact architectural foundation, data contracts, UX journeys, failure modes, and implementation roadmap for Exam Rescue.

---

### 1. Existing Architecture Discovered

An exhaustive audit of the Gochano repository reveals the following structural reality:

- **App Shell Architecture (`flutter_app/lib/features/shell/presentation/gochano_shell.dart`)**:
  - Employs a dual-mode shell driven by `GochanoAppMode` (`study` vs `utility`).
  - **Study Mode Destinations**:
    0: `HomeScreen` ("Today")
    1: `WorkspaceView` ("Workspace")
    2: `PlanView` ("Plan")
    3: `CommunityView` ("Community")
    4: `ProfileScreen` ("Profile")
  - Navigation between tabs preserves state via `IndexedStack`.
- **Backend Architecture (`backend/app`)**:
  - FastAPI modular service with Routers: `account.py`, `ai.py`, `ai_study.py`, `commute.py`, `groups.py`, `materials.py`, `part3.py`, `reports.py`, `study.py`.
  - Services: `ai_service.py` (AI cascade & quota system), `pdf_service.py`, `ocr_service.py`, `storage_provider.py` (B2 integration), `weak_topic_service.py`, `ai_recommendation_service.py`.
- **Frontend State & Services (`flutter_app/lib/services`)**:
  - `ApiService`: Unified authenticated HTTP client using single connection pool, deduplicated requests, automatic 403 token refresh retry, and error normalization.
  - `FirestoreService`: Direct real-time streaming and local offline cache writes (`ownerStream`, offline write queues).
  - `StudyService`: Focus session tracking and telemetry.
  - `NotificationService`: Exact alarm notifications on Android and reconciliation from Firestore.

---

### 2. Existing Material Flow

- **Storage Pipeline**:
  - Files are uploaded via `ApiService.uploadMaterial` $\to$ backend `POST /api/materials/upload` (`backend/app/routers/materials.py:112`).
  - Raw binaries are validated for MIME type (`detect_supported_file_type`) and streamed directly into **Backblaze B2** under `users/{uid}/{uuid}_{filename}` (`storage_provider.B2`).
  - Metadata is recorded in Firestore collection `materials`:
    - `ownerId`, `ownerName`, `title`, `fileName`, `filePath`, `storage_provider: 'b2'`, `mimeType`, `sizeBytes`, `visibility`, `groupId`, `subject`, `createdAt`, `updatedAt`.
  - Notes are stored separately in Firestore collection `notes`:
    - `ownerId`, `title`, `content`, `createdAt`, `updatedAt`.
- **Text Processing & AI Extraction**:
  - In `backend/app/routers/ai_study.py:358-394`:
    - **PDF**: Extracted via `extract_pdf_text(raw, max_pages=10)[:8000]` with fallback to OCR (`ocr_extract_text`).
    - **DOC / DOCX**: Decoded or processed via OCR fallback.
    - **TXT**: Direct UTF-8 decode (`raw.decode("utf-8", errors="ignore")[:8000]`).
    - **Images**: Intentionally **NOT** extracted as text. Images are strictly routed to multimodal vision endpoints (`askImage` via Gemini/OpenRouter vision).
    - **Notes**: Extracted directly from Firestore document `content[:10000]`.
- **Material Selection**:
  - Fully reusable bottom sheet already exists: `showMaterialPicker(BuildContext context)` in `flutter_app/lib/features/study/presentation/ai/material_picker_sheet.dart:20`.
  - Enforces `allowImages: false` for academic AI source selection.
  - Returns `List<Map<String, String>>` containing `id` and `title`.
  - Used directly by `QuizGeneratorScreen` (clamped to max 3 materials).

---

### 3. Existing AI Flow

- **Cascade Architecture (`backend/app/services/ai_service.py:896`)**:
  1. **Primary**: **GROQ** (`_groq_generate` using `llama-3.3-70b-versatile` or configured model) — Ultra-fast, $<2.5\text{ s}$ response time.
  2. **Fallback**: **Gemini** (`_gemini_generate` using `gemini-2.5-flash` or `gemini-1.5-flash`) — High context window and structured adherence.
  3. **Tertiary Emergency**: **OpenRouter** (`_openrouter_generate`) — Redundancy guarantee.
- **Quota Governance**:
  - Gated in atomic Firestore transaction `_consume_quota(uid, feature)` (`ai_service.py:175`).
  - Quota tracks:
    - `AiFeature.CHAT`: Daily quota in `ai_usage/{uid}_{YYYYMMDD}`.
    - `AiFeature.NOTE_AI`: Monthly quota in `ai_usage_monthly/{uid}_{YYYYMM}`.
    - `AiFeature.QUIZ`: Monthly quota in `ai_usage_monthly/{uid}_{YYYYMM}` (default 3/month).
    - `AiFeature.STUDY_PLAN`: Active plan quota in `ai_usage_active/{uid}` (default 1 active plan).
- **Existing Endpoints & Limitations**:
  - `POST /api/study/plan` (`backend/app/routers/study.py`): Purely deterministic deadline urgency ranking of unfinished tasks. No generative capability.
  - `POST /api/ai/assignment/plan` (`ai_study.py:306`): Generates unformatted markdown prose under 500 words. Unparseable by client widgets.
  - `POST /api/ai/planner/recommend` (`ai_study.py:533`): Generates daily recommendation text for `SmartPlannerScreen`. Unstructured.
  - `POST /api/ai/quiz/generate` (`ai_study.py:397`): Accepts `source_ids`, extracts texts, prompts for strict JSON schema, strips markdown fences, parses JSON, and returns structured questions.

---

### 4. Existing Study-Plan Flow

- **PlanView (`flutter_app/lib/features/study/presentation/planner/plan_view.dart`)**:
  - Streams `tasks` directly: `FirestoreService.ownerStream('tasks', limit: 300)`.
  - Renders a 31-day horizontal date selector (`_DateStrip`) and groups items by `dueAt` date.
  - Each item displays status, category tag (`Asm` vs `Task`), due time, and interactive checkbox.
- **PlannerView (`planner_view.dart`)**:
  - Uses `ApiService.studyPlan()` to display urgency order.
- **Plan Persistence**:
  - Crucial insight: **There is no separate `study_plans` table or collection in current active use.**
  - Every scheduled item in Gochano is represented as a document in the `tasks` collection with a `dueAt` timestamp.
  - Therefore, Exam Rescue items **must materialize as `tasks`** to seamlessly integrate into `PlanView`, the `HomeScreen` today list, and device alarms!

---

### 5. Existing Task / Assignment Flow

- **Firestore Representation (`tasks` collection)**:
  - Document fields:
    - `ownerId`: `String` (Firebase Auth UID)
    - `title`: `String`
    - `type`: `'task' | 'assignment'`
    - `dueAt`: `Timestamp` (nullable)
    - `remindAt`: `Timestamp` (nullable)
    - `done`: `bool`
    - `createdAt`: `FieldValue.serverTimestamp()`
    - `updatedAt`: `FieldValue.serverTimestamp()`
    - Optional/extensible: `subjectId`, `semesterId`, `materialId`.
- **Task Creation & Persistence (`add_task_sheet.dart`)**:
  - Generates stable local document reference synchronously: `FirestoreService.db.collection('tasks').doc()`.
  - Dispatches non-blocking write to Firestore local cache (`unawaited(docRef.set(..., SetOptions(merge: true)))`).
  - Calls `NotificationService.rescheduleTask` to set exact system alarms when `dueAt` is specified.
  - Operates completely offline with zero UI latency.

---

### 6. Existing Quiz Flow

- **Generation**:
  - Triggered via `QuizGeneratorScreen` $\to$ `ApiService.quizGenerate` $\to$ `POST /api/ai/quiz/generate`.
  - Supports up to 3 selected documents or notes via `showMaterialPicker`.
- **Execution & Persistence**:
  - Interactive test runner calculates score, correct answers, and topic breakdown.
  - Persisted via `ApiService.saveQuizResult` $\to$ `POST /api/ai/quiz/save-result`.
  - Stored in subcollection `users/{uid}/quiz_results/{quizId}` with:
    `questions`, `userAnswers`, `correctAnswers`, `score`, `topicScores`, `difficulty`, `timeSpentSeconds`, `materialId`, `dayKey`.
- **Weak-Topic Analysis (`weak_topic_service.py`)**:
  - Aggregates `topicScores` across `quiz_results`.
  - Topics with average score $<60\%$ are flagged as weak topics.
  - Accessible via `GET /api/ai/learning/weak-topics` and presented in `LearningInsightsScreen`.

---

### 7. Existing Today / Study Mode Integration Opportunities

Study Mode destinations:
`Today` (0) | `Workspace` (1) | `Plan` (2) | `Community` (3) | `Profile` (4).

Exam Rescue must not alter bottom navigation or create an isolated enclave. We establish a 3-tier access hierarchy:
1. **Tier 1 (The Operational Anchor — `PlanView`)**:
   - Prominent **"Exam Rescue" Action Banner/Card** right above the date strip in `PlanView`.
   - Reason: The student enters the Plan tab specifically to organize their deadlines and study time.
2. **Tier 2 (The Daily Command Center — `HomeScreen` / "Today")**:
   - When an active Exam Rescue session exists: A dynamic **Exam Rescue Hero Card** renders at the top of Today (above or beside `_TodaysTasksCard`).
   - Displays: Exam Name, countdown badge ("Day 2 of 3"), today's target minutes, remaining tasks for today, and a direct button "Start Day Quiz" or "Focus Now".
   - When no active rescue exists: A discrete contextual quick action in `_QuickAccess` or Quick Add Sheet.
3. **Tier 3 (The Academic Launcher — `WorkspaceView`)**:
   - Included in `_QuickAccess` primary/secondary grid alongside `AI Assistant`, `Assignment AI`, `Quiz`, and `Insights`.

---

### 8. Reusable Components

The following existing components will be reused **as-is**:
1. **`showMaterialPicker(BuildContext context)`** (`material_picker_sheet.dart:20`):
   - Zero modifications needed. Already enforces `allowImages: false`, searches materials, and returns document IDs and titles.
2. **AI Cascade Engine** (`ai_service.py`):
   - Directly reuse `generate()` with GROQ $\to$ Gemini $\to$ OpenRouter fallback.
3. **Document Text Extraction Pipeline** (`ai_study.py:358-394`):
   - Directly reuse `_extract_material_text` and `_extract_note_text`.
4. **Offline Task Persistence Pipeline** (`add_task_sheet.dart`):
   - Reuse pattern of synchronous client doc generation + offline merge write to `tasks`.
5. **Exact Alarm & Notification Scheduling** (`NotificationService.rescheduleTask`).
6. **Design System & Surfaces**:
   - `AppCard`, `PrimaryButton`, `SecondaryButton`, `GochanoBadge`, `GochanoScaffold`, `GochanoAppBar`, `AiErrorBanner`.
7. **Bilingual Localization Helper**: `GochanoLanguage.text(en, bn)` and `toBanglaDigits()`.

---

### 9. Components That Must NOT Be Duplicated

1. **DO NOT** create a second file uploader or material picker sheet.
2. **DO NOT** create a parallel task database or task UI renderer.
3. **DO NOT** create a separate notification scheduling engine.
4. **DO NOT** create a standalone quiz evaluation engine.
5. **DO NOT** create a new HTTP client or authentication refresh wrapper.
6. **DO NOT** create a separate offline synchronization manager.

---

### 10. Recommended Exam Rescue User Journey

```
[Entry Point: PlanView Banner OR Today Hero Card OR Workspace QuickAction]
                                   │
                                   ▼
          ┌──────────────────────────────────────────────────┐
          │ Step 1: Exam Rescue Setup Sheet / Screen         │
          │ - Exam Name / Subject (e.g., "Database Systems") │
          │ - Exam Date (Date picker, default: Today + 3d)   │
          │ - Daily Study Budget (1h, 2h, 3h, 4h, custom)    │
          │ - Select Materials (triggers showMaterialPicker) │
          └──────────────────────────────────────────────────┘
                                   │
                     [Tap "Generate Rescue Plan"]
                                   │ (Instant client validation)
                                   ▼
          ┌──────────────────────────────────────────────────┐
          │ Step 2: AI Plan Generation                       │
          │ - Calls POST /api/ai/exam-rescue/plan            │
          │ - Backend extracts text from chosen materials    │
          │ - Fetches user's weak topics from quiz history   │
          │ - AI synthesizes structured rescue schedule      │
          │ - Fallback template if quota/network drops       │
          └──────────────────────────────────────────────────┘
                                   │
                                   ▼
          ┌──────────────────────────────────────────────────┐
          │ Step 3: Interactive Plan Preview Screen          │
          │ - Shows Day-by-Day schedule (Day 1, Day 2, Day 3)│
          │ - Displays review, practice, quiz, revision items│
          │ - Student can delete an item or adjust duration  │
          │ - Student can re-generate if unsatisfied         │
          └──────────────────────────────────────────────────┘
                                   │
                       [Tap "Accept & Save Plan"]
                                   │
                                   ▼
          ┌──────────────────────────────────────────────────┐
          │ Step 4: Batch Persistence & Task Materialization │
          │ - Saves Session to users/{uid}/exam_rescue       │
          │ - Materializes items as real `tasks` with dueAt  │
          │ - Schedules notification reminders for Day 1..N  │
          └──────────────────────────────────────────────────┘
                                   │
                                   ▼
          ┌──────────────────────────────────────────────────┐
          │ Step 5: Active Rescue Loop                       │
          │ - Today tab renders active Rescue Hero Card      │
          │ - Plan tab highlights rescue tasks on each day   │
          │ - Tapping "Quiz" item launches Quiz Generator    │
          │   pre-scoped to session materials                │
          │ - Quiz completion feeds back into weak topics    │
          └──────────────────────────────────────────────────┘
```

---

### 11. Exact Proposed Screens & Sheets

1. **`ExamRescueSetupSheet`** (`flutter_app/lib/features/study/presentation/rescue/exam_rescue_setup_sheet.dart`):
   - Clean, modal bottom sheet or focused screen.
   - Fields:
     - Exam Title (`TextFormField` with auto-complete from existing subjects).
     - Exam Date Selector (interactive chips: "Tomorrow", "In 3 Days", "In 5 Days", "Custom Date").
     - Daily Time Commitment selector (chips: `1h`, `2h`, `3h`, `4h`).
     - Selected Materials List with `+ Add Materials` button (opens existing `showMaterialPicker`).
     - Action button: `PrimaryButton` with label "Generate Rescue Plan".
2. **`ExamRescuePreviewScreen`** (`flutter_app/lib/features/study/presentation/rescue/exam_rescue_preview_screen.dart`):
   - Shows the generated multi-day strategy.
   - Per-day collapsible cards with timeline indicators:
     - Item chips: Type badge (`Study`, `Practice`, `Quiz`, `Revision`), duration (`45m`), linked material tag.
     - Swipe-to-delete or remove button per item.
   - Summary footer: Total focus hours planned, total quizzes scheduled.
   - Actions: "Regenerate" (`SecondaryButton`) and "Confirm & Apply Plan" (`PrimaryButton`).
3. **`ExamRescueActiveCard`** (`flutter_app/lib/features/study/presentation/rescue/exam_rescue_active_card.dart`):
   - Reusable surface widget rendered in `HomeScreen` and `PlanView`.
   - Compact mode for Today tab; expanded mode for Plan tab.

---

### 12. Exact Proposed Data Flow

```
[User Input] ──► ApiService.generateExamRescuePlan(payload)
                        │
                        ▼ (HTTP POST /api/ai/exam-rescue/plan)
[Backend Router]
  1. Auth check: require_student
  2. Quota check: _consume_quota(user.uid, feature=AiFeature.STUDY_PLAN)
  3. Extract text from material_ids (pdf/doc/txt, max 5k chars each, 15k total)
  4. Fetch weak topics via weak_topic_service.get_weak_topics(user.uid)
  5. Assemble structured prompt
  6. AI Cascade: GROQ -> Gemini -> OpenRouter
  7. Strip fences, parse JSON, validate against Pydantic schema
  8. Return validated JSON to Flutter
                        │
                        ▼ (Response: ExamRescuePlanDto)
[Flutter Client]
  1. Displays in ExamRescuePreviewScreen (in-memory state)
  2. Student reviews/edits
  3. Student confirms
  4. Client writes in batch:
     a. users/{uid}/exam_rescue/{sessionId} (Session metadata)
     b. tasks/{taskId} for each generated item (dueAt = target date 09:00, 11:00, etc.)
  5. Schedules local alarm notifications for each task
  6. Pop back to PlanView with success snackbar
```

---

### 13. Whether a New Persistent Model Is Necessary

**Verdict: YES, but strictly MINIMAL (1 subcollection document for session state, 0 duplicate task collections).**

We do **not** create a new global collection or separate database.
We only store the session envelope in:
`users/{uid}/exam_rescue/{sessionId}`

#### Minimal Model Schema:
```json
{
  "id": "rescue_session_abc123",
  "examTitle": "Database Systems Final",
  "examDate": "Timestamp(2026-10-02T10:00:00Z)",
  "daysRemaining": 3,
  "dailyTargetMinutes": 120,
  "materialIds": ["mat_1", "mat_2"],
  "materialTitles": ["Ch1_RelationalModel.pdf", "Ch2_SQL.pdf"],
  "status": "active", // active | completed | abandoned
  "taskIds": ["task_1", "task_2", "task_3", "task_4"],
  "createdAt": "FieldValue.serverTimestamp()",
  "updatedAt": "FieldValue.serverTimestamp()"
}
```

The individual daily action items are saved directly into the **existing `tasks` collection** with these additional attributes:
- `source`: `"exam_rescue"`
- `rescueSessionId`: `"rescue_session_abc123"`
- `rescueItemType`: `"study" | "practice" | "quiz" | "revision"`
- `materialId`: `"mat_1"` (if linked)

This ensures zero duplication: tasks immediately appear on `PlanView`, `HomeScreen`, Universal Search, and offline stores.

---

### 14. Proposed AI Input Contract

The backend router will accept:
```python
class ExamRescuePlanRequest(_CamelModel):
    exam_title: str = Field(..., min_length=2, max_length=150)
    exam_date: str = Field(..., min_length=10, max_length=30)  # ISO format
    daily_minutes: int = Field(default=120, ge=30, le=720)
    material_ids: list[str] = Field(default_factory=list, max_length=3)
    extra_topics: str = Field(default="", max_length=1000)
```

---

### 15. Proposed AI Output Contract

The AI cascade will be constrained to return strictly validated JSON:
```json
{
  "exam_title": "Database Systems Final",
  "days_remaining": 3,
  "total_estimated_minutes": 360,
  "strategy_summary": "High-intensity 3-day recovery covering relational theory, query writing, and a final mock quiz.",
  "days": [
    {
      "day_number": 1,
      "date_offset": 0,
      "theme": "Core Theory & Schemas",
      "target_minutes": 120,
      "items": [
        {
          "title": "Review Chapter 1: Relational Schema & Normalization",
          "type": "study",
          "estimated_minutes": 50,
          "material_id": "mat_1",
          "action_note": "Focus on 3NF vs BCNF differences"
        },
        {
          "title": "Practice 5 Schema Decomposition Problems",
          "type": "practice",
          "estimated_minutes": 40,
          "material_id": "mat_1",
          "action_note": "Check lossless join and dependency preservation"
        },
        {
          "title": "Checkpoint Quiz: Normalization",
          "type": "quiz",
          "estimated_minutes": 30,
          "material_id": "mat_1",
          "action_note": "Verify understanding before Day 2"
        }
      ]
    },
    {
      "day_number": 2,
      "date_offset": 1,
      "theme": "SQL & Transactions",
      "target_minutes": 120,
      "items": [
        {
          "title": "Review Chapter 2: Complex Queries & ACID",
          "type": "study",
          "estimated_minutes": 50,
          "material_id": "mat_2",
          "action_note": "Review GROUP BY, HAVING, and isolation levels"
        },
        {
          "title": "Write 6 SQL Aggregation Queries",
          "type": "practice",
          "estimated_minutes": 40,
          "material_id": "mat_2",
          "action_note": "Practice nested subqueries"
        },
        {
          "title": "Checkpoint Quiz: SQL & Transactions",
          "type": "quiz",
          "estimated_minutes": 30,
          "material_id": "mat_2",
          "action_note": "Target tricky syntax questions"
        }
      ]
    },
    {
      "day_number": 3,
      "date_offset": 2,
      "theme": "Full Revision & Mock Test",
      "target_minutes": 120,
      "items": [
        {
          "title": "Review Weak Areas & Summary Notes",
          "type": "revision",
          "estimated_minutes": 45,
          "material_id": "",
          "action_note": "Skim highlighted definitions and formulas"
        },
        {
          "title": "Comprehensive Mock Quiz",
          "type": "quiz",
          "estimated_minutes": 45,
          "material_id": "mat_1",
          "action_note": "Simulate real exam timing"
        },
        {
          "title": "Final Rest & Mental Prep",
          "type": "revision",
          "estimated_minutes": 30,
          "material_id": "",
          "action_note": "Pack exam kit, check admit card, sleep on time"
        }
      ]
    }
  ]
}
```

---

### 16. Material / Content Limits

- **Maximum Materials**: Clamped to **3 documents** (matches Quiz Generator limit).
- **Text Length Limit per Material**: Capped at **5,000 characters** per document.
- **Combined Context Cap**: Maximum **15,000 characters** sent to AI prompt.
- **Supported File Types**: PDF, TXT, DOC, DOCX.
- **Images**: Strictly blocked from text extraction (images are filtered out in `showMaterialPicker`).

---

### 17. AI Quota / Error Handling

- **Quota Bucket**: Uses `AiFeature.STUDY_PLAN` (1 active plan per student) or fallback to `CHAT` daily bucket if active limit policy is adjusted.
- **Error Handling**:
  - Quota Exhausted ($429$): Returns clear bilingual explanation:
    *"Active study plan limit reached. Complete or archive existing rescue plan first."*
  - Provider Failure ($502 / 504$): Automated cascade executes: GROQ $\to$ Gemini $\to$ OpenRouter.
  - Parsing / Format Error: If AI returns malformed JSON, a deterministic rule-based rescue template is synthesized instantly from the material titles and days remaining so the user is never left stranded.

---

### 18. Preview-Before-Save Workflow

- User safety is guaranteed:
  1. No task is created during generation.
  2. The generated plan is passed to `ExamRescuePreviewScreen` purely as Dart model objects.
  3. The user can:
     - Delete individual tasks that do not fit their schedule.
     - Adjust time allocations.
     - Change the exam date if necessary.
     - Tap "Regenerate" with adjusted parameters.
  4. Only upon explicit tap of **"Confirm & Apply Plan"** are tasks and session records committed to Firestore.

---

### 19. Plan / Tasks Integration

- Each item in the confirmed plan becomes a standard document in the `tasks` collection.
- Task title format: `"[Exam Rescue] {item.title}"`.
- `dueAt` is computed by adding `item.date_offset` days to the start date at designated intervals (e.g., 09:00 AM, 11:30 AM, 03:00 PM).
- Result:
  - Immediately visible in `PlanView` on the corresponding calendar dates.
  - Immediately visible in `HomeScreen` under `_TodaysTasksCard` when `dueAt` matches today.
  - Automatically activates notification reminders via `NotificationService`.

---

### 20. Quiz Integration

- When an Exam Rescue item has `type: "quiz"`:
  - In `PlanView` or `HomeScreen`, the task tile renders a specialized action button: **"Take Quiz"**.
  - Tapping this button directly routes to `QuizGeneratorScreen` with:
    - Pre-selected material: `item.material_id`.
    - Pre-filled topic: `item.title`.
    - Auto-configured question count: `10`.
- After quiz completion:
  - Result is automatically saved to `users/{uid}/quiz_results`.
  - The corresponding Exam Rescue task is automatically marked `done: true`.

---

### 21. Weak-Topic Loop — Minimal Viable Version

- **The Closed Loop**:
  1. When building the Exam Rescue prompt, the backend inspects `weak_topic_service.get_weak_topics(uid)`.
  2. If the user previously scored poorly on a topic matching the exam subject (e.g. "Normalization" $<60\%$), the prompt instructs the AI to prioritize that specific weak topic on Day 1 or Day 2.
  3. When the user takes the Day 1 quiz in Exam Rescue, the score is saved in `quiz_results`.
  4. `weak_topic_service.py` immediately recalculates the student's mastery.
  5. The Day 3 revision card automatically suggests reviewing whatever questions were missed during the Day 1 & Day 2 quizzes!

---

### 22. Offline Behavior

- If offline during setup:
  - `ConnectivityService.instance.online.value` detects disconnection.
  - Shows warning: *"AI Plan Generation requires an internet connection. Check connection or use offline manual planner."*
- If offline after plan confirmation:
  - All confirmed tasks and session data are committed to Firestore local cache via `SetOptions(merge: true)`.
  - Tasks render immediately on the offline schedule.
  - Local alarms continue to fire via Android AlarmManager even without network connectivity.

---

### 23. Edge Cases & Resilience

1. **Exam is Today (0 days remaining)**:
   - Validated on client and server. Suggests "Cram Session Mode" (single-day breakdown: 3 focused revision blocks + 1 quick quiz).
2. **Exam date is in the past**:
   - Form validation error: *"Exam date must be in the future."*
3. **1 Day Remaining (Tomorrow)**:
   - Tailored prompt: Focus on high-yield summary, formulas, and a short 10-minute diagnostic quiz.
4. **10+ Days Remaining**:
   - AI adjusts pace to regular daily distribution with rest intervals.
5. **No Materials Selected**:
   - Allowed! Prompts AI using the Exam Title / Subject name to build a standard curriculum syllabus.
6. **User exits screen mid-generation**:
   - Client request cancellation handled gracefully; no orphaned tasks created.

---

### 24. English / Bangla Localization Needs

All strings will use `GochanoLanguage.text(en, bn)`:
- "Exam Rescue" $\to$ "পরীক্ষা উদ্ধার"
- "Days remaining" $\to$ "দিন বাকি"
- "Daily Study Time" $\to$ "দৈনিক পড়ার সময়"
- "Review" $\to$ "রিভিউ"
- "Practice" $\to$ "অনুশীলন"
- "Take Quiz" $\to$ "কুইজ দিন"
- "Rescue plan generated" $\to$ "উদ্ধার পরিকল্পনা তৈরি হয়েছে"
- Bangla digit formatting for all days and hours via `GochanoLanguage.toBanglaDigits()`.

---

### 25. Exact Files Likely to Change in Subsequent Phases

#### Backend:
1. `backend/app/routers/ai_study.py`:
   - Add `ExamRescuePlanRequest` schema and endpoint `POST /api/ai/exam-rescue/plan`.
2. `backend/app/services/ai_service.py`:
   - Support `AiFeature.STUDY_PLAN` quota routing.

#### Flutter App:
1. `flutter_app/lib/services/api_service.dart`:
   - Add `generateExamRescuePlan` method.
2. `flutter_app/lib/features/study/presentation/rescue/`:
   - `exam_rescue_setup_sheet.dart` (Setup dialog / wizard)
   - `exam_rescue_preview_screen.dart` (Interactive plan preview & edit)
   - `exam_rescue_active_card.dart` (Hero card for active rescue)
   - `exam_rescue_models.dart` (Data classes & JSON deserializers)
3. `flutter_app/lib/features/study/presentation/planner/plan_view.dart`:
   - Add Exam Rescue banner action above date strip.
4. `flutter_app/lib/features/home/presentation/home_screen.dart`:
   - Add `_ExamRescueHeroCard` in Study Mode when active session exists.
5. `flutter_app/lib/features/study/presentation/workspace/workspace_view.dart`:
   - Add Exam Rescue tile in `_QuickAccess`.

---

### 26. Backend Changes Justification

- **Single New Endpoint**: `POST /api/ai/exam-rescue/plan` inside `backend/app/routers/ai_study.py`.
- **Justification**:
  - Existing `/api/study/plan` is strictly deterministic sorting of existing tasks.
  - Existing `/api/ai/assignment/plan` returns unstructured markdown prose.
  - Exam Rescue requires rigid, typed JSON validation with day-by-day itemization, durations, and material mapping.
  - Reuses the existing `_call_generate`, `_extract_material_text`, and quota infrastructure without modifying server architecture.

---

### 27. Firestore Changes Justification

- **Single Subcollection**: `users/{uid}/exam_rescue/{sessionId}`.
- **Justification**:
  - Stores high-level session status (`active`, `completed`), target exam date, and task IDs.
  - Scoped strictly inside the authenticated user's document path, adhering to existing Firestore security rules (`users/{userId}/**`).
  - All actionable schedule items are written to the existing `tasks` collection, requiring zero security rule revisions.

---

### 28. Security Implications

- **Authorization**: All endpoints protected with `@router.post(..., user: CurrentUser = Depends(require_student))`.
- **Resource Ownership**: Document IDs passed in `material_ids` are verified via `get_material_for_user(mid, user)`. Students cannot extract other users' private documents.
- **Injection Safety**: Text extracted from documents is escaped and wrapped in clear system boundary blocks.

---

### 29. Test Strategy

1. **Backend Unit Tests** (`backend/tests/test_ai_exam_rescue.py`):
   - Test JSON contract validation with mock AI output.
   - Test fallback heuristic generation when AI fails.
   - Test quota consumption under `AiFeature.STUDY_PLAN`.
   - Test extraction with 0, 1, and 3 materials.
2. **Flutter Unit & Widget Tests**:
   - `test/features/study/exam_rescue_models_test.dart`: Serialization/deserialization.
   - `test/features/study/exam_rescue_setup_sheet_test.dart`: Form validation & material picker callback.
   - `test/features/study/exam_rescue_preview_screen_test.dart`: Interactive item deletion and task conversion.

---

### 30. Competition Live-Demo Reliability Risks & Mitigation

| Risk | Likelihood | Impact | Built-in Mitigation |
|---|---|---|---|
| **AI API Latency / Hang during demo** | Medium | Critical | Primary provider is **GROQ** ($<2.5\text{ s}$). If timeout exceeds 8s, auto-fallback to instant local heuristic plan generator. Demo never stalls! |
| **No Internet / Weak Wi-Fi on demo stage** | Low | High | App detects network failure and offers immediate sample plan generation with offline local persistence. |
| **Quota Depletion during testing** | Low | High | Quota gate allows development override; fallback generator bypasses quota when provider fails. |
| **Empty Material Database on fresh demo device** | Medium | Medium | Exam Rescue supports zero-material mode: typing subject name alone generates a complete syllabus recovery plan. |

---

### 31. Recommended Implementation Phases

Following approval of this audit, implementation should proceed in disciplined, incremental phases:

- **Phase T2 — Data Models, API Contract & Backend Endpoint**
  - Implement `ExamRescuePlanRequest` / `Response` Pydantic models in `ai_study.py`.
  - Implement `POST /api/ai/exam-rescue/plan` with text extraction, AI prompt, JSON parser, and fallback generator.
  - Implement Dart models (`ExamRescuePlan`, `ExamRescueDay`, `ExamRescueItem`) and `ApiService.generateExamRescuePlan`.
- **Phase T3 — UI Foundation & Material Picker Integration**
  - Build `ExamRescueSetupSheet` using existing `showMaterialPicker`.
  - Connect input validation and loading states with `AiErrorBanner`.
- **Phase T4 — Interactive Preview Screen & Task Persistence**
  - Build `ExamRescuePreviewScreen` with day-by-day item editing and deletion.
  - Implement batch conversion of plan items into Firestore `tasks` with notification alarms.
  - Persist session document in `users/{uid}/exam_rescue`.
- **Phase T5 — Plan & Today Dashboard Integration**
  - Add Exam Rescue launch card to `PlanView` above the date strip.
  - Add `_ExamRescueHeroCard` to `HomeScreen` (Study Mode Today) displaying active rescue countdown and today's rescue tasks.
  - Add Quick Access tile in `WorkspaceView`.
- **Phase T6 — Quiz & Weak-Topic Progress Loop**
  - Connect "Take Quiz" action from rescue tasks directly into `QuizGeneratorScreen`.
  - Verify quiz completion marks rescue tasks done and updates weak topics.
- **Phase T7 — Hardening, Bilingual Audit & Competition Demo Polish**
  - Verify full English & Bangla localization.
  - Verify offline task creation and alarm scheduling.
  - Full end-to-end rehearsal under 30-second live demo conditions.
