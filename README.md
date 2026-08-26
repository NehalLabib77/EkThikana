# Gochano — One Place for Everything

Gochano is an Android-first Flutter + FastAPI application with two roles.

## Roles

- **Student** — Study workspace, groups/shared box, Community Library, Study AI, tasks, and all LifeHub features.
- **General** — Tasks and LifeHub only. Study, Groups, Community Library and Study AI are hidden and denied by backend/Firestore rules.

## Final LifeHub

LifeHub contains only:

- Medicine
- BazarBuddy
- Daily Expenses
- CommuteBD

RentMate, FamilyHub and Wellness are obsolete and are not part of the current UI.

## Expense tracking — spending only

Gochano is **not a cash-flow/accounting app**. It does not track income, savings, profit/loss or remaining balance.

One idempotent expense ledger combines:

```text
Daily Expense entered    -> Expense
Bazar item purchased     -> Expense
Medicine dose Taken      -> Expense
Pending/Skipped/Missed   -> No expense
Commute estimate         -> No expense
Actual commute fare      -> Expense
```

Daily, monthly, calendar, category and yearly totals come from `financial_transactions` expense records.

## Study

Student Study includes semesters, subjects, notes, materials/PDF reader, Saved Library, Community Library, groups/shared box, AI study tools and Study Planner. The Study dashboard intentionally has **no standalone `Community Library / Browse Resources` promotional block**; Community Library remains available through its compact Library entry.

Automatic MCQ/question/quiz generation and all chat/messaging are excluded.

## Stack

- Flutter / Dart / Material 3
- Firebase Authentication + Cloud Firestore
- FastAPI + Firebase Admin on Render
- Supabase private Storage
- Gemini through backend only
- Tesseract OCR for prescriptions
- OpenStreetMap-compatible map/routing stack for CommuteBD
- Android local notifications

## Setup order

1. `docs/START_HERE.md`
2. `docs/FIREBASE_SETUP.md`
3. `docs/STORAGE_SETUP.md`
4. `docs/RENDER_DEPLOY.md`
5. `docs/PRODUCTION_CHECKLIST.md`

No server secrets belong in Flutter or Git.
