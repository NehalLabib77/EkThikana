# Gochano — Consolidated Source of Truth

> **This file replaces the prior scattered setup/architecture/audit docs.**
> All implementation details for the Gochano Android-first Flutter + FastAPI
> application live here. The appendices (`audit.json`, `FINAL_FEATURE_AUDIT.md`,
> `PROJECT_SPEC.md`, `PART4_REMOVAL_MANIFEST.json`) preserve per-phase evidence.

---

## 1. Product scope

Gochano is a **student-first life-organizer** with a single active role:

- **Student** — Study workspace (semesters / subjects / notes / materials /
  PDF reader / Study Planner / Study AI), optional private Group Chat (per
  group `chatEnabled` flag, OFF by default — pure shared box), Tasks, and
  all four LifeHub features (Medicine / BazarBuddy / Daily Expenses /
  CommuteBD).

The "General" role, RentMate, FamilyHub and Wellness are **legacy-only /
denied** and not present in any active UI, route, search, or Firestore
rule. Public academic material sharing is also removed — there is no
Community Library tile, no `public` visibility value, no public browser.

Finance is **expense tracking plus a single monthly-available budget**. The
Finance module exposes:

- A **Monthly Available** amount (in BDT) the user sets for the month.
- **Actual Confirmed Spending** — aggregated only from rows whose
  `sourceRecordId` still exists in the corresponding source collection
  (Daily expense, Bazar purchased, Medicine Taken, Confirmed Commute fare).
  Estimated commute, pending / skipped / missed medicine, unpurchased
  bazar never contribute.
- **Remaining Money** for the month, defined as:

  ```text
  Remaining = Monthly Available − Actual Confirmed Spending
  ```

  Income, savings, profit / loss, net-difference, or any "rolling
  balance across months" is intentionally NOT computed.

## 2. Brand and infrastructure identifiers

User-facing brand: **Gochano**.

The following identifiers are kept on purpose and must NOT be renamed without
intentional migration:

| Surface | Identifier | Reason |
| --- | --- | --- |
| Android application id | `com.ekthikana.ekthikana` | Firebase Android registration and any future Play Store identity are tied to it. |
| Supabase bucket | `ekthikana-files` | Private infrastructure; renaming moves objects and changes Render env `SUPABASE_BUCKET`. |
| Render service name / URL | unchanged | Existing URL is the deploy target. |
| Notification channel IDs | legacy IDs allowed | Display name shows Gochano; IDs are internal. |

---

## 3. Architecture

```text
Flutter Android client
 ├─ Firebase Authentication (email/password)
 ├─ Cloud Firestore (direct client reads/writes, owner-scoped subcollections)
 └─ HTTP client ──▶ FastAPI backend on Render
                       ├─ Firebase Admin SDK (token verification, role lookup)
                       ├─ Supabase Storage (private bucket, signed URLs)
                       ├─ Gemini API (backend-only Study AI)
                       ├─ Tesseract OCR (prescription parsing)
                       └─ OpenStreetMap-compatible stack for CommuteBD
```

### Flutter module layout

```text
lib/
  core/         app config, language, theme, navigation, ui helpers
  models/       data classes (incl. FinancialTransactionModel)
  services/     api_service, auth_service, firestore_service, financial_service,
                notification_service
  screens/
    auth/       login, register
    home/       role-aware shell/dashboard
    study/      semesters, notes, materials, PDF reader, Library, Planner
    groups/     shared box only (no chat)
    tasks/      tasks/reminders
    life/       Medicine, BazarBuddy, Daily Expenses, CommuteBD, ExpenseTracker
    profile/    profile, expense summary, export/delete
    search/     role-aware universal search
  widgets/      notification_action_host, etc.
```

---

## 4. Roles and access control

- The only active role is `student`. A legacy `general` role may still
  exist on accounts created before this scope change, but General users
  have no Study UI, no Groups, no Materials, no Study AI, and no Monthly
  Budget screen — Tasks + LifeHub only.
- Student-only collections (`semesters`, `subjects`, `notes`, `materials`,
  `groups`, `users/{uid}/saved_materials`, `users/{uid}/material_state`,
  `users/{uid}/monthly_budget`, `users/{uid}/messages` [opt-in]) are denied
  to non-Student users in rules and the Flutter UI hides them.
- Group material access requires group membership.
- **Group Chat is OPTIONAL.** A group with `chatEnabled: true` allows
  members to post into `groups/{id}/messages`; otherwise the group is a
  pure shared box. The default for newly created groups is `chatEnabled:
  false`. There is no DM, no global chat, no public chat, and no comment
  thread collection.

