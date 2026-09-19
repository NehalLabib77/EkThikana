# Phase 3A — AI Upgrade Report

## Status
- **Phase**: Phase 3A — AI Upgrade (Infrastructure + Usage Control)
- **Progress**: Completed ✅
- **Last update**: 2026-09-19

## Providers

| Provider | Role | Status |
|---|---|---|
| Groq | Primary | Active |
| Gemini | Fallback | Active |
| OpenRouter | Emergency | Active |

## Models

- **Groq**: `qwen/qwen3.8-27b`
- **Gemini**: `gemini-3.1-flash-lite`
- **OpenRouter**: `qwen/qwen-2.5-72b-instruct:free`

## Fallback

Flow:
```
Groq
 ↓
Gemini
 ↓
OpenRouter
```

Supported error codes & failures:
- `429` (Rate limit / quota exceeded)
- `500` / `502` (Upstream provider errors)
- `503` (Service unavailable / provider config error)
- `504` (Gateway timeout)
- `TimeoutException` / network failures

## Usage Limits

- **Chat**: 20 / day (Daily reset at 00:00 UTC)
- **Note AI**: 5 / month (Monthly reset on 1st of month)
- **Quiz**: 3 / month (Monthly reset on 1st of month)
- **Study Planner**: 1 active plan

## Changes

Backend files:
- `backend/app/core/config.py`: Added OpenRouter settings (`openrouter_api_key`, `openrouter_model`, `openrouter_base_url`), updated Groq/Gemini models to `qwen/qwen3.8-27b` and `gemini-3.1-flash-lite`, and configured feature-based limits (`ai_limit_chat_daily`, `ai_limit_note_monthly`, `ai_limit_quiz_monthly`, `ai_limit_study_plan_active`).
- `backend/app/services/ai_service.py`: Implemented OpenRouter text and multimodal emergency fallback (`_openrouter_generate`, `_openrouter_generate_multimodal`), three-tier provider cascade (`Groq -> Gemini -> OpenRouter`), feature quota management (`_consume_quota` with daily/monthly/active periods), and detailed usage endpoint data provider (`get_ai_usage`).
- `backend/app/routers/ai.py`: Added `GET /api/ai/usage` returning feature-specific used, limit, and remaining counters; added backward-compatible generate helpers (`_call_generate`, `_call_generate_multimodal`).
- `backend/app/routers/account.py`: Updated user account deletion cascade to clean `ai_usage_monthly` and `ai_usage_active` Firestore collections.
- `backend/app/services/ocr/structuring.py`: Fixed prescription structuring prompt to use raw strings avoiding invalid escape sequence warnings.
- `backend/tests/conftest.py`: Added `FakeFirestore` patch for `ai_service.get_firestore` and backward-compatible positional kwargs support for faked generate fixtures.
- `backend/tests/test_ai_provider_fallback.py`: Added comprehensive unit & integration tests covering fallback cascade (Groq 429 -> Gemini, Groq 504 + Gemini 502 -> OpenRouter, all fail -> 502), multimodal fallback cascade, daily chat limit & reset, monthly Note AI & Quiz limits & reset, active Study Plan limit, user isolation, and `GET /api/ai/usage` JSON schema.

Flutter files:
- `flutter_app/lib/services/api_service.dart`: Added `ApiService.getAiUsage()` client method.
- `flutter_app/lib/features/profile/presentation/ai_usage_screen.dart`: Created dedicated AI Usage screen displaying Chat (20/day), Note AI (5/month), Quiz (3/month), and Study Planner (1 active) with progress indicators, status badges, English & Bengali localization, pull-to-refresh, loading state, and error/retry state.
- `flutter_app/lib/features/profile/presentation/profile_screen.dart`: Wired Settings AI usage row to `_showAiUsageSheet` navigating to `AiUsageScreen`, updated label to display remaining chat calls or status.
- `flutter_app/test/ai_usage_screen_test.dart`: Added widget tests for `AiUsageScreen` validating limits, reset times, translations, navigation, and loading/retry states.

Tests:
- `backend/tests/test_ai_provider_fallback.py` (9 tests passing)
- `backend/tests/test_quotas.py` (5 tests passing)
- `backend/tests/test_ai_question.py` (12 tests passing)
- Full backend pytest suite: 523 passed in 16s.
- `flutter_app/test/ai_usage_screen_test.dart` (10 tests passing)
- `flutter_app/test/profile_structure_test.dart` (34 tests passing)
- `flutter analyze`: 0 errors, 0 warnings.

