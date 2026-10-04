# Phase 10.5 - Ziku Learning Memory

## Architecture

`learning_memory_service.py` is a derived intelligence layer over the existing
Mistake Memory, Academic Health, Adaptive Learning, focus, quiz, exam and
`ai_content` records. It does not introduce another model or generation
pipeline. It builds a student graph of topics, concepts, mistakes, revisions,
generated content and improvement, then caches the result under
`learning_memory/{studentId}`.

## Services

- `learning_memory_service.py` builds the graph, profile, progress and
  content-effectiveness evidence.
- `content_recommendation_service.py` ranks due revision, weak accuracy,
  repeated mistakes and demonstrated improvement into capped daily actions and
  notifications.
- Existing `ziku_content_service.py` remains the content-generation owner.
- Existing `mistake_memory_service.py` remains the source of mistake and review
  history.

Content effectiveness compares topic quiz accuracy before and after generated
content, counts later Mistake Memory occurrences, and records an outcome such
as `helped`, `stable`, `needs_review` or `awaiting_evidence`. The best content
type is derived from observed improvement rather than guessed by AI.

## APIs

All endpoints require `require_student` and are read-only from the client:

- `GET /api/learning/memory`
- `GET /api/learning/recommendations`
- `GET /api/learning/progress`
- `GET /api/learning/content-effectiveness`

The backend may refresh derived caches while serving these reads.

## Database and security

- `learning_memory/{studentId}` stores the graph and student profile.
- `content_effectiveness/{contentId}` stores per-content evidence.
- `learning_recommendations/{studentId}` stores daily recommendations and
  priority-scored notifications.

Firestore rules allow only the owning student to read these documents and deny
client writes. The trusted backend is the writer.

## Recommendation logic

Due spaced-repetition topics become flashcard recommendations first. Low topic
accuracy becomes quiz practice. Repeated mistakes become explanation/revision
recommendations. Notifications are capped to three and only emitted for due
revision or meaningful improvement, avoiding a notification flood.

## Flutter UI

- `LearningMemoryScreen` presents the Student Learning Profile, strongest
  subject, weak topics, best content type, study-time pattern and improvement
  bars showing before/now accuracy.
- `LearningRecommendationCard` is embedded in the study Home mode as “Ziku
  Suggests” and links to the profile.
- `learning_api_service.dart` provides the four authenticated reads.

## Chat integration

The existing Ziku prompt now receives learning-memory context containing the
student's recurring concept gap and measured improvement. Academic Health and
Study Coach context remain separate existing inputs, so the chat gains memory
without a second AI system.

## Verification

- Backend compilation passed and OpenAPI exposes all four `/api/learning`
  routes.
- New learning-memory Flutter UI passed focused analysis with no issues.
- Full `flutter analyze lib --no-pub` reports only six inherited Phase 9
  adaptive infos.
- `pytest -q`: 871 passed, 9 existing attachment-route failures in
  `/api/ai/attachment-question`.
- `flutter test`: 1,349 passed, 93 existing baseline failures. No failure was
  reported from the new learning-memory UI or APIs.