---

## 5. Study module (Student only)

Structure:

```text
Study
├── Semesters → Subjects → Notes / Materials
├── My Notes
├── My Materials
├── Saved Library
├── Study Groups / Shared Box (opt-in per-group chat)
└── Study Planner
```

There is no Community Library, no Browse Resources block, and no public
material browser. Materials live under the owner (Private) or under a
group the owner belongs to (`visibility == group`). The `public` value
was removed during PART 4 cleanup and is no longer accepted by the
backend.

PDF reader features: open, page navigation, text selection / search, zoom,
resume last page, bookmarks, page-linked notes, loading and error states.

Study AI: note cleanup, summarize, explain, key topics, PDF Q&A, Study Planner
assistance. **No MCQ / question / quiz generation.**

Groups: material sharing plus an **optional** private Group Chat. Chat is
disabled by default (`chatEnabled: false`); the group owner can flip it on,
which then exposes `groups/{id}/messages` to members only. There is no DM,
no global chat, and no comment thread collection.

---

## 6. Final LifeHub

Only four tiles (see §1):

```text
Medicine
BazarBuddy
Daily Expenses
CommuteBD
```

RentMate, FamilyHub and Wellness are absent from active UI, routes, search,
and Firestore rules. The Monthly Budget screen under Study → Tools is the
only Finance surface beyond the per-source expense views.

---

## 7. Central expense tracker + Monthly Available budget

Gochano is **not** a cash-flow / accounting app. There is exactly one
forward-looking input the user gives the Finance module per month:

```text
users/{uid}/monthly_budget/{YYYY-MM}
  monthKey        = "YYYY-MM"
  availableAmount = <float, BDT>
  currency        = "BDT"
  updatedAt, updatedAtIso
```

The central expense collection is append-only per source record:

```text
financial_transactions/{deterministicSourceId}
  ownerId, userId
  type   = expense
  status = confirmed | estimated
  source = daily | bazar | medicine | commute
  sourceRecordId, category, title, amount, date, dateKey, monthKey
  createdAt, updatedAt
```

Expense creation rules:

```text
Daily expense entered            -> confirmed expense (one row)
Bazar item purchased             -> confirmed expense (one row)
Bazar item unpurchased           -> linked confirmed expense removed
Medicine Taken                   -> confirmed expense (actual qty × unit-price)
Medicine pending / skipped / missed -> estimated expense only, no contribution
Commute estimated fare           -> estimated expense only, no contribution
Commute confirmed actual fare    -> confirmed expense (one row)
```

Every source update/delete **must** update/delete its linked deterministic
expense record. Retry / repeated taps must not duplicate charges.

### Remaining Money formula

```text
actualConfirmedSpending(month) = sum(amount) where
    status == "confirmed"
    and sourceRecordId exists in:
        daily_expenses, bazar_items (purchased), medicine_doses (Taken),
        commute_trips (confirmed actual fare)

Remaining(month) = MonthlyAvailable(month) − actualConfirmedSpending(month)
```

Estimated rows (estimated commute, pending / skipped / missed medicine,
unpurchased bazar) are NEVER counted toward Remaining. The endpoints
`POST /api/budget/monthly`, `GET /api/budget/monthly`, and
`GET /api/budget/remaining` are the authoritative surface — see §16.

---

## 8. Medicine

- Available to Student and General.
- Entry methods: **Add Manually** or **Scan Prescription**.
- OCR flow:
  `Image/PDF → OCR → suggestions → user reviews/edits → user confirms → quantity + price + schedule → save`.
- OCR must **never** auto-activate medicine name, dose, price, quantity,
  schedule or reminders. Show a medical-safety warning.
- Supports unit or pack/strip/bottle pricing; unit-price snapshots are stored
  on Taken doses.
- Dose statuses: `pending | taken | skipped | missed`. Only **Taken** creates
  an expense.
- Supports pause / resume / stop / history.

---

## 9. BazarBuddy

- Visual categories plus custom items.
- Item fields: name, quantity, unit, price, purchased.
- Supports add / edit / delete / purchased toggle, session / day / month
  history.
- Only purchased items create central expenses.

---

## 10. Daily Expenses

- Categories: Breakfast/Nasta, Lunch, Snacks, Dinner, Other.
- Multiple entries per category with title, amount, optional note, date/time.
- Daily / monthly totals come from the central expense collection.

---

## 11. CommuteBD

