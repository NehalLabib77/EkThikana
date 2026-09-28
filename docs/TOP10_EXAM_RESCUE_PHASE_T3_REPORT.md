# Gochano Top-10 Competition Upgrade: Phase T3 Implementation Report

**Feature**: Exam Rescue (পরীক্ষা উদ্ধার) — UI Foundation & Interactive Plan Preview
**Phase**: T3
**Status**: PASS
**Branch**: `feature/top10-exam-rescue-v1`
**Date**: September 29, 2026

---

## 1. Files Changed

The following files were created or modified as part of Phase T3:

1. `flutter_app/lib/features/study/presentation/rescue/exam_rescue_setup_sheet.dart` (Created)
   - Bottom sheet modal for configuring an exam rescue plan with inline title validation, date chips (Today/Tomorrow/3d/5d/Custom), daily budget selection (1h/2h/3h/4h/Custom), document material picker, zero-material confirmation dialog, extra topics, and error handling.
2. `flutter_app/lib/features/study/presentation/rescue/exam_rescue_preview_screen.dart` (Created)
   - Interactive in-memory preview screen rendering hero statistics, source transparency badge, fallback indicator, AI rescue strategy summary, daily timeline cards with color-coded type badges (`Study`, `Practice`, `Quiz`, `Revision`), dynamic in-memory item removal updating totals, and bottom actions `[ Edit / Back ]` and `[ Regenerate ]`.
3. `flutter_app/lib/features/study/presentation/planner/plan_view.dart` (Modified)
   - Integrated `_ExamRescueBanner` placed immediately below `_DateStrip` and above `_CombinedPlannerList`, wired to `showExamRescueSetupSheet(context)`.
4. `flutter_app/lib/services/api_service.dart` (Modified)
   - Added `ApiService.generateExamRescuePlan` client method interfacing with `POST /api/ai/exam-rescue/plan` with student authentication and DTO parsing.
5. `flutter_app/test/exam_rescue_flow_test.dart` (Created)
   - 15 comprehensive widget tests covering setup form rendering, inline validation, date/time chips, material removal, zero-material confirmation, 320dp layout, 2.0x font scaling, preview screen rendering, source/fallback transparency, in-memory deletion, Bangla localization, and `PlanView` banner entry.
6. `docs/TOP10_EXAM_RESCUE_PHASE_T3_REPORT.md` (Created)
   - Phase T3 implementation and verification report.

---

## 2. ExamRescueSetupSheet Implementation

The setup modal is implemented in `ExamRescueSetupSheet` under `flutter_app/lib/features/study/presentation/rescue/exam_rescue_setup_sheet.dart`:
- Top-level launcher helper: `showExamRescueSetupSheet(BuildContext context, {...})`.
- Designed using Gochano design tokens (`GochanoColors`, `GochanoSpacing`, `GochanoRadius.sheet`, `GochanoTypography`).
- Structured in a rounded bottom sheet with a central drag handle, flexible scrollable form body, and pinned sticky bottom action bar.
- Form components include:
  - Header with bolt icon, screen title ("Exam Rescue" / "এক্সাম রেসকিউ"), and subtitle.
  - Exam/Subject input field with inline validation.
  - Exam Date chip selector and contextual remaining days indicator.
  - Daily Study Time chip selector and dynamic hour/minute counter.
  - Study Materials list with file badges, delete buttons, counter, and picker launcher.
  - Optional Extra Focus Topics text field.
  - Inline error banner and primary action button.

---

## 3. PlanView Exam Rescue Entry Point

In `flutter_app/lib/features/study/presentation/planner/plan_view.dart`:
- `_ExamRescueBanner` is positioned immediately beneath `_DateStrip` and above `_CombinedPlannerList`.
- Visually styled with `colors.brandSoft` container, subtle brand border (`Border.all(color: colors.brand.withValues(alpha: 0.18))`), lightning bolt icon (`Icons.bolt_rounded`), bold headline (`GochanoLanguage.text('Exam Rescue', 'পরীক্ষা উদ্ধার')`), subtitle (`GochanoLanguage.text('Exam close? Build a focused rescue plan.', 'পরীক্ষা কাছাকাছি? একটি গোছানো উদ্ধার প্ল্যান তৈরি করুন।')`), and tonal action button (`[ Build Plan ]` / `[ প্ল্যান বানান ]`).
- Tapping "Build Plan" invokes `showExamRescueSetupSheet(context)`.

