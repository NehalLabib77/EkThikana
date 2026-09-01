"""
Shared test harness for Gochano backend tests.

These tests run against the real FastAPI app via ``TestClient``, but every
external dependency (Firebase Admin, Supabase storage, Tesseract OCR,
pdf2image/Pillow) is replaced with an in-memory fake so the tests are
deterministic, hermetic, and free of network calls.

The conftest installs lightweight stand-in modules on ``sys.modules`` **before**
``app.main`` is imported, so the real optional dependencies never need to be
installed in the test environment.
"""

from __future__ import annotations

import sys
import types
from datetime import datetime, timezone
from typing import Any, Callable, Iterable

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# Stub optional third-party modules so app.* imports succeed in any env.
# ---------------------------------------------------------------------------

def _install_stub(
    name: str, *, attrs: dict[str, Any] | None = None, members: list[str] | None = None
) -> None:
    """Insert or augment a module entry on ``sys.modules`` without losing
    attributes the caller set directly beforehand (e.g. ``__path__``)."""
    module = sys.modules.get(name) or types.ModuleType(name)
    for attr, value in (attrs or {}).items():
        setattr(module, attr, value)
    for member in members or []:
        if not hasattr(module, member):
            setattr(module, member, lambda *a, **k: None)
    sys.modules[name] = module


# Supabase — only the symbols our storage service actually touches.
_supabase_pkg = types.ModuleType("supabase")
_supabase_pkg.__path__ = []  # mark as package so `from supabase import create_client` works
_supabase_pkg.create_client = lambda url, key: types.SimpleNamespace(
    storage=types.SimpleNamespace(
        from_=lambda bucket: types.SimpleNamespace(
            upload=lambda path, file, file_options=None: {"path": path},
            create_signed_url=lambda path, ttl, options=None: {
                "signedURL": f"http://fake/{bucket}/{path}?ttl={ttl}"
            },
            download=lambda path: b"%PDF-1.4\n%fake",
            remove=lambda paths: {"removed": list(paths)},
        )
    )
)
# Pre-populate submodules storage_service might import via `from supabase import ...`
for _sub_name in ("_async", "_sync", "lib", "types", "version"):
    _sub = types.ModuleType(f"supabase.{_sub_name}")
    _supabase_pkg.__dict__[_sub_name] = _sub
    sys.modules[f"supabase.{_sub_name}"] = _sub
sys.modules["supabase"] = _supabase_pkg

# Defensive: if pytest auto-imported the real package first, evict it.
for _real_key in [k for k in sys.modules if k == "supabase" or k.startswith("supabase.")]:
    if sys.modules.get(_real_key) is not _supabase_pkg and _real_key not in (
        "supabase",
        "supabase._async",
        "supabase._sync",
        "supabase.lib",
        "supabase.types",
        "supabase.version",
    ):
        sys.modules.pop(_real_key, None)
# Re-pin
sys.modules["supabase"] = _supabase_pkg


# Firebase Admin — import-time stand-ins; fixtures patch runtime behaviour.
_firebase_admin = types.ModuleType("firebase_admin")
_firebase_admin.__path__ = []
_firebase_admin._apps = []
_firebase_admin.initialize_app = lambda *a, **k: object()

_firebase_auth = types.ModuleType("firebase_admin.auth")
_firebase_auth.verify_id_token = lambda *a, **k: {}
_firebase_auth.delete_user = lambda *a, **k: None

_firebase_credentials = types.ModuleType("firebase_admin.credentials")
_firebase_credentials.Certificate = lambda info: info

_firebase_firestore = types.ModuleType("firebase_admin.firestore")
_firebase_firestore.client = lambda: None
_firebase_firestore.SERVER_TIMESTAMP = object()
_firebase_firestore.ServerTimestamp = object
_firebase_firestore.ArrayUnion = lambda values: values
_firebase_firestore.Increment = lambda value: value
_firebase_firestore.transactional = lambda func: func
_firebase_firestore.Query = types.SimpleNamespace(DESCENDING="DESCENDING", ASCENDING="ASCENDING")

