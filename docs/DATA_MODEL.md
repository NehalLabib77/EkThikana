# Gochano data model — current scope

## Users

`users/{uid}`: displayName, email, role (`student|general`), optional university/department/semester, timestamps.

## Student-only

- `semesters/{id}`
- `subjects/{id}`
- `notes/{id}` (`private|group|public`)
- `materials/{id}` (private Supabase file metadata)
- `groups/{id}`
- `users/{uid}/saved_materials/{materialId}`
- `users/{uid}/material_state/{materialId}` + page notes

No messages/chat collection exists.

## Student + General

- `tasks/{id}`
- `medicines/{id}`
- `medicine_doses/{id}`
- `bazar_items/{id}`
- `daily_expenses/{id}`
- `commute_trips/{id}`
- `financial_transactions/{id}`

## Central expense transaction

```text
ownerId
userId
type = expense
source = daily | bazar | medicine | commute
sourceRecordId
category
title
amount
date
dateKey
monthKey
createdAt
updatedAt
```

The ID is deterministic from source + sourceRecordId. This provides idempotent retry/update behavior.

### Expense creation rules

- daily record -> expense
- bazar purchased -> expense; unpurchased -> remove
- medicine Taken -> actual quantity × stored unit-price snapshot -> expense
- pending/skipped/missed -> none
- commute estimate -> none
- confirmed actual fare -> expense

Savings/income/cash-flow are not part of the current product.

## Backend-only/moderated

- `ai_usage/*`
- `upload_usage/*`
- `reports/*`
- Commute fare-report/aggregate data where implemented through backend/Supabase

Legacy Family/Rent/Wellness/Savings collections are denied to the current Flutter app and may only be cleaned up during account deletion.
