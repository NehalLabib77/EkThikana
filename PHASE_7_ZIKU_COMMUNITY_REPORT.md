# PHASE 7 - Ziku Learning Community 2.0

The Community tab stops being a group list with a chat bolted on. One
screen now holds three doors - **study groups** (Phase 1's surface, kept
as the default), a **Question Bank** where asking and answering is how a
student earns Learning Points, and **Exam Challenges** where any paper you
built can be raced against a classmate - and every group carries a
**Ziku Moderator** that answers a doubt, judges a disagreement, proposes
discussion topics and writes a group quiz from the group's own weak spots.
Nothing here is a second community system: groups, chat, membership and
invites are the ones Phase 1 built, and Phase 7 only adds what sits on top
of them.

## 1. What shipped

### Backend

* **`community_service.py` (1640 lines)** - the whole Phase 7 domain:
  learning posts + answers (`create_post` with AI tagging and duplicate
  detection, `list_posts`, `get_post`, `add_answer`), the three Learning
  Point awards (`accept_answer` +5, `mark_helpful` +3, `mark_useful` +10
  on notes), `leaderboard`, the exam-challenge lifecycle
  (`create_challenge`, `join_challenge`, `decline`, `start`,
  `submit` with server-side grading and a clamped duration), family links
  (`create_family_code` / `redeem_family_code` / `list_family_links`),
  group insights, the four Ziku Moderator calls and group quiz generation
  / attempt grading. It owns every constant the API validates against:
  `STUDY_CATEGORIES`, `POST_KINDS`, `GROUP_KINDS`, `POINT_RULES`.
* **Three routers, 26 routes** - `routers/community.py` (15),
  `routers/group_ziku.py` (8, mounted on `/api/groups` so membership
  gating stays in one place), `routers/family.py` (3).
* **`GroupCreate` carries `category` + `kind`** (`schemas.py`) and
  `routers/groups.py` rejects anything outside `STUDY_CATEGORIES` /
  `GROUP_KINDS` at the door. `class` / `teacher` groups also record an
  explicit `ownerRole: "teacher"` (spec 7.7).
* **Coach hand-off** - `study_coach_service.chat_context` appends one
  sentence built from `community_service.group_trend_line`, so Ziku Coach
  knows the student has a study group and what is hot in it.
