# Phase 3C Lite — Learning Data Foundation + AI Recommendations

**Date:** 2026-09-20
**Status:** ✅ Complete (Phase 3C-1 + 3C-2 + 3C-3)

---

## Summary

Phase 3C Lite implements the learning data foundation and AI-powered study recommendations:

1. **Phase 3C-1:** Quiz persistence — quiz results saved to Firestore
2. **Phase 3C-2:** Weak topic detection — aggregates quiz history to find weak areas
3. **Phase 3C-3:** AI study recommendations — personalized daily study suggestions

Quiz attempts are saved server-side, weak topics are identified from history, and the AI generates cached daily recommendations based on the student's full learning profile.

---

## Phase 3C-1: Quiz Persistence (Complete)

### Backend (`backend/app/routers/ai_study.py`)

**New Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/ai/quiz/save-result` | POST | Save completed quiz result to Firestore |
| `/api/ai/quiz/history` | GET | Fetch user's quiz history (newest first) |
| `/api/ai/quiz/history/{quizId}` | GET | Fetch a single quiz result with full details |

**Firestore Collection:** `users/{uid}/quiz_results/{quizId}`

**Document Schema:**
```javascript
{
  ownerId: string,           // Firebase UID
  subjectId: string,         // Topic/subject context
  materialId: string,        // Source material reference
  questions: array,          // Full question objects
  userAnswers: array,        // User's submitted answers
  correctAnswers: array,     // Correct answers
  totalQuestions: int,       // Question count
  correctCount: int,         // Correct answer count
  score: int,                // 0-100 percentage
  topicScores: map,          // Topic-level breakdown
  difficulty: string,        // 'easy'|'medium'|'hard'
  timeSpentSeconds: int,     // Quiz duration
  createdAt: timestamp,      // When quiz was taken
  dayKey: string,            // YYYY-MM-DD for daily queries
  monthKey: string           // YYYY-MM for monthly queries
}
```

### Flutter

**New Files:**

| File | Purpose |
|------|---------|
| `quiz_result_screen.dart` | Displays score, correct/wrong breakdown, topic performance, question review |
| `quiz_history_screen.dart` | Shows past quiz attempts with scores and statistics |

**Modified Files:**

| File | Changes |
|------|---------|
| `quiz_generator_screen.dart` | Added interactive quiz mode with answer selection, submit flow, navigation to results/history |
| `api_service.dart` | Added `saveQuizResult()`, `getQuizHistory()`, `getQuizResult()` methods |

### Firestore Configuration

**Security Rules** (`firebase/firestore.rules`):
```
match /quiz_results/{quizId} {
  allow create: if isStudent() && request.auth.uid == uid;
  allow read, delete: if isStudent() && request.auth.uid == uid;
  allow update: if false;
}
```

**Indexes** (`firebase/firestore.indexes.json`):
- `quiz_results`: `(ownerId ASC, createdAt DESC)` — history listing
- `quiz_results`: `(ownerId ASC, subjectId ASC, createdAt DESC)` — subject-filtered history

---

## Quiz Flow (Updated)

```
Previous:                    Updated:
Generate Quiz               Generate Quiz
    ↓                           ↓
Show Questions              Enter Quiz Mode (interactive)
    ↓                           ↓
Show/Hide Answer            Select Answers per Question
                                ↓
                            Submit Quiz
                                ↓
                            Save Result → Firestore
                                ↓
                            Navigate to QuizResultScreen
                                ↓
                            Show Score + Topic Performance + Question Review
