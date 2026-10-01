# PHASE AI-FLOAT-1.1 REPORT: ZIKU RIGHT-SIDE PANEL, COMPLETE AI ACTIVITY INVENTORY, SERVER-SIDE COUNTERS & UNLIMITED-MODE VERIFICATION

**Phase**: AI-FLOAT-1.1 (remediation of the AI-FLOAT-1 completion report)
**Working Branch**: `feature/top10-exam-rescue-v1` (HEAD `025b5c2`)
**Date**: October 1, 2026
**Status**: CODE + TESTS COMPLETE — LIVE / DEVICE VERIFICATION PENDING (see §7)

---

## 1. Why this phase exists

The previous AI-FLOAT-1 report (`docs/AI_FLOATING_ASSISTANT_PHASE_REPORT.md`, written
before this phase) did not match the repository or the deployed service. Every
requirement mismatch found during the AI-FLOAT-1.1 audit is listed here with what
actually exists now.

| # | Previous report claim | Audit finding at HEAD / live | Resolution in 1.1 |
|---|---|---|---|
| 1 | "Slide-in **bottom modal** panel" | `ziku_assistant_panel.dart` already shows a **right-edge** dialog (`showGeneralDialog` + `Align(centerRight)` + slide from `Offset(1,0)`); only the wording was wrong | Verified by code + tests; report corrected. Spec §11 compliance fix: `SlideTransition` replaced with `AnimatedBuilder` + `Transform.translate` (same right-slide, no banned motion widget) |
| 2 | "`POST /api/ai/chat` implemented and live" | Endpoint **404 on the live service**; not present at HEAD | Endpoint implemented in `backend/app/routers/ai.py` (auth + role gate + history validation) — needs deploy |
| 3 | "`backend/tests/test_ai_assistant_and_usage.py` — 2/2 passed" | The file **existed but was empty (0 tests)** | Written from scratch: **33 tests, all passing** |
| 4 | "AI usage dashboard shows the full inventory" | Dashboard omitted `quiz_generations`, `assignment_uses`, `study_recommendations`, `commute_guides`; quiz was a single row | Full inventory of all 11 server counters, with **Quiz Generations and Quiz Questions as two distinct cards** |
| 5 | "Activity counters recorded server-side" | `record_ai_activity` / `ai_usage_summary` did not exist anywhere at HEAD | Implemented + wired into every AI success path (§3) |
| 6 | "Unlimited mode (`AI_QUOTA_ENFORCEMENT=false`) verified live" | No `ai_quota_enforcement` setting existed; live config had no such env var | Setting + `render.yaml` declaration added; enforcement ON/OFF proven in tests; **live toggle still needs your Render change** |
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
| C6 | **Unlimited AI mode verified live** (`AI_QUOTA_ENFORCEMENT=false` → no 429, counters still increment) | **VERIFIED IN TESTS**, **PENDING LIVE** (Render env change + redeploy by operator) |
| C7 | Report corrected, suites distinguished, no fabricated numbers | **PASS** (this document) |

Verdict: `PHASE AI-FLOAT-1: PASS` requires **all seven** criteria. C6 is verified
against the test suite but not against the deployed service yet → **provisional
BLOCKED until the live check in §7 completes**.

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

## 7. Live & device verification (required to lift BLOCKED)

### 7.1 Operator actions (Render)

1. Push this branch (`git push origin feature/top10-exam-rescue-v1`) and let Render
   deploy `backend/` (or trigger a manual deploy).
2. In the Render service → Environment, set `AI_QUOTA_ENFORCEMENT=false`, save,
   wait for redeploy. (`render.yaml` already declares the key with `"true"`, so the
   safe default is unchanged for everyone else.)

### 7.2 Automated checks run by the agent once the deploy is live

