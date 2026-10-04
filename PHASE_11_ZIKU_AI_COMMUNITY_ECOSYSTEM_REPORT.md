# Phase 11 - Ziku AI Learning Community Ecosystem

## Architecture

The existing `community_service.py` remains the source of truth for learning
posts, answers, groups, group quizzes, exam challenges and Learning Points.
`community_intelligence_service.py` is an adapter that connects those records
to the existing Learning Memory, Adaptive Learning and Content Studio signals.
No second AI brain or community storage system was introduced.

## AI community intelligence

Existing post analysis now tags subject, chapter, concept, difficulty and
related topics in addition to duplicate detection. Supported academic post
types now include Question, Solution, Notes, Achievement, Discussion and
Study Challenge.

The intelligence adapter adds:

- Learning-aware community feed markers.
- Similar public questions and weak-topic links when a question is posted.
- Group hotspot caching and common-struggle summaries.
- Existing Ziku moderator and group-quiz flows remain the AI moderation path.

## Groups, challenges and reputation

Existing study groups, member checks, group chat, shared resources, group
quizzes and server-graded friend challenges remain unchanged. New API aliases
reuse those implementations. Group quiz creation now awards the existing
Learning Points ledger +5 contribution points. Private mistakes, scores and
learning profiles are never included in community payloads.

## Learning graph and Ziku integration

Learning Memory now includes aggregate public discussion hotspots alongside the
student's topics, mistakes, revisions, generated content and improvement. The
shared Ziku chat context can say when other students are discussing the same
weak topic, while keeping the individual memory and community aggregate
separate.

## APIs

Existing community APIs remain available. Phase 11 adds:

- `GET /api/community/feed`
- `POST /api/community/questions`
- `POST /api/community/groups`
- `GET /api/community/group-insights`
- `POST /api/community/challenge`

All are authenticated student routes. Group and challenge operations reuse
existing membership and participant privacy checks.

## Firestore

Existing `groups`, `community_posts`, `community_reputation` and
`community_challenges` remain the source collections. Backend-only derived
rules were added for `group_insights`, `study_groups`, `group_members`,
`learning_points` and `exam_challenges` to prepare the teacher/classroom
architecture without exposing private learning data.

## Flutter UI

Added an authenticated AI Community Feed with subject/chapter/difficulty tags,
weak-topic relationship markers and question posting. Added a Contribution
Profile view for Learning Points and contributor ranking. Existing Group Detail,
Ziku Moderator and Challenge screens remain the active group workflows.

## Verification

- Backend compilation passed.
- Requested Phase 11 routes are present in OpenAPI.
- Focused Phase 11 Flutter analysis passed with no issues.
- Full `pytest -q`: 871 passed, 9 existing `/api/ai/attachment-question`
  failures.
- Full `flutter test`: 1,348 passed, 94 existing baseline failures.
- Full `flutter analyze lib`: six inherited Phase 9 adaptive infos; no Phase
  11 analyzer issues.