---

## 4. Material Picker Reuse

Exam Rescue reuses the existing, production-tested document picker rather than creating duplicate material selection code:
- Calls `showMaterialPicker(context)` from `flutter_app/lib/features/study/presentation/ai/material_picker_sheet.dart`.
- Uses `allowImages: false` (documents only: PDF, DOC, DOCX, TXT).
- Limits selection to a maximum of 3 materials.
- Deduplicates incoming materials by `id`.
- Selected materials are displayed in high-contrast chips with document icon (`Icons.description_outlined`), truncated file title, and individual delete icon button (`tooltip: 'Remove material'`).
- Displays live counter text: `2 of 3 selected` / `২ / ৩টি নির্বাচিত`.

---

## 5. Exam Title, Date, and Time Validation

- **Exam Title**:
  - Validated via `_validateTitle(String value)` on submit and dynamically on text change.
  - Requires trimmed non-empty string.
  - Minimum length: 2 characters (`"Exam title must be at least 2 characters."` / `"পরীক্ষার নাম কমপক্ষে ২ অক্ষরের হতে হবে।"`).
  - Maximum length: 150 characters (`"Exam title cannot exceed 150 characters."`).
  - Empty string: `"Please enter an exam or subject title."` / `"দয়া করে পরীক্ষা বা বিষয়ের নাম লিখুন।"`.
- **Exam Date**:
  - Presets: `Today` (0-day emergency cram), `Tomorrow` (1-day, default), `3 Days`, `5 Days`.
  - `Custom`: Opens native `showDatePicker` constrained between today and today + 14 days.
  - Contextual remaining days header:
    - 0 days: `"Exam is today (1-day emergency cram)"` / `"পরীক্ষা আজকেই (১ দিনের ইমার্জেন্সি রিভিশন)"`.
    - 1 day: `"1 day remaining (Tomorrow)"` / `"১ দিন বাকি (আগামীকাল)"`.
    - >1 days: `"$days days remaining"` / `"${GochanoLanguage.formatNumber(days)} দিন বাকি"`.
- **Daily Study Time**:
  - Presets: `1 hour` (60m), `2 hours` (120m, default), `3 hours` (180m), `4 hours` (240m).
  - `Custom`: Interactive modal dialog with slider bounded between 30 minutes and 720 minutes (12 hours) in 15-minute increments.
  - Dynamic display badge: `${minutes ~/ 60}h ${minutes % 60}m` (e.g. `2h 0m`, `1h 0m`).

---

## 6. Zero-Material UX

If a student attempts to generate a plan without selecting study materials:
- An `AlertDialog` is displayed:
  - Title: `"No Materials Selected"` / `"কোনো মেটেরিয়াল নির্বাচন করা হয়নি"`.
  - Message: `"No materials selected. Gochano will create a general subject-based rescue plan."` / `"কোনো মেটেরিয়াল নির্বাচন করা হয়নি। গচানো সাধারণ বিষয়-ভিত্তিক রেসকিউ প্ল্যান তৈরি করবে।"`.
  - Actions:
    - `[ Select Materials ]`: Cancels generation so the student can select documents.
    - `[ Continue ]`: Confirms and proceeds with subject-only AI plan generation.

---

## 7. Generate and Loading State

- The primary action button uses `PrimaryButton`:
  - Default label: `"Generate Rescue Plan"` / `"রেসকিউ প্ল্যান তৈরি করুন"`.
  - Busy label: `"Generating Rescue Plan…"` / `"প্ল্যান তৈরি হচ্ছে…"`.
