# PHASE AI-FLOAT-1.1 REPORT: ZIKU RIGHT-SIDE PANEL, COMPLETE AI ACTIVITY INVENTORY, SERVER-SIDE COUNTERS & UNLIMITED-MODE VERIFICATION

**Phase**: AI-FLOAT-1.1 (remediation of the AI-FLOAT-1 completion report)
**Working Branch**: `feature/top10-exam-rescue-v1` (HEAD `df0e9c1`, deployed on Render)
**Date**: October 1, 2026
**Status**: **PASS** — code + tests + live + device verification complete (see §7)

---

## 1. Why this phase exists

The previous AI-FLOAT-1 report (`docs/AI_FLOATING_ASSISTANT_PHASE_REPORT.md`, written
before this phase) did not match the repository or the deployed service. Every
requirement mismatch found during the AI-FLOAT-1.1 audit is listed here with what
actually exists now.

| # | Previous report claim | Audit finding at HEAD / live | Resolution in 1.1 |
|---|---|---|---|
| 1 | "Slide-in **bottom modal** panel" | `ziku_assistant_panel.dart` already shows a **right-edge** dialog (`showGeneralDialog` + `Align(centerRight)` + slide from `Offset(1,0)`); only the wording was wrong | Verified by code + tests; report corrected. Spec §11 compliance fix: `SlideTransition` replaced with `AnimatedBuilder` + `Transform.translate` (same right-slide, no banned motion widget) |
| 2 | "`POST /api/ai/chat` implemented and live" | Endpoint **404 on the live service**; not present at HEAD | Endpoint implemented in `backend/app/routers/ai.py` (auth + role gate + history validation); **deployed and live-verified (§7.2 L2)** |
| 3 | "`backend/tests/test_ai_assistant_and_usage.py` — 2/2 passed" | The file **existed but was empty (0 tests)** | Written from scratch: **33 tests, all passing** |
| 4 | "AI usage dashboard shows the full inventory" | Dashboard omitted `quiz_generations`, `assignment_uses`, `study_recommendations`, `commute_guides`; quiz was a single row | Full inventory of all 11 server counters, with **Quiz Generations and Quiz Questions as two distinct cards** |
| 5 | "Activity counters recorded server-side" | `record_ai_activity` / `ai_usage_summary` did not exist at HEAD | Implemented + wired into every AI success path (§3), live counters observed (§7.2 L3) |
| 6 | "Unlimited mode (`AI_QUOTA_ENFORCEMENT=false`) verified live" | No `ai_quota_enforcement` setting existed; live config had no such env var | Setting + `render.yaml` declaration added; enforcement ON/OFF proven in tests; **live toggle set on Render and verified (§7.2 L3/L4)** |
| 7 | "Zero regressions / `git diff --check` clean / `analyze` clean" | Numbers were not reproducible | Re-measured honestly in §5 (with baseline comparison); `git diff --check` noise is pre-existing repo-wide CRLF |
| 8 | "Revision AI" mentioned as an inventory item | Revision AI was **removed** in commit `b258980` | Not shown anywhere; test asserts the dashboard never claims it |

---

## 2. Requirement criteria (AI-FLOAT-1.1)

| ID | Criterion | Result |
|---|---|---|
| C1 | Ziku AI panel **slides in from the RIGHT** (not a bottom sheet) | **PASS** — code + widget/static tests |
| C2 | Floating stack: **Ziku launcher above Quick Add** (`assets/Ziku.png`), same floating region | **PASS** — code + static tests |
| C3 | Launcher present in Study & Utility modes, hidden on auth screens | **PASS** — code (shell gating) + static tests |
| C4 | **Complete AI usage inventory** with distinct `quiz_generations` / `quiz_questions` | **PASS** — screen + tests |
| C5 | **Server-side activity counters** per authenticated user, counters only (never prompt/reply text) | **PASS** — backend tests |
| C6 | **Unlimited AI mode verified live** (`AI_QUOTA_ENFORCEMENT=false` → no 429, counters still increment) | **PASS** — live: `quota_enforcement_enabled=false`, 6 straight `/api/ai/note` calls past the 5/month limit all `200` (no 429), `ai_notes` incremented to 6, banner shown on device (§7.2 L3/L4, §7.5 D4) |
| C7 | Report corrected, suites distinguished, no fabricated numbers | **PASS** (this document) |