- Real interactive map and routing-provider abstraction.
- Supports GPS, origin/destination search, route polyline, distance, ETA,
  recenter, loading / offline / GPS-denied / no-route states.
- Use the supplied dataset. Official BRTA bus and Metro fares are
  **deterministic**. Crowd / ML is only for uncertain market fares such as
  Rickshaw / CNG and must show source / confidence. Do not fabricate live
  transport data.
- Estimated fare **never** becomes an expense. Only a user-confirmed actual
  fare creates the commute expense.

---

## 12. Data model

```text
users/{uid}                        displayName, email, role, university?, department?, semester?, timestamps
semesters/{id}                     (student-only)
subjects/{id}                      (student-only)
notes/{id}                         (student-only, visibility ∈ {private, group})
materials/{id}                     (student-only, private Supabase file metadata)
groups/{id}                        (student-only, membership list, chatEnabled: bool)
groups/{id}/messages/{msgId}       (student-only, OPT-IN per group, members-only)
users/{uid}/saved_materials/{id}   (student-only)
users/{uid}/material_state/{id}    (student-only, page notes, bookmarks)
users/{uid}/monthly_budget/{YYYY-MM} (student-only, availableAmount BDT)

tasks/{id}                         (Student + General)
medicines/{id}                     (Student + General)
medicine_doses/{id}                (Student + General)
bazar_items/{id}                   (Student + General)
daily_expenses/{id}                (Student + General)
commute_trips/{id}                 (Student + General)
financial_transactions/{id}        (Student + General, expense only, status: confirmed|estimated)
```

There is no DM, no global chat, and no public comment thread. Group chat
exists only as `groups/{id}/messages`, gated by the group's
`chatEnabled` flag.

---

## 13. Security and privacy decisions

1. Firebase ID tokens are verified by FastAPI before protected operations.
2. Email verification is required for app data access.
3. Role is loaded from the trusted Firestore profile, never from the client.
4. General users (legacy) cannot access student-only Firestore collections.
5. Groups have **chat disabled by default**; chat is opt-in per group via
   the group's `chatEnabled` flag and is members-only when enabled.
6. Group material access requires membership regardless of chat state.
7. Public academic material is no longer a supported feature (removed in
   PART 4); only authenticated Student users see materials shared with them.
8. Supabase bucket is private. The service-role key exists only on the
   backend.
9. Downloads use short-lived signed URLs (TTL ≤ 15 min).
10. Render local disk is **not** used as permanent storage.
11. AI / OCR keys never ship in the Flutter application.
12. Prescription extraction uses OCR; it does not automatically save medicine
    information. Users must confirm before creating a medicine record.
13. Automatic question / MCQ / quiz generation is intentionally absent.
14. Render deployment runs behind HTTPS; do not point production builds at
    `http://127.0.0.1`.

---

## 14. Explicitly forbidden

- Automatic MCQ generation
- Automatic question generation
- Quiz generation
- DM, global chat, public chat, comment threads (Group Chat is allowed only
  as an opt-in shared-box feature — see §4 / §5)
- Fake or live transport claims without a real provider
- Cash-flow / savings / profit / loss / net-difference features
- "Remaining balance" carried across months (Remaining is per-month only)
- Public note / material sharing (removed in PART 4)

---

## 15. Backend runtime

- FastAPI app under `backend/app/` (`main.py`, `routers/`, `services/`,
  `core/`, `schemas.py`).
- Stateless. User files live in Supabase; metadata in Firestore. Render
  filesystem is ephemeral and must not be used as persistent storage.
- Global JSON exception handler in `main.py` so unhandled failures return
  JSON. Full traceback stays in Render logs.
- Per-user storage quota (`storageUsedBytes`) is maintained as a
  denormalized counter on the `users/{uid}` document with a one-time
  legacy-seed scan, so `materials.py` upload checks are O(1) instead of
  full-collection scans.

### Required backend environment variables

| Variable | Purpose |
| --- | --- |
| `APP_ENV` | `production` on Render, anything else for local. |
| `FIREBASE_PROJECT_ID` | Firebase project id (matches FlutterFire config). |
| `FIREBASE_SERVICE_ACCOUNT_B64` | Base64 of Firebase service-account JSON. |
| `SUPABASE_URL` | Full Supabase URL or bare project ref. |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (backend-only). |
| `SUPABASE_BUCKET` | Bucket name (default `ekthikana-files`). |
| `GEMINI_API_KEY` | Optional. Disables Study AI when missing. |
| `GEMINI_MODEL` | Optional. Default model id (e.g. `gemini-1.5-flash`). |
| `OCR_LANG` | Optional. Tesseract language code (e.g. `eng+ben`). |