_firebase_admin.auth = _firebase_auth
_firebase_admin.credentials = _firebase_credentials
_firebase_admin.firestore = _firebase_firestore

# Firebase Storage — stubbed at import time so storage_service.py can be
# imported in tests. The bucket/Client surface is only used inside the
# production code path, so a minimal namespace is enough.
_firebase_storage = types.ModuleType("firebase_admin.storage")
_firebase_storage.Client = lambda *a, **k: types.SimpleNamespace(
    bucket=lambda name: types.SimpleNamespace(
        blob=lambda path: types.SimpleNamespace(
            upload_from_string=lambda *a, **k: None,
            generate_signed_url=lambda **k: "http://fake/signed",
            download_as_bytes=lambda: b"%PDF-1.4\n%fake",
            delete=lambda: None,
        )
    )
)
_firebase_admin.storage = _firebase_storage

sys.modules["firebase_admin"] = _firebase_admin
sys.modules["firebase_admin.auth"] = _firebase_auth
sys.modules["firebase_admin.credentials"] = _firebase_credentials
sys.modules["firebase_admin.firestore"] = _firebase_firestore
sys.modules["firebase_admin.storage"] = _firebase_storage


# OCR / image helpers — only used by prescription upload route. We patch the
# service functions to deterministic no-ops in the route-level tests; the
# import-only stubs are enough for app.main to load.
_install_stub("pytesseract")
_install_stub(
    "pdf2image",
    attrs={"convert_from_bytes": lambda *a, **k: []},
)

# PIL — use the real Pillow when it is installed, which it is in both the
# Docker image and any normal dev environment. The stub below exists only so
# `app.main` can still be imported somewhere Pillow genuinely is not
# available. Stubbing it unconditionally, as this used to, meant no test could
# ever exercise the real image preprocessing.
try:  # pragma: no cover - exercised by which branch the environment takes
    import PIL  # noqa: F401
    import PIL.Image  # noqa: F401
    import PIL.ImageDraw  # noqa: F401
    import PIL.ImageEnhance  # noqa: F401
    import PIL.ImageFilter  # noqa: F401
    import PIL.ImageOps  # noqa: F401
except Exception:  # pragma: no cover - only on an install without Pillow
    _pil_pkg = types.ModuleType("PIL")
    _pil_pkg.__path__ = []  # mark as package so PIL.Image can live under it
    _pil_pkg.__version__ = "0.0-fake"
    _pil_pkg.isImageFile = lambda *a, **k: False
    sys.modules["PIL"] = _pil_pkg
    _pil_image = types.ModuleType("PIL.Image")
    _pil_image.__version__ = "0.0-fake"
    _pil_image.open = lambda *a, **k: None
    _pil_image.new = lambda *a, **k: None
    sys.modules["PIL.Image"] = _pil_image
    _pil_pkg.Image = _pil_image

    _pil_enhance = types.ModuleType("PIL.ImageEnhance")
    _pil_enhance.Contrast = lambda image: types.SimpleNamespace(
        enhance=lambda factor: image
    )
    sys.modules["PIL.ImageEnhance"] = _pil_enhance
    _pil_pkg.ImageEnhance = _pil_enhance

    _pil_filter = types.ModuleType("PIL.ImageFilter")
    _pil_filter.SHARPEN = object()
    _pil_filter.MedianFilter = lambda size=3: object()
    sys.modules["PIL.ImageFilter"] = _pil_filter
    _pil_pkg.ImageFilter = _pil_filter

    _pil_ops = types.ModuleType("PIL.ImageOps")
    _pil_ops.exif_transpose = lambda image: image
    _pil_ops.grayscale = lambda image: image
    _pil_ops.autocontrast = lambda image, cutoff=0: image
    sys.modules["PIL.ImageOps"] = _pil_ops
    _pil_pkg.ImageOps = _pil_ops


# ---------------------------------------------------------------------------
# In-memory fakes for Firebase Admin + Firebase Auth.
# ---------------------------------------------------------------------------


_MISSING = object()