Verdict: all seven criteria C1–C7 hold (code + tests + live + device) →
**`PHASE AI-FLOAT-1: PASS`**.

---

## 3. What was implemented

### Backend (Python / FastAPI)

1. **`backend/app/core/config.py`** — `ai_quota_enforcement: bool = True`
   (safe production default; `AI_QUOTA_ENFORCEMENT=false` disables 429 only).
2. **`backend/app/services/ai_service.py`**
   - `quota_enforcement_enabled()`, enforcement-aware `_consume_quota` (counters
     always increment; HTTP 429 only when enforcement is on).
   - `AI_ACTIVITY_TYPES`, `record_ai_activity()` (Firestore transaction,
     keyed by UID, unknown keys/zero/negative counts ignored), `get_ai_activity_summary()`.
   - `get_ai_usage()` now returns `quota_enforcement_enabled` + `summary`.
   - Multi-turn chat: `normalize_chat_messages()` (user/assistant only, order
     preserved, last 10 turns), `build_chat_system_prompt()`,
     `build_followup_suggestions()` (**deterministic — no second AI call**),
     `_groq_chat()` / `_gemini_chat()` / `_openrouter_chat()`, `chat_generate()`
     (GROQ → Gemini → OpenRouter cascade, one `CHAT` quota consumption).
3. **`backend/app/routers/ai.py`**
   - `POST /api/ai/chat` — `require_student`, role-validated history
     (`^(user|assistant)$`, last message must be `user`, ≤20 messages, ≤8000 chars),
     optional material context resolved with permission check, records
     `ai_chat_messages +1` **only on success**.
   - Activity recording: `/note` → `ai_notes`, `/commute-guide` → `commute_guides`,
     `/pdf-question` → `pdf_questions`, `/image-question` → `image_questions`.
4. **`backend/app/routers/ai_study.py`** — `assignment_uses` (explain/breakdown/plan),
   `planner_plans`, `quiz_generations` + `quiz_questions` (usable-question count,
   success only), `exam_rescue_plans` (**AI path only**; deterministic fallback and
   re-applying an existing plan do not count).
5. **`backend/app/services/ai_recommendation_service.py`** — `study_recommendations`
   only on the AI path (cached/no-AI runs do not count).
6. **`backend/app/routers/account.py`** — `ai_usage_summary` added to account deletion.
7. **`backend/render.yaml`** — declares `AI_QUOTA_ENFORCEMENT: "true"` (default unchanged).
8. **`backend/requirements.txt`** — `pytest-asyncio` added (required by the existing
   async AI fallback tests, which could not even be collected before).

**Canonical activity keys** (all surfaced in `GET /api/ai/usage` → `summary`):
`ai_chat_messages`, `ai_notes`, `pdf_questions`, `image_questions`,
`quiz_generations`, `quiz_questions`, `assignment_uses`, `planner_plans`,
`exam_rescue_plans`, `study_recommendations`, `commute_guides`.

**Note AI semantics**: four actions (`summary` / `cleanup` / `explain` / `key_topics`)
each `+1` toward a single `ai_notes` total row.

**Revision AI**: does not exist (removed in `b258980`) — documented, never displayed.

### Flutter

1. **`lib/features/study/presentation/ai/ziku_assistant_panel.dart`** — right-side
   sheet: `showGeneralDialog` → `Align(alignment: Alignment.centerRight)` →
   width `(screenWidth * 0.90).clamp(280, 420)` → entrance slides from
   `Offset(1, 0)` (right edge). Accessibility: `semanticLabel` on every
   `Image.asset`, `tooltip` on the send `IconButton`, no spec §11 motion widgets.
2. **`lib/shared/widgets/ziku_floating_launcher.dart`** — circular `assets/Ziku.png`
   launcher with tooltip + semantic label.
3. **`lib/features/shell/presentation/gochano_shell.dart`** —
   `ZikuFloatingLauncher` stacked **above** `universal_quick_add_fab` inside one
   `Column(mainAxisSize: min, crossAxisAlignment: end)`; gated by the same
   auth/mode rules as the Quick Add FAB (hidden on auth screens, shown in both
   Study and Utility modes).
