from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
def health():
    return {
        "ok": True,
        "service": "gochano-api",
        "version": "2.0.0",
    }