Secrets must live in Render environment variables or local
`backend/.env`; never commit them.

---

## 16. API surface (overview)

The live route catalog is generated by `backend/app/main.py` and is
verified by `backend/tests/test_openapi.py`. The overview below is the
canonical human-readable summary; do **not** add a route that is not
visible in `app.openapi()`. PART 4 removed the duplicate `me.py` router
file. **No `GET /api/me` exists** — identity is reached through
`/api/account/export` (returns `{profile: …}`) and the authenticated
Firebase ID token; there is no public "current user" endpoint.

Public:

- `GET /api/health`

Account / profile:

- `DELETE /api/account` — permanently delete the account and owned data
- `GET /api/account/export` — JSON export including `{profile: …}`

Student groups:

- `POST /api/groups`, `POST /api/groups/join`, group membership, materials
- `POST /api/groups/{id}/invite/reset`, `POST /api/groups/{id}/leave`
- `POST /api/groups/{id}/messages` / `GET /api/groups/{id}/messages`
  (members-only, 403 unless `chatEnabled == true` on the group)

Study:

- Notes CRUD, materials CRUD, signed-URL upload + download, AI endpoints

Finance / Monthly budget:

- `POST /api/budget/monthly` — set the Monthly Available amount for a month
- `GET /api/budget/monthly?month_key=YYYY-MM` — read the Monthly Available
- `GET /api/budget/remaining?month_key=YYYY-MM` — `Remaining = Available −
  Actual Confirmed Spending` (see §7)

LifeHub:

- Medicine CRUD, OCR prescription parse, dose record
- Bazar items CRUD + purchase toggle
- Daily expenses CRUD
- Commute route search, fare report, actual-fare record

The full route catalog lives in `backend/app/routers/` and
`backend/app/main.py`. PART 4 removed the duplicate `me.py` router file;
no replacement route is required.

---

## 17. Local setup (Windows)

```powershell
# 1. Install Flutter stable, Android Studio (with Android SDK), Git, Python 3.11+
flutter doctor
# Resolve every red X before continuing.

# 2. Backend
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pytest -q
```

```powershell
# 3. Flutter app
cd ..\flutter_app
flutter clean
flutter pub get
flutter analyze
flutter test
```

The Flutter app reads the backend URL from the build configuration. For local
phone testing either use `adb reverse tcp:8000 tcp:8000` or build with your
Render HTTPS URL — never ship `127.0.0.1` in a release build.

---

## 18. Android configuration

- `compileSdk` / `targetSdk` 34, `minSdk` 24.
- JDK 17 (Flutter Gradle JDK = 17 in Android Studio).
- Android 13+ notification permission declared.
- `RECEIVE_BOOT_COMPLETED` and scheduled-notification receiver declared so
  reminders survive reboots.
- Core-library desugaring enabled for `flutter_local_notifications`.
- **Launcher icon.** The Android launcher icon is generated from
  `flutter_app/assets/branding/Gochano.png` via the
  `flutter_launcher_icons` package (configured in `pubspec.yaml`). Run
  `dart run flutter_launcher_icons` after changing the master PNG. The
  launcher icon is a branding surface only — functional icons
  (back / menu / edit / delete / filter / etc.) stay on Material Icons.
- **Notification small icon.** Android 5+ requires the small notification
  icon to be a monochrome white-on-transparent drawable. The file
  `android/app/src/main/res/drawable/ic_stat_gochano.xml` is a simple
  flat Gochano "G" mark; it is referenced by
  `flutter_local_notifications` via `@mipmap/ic_launcher` foreground or
  the dedicated notification icon resource. **Never** pass the colourful
  full PNG as the notification icon — Android will render it as a solid
  white square.
- **Native splash.** `flutter_native_splash` produces the OS-level splash
  shown before the Flutter engine starts. Background color matches the
  Gochano dark premium background (`#0F1115`); the centered image is a
  padded variant of the master logo. Regenerate with
  `dart run flutter_native_splash:create` after editing `pubspec.yaml`.
- Debug builds allow cleartext HTTP only so a phone can talk to a local
  FastAPI server during development.
- If you regenerate `android/`, rerun `tool/bootstrap_flutter_windows.ps1`
  before `flutterfire configure`.

---

## 19. Firebase setup (one-time)

1. Firebase console → reuse the existing project (current FlutterFire config
   uses project id `gochano-a30c8`).
