from fastapi import APIRouter, Depends

from app.core.auth import CurrentUser, get_current_user

router = APIRouter()


@router.get("/me")
def me(user: CurrentUser = Depends(get_current_user)):
    return {
        "uid": user.uid,
        "email": user.email,
        "role": user.role,
        "displayName": user.display_name,
    }