4. **`lib/features/profile/presentation/ai_usage_screen.dart`**
   - "Unlimited AI Mode Active" banner when `quota_enforcement_enabled == false`.
   - **Full 11-row activity inventory** in two-column cards, including the two
     distinct quiz metrics, plus a caption explaining the difference.
   - All colour literals replaced with `GochanoColors` tokens (design-system audit).
5. **`lib/services/api_service.dart`** — `aiChat()` → `POST /api/ai/chat`.

---

## 4. Verification & test results

### 4.1 Backend (FULL BACKEND SUITE)

```
backend> .venv\Scripts\python.exe -m pytest tests -q
614 passed, 9 failed in 37.92s
```

- **New phase suite** `tests/test_ai_assistant_and_usage.py` — **33 passed**
  (chat auth/role/validation/history order, counter increments on success only,
  no counter on failure, usage screen never writes, summary + quota flag shape,
  privacy: prompt/reply never stored, user isolation, quota ON → 429 at limit,
  quota OFF → no 429 but counters still increment, note/PDF/image/assignment/
  planner counters, quiz generations vs questions incl. partial/failure/unparsed,
  Exam Rescue AI vs fallback, `record_ai_activity` unit contract, account deletion).
- **Quota / exam-rescue / fallback**: `test_quotas.py`, `test_ai_exam_rescue.py`,
  `test_ai_fallback_policy.py`, `test_ai_provider_fallback.py` — all pass.
- **9 failures are pre-existing and unrelated**: `tests/test_ai_attachment.py`
  targets `POST /api/ai/attachment-question`, which does not exist in this
  codebase (404). Reproduced identically on a clean HEAD checkout.
- Note: at HEAD, `test_ai_fallback_policy.py` could not be **collected**
  (imports `_is_retriable`, absent at HEAD) — this phase restores it.

### 4.2 Focused Flutter suites (PHASE-SPECIFIC)

```
flutter test test/ai_floating_assistant_test.dart test/ai_usage_screen_test.dart
00:03 +26: All tests passed!

flutter test test/a11y/accessibility_audit_test.dart
00:00 +9: All tests passed!
```

- Right-side geometry assertions (`Alignment.centerRight`,
  `begin: const Offset(1, 0)`, **no** `Offset(0, 1)` / `bottomCenter`),
  launcher/shell stacking, full 11-counter inventory, distinct quiz metrics,
  "no Revision AI" guard, unlimited-banner key.

### 4.3 FULL FLUTTER SUITE + baseline comparison

```
flutter test   (with this phase's changes)
1173 passed, 92 failed
```

Baseline for comparison = `git stash` of all `flutter_app` changes:

```
baseline      107 failed, and 18 test files could not even be loaded
              (HEAD does not compile: home_screen.dart calls
               ExamRescueSessionService.instance / ExamRescueSession,
               which HEAD's rescue service does not define)
```

- No failure set is attributable to this phase: the four AI-adjacent failures
  found in the first full run were reproduced with `gochano_shell.dart` reverted
  to HEAD (stale expectations: `_isStudent ? 5 : 4`, `Today` label, reminder
  `LateInitializationError`), and the a11y failures were **fixed in this phase**
  (hex literals → tokens, missing tooltips/semantic labels, `SlideTransition`).
- The remaining 92 failures are pre-existing/stale tests in unrelated areas
  (StudentContext, note/task↔material relationships, Material Availability,
  navigation labels) plus `test/dev_auth_test.dart` and `test/focus_session_test.dart`
  which do not compile (`maySendOtp`, missing `focus_view.dart`).

### 4.4 Static analysis

```
flutter analyze lib/features/profile/presentation/ai_usage_screen.dart
             lib/features/study/presentation/ai/ziku_assistant_panel.dart
             lib/shared/widgets/ziku_floating_launcher.dart
             lib/features/study/presentation/ai/material_picker_sheet.dart
No issues found!

flutter analyze   (whole project)
14 issues — all in test files, all present before this phase:
  4x dev_auth_test.dart (undefined_getter maySendOtp)
  1x focus_session_test.dart (missing focus_view.dart)
  9x warnings in exam_rescue / home_mode_filtering tests
```

### 4.5 Whitespace