def _field_matches(data: dict, field: str, op: str, value: Any) -> bool:
    """Evaluate one Firestore filter against one document.

    Faithfulness matters here. This helper previously treated every operator
    other than ``==`` / ``array_contains`` as an unconditional match, so a
    range filter matched *every* document — including documents that do not
    have the field at all.

    Real Firestore does the opposite: **a document that lacks the filtered
    field is not returned by a range filter.** That divergence is exactly how
    the ``/api/budget/remaining`` bug reached production. The endpoint
    range-filtered on ``createdAtIso``, no Gochano client has ever written
    that field, so the live query matched nothing and every student's
    "remaining" showed their full untouched budget — while this fake happily
    returned all the seeded rows and the test passed.
    """
    actual = data.get(field, _MISSING)

    if op == "array_contains":
        return actual is not _MISSING and value in (actual or [])
    if op == "array_contains_any":
        if actual is _MISSING:
            return False
        return any(v in (actual or []) for v in (value or []))
    if op == "==":
        return (None if actual is _MISSING else actual) == value
    if op == "!=":
        return actual is not _MISSING and actual != value
    if op == "in":
        return actual is not _MISSING and actual in (value or [])
    if op == "not-in":
        return actual is not _MISSING and actual not in (value or [])

    if op in {"<", "<=", ">", ">="}:
        # Range filters skip documents missing the field, and skip values that
        # are not order-comparable with the bound.
        if actual is _MISSING or actual is None:
            return False
        try:
            if op == "<":
                return actual < value
            if op == "<=":
                return actual <= value
            if op == ">":
                return actual > value
            return actual >= value
        except TypeError:
            return False

    raise AssertionError(f"FakeFirestore does not implement operator {op!r}")


class _FakeQuery:
    def __init__(self, docs: list, field: str | None = None, op: str | None = None, value: Any = None):
        self._docs = docs
        self._field = field
        self._op = op
        self._value = value

    def where(self, field: str, op: str, value: Any = None):
        matched = [
            doc for doc in self._docs
            if _field_matches(doc["data"] or {}, field, op, value)
        ]
        return _FakeQuery(matched, field, op, value)

    def limit(self, n: int):
        return _FakeQuery(self._docs[:n])

    def order_by(self, field: str, direction=None):
        # direction is ignored — DESCENDING is just reverse-sort on field.
        sorted_docs = sorted(
            self._docs,
            key=lambda d: (d.get("data") or {}).get(field) or "",
            reverse=True,
        )
        return _FakeQuery(sorted_docs)

    def stream(self):
        for doc in self._docs:
            if self._field is not None and self._op is not None:
                if not _field_matches(doc["data"] or {}, self._field, self._op, self._value):
                    continue
            yield doc["snap"]

    def get(self, transaction=None):  # pragma: no cover - transactional path
        return self._docs[0]["snap"] if self._docs else _NoSnap()


class _FakeCollectionGroup(_FakeQuery):
    def __init__(self, group_id: str, db: "FakeFirestore"):
        docs = []
        for bucket_name, bucket in db._collections.items():
            if bucket_name == group_id:
                continue  # collection-group only
            for d in bucket.values():
                # treat any nested key with this id as a hit
                docs.append(d)
        super().__init__(docs)


class _Snap:
    def __init__(self, ref: "_FakeDocRef", data: dict | None):
        self.reference = ref
        self.id = ref.id
        self._data = data or {}

    @property
    def exists(self) -> bool:
        return bool(self._data)

    def to_dict(self) -> dict:
        return dict(self._data)


class _NoSnap(_Snap):
    def __init__(self):
        super().__init__(_FakeDocRef(None, "", {}), {})
        self.exists = False