2. **Authentication → Sign-in method → Email/Password → Enable.**
3. **Firestore Database → Create database → production mode → region close
   to your Render service.**
4. From `flutter_app/`: `flutterfire configure` (already aligned to
   `gochano-a30c8`).
5. Generate a service-account JSON for the backend, base64-encode it, and
   store the value as `FIREBASE_SERVICE_ACCOUNT_B64` in Render.
6. Deploy the rules + indexes:

```powershell
firebase deploy --only firestore
```

---

## 20. Supabase setup

1. Create a Supabase project.
2. **Storage → New bucket** named `ekthikana-files`, visibility **Private**.
3. Copy the **Project URL** and **`service_role` key** from
   `Project Settings → API` into Render env (`SUPABASE_URL`,
   `SUPABASE_SERVICE_ROLE_KEY`).
4. The service-role key bypasses row-level security; it never leaves the
   backend.

---

## 21. Render deployment

1. Push the repo to a private GitHub repository.
2. Render → New → Web Service → connect the repository.
3. Root directory: `backend`.
4. Runtime: Docker (image built from `backend/Dockerfile`).
5. Instance: Free tier is enough for small workloads.
6. Or import `backend/render.yaml` as a blueprint.
7. Confirm `/api/health` returns 200 after deploy.

---

## 22. Gemini + OCR

- `GEMINI_API_KEY` is optional. When empty, the Study AI endpoint returns
  `503 AI is not configured` and the rest of the app keeps working.
- `GEMINI_MODEL` defaults to a stable model id (override only if your account
  has access to a different one).
- OCR runs inside the Render Docker image with Tesseract English + Bengali and
  Poppler. Local OCR uses the same Tesseract binary.
- OCR **must** be confirmed by the user before any medicine data is saved.

---

## 23. Branding, splash, and loading UX

Master assets live under `flutter_app/assets/branding/`:

- `Gochano.png` — final master logo (color, transparent background).
  Source of truth for the Android launcher icon, the native splash image,
  and the in-app splash. Already registered as a Flutter asset in
  `pubspec.yaml` (`assets/branding/Gochano.png`). Regenerate launcher
  icons with `dart run flutter_launcher_icons` after editing the master.
- (optional) `Gochano_foreground.png` — padded foreground used by
  adaptive-icon if the launcher needs the OS-mask-friendly crop. Only
  required if Android 12+ adaptive-icon foreground/background split is
  wanted; otherwise the launcher-icons config renders from the master.

Color tokens used by branding surfaces:

| Surface | Value | Notes |
| --- | --- | --- |
| Splash background | `#0F1115` | Matches the dark premium feel. |
| Loader ring | `#FFB300` | Gochano amber accent. |
| Body text | `#F5F5F5` | On dark surfaces. |
| Error | `#E53935` | For GochanoLoading error states. |

### Animated Flutter splash

`flutter_app/lib/screens/system/gochano_splash_screen.dart` is the screen
shown immediately after the native splash and before `AuthGate`. It
centers the Gochano logo with a fade + scale entrance, then keeps a thin
amber circular progress ring rotating **around** the logo while
`AuthGate` resolves. The logo itself never spins. After `AuthGate` emits
its first frame, the splash fades out (180–300 ms) and is replaced by
the home / login surface. The splash route is the initial route of
`MaterialApp`; `main()` runs `WidgetsFlutterBinding.ensureInitialized()`
before any of this.

### Reusable branded loader

`flutter_app/lib/widgets/gochano_loading.dart` exposes:

```dart
const GochanoLoading({
  String? message,           // shown under the ring; defaults to "Loading..." / "লোড হচ্ছে..."
  bool compact = false,      // true → 24 px ring, no message; for buttons
  VoidCallback? onRetry,     // when set, the widget shows an inline retry action after a delay
});
```

Behavior:

- Same rotating amber ring around the static logo.
- Bilingual strings via the existing `EkLanguage.text(...)` helper, so
  the loader follows the user's language toggle without any extra wiring.
- Threshold delay: the loading indicator only paints after ≥ 200 ms,
  avoiding a flicker on sub-second operations.
- Error / retry path: if a caller wraps the loader in an error boundary
  that passes `onRetry`, the widget switches from the rotating ring to
  a small "Tap to retry" affordance; otherwise the screen shows the
  loader until `parent` swaps it out.
- Performance: the `AnimationController` is always disposed in
  `dispose()`. No controllers leak.

The loader is wired into:

