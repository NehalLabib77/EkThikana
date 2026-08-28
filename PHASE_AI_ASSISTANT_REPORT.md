# Phase: AI Assistant UI Rebuild — Report

**Date:** current session
**Branch:** `part5-release-validation`
**Scope:** Flutter — `flutter_app/lib/screens/study/ai_assistant_screen.dart`
**Goal:** Visual / UX redesign of the AI Assistant screen.
**Constraint:** No AI service, Gemini integration, API endpoint, response parser, file-upload API, auth gate, or business logic was modified.

---

## 1. Files changed

| Path | Change |
|------|--------|
| `flutter_app/lib/screens/study/ai_assistant_screen.dart` | Full visual rebuild (same stateful contract). |

No other Flutter file, no Dart package config, no backend module, no AI service, no API endpoint, no auth, no test, no doc was touched.

---

## 2. Logic preservation

The new screen still routes through **exactly the same call sites** the previous screen used:

| Concern | Old code | New code | Status |
|--------|---------|---------|--------|
| Chat completion | `ApiService.aiNote('explain', text)` | `ApiService.aiNote('explain', raw)` | unchanged |
| File picker | `FilePicker.platform.pickFiles(...)` (pre-12 API used in `materials_screen.dart`) | `FilePicker.pickFiles(...)` (12.x static) | Same intent, updated to match the installed package version |
| File question routing | Navigator.push → `MaterialsScreen` | Navigator.push → `MaterialsScreen` | unchanged |
| Auth gate | `AiAssistantScreen()` (no args, auth decided by parent shell) | `const AiAssistantScreen()` (no args) | unchanged |
| Endpoints | `/api/ai/note`, `/api/ai/ocr`, `/api/ai/pdf-question` | Same three endpoints, not re-implemented | unchanged |
| Language toggle | `LanguageToggle` widget in AppBar | Same widget in AppBar | unchanged |
| Theme tokens | `EkColors`/`colorScheme` | Same scheme tokens | unchanged |
| Quick-action targets | `NotesScreen`, `StudyPlanScreen` | Same screens | unchanged |

### One mechanical detail

The installed `file_picker` package is **12.0.0** (see `pubspec.lock`). The old screen and `materials_screen.dart` were calling the pre-12 `FilePicker.platform.pickFiles(...)` form, which is undefined in 12.x. This pre-existed the rebuild and was a project-wide issue (`flutter analyze` shows it as `undefined_getter` in `materials_screen.dart:340` regardless of my work).

For the new file I used the **correct 12.x static API** (`FilePicker.pickFiles(...)` returns `List<PlatformFile>`) plus the correct 12.x way to read metadata:

- `PlatformFile.extension` no longer exists → derive from `file.name` (last segment after `.`).
- `PlatformFile.size` no longer exists → would need `await file.length()`; the new UI shows the extension label in that slot instead, which is a minor visual choice.

Both adjustments are entirely mechanical consequences of the package version already locked. **No business logic, no endpoint, no API surface, and no parsing was added or changed.**

---

## 3. What the new UI looks like

### AppBar
- Title: `AI Assistant` / `AI সহকারী` with subtitle `Your smart helper` / `আপনার স্মার্ট সহায়ক`
- Actions: settings (`Icons.tune`) + the existing `LanguageToggle`

### Empty state (no bubbles yet)
- Light blue greeting card (`#E0F2FE`) with `Hi 👋` + `How can I help you today?` / `হ্যালো 👋` + `আজ আমি আপনাকে কীভাবে সাহায্য করতে পারি?`
- 2×2 grid of `QuickAction` cards: **Summarize / Explain / Generate Image / Analyze Data** (each in `en` + `bn`).

### Chat area
- User bubbles: right-aligned, primary `#0284C7` background, white text, `person_outline` avatar.
- AI bubbles: left-aligned, `surfaceContainerHighest` background, primary-tinted `auto_awesome` avatar.
- Error bubbles: `errorContainer` background, `error_outline` avatar.
- Typing indicator: animated 3-dot pulse inside an AI-style bubble, driven by a `SingleTickerProviderStateMixin` controller.

