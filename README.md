# EkThikana — One Place for Everything

EkThikana is a role-based Flutter + FastAPI application.

## User roles

- **Student**: Study workspace + groups/shared box + community library + AI study tools + all daily-life modules.
- **General**: Daily-life modules only. Study, groups, community and study AI are not available.

## Documentation

Read these in order:

1. `docs/START_HERE.md` — the step-by-step first run.
2. `docs/ARCHITECTURE.md` — module map, data ownership, and failure modes.
3. `docs/FIREBASE_SETUP.md`, `docs/STORAGE_SETUP.md`, `docs/ANDROID_SETUP.md` — provider setup.
4. `docs/API_REFERENCE.md`, `docs/DATA_MODEL.md` — runtime contracts.
5. `docs/RENDER_DEPLOY.md`, `docs/PRODUCTION_CHECKLIST.md` — go-live.
6. `docs/TROUBLESHOOTING.md`, `docs/SECURITY_PRIVACY.md`, `docs/BUILD_VALIDATION.md` — when things go wrong.

## Architecture

```text
Flutter Android App
├── Firebase Authentication
├── Cloud Firestore
├── Local notifications
└── FastAPI API on Render Free
    ├── Firebase Admin token verification
    ├── Group/invite operations
    ├── Material upload/download authorization
    ├── Supabase private file storage (free-stack default)
    ├── Gemini study AI
    ├── PDF text extraction / Q&A
    └── Prescription OCR (no AI required)
```

### Why Supabase Storage is the default here

As of August 2026, Cloud Storage for Firebase requires a Blaze billing plan. To keep the first EkThikana deployment possible without enabling Firebase billing, this source uses **Firebase Auth + Firestore** and a **private Supabase Storage bucket** for PDFs/images. If you later enable Firebase Blaze, the storage adapter can be replaced without changing the app's data model.

## Included features

### Student
- Email/password registration and email verification
- Student/general role selection
- Semester and subject management
- Notes with private/group/public visibility
- PDF/image upload
- Built-in PDF reader
- PDF search
- Resume from last PDF page
- PDF page bookmarks
- Page-linked notes
- Public Community Library
- Save public/group materials to My Library
- Download files offline
- Student groups with invite codes
- Shared Box (no chat)
- Community content reporting/moderation queue
- AI note cleanup, summary, explanation and key topics
- PDF Q&A
- Study-plan endpoint
- Universal keyword search
- Tasks and reminders

### Student + General
- Tasks and reminders
- Medicine records
- Prescription OCR + mandatory user confirmation
- BazarBuddy
- FamilyHub
- RentMate
- CommuteBD
- Wellness
- Profile/logout
- Permanent in-app account deletion

### Explicitly excluded
- Automatic question generation
- MCQ generation
- Group chat / direct messaging

## Folders

- `flutter_app/` — Flutter mobile application source
- `backend/` — FastAPI service for Render
- `firebase/` — Firestore rules and indexes
- `docs/` — exact setup and deployment instructions
- `tool/` — Windows bootstrap helpers

## Important

This repository contains **no secret keys**. You must create your own Firebase, Supabase and Gemini credentials and store backend secrets only in Render environment variables.

Start with `docs/START_HERE.md`, then follow `docs/WHAT_I_NEED_FROM_YOU.md`.