- When generation starts:
  - `_isGenerating = true` prevents multiple clicks or concurrent requests.
  - `_errorMessage = null` clears previous errors.
  - Button switches to busy state with indicator.

---

## 8. Async Lifecycle Safety

- All asynchronous flows verify `if (!mounted) return;` before calling `setState(...)`, showing dialogs, navigating, or displaying snackbars:
  - After `showMaterialPicker`: `if (!mounted || picked.isEmpty) return;`
  - After `ApiService.generateExamRescuePlan`: `if (!mounted) return;`
  - In `catch (ApiException)` and `catch (_)` error blocks: `if (!mounted) return;`
  - In `_regeneratePlan`: `if (mounted) setState(...)`
- All text editing controllers (`_titleCtrl`, `_extraTopicsCtrl`) are properly disposed in `dispose()`.

---

## 9. 400 / 429 / Network / Provider Error UX

Errors from `ApiService.generateExamRescuePlan` are caught and mapped using `AiErrorBanner`:
- **HTTP 429 (Quota Exceeded)**:
  `"Daily AI plan generation limit reached. Please try again tomorrow or upgrade your plan."` / `"আজকের এআই প্ল্যান তৈরির সীমা শেষ। আগামীকাল চেষ্টা করুন।"`
- **HTTP 401 (Unauthorized)**:
  `"Please sign in again to generate your rescue plan."` / `"রেসকিউ প্ল্যান তৈরি করতে পুনরায় সাইন ইন করুন।"`
- **HTTP 400 (Validation / Bad Request)**:
  Displays `e.message` if available, or fallback `"Failed to generate plan. Please try again."`
- **Network / SocketException**:
  `"An unexpected error occurred. Please check your network and try again."` / `"একটি অপ্রত্যাশিত ত্রুটি ঘটেছে। নেটওয়ার্ক চেক করে আবার চেষ্টা করুন।"`
- **Provider Names**: No technical model names or internal provider errors are leaked to the student.

---

## 10. ExamRescuePreviewScreen Implementation

Located in `flutter_app/lib/features/study/presentation/rescue/exam_rescue_preview_screen.dart`:
- Stateful widget initialized with `ExamRescuePlan` and original parameters.
- Screen contains:
  - Top `AppBar` with `"Exam Rescue"` overline and `"Rescue Plan Preview"` title.
  - Fallback banner (when applicable).
  - Hero statistics card (Exam title, days remaining, daily budget, total estimated hours).
  - Source grounding badge with document chips or general subject indicator.
  - AI Rescue Strategy summary card.
  - Day breakdown cards with item rows and type badges.
  - Bottom action bar with `[ Edit / Back ]` and `[ Regenerate ]`.

---

## 11. sourceMode UI Behavior

- When `sourceMode == 'materials'`:
  - Renders folder icon (`Icons.folder_outlined`) and label: `"Based on your selected materials"` / `"আপনার নির্বাচিত মেটেরিয়াল অনুযায়ী"`.
  - Displays material chips with document names under the header.
  - Individual items with `materialId` display an attachment indicator: `Icons.attach_file_rounded` `"Linked material"` / `"সংযুক্ত মেটেরিয়াল"`.
- When `sourceMode == 'general_subject'`:
  - Renders book icon (`Icons.auto_stories_outlined`) and label: `"General subject-based plan"` / `"সাধারণ বিষয়-ভিত্তিক প্ল্যান"`.
  - No document chips are rendered.

---

## 12. generationMode / Fallback UI Behavior

- When `generationMode == 'fallback'`:
  - Displays a warning container at the top of the preview:
    - Icon: `Icons.info_outline_rounded`
    - Text: `"Quick recovery plan created using Gochano's fallback planner."` / `"গচানোর ব্যাকআপ প্ল্যানার দিয়ে দ্রুত উদ্ধার প্ল্যান তৈরি করা হয়েছে।"`
  - Transparent and honest with the user while maintaining a polished student experience (never displaying raw stack traces or internal provider errors).
- When `generationMode == 'ai'`:
  - The fallback banner is hidden.

---

## 13. Day and Item Rendering

