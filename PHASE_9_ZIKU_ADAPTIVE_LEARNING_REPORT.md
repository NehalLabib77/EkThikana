# Phase 9 - Ziku Adaptive Learning Engine

## Architecture

`backend/app/services/ziku_adaptive_service.py` is a cache-first aggregation
layer. Mistake Memory remains the source of truth for mistakes, occurrences and
spaced-review dates. Academic Health remains the source of truth for quiz,
topic and exam signals. Phase 9 owns only derived adaptive caches.

The deterministic path works without an AI provider. The textbook optionally
uses the shared `ai_service.generate` cascade and stores the deterministic
mistake-based chapter when generation is unavailable.

## APIs

All routes are student-only and read-only:

- `GET /api/adaptive/revision-queue`
- `GET /api/adaptive/curriculum`
- `GET /api/adaptive/textbook`
- `GET /api/adaptive/difficulty`
- `GET /api/adaptive/learning-path`

Daily queue and curriculum responses are cached by UTC day. Textbook and
learning-path responses use stable current documents; backend cache writes are
not exposed to clients.

## Adaptive decisions

Revision priority combines occurrence frequency, overdue review risk, exam
urgency and low topic accuracy. Curriculum time is split into concept review,
practice and revision. Difficulty uses stored `difficultyScores` when present,
and learning paths insert a basic prerequisite for very low topic accuracy.

## Database and security

The backend writes these collections under each student document:

- `adaptive_revision/{dayKey}`
- `adaptive_curriculum/{dayKey}`
- `adaptive_textbooks/{docId}`
- `adaptive_learning_paths/{docId}`

`firebase/firestore.rules` permits the owning student to read these derived
documents and denies client create, update and delete operations.

## Integrations

The shared Ziku chat system prompt receives the adaptive focus through
`ai_service._adaptive_context`. Flutter includes adaptive API methods, an
adaptive dashboard, revision queue, AI textbook and a reusable coach-dashboard
section.

## Verification

- Backend syntax: passed with `py_compile`.
- OpenAPI registration: all five `/api/adaptive/*` paths present.
- Focused Flutter analysis: no errors; six existing style infos remain.
- `pytest -q`: 10 unrelated pre-existing failures in
  `/api/ai/attachment-question` (404); no Phase 9 test failure was reported.
- `flutter test`: 1352 passed, 90 pre-existing failures. The failures are
  concentrated in existing shell/search and other baseline tests; the saved
  output included no Phase 9 adaptive test failure.