```
git diff --check
```
Reports "trailing whitespace" on essentially every added backend line because the
repository stores **CRLF** line endings and has no `.gitattributes` — this is a
repo-wide, pre-existing condition (a `git stash` of this phase's Flutter changes
emitted 721 identical warnings). A CR-insensitive scan of every file touched by
this phase found **one** trailing-whitespace line, `backend/app/routers/ai_study.py:138`,
which is pre-existing and outside this phase's hunks.

---

## 5. Security & redaction

- No passwords, tokens, API keys, or personal data are hardcoded or committed.
- Usage analytics store **counters only** — a backend test asserts that neither
  the student's question nor Ziku's reply appears anywhere in
  `ai_usage_summary/{uid}`.
- Chat history is replayed only to the LLM provider; it is never logged or persisted
  server-side.
- Live verification commands will use the operator's Render dashboard values; no
  secrets appear in this report.

---

## 6. Test-command reference

```bash
# Backend (FULL)
cd backend && .venv\Scripts\python.exe -m pytest tests -q

# Backend (phase-focused)
cd backend && .venv\Scripts\python.exe -m pytest tests/test_ai_assistant_and_usage.py tests/test_quotas.py tests/test_ai_exam_rescue.py -q

# Flutter (phase-focused)
cd flutter_app && flutter test test/ai_floating_assistant_test.dart test/ai_usage_screen_test.dart test/a11y/accessibility_audit_test.dart

# Flutter (FULL)
cd flutter_app && flutter test

# Analysis
cd flutter_app && flutter analyze
```

---

## 7. Live & device verification

### 7.1 Operator actions (Render) — COMPLETED

1. ✅ Branch pushed (`df0e9c1`) and Render deployed `backend/` — live service now
   serves 67 openapi paths including `POST /api/ai/chat` (was 66 + 404).
2. ✅ `AI_QUOTA_ENFORCEMENT=false` set on the Render service (operator action;
   env var unchanged by the agent).

### 7.2 Automated checks run against the deployed service (2026-10-01)

| # | Check | Expected | Result |
|---|---|---|---|
| L1 | `GET /health` | `{"ok": true, ...}` | **PASS** — `200 {"ok":true,...,"version":"2.0.0"}` |
| L2 | `POST /api/ai/chat` with a student token, 1 user turn + 1 assistant turn + 1 follow-up | `200`, `reply` string, `suggested_followups` list | **PASS** — turn 1 `200` (reply 1769 chars + 3 follow-ups); turn 2 `200` with context-aware reply referencing the earlier turns |
| L3 | `GET /api/ai/usage` | `quota_enforcement_enabled == false`, `summary.ai_chat_messages` increased by exactly 1 per successful turn | **PASS** — flag `false`; chat counter `0 → 2` after the 2 curl turns (later `4` after 2 device turns — exactly +1/successful turn) |
| L4 | Exhaust a monthly feature quota, call the feature again | `200` (no 429) while counters still increment | **PASS** — 6 consecutive `POST /api/ai/note` calls against the 5/month limit: all `200` (zero 429s), `ai_notes = 6`, `note_ai 6/5` on the usage screen |
| L5 | Same request from a second account | isolated `summary` (no leakage) | **NOT EXECUTED** — no second account credentials available in this session; isolation is enforced by the tested `record_ai_activity(uid=...)` keying + covered by the suite's user-isolation test (`test_ai_assistant_and_usage.py`) |
| L6 | `POST /api/ai/chat` with a driver/non-student token | `403` | **NOT EXECUTED** — no non-student account credentials available; the `require_student` role gate is covered by suite tests (403 on non-student role) |
| L7 | UI on device: Profile → AI Usage | "Unlimited AI Mode Active" banner + all 11 inventory cards incl. both quiz rows | **PASS** — banner + FREE badge + all 11 counters visible on device (`AI_04*`, see §7.5) |

### 7.3 Device checks (Infinix X665E)

