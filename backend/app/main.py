from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.routers import account, ai, groups, health, materials, me, prescriptions, reports, study

app = FastAPI(
    title="EkThikana API",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

settings = get_settings()
origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, prefix="/api", tags=["Health"])
app.include_router(me.router, prefix="/api", tags=["Account"])
app.include_router(groups.router, prefix="/api/groups", tags=["Groups"])
app.include_router(materials.router, prefix="/api/materials", tags=["Materials"])
app.include_router(ai.router, prefix="/api/ai", tags=["AI"])
app.include_router(prescriptions.router, prefix="/api/prescriptions", tags=["Prescriptions"])
app.include_router(study.router, prefix="/api/study", tags=["Study"])
app.include_router(reports.router, prefix="/api/reports", tags=["Moderation"])
app.include_router(account.router, prefix="/api", tags=["Account"])
