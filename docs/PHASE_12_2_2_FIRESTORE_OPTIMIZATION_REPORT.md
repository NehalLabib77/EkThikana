# Phase 12.2.2 — Firestore Optimization & Data Scaling Report

**Project:** Gochano / EkThikana
**Phase:** 12.2.2 — Firestore Optimization, Indexing & Session Data Scaling
**Status:** Implemented & Verified
**Date:** October 3, 2026

---

## 0. Scope

Phase 12.2.2 closes three scaling risks identified in the Phase 12.2 production audit:

1. **Unindexed composite queries** on collections that grow without bound (`analytics_events`, `tutor_sessions`, `exam_attempts`, `exam_results`, `mistakes`).
2. **Tutor session documents that embed full dialogue history**, so a single document grows with every Socratic turn and every read rewrites the whole transcript.
3. **Security rules that allowed session reads without proving ownership of nested turn data.**

No business logic changed: the endpoints, payload shapes and role gates are identical.

---

## 1. Composite Index Inventory

**File:** `firebase/firestore.indexes.json` (343 lines, LF endings, `fieldOverrides: []`)

| | Count |
|---|---|
| Composite indexes at HEAD `5a0bb7f` | 18 |
| Composite indexes now | **23** |
| Added in Phase 12.2.2 | **5** |
| Removed | **0** |

### 1.1 Indexes added

| Collection group | Fields | Why it is needed |
|---|---|---|
| `analytics_events` | `event_name` ASC, `timestamp` DESC | Activity feed / audit queries filter by event name and page newest-first. |
| `tutor_sessions` | `studentId` ASC, `createdAt` DESC | "My tutoring sessions" list is per-student, newest-first. |
| `exam_attempts` | `examId` ASC, `startedAt` DESC | Leaderboard / attempt history for one exam. |
| `exam_results` | `examId` ASC, `createdAt` DESC | Result history for one exam. |
| `mistakes` | `subject` ASC, `timestamp` DESC | Per-subject mistake/review queues. |

Every one of these is a single-field-inequality + sort query that Firestore would
otherwise reject with `FAILED_PRECONDITION` ("The query requires an index…") at
runtime.

### 1.2 Verification

`backend/tests/test_firestore_scaling.py::test_index_configuration_exists` parses
the file and asserts the presence of all five collection groups plus the exact
field order of the `analytics_events` and `tutor_sessions` entries.

---

## 2. Tutor Session Data Model (Subcollection Isolation)

**Service:** `backend/app/services/ziku_tutor_service.py`

### 2.1 Parent document — lightweight metadata only

`tutor_sessions/{sessionId}` stores only what a list view needs:

```text
sessionId, studentId, subject, topic, mode,
turnCount, mastery, createdAt, updatedAt, status
```

It never stores a turn body.

### 2.2 Turn documents — `tutor_sessions/{sessionId}/turns/{turnId}`

Each exchange is its own document:

```text
turnId, role, content, message, stepType, evaluation, timestamp
```

**Scaling effect:** appending a turn is a single-document write instead of a
full read-modify-write of an ever-growing array, and reading a list of sessions
no longer downloads every transcript ever produced.

`_save_session` writes the parent metadata document and the turn documents;
`_load_session` streams the `turns` subcollection, sorts by `(turnId, timestamp)`
and re-hydrates the legacy `history` field so downstream code is unchanged.

### 2.3 Migration fallback for pre-subcollection sessions

Sessions written before this phase keep their dialogue in the embedded
`history` array on the parent document. `_load_session` handles this
automatically:

1. Stream `turns`; if any document exists, use it (subcollection is canonical).
2. Otherwise fall back to `data["history"]` / `data["turns"]` on the parent and
   synthesise `turnId` values (`turn_1`, `turn_2`, …).
3. Populate `turns`, `history` and `turnCount` from whichever source won.

No backfill job is required: legacy documents stay readable indefinitely, and
the first write to a session promotes it to the subcollection layout.

Covered by `test_legacy_embedded_turn_fallback`.

### 2.4 Ownership & missing sessions

`_load_session` is the single read seam for every tutor route:

| Condition | Result |
|---|---|
| Document missing | `404 Not Found` |
| `studentId` and `uid` both differ from the caller | `403 Forbidden` |
| Firestore unavailable | `500 Database unavailable` |

Covered by `test_student_ownership_validation`.

---

## 3. Security Rules

**File:** `firebase/firestore.rules` (573 lines, 71 `match` blocks, 47 explicit
`allow create, update, delete: if false` write denials)

### 3.1 Phase 12.2.2 change

```text
match /tutor_sessions/{sessionId} {
  allow read: if isStudent() && (resource.data.studentId == request.auth.uid
                              || resource.data.uid == request.auth.uid);
  allow create, update, delete: if false;

  match /turns/{turnId} {
    allow read: if isStudent() && (
      get(/databases/$(database)/documents/tutor_sessions/$(sessionId)).data.studentId == request.auth.uid
      || get(/databases/$(database)/documents/tutor_sessions/$(sessionId)).data.uid == request.auth.uid
    );
    allow create, update, delete: if false;
  }
}
```

* The nested `turns` rule re-reads the **parent** session and compares its
  owner field, so knowing a session id is not enough to read its dialogue.
* Every tutor document is **server-write-only**: the client cannot create,
  mutate or delete sessions or turns through the rules layer at all.
* This is consistent with the rest of the collection, where 47 of the 71 match
  blocks deny all client writes.

---

## 4. Test Results (live runs)

### 4.1 Phase suite

```text
backend$ python -m pytest tests/test_firestore_scaling.py -q
5 passed, 2 warnings in 4.06s
```

| Test | Asserts |
|---|---|
| `test_index_configuration_exists` | 23 indexes present, 5 required groups, exact field order |
| `test_tutor_session_creation_stores_metadata_correctly` | Parent doc carries `studentId`, `topic`, `turnCount`, `createdAt`, `updatedAt`, `mastery` |
| `test_turn_storage_in_subcollection` | Turns land in `tutor_sessions/{id}/turns`, both roles round-trip |
| `test_legacy_embedded_turn_fallback` | Pre-subcollection `history` loads with normalised `turns`/`turnCount` |
| `test_student_ownership_validation` | Owner 200, other student 403, missing session 404 |

### 4.2 Full backend suite

```text
backend$ python -m pytest -q
942 tests collected
933 passed, 9 failed
```

The 9 failures are the pre-existing `test_ai_attachment.py` baseline: those
tests target `POST /api/ai/attachment-question`, a route that does not exist in
this application. They fail identically at HEAD `5a0bb7f`. **0 regressions.**

### 4.3 Static analysis

```text
flutter_app$ flutter analyze lib
No issues found!
```

---

## 5. Artifacts Changed

| File | Change |
|---|---|
| `firebase/firestore.indexes.json` | +5 composite indexes (18 → 23); normalised to LF |
| `firebase/firestore.rules` | Nested read-only `turns` rule with parent-ownership check |
| `backend/app/services/ziku_tutor_service.py` | Parent-metadata + `turns` subcollection write/read path and legacy `history` fallback |
| `backend/tests/test_firestore_scaling.py` | 5 tests covering indexes, metadata, subcollection, migration fallback, ownership |

### Explicitly not changed

* No endpoint, request/response schema, or role gate moved.
* No Firestore document was rewritten in place — legacy `history` arrays remain
  readable and are promoted lazily on the next write.
* No security rule was loosened; the change only adds a rule for a new
  subcollection.
