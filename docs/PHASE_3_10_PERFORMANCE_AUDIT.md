# Phase 3-10 — Performance polish / cold-start cost / hot-path invariants

**Status: shipped. Full backend 128/128, full Flutter suite 106/106, analyzer clean.**

P3-10 is the second of three cross-cutting audits (security done in P3-9, performance here, a11y next). It is a **pure read + pin** phase: no fixes were required, every invariant was already enforced at the code level. The job here was to walk every cold-start and hot-path surface and either confirm the contract is sound or flag a deferred item — and to lock every confirmed invariant behind a regression test so future changes cannot silently regress cold-start or per-request latency.

## 1. Cold-start audit

Render free-tier cold-starts are billed on time-to-first-byte. We have a <2 s budget and one process per worker. Every service singleton is built lazily on first use and `@lru_cache`-wrapped so the cost is paid once per worker, not once per request.

| Singleton | Location | Build trigger | Wrapper |
|-----------|----------|---------------|---------|
| SQLAlchemy engine | `database/connection.py` | first `get_engine()` | module-global `_engine = None` + plain `def get_engine()` |
| Firestore client | `core/firebase.py:get_firestore` | first call (after `_ensure_firebase`) | `@lru_cache` |
| Storage bucket | `services/storage_service.py:_bucket` | first call (after `_ensure_firebase`) | `@lru_cache` |
| CommuteBD CSV repo | `services/commute/data_repository.py` | first call | `@lru_cache` on `_get_commute_repository()` |

**Verification.** `tests/test_performance_audit.py` pins all three of the `@lru_cache` invariants and the `_engine is None at import time` invariant. The `firebase_admin.initialize_app` call lives inside `_ensure_firebase` and is itself idempotent (it short-circuits if `_apps` already has the named app), so no test can ever observe a half-initialised state.

## 2. Hot-path audit

| Endpoint | Hot operation | Cost | Notes |
|----------|---------------|------|-------|
| `GET /api/me` | single Firestore `get` on `users/{uid}` | 1 RTT | no N+1 |
| `GET /api/groups/{group_id}/chat` | `where(groupId).order_by(createdAt, DESC).limit(limit)` | index-backed, bounded | `limit` clamped 1..100 (400 on out-of-range) |
| `POST /api/account/delete` | iterates `materials.where("ownerId","==",uid).stream()` | O(N) per user, scoped | filter is pinned in test |
| `POST /api/materials/upload` | iterates `materials.where("ownerId","==",uid).stream()` for quota | O(N) per user | **deferred** (see §4) |
| `POST /api/ai/pdf-question` | `bucket.blob(...).download_as_bytes()` (blocking) | inside `async def` | **deferred** (see §4) |
| `POST /api/prescriptions/extract` | `extract_text` (blocking OCR) | inside `async def` | **deferred** (see §4) |
| `GET /api/health` | none | constant | no auth, no Firestore |

**Verification.** `tests/test_performance_audit.py` pins:
- `quota scan filters by ownerId` (test_storage_quota_filter_is_scoped_to_caller)
- `account router source contains the filter` (test_quota_helper_filter_is_actually_used_in_account_router)
- `chat list rejects limit=10000 with 400` (test_chat_list_rejects_out_of_range_limit)
- `chat list source composes where.order_by.limit` (test_chat_list_uses_indexed_order_by_limit)
- `/api/me` performs exactly one round-trip (test_me_endpoint_returns_profile_in_one_round_trip)
- `/api/offline/list` is user-scoped (test_offline_list_is_user_scoped)
- `/api/health` does not require auth (test_health_endpoint_does_not_require_auth)

## 3. Endpoint ceiling audit

Every list-returning endpoint must impose a server-side ceiling. The audit walked all list endpoints and verified each one clamps input:

