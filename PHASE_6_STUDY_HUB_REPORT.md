# Phase 6 — Study Hub + Group Sharing Architecture Contract

**Mode:** Read-only audit. No code changes were made.
**Scope:** Flutter Study Hub (`lib/screens/study/*`, `lib/screens/groups/*`), supporting services (`lib/services/*`), Firestore rules, backend `materials` router, indexes.

---

## 1. Semester → Subject → Resource — Contract

| Level | Collection | Doc-id | Storage path | Key fields |
|-------|-----------|--------|--------------|------------|
| Semester | `semesters/{semesterId}` | client | n/a | `ownerId`, `name`, `createdAt`, `updatedAt` |
| Subject | `subjects/{subjectId}` | client | n/a | `name`, `semesterId` |
| Note | `notes/{noteId}` | client | n/a | `title`, `content`, `groupId`, `semesterId`, `subjectId`, `ownerId`, `ownerName`, `pinned`, `tags`, `createdAt`, `updatedAt` |
| Material | `materials/{materialId}` | **server only** | `users/{uid}/{uuidHex}_{safeFilename}` | `ownerId`, `ownerName`, `title`, `subject`, `fileName`, `filePath`, `mimeType`, `sizeBytes`, `visibility`, `groupId`, `semesterId`, `saveCount`, `downloadCount`, `createdAt`, `updatedAt` |
| Material state (per-user) | `users/{uid}/material_state/{materialId}` | client | n/a | page position, bookmarks, highlights |

**Source:** `firestore_service.dart:51-131`, `materials.py:148,158-187`, `firestore.rules:22-36`.

---

## 2. Resource CRUD — Status

| Action | Status | Where | Notes |
|--------|--------|-------|-------|
| Upload (create) | **GREEN** | `MaterialUploadScreen` → `ApiService.uploadMaterial` → `POST /api/materials/upload` | `pdf, png, jpg, jpeg, doc, docx`. Filename uuid'd per upload. |
| Rename title | **RED** | No route, no UI | Workaround: delete + re-upload. Client writes to `materials` are denied by rules. |
| Replace file (swap PDF) | **RED** | No route, no UI | Storage path is `{uuidHex}_{name}` — must regenerate. |
| Update description/metadata | **RED** | No PATCH route; rules deny client writes | |
| Delete | **GREEN (owner)** | `MaterialsScreen` popup → `ApiService.deleteMaterial` → backend | Cascades: storage object + `storageUsedBytes` counter. Does **not** cascade to other users' `users/{uid}/saved_materials` — they render as "Unavailable material" (`saved_materials_screen.dart:46-47`). |

---

## 3. Group Sharing Contract

| Aspect | Implementation |
|--------|----------------|
| Collection | `groups/{groupId}` (top-level) |
| Doc shape | `name`, `description`, `memberIds: string[]`, `adminIds: string[]` (legacy `adminId`), `inviteCode`, `memberCount` |
| Membership model | Flat `memberIds` array on doc — **no `members/` subcollection** |
| Permission check | `request.auth.uid in memberIds` (rules) — plus `isGroupAdmin` for admin ops |
| "Share resource into group" | `MaterialUploadScreen` sends `groupId` in upload form; `POST /api/materials/upload` validates membership server-side (`materials.py:108-114`) |
| Leave group | `ApiService.leaveGroup` → `POST /api/groups/{id}/leave` (`group_detail_screen.dart:42-62`) |
| Visibility propagation | Pure **Firestore rules** — `canReadStudyDoc` reads `group.memberIds` per material read (1 extra doc read per material) |

**Source:** `firestore_service.dart:63-78`, `group_detail_screen.dart:34-62`, `materials.py:108-114`, `firestore.rules:22-36,53-57`.

---

## 4. Group Resource Permissions

| Role | Allowed actions |
|------|-----------------|
| Owner | upload, delete own materials, manage group |
| Member (non-owner) | read materials where `groupId == self.groupId && memberIds.contains(uid)` |
| Non-member | **No access** — `canReadStudyDoc` returns false; public visibility was removed (PART 3 correction 4) |