- `AuthGate` while Firebase / Firestore restores the session.
- Material upload / download (long form).
- AI Note / PDF Q&A (long form).
- Study Plan refresh.
- Group create / join / chat send.
- Material attachment upload inside Note editor.
- Prescription OCR.
- Bazar cloud sync / Daily cloud sync.
- Commute route / fare search.
- Monthly Budget save + Remaining fetch.
- Account export.

### Branding vs functional icons

The Gochano logo is a **branding surface only**. It is used on the
launcher, the native splash, the in-app splash, the loader, and any
"About" / splash fade end. Functional icons (back arrow, edit pencil,
delete trash, filter funnel, FAB plus, language toggle, etc.) stay on
Material Icons — they are not rebranded. Do not introduce a custom
Gochano glyph as a functional icon.

---

## 24. Notifications

Notification policy in PART 4.1:

- `flutter_local_notifications` schedules inexact alarms for tasks and
  medicine doses. Exact-alarm permission is intentionally not requested.
- After a cold launch the `NotificationActionHost` widget replays the most
  recent medicine notification action (Taken / Skipped) once the navigator
  is ready.

### Small icon (monochrome)

- Android 5+ requires the small notification icon to be a monochrome
  white-on-transparent drawable. The file
  `android/app/src/main/res/drawable/ic_stat_gochano.xml` is referenced
  as the Android notification **small icon** in
  `AndroidInitializationSettings('@drawable/ic_stat_gochano')`.
- **Never** pass the colorful master `Gochano.png` as the small
  notification icon — Android renders it as a solid white square.

### Channels (locked identifiers, may stay)

- `ekthikana_reminders` — generic Gochano reminders (task, group chat).
  Display name `Gochano Reminders`.
- `ekthikana_medicine` — medicine doses. Display name
  `Gochano Medicine Reminders`. Carries two actions:
  `Taken` and `Skip`. Only `Taken` creates a confirmed expense in the
  central ledger (via `FinancialService.recordMedicineDose`).
- Channel IDs are not user-facing and are preserved for compatibility
  with existing device-side settings and stats.

### Policy

- **Medicine.** A single Taken action produces exactly one confirmed
  expense in `financial_transactions/{deterministicSourceId}`. A Skip
  action records a `skipped` dose (no expense). Pending / missed doses
  do not generate notifications. The notification body is bilingual
  (English / Bangla) and routed through `EkLanguage.text(...)`.
- **Tasks / Study sessions.** Tasks schedule a single reminder per
  instance with a deterministic id (`taskId.hashCode & 0x7fffffff`).
  Cancelling the task cancels its reminder. The notification is muted
  silently if the user has muted the channel — Gochano does not surface
  a custom mute toggle; it relies on Android system channel settings.
- **Group notifications.** Group chat (text/image/PDF/DOC/DOCX)
  notifications are only emitted when the group's `chatEnabled` flag
  is `true`. While `chatEnabled == false` the group is a pure shared
  box and does not generate notifications. The channel-side rule is
  enforced in `NotificationService` before any schedule call.
- **Stable IDs.** Every scheduled notification uses a deterministic id
  derived from the source record (`sourceRecordId.hashCode &
  0x7fffffff` or `medicineId|hhmm.hashCode`). Re-scheduling the same
  source replaces the previous notification instead of duplicating it.
- **Permission denial.** If the OS denies `POST_NOTIFICATIONS`
  (Android 13+), the app continues to function without notifications.
  No exception is surfaced to the user; a single `debugPrint`-style
  swallowed log may be emitted for diagnostics.
- **No remote push.** This build uses local-only notifications. Remote
  push is intentionally deferred and is the only known gap that would
  belong in PART 5 if pursued.

---

## 25. Storage quota

- Each user's total uploaded bytes is maintained as `storageUsedBytes` on
  `users/{uid}`.
- Upload increments via `firestore.Increment(len(raw))`; delete decrements
  with a safe try/except so a stale counter never blocks deletion.
- On first use for legacy users the counter is seeded from a one-time
  full-collection scan.
- Default per-user cap is 200 MB.

---

## 26. Tests