- Grouped by day: `DAY 1`, `DAY 2`, `DAY 3`... with daily theme and target duration (e.g. `120m`).
- Each item row displays:
  - **Type Badge** with distinct color coding:
    - `Study` -> `colors.brand`
    - `Practice` -> `colors.info`
    - `Quiz` -> `colors.ai`
    - `Revision` -> `colors.warning`
  - **Item Title**: Bold typography (`type.body.copyWith(fontWeight: FontWeight.w600)`).
  - **Action Note**: Optional supporting guidance in secondary text.
  - **Linked Material Indicator**: If `item.hasMaterial` is true.
  - **Estimated Time**: Displayed in minutes (e.g. `60m`).
  - **Delete Action**: Close icon button (`tooltip: 'Remove item'`). Tapping immediately removes the item from the day's list and dynamically recalculates total planned hours (e.g. 6h -> 5h).

---

## 14. Regenerate and Back Behavior

- **`[ Edit / Back ]` Button**:
  - Uses `SecondaryButton`.
  - Pops the preview screen, returning the student to `ExamRescueSetupSheet` with their inputs preserved.
- **`[ Regenerate ]` Button**:
  - Uses `PrimaryButton` with busy state (`"Regenerating…"`, `_isRegenerating`).
  - Makes an in-place API request to `ApiService.generateExamRescuePlan` with the initial configuration.
  - On success, updates `_currentPlan` and re-renders the preview.
  - On error, displays a `SnackBar` and restores button state.
- **NO False Apply/Save Button**: The preview explicitly avoids premature "Save" or "Apply" buttons since persistence belongs to Phase T4.

---

## 15. Localization

- Complete bilingual support (English and Bangla) using `GochanoLanguage.text(english, bangla)` and `GochanoLanguage.formatNumber(number)`.
- Verified strings in Bangla:
  - Header: `"এক্সাম রেসকিউ"`
  - Preview title: `"রেসকিউ প্ল্যান প্রিভিউ"`
  - Strategy title: `"এআই রেসকিউ কৌশল"`
  - Action button: `"আবার তৈরি করুন"`
  - Date indicators: `"পরীক্ষা আজকেই (১ দিনের ইমার্জেন্সি রিভিশন)"`, `"১ দিন বাকি (আগামীকাল)"`, `"$number দিন বাকি"`
  - Metric chips: `"$number ঘণ্টা / দিন"`, `"মোট: $number ঘণ্টা"`
  - Material counter: `"$number / ৩টি নির্বাচিত"`

---

## 16. 320dp, Bangla, and 2.0x Text-Scale Verification

- **320dp Narrow Viewport**:
  - Tested on `Size(320, 640)`.
  - Setup sheet and preview screen render without any `RenderFlex` overflow.
  - Long file titles and item names wrap or truncate cleanly.
- **Bangla Localization**:
  - Tested with `GochanoLanguage.current.value = GochanoLocale.bangla`.
  - Verified that Bangla ascenders/descenders render without vertical clipping.
- **2.0x Text Scaling**:
  - Tested with `TextScaler.linear(2.0)`.
  - Form section headers utilize `Flexible` text wrappers to prevent horizontal row overflows.
  - Sticky bottom container ensures action buttons remain visible and tappable.

---

## 17. T3 Widget Tests and Results

**Test File**: `flutter_app/test/exam_rescue_flow_test.dart`<br>
**Execution Command**: `flutter test test/exam_rescue_flow_test.dart`<br>
**Result**: **15 / 15 PASSED**