class _FakeDocRef:
    def __init__(self, db: "FakeFirestore | None", collection: str, doc_id: str, parent_collection: str = ""):
        self._db = db
        self._collection = collection
        self.id = doc_id

    def get(self, transaction=None):
        bucket = self._db._collections.setdefault(self._collection, {}) if self._db else {}
        data = bucket.get(self.id, {})
        return _Snap(self, data)

    def set(self, data: dict, merge: bool = False):
        bucket = self._db._collections.setdefault(self._collection, {})
        if merge and self.id in bucket:
            merged = {**bucket[self.id], **data}
            bucket[self.id] = merged
        else:
            bucket[self.id] = dict(data)
        self._db._record("set", self._collection, self.id)

    def update(self, data: dict):
        bucket = self._db._collections.setdefault(self._collection, {})
        bucket[self.id] = {**bucket.get(self.id, {}), **data}
        self._db._record("update", self._collection, self.id)

    def delete(self):
        bucket = self._db._collections.setdefault(self._collection, {})
        bucket.pop(self.id, None)
        # also drop any subcollections created during this doc's lifetime
        for sub in [k for k in self._db._collections if k.startswith(f"{self._collection}/{self.id}/")]:
            self._db._collections.pop(sub, None)
        self._db._record("delete", self._collection, self.id)

    def collections(self):
        prefix = f"{self._collection}/{self.id}/"
        sub_ids = sorted({k[len(prefix):].split("/", 1)[0] for k in self._db._collections if k.startswith(prefix)})
        for sub_id in sub_ids:
            yield _FakeDocRef(self._db, f"{prefix}{sub_id}", "_", parent_collection=self._collection)

    def collection(self, sub_id: str) -> "_FakeCollection":
        return _FakeCollection(self._db, self, sub_id)


class _FakeCollection:
    def __init__(self, db: "FakeFirestore", parent_ref: "_FakeDocRef | None", name: str):
        if parent_ref is None:
            self._path = name
            self._db = db
        else:
            self._path = f"{parent_ref._collection}/{parent_ref.id}/{name}"
            self._db = db

    def document(self, doc_id: str | None = None) -> _FakeDocRef:
        if doc_id is None:
            from uuid import uuid4

            doc_id = uuid4().hex
        return _FakeDocRef(self._db, self._path, doc_id)

    def add(self, data: dict) -> tuple[_FakeDocRef, datetime]:
        from uuid import uuid4

        doc_id = uuid4().hex
        ref = _FakeDocRef(self._db, self._path, doc_id)
        ref.set(data)
        return ref, datetime.now(timezone.utc)

    def where(self, field: str, op: str = "==", value: Any = None):
        bucket = self._db._collections.setdefault(self._path, {})
        matched = [
            {"snap": _Snap(_FakeDocRef(self._db, self._path, k), v), "data": v}
            for k, v in bucket.items()
            if _field_matches(v, field, op, value)
        ]
        return _FakeQuery(matched, field, op, value)

    def stream(self):
        bucket = self._db._collections.setdefault(self._path, {})
        for k, v in bucket.items():
            yield _Snap(_FakeDocRef(self._db, self._path, k), v)

    def order_by(self, field: str, direction=None):
        bucket = self._db._collections.setdefault(self._path, {})
        sorted_items = sorted(
            bucket.items(),
            key=lambda kv: (kv[1].get(field) or ""),
            reverse=True,
        )
        new_q = _FakeQuery([
            {"snap": _Snap(_FakeDocRef(self._db, self._path, k), v), "data": v}
            for k, v in sorted_items
        ])
        return new_q

    def limit(self, n: int):
        bucket = self._db._collections.setdefault(self._path, {})
        items = list(bucket.items())[:n]
        return _FakeQuery([
            {"snap": _Snap(_FakeDocRef(self._db, self._path, k), v), "data": v}
            for k, v in items
        ])


class FakeFirestore:
    """Minimal Firestore stand-in covering the operations Gochano uses."""

    def __init__(self):
        self._collections: dict[str, dict[str, dict]] = {}
        self.events: list[tuple[str, str, str]] = []

    def _record(self, op: str, collection: str, doc_id: str) -> None:
        self.events.append((op, collection, doc_id))

    def collection(self, name: str) -> _FakeCollection:
        return _FakeCollection(self, None, name)

    def collection_group(self, name: str) -> _FakeCollectionGroup:
        return _FakeCollectionGroup(name, self)

    def transaction(self) -> "FakeTransaction":
        return FakeTransaction(self)

    # Convenience used by tests
    def seed(self, collection: str, doc_id: str, data: dict) -> None:
        self._collections.setdefault(collection, {})[doc_id] = dict(data)


