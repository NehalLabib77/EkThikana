# EkThikana Firestore data model

## `users/{uid}`

Main fields:

```text
displayName
email
role                  student | general
university             student profile
department
semester
createdAt
updatedAt
```

Nested collections:

```text
saved_materials/{materialId}
material_state/{materialId}
material_state/{materialId}/page_notes/{noteId}
```

`material_state` stores PDF last page and bookmarks.

## Student-only collections

### `semesters/{id}`

```text
ownerId
name
createdAt
updatedAt
```

### `subjects/{id}`

```text
ownerId
semesterId
name
createdAt
updatedAt
```

### `notes/{id}`

```text
ownerId
ownerName
title
content
visibility            private | group | public
groupId
university
department
semester
semesterId
subjectId
keywords[]
createdAt
updatedAt
```

### `materials/{id}`

Metadata only. File bytes stay in private Supabase Storage.

```text
ownerId
ownerName
title
fileName
filePath
mimeType
sizeBytes
visibility            private | group | public
groupId
university
department
semester
subject
keywords[]
saveCount
downloadCount
createdAt
updatedAt
```

### `groups/{id}`

```text
name
description
ownerId
adminIds[]
memberIds[]
memberCount
inviteCode
createdAt
updatedAt
```

There is no messages collection.

## Student + General collections

```text
tasks/{id}
medicines/{id}
grocery_items/{id}
family_records/{id}
rent_records/{id}
saved_locations/{id}
wellness_records/{id}
```

All contain `ownerId`, timestamps and module-specific fields.

## Backend-only collections

```text
ai_usage/{uid_day}
upload_usage/{uid_day}
reports/{reportId}
```

Firestore security rules deny direct Flutter access to these backend-only collections.