```
00:00 +0: Phase T3 — Exam Rescue Setup Sheet renders all setup form elements cleanly
00:00 +1: Phase T3 — Exam Rescue Setup Sheet validates empty and short exam title inline
00:01 +2: Phase T3 — Exam Rescue Setup Sheet date chips update remaining days indicator
00:01 +3: Phase T3 — Exam Rescue Setup Sheet daily study time chips update selection
00:01 +4: Phase T3 — Exam Rescue Setup Sheet renders initial materials and allows removing them
00:02 +5: Phase T3 — Exam Rescue Setup Sheet zero materials flow prompts confirmation dialog
00:02 +6: Phase T3 — Exam Rescue Setup Sheet responsive 320dp width renders without overflow
00:02 +7: Phase T3 — Exam Rescue Setup Sheet text scale 2.0x renders without overflow
00:02 +8: Phase T3 — Exam Rescue Preview Screen renders preview header, badges, strategy, and days
00:02 +9: Phase T3 — Exam Rescue Preview Screen general subject plan displays general plan label
00:02 +10: Phase T3 — Exam Rescue Preview Screen fallback mode displays fallback transparency label
00:03 +11: Phase T3 — Exam Rescue Preview Screen in-memory item removal removes item and updates total minutes
00:03 +12: Phase T3 — Exam Rescue Preview Screen responsive 320dp and 2.0x text scale renders without overflow
00:03 +13: Phase T3 — Exam Rescue Preview Screen Bangla mode renders localized titles without overflow
00:03 +14: Phase T3 — Exam Rescue Preview Screen renders Exam Rescue banner on PlanView
00:04 +15: All tests passed!
```

---

## 18. Relevant Regression Tests

1. **Exam Rescue Data Models Test Suite**:
   - Command: `flutter test test/exam_rescue_models_test.dart`
   - Result: **9 / 9 PASSED**
2. **Home Mode Filtering Test Suite**:
   - Command: `flutter test test/home_mode_filtering_test.dart`
   - Result: **9 / 9 PASSED**
3. **Backend AI Exam Rescue Pytest Suite**:
   - Command: `pytest backend/tests/test_ai_exam_rescue.py`
   - Result: **18 / 18 PASSED**

---

## 19. flutter analyze lib/ Result

**Execution Command**: `flutter analyze lib/`<br>
**Result**: **0 issues found** (clean in 16.8s)

```
Analyzing lib...
No issues found! (ran in 16.8s)
```

---

## 20. git diff --check Result

**Execution Command**: `git diff --check`<br>
**Result**: Clean (exit code 0, no trailing whitespaces, no conflict markers)

---

## 21. flutter build apk --debug Result

**Execution Command**: `flutter build apk --debug`<br>
**Result**: **SUCCESS**

