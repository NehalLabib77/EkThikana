# Phase 3C-1 — Learning Data Foundation Audit

**Date:** 2026-09-20
**Scope:** Audit existing data infrastructure before implementing AI personalization

---

## Executive Summary

Gochano uses a **dual-database architecture**: Firestore for user/study data and PostgreSQL for CommuteBD transport data. Learning-related data exists across **5 Firestore collections** but lacks the depth needed for meaningful AI personalization. The system has **no quiz persistence**, **no material interaction tracking**, and **no topic knowledge model**.

---

## 1. Existing Data Sources

### 1.1 Tasks Collection
**Collection:** `tasks` (Firestore, top-level)

| Field | Type | Reusable for Personalization |
|-------|------|------------------------------|
| `ownerId` | String | ✅ User mapping |
| `title` | String | ⚠️ Subject extraction via NLP |
| `type` | String | ✅ `'task'` / `'assignment'` distinction |
| `done` | Boolean | ✅ Completion rate tracking |
| `completedAt` | Timestamp | ✅ Completion timing |
| `completedBy` | String | ✅ Collaborative tracking |
| `dueAt` | Timestamp | ✅ Deadline urgency calculation |
| `subjectId` | String | ✅ Subject-based analysis |
| `semesterId` | String | ✅ Semester context |
| `updatedAt` | Timestamp | ✅ Activity recency |

**Group Tasks:** `groups/{gid}/projects/{projectId}/tasks/{taskId}` includes `assigneeId`, `status`, `deadline`, `completedAt`, `completedBy`, `createdBy`

**Backend routers:** `study.py`, `part3.py`, `ai_study.py`

### 1.2 Materials Collection
**Collection:** `materials` (Firestore, top-level)

| Field | Type | Reusable for Personalization |
|-------|------|------------------------------|
| `ownerId` | String | ✅ User-material mapping |
| `title` | String | ⚠️ Topic extraction possible |
| `mimeType` | String | ✅ Content type classification |
| `university` | String | ✅ Institutional context |
| `department` | String | ✅ Departmental relevance |
| `semester` | String | ✅ Semester relevance |
| `subject` | String | ✅ Subject mapping |
| `keywords` | Array<String> | ✅ Topic tagging |
| `description` | String | ⚠️ Topic extraction possible |
| `saveCount` | Number | ✅ Popularity signal |
| `downloadCount` | Number | ✅ Engagement signal |
| `version` | Number | ⚠️ Content iteration tracking |
| `visibility` | String | ✅ `'private'`/`'group'`/`'public'` |
| `groupId` | String | ✅ Group material sharing |
| `createdAt` | Timestamp | ✅ Material age |
| `updatedAt` | Timestamp | ✅ Freshness |

**Subcollections:**
- `users/{uid}/saved_materials/{materialId}` — savedAt, title, fileName
- `users/{uid}/material_state/{materialId}` — page_notes subcollection
- `users/{uid}/offline_materials/{materialId}` — downloadedAt, localPath

**Backend router:** `materials.py`

### 1.3 Focus Sessions
**Collection:** `users/{uid}/focus_sessions/{focusId}`

| Field | Type | Reusable for Personalization |
|-------|------|------------------------------|
| `status` | String | ✅ `'running'`/`'paused'`/`'completed'`/`'cancelled'` |
| `label` | String | ✅ Study subject context |
| `plannedMinutes` | Number | ✅ Goal setting |
| `accumulatedSeconds` | Number | ✅ Actual focus duration |
| `startedAt` | Timestamp | ✅ Session timing |
| `completedAt` | Timestamp | ✅ Completion |
| `dayKey` | String | ✅ Daily pattern analysis |
| `note` | String | ⚠️ Activity context |

**Backend router:** `part3.py` (GET `/study/stats`)

### 1.4 AI Usage Metering
**Collection:** `ai_usage` (daily) / `ai_usage_monthly`

| Field | Type | Reusable for Personalization |
|-------|------|------------------------------|
| `uid` | String | ✅ User mapping |
| `day` | String | ✅ Usage frequency |
| `count` | Number | ✅ Total AI calls |
| `features` | Map<String, Number> | ✅ Per-feature usage breakdown |

**Backend:** `ai_service.py`