```

---

## UI Features

### Quiz Result Screen
- Animated score circle with percentage
- Score label (Excellent/Good/Needs Improvement)
- Summary stats: Correct, Wrong, Total
- Topic performance bars with progress indicators
- Full question review with:
  - Your answer vs correct answer
  - Option highlighting (MCQ)
  - Explanation display
- Auto-saves result to backend on screen load

### Quiz History Screen
- Overall stats: Total quizzes, Average score, Best score, Accuracy
- List of past quizzes with:
  - Score circle
  - Correct/Total count
  - Difficulty level
  - Time spent
  - Date
  - Topic tags (top 3)
- Pull-to-refresh
- Empty state with CTA

### Quiz Generator Screen (Enhanced)
- History button in app bar
- After generation: "Start Quiz" button enters interactive mode
- Interactive mode: selectable options, answer counter
- Submit validates all questions answered
- Cancel returns to review mode

---

## Data Foundation for AI Personalization

### What's Now Available

| Signal | Source | Use Case |
|--------|--------|----------|
| Quiz scores | `quiz_results.score` | Knowledge level tracking |
| Topic performance | `quiz_results.topicScores` | Weak topic detection |
| Score trends | `quiz_results.createdAt` | Progress over time |
| Difficulty performance | `quiz_results.difficulty` | Difficulty calibration |
| Time per quiz | `quiz_results.timeSpentSeconds` | Study efficiency |
| Subject performance | `quiz_results.subjectId` | Subject-level analysis |

### What This Enables (Future Phases)

1. **Weak Topic Detection** — Aggregate `topicScores` across quizzes to identify consistently low-performing topics
2. **Spaced Repetition** — Use `createdAt` + `score` to schedule review of topics below mastery threshold
3. **Learning Profile** — Compute average scores per subject, difficulty preferences, study patterns
4. **Adaptive Quizzes** — Target weak topics with more questions, adjust difficulty based on history

---

## Testing

### Test Scenarios

1. ✅ Generate quiz from source material
2. ✅ Answer all questions in interactive mode
3. ✅ Submit quiz → result saved to Firestore
4. ✅ View quiz result with score breakdown
5. ✅ View quiz history with past attempts
6. ✅ Navigation: Generator → Quiz Mode → Result → Back
7. ✅ Firestore rules enforce owner-only access
8. ✅ Backend validation (score 0-100, required fields)
9. ✅ Flutter analysis: 0 errors, 0 warnings

### Backend Validation

- Score must be 0-100
- Questions, userAnswers, correctAnswers must have 1-50 items
- timeSpentSeconds must be 0-86400 (24h max)
- Only students can create quiz results
- Only owner can read/delete their results

---

## Files Changed (Phase 3C-1)

```
backend/app/routers/ai_study.py              # +150 lines (3 new endpoints)
firebase/firestore.rules                      # +8 lines (quiz_results rules)
firebase/firestore.indexes.json               # +32 lines (2 new indexes)
flutter_app/lib/services/api_service.dart     # +60 lines (3 new API methods)
flutter_app/lib/features/study/presentation/ai/
  quiz_generator_screen.dart                  # Rewritten (interactive mode)
  quiz_result_screen.dart                     # New (643 lines)
  quiz_history_screen.dart                    # New (333 lines)
```

---

## Phase 3C-2: Weak Topic Detection + Learning Insights (Complete)

### Backend

**New Service:** `backend/app/services/weak_topic_service.py`

**Functions:**

| Function | Purpose |
|----------|---------|
| `get_weak_topics(uid, threshold, min_attempts)` | Aggregate topicScores, return topics below threshold |
| `get_learning_summary(uid)` | Overall stats: total quizzes, avg score, strong/weak topics |

**Logic:**
1. Fetch all `quiz_results` for user (limit 100)
2. Aggregate `topicScores` across all quizzes
3. Compute average score per topic
4. Flag topics below threshold (default 60%) as weak
5. Generate recommendation text per weak topic
6. Sort by average score ascending (weakest first)

**New Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/ai/learning/weak-topics` | GET | Get weak topics with recommendations |
| `/api/ai/learning/summary` | GET | Get overall learning performance summary |

**Weak Topics Response:**
```json
{
  "weak_topics": [
    {
      "topic": "Normalization",
      "average_score": 45,
      "attempts": 3,
      "recommendation": "Review normalization concepts and practice more questions"
    }
  ],
  "count": 1,
  "threshold": 60
}
```

**Learning Summary Response:**
```json
{
  "total_quizzes": 5,
  "average_score": 72,
  "total_topics": 8,
  "strong_topics": [
    {"topic": "SQL Queries", "average_score": 85, "attempts": 3}
  ],
  "weak_topics": [
    {"topic": "Normalization", "average_score": 45, "attempts": 2}
  ]
}
```

### Flutter

**New File:** `learning_insights_screen.dart`

**Features:**
- Overall stats: Total quizzes, Average score, Total topics
- Weak topics section with score indicators and recommendations
- Strong topics section with performance metrics
- Empty state: "No quiz data yet" with CTA
- No weak topics state: "Great job! No weak topics detected"
- Pull-to-refresh
- Auto-loads data on screen init

**Navigation:** Study Workspace → Quick Access → "Insights" (secondary items)

### Files Changed (Phase 3C-2)

```
backend/app/services/weak_topic_service.py    # New (180 lines)
backend/app/routers/ai_study.py              # +35 lines (2 new endpoints)
flutter_app/lib/services/api_service.dart     # +20 lines (2 new API methods)
flutter_app/lib/features/study/presentation/ai/
  learning_insights_screen.dart               # New (370 lines)
flutter_app/lib/features/study/presentation/workspace/
  workspace_view.dart                         # +12 lines (import + nav item)
```

---

## Complete Data Flow

```
Student takes quiz
    ↓
QuizResultScreen saves to Firestore
    ↓
quiz_results collection populated
    ↓
weak_topic_service.py aggregates topicScores
    ↓
GET /api/ai/learning/weak-topics returns weak topics
    ↓
LearningInsightsScreen displays insights
    ↓
Student sees weak topics + recommendations
```

---

## Testing (Phase 3C-2)

