# Gochano — Final Production Specification

This file is the source of truth for the current build.

## 1. Brand and compatibility

User-facing app name: **Gochano**.

Keep these existing infrastructure identifiers unless intentionally migrating them:

- Android application id: `com.ekthikana.ekthikana`
- Existing Supabase bucket may remain `ekthikana-files`
- Existing Render service name/URL may remain unchanged

Changing those identifiers is **not required** for the Gochano brand and can break existing Firebase/Render/Supabase integrations.

## 2. Roles

- **Student** — all Study + LifeHub features.
- **General** — LifeHub/tasks/profile only.

General users must not see or access Study, Groups, Community Library, academic materials or Study AI. Enforce in Flutter and backend/Firestore rules.

## 3. Study

Structure:

```text
Study
├── Semesters -> Subjects -> Notes / Materials
├── My Notes
├── My Materials
├── Saved Library
├── Community Library
├── Study Groups / Shared Box
└── Study Planner
```

The Study dashboard must **not** contain a separate `Community Library / Browse Resources` promotional section. A compact Library entry is allowed so the Student-only Community Library remains reachable.

Notes/material visibility: `private | group | public`.

Required PDF features: open, page navigation, text selection/search, zoom, resume last page, bookmarks, page-linked notes, loading/error states.

AI: note cleanup, summarize, explain, key topics, PDF Q&A, Study Planner assistance. No MCQ/question/quiz generation.

Groups: material sharing only; no chat, messages, DMs or comment threads.

## 4. Final LifeHub

Only:

```text
Medicine
BazarBuddy
Daily Expenses
CommuteBD
```

RentMate, FamilyHub and Wellness are removed from active UI/routes/search and denied as legacy collections.

## 5. Central expense tracker — spending only

Gochano does **not** implement cash flow, income, savings, net difference, profit/loss or remaining balance.

Central collection:

```text
financial_transactions/{deterministicSourceId}
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

Rules:

```text
Daily expense entered      -> one expense
Bazar item purchased       -> one expense
Bazar item unpurchased     -> linked expense removed
Medicine Taken             -> actual quantity * unit-price snapshot -> one expense
Medicine pending/skipped/missed -> no expense
Commute estimated fare     -> no expense
Commute confirmed actual fare -> one expense
```

All source update/delete operations must update/delete the linked deterministic expense record. Retry/repeated taps must not duplicate charges.

## 6. Medicine

Available to Student and General.

Entry methods: Add Manually or Scan Prescription.

OCR flow:

```text
Image/PDF -> OCR -> suggestions -> user reviews/edits -> user confirms -> quantity + price + schedule -> save
```

OCR must never auto-activate medicine name, dose, price, quantity, schedule or reminders. Show a medical-safety warning.

Support unit or pack/strip/bottle pricing; store unit-price snapshots on Taken doses. Dose status: pending/taken/skipped/missed. Only Taken creates an expense. Support pause/resume/stop/history.

## 7. BazarBuddy

Visual categories plus custom items. Item fields: name, quantity, unit, price, purchased. Support add/edit/delete/purchased toggle, session/day/month history. Only purchased items create central expenses.

## 8. Daily Expenses

Categories: Breakfast/Nasta, Lunch, Snacks, Dinner, Other. Multiple entries per category with title, amount, optional note, date/time. Daily/monthly totals come from central expenses.

## 9. CommuteBD

Use a real interactive map and routing-provider abstraction. Support GPS, origin/destination search, route polyline, distance, ETA, recenter, loading/offline/GPS-denied/no-route states.

Use supplied dataset. Official BRTA bus and Metro fares are deterministic. Crowd/ML is only for uncertain market fares such as Rickshaw/CNG and must show source/confidence. Do not fabricate live transport data.

Estimated fare never becomes an expense. Only a user-confirmed actual fare creates the commute expense.

## 10. Security

- Firebase ID token on protected backend routes
- verified email required
- role loaded from trusted Firestore profile
- no client-side role trust
- private Supabase bucket; service key backend-only
- short-lived signed URLs
- file-signature validation
- no secrets in Flutter/Git
- Render filesystem is ephemeral

## 11. Explicitly forbidden

- Automatic MCQ generation
- Automatic question generation
- Quiz generation
- Group chat
- Direct messaging
- Comment/chat threads
- Fake/live transport claims without a provider

## 12. Production acceptance

Before release: `flutter analyze`, `flutter test`, backend tests, real device test, Student/General role test, Firestore rules/index deployment, Supabase/Render/Gemini integration test, OCR confirmation test, duplicate-expense test, and signed release AAB build.
