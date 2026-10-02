# PHASE 10.6 — ZIKU ANALYTICS INTELLIGENCE FOUNDATION REPORT

**Phase:** 10.6 — Ziku Analytics Intelligence Foundation  
**Status:** COMPLETE & VERIFIED  
**Architecture Contract:** Zero Phase 12 tutor behavior; Zero duplicate learning brains; Reuses all 10 existing systems.  

---

## 1. Executive Summary & Design Invariants

Phase 10.6 establishes a single, canonical, privacy-preserving analytics infrastructure for the Gochano and Ziku learning ecosystem. 

### Core Invariants Maintained:
1. **Foundation Only:** Pure analytics and data aggregation. No conversational tutor logic, no predictive algorithms (reserved for Phase 15), and no secondary student learning brains were created.
2. **Reuse Existing Engines:** Reuses AI usage counters, Mistake Memory, Learning Memory, Adaptive Learning, Quiz Engine, Real Exam Simulator, Focus Sessions, AI Content Studio, Community, and Study Coach.
3. **Backend-Only Storage:** Analytics events are recorded solely through backend operations. Client apps cannot directly read or write the platform-wide analytics event collection.
4. **Privacy-Preserving:** Raw conversation transcripts, private notes, document contents, student/parent PII, and exam answer keys are strictly discarded at the normalization boundary. Only aggregate educational signals are stored and analyzed.
5. **Deterministic Admin Calculations:** Platform metrics, subject demand, and topic difficulty scores are derived strictly using arithmetic algorithms—zero LLM calls for counting or ranking.

---

## 2. Event Taxonomy

Events represent meaningful educational milestones across the app rather than granular UI taps:

| Category | Event Name | Normalized Metadata Dimensions |
|---|---|---|
| **AI** | `ai_chat_used` | `feature`, `subject`, `topic`, `duration_seconds` |
| | `ai_teacher_used` | `feature`, `subject`, `topic`, `chapter` |
| | `content_generated` | `content_type`, `subject`, `topic`, `feature` |
| | `study_pack_created` | `content_type`, `subject`, `topic`, `total` |
| **Learning** | `quiz_completed` | `subject`, `topic`, `chapter`, `score`, `total`, `mistake_count` |
| | `flashcard_reviewed` | `subject`, `topic`, `score`, `total` |
| | `revision_completed` | `subject`, `topic`, `source` (`successful` / `unsuccessful`) |
| | `mistake_corrected` | `subject`, `topic`, `mistake_count` |
| **Exam** | `exam_started` | `subject`, `feature`, `exam_type` |
| | `exam_completed` | `subject`, `feature`, `exam_type`, `score`, `total`, `mistake_count`, `duration_seconds` |
| **Focus** | `focus_session_completed` | `duration_seconds`, `feature`, `subject` |
| **Community** | `community_question_posted` | `subject`, `topic`, `feature` |
| | `community_answer_given` | `subject`, `topic`, `feature` |
| | `study_group_joined` | `feature` |
| | `group_quiz_created` | `subject`, `topic`, `total` |
| | `challenge_completed` | `feature`, `score`, `total` |

---

## 3. Canonical Storage & Security Rules

### 3.1 Document Schema (`analytics_events/{eventId}`)
Every event document adheres to a single canonical schema:
```json
{
  "eventId": "event_4f88c...",
  "userId": "usr_98124...",
  "eventName": "quiz_completed",
  "timestamp": "2026-10-02T18:15:30.123456Z",
  "subject": "Physics",
  "topic": "Optics",
  "chapter": "Refraction",
  "feature": "quiz",
  "content_type": "mcq",
  "score": 8,
  "total": 10,
  "mistake_count": 2,
  "duration_seconds": 320,
  "source": "quiz_save_result",
  "exam_type": "mcq",
  "event_date": "2026-10-02"
}
```

### 3.2 Firestore Security (`firebase/firestore.rules`)
```javascript
// Phase 10.6: analytics are backend-only aggregate events. Students and
// normal clients must never read platform-wide activity or write events.
match /analytics_events/{eventId} {
  allow read, write: if false;
}
```

---

## 4. Privacy Boundary & Exclusions

`normalize_metadata()` functions as a whitelist filter. All non-whitelisted keys are automatically dropped before writing to Firestore.

### Explicitly Excluded & Stripped Fields:
- Raw Ziku conversation turns and chat transcripts (`chat_transcript`, `raw_chat`, `message_body`)
- Student private notes and personal scratchpads (`note_body`, `raw_notes`)
- Uploaded syllabus or document file contents (`extracted_text`, `file_bytes`)
- Student written answer texts and exam answer keys (`answer_text`, `answer_key`)
- Parent/family private information (`parent_email`, `phone_number`, `parent_name`)

---

## 5. Deterministic Aggregation Formulas

### 5.1 Subject Demand
- Groups events within the time window (`days` = 7, 30, 90) by `subject`.
- Returns sorted descending by event volume:
$$\text{Ranked Subjects} = \operatorname{sort\_desc}(\text{eventCount})$$

### 5.2 Topic Difficulty Metric
Calculated over topics with at least `MIN_TOPIC_SAMPLE = 3` quiz attempts:
1. **Wrong-Answer Rate ($R_{\text{wrong}}$):**
   $$R_{\text{wrong}} = \frac{\text{wrong}}{\max(1, \text{questions})}$$
2. **Repeated Mistake Rate ($R_{\text{repeat}}$):**
   $$R_{\text{repeat}} = \min\left(1.0, \frac{\text{repeatedMistakes}}{\max(1, \text{samples} \times 3)}\right)$$