1. ✅ Complete multiple quizzes with different topic scores
2. ✅ Verify topicScore aggregation across quizzes
3. ✅ Verify weak topic detection (avg < 60%)
4. ✅ Verify empty state when no quizzes exist
5. ✅ Verify "no weak topics" state when all scores >= 60%
6. ✅ Verify user isolation (cannot see other users' data)
7. ✅ Flutter analysis: 0 errors, 0 warnings
8. ✅ Backend compilation: verified

---

## Phase 3C-3: AI Study Recommendation (Complete)

### Backend

**New Service:** `backend/app/services/ai_recommendation_service.py`

**Functions:**

| Function | Purpose |
|----------|---------|
| `generate_study_recommendation(uid)` | Main entry: cache check → data collection → AI generation → cache save |
| `_collect_student_context(uid)` | Gathers weak topics, tasks, assignments, quiz history, focus time |
| `_build_recommendation_prompt(context)` | Builds AI prompt from student data |
| `_generate_fallback_recommendations(context)` | Rule-based fallback when AI is unavailable |
| `_fetch_cached_recommendation(uid)` | Check if today's recommendation is cached |
| `_save_cached_recommendation(uid, recs)` | Cache recommendation for today |

**Data Sources Collected:**

| Source | Collection | Fields Used |
|--------|------------|-------------|
| Weak topics | `quiz_results` (via weak_topic_service) | topicScores |
| Tasks | `tasks` | title, dueAt, subjectId (undone only) |
| Assignments | `tasks` (type=assignment) | title, dueAt, subjectId |
| Recent quizzes | `quiz_results` (last 5) | score, difficulty, subjectId |
| Focus time | `focus_sessions` (today) | accumulatedSeconds |

**Caching Strategy:**
- Stored in `users/{uid}/learning_cache/recommendation_{YYYY-MM-DD}`
- Refreshes once per day (new cache key each day)
- Skips AI call if today's cache exists
- Uses `AiFeature.CHAT` quota (daily limit)

**New Endpoint:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/ai/learning/recommendations` | GET | Get AI study recommendations (cached daily) |

**Recommendation Response:**
```json
{
  "recommendations": [
    {
      "title": "Review: Database Normalization",
      "reason": "Your average score is 45% after 3 attempts. Focus on fundamentals.",
      "priority": "high"
    },
    {
      "title": "Start a study session",
      "reason": "You've studied 15 min today. Aim for at least 1-2 hours.",
      "priority": "medium"
    }
  ],
  "cached": false
}
```

**Priority Levels:**

| Priority | Triggers |
|----------|----------|
| `high` | Weak topics (< 60%), overdue assignments |
| `medium` | Low study time (< 30 min/day), pending tasks |
| `low` | General suggestions, encouragement |

**Fallback Logic:**
If AI call fails, generates rule-based recommendations:
1. Top weak topics → high priority
2. Pending assignments → high priority
3. Low study time → medium priority
4. Undone tasks → low priority
5. No data → "Keep up the great work!"

### Flutter

**Updated File:** `learning_insights_screen.dart`

**New Features:**
- AI Study Recommendations section at top of insights
- Loading spinner while fetching recommendations
- Error handling with friendly message
- Empty state: "Take a quiz to get personalized recommendations"
- Recommendation cards with:
  - Priority color indicator (red/yellow/gray bar)
  - Title + priority badge
  - Reason text (1-2 sentences)
- Recommendations load automatically after summary

**API Method:** `ApiService.getStudyRecommendations()`

### Files Changed (Phase 3C-3)

```
backend/app/services/ai_recommendation_service.py  # New (230 lines)
backend/app/routers/ai_study.py                    # +15 lines (1 new endpoint)
flutter_app/lib/services/api_service.dart           # +10 lines (1 new API method)
flutter_app/lib/features/study/presentation/ai/
  learning_insights_screen.dart                     # Updated (+150 lines, recommendations section)
```

---

## Complete Data Flow (All Phases)

```
Phase 3C-1: Quiz Persistence
Student takes quiz → QuizResultScreen → save to Firestore → quiz_results collection

Phase 3C-2: Weak Topic Detection
quiz_results → weak_topic_service aggregates → GET /weak-topics → LearningInsightsScreen

Phase 3C-3: AI Study Recommendation
weak topics + tasks + assignments + quizzes + focus →
ai_recommendation_service collects → AI generates → cached daily →
GET /recommendations → LearningInsightsScreen
```

---

## Testing (Phase 3C-3)

1. ✅ User with weak topics gets recommendation mentioning those topics
2. ✅ User with pending tasks/assignments gets recommendation
3. ✅ User with low study time gets "start a session" suggestion
4. ✅ Empty user gets friendly "keep up the great work" message
5. ✅ Cache works: second call returns cached=true, no AI quota used
6. ✅ User isolation: cannot see other users' recommendations
7. ✅ Fallback: AI failure still returns rule-based recommendations
8. ✅ Flutter analysis: 0 errors, 0 warnings
9. ✅ Backend compilation: verified

---

## What's NOT Implemented (Future Phases)

This Phase 3C Lite is complete. The following are NOT implemented:

- ❌ Personalized quiz generation targeting weak areas
- ❌ Adaptive quiz difficulty
- ❌ Spaced repetition scheduling
- ❌ Real-time learning alerts
- ❌ Study schedule optimization
- ❌ Learning curve prediction

---

## Future Enhancements (Phase 3D+)

- AI quiz generation focused on weak topics
- Adaptive difficulty based on performance history
- Spaced repetition algorithm (SM-2 or similar)
- Push notifications for study reminders
- Weekly progress reports
- Study group recommendations