### 1.5 Study Goals (User Profile)
**Collection:** `users/{uid}`

| Field | Type | Reusable for Personalization |
|-------|------|------------------------------|
| `dailyGoalMinutes` | Number | ✅ Daily target |
| `weeklyGoalMinutes` | Number | ✅ Weekly target |
| `university` | String | ✅ Institutional context |
| `department` | String | ✅ Departmental context |
| `semester` | String | ✅ Academic level |
| `role` | String | ✅ `'student'` / `'general'` |

### 1.6 Notes Collection
**Collection:** `notes` (Firestore, top-level)

| Field | Type | Reusable for Personalization |
|-------|------|------------------------------|
| `ownerId` | String | ✅ User mapping |
| `title` | String | ⚠️ Topic extraction possible |
| `content` | String | ✅ Full text for topic analysis |
| `semesterId` | String | ✅ Semester context |
| `subjectId` | String | ✅ Subject mapping |
| `keywords` | Array<String> | ✅ Topic tagging |

### 1.7 Quizzes
**Status:** NO PERSISTENT STORAGE

Quizzes are generated on-demand via AI (`ai_study.py`) from materials/notes. Output is returned as JSON to the client and **never persisted server-side**.

**Backend router:** `ai_study.py` (POST `/quiz/generate`)

---

## 2. Database Architecture Summary

| Database | Purpose | Learning Data |
|----------|---------|---------------|
| **Firestore** | User data, study materials, tasks, notes, focus sessions, AI metering | ✅ Primary |
| **PostgreSQL (Supabase)** | CommuteBD transport data | ❌ None |
| **Firebase Auth** | Authentication, roles, verification | ✅ User identity |

**Learning data is 100% Firestore-based.** PostgreSQL is only used for CommuteBD.

---

## 3. Reusable Fields for Personalization

### Already Available (No Schema Changes)

| Signal | Source | Personalization Use |
|--------|--------|---------------------|
| Task completion rate | `tasks.done` | Motivation level estimation |
| Deadline adherence | `tasks.dueAt` vs `tasks.completedAt` | Time management patterns |
| Focus session duration | `focus_sessions.accumulatedSeconds` | Study capacity profiling |
| Focus session frequency | `focus_sessions.count` | Study habit consistency |
| Material engagement | `materials.saveCount`, `downloadCount` | Topic interest mapping |
| AI feature usage | `ai_usage.features` | Learning tool preferences |
| Subject coverage | `tasks.subjectId`, `materials.subject` | Knowledge domain mapping |
| Study goals | `users.dailyGoalMinutes`, `weeklyGoalMinutes` | Self-assessment alignment |

### Derived (Can Be Computed)

| Derived Signal | Source | Personalization Use |
|----------------|--------|---------------------|
| Daily study streak | Focus sessions `dayKey` | Consistency scoring |
| Subject time distribution | Focus sessions + subject context | Balance analysis |
| Task urgency patterns | `dueAt` → `completedAt` gaps | Procrastination detection |
| Material popularity | `saveCount` + `downloadCount` peer comparison | Community relevance |

---

## 4. Missing Data for AI Personalization

### Critical Gaps

| Missing Data | Impact | Priority |
|--------------|--------|----------|
| **Quiz scores / results** | Cannot track knowledge retention | 🔴 HIGH |
| **Material interaction tracking** | Cannot measure actual study effort | 🔴 HIGH |
| **Topic knowledge model** | Cannot build learning profiles | 🔴 HIGH |
| **Prerequisite mapping** | Cannot detect knowledge gaps | 🟡 MEDIUM |
| **Study pattern analytics** | Cannot optimize scheduling | 🟡 MEDIUM |
| **Material difficulty ratings** | Cannot calibrate recommendations | 🟡 MEDIUM |
| **Time-to-mastery tracking** | Cannot predict learning curves | 🟡 MEDIUM |

### Missing Fields per Collection

#### Tasks — Additional Fields Needed

| Field | Type | Purpose |
|-------|------|---------|
| `estimatedMinutes` | Number | Time estimation for task |
| `actualMinutes` | Number | Actual time spent |
| `difficulty` | String | `'easy'`/`'medium'`/`'hard'` |
| `topicTags` | Array<String> | Topic categorization |
| `repetitionCount` | Number | Times revisited |