3. **Low-Accuracy Quiz Rate ($R_{\text{low}}$):**
   $$R_{\text{low}} = \frac{\text{lowAccuracyQuizzes}}{\text{samples}}$$
4. **Unsuccessful Revision Rate ($R_{\text{revision}}$):**
   $$R_{\text{revision}} = \min\left(1.0, \frac{\text{unsuccessfulRevisions}}{\text{samples}}\right)$$
5. **Composite Difficulty Score ($S_{\text{difficulty}}$):**
   $$S_{\text{difficulty}} = \operatorname{round}\Big(100 \times \big(0.45 R_{\text{wrong}} + 0.30 R_{\text{repeat}} + 0.20 R_{\text{low}} + 0.05 R_{\text{revision}}\big), 1\Big)$$

**Transparency Mandate:** Each returned topic includes the exact supporting metrics and the mandatory interpretation disclaimer:
> *"Observed platform struggle, not an objective property of the topic."*

---

## 6. Admin Authorization & API Surface

### 6.1 Endpoints (`backend/app/routers/admin_analytics.py`)
Mounted under `/api/admin/analytics`:
- `GET /api/admin/analytics/overview?days={7|30|90}`
- `GET /api/admin/analytics/subjects?days={7|30|90}`
- `GET /api/admin/analytics/topics?days={7|30|90}`
- `GET /api/admin/analytics/features?days={7|30|90}`

### 6.2 Authentication & Role Enforcement
Protected by `require_admin` dependency:
- Unauthenticated requests $\to$ `401 Unauthorized`
- `student` role $\to$ `403 Forbidden ("Administrator account required")`
- `general` role $\to$ `403 Forbidden ("Administrator account required")`
- `admin` role $\to$ `200 OK`

---

## 7. Flutter Admin Dashboard UI

### 7.1 Architecture
- **Screen:** `lib/features/admin/presentation/admin_analytics_screen.dart`
- **Client Service:** `ApiService.adminAnalyticsOverview()`, `adminAnalyticsSubjects()`, `adminAnalyticsTopics()`, `adminAnalyticsFeatures()`
- **Access Point:** `lib/features/profile/presentation/profile_screen.dart` surfaces `_AdminAnalyticsCard` strictly when `role == 'admin'`.

### 7.2 UI Components & States
- **Platform Overview:** Active Students, AI Requests, Quiz Attempts, Exam Attempts, Content Generated.
- **Subject Demand:** Ranked list with event counters and relative distribution badges.
- **Topic Difficulty:** Color-coded difficulty badges (Red $\ge$ 60, Orange $\ge$ 35, Green $<$ 35), sample size, wrong rate %, repeated mistake counters, and the required disclaimer.
- **Feature Usage:** Breakdown chips showing event counts per feature name.
- **Time Filters:** Interactive chips for 7 Days, 30 Days, and 90 Days.
- **Lifecycle States:** Loading (`CircularProgressIndicator`), Empty State ("No Analytics Available"), Error State (with Retry button), and Access Restricted view (`Icons.lock_outline_rounded`).
- **Privacy Notice:** Persistent footer stating that platform analytics only operate on aggregate counters and never expose private student data.

---

## 8. Preparation for Future Phase 15 (Exam Intelligence)

To support Phase 15 predictive intelligence without needing data migration, events preserve:
- `subject`
- `chapter`
- `topic`
- `exam_type`
- `event_date`

This allows future modules to correlate historical exam performance with topic difficulty and aggregate mistake patterns.

---

## 9. Verification & Exact Regression Totals

### 9.1 Backend Test Results (`python -m pytest tests/ -q`)
- **Baseline Before Phase 10.6:** 871 passed / 9 known attachment-route failures
- **New Tests Added:** 14 focused tests in `backend/tests/test_analytics_and_admin.py`:
  - `test_normalize_metadata_whitelists_allowed_dimensions`
  - `test_privacy_exclusions_disallow_raw_student_content`
  - `test_normalize_metadata_handles_invalid_types_and_defaults_date`
  - `test_track_event_persists_canonical_event`
  - `test_track_event_rejects_unknown_event_or_missing_user`
  - `test_admin_analytics_requires_authentication`
  - `test_admin_analytics_forbids_student_account`
  - `test_admin_analytics_forbids_general_account`
  - `test_admin_analytics_allows_admin_account`
  - `test_subject_demand_aggregation`
  - `test_feature_usage_aggregation`
  - `test_topic_difficulty_excludes_topics_below_minimum_sample`
  - `test_topic_difficulty_includes_topics_meeting_minimum_sample`
  - `test_time_filtering_excludes_events_past_cutoff`
- **Total After Phase 10.6:** **885 passed / 9 known attachment-route failures**
- **Regression:** Zero regressions.

### 9.2 Flutter Analysis (`flutter analyze lib/`)
- **Result:** `No issues found! (ran in 8.2s)` (0 errors, 0 warnings, 0 info lints)

### 9.3 Flutter Widget & Unit Test Results (`flutter test`)
- **Baseline Before Phase 10.6:** 1,352 passed / 90 failed
- **New Tests Added:** 7 tests in `flutter_app/test/admin_analytics_test.dart`:
  - `profile_screen surfaces AdminAnalyticsScreen only for role == admin`
  - `admin_analytics_screen defines time range filters 7, 30, and 90 days`
  - `admin_analytics_screen enforces topic difficulty disclaimer`
  - `admin_analytics_screen has explicit privacy notice and no student profile leak`
  - `non-admin role displays Access Restricted view`
  - `general role displays Access Restricted view`
  - `admin role initially renders loading indicator then handles network error cleanly`
- **Total After Phase 10.6:** **1,359 passed / 90 failed**
- **Regression:** Zero regressions.