class FakeTransaction:
    def __init__(self, db: FakeFirestore):
        self.db = db

    @staticmethod
    def transactional(func: Callable) -> Callable:
        return func


class FakeAuth:
    """Records delete_user calls; ID-token verification is set per-test."""

    def __init__(self):
        self.deleted: list[str] = []
        self.tokens: dict[str, dict] = {}

    def issue(self, uid: str, *, email: str = "u@example.com", verified: bool = True, email_field: str = "email") -> str:
        token = f"token-{uid}"
        self.tokens[token] = {"uid": uid, "email": email, "email_verified": verified}
        return token

    def verify_id_token(self, token: str, check_revoked: bool = True) -> dict:
        if token not in self.tokens:
            from fastapi import HTTPException

            raise HTTPException(status_code=401, detail="invalid token")
        return dict(self.tokens[token])

    def delete_user(self, uid: str) -> None:
        self.deleted.append(uid)


class FakeSupabaseStorage:
    def __init__(self):
        self.uploads: list[tuple[str, int, str]] = []  # (path, size, content_type)
        self.deletes: list[str] = []
        # Optional per-path byte overrides. Use ``set_bytes(path, data)`` so
        # AI / OCR / image tests can return realistic fixtures (PNGs, scans,
        # multi-page PDFs) instead of the default ``%PDF-1.4\n%fake`` blob.
        self._bytes_by_path: dict[str, bytes] = {}

    def set_bytes(self, path: str, data: bytes) -> None:
        """Seed the fake storage so ``download_bytes(path)`` returns ``data``."""
        self._bytes_by_path[path] = data

    def upload_bytes(self, path: str, data: bytes, content_type: str) -> None:
        self.uploads.append((path, len(data), content_type))
        # Last write wins — keep the in-memory store consistent with uploads.
        self._bytes_by_path[path] = data

    def create_signed_url(self, path: str, ttl: int = 60, download: bool = False) -> str:
        return f"http://fake/{path}?ttl={ttl}&download={int(bool(download))}"

    def download_bytes(self, path: str) -> bytes:
        if path in self._bytes_by_path:
            return self._bytes_by_path[path]
        return b"%PDF-1.4\n%fake"

    def delete_file(self, path: str) -> None:
        self.deletes.append(path)
        self._bytes_by_path.pop(path, None)


# ---------------------------------------------------------------------------
# Pytest fixtures.
# ---------------------------------------------------------------------------


@pytest.fixture()
def fake_db() -> FakeFirestore:
    return FakeFirestore()


@pytest.fixture()
def fake_auth() -> FakeAuth:
    return FakeAuth()


@pytest.fixture()
def fake_storage() -> FakeSupabaseStorage:
    return FakeSupabaseStorage()