| # | Check | Screenshot | Status |
|---|---|---|---|
| D1 | Launcher stack: Ziku above Quick Add | `AI_01_launcher_stack.png` | **PASS** |
| D2 | Panel opens **from the right**, full-height, ~90% width | `AI_02_right_panel_open.png` | **PASS** |
| D3 | Multi-turn reply + dynamic follow-up chip tapped | `AI_03a_chat_reply.png`, `AI_03b_followup_chip.png` | **PASS** (recaptured post-deploy — see 7.5) |
| D4 | Profile → AI Usage: banner + `Quiz generations` vs `Quiz questions` | `AI_04_usage_inventory.png`, `AI_04b_usage_inventory_scrolled.png`, `AI_04c_usage_inventory_quiz_rows.png` | **PASS** |
| D5 | Launcher hidden on auth screen, present in Utility mode | `AI_05a_utility_launcher.png`, `AI_05b_auth_hidden.png` | **PASS** |

### 7.4 Current live state (measured after the deploy)

- `GET /health` → `{"ok":true,...,"version":"2.0.0"}`; openapi serves **67 paths**
  (old 66 + `POST /api/ai/chat`) — route mounting confirmed.
- `POST /api/ai/chat` → **200** with real LLM replies (single-turn and multi-turn).
- `GET /api/ai/usage` → `quota_enforcement_enabled: false`, `summary` with live
  counters (`ai_chat_messages: 4`, `ai_notes: 6`).
- `AI_QUOTA_ENFORCEMENT=false` present in the running service (banner + no-429
  behaviour both confirm it).

### 7.5 Device verification results (2026-10-01, agent-run)

