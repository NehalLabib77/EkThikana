# Phase 10 - Ziku AI Content Generation Studio

## Architecture

`backend/app/services/ziku_content_service.py` is the single orchestration
layer for generated explanations, flashcards, revision sheets and study packs.
It reuses `ai_service.generate` for the provider cascade and quota gate,
Mistake Memory for personal error context, Adaptive Learning for priorities,
Academic Health for exam context, and the existing `ai_study` source extraction
and quiz generator. No second AI provider or quiz-generation system was added.

Every generator has a deterministic fallback. Generated records are written by
the backend to `ai_content/{contentId}` with the student id, content type,
topic, source label, generated payload, timestamp and `reviewStatus`.

## Services and APIs

The student-only endpoints are:

- `POST /api/content/explain`
- `POST /api/content/flashcards`
- `POST /api/content/revision-sheet`
- `POST /api/content/study-pack`

Inputs accept a topic, pasted notes, an existing material id or note id. Study
packs compose summary, important topics, the existing quiz generator, generated
flashcards and a generated revision sheet.

AI feature usage is routed through the existing quota mechanism as
`content_generation`; lifetime activity counters track explanations,
flashcards, revision sheets and study packs.

## Firestore security

`firebase/firestore.rules` allows a verified student to read only documents
whose `studentId` matches the authenticated uid. Client creates, updates and
deletes are denied; the trusted backend writes generated content.

## Flutter UI

Added:

- `AiTeacherScreen` for personalized explanations.
- `FlashcardScreen` for generated cards and review dates.
- `RevisionSheetScreen` for exam-focused generated sheets.
- `StudyPackScreen` for pasted notes or existing uploaded material ids.

The client uses the existing Firebase-authenticated API pattern. Uploading is
still owned by the existing material upload pipeline; the study-pack flow
consumes its resulting material id rather than duplicating file storage.

## Ziku integration

The shared chat system prompt now receives a deterministic Phase 10 teacher cue
from Mistake Memory, while the existing Academic Health context remains a
separate input. This lets Ziku lead with the student's actual concept gap
before offering generic explanation.

## Verification

- Backend compile and OpenAPI registration passed for all four content routes.
- Focused Phase 10 Flutter analysis: passed with no issues.
- Repository-wide `flutter analyze lib --no-pub`: six inherited Phase 9
  adaptive style infos remain; no Phase 10 analyzer issue remains.
- `flutter test`: 1,352 passed and 90 existing baseline failures.
- `pytest -q`: the existing `/api/ai/attachment-question` 404 failures remain;
  no Phase 10 failure was reported.