| # | Check | Expected |
|---|---|---|
| L1 | `GET /health` | `{"ok": true, ...}` |
| L2 | `POST /api/ai/chat` with a student token, 1 user turn + 1 assistant turn + 1 follow-up | `200`, `reply` string, `suggested_followups` list |
| L3 | `GET /api/ai/usage` | `quota_enforcement_enabled == false`, `summary.ai_chat_messages` increased by exactly 1 per successful turn |
| L4 | Exhaust a monthly feature quota, call the feature again | `200` (no 429) while `ai_usage_monthly` still increments |
| L5 | Same request from a second account | isolated `summary` (no leakage) |
| L6 | `POST /api/ai/chat` with a driver/non-student token | `403` |
| L7 | UI on device: Profile → AI Usage | "Unlimited AI Mode Active" banner + all 11 inventory cards incl. both quiz rows |

### 7.3 Device checks (Infinix X665E)

| # | Check | Screenshot | Status |
|---|---|---|---|
| D1 | Launcher stack: Ziku above Quick Add | `AI_01_launcher_stack.png` | **PASS** |
| D2 | Panel opens **from the right**, full-height, ~90% width | `AI_02_right_panel_open.png` | **PASS** |
| D3 | Multi-turn reply + dynamic follow-up chip tapped | `AI_03a_chat_reply.png`, `AI_03b_followup_chip.png` | **INVALID — pending redeploy** (see 7.5) |
| D4 | Profile → AI Usage: banner + `Quiz generations` vs `Quiz questions` | `AI_04_usage_inventory.png`, `AI_04b_usage_inventory_scrolled.png`, `AI_04c_usage_inventory_quiz_rows.png` | **PASS** |
| D5 | Launcher hidden on auth screen, present in Utility mode | `AI_05a_utility_launcher.png`, `AI_05b_auth_hidden.png` | **PASS** |

### 7.4 Current live state (measured before the deploy)

- `GET /health` → `{"ok":true,...,"version":"2.0.0"}` (feature-branch lineage:
  `/api/ai/exam-rescue/plan` exists, which `origin/main` does not have).
- `POST /api/ai/chat` → **404** (this phase's endpoint is not deployed yet).
- No `AI_QUOTA_ENFORCEMENT` env var present in the running service.
- Note: all backend changes for this phase are still **local and uncommitted**
  (`HEAD == origin == 025b5c2`), so the running service cannot contain them —
  deploy is impossible until the branch is pushed (§7.1).

### 7.5 Device verification results (2026-10-01, agent-run)

- **D1/D2 PASS** — launcher anchored at `[587,1126][690,1228]` above Quick Add;
  panel opens from the right edge at ~90% width, full height.
- **D4 PASS** — AI Usage shows the limits banner, quota cards (Chat 20/20,
  Note AI 5/5, Quiz Generator 3/3, Study Planner, Assignment Assistant) and the
  11-tile **AI Activity Dashboard** with distinct `Quiz generations` and
  `Quiz questions` tiles plus the explainer footer.
- **D5 PASS** — in Utility mode the Ziku launcher is present above Quick Add on
  the 4-destination Today; on the auth (login) screen no launcher is rendered.
  Study mode restored after the check.
- **D3 INVALID (twice)** — both captures show an empty conversation:
  1. the scripted `adb shell input text "…"` was split on spaces by the device
     shell, so the prompt was never typed (fix: `%s` escapes or shell quoting);
  2. even a correctly typed prompt cannot succeed while live
     `POST /api/ai/chat` returns 404 (§7.4).
  D3 must be re-captured after §7.1 completes.
- Side observations: the AI Usage screen was reachable and rendered correctly
  against the live API (`/api/ai/usage` 401 without token, 200 with session);
  a transient `hasProfile()` false on one Developer Login was resolved by a
  cold restart (read failure path, not a data loss — profile intact).

**Verdict**: `PHASE AI-FLOAT-1: BLOCKED (C6 pending live verification;
D3 pending redeploy)` — everything except the live unlimited-mode check and the
live chat capture is implemented, test-verified, and device-verified.
This section will be updated to `PASS` once §7.1–§7.2 checks succeed.
