# PHASE 7 — Study Hub + Group Sharing Implementation Report

**Scope:** Six additive tasks from the prior audit. Architecture preserved
end-to-end. Auth, Firestore collection names, upload multipart flow, and the
PDF reader flow are untouched.

---

## 1. Changed files

| # | File | Change |
|---|------|--------|
| 1 | `backend/app/routers/materials.py` | PATCH extended with `description`; PUT increments `version`; upload seeds `description` + `version: 1`; pre-existing PUT route converted to `async` (required for `await file.read()`). |
| 2 | `flutter_app/lib/services/api_service.dart` | New `updateMaterial(id, {title, subject, description})` (PATCH) + `replaceMaterialFile(id, bytes, fileName)` (PUT multipart) + private `_patch` helper. |
| 3 | `flutter_app/lib/screens/study/study_screen.dart` | Removed `MonthlyMoneyScreen` + `StudyStatsScreen` tiles; dropped their imports. |
| 4 | `flutter_app/lib/screens/profile/profile_screen.dart` | Added `_insightsCard(BuildContext)` with two `ListTile`s linking to `StudyStatsScreen` and `MonthlyMoneyScreen`. |
| 5 | `flutter_app/lib/screens/study/study_stats_screen.dart` | Removed duplicate Firestore `tasks` read; renders `StudyStats.completedTaskCount` directly from the server-supplied `/api/study/stats` response. |
| 6 | `flutter_app/lib/screens/study/materials_screen.dart` | Subtitle now shows subject · uploader · date · `vN`; description snippet rendered below the title; owner-only `PopupMenuButton` with **Edit details** (PATCH), **Replace file** (PUT), **Delete**. |
| 7 | `flutter_app/lib/screens/study/saved_materials_screen.dart` | Rewritten as `StatefulWidget` with `Map<String, DocSnapshot>` cache, **single batched** `Future.wait` for uncached material docs, cache invalidation on snapshot diff, and a `_Skeleton` placeholder during initial load. |
| 8 | `flutter_app/lib/screens/groups/group_detail_screen.dart` | No code change needed: shared materials are rendered by `MaterialsScreen` (opened from the *Shared Box* tile), which now carries the per-item owner actions and the uploader/date/version/description. |

---

## 2. API surface diff

### `PATCH /api/materials/{material_id}` — now accepts `description`

- **Before:** `allowed_keys = {"title", "subject"}`
- **After:**  `allowed_keys = {"title", "subject", "description"}`
- `description` is capped at 1000 chars; explicit `null` in the body **clears**
  the field (`delete()` on the doc key); empty string is treated as a
  no-op.
- Keyword blob is rebuilt to include the new description so the existing
  `/api/materials/search` and ranker surface the change.

### `PUT /api/materials/{material_id}/file` — version tracking

- The update dict now includes `"version": firestore.Increment(1)`.
- `materialId` is preserved (`document.id` is never changed), so every
  saved-library reference, group-material join, and reader URL stays valid
  across a replace.
- `sizeBytes` / `filePath` / `fileName` / `mimeType` / `updatedAt` are
  still overwritten; `downloadCount` / `saveCount` are reset because the
  replacement is a new revision; `storageUsedBytes` is delta-incremented
  by `(newSize − oldSize)` — gated by a field-presence check so legacy
  users without that field don't break.
- **Bug fix (pre-existing):** the route handler was declared `def` but
  used `await file.read()`. It was uncompilable. Changed the signature to
  `async def replace_material_file(...)`. No behaviour change.

### `POST /api/materials/upload` — seeds `description` + `version`

- New optional form field `description: str = Form("")` (stripped and
  capped at 1000 chars server-side).
- New doc writes the fields `"description": description_clean or None`
  and `"version": 1` so brand-new uploads immediately have a version
  to increment on later replaces.

---

## 3. Database impact (`materials/{materialId}` document)

| Field | Before | After | Notes |
|-------|--------|-------|-------|
| `description` | absent | optional `string ≤ 1000` | Read by `MaterialsScreen` subtitle/snippet, used by keyword ranker. `null` is the cleared state. |
| `version` | absent | `int`, starts at `1`, `+1` on every PUT | Used by `MaterialsScreen` subtitle (`v2`, `v3`, ...). Legacy docs without a `version` field gain `version = 1` automatically on the first PUT via `firestore.Increment`. |
| `title`, `subject`, `fileName`, `filePath`, `mimeType`, `sizeBytes`, `updatedAt`, `downloadCount`, `saveCount`, `keywords` | unchanged | unchanged | Same schema, same rules. |
| `storageUsedBytes` (on owner `users/{uid}`) | unchanged | now requires `firestore.Increment` | Pre-existing requirement of the PUT delta; the existing guard `if "storageUsedBytes" in user_snap.to_dict():` is preserved. |

