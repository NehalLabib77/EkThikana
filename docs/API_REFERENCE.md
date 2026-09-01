# Gochano API reference

Base prefix:

```text
/api
```

Except for `/api/health`, protected routes expect:

```http
Authorization: Bearer <Firebase ID token>
```

The backend verifies the Firebase token and requires a verified email.

## Public

### GET `/api/health`
Render health check.

## Account

### GET `/api/me`
Returns authenticated profile identity and role.

### DELETE `/api/account`
Permanently deletes the authenticated user's Gochano data, owned materials, group membership and Firebase Authentication account.

## Student groups

### POST `/api/groups`
Student only.

```json
{
  "name": "CSE 5th Semester",
  "description": "Shared course materials"
}
```

Returns group id and invite code.

### POST `/api/groups/join`
Student only.

```json
{
  "invite_code": "AB12CD34"
}
```

There are deliberately no chat/message endpoints.

### POST `/api/groups/{group_id}/leave`
Student only. Leaves a group. If the owner leaves, ownership is transferred when members remain.

### POST `/api/groups/{group_id}/invite/reset`
Group admin only. Invalidates the old invite code and returns a new one.

## Materials

### POST `/api/materials/upload`
Student only. Multipart fields:

- `file`
- `title`
- `visibility`: `private`, `group`, or `public`
- `group_id`
- `university`
- `department`
- `semester`
- `subject`

Only PDF, PNG and JPEG signatures are accepted.

### GET `/api/materials/{material_id}/url`
Student only. Returns a temporary signed URL after checking ownership/public/group permission.

Optional query:

```text
?download=true
```

### POST `/api/materials/{material_id}/save`
Student only. Saves a reference in the user's Saved Library.

### DELETE `/api/materials/{material_id}`
Owner only.

## AI — Student only

### POST `/api/ai/note`

Supported actions:

```text
cleanup
summary
explain
key_topics
```

Automatic question generation and MCQ generation are intentionally absent.

### POST `/api/ai/pdf-question`

```json
{
  "material_id": "...",
  "question": "Explain this concept",
  "page": 5
}
```

`page` can be null to use extractable text from the document.

## Study planning

### POST `/api/study/plan`
Student only. Creates a deadline-priority plan from unfinished tasks.

This is rule-based planning, not quiz generation.

## Prescription OCR

### POST `/api/prescriptions/extract`
Student and General users.

Multipart prescription image/PDF. Returns OCR text only. The Flutter UI requires the user to verify medicine name, instructions and schedule before saving.

## Moderation

### POST `/api/reports`
Student only.

```json
{
  "target_type": "material",
  "target_id": "...",
  "reason": "copyright",
  "details": ""
}
```

Allowed reasons:

```text
spam
copyright
inappropriate
misleading
other
```

Reports are stored in the backend-only `reports` Firestore collection.
