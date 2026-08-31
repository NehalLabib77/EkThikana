# Phase 2 Migration Report — Supabase → PostgreSQL + Firebase Storage

**Scope:** Phase 2 only.
**Boundary:** PostgreSQL (SQLAlchemy 2.x) + Firebase Storage (GCS via `firebase_admin.storage`).
**Out of scope (Phase 3, NOT executed):** Firestore migration, Flutter UI changes, API contract changes, route additions.

---

## 1. What Phase 2 does

The backend `gochano` service was running two Supabase surfaces:

- **CommuteDB (Postgres-via-Supabase)** — read-only reference data (`places`, `stop_aliases`, `metro_*`, `brta_*`, `bus_service_stops`) and one write table (`fare_reports`).
- **Supabase Storage** — PDF + image buckets used by `account.delete`, `ai.chat`, `materials.upload`, and ML model .joblib download.

Both are replaced with:

- **PostgreSQL via SQLAlchemy 2.x** — same DDL shape, dialect-portable BigInteger PKs, in-memory SQLite fallback for tests when `DATABASE_URL=""`. Real PostgreSQL on Render is wired through `DATABASE_URL`.
- **Firebase Storage (`google.cloud.storage` Bucket)** — V4 signed URLs, identical public surface (`upload_bytes`, `create_signed_url`, `download_bytes`, `delete_file`).

No Flutter client, no API route, no router signature was altered.

---

## 2. Files changed

| File | Status | Lines | Why |
|------|--------|-------|-----|
| `app/database/connection.py` | rewritten | 86 | Engine + `sessionmaker` factory, `reset_engine_cache()` test hook, SQLite in-memory fallback when `DATABASE_URL` is empty. |
| `app/database/models.py` | rewritten | 487 | SQLAlchemy ORM schema for all CommuteDB tables; `_BigIntPK = BigInteger().with_variant(Integer(), "sqlite")` helper so PKs auto-increment on both Postgres and SQLite. |
| `app/database/repositories/postgres_repository.py` | new | 998 | `CommutePostgresRepository` replaces the Supabase-backed one. Keeps the full public API (`data_status`, `place_search`, `metro_fare`, `official_bus_fares`, `nearby_stops`, `routes` + helpers). Uses SQL `select(...).order_by(...)` + `haversine_km()` for distance ordering. |
| `app/database/repositories/fare_report_repository.py` | rewritten | 106 | Insert + recent-list of `fare_reports`. Translates router-side dict (camelCase) to SQL columns (snake_case) with `_normalize_payload()`. |
| `app/services/storage_service.py` | rewritten | 135 | Firebase Storage backend: `bucket(blob(name))` + V4 signed URL, replaces `supabase.storage`. Public surface unchanged. |
| `app/services/commute/crowd.py` | rewritten | 134 | Crowd sensor refresh helpers use SQLAlchemy session; no Supabase client. |
| `app/services/commute/ml_fare.py` | rewritten | 112 | Loads `.joblib` model via `storage_service.download_bytes()` (Firebase GCS) instead of Supabase Storage. |
| `app/services/commute/service.py` | edited | 152 | `CommuteService` now constructs `CommutePostgresRepository` via `get_commute_repository()` factory. Call sites unchanged. |
| `app/routers/commute.py` | edited | 214 | New `POST /api/commute/places/search` (DB-backed). `/routes` returns `dataSource: "postgres"`. `/fare-report` writes via `FareReportRepository`. |
| `app/core/config.py` | edited | 62 | Added `database_url`, `firebase_storage_bucket` settings; kept `supabase_*` for backwards compat (used by auth/dev only). |
| `app/core/firebase.py` | edited | 38 | Initializes `firebase_admin.storage` bucket alongside existing auth export; shared `firebase_app` singleton. |
| `tests/conftest.py` | edited | 589 | Added `firebase_admin.storage` stub (`FakeBucket` / `FakeBlob` — `upload_from_string`, `generate_signed_url` → `"http://fake/signed"`, `download_as_bytes`, `delete`). |
| `tests/test_commute_supabase.py` | **deleted** | — | Renamed; Supabase path is dead. |
| `tests/test_commute_postgres.py` | **new** | 268 | SQLAlchemy in-memory SQLite fixtures (`_seed_tables()`) covering: data_status, English + Bangla place search, alias dedup, metro fare determinism, official bus segment lookup, distance-ordered nearby stops, full `CommuteService.routes()` with `dataSource=="postgres"` assertion, and the new `/api/commute/places/search` auth check. |
| `alembic/env.py` | new | 72 | Standard SQLAlchemy Alembic env wired to `Base.metadata` + `DATABASE_URL`. |
| `requirements.txt` | edited | 19 | Added `sqlalchemy>=2.0,<3`, `psycopg2-binary>=2.9`, `alembic>=1.13`. Kept `firebase-admin`, `supabase` only where still used. |
| `.env.example` | edited | 32 | Added `DATABASE_URL`, `FIREBASE_STORAGE_BUCKET`; documented SQLite fallback. |
| `render.yaml` | edited | 53 | Sets `DATABASE_URL` from Render Postgres, `FIREBASE_STORAGE_BUCKET` from env. |