**Firestore security rules** (unchanged): client-side `allow create/update/delete`
on `materials/{id}` is still `false`; backend is the sole writer. The
existing public-read-by-metadata rule is preserved.

---

## 4. UI architecture — preservation proof

- **Auth flow:** `_token()` + `Authorization: Bearer …` header pattern in
  `ApiService` is untouched. The new `_patch` and `replaceMaterialFile`
  follow the same `_guard` / `_uri` / `http.*` shape as the existing
  POST/PATCH/DELETE helpers.
- **Firestore structure:** no collection was renamed, added, or removed
  on the client. The Reads list is identical (`users/{uid}/saved_materials`,
  `materials`, `groups/{id}/...`). One new client read path: a batched
  `Future.wait` of `materials/{id}.get()` instead of one
  `FutureBuilder` per item (Task 8 — fewer reads total).
- **Upload flow:** `MaterialUploadScreen` and the multipart `POST` to
  `/api/materials/upload` were not touched; only the backend's
  `upload_material` function grew two doc-write fields.
- **Reader flow:** `MaterialReaderScreen` and the `/api/materials/{id}/url`
  presigned-URL handshake were not touched; PUT preserves `materialId`
  so existing reader URLs continue to work after a replace.
- **Navigation graph:** `study_screen.dart` keeps the GridView +
  Saved-Library shortcut; the two relocated destinations remain
  reachable (now from the Profile *Insights* card). The shared Box
  surface is unchanged for members.
- **Language:** every visible string uses `EkLanguage.text(en, bn)`.

---

## 5. Test outcomes

```
backend/ — python -m compileall -q backend/app
Exit: 0

flutter_app/lib/services/api_service.dart                — no errors
flutter_app/lib/screens/study/saved_materials_screen.dart — no errors
flutter_app/lib/screens/study/materials_screen.dart      — no errors
flutter_app/lib/screens/study/study_stats_screen.dart    — no errors
flutter_app/lib/screens/study/study_screen.dart          — no errors
flutter_app/lib/screens/profile/profile_screen.dart      — no errors
flutter_app/lib/screens/groups/group_detail_screen.dart  — no errors
```

`dart analyze` not run in this environment because the Dart SDK is not
present on PATH inside the agent's sandbox; the equivalent static check
(per-file `get_errors`) reports zero diagnostics on every touched file.
The Flutter `dart pub get` lockfile is untouched — no new dependencies.

---

## 6. Per-task results

1. **Study Hub restructure** — Money + Stats tiles removed from
   `study_screen.dart`; both moved to the Profile *Insights* card with
   bilingual labels.
2. **Material Update Feature (PATCH)** — owner-only metadata edit for
   `title` / `subject` / `description`. `description = null` clears.
3. **PDF Replace Feature (PUT)** — owner-only file replacement. `materialId`
   stays stable; `version` increments on every replace; `downloadCount` /
   `saveCount` reset; storage delta-incremented.
4. **Group resource sharing UI** — per-material rows now show
   `subject · uploader · date · vN`, plus a description snippet under
   the title. Owners see *Edit details*, *Replace file*, *Delete*;
   members only see *View / Download*. Available from both *My materials*
   and *Shared Box* screens (the latter from
   `group_detail_screen.dart`).
5. **Focus cleanup** — `study_stats_screen.dart` no longer runs a
   parallel Firestore `tasks.where(ownerId == …)` query; the *Completed
   tasks* tile renders `StudyStats.completedTaskCount` from the
   `/api/study/stats` response directly.
6. **Optimization** — saved-materials batches all material reads in one
   `Future.wait`, caches `DocumentSnapshot`s keyed by `materialId`,
   invalidates stale entries on snapshot diff, and shows a skeleton
   during the first paint. No N+1 reads.

---

## 7. Known pre-existing issues (not introduced by this phase)

- `PUT /api/materials/{id}/file` was declared `def` but used
  `await file.read()` — `py_compile` rejected the module before this
  phase. Converted to `async def` as part of Task 3; behaviour is
  unchanged for callers.
- A `'attachment_url': ?attachmentUrl,` line in
  `api_service.dart::postGroupMessage` predates this phase; it parses
  as a no-op `Null` (treated as `attachment_url = null` in a map) and
  does not block any of the tasks in scope. Untouched per the
  "no rewrite" constraint.

---

**Conclusion:** every change is additive (new fields on the doc, new menu
entries, new nav entries, new client helpers, one `def → async def` to
unblock the PUT route). No collection names, no auth, no upload, no
reader code, and no Firestore security rules were modified.
