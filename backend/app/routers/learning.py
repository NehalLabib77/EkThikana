"""Phase 10.5 - student learning memory reads."""

from fastapi import APIRouter, Depends

from app.core.auth import CurrentUser, require_student
from app.services import content_recommendation_service as recommendations
from app.services import learning_memory_service as memory

router = APIRouter()


@router.get("/memory")
def learning_memory(user: CurrentUser = Depends(require_student)):
    return memory.build_memory(user.uid)


@router.get("/recommendations")
def learning_recommendations(user: CurrentUser = Depends(require_student)):
    return recommendations.get_recommendations(user.uid)


@router.get("/progress")
def learning_progress(user: CurrentUser = Depends(require_student)):
    return memory.get_progress(user.uid)


@router.get("/content-effectiveness")
def content_effectiveness(user: CurrentUser = Depends(require_student)):
    return memory.get_content_effectiveness(user.uid)