Backend (FastAPI):

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
pytest -q
```

Flutter (Dart):

```powershell
cd flutter_app
flutter test
```

The PART 4 baseline produced 58 backend tests passing and 12 Flutter tests
passing. PART 4 also tightened `flutter analyze` (no errors; only pre-existing
info-level lints).

---

## 27. PART 4 deep cleanup summary

PART 4 (branch `part4-deep-clean`, off commit `89c6fdb`) executed the
following safety-respecting cleanup. Full evidence is in
`PART4_REMOVAL_MANIFEST.json` and the PART 4 section of
`FINAL_FEATURE_AUDIT.md`.

- **Public material / note visibility removed.** Backend whitelist tightened
  to `{private, group}`; Flutter UI dropdown no longer offers `public`;
  Firestore `canReadStudyDoc` no longer publishes a public read branch; the
  legacy `publicMaterials` / `publicNotes` stubs were removed.
- **`/api/me` router file removed.** `backend/app/routers/me.py` was deleted;
  `main.py` no longer imports or includes it. The `/api/me` route is not
  provided from any other router — it is gone from the API surface
  entirely; callers reach identity through `GET /api/account/export`
  (returns `{profile: …}`) and the verified Firebase ID token.
- **Savings / cash-flow removed.** `totalSavings` and `netDifference` fields
  were dropped from `FinancialTransactionModel` and the savings accumulator
  removed; the Flutter financial ledger test was rewritten.
- **Storage quota optimization.** `_check_storage_quota` now uses the
  denormalized `storageUsedBytes` counter on the user document with a
  legacy-seed scan fallback. Upload increments; delete decrements safely.
- **Archive / log cleanup.** `backend_backup/` (126 MB), `backend.zip` (44 MB)
  and `flutter_app.zip` (533 MB) were deleted. `flutter_run.log` and
  `flutter_app/lib.zip` removed.
- **`.gitignore` hardened** with patterns for service-account JSON, common
  cert / key formats, all `*.zip` archives, `Gochano_Full_Production/` and
  `_commute_patch/`.
- **Dead public-test cases removed**; legacy public-material ownership test
  kept only for migration reference.

---

## 28. Operational checklist before release

- [ ] `flutter clean && flutter pub get && flutter analyze && flutter test`
- [ ] Backend `pytest -q`
- [ ] `firebase use` selects the correct project
- [ ] Firestore `(default)` database exists; `firebase deploy --only firestore`
- [ ] Render env contains all required variables
- [ ] `/api/health` returns 200 after deploy
- [ ] Gemini Study AI succeeds with a real prompt
- [ ] OCR succeeds on a sample prescription
- [ ] Private Supabase bucket works (upload + signed URL download)
- [ ] Commute route + fare path returns deterministic BRTA / Metro results
- [ ] Notification reminders scheduled on a real device
- [ ] Account export / delete tested with a disposable account
- [ ] Android release keystore configured (`android/key.properties`)
- [ ] Privacy policy / Play Store Data Safety prepared

---

## 29. Troubleshooting quick recipes

- **`uvicorn` exits "Supabase storage credentials are not configured"** —
  set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in `backend/.env` or
  Render.
- **`firebase_admin` "default app already exists"** — only the app entry
  point initializes Admin SDK. Check no test script calls
  `firebase_admin.initialize_app(...)` twice.
- **`pytest ImportError: No module named pydantic_settings`** — install dev
  deps via `pip install -r requirements.txt`.
- **`/api/ai` returns `503 AI is not configured`** — `GEMINI_API_KEY` is
  empty; set it in Render env to enable Study AI.
- **`FormatException: Unexpected character ... Internal Server Error`** —
  the Flutter client already handles non-JSON responses, but if you still see
  it, check the Render log for the real exception.
- **`SocketException 127.0.0.1:8000` on a physical phone** — point
  `API_BASE_URL` at your Render HTTPS URL or use `adb reverse tcp:8000
  tcp:8000` for local development.

---

## 30. Appendix — preserved evidence

The following artifacts remain in the repo root as authoritative per-phase
evidence and must NOT be deleted:

- `audit.json` — machine-readable feature audit (PARTs 1–4.1).
- `FINAL_FEATURE_AUDIT.md` — human-readable audit narrative (PARTs 1–4.1).
- `PROJECT_SPEC.md` — earlier long-form specification (kept for diff
  traceability).
- `PART4_REMOVAL_MANIFEST.json` — removal record with safety baseline.
- `.part4_pre_git_safety.json` — git safety snapshot taken at the start of
  PART 4.
- `.part3_*` — PART 3 git-safety + normalization backups.
- `_audit_*.txt`, `_p3_*.py`, `_recon_*.py`, `_verify_audit.py`,
  `_part4_secret_scan.py`, `_inspect_keys.py`, `_grep_doc.py`,
  `_tail_check.py`, `_inspect_keys.py` — historical recon / audit evidence
  (tracked).

The third-party Python dependency manifests (`backend/requirements.txt`,
`backend/requirements-ml.txt`) and `flutter_app/PUBSPEC_REQUIRED.txt` are
preserved verbatim and must NOT be edited by documentation passes.

---

## 31. What's intentionally NOT in this file

- Live secret values, tokens, project ids, or service URLs.
- Supabase / Render / Firebase console screenshots.
- Per-account UI walk-through videos.
- Anything that requires the operator's real cloud accounts to be useful.

If a future Gochano contributor needs those, they are operator-side tasks
listed in §28.

---

## 32. PART 4.1 — Branding, Loading UX & Notification Polish

PART 4.1 is a **branding/UX pass only**. It does NOT change product scope,
roles, data model, or any forbidden feature. Locked infrastructure identifiers
(`com.ekthikana.ekthikana`, `ekthikana-files`, `ekthikana_reminders`,
`ekthikana_medicine`) are preserved.

### Source-of-truth assets

- `flutter_app/assets/branding/Gochano.png` — final master logo (color,
  transparent background). Already declared in `pubspec.yaml`. Source
  for the Android launcher icon, the native splash image, and the
  in-app splash.
- (optional) `flutter_app/assets/branding/Gochano_foreground.png` —
  padded foreground used only if Android 12+ adaptive-icon foreground
  is required.
- `android/app/src/main/res/drawable/ic_stat_gochano.xml` — monochrome
  white-on-transparent drawable used as the Android notification
  **small icon**. Never replaced by the colorful `Gochano.png`.

### Pubspec & generator wiring

- `pubspec.yaml` registers `assets/branding/Gochano.png` and declares
  a single `flutter:` block (one `assets:`, no duplicates).
- `flutter_launcher_icons` config reads from `Gochano.png`; running
  `dart run flutter_launcher_icons` regenerates the launcher icons in
  every density bucket.
- `flutter_native_splash` config uses dark premium background
  (`#0F1115`) and a padded variant of the master logo; running
  `dart run flutter_native_splash:create` regenerates native splash
  drawables for both day and night themes and Android 12+ splash
  support.

