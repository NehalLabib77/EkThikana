import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.core.latency import latency_middleware, router as latency_router
from app.database.connection import describe_active_database
from app.routers import account, ai, commute, groups, health, materials, me, part3, prescriptions, reports, study

logger = logging.getLogger("gochano")

app = FastAPI(
    title="Gochano API",
    version="1.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

settings = get_settings()
origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
# P4-1: record per-endpoint latency. Middleware runs *outside* the CORS
# middleware so the elapsed time reflects the actual route handler work
# rather than the CORS preflight round-trip.
app.middleware("http")(latency_middleware)


def _log_startup_banner() -> None:
    """Log a single summary line describing the active backend surfaces.

    P0-1 / P0-2 deliverable: makes it impossible to silently boot against the
    wrong database / storage / AI surface. Legacy ``supabase_*`` bindings are
    still honoured for backwards compatibility but logged as warnings so the
    operator knows they are inert.
    """
    storage = settings.firebase_storage_bucket.strip() or "<UNSET>"
    ai_model = settings.gemini_model.strip() or "<UNSET>"
    db = describe_active_database()
    legacy_supabase = bool(
        settings.supabase_url.strip() or settings.supabase_service_role_key.strip()
    )
    logger.info(
        "Gochano API starting | env=%s | db=%s | storage_bucket=%s | ai_model=%s"
        " | legacy_supabase=%s",
        settings.app_env,
        db,
        storage,
        ai_model,
        legacy_supabase,
    )
    if legacy_supabase:
        logger.warning(
            "Legacy Supabase env bindings (supabase_url / supabase_service_role_key)"
            " are still present. They are inert in Phase 2 — the active storage"
            " surface is Firebase Storage. Remove them on the next operator"
            " rotation if no historical code path needs them."
        )


_log_startup_banner()


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Always return JSON instead of Starlette's plain-text 500 body.

    The full exception still goes to Render logs. Flutter receives a stable
    message and no longer crashes while trying to jsonDecode("Internal Server Error").
    """
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    detail = "Internal server error"
    if settings.app_env.lower() != "production":
        detail = f"{type(exc).__name__}: {exc}"
    return JSONResponse(status_code=500, content={"detail": detail})


app.include_router(health.router, prefix="/api", tags=["Health"])
app.include_router(latency_router, tags=["Internal"])
app.include_router(me.router, prefix="/api", tags=["Account"])
app.include_router(groups.router, prefix="/api/groups", tags=["Groups"])
app.include_router(materials.router, prefix="/api/materials", tags=["Materials"])
app.include_router(ai.router, prefix="/api/ai", tags=["AI"])
app.include_router(prescriptions.router, prefix="/api/prescriptions", tags=["Prescriptions"])
app.include_router(study.router, prefix="/api/study", tags=["Study"])
app.include_router(part3.router, prefix="/api", tags=["PART3"])
app.include_router(reports.router, prefix="/api/reports", tags=["Moderation"])
app.include_router(account.router, prefix="/api", tags=["Account"])
app.include_router(commute.router, prefix="/api/commute", tags=["CommuteBD"])
