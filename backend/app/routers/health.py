from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
def health():
    return {
        "ok": True,
        "service": "ekthikana-api",
        "version": "1.0.0",
    }