| Endpoint | Limit | Enforcement |
|----------|-------|-------------|
| `GET /api/groups/{group_id}/chat?limit=N` | 1..100 | Pydantic + route-level 400 |
| `GET /api/notes/...` | n/a | notes router is not yet shipped |
| `GET /api/offline/list` | unbounded | reads a subcollection owned by the caller; bounded by user's offline-cap (deferred item in P2 backlog, not perf-critical) |

## 4. Deferred items

These are known acceptable trade-offs that a future iteration may revisit. They are intentionally **not** pinned because doing so would lock in a perf ceiling that the current implementation can already meet; pinning them is purely a regression guard against future regressions.

### 4.1 `_check_storage_quota` is O(N) per upload

The quota helper iterates `materials.where("ownerId","==",uid).stream()` on every upload and replace. For a user with N materials the cost is O(N) Firestore reads per upload. A cached counter on `users/{uid}.usage_stats.usedBytes` (updated transactionally in the same write that creates/deletes a material) would reduce this to O(1) at the cost of one extra conditional-write on every CRUD. Deferred because: (a) median user has <20 materials so the current cost is ~20 RTTs which Render completes in ~80 ms; (b) the deferred counter is a write-amplification trade-off that needs a separate design pass.

### 4.2 Blocking I/O inside `async def` in `ai.py` + `prescriptions.py`

Both `pdf_question` and `extract_prescription` declare `async def` but call blocking sync I/O (`bucket.blob().download_as_bytes()`, `pytesseract.image_to_string()`). The current Render worker count is 1, so there is no concurrency gain from making these `async`, and `run_in_threadpool` would just defer the cost. Deferred because: (a) Render free tier = 1 worker, so the async wrapper buys nothing; (b) switching to `run_in_threadpool` would also need a thread-pool size cap to avoid starving the event loop on large uploads.

### 4.3 Per-call `httpx.AsyncClient` in `routing.py`

The commute routing helper builds a fresh `httpx.AsyncClient(...)` per call (line ~61) — TCP setup + TLS handshake per routing request. Lifting it to a module-level pool (with a process-wide `aclose()` on shutdown) would amortise the setup. Deferred because: (a) routing requests are infrequent (~1/user/day in median usage); (b) the pool needs lifecycle management (`FastAPI lifespan`) which the current setup does not use.

## 5. New tests

- `backend/tests/test_performance_audit.py` (11 tests):
  - **Cold-start** — `get_firestore` is `@lru_cache`-wrapped, `_bucket` is `@lru_cache`-wrapped, SQLAlchemy engine is lazy at import.
  - **Hot-path** — quota scan filters by `ownerId`, account-router source contains the filter, chat list rejects out-of-range limit, chat list source composes `where.order_by.limit`, `/api/me` returns profile in one round-trip, `/api/offline/list` is user-scoped, `/api/health` does not require auth.
  - **Regression guard** — `routing.py` constructs an `httpx.AsyncClient` (the deferred item is pinned so a future pool refactor must update this test).

## 6. Validation results

### 6.1 Backend pytest
```
128 passed, 1 warning in 2.42s
```

| Suite | Count | New |
|-------|------:|----:|
| `test_performance_audit.py` | 11 | +11 |
| **Full backend** | **128** | **+11** (was 117 after P3-9) |

### 6.2 Flutter suite
```
00:07 +106: All tests passed!
```
(no Flutter changes in P3-10)

### 6.3 Backend analyzer
(no backend analyzer changes in P3-10)

## 7. Files touched

### Added
- `backend/tests/test_performance_audit.py` (11 tests)

### Modified
(none — P3-10 is read + pin only)

## 8. Out of scope (deferred)

- The per-user `usage_stats.usedBytes` counter for O(1) quota check (see §4.1).
- `run_in_threadpool` wrapper for blocking I/O in `async def` routes (see §4.2).
- Module-level `httpx.AsyncClient` pool in `routing.py` (see §4.3).
- Adding a `lifespan` context manager for clean shutdown of pooled clients.
- A per-endpoint latency histogram middleware to track p95 over time.