```
Running Gradle task 'assembleDebug'...                            441.1s
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

---

## 22. Strict Scope Boundary Confirmation

It is hereby confirmed that in accordance with Phase T3 guardrails:
- **NO** task persistence or assignment creation was added.
- **NO** Firestore `exam_rescue` session documents were created or mutated.
- **NO** Firestore security rules were modified.
- **NO** notifications were scheduled.
- **NO** Today hero cards or active rescue state trackers were integrated.
- **NO** quiz completion integration was added.
- All plan previews and item removals are strictly in-memory.

---

## 23. Final T3 Async & Error Hardening Audit

A comprehensive lifecycle, concurrency, boundary, and error hardening audit was conducted to guarantee resilience before introducing database mutations in Phase T4.

### 1. Double-Tap Prevention (Generate Rescue Plan)
- **Implementation**: Synchronous `if (_isGenerating) return;` guard at the top of `_generatePlan()` combined with `onPressed: _isGenerating ? null : _generatePlan` and `busy: _isGenerating`.
- **Verification**: Tapping "Generate Rescue Plan" twice rapidly calls the generation routine exactly once (`callCount == 1`), keeps the button disabled while in flight, and pushes only one `ExamRescuePreviewScreen`. No duplicate routes or calls occur.
- **Result**: **PASS**

### 2. Dispose-During-Request Safety
- **Implementation**: Immediate `if (!mounted) return;` check following `await generator(...)`, as well as inside `ApiException` and generic catch blocks.
- **Verification**: `ExamRescueSetupSheet` was launched, generation triggered with a pending `Completer`, and the sheet dismissed/popped before resolution. Upon future completion, no `setState` after dispose was called, no `Navigator` calls were made with an unmounted context, and zero exceptions were thrown (`tester.takeException() == null`).
- **Result**: **PASS**

### 3. 429 Quota UX Verification
- **Implementation**: HTTP 429 status code handling in `ExamRescueSetupSheet` maps directly to `Daily AI plan generation limit reached. Please try again tomorrow or upgrade your plan.`
- **Verification**: Injected mock throwing `ApiException('Rate limit exceeded', statusCode: 429)`. Verified that `AiErrorBanner` displays the specific limit message. Generic fallback `"Something went wrong"` was not displayed.
- **Result**: **PASS**

### 4. Network / Offline Error Handling
- **Implementation**: Network failures and timeouts are normalized into dedicated connectivity guidance without leaking provider internals or stack traces.
- **Verification**: Mocked network/timeout `ApiException` displayed clear connection status instructions in `AiErrorBanner`. No live network calls were made in tests.
- **Result**: **PASS**

### 5. Successful End-to-End Flow (Setup -> Generate -> Preview)
- **Verification**: Tested end-to-end user flow: entering subject title `"Advanced Microprocessors"`, selecting materials, tapping `"Generate Rescue Plan"`, transitioning to `ExamRescuePreviewScreen`, and rendering uppercase title (`ADVANCED MICROPROCESSORS`), source mode badge (`Based on your selected materials`), and multi-day schedule items with action notes and type chips.
- **Result**: **PASS**

### 6. Exact Date Boundaries
- **Constraints Aligned with Backend**:
  - `Today` accepted: displays `Exam is today (1-day emergency cram)`.
  - `Today + 14 days` accepted: displays `14 days remaining`.
  - `Today + 15 days` rejected: displays inline error `Exam date cannot be more than 14 days away.`
  - `Past Date` rejected: displays inline error `Exam date cannot be in the past.`
  - Native `showDatePicker` enforces `firstDate: today`, `lastDate: today + 14 days`.
- **Result**: **PASS**

### 7. Material Selection Limits & Deduplication
- **Constraints**: Maximum 3 documents, strict deduplication by ID, dynamic add/remove flow.
- **Verification**:
  - Adding document batch of 4 items: only first 3 accepted (`3 of 3 selected`), 4th rejected.
  - Adding duplicate ID: deduplicated, count unchanged.
  - Button `+ Select Materials` automatically hides when 3 items are selected.
  - Removing an item decrements count to 2, causing `+ Select Materials` button to reappear.
  - Selecting new document fills the 3rd slot and hides button again.
- **Result**: **PASS**

### 8. Regenerate Concurrency Protection
- **Implementation**: Synchronous `if (_isRegenerating) return;` guard and `onPressed: _isRegenerating ? null : _regeneratePlan` on `ExamRescuePreviewScreen`.
- **Verification**: Double-tapping `Regenerate` rapidly invokes the generator function exactly once (`regenCalls == 1`), sets busy state, and atomically replaces the in-memory plan once.
- **Result**: **PASS**

### 9. ApiService Duplication Audit
- **Audit**: Comprehensive inspection of `flutter_app/lib/services/api_service.dart`, commit history, and AST.
- **Finding**: Exactly **ONE** definition of `generateExamRescuePlan` exists (line 1213). No duplicate methods or conflicting signatures exist in the codebase.
- **Result**: **PASS**

### 10. Updated Test Counts
- `flutter_app/test/exam_rescue_flow_test.dart`: **23 / 23 PASSED** (15 base + 8 lifecycle/concurrency hardening tests)
- `flutter_app/test/exam_rescue_models_test.dart`: **9 / 9 PASSED**
- `flutter_app/test/home_mode_filtering_test.dart`: **9 / 9 PASSED**
- `backend/tests/test_ai_exam_rescue.py`: **18 / 18 PASSED**
- **Total Suite Passing**: **59 / 59 PASSED**

### 11. Static Analysis & APK Verification
- `flutter analyze lib/`: **0 issues found** (clean in 15.0s)
- `git diff --check`: **Clean** (exit code 0, no trailing whitespace)
- `flutter build apk --debug`: **SUCCESS**

---

PHASE T3: PASS
