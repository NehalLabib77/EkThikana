import base64
import json
from functools import lru_cache

import firebase_admin
from firebase_admin import credentials, firestore

from app.core.config import get_settings


def _ensure_firebase():
    if firebase_admin._apps:
        return

    settings = get_settings()
    if not settings.firebase_service_account_b64:
        raise RuntimeError("FIREBASE_SERVICE_ACCOUNT_B64 is not configured")

    raw = base64.b64decode(settings.firebase_service_account_b64).decode("utf-8")
    info = json.loads(raw)
    cred = credentials.Certificate(info)

    options = {}
    if settings.firebase_project_id:
        options["projectId"] = settings.firebase_project_id
    # No storage bucket is attached: Gochano's private files live in
    # Backblaze B2 (see ``app.services.storage_service``). Firebase is used
    # here only for Authentication, Firestore and FCM.

    firebase_admin.initialize_app(cred, options=options or None)


@lru_cache
def get_firestore():
    _ensure_firebase()
    return firestore.client()