@pytest.fixture()
def client(monkeypatch, fake_db, fake_auth, fake_storage, request):
    """
    Replace every external collaborator with fakes, then return a TestClient.
    Tests request this fixture (or override ``request.param`` for custom auth)
    and pass Firebase ID tokens via ``Authorization: Bearer <token>``.
    """
    # --- Firebase ---
    import app.core.firebase as fb_mod
    import app.core.auth as auth_mod
    from app.routers import account as account_router_mod

    monkeypatch.setattr(fb_mod, "_ensure_firebase", lambda: None)
    monkeypatch.setattr(fb_mod, "get_firestore", lambda: fake_db)

    # auth.py imports these names into its own module namespace via
    # ``from app.core.firebase import ...``, so we must patch both the
    # source module *and* the already-bound names inside auth.py.
    monkeypatch.setattr(auth_mod, "_ensure_firebase", lambda: None)
    monkeypatch.setattr(auth_mod, "get_firestore", lambda: fake_db)

    monkeypatch.setattr(auth_mod.auth, "verify_id_token", fake_auth.verify_id_token)
    monkeypatch.setattr(auth_mod.auth, "delete_user", fake_auth.delete_user)

    # The account router imports ``from firebase_admin import auth`` directly,
    # so it has its own bound reference to the firebase_admin.auth module.
    monkeypatch.setattr(account_router_mod.auth, "delete_user", fake_auth.delete_user)

    # --- Storage ---
    import app.services.storage_service as st_mod

    monkeypatch.setattr(st_mod, "upload_bytes", fake_storage.upload_bytes)
    monkeypatch.setattr(st_mod, "create_signed_url", fake_storage.create_signed_url)
    monkeypatch.setattr(st_mod, "download_bytes", fake_storage.download_bytes)
    monkeypatch.setattr(st_mod, "delete_file", fake_storage.delete_file)

    # Routers that did ``from app.services.storage_service import delete_file``
    # or ``create_signed_url`` or ``download_bytes`` have their own module-bound
    # copies that must also be patched.
    import app.routers.account as _acc_router_mod
    import app.routers.materials as _mat_router_mod
    import app.routers.ai as _ai_router_mod
    for _mod in (_acc_router_mod, _mat_router_mod, _ai_router_mod):
        for _name, _fake in (
            ("delete_file", fake_storage.delete_file),
            ("create_signed_url", fake_storage.create_signed_url),
            ("download_bytes", fake_storage.download_bytes),
            ("upload_bytes", fake_storage.upload_bytes),
        ):
            if hasattr(_mod, _name):
                monkeypatch.setattr(_mod, _name, _fake)

    # --- OCR (used by /api/prescriptions/extract) ---
    import app.services.ocr_service as ocr_mod

    def _fake_extraction(data, content_type):
        # An OCR result with no recognition attached, which is exactly what a
        # PDF text layer produces. Tests that care about confidence build
        # their own RecognitionResult instead of relying on this.
        return ocr_mod.Extraction(
            text=f"fake-text-bytes={len(data)}",
            recognition=None,
            source="ocr",
        )

    monkeypatch.setattr(ocr_mod, "extract", _fake_extraction)
    monkeypatch.setattr(
        ocr_mod,
        "extract_text",
        lambda data, content_type: f"fake-text-bytes={len(data)}",
    )
    monkeypatch.setattr(
        ocr_mod,
        "candidate_lines",
        lambda text: ["Paracetamol 500mg", "1+0+1 after meal"],
    )
    # The prescriptions router bound these names at import time via
    # ``from app.services.ocr_service import ...``; patch the router's
    # local references too so tests that exercise the full route stay
    # hermetic even after other tests have already imported the router.
    import app.routers.prescriptions as _rx_mod

    if hasattr(_rx_mod, "extract"):
        monkeypatch.setattr(_rx_mod, "extract", _fake_extraction)
    if hasattr(_rx_mod, "extract_text"):
        monkeypatch.setattr(
            _rx_mod,
            "extract_text",
            lambda data, content_type: f"fake-text-bytes={len(data)}",
        )

    # Tesseract is not installed in CI, and the route now refuses to run
    # without it rather than returning confident-looking nonsense. Report a
    # working engine so these tests exercise the review-only contract they
    # are actually about; `test_ocr_pipeline` covers the refusal itself.
    import app.services.ocr.languages as _lang_mod

    monkeypatch.setattr(
        _lang_mod,
        "status",
        lambda: {
            "available": True,
            "reason": None,
            "tesseractVersion": "5.0.0-test",
            "installedLanguages": ["ben", "eng"],
            "missingRequired": [],
            "missingRecommended": [],
            "language": "eng+ben",
            "bengaliSupported": True,
            "message": "English and Bengali text recognition are both available.",
        },
    )
    if hasattr(_rx_mod, "candidate_lines"):
        monkeypatch.setattr(
            _rx_mod,
            "candidate_lines",
            lambda text: ["Paracetamol 500mg", "1+0+1 after meal"],
        )

    # --- PDF text extraction (used by /api/ai/pdf-question). The real
    # pypdf-backed parser raises on fake bytes; the test fixture returns
    # a stable, deterministic string so AI question tests don't depend on
    # a real PDF corpus. ---
    import app.services.pdf_service as pdf_mod

    def _fake_extract_pdf_text(data, page=None, max_chars=70000):
        # Real PDF text is multi-sentence; mimic that so the route's
        # ``len(text.strip()) < 40`` heuristic doesn't fall through to OCR.
        return (
            f"fake-pdf-text bytes={len(data)} page={page or 'all'} "
            "Photosynthesis is how plants convert sunlight into chemical energy. "
            "This fake PDF text is returned by the test fixture so AI question "
            "tests do not depend on a real PDF corpus."
        )

    monkeypatch.setattr(
        pdf_mod,
        "extract_pdf_text",
        _fake_extract_pdf_text,
    )
    # The router imports it via ``from app.services.pdf_service import
    # extract_pdf_text`` so we must patch the bound copy too.
    import app.routers.ai as _ai_router_pdf_mod

    if hasattr(_ai_router_pdf_mod, "extract_pdf_text"):
        monkeypatch.setattr(
            _ai_router_pdf_mod, "extract_pdf_text", _fake_extract_pdf_text
        )

    # --- AI service: deterministic, no quota side-effects unless we want ---
    import app.services.ai_service as ai_mod

    async def _fake_generate(uid: str, prompt: str) -> str:
        return f"echo({len(prompt)})"

    async def _fake_generate_multimodal(uid: str, parts: list) -> str:
        # Echo back enough to verify the caller shape (which parts were sent,
        # whether inline_data was attached) without leaking to real Gemini.
        text_parts = [p.get("text", "") for p in parts if isinstance(p, dict) and "text" in p]
        inline = [p for p in parts if isinstance(p, dict) and "inline_data" in p]
        return f"multimodal(text_chars={sum(len(t) for t in text_parts)},inline_parts={len(inline)})"

    monkeypatch.setattr(ai_mod, "generate", _fake_generate)
    monkeypatch.setattr(ai_mod, "generate_multimodal", _fake_generate_multimodal)
    # The AI router bound both helpers at import time, so patch those too.
    import app.routers.ai as _ai_router_mod
    if hasattr(_ai_router_mod, "generate"):
        monkeypatch.setattr(_ai_router_mod, "generate", _fake_generate)
    if hasattr(_ai_router_mod, "generate_multimodal"):
        monkeypatch.setattr(_ai_router_mod, "generate_multimodal", _fake_generate_multimodal)

    # Avoid Gemini quota document mutations from polluting the fake db.
    monkeypatch.setattr(ai_mod, "_consume_quota", lambda uid: None)
    from app.routers import materials as mat_router_mod
    from app.routers import account as account_router_mod
    from app.routers import groups as groups_router_mod
    from app.routers import part3 as part3_router_mod

    monkeypatch.setattr(mat_router_mod, "_consume_upload_quota", lambda uid: None)

    # Routers that call ``from app.core.firebase import _ensure_firebase,
    # get_firestore`` need their own module-bound copies patched too — the
    # `from X import Y` form captures the name at import time.
    for _r_mod in (account_router_mod, groups_router_mod, mat_router_mod, part3_router_mod):
        if hasattr(_r_mod, "_ensure_firebase"):
            monkeypatch.setattr(_r_mod, "_ensure_firebase", lambda: None)
        if hasattr(_r_mod, "get_firestore"):
            monkeypatch.setattr(_r_mod, "get_firestore", lambda: fake_db)

    # Service modules also bind `get_firestore` at import time.
    import app.services.permission_service as perm_mod
    if hasattr(perm_mod, "get_firestore"):
        monkeypatch.setattr(perm_mod, "get_firestore", lambda: fake_db)

    # Settings: zero out limits we want to assert against during tests.
    from app.core.config import get_settings

    get_settings.cache_clear()

    # Import app.main AFTER all patches are in place.
    from app.main import app as fastapi_app

    with TestClient(fastapi_app) as c:
        yield c

    get_settings.cache_clear()


# Helpers used across tests --------------------------------------------------


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def seed_profile(db: FakeFirestore, uid: str, *, role: str = "student", name: str = "Test") -> None:
    db.seed(
        "users",
        uid,
        {
            "displayName": name,
            "email": f"{uid}@example.com",
            "role": role,
            "university": "Test University",
            "department": "CSE",
            "semester": "5",
        },
    )