Issues:

### Physical Test Issue: AI Usage screen failed loading

**Symptom**: Profile → AI Usage always showed:
`"Failed to load AI usage. Please check your connection and try again."`

**Root cause**:
1. **Flutter error masking** — `_AiUsageScreenState._fetchUsage()` used a blanket `catch (e)` that discarded the actual exception and always displayed a misleading "connection" error. Whether the real cause was a 401 (not signed in), 403 (non-student role gate from `require_student`), missing `API_BASE_URL` configuration, or a genuine network failure, the user always saw the same generic message. This made physical testing impossible to diagnose.
2. **Incomplete deployment spec** — `render.yaml` was missing Phase 3A environment variables (`OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENROUTER_BASE_URL`, `AI_LIMIT_CHAT_DAILY`, `AI_LIMIT_NOTE_MONTHLY`, `AI_LIMIT_QUIZ_MONTHLY`, `AI_LIMIT_STUDY_PLAN_ACTIVE`). Defaults in `config.py` compensated, but operational visibility was lost.
3. **Missing Firestore security rules** — `ai_usage_monthly` and `ai_usage_active` collections had no explicit deny rules (defaulted to deny by omission, but explicit rules document intent).

**Fix**:
1. `ai_usage_screen.dart`: Replaced blanket `catch (e)` with categorized error handling:
   - Safe `debugPrint` logging (error type + sanitized message, no tokens/keys/user data)
   - `_sanitizeErrorMessage()` strips sensitive data from log output
   - `_categorizeError()` shows specific user-facing messages:
     - 401 → "You are not signed in"
     - 403 → "AI usage is available for student accounts only"
     - Config → "App configuration error"
     - SocketException/Timeout → "Check your connection"
     - Unknown → "Please try again"
2. `render.yaml`: Added Phase 3A env vars (OpenRouter + per-feature limits).
3. `.env.example`: Added Phase 3A env vars for new deployments.
4. `firestore.rules`: Added explicit deny rules for `ai_usage_monthly` and `ai_usage_active`.

**Validation**:
- `flutter analyze`: 0 issues
- `flutter test test/ai_usage_screen_test.dart`: 10 passed (3 new tests for error diagnostics)
- `python -m pytest tests/`: 523 passed
- Backend `GET /api/ai/usage`: returns correct default `0/20, 0/5, 0/3, 0/1` for new users with no Firestore documents

## Changelog

Date: 2026-09-19
Added:
- OpenRouter as tertiary emergency fallback provider with free model `qwen/qwen-2.5-72b-instruct:free`.
- Feature-based AI usage limits with UID-based Firestore tracking:
  - Chat: 20/day (daily reset at 00:00 UTC)
  - Note AI: 5/month (monthly reset on 1st of month)
  - Quiz: 3/month (monthly reset on 1st of month)
  - Study Planner: 1 active plan
- Endpoint `GET /api/ai/usage` returning:
  ```json
  {
    "chat": { "used": 0, "limit": 20, "remaining": 20 },
    "note_ai": { "used": 0, "limit": 5, "remaining": 5 },
    "quiz": { "used": 0, "limit": 3, "remaining": 3 },
    "study_plan": { "used": 0, "limit": 1, "remaining": 1 }
  }
  ```
- Dedicated Flutter `AiUsageScreen` in Profile with progress indicators, status badges, and English & Bengali text.
- Comprehensive automated tests in backend (`test_ai_provider_fallback.py`) and Flutter (`ai_usage_screen_test.dart`).
Fixed:
- Cascade reliability handling 429, 500, 502, 503, 504, and timeouts across Groq, Gemini, and OpenRouter.
- Sensitive data isolation: No API keys, authorization tokens, or prompt bodies logged; logging sanitized to prompt lengths and model names only.
- **Physical test fix**: `AiUsageScreen` error handling replaced blanket catch with categorized diagnostics (401/403/config/network), safe `debugPrint` logging, and explicit Firestore rules for `ai_usage_monthly`/`ai_usage_active`.
- `render.yaml` and `.env.example` updated with Phase 3A env vars.
Files:
- Listed above in Changes section.
