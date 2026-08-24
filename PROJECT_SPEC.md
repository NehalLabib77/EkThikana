# EkThikana — Production Build Specification

**Source of truth.** Every implementation, audit finding, and final-audit entry traces back to a bullet here. If code and this spec disagree, this spec wins and the code must be reconciled.

> Status: Working spec. Updates only via explicit revision notes appended at the end.

---

## 1. Stack (fixed)

- Flutter + Dart + Material 3
- Android first
- Firebase Authentication
- Cloud Firestore
- Supabase private Storage (PDFs/images)
- FastAPI backend
- Firebase Admin SDK
- Render deployment
- Gemini API through backend only
- Tesseract OCR for prescriptions
- Local Android notifications

**Android package id (fixed, never change after first internal release):**

```
com.ekthikana.ekthikana
```

---

## 2. Users and roles

Two fixed roles.

**Student** — every feature.

**General** — daily-life features only.

**Hard rule.** General users must not see or access Study, Groups, Community Library, academic materials, or Study AI. Enforce in **both** UI and backend/Firestore rules.

---

## 3. Student features

### 3.1 Study structure

```
Semester → Subject → Notes / Materials
```

### 3.2 Study feature list

- Notes
- PDF/image upload
- Built-in PDF reader
- PDF search / text selection
- Last-page resume
- Page bookmarks
- Page-linked notes
- AI note cleanup
- AI summary
- AI explanation
- Key-topic extraction
- PDF Q&A
- Study planner
- Community Library
- Saved Library
- Student Groups
- Shared Box

### 3.3 Explicitly excluded (forbidden)

- MCQ generation
- Automatic question generation
- Quiz generation

Any endpoint, screen, prompt, or service that performs these is a violation and must be removed.

---

## 4. Sharing

Academic content visibility:

```
Private | Group | Public
```

- **Private** — owner only.
- **Group** — selected group members only.
- **Public** — authenticated Student Community (verified-Student only).

Public and group materials can be viewed, saved, downloaded, and reported. **Saving does not transfer ownership.**

---

## 5. Groups

Students can:

- Create group
- Join by invite code
- Leave group
- Reset invite code (admin only)
- Share PDFs / images / notes

A group contains:

- owner
- admins
- members
- invite code
- Shared Box
- shared notes

**Hard rule.** There must be **NO group chat, comments, messages, or direct messaging** anywhere in the app, backend, or Firestore data model.

---

## 6. Community Library

Student-only.

Must support:

- Public notes
- Public PDFs/images
- Search
- University filter
- Department filter
- Semester filter
- Subject filter
- Material-type filter
- Newest sort
- Most-saved sort
- Preview
- Save
- Download
- Report

---

## 7. Daily-life features

Available to **both** Student and General:

- Tasks
- Reminders
- Medicine
- Prescription OCR
- BazarBuddy
- FamilyHub
- RentMate
- CommuteBD
- Wellness
- Universal Search
- Profile
- Data export
- Account deletion

### 7.1 Prescription flow (mandatory)

```
Upload → OCR → show extracted text → user manually verifies medicine/dose/schedule → save
```

**Never automatically trust prescription OCR.** The OCR endpoint must not write to the medicines collection. A `confirmedByUser: true` flag is required on every saved medicine record derived from OCR.

---

## 8. Security requirements

Hard requirements (non-negotiable):

1. Verify Firebase ID token on every protected backend route.
2. Require a verified email before data access.
3. Never trust the role supplied by the Flutter client — load role from the trusted user profile in Firestore (`users/{uid}.role`).
4. Prevent `ownerId` changes on owned documents via Firestore rules.
5. Private content → owner only.
6. Group content → group members only.
7. Public academic content → verified Student users only.
8. Supabase bucket must be private; service-role key only on the backend.
9. AI key only on the backend.
10. Use short-lived signed URLs for download/view.
11. Validate actual file signatures (PDF/PNG/JPEG); do not trust MIME from the client.
12. Sanitize filenames; randomize storage paths.
13. No permanent Render filesystem storage for user files.

### Configurable defaults

```
15 MB / file
100 MB / user
10 uploads / day
30 AI requests / day
```

Values must be configurable via environment variables on the backend (never hard-coded in clients).

---

## 9. Required backend APIs

Every endpoint below is required. Each is implemented as a FastAPI route under `/api` and protected per §8.

```
GET    /api/health
GET    /api/me
POST   /api/groups
POST   /api/groups/join
POST   /api/groups/{id}/leave
POST   /api/groups/{id}/invite/reset
POST   /api/materials/upload
GET    /api/materials/{id}/url
POST   /api/materials/{id}/save
DELETE /api/materials/{id}
POST   /api/ai/note
POST   /api/ai/pdf-question
POST   /api/study/plan
POST   /api/prescriptions/extract
POST   /api/reports
DELETE /api/account
```

---

## 10. Required repository layout

```
flutter_app/
backend/
firebase/
docs/
tool/
README.md
PROJECT_SPEC.md
TODO.md
firebase.json
.gitignore
.env.example   (placeholders only — never real credentials)
```

---

## 11. Working rules

- First save this specification as `PROJECT_SPEC.md`.
- Create `TODO.md` containing every required feature and implementation phase.
- For every phase:
  1. Read `PROJECT_SPEC.md`, `TODO.md`, and existing code first.
  2. Preserve working code and architecture.
  3. Implement real code, not pseudocode.
  4. Do not leave placeholder important functions.
  5. Run available tests / static analysis.
  6. Fix errors caused by the phase.
  7. Update `TODO.md`.
  8. Report exactly what was completed and what still requires external credentials.
- Do not ask for secret keys. Use environment-variable placeholders.
- Do not declare the project production-ready until the final audit passes every requirement in this spec.

---

## 12. Excluded features (do not implement)

- Automatic question generation
- MCQ generation
- Quiz generation
- Group chat / comments / direct messaging
- Any feature that bypasses email verification, role checks, or owner checks

---

## Revision log

- v1 — initial specification authored from the user request.