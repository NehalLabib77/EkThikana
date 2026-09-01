# Gochano architecture

## Runtime

- Flutter Android client
- Firebase Authentication + Cloud Firestore
- FastAPI backend on Render
- Firebase Admin SDK on backend
- private Supabase Storage
- Gemini backend-only Study AI
- Tesseract prescription OCR
- OpenStreetMap-compatible map/geocoding/routing stack for CommuteBD
- local Android notifications

## Roles

Student receives Study + LifeHub. General receives LifeHub/tasks/profile only. Student-only access is enforced in both UI and backend/Firestore rules.

## Flutter modules

```text
screens/auth/      authentication and verification
screens/home/      role-aware shell/dashboard
screens/study/     semesters, notes, materials, PDF reader, Library, Planner
screens/groups/    Shared Box / material sharing only
screens/tasks/     tasks/reminders
screens/life/      Medicine, BazarBuddy, Daily Expenses, CommuteBD
screens/profile/   profile, expense summary, export/delete
screens/search/    role-aware universal search
```

The Study dashboard intentionally has no separate Community Library/Browse Resources promotional block.

## Expense architecture

```text
Daily Expenses ----Bazar purchased ----+--> financial_transactions (expense only)
Medicine Taken -----+
Commute actual fare-/
```

Deterministic IDs are generated from source + sourceRecordId to prevent duplicate expenses. Estimated commute fare and non-Taken medicine doses never create expenses.

## Backend privileged operations

FastAPI verifies Firebase tokens and performs privileged storage/AI/report/account/Commute operations. Supabase service-role and Gemini keys never enter Flutter. Render local disk is not permanent storage.

## Legacy modules

FamilyHub, RentMate, Wellness and the former Savings feature are not active. Legacy records may only be referenced by account-deletion cleanup so old data is not stranded.