### File upload preview
- Shows when a file is picked: extension-derived icon (PDF or image), filename, status line (extension / uploading / error).
- Inline clear and ask buttons.

### Bottom-fixed chat input
- Attach (`Icons.attach_file_rounded`), rounded TextField with mic, circular primary send button.
- Disabled state while a message is sending.

### Color tokens
Light mode uses the requested palette:
- background `#F8FAFC`
- greeting card `#E0F2FE`
- primary action `#0284C7`
- ink `#1E293B`
- button / card `#FFFFFF`

Dark mode swaps to `ColorScheme` tokens (`surface`, `surfaceContainerHighest`, `surfaceContainerHigh`, `primaryContainer`, `outlineVariant`, `errorContainer`) while preserving the same primary `#0284C7` brand color.

### Settings bottom sheet
- Search your study content → `UniversalSearchScreen(student: true)`
- Plan my study → `StudyPlanScreen`
- Info note: "Gochano does not generate MCQs or automatic quizzes." (matches the existing product policy shown elsewhere in the app).

---

## 4. Verification

### `flutter analyze` on the new file
```
$ flutter analyze lib/screens/study/ai_assistant_screen.dart
Analyzing ai_assistant_screen.dart...
No issues found! (ran in 2.7s)
```

### `flutter analyze` on the full project
```
15 issues found.
```
- **0 issues** in `ai_assistant_screen.dart`.
- All 15 issues are pre-existing in:
  - `lib/screens/profile/profile_screen.dart` (8 parse errors at line 368 — pre-existing).
  - `lib/screens/life/medicine_screen.dart` (3 info — deprecated `Radio.groupValue`/`onChanged`, parameter named `sum`).
  - `lib/screens/life/medicine_history_screen.dart` (1 info — parameter named `sum`).
  - `lib/screens/study/materials_screen.dart` (1 error — pre-existing `FilePicker.platform` mismatch; 1 info — `BuildContext` across async gaps).

**The rebuild added zero new issues.**

### Pubspec / dependency check
- `file_picker: ^12.0.0` was already a direct dependency and is used in 6 other Flutter files (`materials_screen`, `profile_screen`, `group_chat_screen`, `medicine_ocr_screen`, `note_editor_screen`, `material_upload_screen`).
- No `pubspec.yaml` change needed.

### Single call site check
```
$ grep "AiAssistantScreen(" lib/ -r
flutter_app/lib/screens/home_shell.dart: ...
const AiAssistantScreen()   // no args
```
Constructor signature preserved (`const AiAssistantScreen({super.key})`), so the single existing call site continues to work without modification.

---

## 5. Constraints respected

- ✅ **No AI service / Gemini logic changed** — still calls `ApiService.aiNote('explain', text)`.
- ✅ **No file upload API changed** — still routes to `MaterialsScreen` and uses `FilePicker` for picking.
- ✅ **No API endpoint touched** — `/api/ai/note`, `/api/ai/ocr`, `/api/ai/pdf-question` still served by `backend/app/main.py` (file unchanged in this phase).
- ✅ **No response parser changed** — replies are still pushed verbatim into `_ChatBubble.ai(reply)`.
- ✅ **No auth changed** — `const AiAssistantScreen()` with no args; auth is handled by `home_shell.dart`.
- ✅ **Dark mode supported** — every visible color branches on `Theme.of(context).brightness`.
- ✅ **i18n parity preserved** — every user-facing string is wrapped in `EkLanguage.text(en, bn)`.
- ✅ **Performance** — `ValueListenableBuilder` around the whole tree; `const` widgets used for avatars and tooltips; `ListView` is lazy and shrinks the grid with `shrinkWrap + NeverScrollableScrollPhysics`.
- ✅ **No new dependencies** — `file_picker` was already in the manifest.
- ✅ **Single-file change** — only `ai_assistant_screen.dart` was modified.

---

## 6. Outcome

- `flutter_app/lib/screens/study/ai_assistant_screen.dart` — new design, analyzer-clean.
- `PHASE_AI_ASSISTANT_REPORT.md` (this file) — records the change set and verifier results.
- No other file in the workspace (frontend, backend, docs, tests, scripts, configs) was modified in this phase.