- **D1 PASS** — launcher anchored at `[587,1126][690,1228]` above Quick Add.
- **D2 PASS** — panel opens from the right edge at ~90% width, full height.
- **D3 PASS (recaptured post-deploy, 17:46–17:56)** —
  `AI_03a_chat_reply.png`: Ziku replies to "explain total internal reflection"
  (key conditions + analogy + optical-fiber example) with the dynamic follow-up
  chip rendered below; `AI_03b_followup_chip.png`: the chip was tapped → violet
  user bubble "Explain ... more simply" → context-aware reply 2 ("Think of it
  like a perfect mirror..." numbered points) → a newly regenerated turn-2 chip.
  Fixes applied vs the two invalid attempts: `%s` space-escaping for
  `input text`, keyboard dismissed before tapping `Send message`, and chat now
  deployed live.
- **D4 PASS (recaptured post-deploy, 18:05)** — `AI_04_usage_inventory.png`
  shows the **"Unlimited AI Mode Active" FREE banner** ("Quota enforcement is
  temporarily disabled...") + limits cards (Chat 16/20, Note AI −1/5 — over
  limit yet still served, Quiz 3/3, Study Planner);
  `AI_04c_usage_inventory_quiz_rows.png` shows the 11-counter activity grid with
  **live values: Chat messages 4, Note AI 6**, distinct `Quiz generations` /
  `Quiz questions` rows and both footnotes.
- **D5 PASS** — in Utility mode the Ziku launcher is present above Quick Add;
  on the auth (login) screen no launcher is rendered. Study mode restored after
  the check (device ends on Today with launcher visible).
- Side observations: a transient `hasProfile()` false on one Developer Login was
  resolved by a cold restart (read failure path, not data loss — profile intact).
  Cosmetic nit (not a criterion): chat replies render raw `**bold**` markdown
  markers as literal text.

### 7.6 Checks not executed (documented, not counted against criteria)

- **L5 (second-account isolation)** and **L6 (non-student 403)** were not run
  live: this session has no second account and no non-student credentials.
  Both behaviours are enforced and covered by the backend suite
  (`test_ai_assistant_and_usage.py`: user-isolation test; `require_student`
  role-gate 403 tests). Neither is required by criteria C1–C7.

---

**Verdict**: `PHASE AI-FLOAT-1: PASS` — all seven criteria (C1–C7) hold against
the code, the test suites, the deployed service (L1–L4, L7), and the physical
device (D1–D5). L5/L6 not executed for lack of credentials (§7.6), covered by
tests.

---

## 8. AI-FLOAT-1.2 — FINAL UI POLISH (2026-10-01)

Presentation-only phase. **No** backend architecture change, **no** new
features, **no** quota-logic change (counters, `_consume_quota`,
`AI_QUOTA_ENFORCEMENT` untouched), **no** Ziku navigation/panel-behavior change
(`showGeneralDialog` + right-edge slide untouched).

### 8.1 Fix 1 — Unlimited-mode presentation on Profile → AI Usage

Old live device evidence showed quota-style values while
`quota_enforcement_enabled == false` ("Chat 16/20", "Note AI -1/5",
"Quiz 3/3") — misleading when enforcement is off.

`ai_usage_screen.dart` now branches on a single `unlimited`
(`quota_enforcement_enabled == false`) flag:

| Element | Unenforced (unlimited) | Enforced (quota) |
|---|---|---|
| Banner | "Unlimited AI Mode Active" + FREE (kept) | not shown |
| Header | "AI Features & Usage" / "Track your AI usage…" | "…Limits" / "Track remaining calls…" |
| Cards | actual counts only: `Chat — 16 uses`, `Note AI — 6 uses`, `Quiz Generator — 0 generations`, `Study Planner — 0 active` | original `x/y left` badge, progress bar, reset-date, `N of M remaining` text |
| Negative values | impossible (badge/caption derive from `used`) | original semantics preserved |
| Caption | "Usage is still tracked, but limits are temporarily not enforced." (new, after cards) | not shown |
| Footer | limits footer hidden (`if (!unlimited)`) | original "Limits ensure equal access…" |

Mechanics: `_FeatureUsageCard` → public `AiFeatureUsageCard` with
`unlimited` + `usageLabel`; in unlimited mode the card renders no progress
bar, no reset-date subtitle, no exhaustion (red) styling, badge = caption =
usage count. **Backend counters untouched.**

### 8.2 Fix 2 — Ziku markdown display

New `ziku_markdown_text.dart` (zero dependencies — project has no markdown
package, and none was added): parses exactly three block types (paragraphs,
`- ` bullets, `1.` numbered lists) and inline `**bold**`, renders via
`SelectableText.rich`. No HTML interpretation (tags stay literal — tested).

`ziku_assistant_panel.dart`: assistant replies (`!isUser && !isError`) render
through `ZikuMarkdownText`; **user messages and error text remain plain
`SelectableText`**. Panel geometry/navigation untouched (static tests assert
`centerRight` / `Offset(1, 0)` / no bottom-sheet anchors still hold).

### 8.3 Language-response policy (system prompt only)

`build_chat_system_prompt()` (backend) now carries a language policy —
inferred from the existing conversation, **no second AI call**, multi-turn
context preserved (the single per-request system prompt covers follow-ups):

- Banglish (Bangla in Latin letters) → reply in **Bangla script**; never Banglish.
- Bangla script → primarily Bangla. English → English.
- Mixed → natural Bangla structure, English technical terms kept in English
  (API, Flutter, assignment, quiz, optical fiber, algorithm, exam, PDF, …).
- Never transliterate a Bangla reply into Latin unless the user explicitly
  asks ("Banglish e bolo") — explicit request unlocks Banglish for that reply.
- Plus a formatting line (paragraphs / `**bold**` / simple lists) matching §8.2.

**Deploy note (updated)**: the prompt change is **deployed live on Render**
(commit `d5ec2f6`, pushed to `feature/top10-exam-rescue-v1`, deployed by the
operator) and was verified against the live `POST /api/ai/chat` with an
authenticated student token (2026-10-01). The UI fixes are client-side and
ship with the app build. Quota flag/env untouched.

Live verification results (all HTTP 200):

| # | Input | Expected | Result |
|---|---|---|---|
| T1 | `amar kal exam ase kivabe porbo` (Banglish) | Bangla-script reply | **PASS** — 513 Bangla / 8 Latin chars |
| T2 | `What is total internal reflection?` (English) | English reply | **PASS** — 0 Bangla chars, `**bold**` + numbered list |
| T3 | `আমার optical fiber exam কাল, কীভাবে revise করব?` (mixed) | Bangla structure + English technical terms | **PASS** — 886 Bangla / 446 Latin; "Optical Fiber", "Total Internal Reflection (TIR)", "Numerical Aperture", "critical angle" kept in English |
| T4 | `Banglish e bolo` (explicit ask) | Banglish allowed | **PASS** — full Banglish reply |
| T5 | Multi-turn: TIR Q → optical-fiber follow-up → Banglish follow-up | Context preserved; policy applies to follow-ups | **PASS** — turn 2 context-aware English (3 follow-ups); turn 3 Banglish follow-up answered in Bangla script (1160 Bangla chars) with full history |

A prompt probe additionally confirmed the new rules are live: Ziku reported
being *"instructed to always reply in Bangla script … and never in Banglish"*
(text present only in `d5ec2f6`; the pre-deploy service quoted the old prompt
line instead). One transient `503 AI provider temporarily unavailable`
occurred on T5 turn 3 — a provider hiccup that succeeded on immediate retry,
**not** a deployment failure.

### 8.4 Tests (21 new; all green)

**New backend tests** — `tests/test_ai_assistant_and_usage.py` (7):
Banglish→Bangla-script instruction, Bangla policy, English policy,
mixed-input keeps English technical terms, explicit "Banglish e bolo"
allowed, rules apply to every follow-up, and
`test_language_policy_costs_exactly_one_ai_call_per_request` (exactly one
provider call, prompt carries the policy).

**New Flutter tests** — 14:
`ai_usage_screen_test.dart` (5): caption present, limits footer hidden,
card supports unlimited presentation, widget: unlimited shows `6 uses` with
**no** `-1/5`, no `remaining`, no `left`, no progress bar; widget: quota mode
still shows `4/20 left` + `4 of 20 remaining today` + progress bar + reset
date and never leaks `16 uses`.
`ai_floating_assistant_test.dart` (9): block parsing, single-paragraph
parsing, plain-visible-text has no `**` (markers consumed, `•`/`1.` glyphs
introduced), HTML stays literal, widget: assistant reply renders bold spans
with no visible `**`, widget: single paragraph, static: markdown only in the
`!isUser && !isError` branch + user text plain, static: right-side panel
unchanged, static: Ziku stacked above Quick Add.

**Suites run (all pass):**

```
flutter analyze lib/                                    → No issues found!
flutter test ai_floating_assistant + ai_usage_screen    → 40 passed
flutter test a11y/accessibility_audit_test              → 9 passed
flutter test exam_rescue_active_experience
           + exam_rescue_quiz_integration               → 41 passed
backend pytest test_ai_assistant_and_usage + quotas
           + exam_rescue + fallback_policy              → 99 passed
git diff --check                                        → 40 flags, all CR-at-EOL
                                                         (CRLF repo, pre-existing)
CR-insensitive scan of 7 phase files                    → 0 genuine trailing
                                                         whitespace lines
```

### 8.5 Device checks (Infinix X665E, debug build w/ dart-defines)

Verification method: screenshots captured to `docs/device_smoke_artifacts/`;
on-device content cross-verified by uiautomator text/desc extraction and
pixel probes (the session's image re-viewer served stale frames, so dumps +
color probes are the evidence of record).

| # | Check | Evidence | Status |
|---|---|---|---|
| P1 | Profile → AI Usage in unlimited mode: banner + usage counts, **no** `-1/5` / `left` / `remaining` | `AI_04_usage_inventory.png` (amber banner present: 468 banner-hued px in rows 200–400), `AI_04b/04c` scrolled views, `AI_04d_unlimited_caption.png` (caption read visually: "Usage is still tracked, but limits are temporarily not enforced."). UI dump: `Unlimited AI Mode Active \| FREE`, `AI Features & Usage`, `Chat \| 6 uses \| 6 uses`, `Note AI \| 6 uses \| 6 uses`, `Quiz Generator \| 0 generations`, `Study Planner \| 0 active` — zero occurrences of `remaining`, `left`, or any `-N/M` | **PASS** |
| P2 | Ziku replies render formatted: numbered list with bold headings, **no visible `**`** | `AI_06_ziku_markdown.png` (reply-only, 4 violet px) + `AI_06b_ziku_markdown_context.png` (user bubble present, 931 violet px). UI dump: user message plain, reply = intro + `1. Condition for Occurrence` / `2. Critical Angle` / `3. Complete Reflection` items; **`**` count in the entire UI tree = 0** | **PASS** |

Panel/launcher regression: panel still opens right-anchored and closes via
its Close button; device ends on Today with the Ziku launcher visible
(restored after checks). Right-side geometry, launcher-above-Quick-Add, and
all AI-FLOAT-1 suites re-run green (§8.4) — behavior unchanged.

---

**AI-FLOAT FINAL UI POLISH: PASS**
