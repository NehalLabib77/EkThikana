# CommuteBD backend update

This backend now adds a Supabase-backed CommuteBD read path without changing the completed dataset/import pipeline.

## Added
- `app/services/commute/supabase_repository.py`
- `app/services/commute/service.py`
- `tests/test_commute_supabase.py`

## Extended
- `app/routers/commute.py`
- `app/services/commute/fare_engine.py` (repository injection; legacy behavior remains the default)
- `app/services/commute/crowd.py`
- `app/services/storage_service.py`
- `app/core/config.py`
- `app/schemas.py`
- `tests/conftest.py` (hermetic dependency stubs)

## New API endpoints
- `GET /api/commute/data-status` (public health/data check)
- `GET /api/commute/places/search?q=...` (Firebase-authenticated)
- `GET /api/commute/nearby-stops?lat=...&lng=...&radius_m=...` (Firebase-authenticated)
- `POST /api/commute/routes` (Firebase-authenticated)

Existing `/api/commute/search`, `/api/commute/route`, and `/api/commute/fare-report` remain available.

## Runtime data source
The new endpoints read the imported CommuteBD tables from Supabase/PostgreSQL. The bundled CSV repository remains only as legacy behavior for the old endpoints and as the explicitly low-confidence synthetic rickshaw fallback.

## Supabase URL handling
The backend accepts either a full Supabase URL or a bare project ref in `SUPABASE_URL` and normalizes it server-side.

## Validation
`pytest -q` passed: **23 tests passed** in the build environment.

## Deployment
Keep real secrets only in Render/local environment variables. This ZIP intentionally excludes `.env` and `.venv`.