Note: `MaterialsScreen` popup only renders delete when `doc['ownerId'] == currentUid` (`materials_screen.dart:55,70-92`).

---

## 5. Focus Module

| Concept | Where | Schema |
|---------|-------|--------|
| Tasks | `tasks/{taskId}` (top-level, owner-gated) | `ownerId`, `title`, `dueAt`, `completedAt`, `priority`, etc. |
| Goals | **None** — no separate collection | |
| Reminders | **None** — derived from `tasks.dueAt` in `StudyPlanScreen` | |
| Focus session | Backend of record at `/api/study/focus/{start,id,list}` and `/api/study/stats` | `FocusSession{startTs, endTs, plannedMinutes, completed}` |
| Local mirror | `users/{uid}/focus_sessions/{focusId}` subcollection (rules-declared) | Not used by `FocusTimerScreen` — only HTTP is called (`focus_timer_screen.dart:56-80`) |
| Stats source | Server `GET /api/study/stats` → `StudyStats{todaySeconds, monthSeconds, streakDays, completedTaskCount}` | `study_service.dart:56-84` |

**Duplication risk:** `StudyStatsScreen` adds a raw Firestore `tasks` query (`study_stats_screen.dart:33-41`) **on top of** the server's `completedTaskCount` — double-counts.

---

## 6. Money + Statistics Location

| Screen | Service | Source | Index status |
|--------|---------|--------|--------------|
| `MonthlyMoneyScreen` | `MonthlyMoneyService` | Budget + remaining via `GET /api/budget/{monthly,remaining}`; transactions via **direct Firestore stream** on `financial_transactions` filtered by `(ownerId, type, status, date)` | **MISSING index** — `firestore.indexes.json` only declares `(ownerId, monthKey)` and `(ownerId, dateKey)`. Runtime failure until added. |
| `StudyStatsScreen` | `StudyService` (HTTP) + raw Firestore | Server `/api/study/stats` + `tasks` query | OK (only `ownerId` filter) |

**Coupling:** Money is **independent** of the academic hierarchy. Only `MaterialUploadScreen` reads `semesterId` to embed in the material doc (`material_upload_screen.dart:82-85`).

---

## 7. Files — Safe-to-Touch vs Must-Not-Touch

| Risk | Files | Reason |
|------|-------|--------|
| 🟢 Pure UI, safe to refactor | `study_screen.dart`, `materials_screen.dart`, `material_reader_screen.dart`, `focus_timer_screen.dart`, `study_plan_screen.dart`, `notes_screen.dart`, `note_editor_screen.dart` (UI parts), `groups_screen.dart`, `group_detail_screen.dart` (UI parts), `monthly_money_screen.dart`, `study_stats_screen.dart` | |
| 🟡 Path-string / rules-adjacent | `firestore_service.dart` | Centralizes `ownerStream`, `groupMaterials`, `groupNotes`, `myGroups`, `saveNote` — changing signatures breaks every screen. |
| 🟡 Path-string / rules-adjacent | `study_service.dart` | Maps to backend focus/stats response shape. |
| 🟡 Path-string / rules-adjacent | `material_upload_screen.dart` | Sends the upload payload shape; backend mirrors. |
| 🟡 Path-string / rules-adjacent | `offline_service.dart` | Uses `users/{uid}/material_state/{materialId}` + `page_notes/` subcollections (`firestore.rules:80-86`). |
| 🔴 Firestore rules | `firestore.rules` | `canReadStudyDoc`, `ownedUpdate`, `isGroupMember` shared across many collections — any change has broad blast radius. |
| 🔴 Backend router | `materials.py` | Entire `/api/materials/*` surface. |
| 🔴 Backend router | routers touching `notes`, `tasks`, `focus_sessions`, `monthly_budget`, `financial_transactions` | Field shape contract. |

---

## 8. Storage / DB Risks