* **`tests/test_community.py` (36 tests)** - posts/answers, all three
  point rules (including "cannot award yourself", "once only", "notes
  only"), leaderboard scopes, the challenge lifecycle with grading and
  duration clamping, the group-boundary 403s, insights, the four moderator
  calls, quiz generation without leaking the answer key, and family links.
* **`firestore.rules`** - a Phase 7 section: `community_posts` (+ answers)
  readable only inside the group and writable by nobody,
  `community_reputation` readable for the leaderboard but writable only by
  the trusted backend, `community_challenges` and `family_links`
  deny-all (API only), and `groups/{id}/quizzes` + its `attempts`
  deny-all so the `correct` field can never reach a client.

### Flutter

* **Segment switch (`community_view.dart`, rewritten)** - a horizontally
  scrollable `SegmentedButton` with `Groups` / `Questions` / `Challenges`,
  defaulting to `Groups` and rendering the *original* Firestore
  `StreamBuilder` for it. `initialSegment` lets a caller open on another
  door; nothing touches Firestore unless the groups segment is shown.
* **Question Bank (`question_bank_screen.dart`, 598)** - two filter
  `FilterChipBar`s (post kind, recent/popular), post cards with
  kind/category/answer/useful badges and `Solved` /
  `Similar question exists` flags, a `Top contributors` leaderboard under
  the feed, an `Ask` header action and the `showQuestionComposerSheet`
  composer (kind, title, details, category).
* **Question detail (`question_detail_screen.dart`, 423)** - answers with
  `Accepted` / `Helpful` badges and the three Learning Point controls,
  each rendered **only for the viewer the server would allow**: the asker
  alone sees *Accept answer*, a peer alone sees *Mark helpful*, a peer
  alone sees *Mark useful* on a notes post. A reply box appears on
  `question` posts only.
* **Exam Challenges (`challenge_list_screen.dart`, 775 +
  `challenge_take_screen.dart`, 540)** - invite/copy/join/cancel/decline,
  a new-challenge sheet with an exam picker off `/api/exams`, and a take
  screen that starts against the server deadline, counts down on a
  `Timer.periodic` **cancelled in `dispose()`**, auto-submits at 0:00,
  MCQ + short-answer input, and a result card with both sides' scores.
* **Ziku Moderator (`group_moderator_screen.dart`, 1103)** - one screen,
  six `FilterChipBar` sections: **Ask** (question -> Ziku answer),
  **Moderate** (two competing claims -> "Let's analyze both
  solutions..."), **Topics** (discussion proposals with reasons), **Quiz**
  (generate -> answer -> grade, plus the saved-quiz list), **Insights**
  (hot chapters, weak topics, question/quiz counts), **Points** (group
  leaderboard). Opened from the group app-bar `Ziku Moderator`
  `IconActionButton`.
* **Study categories (spec 7.5)** - `group_actions.dart` adds a
  `DropdownButtonFormField` to the create-group form; `community_labels.dart`
  is the single bilingual vocabulary for categories, post kinds, sorts,
  segments, moderator sections and challenge statuses.
* **Models (`community_models.dart`, 341)** - `CommunityPost` (with
  `duplicateOf` / `duplicateOfTitle` / `duplicateConfidence` / `answers`),
  `CommunityAnswer`, `ChallengeEntry` (`myScore` / `opponentScore` /
  `isOpen` / `isFinished`), plus the 21 typedefs every screen takes as an
  injection seam.
* **26 API methods** (`api_service.dart` 1834-2198) - 15 on
  `/api/community`, 8 on `/api/groups`, 3 on `/api/family`.
* **Tests - `test/community_phase7_test.dart` (25)**.

## 2. Design

| Rule | Why |
| --- | --- |
| One community, three doors | The groups segment still renders the original Firestore stream. A second group system would have forked membership, invites, chat and every Phase 1 test. |
| The server owns the ledger | Learning Points are awarded only by `community_service`, from the single `POINT_RULES` table, and `community_reputation` is read-only to clients. A client-writable score is a score that eventually gets gamed. |
| Posts and answers are backend-written | AI subject tagging, duplicate detection and point awards all happen in one trusted place. Clients read; they never write the document. |
| The answer key never leaves the server | Challenge questions are redacted on every fetch, and group quiz docs are `allow read, write: if false` - grading runs on the admin SDK. |
| Categories and kinds are closed vocabularies | `STUDY_CATEGORIES` / `POST_KINDS` / `GROUP_KINDS` are validated at the door (including `GroupCreate`), so the UI can offer a dropdown instead of a text box and the API can index on real values. |
| Points only for help | Three rules, no vanity metrics: an accepted answer +5 (asker decides), a helpful explanation +3 (once, never your own), useful notes +10 (first peer only). No reactions, no follower counts, no streaks. |
| Every networked widget takes a seam | The screens accept typedefs (`CommunityPostsFn`, `CommunityZikuAskFn`, ...) and fall back to `ApiService`. That is why the Phase 7 tests open no socket and never touch Firestore. |
| Body widgets vs pushed screens | `*_view` is pushed into the shell body; `*_screen` is pushed with `GochanoRoute.to`. Keeps the shell's `bottomNavigationBar` and the community scan rules intact. |
| One timer, cancelled in `dispose()` | The challenge clock is a `Timer.periodic` that stops at 0:00 and on disposal; a leaked periodic timer fails the widget test binding outright. |
| No local FAB, no `IntrinsicHeight` in Community | Preserves the Quick Add FAB owned by `GochanoShell` and the Phase 1 community layout scan. |

### Spec coverage

| Spec | Where it lives |
| --- | --- |
| 7.1 Study groups (categories, kinds, Ziku entry point) | `groups` segment (unchanged Firestore stream), `group_actions.dart` category dropdown, `group_detail_screen.dart` app-bar **Ziku Moderator** action, `GroupCreate.category`/`kind` validation |
| 7.2 AI Moderator Ziku (explain, judge, topics, quiz, insights, points) | `GroupModeratorScreen` + `POST /api/groups/{id}/ziku/{ask,moderate,topics,quiz}`, `GET /{id}/insights`, `GET /{id}/quizzes`, `POST /{id}/quizzes/{qid}/attempt` |
| 7.3 Question Bank (ask, answer, browse by kind/sort) | `QuestionBankView` + `showQuestionComposerSheet` + `QuestionDetailScreen`; `GET/POST /api/community/posts`, `GET /posts/{id}`, `POST /posts/{id}/answers`, kind + recent/popular filters |
| 7.4 Exam Challenge Mode (invite, race, score both sides) | `ChallengeListView` + `ChallengeTakeScreen`; `POST /challenges`, `/challenges/join`, `GET /challenges`, `GET /challenges/{id}`, `POST /challenges/{id}/{decline,start,submit}` |
| 7.5 study categories + learning post kinds | `STUDY_CATEGORIES` / `POST_KINDS` constants, `community_labels.dart` bilingual labels, `kPostKinds` filter, category field on every post, `GroupCreate` validation |
| 7.6 Learning Points (+5 / +3 / +10, leaderboard) | `POINT_RULES` + `accept_answer` / `mark_helpful` / `mark_useful` / `leaderboard`; the three controls in `QuestionDetailScreen`; `Top contributors` and the moderator's **Points** section |
| 7.7 parent / teacher architecture only (no UI) | `family.py` (3 routes) + `family_links` (rules deny-all) + `GroupCreate.kind` `class`/`teacher` with `ownerRole: teacher`. **No parent or teacher surface was built** - by design. |

## 3. Backend

### New

| File | What |
| --- | --- |
| `app/services/community_service.py` (1640) | The Phase 7 service layer - posts, answers, points, leaderboard, challenges, family links, insights, moderator, quizzes |
| `app/routers/community.py` (15 routes) | Question Bank + Learning Points + Exam Challenges |
| `app/routers/group_ziku.py` (8 routes) | Ziku Moderator + group quizzes, on `/api/groups` |
| `app/routers/family.py` (3 routes) | Family links, architecture only |
| `tests/test_community.py` (36 tests) | Whole domain incl. every point-rule edge case |

### Modified

* `app/main.py` - three router mounts (`/api/community`, `/api/groups`,
  `/api/family`).
* `app/schemas.py` - `GroupCreate.category` + `GroupCreate.kind`.
* `app/routers/groups.py` - category/kind validation, `ownerRole` for
  `class`/`teacher` groups, category/kind stored and returned.
* `app/services/study_coach_service.py` - `chat_context` appends
  `community_service.group_trend_line(uid)` (Phase 7 hand-off).
* `tests/conftest.py` - Phase 7 fakes for the new Firestore paths.
* `firebase/firestore.rules` - Phase 7 section (see above).

### Endpoints

**`/api/community`** (`routers/community.py`)

```
GET    /posts                       list (kind, category, groupId, popular, limit)
POST   /posts                       create (AI tag + duplicate detection)
GET    /posts/{post_id}             post + answers
POST   /posts/{post_id}/answers                 add an answer
POST   /posts/{post_id}/answers/{id}/accept     asker, +5
POST   /posts/{post_id}/answers/{id}/helpful    peer, +3
POST   /posts/{post_id}/useful                  notes, first peer, +10
GET    /leaderboard                 scope=global|group
POST   /challenges                  create from one of your papers
POST   /challenges/join             by invite code
GET    /challenges                  mine, both roles
GET    /challenges/{id}             participants only
POST   /challenges/{id}/decline
POST   /challenges/{id}/start       409 unless accepted
POST   /challenges/{id}/submit      graded server-side
```

**`/api/groups`** (`routers/group_ziku.py`)

```
POST   /{group_id}/ziku/ask                     explain a doubt in context
POST   /{group_id}/ziku/moderate                two claims -> analysis
POST   /{group_id}/ziku/topics                  discussion proposals
POST   /{group_id}/ziku/quiz                    generate a group quiz
GET    /{group_id}/insights                     hot chapters / weak topics
GET    /{group_id}/quizzes                      saved quizzes (no key)
GET    /{group_id}/quizzes/{quiz_id}            one quiz (no key)
POST   /{group_id}/quizzes/{quiz_id}/attempt    graded, returns the key back
```

**`/api/family`** (`routers/family.py`, architecture only)

```
POST   /link-code     parent/teacher issues a code
POST   /link/redeem   student redeems it
GET    /links         the student's links
```

### Database (spec -> collection)

| Spec | Collection / path | Notes |
| --- | --- | --- |
| 7.3 / 7.5 | `community_posts` (+ `community_posts/{id}/answers`) | `kind`, `category`, `groupId`, `duplicateOf*`, `acceptedAnswerId` |
| 7.6 | `community_reputation` | `{points, totalPoints, breakdown, displayName}` - client read-only |
| 7.4 | `community_challenges` | `inviteCode`, both sides, `timeLimitSeconds`, both `*Result` docs |
| 7.1 / 7.5 / 7.7 | `groups` (existing) | `category`, `kind`, `ownerRole` added |
| 7.2 | `groups/{gid}/quizzes` (+ `.../attempts`) | answer key in the quiz doc; both deny-all to clients |
| 7.7 | `family_links` | deny-all to clients, API only |
| - | `group_messages` (existing) | untouched - Phase 1 chat |

**Privacy:** every list/read path passes through `_public_post`,
`_public_answer`, `_public_challenge` or a redacted quiz shape. Client
writes to points, posts, answers, challenges, quizzes and family links are
all denied by `firestore.rules`, so a modified APK still cannot award
itself a point or read an answer key.

### Integrations

* `study_coach_service.chat_context` (L943) -> `community_service.group_trend_line`
  (L1214): one sentence about the student's group in Ziku Coach chat.
* Moderator and quiz generation spend the existing `AiFeature.CHAT` quota
  through `_ai(...)` + `_parse_json` - no new usage category, so the AI
  Usage dashboard stays truthful.
* The new-challenge sheet reuses `GET /api/exams` (`listExams`, Phase 3)
  as its paper picker.
* Group insights are derived from the group's own question posts and quiz
  attempts - no second analytics store.

## 4. Flutter

### New

| File | Lines | What |
| --- | --- | --- |
| `lib/features/community/domain/community_models.dart` | 341 | `CommunityPost`, `CommunityAnswer`, `ChallengeEntry` + 21 seam typedefs |
| `lib/features/community/presentation/community_labels.dart` | 135 | bilingual category / kind / sort / segment / section / status vocabulary |
| `.../question_bank_screen.dart` | 598 | `QuestionBankView` + `showQuestionComposerSheet` |
| `.../question_detail_screen.dart` | 423 | `QuestionDetailScreen` + the three point controls |
| `.../challenge_list_screen.dart` | 775 | `ChallengeListView` + join / new-challenge sheets |
| `.../challenge_take_screen.dart` | 540 | `ChallengeTakeScreen` - clock, answers, result |
| `.../group_moderator_screen.dart` | 1103 | `GroupModeratorScreen` + six sections |
| `test/community_phase7_test.dart` | 902 | 25 Phase 7 tests |

### Modified

* `community_view.dart` (253) - `SegmentedButton` switch; groups segment is
  the original stream; `initialSegment` constructor arg.
* `group_actions.dart` (255) - study-category dropdown on create;
  `createGroup(name, description, category: ...)`.
* `group_detail_screen.dart` (2303) - `Ziku Moderator`
  `IconActionButton` (`Icons.auto_awesome_outlined`) first in
  `GochanoAppBar.actions`, pushing `GroupModeratorScreen`.
* `community_screen.dart` (58) - header comment now describes the Phase 7
  surfaces; still no local FAB.
* `api_service.dart` (2198) - 26 Phase 7 methods (lines 1834-2198), all
  written to the Phase 3 contract discipline (no `?` on any `_get`/`_post`
  path, typed `Map<String, dynamic>` returns).

### Seams

Every Phase 7 screen takes function typedefs and falls back to
`ApiService`, e.g. `QuestionBankView(postsFn:, leaderboardFn:,
createPostFn:, postDetailFn:)`. The typedefs are declared to match the
`ApiService` signatures exactly, so `ApiService.listPosts` is a plain
tear-off. That is what lets the tests assert "the composer sent
`kind: question` with this title" without a server.

## 5. Verification

### Backend (`cd backend && .venv\Scripts\python.exe -m pytest -q`)

```
9 failed, 842 passed, 2 warnings in 44.01s
```

* `tests/test_community.py`: **36 passed**.
* The 9 failures are the pre-existing `tests/test_ai_attachment.py` set
  (identical before this phase).
* Baseline Phase 6: `9 failed, 806 passed` -> **`9 failed, 842 passed`**
  (+36 = exactly the new community suite), zero new failures.

### Flutter (`cd flutter_app`)

```
dart analyze lib                          -> No issues found!
dart analyze test/community_phase7_test.dart -> No issues found!
flutter test                              -> 1336 passed, 90 failed
```

* `test/community_phase7_test.dart`: **25 passed** - models (duplicate
  metadata, answers, challenge scores / open / finished), question bank
  (renders injected posts + leaders, kind/sort filter reloads, composer
  sends `kind`+`title`+`body`+`category`, empty CTA), question detail
  (Accept only for the asker, `Accepted` badge retires it, `Mark useful`
  only for a peer on notes, reply reaches `answerFn`), challenges (empty
  state both ways in, join seam gets the code, accepted -> start ->
  submit carries `answers: ['0']` and `durationSeconds`, **countdown timer
  cancelled on dispose**), moderator (ask, moderate with both claims,
  quiz generate -> answer -> grade, points = group scope leaderboard,
  insights hot/weak counts), segments (opens on Questions with no
  Firestore, switches to Challenges) and four source wiring scans.
* Baseline Phase 6: **1311 passed / 90 failed** -> **1336 passed / 90
  failed**: +25 new tests. The 90 failing tests are *identical* to
  baseline - compared test by test from the runner's `[E]` lines (the same
  navigation / Quick Actions / relationship source-scan tests that were
  already red before this phase). No regression.
* Protected surfaces re-run inside the same full run and unchanged:
  home mode filtering (15 study items - Phase 7 added **no** Home
  entries), home banned-word scan, translation smoke (bilingual pairs
  clean, EN != BN), API contract scan, theme parity, accessibility audit,
  physical-defects regression, community rebuild step 7.

## 6. Follow-ups (not blocking)

1. **Saved-quiz take path** - the moderator's **Quiz** section *lists*
   saved quizzes and can generate + take a fresh one, but it does not open
   a previously generated quiz. `getGroupQuiz` already exists in
   `api_service.dart` (the backend route and its no-answer-key payload are
   tested); what is missing is a detail screen that calls it and then
   `attemptGroupQuiz`.
2. **Question Bank paging** - the feed reads one page (`limit: 30`) and
   reloads on filter change; there is no infinite scroll or
   pull-to-refresh yet. The API already accepts `limit`, so this is a
   client-only addition.
3. **Family links (spec 7.7)** - routes, collection, rules and
   `ownerRole` are in place with deliberately **no UI**. A parent/teacher
   view will need its own permission check, not just a new screen.
4. **Moderator entry points** - Ziku Moderator is reachable from the
   group app bar only. A second door from the group body (e.g. beside the
   chat toggle) would make it discoverable for groups that never open the
   overflow menu.
5. **Challenge discovery** - challenges are listed for the two
   participants only (`challengerId` / `opponentId`). An "open challenges
   from your groups" surface would need a new read path plus an explicit
   privacy decision (scores stay private; only the invite travels).
