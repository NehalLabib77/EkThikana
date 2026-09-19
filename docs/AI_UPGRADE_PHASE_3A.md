# Gochano Phase 3A — AI Upgrade (Infrastructure + Usage Control)

## 1. System Architecture & Flow

```
Flutter App
    │
    ▼ (Authenticated HTTPS Request)
FastAPI Router (`/api/ai/...`)
    │
    ├── Quota Check & Atomic Deduction (`_consume_quota(uid, feature)`)
    │       └── Firestore: `ai_usage/{uid}_{YYYYMMDD}`
    │
    ▼
AI Service (`app/services/ai_service.py`)
    │
    ▼ (Primary Provider)
Groq (`qwen/qwen3.8-27b`)
    │
    ├── (On 429 / 500 / 502 / 503 / 504 / timeout)
    ▼ (Secondary Fallback Provider)
Gemini (`gemini-2.5-flash`)
    │
    ├── (On 429 / 500 / 502 / 503 / 504 / timeout)
    ▼ (Tertiary Emergency Fallback)
OpenRouter (`deepseek/deepseek-chat`)
```

---

## 2. Component Audits

### 2.1 Backend AI Components
- **`app/services/ai_service.py`**:
  - Central gateway for LLM calls (`generate`, `generate_multimodal`).
  - Shared connection-pooled HTTP client with keep-alives.
  - Error classification and translation into student-friendly HTTP status and messages.
  - Daily quota gate via Firestore atomic transactional increment.
- **`app/routers/ai.py`**:
  - `POST /api/ai/note`: Note editing, summary, explanation, key topic extraction.
  - `POST /api/ai/commute-guide`: Strict grounding explanation of verified Dhaka transit facts.
  - `POST /api/ai/pdf-question`: PDF text extraction (digital + OCR fallback) + QA.
  - `POST /api/ai/image-question`: Vision multimodal image QA.
  - `GET /api/ai/usage`: Daily usage & quota status endpoint (added in Phase 3A).
- **`app/core/config.py`**:
  - Groq credentials (`GROQ_API_KEY`, `GROQ_MODEL`).
  - Gemini credentials (`GEMINI_API_KEY`, `GEMINI_MODEL`).
  - OpenRouter credentials (`OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENROUTER_BASE_URL`).
  - Daily limits: global `AI_DAILY_LIMIT` and per-feature limits (`AI_DAILY_LIMIT_NOTE`, `AI_DAILY_LIMIT_PDF`, etc.).

### 2.2 Flutter Client Components
- **`services/api_service.dart`**:
  - `aiNote(action, text)`
  - `commuteGuide(facts)`
  - `askPdf(materialId, question, page)`
  - `askImage(materialId, question)`
  - `getAiUsage()`: fetches `/api/ai/usage` for profile and UI usage indicators.
- **`features/study/presentation/ai/ai_assistant_screen.dart`**:
  - Dynamic routing between `note`, `pdf-question`, and `image-question`.
- **`features/profile/presentation/profile_screen.dart`**:
  - Displays remaining AI quota in `_SettingsCard`.
  - Tap opens bottom sheet breakdown with per-feature counters and status bars.

---

## 3. Provider Fallback Reliability Specification

### 3.1 Failure Handling Matrix
| HTTP Status / Exception | Groq Action | Gemini Action | OpenRouter Action |
|---|---|---|---|
| **429 Too Many Requests / Quota Exceeded** | Log warning → Fallback to Gemini | Log warning → Fallback to OpenRouter | Raise 429 Quota Exceeded |
| **500 Internal Server Error** | Log warning → Fallback to Gemini | Log warning → Fallback to OpenRouter | Raise 502 Provider Unavailable |
| **502 Bad Gateway** | Log warning → Fallback to Gemini | Log warning → Fallback to OpenRouter | Raise 502 Provider Unavailable |
| **503 Service Unavailable / Config Error** | Log warning → Fallback to Gemini | Log warning → Fallback to OpenRouter | Raise 503 Service Unavailable |
| **504 Gateway Timeout / TimeoutException** | Log warning → Fallback to Gemini | Log warning → Fallback to OpenRouter | Raise 504 Request Timed Out |
| **400 Bad Request / 413 Payload Too Large** | Fail immediately (Client error) | Fail immediately (Client error) | Fail immediately (Client error) |

---

## 4. Usage Quota Specification

### 4.1 Firestore Schema
Collection: `ai_usage`  
Document ID: `{uid}_{YYYYMMDD}` (UTC)

```json
{
  "uid": "USER_ID",
  "day": "20260919",
  "count": 5,
  "features": {
    "note": 2,
    "pdf_question": 1,
    "image_question": 1,
    "commute_guide": 1,
    "prescription": 0
  },
  "updatedAt": "SERVER_TIMESTAMP"
}
```

### 4.2 Endpoint: `GET /api/ai/usage`
**Auth**: Bearer token (Student role)  
**Response (200 OK)**:
```json
{
  "day": "20260919",
  "total": {
    "used": 5,
    "limit": 30,
    "remaining": 25
  },
  "features": {
    "note": { "used": 2, "limit": 25, "remaining": 23 },
    "pdf_question": { "used": 1, "limit": 15, "remaining": 14 },
    "image_question": { "used": 1, "limit": 10, "remaining": 9 },
    "commute_guide": { "used": 1, "limit": 20, "remaining": 19 },
    "prescription": { "used": 0, "limit": 10, "remaining": 10 }
  }
}
```