| Risk | Severity | Detail |
|------|----------|--------|
| Orphan storage files | Medium | `materials.py:270-283` deletes file in `try/finally` + doc in `finally`. If Firestore write fails after storage write, rollback deletes the file (`materials.py:190-195`), but a crash between steps can orphan. `storageUsedBytes` is bumped before Firestore write — fails safely. |
| Public-bucket leaks | None | `materialUrl` returns a **signed URL with TTL** (`materials.py:200-218`). `visibility:public` rejected at backend (`materials.py:98-102`). Storage prefix is `users/{uid}/…` — never public. |
| Missing composite index | High | `MonthlyMoneyService.monthStream` queries `(ownerId, type, status, date)` — **no matching index** declared in `firestore.indexes.json`. Will fail at runtime. |
| SavedLibrary N+1 | Medium | `saved_materials_screen.dart:34-35` issues one `materials/{id}.get()` per saved item with no caching. Scroll = N doc reads. |
| Double-counting completed tasks | Low | `StudyStatsScreen` runs its own `tasks` query in addition to `/api/study/stats`. Cosmetic only. |
| Material doc survives delete cascade | Low | When owner deletes a material, other users' `users/{uid}/saved_materials` entries become stale and render as "Unavailable material" — not auto-cleaned. |

---

## 9. Recommended Implementation Order

1. **Add missing composite index** `(ownerId ASC, type ASC, status ASC, date ASC)` to `firebase/firestore.indexes.json` and deploy — unblocks `MonthlyMoneyScreen` runtime.
2. **Implement `PATCH /api/materials/{id}`** (owner-only: title, subject, visibility) plus a Flutter `MaterialRenameSheet` — unlocks rename + visibility flip without delete/reupload.
3. **Implement `PUT /api/materials/{id}/file`** for in-place replace — overwrite storage object bytes, reset `mimeType`/`sizeBytes`/`updatedAt`, audit `storageUsedBytes` — closes the swap-PDF gap and avoids quota churn.
4. **Centralize Firestore path constants** into a single `lib/services/firestore_paths.dart` and migrate hardcoded strings in `firestore_service.dart`, `offline_service.dart`, `saved_materials_screen.dart`, `monthly_money_service.dart` — reduces rules/rename blast radius.
5. **Cache `SavedMaterialsScreen` material lookups** via per-id memoization or a Firestore `CollectionReference.whereIn` join; remove the duplicate `tasks` query from `StudyStatsScreen` (use server `completedTaskCount` only).

---

## 10. Final Summary — 5 Questions

**Q1. Is the Study Hub safe to modify?**
Yes — it is well-bounded. All Firestore reads/writes go through `FirestoreService` + backend `/api/materials/*` + `/api/study/*` + `/api/budget/*`. Firestore rules already enforce per-doc authorization (`canReadStudyDoc`, `ownedUpdate`, `isGroupMember`). No background jobs, no realtime aggregations on the client.

**Q2. Which files can be changed?**
All `lib/screens/study/*` and `lib/screens/groups/*` UI files are safe to refactor visually. Backend routers can be extended (additive PATCH/PUT). Adding fields to Firestore docs is safe as long as old clients ignore them.

**Q3. Which files must NOT be touched?**
`firestore.rules` is the single highest-risk file — its helper functions (`canReadStudyDoc`, `ownedUpdate`, `isGroupMember`) gate dozens of collections. `materials.py` field shape is the source of truth for the entire material surface; renaming a field there breaks the Flutter reader. `firestore_service.dart` is the second-broadest touchpoint.

**Q4. Storage / DB risks?**
- **High:** missing composite index for `MonthlyMoneyService.monthStream` will fail at runtime.
- **Medium:** orphan storage file window between upload and Firestore write; `SavedMaterialsScreen` N+1 read pattern.
- **Low:** saved-library entries go stale on owner delete; `StudyStatsScreen` double-counts completed tasks.
- **None:** public-bucket leak risk (signed URLs + `visibility:public` rejected).

**Q5. Recommended implementation order?**
See §9: (1) fix the missing index, (2) add `PATCH /api/materials/{id}`, (3) add `PUT /api/materials/{id}/file`, (4) centralize Firestore paths, (5) cache saved-library lookups + remove duplicate task query.

---

**Audit complete.** No code was modified. Findings above are derived exclusively from the files listed in §7 and §8.