#### Materials — Additional Fields Needed

| Field | Type | Purpose |
|-------|------|---------|
| `topicTags` | Array<String> | Topic categorization |
| `difficultyLevel` | String | `'beginner'`/`'intermediate'`/`'advanced'` |
| `estimatedReadTimeMin` | Number | Time-to-complete estimate |
| `prerequisiteIds` | Array<String> | Dependencies |
| `learningObjectives` | Array<String> | What the material teaches |
| `lastAccessedAt` | Timestamp | When last opened |
| `totalTimeSpentSeconds` | Number | Cumulative engagement |

#### Quizzes — New Collection Needed

| Field | Type | Purpose |
|-------|------|---------|
| `quizId` | String (PK) | Unique identifier |
| `ownerId` | String | User who took quiz |
| `materialId` | String | Source material |
| `subjectId` | String | Subject context |
| `questions` | Array<Object> | Question text + options |
| `userAnswers` | Array<String> | User responses |
| `correctAnswers` | Array<String> | Correct answers |
| `score` | Number | 0-100 percentage |
| `topicScores` | Map<String, Number> | Per-topic breakdown |
| `timeSpentSeconds` | Number | Quiz duration |
| `createdAt` | Timestamp | When quiz was taken |

#### Focus Sessions — Additional Fields Needed

| Field | Type | Purpose |
|-------|------|---------|
| `subjectId` | String | What subject was studied |
| `topicTags` | Array<String> | Specific topics covered |
| `qualityRating` | Number | Self-rated 1-5 |
| `interruptions` | Number | Focus breaks |

#### Notes — Additional Fields Needed

| Field | Type | Purpose |
|-------|------|---------|
| `topicTags` | Array<String> | Topic categorization |
| `subjectId` | String | Subject mapping |
| `qualityRating` | Number | Self-rated quality |

---

## 5. Recommended Schema for Phase 3C

### 5.1 New Collection: `quiz_results`

```
users/{uid}/quiz_results/{quizId}
├── quizId: string
├── ownerId: string (Firebase UID)
├── materialId: string (source material)
├── subjectId: string
├── semesterId: string
├── questions: array<{
│   ├── questionText: string
│   ├── options: array<string>
│   ├── correctAnswer: string
│   ├── userAnswer: string
│   ├── isCorrect: boolean
│   ├── topicTag: string
│   └── difficulty: string
│ }>
├── score: number (0-100)
├── topicScores: map<string, number> (topic -> % correct)
├── timeSpentSeconds: number
├── attemptNumber: number (1st, 2nd, etc.)
├── createdAt: timestamp
└── dayKey: string (YYYY-MM-DD)
```

### 5.2 New Collection: `learning_analytics`

```
learning_analytics/{analyticsId}
├── ownerId: string
├── dateKey: string (YYYY-MM-DD)
├── monthKey: string (YYYY-MM)
├── subjectId: string
├── metrics: map<string, any>
│   ├── tasksCompleted: number
│   ├── tasksDue: number
│   ├── focusMinutes: number
│   ├── quizzesTaken: number
│   ├── averageQuizScore: number
│   ├── materialsAccessed: number
│   └── studyStreakDays: number
├── computedAt: timestamp
└── version: number
```

### 5.3 New Collection: `topic_knowledge`

```
users/{uid}/topic_knowledge/{topicId}
├── topicId: string (derived from title/tags)
├── subjectId: string
├── masteryLevel: number (0-100)
├── confidence: number (0-100)
├── lastTestedAt: timestamp
├── testCount: number
├── averageScore: number
├── reviewHistory: array<{
│   ├── score: number
│   ├── date: timestamp
│   └── source: string ('quiz'|'task'|'note')
│ }>
├── nextReviewAt: timestamp (spaced repetition)
├── createdAt: timestamp
└── updatedAt: timestamp
```

### 5.4 New Collection: `material_interactions`

```
users/{uid}/material_interactions/{interactionId}
├── materialId: string
├── subjectId: string
├── interactionType: string ('view'|'download'|'save'|'read'|'quiz_from')
├── durationSeconds: number (for read sessions)
├── progressPercent: number (0-100)
├── createdAt: timestamp
└── dayKey: string
```

### 5.5 Schema Extensions to Existing Collections

