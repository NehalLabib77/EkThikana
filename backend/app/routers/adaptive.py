"""Phase 9 - student-only, read-only adaptive learning surfaces."""

from fastapi import APIRouter, Depends

from app.core.auth import CurrentUser, require_student
from app.services import ziku_adaptive_service as adaptive

router = APIRouter()


@router.get("/revision-queue")
def revision_queue(user: CurrentUser = Depends(require_student)):
    return adaptive.get_revision_queue(user.uid)


@router.get("/curriculum")
def curriculum(user: CurrentUser = Depends(require_student)):
    return adaptive.get_curriculum(user.uid)


@router.get("/textbook")
async def textbook(user: CurrentUser = Depends(require_student)):
    return await adaptive.get_textbook(user.uid)


@router.get("/difficulty")
def difficulty(user: CurrentUser = Depends(require_student)):
    return adaptive.get_difficulty(user.uid)


@router.get("/learning-path")
def learning_path(user: CurrentUser = Depends(require_student)):
    return adaptive.get_learning_path(user.uid)