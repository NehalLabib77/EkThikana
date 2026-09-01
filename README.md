# Gochano

A calm personal operating system for student life — study materials, tasks,
money, medicine and getting around Bangladesh, in one Android app.

> **About this document.** It is the single authoritative description of the
> project: architecture, feature reference, setup guide, testing guide,
> deployment guide, troubleshooting, and an honest status report. Every claim
> about what works is marked with how it was verified. Where something is not
> implemented, or is implemented but unproven, this document says so plainly
> rather than rounding up.
>
> Last verified: 1 September 2026, against Flutter 3.47.2 / Dart 3.13.2.

---

## Table of contents

1. [Project overview](#1-project-overview)
2. [Problem statement](#2-problem-statement)
3. [Objectives](#3-objectives)
4. [Target user](#4-target-user)
5. [Application structure](#5-application-structure)
6. [Complete feature overview](#6-complete-feature-overview)
7. [Home](#7-home) · [Study](#8-study-workspace) · [Materials](#9-notes-pdfs-and-materials) · [Tasks](#10-tasks) · [Planner](#11-planner) · [Focus](#12-focus-sessions)
8. [AI assistant](#13-ai-assistant)
9. [Study groups](#14-study-groups) · [Chat](#15-group-chat) · [Resource sharing](#16-group-resource-sharing)
10. [Expense](#17-expense) · [Grocery](#18-grocery--bazar)
11. [Medicine](#19-medicine) · [Prescription OCR](#20-prescription-ocr)
12. [CommuteBD](#21-commutebd)
13. [Community](#22-community) · [Profile](#23-profile)
14. [UI/UX design system](#24-uiux-design-system)
15. [Technology stack](#25-technology-stack)
16. [System architecture](#26-system-architecture)
17. [Data ownership](#27-data-ownership)
18. [Authentication flow](#28-authentication-flow)
19. [Firestore architecture](#29-firestore-architecture)
20. [Backblaze B2 architecture](#30-backblaze-b2-architecture)
21. [AI architecture](#31-ai-architecture) · [PDF/material AI flow](#32-pdfmaterial-ai-flow)
22. [OCR architecture](#33-ocr-architecture)
23. [ML model inventory](#34-ml-model-inventory)
24. [CommuteBD architecture](#35-commutebd-architecture)
25. [Expense architecture](#36-expense-architecture) · [Medicine architecture](#37-medicine-architecture)
26. [Notification architecture](#38-notification-architecture) · [Localization](#39-localization)
27. [Folder structure](#40-folder-structure)
28. [Environment variables](#41-environment-variables)
29. [Setup guides](#42-local-development-setup) — [Firebase](#43-firebase-setup) · [Neon/PostGIS](#44-neonpostgis-setup) · [Backblaze B2](#45-backblaze-b2-setup) · [Gemini](#46-gemini-setup) · [Render](#47-render-setup) · [Android](#48-android-setup)
30. [How to run](#49-how-to-run-the-flutter-app) · [Backend](#50-how-to-run-the-backend) · [Testing](#51-testing)
31. [Feature verification table](#52-feature-verification-table)
32. [Security](#53-security) · [Privacy](#54-privacy) · [Known limitations](#55-known-limitations)
33. [Troubleshooting](#56-troubleshooting)
34. [What the project owner must do](#57-what-the-project-owner-must-do)
35. [What the application does automatically](#58-what-the-application-does-automatically)
36. [How every feature works](#59-how-every-feature-works)
37. [Deployment checklist](#60-deployment-checklist) · [Production readiness](#61-production-readiness-checklist)
38. [Future scope](#62-future-scope) · [Final project status](#63-final-project-status)

---

## 1. Project overview

Gochano is a student-centred Android application that keeps the parts of
student life that normally live in five different apps in one place:

- **Study** — semesters, subjects, PDFs, images, written notes, tasks, a
  planner, focus sessions, and an AI assistant that answers questions about
  the student's own material.
- **Life** — one expense module covering daily spending and grocery, a
  medicine reminder system with prescription scanning, and CommuteBD, a
  Bangladesh transport fare and route assistant.
- **Community** — private study groups with shared resources and chat.
- **Profile** — account, statistics, language, appearance, notifications and
  data controls.

A Flutter app talks to Firebase directly for authentication and its own
documents, and to a FastAPI backend on Render for everything that needs a
secret: private file storage, AI, OCR, quota enforcement and the CommuteBD
dataset.

## 2. Problem statement

A university student in Bangladesh typically juggles:

- lecture PDFs scattered across WhatsApp, Drive and a phone's Downloads
  folder, with no notion of which subject they belong to;
- a mental list of deadlines;
- a monthly allowance tracked, if at all, in a notes app;
- a prescription photo they will forget the schedule from;
- and a daily commute whose fare they have no reliable way to check —
  official BRTA and metro fares exist but are not in any usable app, and
  rickshaw and CNG fares are pure negotiation.

Each of those has an app. None of them talk to each other, and most of them
are not built for this context. Gochano's premise is that a single, calm,
bilingual app that answers "what should I do today, and what will it cost"
is more useful than five specialised ones.

## 3. Objectives

1. Put a student's study materials somewhere they can be found by subject.
2. Let AI answer questions about *their* material, not the internet's.
3. Give one honest number for money spent this month, across every source.
4. Remind reliably about medicine without ever prescribing anything.
5. Make Bangladesh transport fares legible, with the provenance of every
   number shown.
6. Work in English and Bangla, in light and dark, on a cheap Android phone.

## 4. Target user

University students in Bangladesh, on Android, often on a mid-range or
budget device and a metered connection. The interface is student-friendly
without being childish; the copy is plain, and every screen works in Bangla.

Two account roles exist:

| Role | Gets |
|---|---|
| `student` | Everything: Home, Study, Life, Community, Profile |
| `general` | Home, Life, Tasks, Profile |

The split is not a UI choice — Study, Groups, AI and Materials are all
behind `require_student` on the backend, so a general account would receive a
403 from every action on those screens.

## 5. Application structure

```text
Home        what matters right now
Study       workspace, tasks, planner, focus  (+ AI and search)
Life        expense, medicine, CommuteBD
Community   study groups
Profile     account and settings
```

Five bottom-navigation destinations for students, four for general accounts.
State is preserved between destinations, so switching tabs does not discard a
half-typed expense.

## 6. Complete feature overview

| Area | What it does |
|---|---|
| Home | Continue studying, today's tasks (with working checkboxes), next medicine, month's money split by source, group activity, five quick actions |
| Workspace | Semesters → subjects → materials; recent materials and notes surfaced at the top |
| Materials | Upload PDF/JPEG/PNG/DOC/DOCX, search, sort, rename, delete, save, open, share to a group |
| Notes | Written notes with four real AI actions: clean up, summarise, explain, extract key points |
| Reader | In-app PDF and image viewing, per-student page memory, "Ask AI about this" |
| Tasks | Today / Upcoming / Completed, due dates, reminders, complete/undo/delete |
| Planner | Deterministic priority order from the backend, plus a day-by-day agenda |
| Focus | Timed focus sessions with pause/resume/finish and history |
| AI | General academic questions, plus material-grounded answers for PDFs and images |
| Groups | Create, join by invite code, leave; Overview / Resources / Chat / Members |
| Expense | Overview, daily expenses, grocery, history — one ledger, one total |
| Medicine | Today's doses, reminders, taken/skipped/missed, history, prescription scanning |
| CommuteBD | Route planning with official/estimated fares, a static route map, post-trip actual fare |
| Search | Across materials, notes and tasks |
| Profile | Account, study stats, monthly money, language, appearance, notifications, data export, account deletion |

---

## 7. Home

Home answers "what matters to me right now?" — it is a briefing, not a
directory of features. Sections in priority order: continue studying, today's
tasks, next medicine, this month's money, group activity, quick actions.

Each section owns its own Firestore stream, so adding a task rebuilds the
tasks card rather than the whole dashboard.

Quick actions: Ask AI, Add expense, Add task, Scan prescription, Find a route.

## 8. Study workspace

`Semester → Subject → Materials`. Recent materials and recent notes sit
*above* the semester list, because the file a student wants is usually the one
they were reading yesterday and making them walk the hierarchy to reach it is
three taps of pure structure.

Each subject gets a static illustration chosen by keyword matching on its
name — "Machine Learning Lab" resolves to the AI drawing, "পদার্থবিজ্ঞান" to
the physics one, and anything unrecognised to a generic study drawing. There
is no state in which a subject renders a missing icon.

## 9. Notes, PDFs and materials

Two distinct things:

- **Materials** are uploaded files. They go through
  `POST /api/materials/upload`, which enforces the per-user storage quota and
  the daily upload limit, writes the object to Backblaze B2, and creates the
  Firestore document — in that order, rolling back the object if the document
  write fails.
- **Notes** are written in the app and live in the `notes` collection. They
  are the one material type `POST /api/ai/note` operates on directly.

Accepted upload types are exactly what the backend sniffs by magic bytes:
**PDF, PNG, JPEG, DOC, DOCX**. The Flutter file picker allows exactly this
set — no more (which would send the student to a 415) and no less (which
would block a format the API supports).

## 10. Tasks

Today / Upcoming / Completed. No Kanban. A task with no due date counts as
"today", because an undated task is something to deal with now rather than
something to hide.

Completing a task cancels its reminder; un-completing restores it. Editing
reschedules through a single primitive that recycles the notification id, so
an edited task cannot leave a stale reminder queued alongside the new one.

## 11. Planner

`POST /api/study/plan` ranks unfinished tasks by deadline urgency — overdue
first, then soonest. It is deterministic arithmetic and the endpoint reports
its own method; the screen calls it "suggested order" rather than dressing it
up as a recommendation engine. Below it is a plain day-by-day agenda of dated
tasks.

## 12. Focus sessions

Start, pause, resume, finish, cancel, and a history list. The elapsed clock
ticks locally, but the authoritative total is whatever the backend returns on
pause/finish, since it is the side that knows about run/pause cycles across
devices.

## 13. AI assistant

The distinction the UI makes visible is **General AI** vs **Material Context
AI**. With a material in context there is a chip reading `Using:
Database_Normalization.pdf` with an × to remove it, and the suggested actions
change to ones that only make sense with a document.

Which endpoint is called follows from the context rather than from a mode
switch:

| Context | Endpoint |
|---|---|
| none | `POST /api/ai/note` (general academic question) |
| PDF | `POST /api/ai/pdf-question` |
| image | `POST /api/ai/image-question` |

Routing uses the MIME type **and** the file name, so a material saved without
a `mimeType` still reaches the right endpoint. Anything unrecognised goes to
the multimodal endpoint, never to the PDF extractor, which hard-rejects
non-PDFs.

Processing shows a static labelled progress bar and a sentence — "Reading
your material…". There are no typing dots, no bouncing indicator and no
glowing orb.

## 14. Study groups

Create a group (you become admin and get an invite code), join with a code,
or leave. Each group has four tabs — **Overview**, **Resources**, **Chat**,
**Members** — rather than one overloaded screen.

## 15. Group chat

`GET`/`POST /api/groups/{id}/chat`. Both are member-only server-side; the
POST additionally requires the group's `chatEnabled` flag, which a group admin
controls. The UI mirrors those rules, but the enforcement is on the server —
a non-member gets a 403, not just a hidden button.

Messages arrive newest-first and are reversed for display so the thread reads
top to bottom.

## 16. Group resource sharing

Two kinds of shared resource:

- **Files** — uploaded through the same authenticated `/api/materials/upload`
  the private library uses, so quota accounting and the file-type check are
  identical. Visibility `group`, `groupId` set.
- **Notes** — written in the app with visibility `group`.

Chat attachments go through the same material pipeline and are handed to the
recipient as a signed URL, so a chat attachment gets the same private storage
and the same quota accounting as everything else.

## 17. Expense

**One** financial module. Previously "Daily Expenses" and "BazarBuddy" sat in
Life as unrelated top-level products, which meant there was no single answer
to "how much did I spend". Expense is now one screen with four tabs:

| Tab | Contents |
|---|---|
| Overview | Monthly available, spent, remaining (with a determinate bar), today's total, spending by source, recent entries |
| Daily | Today's daily expenses, add/edit/delete |
| Grocery | The bazar list |
| History | Every ledger entry, grouped by day |

All four read the same `financial_transactions` ledger, so the number on
Overview is always the sum of what the other tabs show.

Daily expense categories are stored identifiers, not labels — `Breakfast /
Nasta`, `Lunch`, `Snacks`, `Dinner`, `Other` — and are preserved
byte-for-byte from the previous version, because they are the values on every
historical document.

## 18. Grocery / Bazar

Workflow: item → unit price → quantity → automatic total → purchased /
pending. The live total is shown before saving so the arithmetic is checkable.

Ledger rules, verified by reading `FinancialService`:

| Action | Ledger effect |
|---|---|
| Mark purchased (price > 0) | Writes one row at the deterministic id `bazar_{itemId}` |
| Retry after a failure | Overwrites the same id — **cannot duplicate** |
| Un-purchase | Deletes that row |
| Delete the item | Deletes item and row together — **no orphan** |

## 19. Medicine

Today's doses, the next reminder with Taken/Skip buttons, taken/skipped/missed
counts, a full history, and both ways to add a medicine.

**Manual entry is primary and always available.** Scanning is secondary. A
student is never forced through OCR to record a medicine.

The one hard rule in the medicine form: **Gochano never guesses a reminder
time.** At least one time must be entered by the student before the form
saves. A frequency shorthand read off a prescription is passed through as
text for them to read while choosing — turning "1+0+1" into clock times is a
medical decision.

Every screen in this feature carries: *"Gochano does not provide medical
advice. It only reminds you of the times you saved and records what you
mark."*

## 20. Prescription OCR

### What it actually is

| Layer | Implementation |
|---|---|
| **A. OCR engine** | **Tesseract** via `pytesseract`. The language string is chosen from what is *actually installed*: `eng+ben` when the Bangla pack is present, `eng` when it is not, and the app is told which |
| **B. Preprocessing** | Pillow + NumPy. Several candidate renderings per page — normalised, contrast-boosted, Otsu-binarised, median-denoised, and deskewed when the page is tilted — recognised across page-segmentation modes 6, 4 and 11 |
| **C. Variant selection** | **Measured, not chosen in advance.** Every variant is scored on Tesseract's own per-word confidence and the best-scoring read wins. A clean read short-circuits the remaining passes |
| **D. Skew and rotation** | Projection-profile deskew over ±8°, refined to 0.25°. A page that is already straight is not rotated at all — resampling costs sharpness it cannot repay. The four right-angle orientations are tried only when the upright read fails entirely |
| **E. PDF handling** | `pypdf` text extraction first; `pdf2image` renders pages 1–3 at 220 dpi and OCRs them when the text layer yields under 40 characters |
| **F. Parser** | **Regex and keyword rules** — dose patterns (`500 mg`), frequency shorthand (`1+0+1`, `BD`, `TDS`, `HS`, `PRN`), dosage-form prefixes (`Tab`, `Cap`, `Syr`), meal instructions in English and Bangla, explicit clock times |
| **G. Name review** | Fuzzy match against a shipped list of generic (INN) names, **suggest-only** |
| **H. AI structured extraction** | **Optional, off by default** (`?useModel=true`). Regroups the OCR text and may not add to it — every field is re-checked word by word against the source and dropped if absent |
| **I. Custom ML model** | **Does not exist.** No model artifact, no training script, no inference |

### Confidence is measured, never invented

Every number comes from Tesseract's `image_to_data` output. Where Tesseract
reports no usable words, the answer is **unknown** — not a default, not the
page average, not a plausible-looking percentage.

The bands are deliberately coarse. Tesseract's raw score is a per-word
character-classifier confidence: meaningful as an *ordering*, not calibrated
as a probability. Presenting "82.4%" beside a misread medicine name would
imply a precision the number does not have, so the UI says **Read clearly /
Check this one / Hard to read**, and **Not measured** when it does not know.

Each medicine carries the confidence for *its own name*, not the page
average, and `None` when that name cannot be traced back to recognised words.

### A medicine name is never silently corrected

This is the single most dangerous thing this codebase could do. *Clobazam*
auto-corrected to *clonazepam* is a different drug, a different indication and
a different dose — and the patient would never see that it happened.

So `app/services/ocr/medicine_names.py` **suggests** and never replaces. The
name rendered is always the text that was read; a match appears as a question
with two explicit answers ("Use this spelling" / "Keep as read"). Four guards
decide whether a suggestion is safe to show at all:

1. A high similarity floor — consistent with an OCR slip, not a different word.
2. The first letter must survive. Nearly every dangerous confusion between
   two real drugs starts differently; OCR slips rarely do.
3. **Ambiguity suppresses it.** If two known medicines are similarly close,
   there is no way to tell which was meant, and the alphabetically luckier one
   is not an answer.
4. Comparable length. "Cef" is close to many things and identifies none.

Absence from the list means nothing at all: `backend/data/medicines/common_generics.txt`
holds generic names only, and most prescriptions in Bangladesh are written as
brand names. "No suggestion" is the ordinary case.

### Bengali is verified, not assumed

An English-only Tesseract does not *fail* on a Bengali prescription — it
returns confident-looking Latin nonsense, which is the worst possible failure
mode for a medicine list. So `GET /api/prescriptions/ocr-status` reports what
is installed, `/extract` refuses rather than guessing when English is missing,
and the app states plainly when Bengali instructions could not be read.

The Docker image already provisions this: `tesseract-ocr`,
`tesseract-ocr-eng`, `tesseract-ocr-ben`, `poppler-utils`.

### Verified end to end

`scripts/verify_prescription_ocr.py` runs the real engine over real pixels.
Against Tesseract 5.4.0 with `eng+ben`, on a rendered prescription tilted
−2.5° with sensor noise:

```text
detected skew correction   +2.50 deg
winning variant            normalised      psm 6      eng+ben
confidence                 94 (high)
4 medicine candidates, all matched to known generic names
  Amlodipine   dose=''        confidence=96 (high)   hints: 1+0+0
  Omeprazole   dose='20mg'    confidence=96 (high)   hints: 1-0-1, before food
  Metformin    dose='500mg'   confidence=96 (high)   hints: 1+0+1, রাতে
  Paracetamol  dose='500mg'   confidence=95 (high)   hints: SOS
```

The Bengali instruction `রাতে` was recognised and attached to the right
medicine. **That is a rendered page, not a photograph** — it verifies the
pipeline end to end and says nothing about handwriting accuracy. Pass real
images as arguments to test those.

Two bugs surfaced only by running the real engine:

- A garbled dose was absorbed into the name. `5mg` misread as `omg` produced
  `Amlodipine omg`; text ending in a dose unit is a dose, not part of a name.
- A short page was discarded entirely. The ranking score zeroes anything
  shorter than a prescription — right for ranking, wrong as a test of
  existence. A crop of just the medicine list, or one Bengali instruction
  line, read perfectly at 94% and came back as "nothing was recognised".

### The flow is still review-only

Upload → OCR → candidates → **student reviews and corrects** → **student sets
the times** → save. Nothing on the scan screen writes a medicine, a dose, a
schedule or a reminder. A frequency shorthand like `1+0+1` is a medical
instruction, not a set of clock times, and is passed through as text so the
student can see it while choosing their own.

## 21. CommuteBD

`From → To → Find routes → Recommended / Cheapest / Fastest`.

CommuteBD is a **multimodal journey planner**, not a distance-and-fare
calculator. A search runs a real Dijkstra over the transport graph and returns
complete origin-to-destination journeys, including the first and last mile —
the walk or rickshaw ride from where you actually are to the stop where the
network begins.

The results screen uses two complementary representations, because they
answer different questions:

- **A static map** — where am I going. One line per leg, walking dashed and
  rides solid, captioned as straight lines between stops rather than passed
  off as road geometry. A leg whose stops have no coordinates still appears
  in the timeline; it is simply not drawn, and the map says so.
- **A step-by-step timeline** — what exactly do I do. Every stop is a real
  place name, every leg carries an instruction the student can act on
  ("Board MRT Line 6 at Mirpur 10 Metro Station and get off at Farmgate"),
  and a change of transport is its own step with its own time cost.

Recommended, Cheapest and Fastest are three genuinely different searches over
one graph, not one result relabelled three times. Each is shown with the fare
and time that distinguish it, plus how it compares to the recommended one
("৳16 cheaper, 27 min slower") and, where there is something real to say, why
the recommendation was made.

**No internal identifier is ever displayed.** A step reading `A1` or
`node_123` is impossible by construction — the graph refuses to build a node
without a human-readable name.

Every fare card states where its number came from and how much to trust it:

| Badge | Meaning |
|---|---|
| **Official** | A BRTA stop-pair fare or a metro station-pair fare, looked up from the dataset |
| **Reported by riders** | Aggregated from moderated crowd fare reports |
| **Historical rule** | The government CNG meter rule, with its effective date and a warning to verify |
| **Estimated** | Distance-based |

Results also include a **static route map** (OpenStreetMap tiles, the OSRM
polyline, origin and destination pins — the line does not animate) and real
bus services connecting the two stops from the CommuteBD dataset.

Post-trip, the student can record what they **actually** paid. That amount —
not the estimate — becomes an expense, through a deterministic transaction id
so a retry cannot double-charge them. Sharing the figure with the crowd
dataset is a separate opt-in switch, and it is stored *pending moderation*;
the backend does not publish it as truth.

## 22. Community

Community in Gochano is **study groups**. There is no posts/comments backend
in this project — no endpoints, no Firestore collection — so the app does not
pretend otherwise: no empty feed, no "Coming Soon" placeholder. What exists
and works is groups, resources, chat and members.

## 23. Profile

Account · Study statistics · Monthly money · Language · Appearance ·
Notifications · Privacy and data · About · Sign out.

Developer configuration (API base URL, Firebase project id, build flags) is
deliberately not shown.

The Notifications section says plainly when the OS has notifications turned
off, because in that state reminders silently do nothing.

---

## 24. UI/UX design system

Gochano uses **Clean Minimalism** on a Material 3 foundation: Material
supplies the interaction model (ripples, focus traversal, field semantics,
dialog and sheet anatomy, Talk-back plumbing); Gochano supplies the look —
flat surfaces, hairline borders, one type scale, restrained accent colour.

### Tokens

| Token file | Contents |
|---|---|
| `gochano_colors.dart` | ~30 semantic roles as a `ThemeExtension`, resolved via `context.colors` |
| `gochano_typography.dart` | One role-named type scale (`pageTitle`, `cardHeading`, `body`, `statistic`…) with Bangla-safe line heights |
| `gochano_spacing.dart` | The 4/8/12/16/20/24/32/40 ladder, four radii, one shadow token, touch-target minimums |
| `gochano_theme.dart` | ThemeData for light and dark, built entirely from the above |

Screens never write a hex literal. A test fails the build if one appears
outside the token files.

### Static illustrations

**61 drawings** live in `gochano_art.dart` as inline SVG bodies, all in
one stroke language: a 96×96 viewBox, stroke width 3.4, round caps and joins,
soft simplified geometry with no faces and no mascots.

Each drawing is painted from exactly three theme colour slots — `{ink}`,
`{fill}`, `{paper}` — substituted at build time. `{paper}` is white in light
mode and a dark surface in dark mode, which is what stops illustrations
punching white holes through a dark screen. The previous `assets/*.svg` set
hardcoded `fill="#FFFFFF"` and had exactly that bug.

They are drawn rather than shipped as assets: one reviewable place for the
whole visual language, no raster weight, no pixelation, project-owned so
there is no third-party asset licence to track. Coverage: 12 subject icons,
6 file types, 19 feature icons, 10 transport modes, 13 empty/status states.

### Light and dark

Dark mode is a designed palette, not an inversion. Surfaces step *up* in
lightness from a dark neutral background; accents are desaturated so they do
not glow. Light mode uses a slightly tinted scaffold so white cards read as
raised without needing a shadow.

Both are verified by test: primary and secondary text clear **4.5:1** on
every surface in both themes, tertiary text clears 3:1, and every status
colour clears 4.5:1 on its own soft background.

### Motion

**Decorative animation is intentionally not part of this design.** This is a
deliberate design decision, not an omission.

Removed during the rebuild: a custom fade + 24dp-rise page transition with
its own duration and curve tokens; a 360 ms splash logo fade; a 220 ms
cross-fade on the offline banner; `ScaleTap` (press-scale), `AnimatedFadeIn`
and `StaggeredList` (cascading entrances); and an animated loading ring.

What remains is the platform's own page transition, which is unavoidable for
core interaction. Loading is a static labelled progress bar with a sentence
saying what is happening, and a real percentage wherever one is known.

A static test fails on any `AnimatedX` / `FadeTransition` / `SlideTransition`
/ `Hero` / `Lottie` / `Rive` usage in `lib/`, on `AnimationController` outside
a `TabController`, and on a custom page route.

### Accessibility

- Every `Image.asset` and `Image.network` carries a `semanticLabel`; every
  `IconButton` carries a tooltip. Both are enforced by test.
- Minimum touch target 48dp.
- Status is never carried by colour alone — every badge pairs a colour with
  an icon and a word.
- Stat cards announce "label: value" as one node rather than reading a bare
  number.

---

## 25. Technology stack

| Layer | Technology |
|---|---|
| App | Flutter 3.47.2 / Dart 3.13.2, Material 3, Android |
| Auth | Firebase Authentication (email/password, verification required) |
| App data | Cloud Firestore |
| Backend | Python 3.11+, FastAPI, Uvicorn/Gunicorn, Docker |
| Relational / geo | Neon PostgreSQL + PostGIS |
| Private files | **Backblaze B2** (S3-compatible API via boto3) |
| AI | Google Gemini |
| OCR | Tesseract (`pytesseract`), Pillow, `pdf2image`, `pypdf` |
| Routing / geocoding | OSRM + Nominatim (OpenStreetMap) |
| Maps | `flutter_map` + OpenStreetMap tiles |
| Hosting | Render |
| Languages | English, Bangla |

## 26. System architecture

```text
┌──────────────────────────────────────────────────────────┐
│                  Flutter Android app                     │
│  features/ (home, study, life, community, profile, …)    │
│  core/design_system · core/localization · shared/        │
└───────────┬──────────────────────────────┬───────────────┘
            │                              │
   Firebase Auth (ID token)        Cloud Firestore (direct,
            │                       rules-enforced, owner-scoped)
            │
            ▼   Authorization: Bearer <Firebase ID token>
┌──────────────────────────────────────────────────────────┐
│              FastAPI backend  (Render, Docker)           │
│                                                          │
│  core/auth       verify token · email verified · role    │
│  routers/        materials · ai · groups · prescriptions │
│                  study · part3 · commute · account       │
│  services/       storage(B2) · ai(Gemini) · ocr · pdf    │
│                  commute/{fare_engine, routing, ml_fare} │
└──┬──────────┬──────────┬───────────┬──────────┬──────────┘
   │          │          │           │          │
   ▼          ▼          ▼           ▼          ▼
Firebase   Backblaze   Google     Neon        OSRM /
Admin +    B2          Gemini     PostgreSQL  Nominatim
Firestore  (private)              + PostGIS   (OpenStreetMap)
+ FCM
```

**The client never holds a secret.** Every credential — the B2 keys, the
Gemini key, the database URL, the Firebase service account — lives only in
the backend's environment.

## 27. Data ownership

| Data | Lives in | Written by |
|---|---|---|
| Accounts, sign-in, email verification | Firebase Auth | Flutter (Auth SDK) |
| User profile, role | Firestore `users` | Flutter on sign-up; backend on privileged writes |
| Semesters, subjects, tasks, notes | Firestore | Flutter, owner-scoped |
| Material metadata | Firestore `materials` | Backend only |
| **Material file bytes** | **Backblaze B2** (private) | Backend only |
| Groups, membership, chat | Firestore | Backend only |
| Expenses, bazar, medicine, doses, trips | Firestore | Flutter, owner-scoped |
| Central ledger `financial_transactions` | Firestore | Flutter, in the same batch as its source record |
| Monthly budget | Firestore, under `users/{uid}/monthly_budget` | Backend |
| Focus sessions | Firestore, under `users/{uid}/focus_sessions` | Backend |
| AI usage quota | Firestore `ai_usage` | Backend |
| CommuteBD dataset, fare reports | Neon PostgreSQL + PostGIS | Backend (reports), operator (import) |
| Notification schedule | Device-local (`flutter_local_notifications`) | Flutter |

## 28. Authentication flow

```text
Flutter → Firebase Auth: email + password
       → email verification link (required)
       → Firebase ID token
       → Authorization: Bearer <token>  on every backend call
                    │
Backend  core/auth.get_verified_identity:
         · verify_id_token(check_revoked=True)
         · reject if email_verified is false            → 403
         · load users/{uid}; reject if missing          → 403
         · reject unless role ∈ {student, general}      → 403
         · require_student on Study/AI/Groups/Materials → 403
```

Firestore rules apply the same gates independently, so a compromised client
cannot read another student's documents even if it bypasses the backend.

## 29. Firestore architecture

Collections: `users`, `semesters`, `subjects`, `tasks`, `notes`, `materials`,
`material_state`, `page_notes`, `saved_materials` (subcollection),
`groups`, `group_messages`, `daily_expenses`, `bazar_items`,
`financial_transactions`, `medicines`, `medicine_doses`, `commute_trips`,
`ai_usage`, plus `monthly_budget` and `focus_sessions` subcollections under
`users/{uid}`.

`firebase/firestore.rules` (24 match blocks) enforces: signed in, email
verified, `ownerId == request.auth.uid` for personal documents, student role
for study documents, and group membership for group-visibility documents.

## 30. Backblaze B2 architecture

```text
Flutter (multipart, Bearer token)
   → FastAPI /api/materials/upload
      · require_student
      · magic-byte type sniff (PDF/PNG/JPEG/DOC/DOCX)
      · per-user storage quota + daily upload limit
      · sanitize filename; key = users/{uid}/{uuid}_{name}
      → B2 put_object   (private bucket, S3-compatible API)
      → Firestore materials document
        (rolls the B2 object back if this write fails)

Reading:
Flutter → /api/materials/{id}/url
      · ownership OR group-membership OR public check
      → presigned GET, ≤15 minutes, inline or attachment
```

The bucket must be **private**. A public B2 bucket hands out permanent
unauthenticated URLs, which would defeat the per-request ownership checks.

If any `B2_*` variable is missing the storage service raises rather than
falling back to another provider — an ambiguous runtime storage target is
precisely what must not happen. The startup banner logs the active target and
warns if the now-inert `FIREBASE_STORAGE_BUCKET` is still set.

> **Migration note.** Before this rebuild the runtime file store was Firebase
> Storage, despite the stated architecture naming Backblaze B2. The backend
> now speaks B2. **Files uploaded before the switch are still in the Firebase
> Storage bucket and are not migrated by this change** — see
> [Known limitations](#55-known-limitations).

## 31. AI architecture

```text
Flutter → Bearer token → FastAPI /api/ai/*
   · require_student
   · daily quota: atomic Firestore transaction on ai_usage/{uid}_{yyyymmdd}
   · material permission check (owner / group member / public)
   · fetch bytes from B2
   · extract text (pypdf) or attach image inline
   · OCR fallback when a PDF has no usable text layer
   → Gemini generateContent
   → classified error or answer
```

Gemini failures are classified rather than passed through: quota exhaustion →
429 "try again later", bad key → 503 "configuration error", model not found →
503, timeout → 504, provider 5xx → 502. The client maps each to a sentence.

Shared `httpx.AsyncClient` per process keeps the TLS handshake warm.

## 32. PDF/material AI flow

```text
PDF question
  → pypdf extract_pdf_text(page?)
  → if the result is under 40 characters:
        pdf2image renders pages 1-3 at 220 dpi
        → Tesseract OCR                          ← image-only PDF path
  → if still empty: 422 "No extractable PDF text"
  → else: prompt scoped to that text → Gemini
```

The image-only/scanned PDF case is handled, and it reuses the same OCR
pipeline as prescription scanning rather than a second implementation.

## 33. OCR architecture

See [§20](#20-prescription-ocr). In short: **Tesseract across several
preprocessing variants, the best-scoring read chosen by Tesseract's own
per-word confidence, a regex/keyword parser, and suggest-only medicine-name
matching. No custom ML model. The Gemini structuring pass is optional, off by
default, and may only regroup text OCR already read.**

Module layout:

```text
app/services/ocr/
  languages.py       what Tesseract can actually read on this server
  preprocess.py      Otsu, denoise, deskew, orientation — Pillow + NumPy only
  recognition.py     runs the variants, reports real per-word confidence
  medicine_names.py  suggest a spelling, never apply one
  structuring.py     optional model pass, grounded against the OCR text
app/services/ocr_service.py   parser and review candidates
```

OpenCV is deliberately not a dependency: it roughly doubles the Docker image
for a page skew the projection-profile method already handles.

The system dependencies are already provisioned: `backend/Dockerfile`
installs `tesseract-ocr`, `tesseract-ocr-eng`, `tesseract-ocr-ben` and
`poppler-utils`. `backend/ml/` is deliberately not copied into the image —
the fare trainer is an offline tool, not a runtime dependency.

## 34. ML model inventory

This section is mandatory and is written to be checkable.

### 34.1 Commute fare model

```text
Name:            Commute quantile fare model (rickshaw, CNG)
Purpose:         Predict a low/median/high fare band for negotiated modes
Model file:      models/commute/{mode}_quantiles.joblib   — DOES NOT EXIST
Framework:       scikit-learn GradientBoostingRegressor (quantile loss)
Input features:  distance_km, trip_minutes, traffic_level_encoded, hour, weekday
Output:          {low, median, high} rounded to ৳5, labelled "estimated"
Trainer:         backend/ml/train_fare_models.py        — EXISTS, runnable
Training data:   data/commutebd/ml/fare_training_template.csv
                 — HEADER ONLY, 0 rows
Loader:          app/services/commute/ml_fare.py MLFarePredictionService._load
Backend service: FareEngine (rickshaw and CNG branches only)
Endpoint:        POST /api/commute/routes, POST /api/commute/route
Flutter feature: CommuteBD fare cards
Runtime status:  NOT AVAILABLE — see below
```

**Why it is not available.** Three independent gates, all currently closed:

1. **No training data.** The training CSV is a header row and nothing else.
2. **No model artifact.** `download_bytes("models/commute/…joblib")` has
   nothing to fetch.
3. **An activation gate.** Even with an artifact, `enabled_for(mode)` requires
   ≥500 approved crowd reports overall and ≥150 for that mode
   (`COMMUTE_ML_MIN_TOTAL_REPORTS` / `COMMUTE_ML_MIN_MODE_REPORTS`).

`predict()` therefore returns `None` on every call and the fare engine falls
through to crowd statistics, then to the historical CNG meter rule or the
distance baseline. **Gochano does not currently use machine learning to
predict fares, and no screen claims it does.**

This is the honest outcome, not a gap to paper over: the repository does not
contain enough real data to train a meaningful model, and fabricating
training rows to be able to claim "ML" would produce a model that is worse
than the deterministic rules it would replace.

The pipeline is genuinely complete and correct — trainer, features, loader,
inference, rounding, fallback and activation policy. What it needs is
moderated real fare reports, which the app now collects.

**You can check this rather than take it on trust.** `GET
/api/commute/ml-status` and `scripts/commute_ml_status.py` read the real
approved-report counts and state them against the thresholds, naming every
blocker with its actual shortfall. The thresholds are reported *alongside* the
counts, so quietly lowering one to manufacture a green light would show up in
the output.

An unreachable database reports **unknown**, never zero. "We have no reports"
and "we cannot see how many reports we have" are different facts, and only one
of them is a reason to keep collecting. Run locally, with no `DATABASE_URL`,
the script prints exactly that:

```text
Commute fare model readiness
  status     UNKNOWN (database_unavailable)
  note       The report database is not configured, so the approved-report
             count cannot be read. Model readiness is unknown, not zero.
  fares today are rule-based and crowdsourced estimates only
```

A static test also asserts that no rule-based branch of the fare engine can
describe itself as a model prediction.

### 34.2 Prescription ML model

```text
Status: DOES NOT EXIST.
```

No artifact, no trainer, no loader, no inference, anywhere in the repository.
Prescription extraction is Tesseract OCR plus a rule-based parser. Nothing in
the UI describes it as ML or AI.

### 34.3 Repository-wide model search

Searched for `.pkl .pickle .joblib .onnx .pt .pth .tflite .h5 .keras` and for
`sklearn`, `tensorflow`, `torch`, `xgboost`, `lightgbm`, `catboost`,
`model.predict`, `load_model`, `joblib.load`, `pickle.load`.

**Result: zero model artifacts in the repository.** The only ML code is the
commute fare trainer and its loader described above.

## 35. CommuteBD architecture

### Dataset (Neon PostgreSQL + PostGIS)

| Table | Rows | Purpose |
|---|---|---|
| `brta_fare_segments` | 15,606 | Official BRTA stop-pair fares |
| `bus_service_stops` | 3,190 | Which services stop where, in order |
| `brta_graph_edges` | 2,398 | Directed stop adjacency along a route |
| `brta_route_stops` | 1,311 | Stop sequence per route |
| `places` | 387 | Canonical places with coordinates |
| `stop_aliases` | 301 | Alternate names |
| `metro_fares` | 272 | Official metro station-pair fares |
| `bus_services` | 156 | Named bus services |
| `brta_routes` | 112 | Route definitions |
| `rickshaw_auto_estimated_fares` | 20 | Distance baselines |
| `fare_rules` | 7 | Per-km and meter rules |
| `metro_stations` | 17 | MRT stations |

### Routing — what actually executes

```text
POST /api/commute/routes
  → resolve origin/destination against `places`
       (falls back to Nominatim geocoding when a place has no coordinates)
  → OSRM /route/v1/driving  → distance, duration, polyline
  → FareEngine.options(...)  → per-mode fare candidates, ranked
  → repo.bus_route_via_services(originId, destinationId)
       → SQL over bus_service_stops: services whose stop sequence
         contains both places in the right order
  → journey_service.plan(...)   → Dijkstra over the transport graph
       → Recommended / Cheapest / Fastest complete journeys
  → recommendations + transitCandidates + journeyPlanning + journeys
```

The response is additive: `recommendations` and `transitCandidates` are
unchanged, and `journeyPlanning` / `journeys` are new keys beside them. A
routing failure cannot break fare lookup — the planner is wrapped, and reports
`available: false` with a reason rather than taking the endpoint down.

### Dijkstra — verified status

> **A real Dijkstra shortest-path search now executes at runtime**, in
> `app/services/commute/graph.py`. This section previously recorded its
> absence; it was implemented rather than claimed.

What runs:

- **State is `(node, arrival_mode)`, not just `node`.** Pricing a transfer
  requires knowing what you arrived on, so the search relaxes over mode-aware
  states. A plain node-keyed search cannot represent "changing here costs ten
  minutes" at all.
- **Three weight functions over one graph.** `RECOMMENDED` minimises a
  generalised cost (time valued at ৳1.5/min, plus a transfer penalty and a
  walk-discomfort multiplier), `CHEAPEST` minimises fare, `FASTEST` minimises
  time. They are genuinely different searches, not one result relabelled
  three ways — and when two objectives do find the same journey it is
  returned once carrying both labels.
- **Non-negative weights, enforced.** `Edge.__post_init__` raises on a
  negative minute, fare or distance. Dijkstra's correctness depends on that
  precondition, so it is a constructor check rather than a comment.
- **Practicality filtering.** Per-leg and total walking caps, a minimum
  hired-vehicle leg, and a leg-count ceiling, all in one documented
  `RoutingPolicy` dataclass.

**No internal identifier can reach a student.** `TransportGraph.add_node`
refuses a node with a blank name, so a step that renders as `A1` or
`node_123` is impossible by construction rather than by convention. A Flutter
test greps the rendered timeline for those patterns as a second line of
defence.

Verified against the real dataset with `scripts/verify_commute_routing.py`:

```text
nodes                 404
edges                 5221
nodes with location   154   (derived from OSM; the dataset ships none)
walking transfers     212
planned               3/3 Dhaka trips
```

Sample real output, Mirpur 10 → Farmgate:

```text
[RECOMMENDED / FASTEST]  25 min  ~30 Tk  6.1 km  2 transfers
  Walk -> Metro -> Walk
  About 26 minutes faster than the cheapest option for around ৳16 more.
  * Mirpur 10 area
  |   Walk about 30 m to Mirpur 10 Metro Station.
  * Mirpur 10 Metro Station
  |   Board MRT Line 6 at Mirpur 10 Metro Station and get off at Farmgate
  |   Metro Station.   5.9 km - 12 min - ~30 Tk (official)
  * Farmgate Metro Station
[CHEAPEST]  52 min  ~14 Tk   Walk -> Bus -> Walk
```

Mohammadpur → Kamalapur produces a genuine five-mode journey:
`Rickshaw -> Bus -> Walk -> Metro -> Walk`.

Two bugs were found only by running against the real data, not by reading the
code: metro fares were being summed per consecutive station hop (৳100 for a
trip that costs ৳30 — fixed by pricing station *pairs*), and a merged
multi-edge walking leg reported the first edge's distance ("Walk about 0 m"
for 800 m).

**What is still missing.** Only 154 of 404 nodes have coordinates, because
the shipped dataset has `geocode_status: pending` for all 387 places;
`scripts/build_commute_geocode_asset.py` derives what it can from OSM. Nodes
without coordinates still route — they simply cannot be drawn on the map, and
the map says so rather than interpolating a line.

### Fare reliability

| Mode | Method | Label |
|---|---|---|
| Bus | `brta_fare_segments` stop-pair lookup, direct or one transfer | Official |
| Metro | `metro_fares` station-pair lookup | Official |
| CNG | Moderated crowd aggregate → *(ML gate, closed)* → government meter rule | Reported by riders / Historical rule |
| Rickshaw | Moderated crowd aggregate → *(ML gate, closed)* → distance baseline | Reported by riders / Estimated |
| Walk | Distance ÷ 4.5 km/h, under 2.5 km | Free |

A journey's headline certainty is its **weakest** leg. One official metro
fare cannot make a negotiated rickshaw fare in the same trip look official.

Ranking blends time, fare, walking distance, transfer count and a confidence
penalty; the top result is badged Recommended, plus Cheapest and Fastest.

### Fare report quality control

Crowd reports are only useful if the obviously-impossible ones never enter
the dataset. `app/services/commute/fare_quality.py` checks each submission
against physics and against the shipped `fare_rules.csv`, with every band
attributed to the rule it came from:

| Check | Example rejected |
|---|---|
| Absolute fare range per mode | ৳5 for a 20 km CNG trip; a ৳250 metro fare against the published ৳100 cap |
| Implied speed | 30 km in 20 minutes on a rickshaw |
| Passenger count | 40 passengers in a CNG |
| Paid walking | any fare on a `walk` trip |

Fares that are steep but possible are **flagged, not discarded** — an
unusually expensive route is exactly what a student wants warning about.

Before aggregation, `remove_outliers` prunes on the **median absolute
deviation**. A mean-and-sigma rule is dragged by the very outlier it is
looking for, so one mistyped ৳5,000 among thirty ৳30 fares would widen the
band enough to hide itself. Samples under four are left alone: with three
points there is not enough information to call any of them wrong.

The duplicate window is one hour, not one minute. The old minute-wide bucket
let a retry at 12:01:02 miss the original at 12:00:58 — precisely the case
the constraint existed to stop.

## 36. Expense architecture

One central ledger, `financial_transactions`, written **in the same Firestore
batch** as the source record it mirrors. Four sources feed it:

| Source | Row written when |
|---|---|
| `daily` | A daily expense is saved |
| `bazar` | A bazar item is marked purchased with a price > 0 |
| `medicine` | A dose is marked **taken** (cost = quantity × unit price) |
| `commute` | A trip's **actual** fare is confirmed by the student |

Every row uses a deterministic id, `{source}_{sourceRecordId}`, so a retry
overwrites rather than duplicates, and reversing the source action deletes the
row rather than leaving an orphan.

Estimated values never enter the ledger. A skipped or missed dose, an
unpurchased item and an estimated commute fare all write nothing.

`GET /api/budget/remaining` selects the month by `monthKey` and subtracts
confirmed spending from the monthly budget.

## 37. Medicine architecture

`medicines` holds the definition (name, strength, instruction, quantity per
dose, unit, price, times, start/end dates, active, paused). `medicine_doses`
holds one document per scheduled dose per day, at the deterministic id
`{medicineId}_{yyyymmdd}_{hhmm}` — which is what makes marking a dose
idempotent.

Today's schedule is derived by a shared domain module, so Home and the
Medicine hub cannot disagree about what the next dose is. A dose still
`pending` more than an hour after its time is treated as missed.

## 38. Notification architecture

Local notifications via `flutter_local_notifications` + `timezone`, on two
Android channels: reminders and medicine.

- **Task reminders** — one-shot at the due time. Deterministic id derived from
  the task id; `rescheduleTask` cancels and re-arms in one primitive.
- **Medicine reminders** — daily repeating per medicine per time.
- Completing a task cancels its reminder; editing reschedules it.
- Android 13+ `POST_NOTIFICATIONS` is requested by `NotificationService`.
- The medicine form and Profile both report when the OS has notifications
  off, because scheduling silently no-ops in that state.

FCM is initialised through Firebase Admin on the backend but **no server-push
notification is currently sent**; all reminders are device-local.

## 39. Localization

English and Bangla, one language shown at a time.

`GochanoLanguage.text(en, bn)` keeps both strings adjacent in the source, so a
translation cannot be silently forgotten when a screen is edited. The choice
is persisted to `SharedPreferences` and restored before the first frame, and
`GochanoLanguageScope` rebuilds the app from the root on change — so no
subtree can be left rendering the previous language.

A test scans every call site and fails on an empty side, Bengali script in the
English string, or an untranslated duplicate.

## 40. Folder structure

```text
flutter_app/lib/
├── app.dart                     MaterialApp + language/appearance scopes
├── main.dart                    bootstrap
├── core/
│   ├── design_system/           colors · typography · spacing · theme
│   │                            art (61 drawings) · illustration renderer
│   ├── localization/            persisted EN/BN
│   ├── settings/                persisted light/dark/system
│   ├── app_config · navigation · page_route
├── shared/
│   ├── widgets/                 scaffold, app bar, cards, buttons, rows, menus
│   └── states/                  loading · empty · error · friendlyErrorMessage
├── features/
│   ├── auth/  shell/  home/
│   ├── study/     workspace · materials · notes · ai · planner · focus
│   ├── life/      domain/ · expense/ · medicine/ · commute/
│   ├── tasks/  community/  profile/  search/
├── services/                    api · auth · firestore · financial ·
│                                notification · offline · connectivity · study
├── models/  widgets/            ledger model; language toggle, banners

backend/
├── app/
│   ├── main.py                  app + startup banner + JSON error handler
│   ├── core/                    auth · config · firebase · latency · utils
│   ├── routers/                 materials · ai · groups · prescriptions ·
│   │                            study · part3 · commute · account · reports
│   ├── services/                storage_service (B2) · legacy_storage
│   │                            (read-only) · storage_provider ·
│   │                            ai_service · pdf_service ·
│   │                            permission_service
│   │        ocr/{languages, preprocess, recognition, medicine_names,
│   │             structuring} + ocr_service (regex parser)
│   │        commute/{graph, graph_builder, journey, journey_service,
│   │                 fare_engine, fare_quality, ml_status, ml_fare,
│   │                 crowd, routing}
│   └── database/                SQLAlchemy models + repositories
├── data/commutebd/              CSV/JSON dataset + ML policy + derived
│                                place coordinates
├── data/medicines/              generic-name list for OCR suggestions
├── ml/train_fare_models.py      quantile fare trainer (no data yet)
├── migrations/ alembic/         schema
├── scripts/                     verify_b2_live · verify_commute_routing ·
│                                verify_prescription_ocr ·
│                                commute_ml_status ·
│                                migrate_firebase_to_b2 ·
│                                build_commute_geocode_asset
└── tests/                       334 tests

docs/RUNBOOK_POSTGRES_BASELINE.md   operational runbook (kept)
firebase/                            firestore.rules + indexes
```

## 41. Environment variables

Backend only. **Never place any of these in Flutter.** Names only — no values.

```text
APP_ENV
CORS_ORIGINS
INTERNAL_METRICS_TOKEN

FIREBASE_PROJECT_ID
FIREBASE_SERVICE_ACCOUNT_B64

DATABASE_URL

B2_BUCKET_NAME
B2_ENDPOINT_URL
B2_REGION
B2_KEY_ID
B2_APPLICATION_KEY

GEMINI_API_KEY
GEMINI_MODEL

MAX_UPLOAD_MB
USER_STORAGE_LIMIT_MB
UPLOAD_DAILY_LIMIT
SIGNED_URL_TTL_SECONDS
AI_DAILY_LIMIT

ROUTING_PROVIDER
OSRM_BASE_URL
NOMINATIM_BASE_URL
ROUTING_USER_AGENT
COMMUTE_ML_MIN_TOTAL_REPORTS
COMMUTE_ML_MIN_MODE_REPORTS
```

**Obsolete — remove from your environment:**

```text
SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_BUCKET   inert
FIREBASE_STORAGE_BUCKET                                    inert (warns at startup)
```

The Flutter app takes exactly one build-time value:

```text
--dart-define=API_BASE_URL=https://your-service.onrender.com
```

## 42. Local development setup

Prerequisites: Flutter **≥ 3.38** (developed on 3.47.2), Android Studio + SDK
34, JDK 17, Python 3.11+, Git, Node.js (for the Firebase CLI).

```powershell
flutter doctor            # resolve every red X first
```

```powershell
# Backend
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env    # then fill it in
uvicorn app.main:app --reload
```

```powershell
# App
cd flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_IP:8000
```

On a physical phone, `127.0.0.1` is the phone itself — use your PC's Wi-Fi
IP, or `adb reverse tcp:8000 tcp:8000`.

## 43. Firebase setup

1. Firebase console → your project (the checked-in config uses
   `gochano-a30c8`; reuse it rather than creating another).
2. **Authentication → Email/Password → Enable.**
3. **Firestore Database → Create**, production mode, region near Render.
4. Configure the app:
   ```powershell
   cd flutter_app
   dart pub global activate flutterfire_cli
   flutterfire configure     # Android, app id com.ekthikana.ekthikana
   ```
5. Deploy rules and indexes from the repo root:
   ```powershell
   firebase use --add
   firebase deploy --only firestore
   ```
6. **Service account** → Project settings → Service accounts → Generate new
   private key. Convert to one-line base64 and set it as
   `FIREBASE_SERVICE_ACCOUNT_B64`:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\service-account.json"))
   ```
7. Authentication → Templates → verify the email-verification template
   mentions Gochano.

Cloud Storage is **not** needed — files live in Backblaze B2.

## 44. Neon/PostGIS setup

1. Create a Neon project and database.
2. Enable PostGIS: `CREATE EXTENSION IF NOT EXISTS postgis;`
3. Set `DATABASE_URL` (psycopg2 form:
   `postgresql+psycopg2://user:pass@host/db?sslmode=require`).
4. Apply the schema (`backend/migrations/`, `backend/alembic/`).
5. Import the CommuteBD dataset from `backend/data/commutebd/core_dataset/`.
6. Verify:
   ```powershell
   python backend/scripts/verify_postgres_schema.py
   ```
   and `GET /api/commute/data-status`.

When `DATABASE_URL` is unset the backend falls back to in-memory SQLite so
tests and local development still run — CommuteBD endpoints then return 503.

## 45. Backblaze B2 setup

1. Create a Backblaze account and a bucket — **Private**, not Public.
2. Note the S3-compatible endpoint shown for the bucket, e.g.
   `https://s3.us-west-004.backblazeb2.com`, and its region
   (`us-west-004`).
3. App Keys → Add a New Application Key, scoped to that bucket, with read and
   write. Copy the **keyID** and the **applicationKey** — the secret is shown
   once.
4. Set in the backend environment:
   ```text
   B2_BUCKET_NAME       your-bucket
   B2_ENDPOINT_URL      https://s3.us-west-004.backblazeb2.com
   B2_REGION            us-west-004
   B2_KEY_ID            your-key-id
   B2_APPLICATION_KEY   your-application-key
   ```
5. Restart and check the startup log for
   `storage=backblaze-b2 bucket=… region=…`. If it says `<UNCONFIGURED …>`,
   the named variable is missing.

Keep the bucket private. Lifecycle rules are optional; the backend deletes
objects when a material is deleted or an account is removed.

## 46. Gemini setup

1. Create an API key in Google AI Studio.
2. Set `GEMINI_API_KEY` and `GEMINI_MODEL` in the backend environment only.
3. Without a key, everything except AI actions works; AI returns a clear
   "Unable to connect to the AI service" message rather than hanging.

`GEMINI_MODEL` must name a model your key can call. If it is wrong the
backend returns 503 "Gemini model configuration error" and logs the reason.

## 47. Render setup

1. Push to a private GitHub repository.
2. Render → New → Web Service → connect the repo.
3. Root directory `backend`, runtime **Docker**.
4. Health check path `/api/health`.
5. Add every variable from [§41](#41-environment-variables), or use
   `backend/render.yaml` as a blueprint.
6. Free instances sleep; the app uses long client timeouts and shows "Render
   may be waking up" rather than a generic failure.

## 48. Android setup

- SDK Platform 34, Build-Tools 34.0.0, Platform-Tools, command-line tools.
- Gradle JDK 17.
- Application id `com.ekthikana.ekthikana` — do not change it after the first
  Play Console upload.
- `POST_NOTIFICATIONS` is declared in the manifest and requested at runtime.
- Release signing: generate your own upload key and keep it out of the repo.

## 49. How to run the Flutter app

```powershell
cd flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://your-service.onrender.com
```

Build a debug APK:

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=https://your-service.onrender.com
```

Release bundle for Play:

```powershell
flutter build appbundle --release --dart-define=API_BASE_URL=https://your-service.onrender.com
```

`API_BASE_URL` is required; without it the app shows a configuration screen
instead of failing at the first request.

## 50. How to run the backend

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload
```

Then open `http://127.0.0.1:8000/api/health` and `/docs`.

The startup log prints one line naming the active database, storage target
and AI model — the fastest way to confirm a deployment is pointed where you
think it is.

## 51. Testing

**These are the results of runs performed on 1 September 2026, not
historical numbers.**

```powershell
cd backend && .\.venv\Scripts\python.exe -m pytest -q
```
```text
334 passed, 1 warning
```

```powershell
cd flutter_app && flutter analyze && flutter test
```
```text
Analyzing flutter_app... No issues found!
00:03 +174: All tests passed!
```

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=https://example.invalid
```
```text
Built build/app/outputs/flutter-apk/app-debug.apk    (223 MB debug build)
```

### Verification scripts

Unit tests prove the code does what it says. These run it against the real
data and the real services, which is a different claim:

| Script | What it proves | Needs |
|---|---|---|
| `scripts/verify_commute_routing.py` | The shipped CSVs build a graph that plans usable journeys | nothing |
| `scripts/verify_prescription_ocr.py` | The OCR pipeline reads a page end to end | Tesseract on PATH |
| `scripts/verify_b2_live.py` | 13 checks against the real bucket, including that it is private | B2 credentials |
| `scripts/commute_ml_status.py` | The fare model's real distance from being trainable | `DATABASE_URL` |
| `scripts/migrate_firebase_to_b2.py` | A dry-run report of what a migration would copy | both buckets |

Results of the runs on 1 September 2026:

```text
verify_commute_routing.py   404 nodes, 5,221 edges, 3/3 Dhaka trips planned
verify_prescription_ocr.py  Tesseract 5.4.0, eng+ben, 4/4 medicines, 94 (high)
verify_b2_live.py           13/13 against bucket Gochano-2026 (us-east-005)
commute_ml_status.py        UNKNOWN - no DATABASE_URL on this machine
migrate_firebase_to_b2.py   no legacy bucket configured; nothing to migrate
```

### Running the OCR verification locally

The Docker image installs Tesseract and both language packs, so the deployed
service needs nothing extra. To run `verify_prescription_ocr.py` on Windows:

```powershell
winget install --id UB-Mannheim.TesseractOCR --source winget
$env:PATH = "C:/Program Files/Tesseract-OCR;$env:PATH"
```

That installer ships `eng` and `osd` only. For Bengali, put `ben.traineddata`
somewhere writable and point Tesseract at it - the UB-Mannheim build installs
into `Program Files`, which needs administrator rights to write to:

```powershell
$dst = "$env:LOCALAPPDATA/gochano-tessdata"
New-Item -ItemType Directory -Force -Path $dst
Copy-Item "C:/Program Files/Tesseract-OCR/tessdata/*.traineddata" $dst
Copy-Item "./ben.traineddata" $dst          # from the tessdata repository
$env:TESSDATA_PREFIX = $dst
tesseract --list-langs                      # expect ben, eng, osd
```

### Build environment notes

Two toolchain problems were hit and fixed while producing that APK. Both are
environmental rather than defects in this project's code, but they will hit
anyone building it fresh:

1. **Android SDK Platform 36 is required.** Flutter 3.47 targets it; a
   machine set up for the older SDK 34 fails with *"Failed to install the
   following SDK components: platforms;android-36"*. Fix:
   ```powershell
   sdkmanager --licenses          # accept all
   sdkmanager "platforms;android-36"
   ```
   `JAVA_HOME` must be set for `sdkmanager` to run — the Android Studio JBR
   at `C:\Program Files\Android\Android Studio\jbr` works.

2. **Kotlin incremental compilation breaks the file_picker plugin.**
   `:android_file_picker:compileDebugKotlin` aborts with *"Could not close
   incremental caches … class-fq-name-to-source.tab"*, reproducibly, from a
   clean build directory with no daemon running. The failure is inside the
   plugin's own Kotlin compile, not in Gochano code.
   `android/gradle.properties` therefore sets `kotlin.incremental=false`,
   with a comment explaining why. Revisit when `file_picker` or the Kotlin
   Gradle plugin is next upgraded.

What the suites cover:

| Suite | Covers |
|---|---|
| `test_b2_storage` | B2 upload keys, presigned TTL cap, disposition, idempotent delete, fail-loud on missing config |
| `test_part3` | Budget/remaining maths including the client's real document shape and cross-month isolation |
| `test_security_audit` | Path traversal on upload, signed-URL TTL and V4, role gates |
| `test_materials`, `test_ai_question`, `test_prescriptions` | Upload/permission/AI/OCR routes |
| `test_commute_postgres` | Dataset repository queries |
| `api_contract_test` | Every Flutter API call matches a real route **and method** |
| `design_system_test` | Illustration integrity, subject/file/transport mapping, 4.5:1 contrast, error-copy safety |
| `theme_parity_test` | Light/dark parity, contrast floors, legacy layer removed |
| `accessibility_audit_test` | semanticLabel/tooltip coverage, **no decorative animation**, no hex literals |
| `translation_smoke_test` | Every bilingual literal is complete and actually translated |
| `financial_ledger_test`, `notification_policy_test` | Ledger and reminder rules |

**Not covered by automated tests:** anything requiring a live credential —
real Gemini calls, real B2 round-trips, real Firestore rules evaluation, real
OSRM/Nominatim responses, and on-device notification delivery. Those need the
manual pass in [§60](#60-deployment-checklist).

## 52. Feature verification table

Status vocabulary: **Verified locally** (exercised by an automated test or by
reading the executing code path end to end) · **Requires production
configuration** (correct in code, needs a live credential to prove) ·
**Working with limitation** · **Not available**.

| Feature | Status | Implementation | Dependency | Limitations |
|---|---|---|---|---|
| Register / login / logout | Verified locally | Firebase Auth | Firebase | Email verification required before any data access |
| Session restore, invalid token | Verified locally | AuthGate + `verify_id_token(check_revoked)` | Firebase | — |
| Semesters, subjects | Verified locally | Firestore, owner-scoped | Firestore | — |
| Material upload | Requires production configuration | `/api/materials/upload` → B2 | B2 | Types limited to PDF/PNG/JPEG/DOC/DOCX by backend sniffing |
| Material open / download | Requires production configuration | Presigned B2 GET ≤15 min | B2 | DOC/DOCX open in an external app |
| Rename / delete / save | Verified locally | Backend routes, owner-checked | Firestore, B2 | — |
| Recent + saved materials | Verified locally | Firestore | Firestore | A bookmark to a deleted material shows as Unavailable |
| Text notes + 4 AI actions | Requires production configuration | `notes` + `/api/ai/note` | Gemini | — |
| Universal search | Verified locally | Client-side over owner streams | Firestore | Capped at 300 docs per collection |
| AI general question | Requires production configuration | `/api/ai/note` | Gemini key | 30/day per user by default |
| AI PDF question | Requires production configuration | `/api/ai/pdf-question` | Gemini, B2 | — |
| AI image-only/scanned PDF | Requires production configuration | pdf2image + Tesseract fallback | Gemini, B2 | Tesseract and poppler are already in the Dockerfile |
| AI image question | Requires production configuration | `/api/ai/image-question` | Gemini, B2 | — |
| AI quota + provider failure | Verified locally | Firestore transaction; classified errors | — | — |
| Tasks add/edit/complete/undo/delete | Verified locally | Firestore | Firestore | — |
| Task reminders | Requires production configuration | `flutter_local_notifications` | Android permission | Silently inert if the OS denies notifications; the UI says so |
| Planner | Verified locally | `/api/study/plan` | Firestore | Deterministic ranking, not a model |
| Focus start/pause/resume/finish/history | Verified locally | `/api/study/focus/*` | Firestore | HTTP-method bug fixed in this rebuild |
| Groups create/join/leave/members | Requires production configuration | `/api/groups/*` | Firestore | Student role only |
| Group chat | Requires production configuration | `/api/groups/{id}/chat` | Firestore | Member-only; needs `chatEnabled`; poll-on-send, no live stream |
| Group resources (files + notes) | Requires production configuration | `/api/materials/upload` + `notes` | B2, Firestore | — |
| Unauthorized resource prevention | Verified locally | Backend checks + Firestore rules | — | Covered by `test_security_audit` |
| Monthly money / remaining | Verified locally | `/api/budget/*` | Firestore | Query bug fixed in this rebuild |
| Daily expense add/edit/delete | Verified locally | Batched source + ledger write | Firestore | — |
| Grocery + ledger mirror | Verified locally | Deterministic `bazar_{id}` row | Firestore | — |
| Duplicate prevention (all sources) | Verified locally | Deterministic transaction ids | Firestore | — |
| Medicine manual add | Verified locally | Firestore | Firestore | At least one reminder time is required |
| Medicine taken/skipped/missed/history | Verified locally | `medicine_doses` deterministic ids | Firestore | — |
| Medicine reminders | Requires production configuration | Daily repeating local notifications | Android permission | — |
| Prescription OCR | Verified locally | Multi-variant Tesseract, best read chosen by real per-word confidence, regex parser | Tesseract + poppler (in the image) | Verified end to end on a rendered page (4/4 medicines, 94 high); handwriting accuracy is unmeasured |
| Prescription custom ML | **Not available** | — | — | Does not exist; not claimed anywhere |
| Prescription name suggestions | Verified locally | Fuzzy match against shipped generic names | — | Suggest-only; a name is never rewritten automatically |
| Prescription model structuring | Working with limitation | Optional Gemini regrouping, off by default | Gemini key | Every field is re-checked against the OCR text and dropped if absent |
| OCR engine status | Verified locally | `/api/prescriptions/ocr-status` | — | Reports installed languages; `/extract` refuses rather than guessing |
| Commute place search | Requires production configuration | `/api/commute/search` | Neon, Nominatim | Falls back to dataset-only if the geocoder fails |
| Commute route + fares | Requires production configuration | `/api/commute/routes` | Neon, OSRM | Now called by the app; previously unreachable |
| Route overview map | Requires production configuration | `flutter_map` + OSM tiles, OSRM polyline | Network | Static line, no animation |
| Official bus/metro fares | Requires production configuration | Dataset lookup | Neon | Only for stop pairs present in the dataset |
| **Dijkstra / shortest path** | Verified locally | `commute/graph.py`, over `(node, arrival_mode)` states | — | 404 nodes, 5,221 edges; 3/3 Dhaka trips planned against the shipped CSVs |
| Multimodal journey planning | Verified locally | `journey_service.plan` — Recommended / Cheapest / Fastest | Neon | Three distinct searches over one graph, deduplicated |
| First and last mile | Verified locally | `attach_endpoint` — walk / rickshaw / CNG by distance | — | Endpoints beyond 4 km of the network report outside-coverage |
| Journey timeline + map | Verified locally | `journey_view.dart` | Network for tiles | Straight lines between stops, not road geometry; legs without coordinates are listed but not drawn |
| **Commute fare ML** | **Not available** | Trainer + loader exist | — | No training data (0 rows), no artifact, activation gate closed |
| Fare model readiness report | Verified locally | `/api/commute/ml-status`, `commute_ml_status.py` | `DATABASE_URL` to read real counts | Reports UNKNOWN, never zero, when the database is unreachable |
| Fare report quality control | Verified locally | `commute/fare_quality.py` | — | Impossible fares refused with a reason; steep-but-possible ones flagged, not discarded |
| Crowd fare outlier pruning | Verified locally | Median-absolute-deviation filter before aggregation | — | Samples under four are left alone |
| Post-trip actual fare → expense | Verified locally | Deterministic `commute_{id}` row | Firestore | Estimates never enter the ledger |
| Crowd fare report | Requires production configuration | `/api/commute/fare-report` | Neon | Stored pending moderation, not published |
| Community | Working with limitation | Study groups | Firestore | No posts/comments backend exists |
| Profile, language, appearance | Verified locally | SharedPreferences + Firestore | — | Both persist across restarts |
| Data export / account deletion | Requires production configuration | `/api/account/*` | Firestore, B2 | Deletion removes B2 objects too |
| B2 live validation | Verified against the live bucket | `scripts/verify_b2_live.py` | B2 credentials | 13/13, including a check that the bucket is private |
| Legacy file migration | Working with limitation | `scripts/migrate_firebase_to_b2.py` | Both buckets | Dry run by default; never deletes a source object; unverifiable here without a legacy bucket |
| Storage provider resolution | Verified locally | `storage_provider.resolve` | — | Records name their bucket; unlabelled ones are probed once and the answer recorded |
| English / Bangla | Verified locally | `GochanoLanguage` + root rebuild | — | Covered by `translation_smoke_test` |
| Light / dark | Verified locally | `ThemeExtension` tokens | — | Contrast floors covered by test |
| Offline behaviour | Working with limitation | Firestore cache + offline banner | — | Reads are cached; writes need a connection |

## 53. Security

- Every protected route requires a Firebase ID token, verified with
  `check_revoked=True`, plus a verified email and a valid role.
- Study, AI, Groups and Materials additionally require the `student` role.
- Firestore rules enforce the same gates independently of the backend.
- Upload filenames are sanitized and keys are locked under `users/{uid}/`;
  a path-traversal attempt is covered by a test.
- Signed URLs are V4 presigned GETs, capped at 15 minutes regardless of what
  `SIGNED_URL_TTL_SECONDS` is set to.
- Per-user storage quota, daily upload limit and daily AI limit are enforced
  server-side.
- Secrets exist only in the backend environment. The app holds one non-secret
  build value, `API_BASE_URL`.
- In production the global exception handler returns a generic message; the
  traceback goes to the Render log.
- Removed during this rebuild: a debug block that forced a token refresh on
  every bazar save and printed the signed-in email and full auth claims to
  the device log.

## 54. Privacy

- Fare reports are stored with a hashed user id, never the raw uid, and are
  held pending moderation rather than published.
- Group member rows show display names only; email and other profile fields
  stay private to the account that owns them.
- Prescription images are processed and not retained beyond the material
  record the student chooses to keep.
- Data export and account deletion are available in Profile; deletion removes
  Firestore documents and B2 objects.
- No analytics or third-party tracking SDK is present.

## 55. Known limitations

Ordered by how much they should worry you.

1. **Handwritten prescriptions are unmeasured.** The OCR pipeline is verified
   end to end against a *rendered* page, which proves the plumbing and says
   nothing about handwriting. Doctors' handwriting is the hard case and no
   accuracy figure exists for it. The confidence bands are what make this
   survivable: a poor read reports itself as one rather than presenting a
   confident-looking medicine list.
2. **Bangla OCR quality is only spot-checked.** `ben.traineddata` is
   installed and `eng+ben` is requested when available; a Bengali instruction
   line was recognised at 94 in verification. On a mixed-script page the
   winning variant is chosen for the page as a whole, so a Bengali line can
   still be missed when a Latin-optimised segmentation mode scores highest
   overall. Missed, not misread — nothing invents a translation.
3. **Only 154 of 404 transport nodes have coordinates.** The shipped dataset
   has `geocode_status: pending` for all 387 places, so coordinates are
   derived from OSM by name matching. Nodes without them still route; they
   just cannot be drawn, and the map says so instead of interpolating.
4. **Journey map lines are schematic.** They connect stop coordinates, not
   road geometry, because the dataset holds stops and not street shapes. The
   caption states this. It is not turn-by-turn navigation.
5. **Commute fare ML is unavailable** — no training data (0 rows), no
   artifact, and an activation gate needing 500 moderated reports overall and
   150 per mode. `scripts/commute_ml_status.py` reports the real distance
   from those thresholds rather than asserting it.
6. **The legacy Firebase migration is unverified against a live legacy
   bucket.** The script, its idempotency, its read-back verification and its
   resume are covered by 29 tests, and a dry run executes correctly, but no
   real object has been copied because this environment has no
   `FIREBASE_STORAGE_BUCKET`. Run the dry run first, read the report, then
   `--apply`.
7. **Gemini, Neon, OSRM and Nominatim are unverified against live
   credentials** in this environment. Backblaze B2 *is* verified — 13/13
   checks against the real bucket, including that it is private.
8. **Notification delivery is unverified on a physical device.**
9. **No Community feed.** Community is study groups. There is no
   posts/comments backend and no screen claims one.
10. **Group chat does not stream.** It reloads on send and on pull-to-refresh;
    a message from someone else appears on the next refresh.
11. **Public OSRM/Nominatim endpoints have no SLA** and rate-limit. Self-host
    or use a paid provider before public release.
12. **Universal search is client-side** over the first 300 documents per
    collection — fine for a student's own data, not a general search index.
13. **DOCX detection is by ZIP signature**, which also matches `.pptx` and
    `.xlsx`. Such a file would upload and be labelled DOCX.

## 56. Troubleshooting

**"Backend URL is not configured"** — run with
`--dart-define=API_BASE_URL=…`.

**"Cannot reach the Gochano backend"** — on a physical phone `127.0.0.1` is
the phone. Use your PC's Wi-Fi IP or `adb reverse tcp:8000 tcp:8000`. On
Render, the free instance may be waking; retry after a few seconds.

**Uploads fail with a 5xx** — check the startup log. If it reads
`storage=backblaze-b2 <UNCONFIGURED: missing …>`, the named `B2_*` variable is
absent. If it reads a bucket but uploads still fail, check the application
key is scoped to that bucket with write permission.

**Files that used to open now 404** — expected for materials uploaded before
the B2 switch; see [Known limitations](#55-known-limitations) item 2.

**`permission-denied` on the first Firestore read** — the account's email is
not verified. Rules block data access until it is.

**"Your profile is missing"** — the `users/{uid}` document was not created.
Sign out and register again.

**AI returns "Unable to connect to the AI service"** — `GEMINI_API_KEY` is
empty or invalid, or `GEMINI_MODEL` names a model the key cannot call. The
Render log has the classified reason.

**AI on a scanned PDF returns "could not extract enough text"** — the OCR
fallback ran and still found nothing. Check `tesseract-ocr` and `poppler-utils`
are installed in the Docker image.

**CommuteBD returns 503** — `DATABASE_URL` is unset or the dataset is not
imported. Check `GET /api/commute/data-status`.

**Route search returns no fares** — the route resolved but neither place is a
CommuteBD dataset place, so no official fare table applies. Pick a place from
the "CommuteBD places" section of the picker.

**Reminders never appear** — Android notification permission is denied.
Profile → Notifications shows this and links to system settings.

**`flutter pub get` fails on the SDK constraint** — the project needs Flutter
≥ 3.38. Run `flutter upgrade`.

## 57. What the project owner must do

Nothing in this list can be done from the source code. Each item needs your
account, your billing decision, your credential or a physical device.

1. **Set the five `B2_*` variables in Render.** The bucket itself is already
   created and validated — `scripts/verify_b2_live.py` passes 13/13 against
   `Gochano-2026` in `us-east-005`, including a check that it is private.
   Re-run that script against your own deployment before trusting it.
2. **Migrate pre-existing Firebase Storage files.** There is now a script for
   this:
   ```powershell
   cd backend
   $env:FIREBASE_STORAGE_BUCKET = "your-old-bucket"
   .\.venv\Scripts\python.exe scripts/migrate_firebase_to_b2.py           # dry run
   .\.venv\Scripts\python.exe scripts/migrate_firebase_to_b2.py --apply
   ```
   Read the dry-run report first. The script **never deletes a source
   object**; deleting the originals is a separate decision for you to make
   after confirming every file serves from B2.
3. **Keep `FIREBASE_STORAGE_BUCKET` set until migration is finished**, then
   remove it — that is how the backend knows there is no legacy bucket left
   to consult. `SUPABASE_*` can be removed now.
4. **Verify the Firebase project** — Email/Password enabled, Firestore
   created, rules and indexes deployed, `FIREBASE_SERVICE_ACCOUNT_B64` set.
5. **Verify the Neon database** — PostGIS enabled, schema applied, CommuteBD
   dataset imported, `DATABASE_URL` set. Confirm with
   `GET /api/commute/data-status`.
6. **Add your Gemini API key** and confirm `GEMINI_MODEL` is a model your key
   can call.
7. *(Already done — no action needed.)* The Docker image installs
   `tesseract-ocr`, `tesseract-ocr-eng`, `tesseract-ocr-ben` and
   `poppler-utils`, which is everything prescription OCR and the scanned-PDF
   AI fallback need. Confirm it on your deployment with
   `GET /api/prescriptions/ocr-status` — it reports the Tesseract version and
   the installed languages, so a missing Bengali pack shows up as a fact
   rather than as bad output.
8. **Check the fare-model readiness on the deployed instance**, where a
   `DATABASE_URL` exists: `GET /api/commute/ml-status`, or
   `scripts/commute_ml_status.py`. It prints the real approved-report count
   against the 500/150 thresholds. Do not lower those thresholds to switch
   the model on — the output reports them beside the counts precisely so that
   would be visible.
9. **Test on a real Android device**: register → verify email → upload a PDF →
   open it → ask AI about it → scan a prescription → set a medicine reminder
   and confirm it fires → plan a commute → follow the journey timeline →
   record an actual fare → check the expense total.
10. **Photograph real prescriptions, including handwritten ones**, and run
    them through `scripts/verify_prescription_ocr.py <image>`. That is the
    one gap automated testing cannot close, and the results should decide
    whether the confidence thresholds in `recognition.py` need moving.
11. **Replace the public OSRM/Nominatim endpoints** with a self-hosted or
    paid provider, and set a real contact address in `ROUTING_USER_AGENT`.
12. **Generate a signed release App Bundle** and keep the upload key outside
    the repository.
13. **Provide your app identity for Play**: developer name, support email,
    privacy-policy URL, terms URL, store listing, screenshots, content
    rating.

## 58. What the application does automatically

You do **not** need to do any of these by hand:

- Verify the Firebase ID token, email verification and role on every request.
- Enforce the storage quota, daily upload limit and daily AI limit.
- Sanitize filenames and scope object keys to the signed-in user.
- Mint short-lived presigned URLs after an ownership or membership check.
- Roll back the uploaded object if the metadata write fails.
- Fall back to OCR when a PDF has no usable text layer.
- Mirror confirmed spending into the central ledger in the same batch as its
  source record, with a deterministic id that makes retries safe.
- Delete the ledger row when the source action is reversed.
- Mark a dose missed an hour after its time.
- Cancel a task reminder when the task is completed, and re-arm it on undo.
- Fall back from crowd fares to rules to distance baselines, labelling each.
- Store fare reports pending moderation with a hashed user id.
- Restore language and appearance before the first frame.
- Cache Firestore reads for offline viewing and show the offline banner.
- Delete B2 objects and Firestore documents on account deletion.

## 59. How every feature works

**Create a semester** — Study → Workspace → Semesters → Add.
**Add a subject** — the semester card's ⋯ menu → Add subject.
**Upload a PDF** — Study → Workspace → a subject → the + button → choose a
file → Upload.
**Create a note** — Study → Workspace → Notes → Write.
**Ask AI about a material** — open it → the ✨ button; or a material row's ⋯
menu → "Ask AI about this". Remove the context with the × on the Using chip
to ask a general question instead.
**Create a group** — Community → New group → Create.
**Join a group** — Community → New group → Join with a code.
**Chat** — open the group → Chat. If it says chat is off, the group admin
turns it on from the ⋯ menu.
**Share a PDF or note to a group** — open the group → Resources → Share.
**Create a task** — Study → Tasks → Add task, or Home → Add task. Set a due
date to get a reminder.
**Plan study** — Study → Planner.
**Start a focus session** — Study → Focus → pick a length → Start focus.
**Add an expense** — Home → Add expense, or Life → Expense → the + button.
**Use Grocery** — Life → Expense → Grocery → Add. Enter unit price and
quantity; the total is calculated. Tick the checkbox when you buy it — that
is what records the expense.
**Set your monthly money** — Life → Expense → Overview → Available, or
Profile → Monthly money.
**Add a medicine manually** — Life → Medicine → Add medicine. Add at least
one reminder time.
**Scan a prescription** — Life → Medicine → Scan → take a photo or upload.
**Verify OCR results** — tap Review on a candidate, correct the name, dose
and instruction, **set the times yourself**, then Save.
**Mark Taken / Skipped** — Life → Medicine, on the next-reminder card or any
dose row's ⋯ menu.
**Use CommuteBD** — Life → CommuteBD → pick From and To → Find routes.
Choosing a place from "CommuteBD places" unlocks official fares.
**Submit an actual fare** — on a fare card, "I took this — record actual
fare". Enter what you paid; that becomes your expense.
**Search** — Study → the magnifier.
**Change language or theme** — Profile → Language / Appearance.

## 60. Deployment checklist

- [ ] Private B2 bucket created; `B2_*` set; startup log shows the bucket
- [ ] `SUPABASE_*` and `FIREBASE_STORAGE_BUCKET` removed from the environment
- [ ] Firebase: Email/Password on, Firestore created, rules + indexes deployed
- [ ] `FIREBASE_SERVICE_ACCOUNT_B64` set and decoding at startup
- [ ] Neon: PostGIS on, schema applied, dataset imported
- [ ] `GET /api/commute/data-status` returns data
- [ ] `GEMINI_API_KEY` and a valid `GEMINI_MODEL` set
- [x] Docker image has `tesseract-ocr` (+ `eng`, `ben`) and `poppler-utils` — already in `backend/Dockerfile`
- [ ] Render health check `/api/health` passing
- [ ] `CORS_ORIGINS` set to your real origins, not `*`
- [ ] `ROUTING_USER_AGENT` has a real contact address
- [ ] App built with the production `API_BASE_URL`
- [ ] Signed release App Bundle produced; upload key stored safely
- [ ] Real-device pass through the flow in [§57](#57-what-the-project-owner-must-do) item 8

## 61. Production readiness checklist

| Area | State |
|---|---|
| Code quality | `flutter analyze` clean; 126 Flutter + 156 backend tests pass; debug APK builds |
| Design system | One system; light/dark verified; contrast floors tested |
| Motion policy | No decorative animation; enforced by test |
| Localization | EN/BN complete and tested; persisted |
| Accessibility | Labels and tooltips enforced; 48dp targets; status never colour-only |
| Security | Token + role + rules; quotas; sanitized keys; TTL-capped URLs |
| Error handling | No raw exception reaches the UI; enforced by test |
| Dead code | 58 superseded files removed after import-graph analysis |
| **B2 storage** | **Implemented and unit-tested; never run against a live bucket** |
| **Legacy file migration** | **Not done — pre-migration files stay in Firebase Storage** |
| **Live integrations** | **Gemini, Neon, OSRM, FCM unverified in this environment** |
| **Device testing** | **Not performed** |

**This project is not "production ready" until the live-integration and
device items above are done.** Everything that can be verified without a
production credential has been.

## 62. Future scope

1. **Migrate existing Firebase Storage objects to B2** with a one-off script
   that rewrites each material's `filePath`.
2. **Multimodal routing with a real shortest-path search.** The dataset
   already has the adjacency list (`brta_graph_edges`, 2,398 edges) and the
   fare tables. A Dijkstra or A* over a graph whose edge weights blend time,
   fare and transfer penalty would produce genuine walk→bus→metro→rickshaw
   itineraries. This is the single largest missing capability.
3. **Train the fare model** once moderation has approved 500+ reports; the
   trainer, features, loader and activation gate are ready.
4. **Live group chat** via a Firestore snapshot listener.
5. **A community feed**, if it is wanted — it would need new backend
   endpoints, rules and moderation.
6. **Server-push notifications** through the already-initialised FCM.
7. **Offline write queue** so an expense recorded on the bus syncs later.
8. **Self-hosted OSRM/Nominatim.**

## 63. Final project status

Gochano is a working, coherent student application with a single design
system, 508 automated tests, and a backend whose integrations are correct in
code and — for storage and routing — verified against real data and a real
bucket.

**What the rebuild changed.** The frontend was rebuilt from the ground up: a
token-based Clean Minimalist design system with 61 project-owned static
illustrations, five-destination navigation, a briefing-style Home, a unified
Expense module replacing two disconnected ones, and honest OCR and fare UI.
All decorative animation was removed and is now blocked by test. 58
superseded files were deleted after verifying, feature by feature, that
nothing was lost.

**Six real bugs were found by end-to-end tracing and fixed:**

1. Focus pause/resume/finish sent POST to a PATCH-only route — every action
   returned 405 and never reached the server.
2. "Remaining money" always showed the full budget, because the endpoint
   range-filtered on a field no client has ever written.
3. Focus session elapsed time always read 0, because the client parsed
   `elapsedSeconds` while the server sends `accumulatedSeconds`.
4. The PostGIS-backed commute endpoint — with dataset place resolution,
   ranked options and real bus services — was never called by the app.
5. Every accented `AppCard` in a scrolling list threw *"BoxConstraints forces
   an infinite height"*, including the Recommended fare card. The accent rule
   is a `stretch` Row, and a ListView hands its children an unbounded height.
6. The test infrastructure itself: the fake Firestore treated range filters
   as unconditional matches, which is what let bug 2 pass CI. Fixed, so that
   class of bug cannot hide again.

**Four more were found only by running against real data**, not by reading
code: metro fares summed per station hop (৳100 for a ৳30 trip), a merged
walking leg reporting "about 0 m" for 800 m, a garbled dose absorbed into a
medicine name, and a short-but-perfect OCR read discarded as unreadable.

**What is now genuinely there.** A real Dijkstra over `(node, arrival_mode)`
states, planning complete multimodal journeys with first and last mile across
404 nodes and 5,221 edges — verified on 3/3 Dhaka trips against the shipped
dataset, with a step-by-step timeline and a map in the app. Prescription OCR
that tries several preprocessing variants and reports Tesseract's real
per-word confidence, verified end to end at 94 (high) on a rendered page.
Fare-report quality control that refuses the impossible and flags the merely
unusual. Backblaze B2, validated 13/13 against the live bucket. A migration
utility for legacy Firebase files that copies and never deletes.

**What is honestly not there.** There is no commute fare ML model and no data
to train one — `scripts/commute_ml_status.py` reports the real distance from
the threshold rather than asserting it, and no rule-based estimate anywhere
describes itself as a prediction. There is no custom prescription ML model.
There is no community feed. Handwriting accuracy is unmeasured, and the
confidence bands exist so a bad read reports itself as one.

**What remains before release** is mostly not code: live Gemini and Neon
credentials, the legacy-file migration run against your real bucket, a
real-device pass, and photographs of actual prescriptions to calibrate the
OCR thresholds. Those are listed concretely in
[§57](#57-what-the-project-owner-must-do).
