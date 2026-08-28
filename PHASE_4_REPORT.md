# Phase 4 — Medicine UX Redesign

Scope: presentation-only changes in **5 UI files**. No service, schema, API,
OCR backend, or notification payload was touched.

## Files changed

| File | Change |
|---|---|
| `flutter_app/lib/screens/life/medicine_screen.dart` | Added loading skeleton, polished empty-state card (with onAddManual / onScan callbacks), purple "This month" pill in summary. |
| `flutter_app/lib/screens/life/medicine_form_screen.dart` | Added `strength` controller + field, three `SectionHeader` blocks, friendly AlertDialog validation helper, `EkColors.green` save button. |
| `flutter_app/lib/screens/life/medicine_ocr_screen.dart` | Inline retry banner, improved loading visuals, new `_CandidateCard` widget with optional confidence pill + dose/schedule chips. |
| `flutter_app/lib/screens/life/medicine_history_screen.dart` | Added `monthlyCost` aggregation, wrapped stats row in Column with purple "This month" pill, `SectionHeader` above list. |
| `flutter_app/lib/widgets/notification_action_host.dart` | Deep-link to `MedicineScreen` via `AppNavigation.navigatorKey.currentState?.push(...)` before any dialog/snackbar. |

## Logic preservation matrix

| Layer | Status |
|---|---|
| `FinancialService` (`recordMedicineDose`, `monthKey`, cost formula, mirror txn) | **Untouched** |
| `NotificationService` (`scheduleDailyMedicine`, payload `{kind, medicineId, medicineName, hhmm, quantityPerDose, unitPrice, unit}`, action IDs `taken` / `skip`) | **Untouched** |
| `ApiService.prescriptionOcr` call shape (multipart fields, response parsing) | **Untouched** |
| Backend `POST /api/prescriptions/extract` (Tesseract, candidate lines, warning) | **Untouched** |
| Firestore schema (`medicines/{id}`, `medicine_doses/{id}`, `financial_transactions/medicine_<doseId>`) | **Untouched** — form now also writes optional `'strength'` (existing field on schema) |
| OCR "may be inaccurate" warning banner on candidate review | **Kept** |
| Manual confirmation gate before save (no auto-save) | **Kept** |

## New UX pieces

- **Loading skeleton** on Medicine entry: skeleton cards mimic the real layout while Firestore streams resolve.
- **Empty state**: 💊 emoji, bilingual heading, **Add Manually** (outlined) + **Scan Prescription** (filled) buttons.
- **Monthly expense pill**: purple rounded chip below the 4-stat summary row in both `MedicineScreen` and `MedicineHistoryScreen`, computed via `FinancialService.monthKey(DateTime.now())`.
- **Strength field**: stored under optional `strength` key, validated visually but non-blocking.
- **Form sections**: `Medicine Info`, `Price`, `Schedule` separated with `SectionHeader` bilingual titles.
- **Validation dialog**: `AlertDialog` with icon + "Please review" header + message + "Got it" button — replaces toast.
- **OCR retry**: inline red banner with **Choose another** + **Retry** buttons; retry reuses last bytes & filename.
- **Candidate card**: name, instruction, optional confidence pill (green ≥0.75, orange ≥0.5, red otherwise — only rendered when backend supplies a numeric value), dose + schedule chips, **Review** CTA.
- **Notification deep-link**: tapping a medicine notification now lands on `MedicineScreen` first, *then* shows the taken/skip dialog or snackbar. The `MedicineNotificationAction` payload shape is unchanged.

## Verification

- `flutter analyze` (project-wide): **5 pre-existing infos**, no new warnings or errors introduced by Phase 4.
- Each modified file analyzed individually after its edits: clean.
- Manual smoke points (not run by agent — run on device before shipping):
  1. Cold-launch app, then trigger a medicine notification → confirm dialog opens on top of MedicineScreen.
  2. Add medicine via form → verify Firestore doc has `strength` populated.
  3. Scan prescription with poor-quality image → confirm inline retry banner appears; retry reuses bytes.
  4. Open MedicineScreen with no medicines → see new empty-state card; tap "Scan" → routes to OCR.
  5. Mark a dose taken → verify `medicine_doses/{id}` and `financial_transactions/medicine_<doseId>` both populated; verify "This month" pill increments.

## Out of scope (intentionally untouched)

- `FinancialService` cost formula and mirroring logic.
- `NotificationService` payload contract.
- OCR backend (Tesseract config, candidate heuristics, warning strings).
- Firestore rules and migrations.
- Any other screen outside the Medicine module.