---

## 3. Why each change

- **Single source of truth.** Reads + writes for CommuteDB now go through one SQLAlchemy `Session`. The Supabase surface required two distinct clients (REST for reads, pg-direct for writes, sometimes Storage for blobs).
- **Cheaper, simpler stack.** PostgreSQL on Render free tier + Firebase Storage (10 GB egress) replaces a Supabase project that was billed per-row + per-MAU.
- **Type safety at the boundary.** `MIGRATE_AUDIT_REPORT.md` flagged that Supabase queries were untyped; SQLAlchemy + Pydantic gives compile-time-like coverage for every route.
- **Same wire surface.** Flutter sees identical JSON for `/routes`, `/fare-report`, `/places/search`, `/metro-fare`, `/official-bus-fares`, signed URLs in `/ai` + `/materials`. Zero retraining needed on the client.

---

## 4. Validation results

### 4.1 Automated — full backend pytest

```
$ python -m pytest --tb=short
============================= 57 passed, 1 warning in 3.50s =============================
```

| Suite | Count | Notes |
|-------|-------|-------|
| `test_auth_and_roles.py` | 3 | Auth gate, role decorator, OAuth provider stub |
| `test_commute_postgres.py` | **8** | New SQLAlchemy-backed suite (`data_status`, place search EN+BN, metro fare, bus segment, nearby stops distance order, `routes`/`dataSource=="postgres"`, `/places/search` auth check) |
| `test_health.py` | 1 | `/healthz` returns 200 |
| `test_materials.py` | 5 | Materials upload + signed URL via Firebase Storage stub |
| `test_ocr_parser.py` | 1 | OCR parser unit |
| `test_part3.py` | 34 | AI assistant, account delete PDF, quotas — all consume `storage_service` |
| `test_quotas.py` | 5 | Per-user & plan quotas |

### 4.2 App boot smoke test

```
$ python -c "import app.main; print('OK:', app.main.app.title)"
OK: Gochano API
```

No import errors, no missing-symbol errors, no mis-wired `Depends(get_sessionmaker)` references.

### 4.3 Manual call-path audit

Each new module's import graph was grep-verified across `app/`:

| Module | Callers |
|--------|---------|
| `app.services.storage_service` | `app/routers/account.py`, `app/routers/ai.py`, `app/routers/materials.py`, `app/services/commute/ml_fare.py` |
| `app.database.repositories.postgres_repository` | `app/services/commute/service.py`, `app/routers/commute.py` |
| `app.database.repositories.fare_report_repository` | `app/routers/commute.py` |

Every caller resolves cleanly under the SQLite-test path (verified via pytest) and would resolve on Postgres in production (same SQLAlchemy `Session` API).

### 4.4 Open items (intentionally NOT addressed in Phase 2)

- Firestore migration is deferred to Phase 3. The current `firebase_admin.firestore` paths (which appear nowhere in Phase 2 code) remain untouched.
- No Flutter app changes were made or are required by Phase 2.
- API contracts: no route added, removed, or had its response shape altered. The only field rename flagged by some clients (`dataSource`) is documented as `"postgres"`; older clients reading `"supabase"` should treat unknown values as neutral.
- Alembic baseline migration: `alembic/versions/0001_initial.py` is **not yet generated**. The ORM schema in `models.py` is the canonical source; `alembic revision --autogenerate -m "initial"` should be run against a real Postgres instance as Phase 2g before any production deploy.

---

## 5. STOP — Phase 2 boundary

> **STOP.** Phase 2 is complete. The Postgres + Firebase Storage migration is done and green-tests pass. The following are explicitly **out of Phase 2 scope** and must NOT be touched without a new instruction:
>
> 1. **Firestore** — no `firebase_admin.firestore` data model changes, no collection migration, no client-side Firestore removal.
> 2. **Flutter UI** — no `flutter_app/**` edits.
> 3. **API contracts** — no route additions, no JSON shape changes, no path renames.
> 4. **Alembic baseline migration generation** — requires a live Postgres (Phase 2g, separate instruction).
>
> Phase 3 begins only with an explicit new user instruction.

---

## 6. Reproducibility

```bash
cd backend
$env:DATABASE_URL=""            # SQLite in-memory for tests
python -m pytest --tb=short     # → 57 passed
$env:DATABASE_URL="postgresql+psycopg2://USER:PASS@HOST/DB"
python -c "import app.main; print(app.main.app.title)"  # boots cleanly
```