### Animated Flutter splash (`lib/screens/system/gochano_splash_screen.dart`)

- Shown immediately after the native splash and before `AuthGate`.
- Centers the Gochano logo with fade + scale entrance, then keeps a
  thin amber ring rotating **around** the (stationary) logo while
  `AuthGate` resolves. The logo itself never spins.
- After `AuthGate` emits its first frame the splash fades out
  (180–300 ms) and is replaced by the home / login surface.
- The splash is the `MaterialApp` initial route. `main()` runs
  `WidgetsFlutterBinding.ensureInitialized()` and any cached
  `precacheImage` before this screen paints.
- The `AnimationController` is always disposed in `dispose()`.
  Re-decoding of `Gochano.png` happens at most once.

### Reusable branded loader (`lib/widgets/gochano_loading.dart`)

- Renders the same amber rotating ring around the static Gochano logo.
- Bilingual strings via the existing `EkLanguage.text(...)` helper
  (`"Loading..."` / `"লোড হচ্ছে..."`).
- Compact mode (24 px ring, no message) for in-button busy states.
- Optional `onRetry` callback — when set, the widget exposes a
  "Tap to retry" affordance after a threshold delay (200 ms threshold
  to avoid flicker on sub-second operations).
- The `AnimationController` is always disposed in `dispose()`.

### Branding vs functional icons (PART 4.1 reaffirmation)

The Gochano logo is a **branding surface only**. It is used on the
launcher, the native splash, the in-app splash, the loader, the
Login/Register header, the `_SetupRequiredApp` error screen, and any
"About" surface. Functional icons (back arrow, edit pencil, delete
trash, filter funnel, FAB plus, language toggle, etc.) stay on Material
Icons — they are NOT rebranded. No custom Gochano glyph is used as a
functional icon.

### Notifications — see §24

Channel IDs are preserved. The small notification icon is the
monochrome `@drawable/ic_stat_gochano`, NOT the colorful master PNG.
Medicine Taken produces exactly one confirmed central expense.
Skip produces a `skipped` dose with no expense. Group chat notifications
are gated on the group's `chatEnabled` flag.

### PART 4.1 status

**IMPLEMENTED_LOCAL_VERIFIED.** No NEEDS_LIVE_TEST promotions. No
PART 5 auto-start. The exit gate is the same as PART 4: `flutter
analyze` clean, `flutter test` passing, `pytest -q` passing, Render
`/api/health` 200 OK. The only device-side checks left for a human
run are listed under the existing §28 operational checklist
(notification channel mute UI, real-device cold-start splash fade).