#### `tasks` — Add Fields

```javascript
{
  estimatedMinutes: number,      // User estimate
  actualMinutes: number,         // Actual time spent
  difficulty: 'easy'|'medium'|'hard',  // User-assigned
  topicTags: string[],           // Topic categorization
  repetitionCount: number,       // Times revisited
  masteryScore: number           // 0-100 after completion
}
```

#### `materials` — Add Fields

```javascript
{
  topicTags: string[],           // Topic categorization
  difficultyLevel: 'beginner'|'intermediate'|'advanced',
  estimatedReadTimeMin: number,  // Time-to-complete
  prerequisiteIds: string[],     // Dependencies
  learningObjectives: string[],  // What it teaches
  lastAccessedAt: timestamp,     // Last opened
  totalTimeSpentSeconds: number, // Cumulative engagement
  interactionCount: number       // Total views/opens
}
```

#### `users` — Add Fields

```javascript
{
  learningProfile: {
    preferredStyle: 'visual'|'textual'|'interactive', // Derived
    optimalStudyMinutes: number,  // Derived from focus data
    peakPerformanceHours: string[], // Derived from session timing
    weakSubjects: string[],       // Derived from quiz scores
    strongSubjects: string[],     // Derived from quiz scores
    lastCalculatedAt: timestamp
  }
}
```

---

## 6. Data Flow Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    USER INTERACTIONS                     │
├─────────────────────────────────────────────────────────┤
│  Tasks → Materials → Focus Sessions → Quizzes → Notes   │
└───────────┬─────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────┐
│              EXISTING COLLECTIONS (Firestore)            │
├─────────────────────────────────────────────────────────┤
│  tasks/materials/focus_sessions/notes/ai_usage          │
└───────────┬─────────────────────────────────────────────┘
            │
            ▼ (Phase 3C additions)
┌─────────────────────────────────────────────────────────┐
│              NEW COLLECTIONS (Firestore)                 │
├─────────────────────────────────────────────────────────┤
│  quiz_results/learning_analytics/topic_knowledge/       │
│  material_interactions                                  │
└───────────┬─────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────┐
│              AI PERSONALIZATION ENGINE                   │
├─────────────────────────────────────────────────────────┤
│  Learning Profile → Study Recommendations → Adaptive    │
│  Quizzes → Spaced Repetition → Progress Predictions     │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Implementation Priorities

### Phase 3C-2: Quiz Persistence & Basic Analytics
1. Create `quiz_results` collection
2. Persist quiz scores server-side
3. Compute topic-level scores
4. Basic study streak calculation

### Phase 3C-3: Topic Knowledge Model
1. Create `topic_knowledge` collection
2. Map topics from materials/notes/tasks
3. Implement mastery score algorithm
4. Add spaced repetition scheduling

### Phase 3C-4: Learning Profile Generation
1. Create `learning_analytics` collection
2. Aggregate daily/weekly metrics
3. Compute learning style indicators
4. Generate personalized recommendations

---

## 8. Key Files Reference

| Component | File Path |
|-----------|-----------|
| Firestore security rules | `firebase/firestore.rules` |
| Firestore composite indexes | `firebase/firestore.indexes.json` |
| AI Study router (quizzes) | `backend/app/routers/ai_study.py` |
| Study planner router | `backend/app/routers/study.py` |
| Focus sessions router | `backend/app/routers/part3.py` |
| Materials router | `backend/app/routers/materials.py` |
| AI service + quota | `backend/app/services/ai_service.py` |
| Auth middleware | `backend/app/core/auth.py` |
| Flutter Firestore client | `flutter_app/lib/services/firestore_service.dart` |

---

## 9. Conclusion

The existing data foundation provides **strong user identity** (Firebase Auth), **material metadata** (subject, department, semester), and **basic activity signals** (focus sessions, task completion). However, it lacks the **knowledge-level tracking**, **quiz persistence**, and **interaction analytics** needed for meaningful AI personalization.

**What we have:** User identity, material catalog, task completion, focus duration, AI usage metering.

**What we need:** Quiz scores, topic knowledge model, material interaction tracking, learning analytics aggregation.

The recommended schema additions in Section 5 provide a clear roadmap for Phase 3C implementation without disrupting existing functionality.
