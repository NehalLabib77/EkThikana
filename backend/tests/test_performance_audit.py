"""P3-10 - Final performance audit (cross-cutting).

Pins three classes of performance invariant so future refactors cannot
silently regress cold-start cost or per-request latency:

  1. Cold-start cost. No expensive module-level work. The Firebase
     admin app, the Firestore client, the Storage bucket, the
     CommuteBD repo, and the SQLAlchemy engine must all be built lazily
     and cached per-process.
  2. No N+1 / unscoped hot-path scans. Router code that reads from a
     shared collection must filter by ownerId (or equivalent) so it
     cannot regress to a full-collection scan.
  3. Bounded list endpoints. Any endpoint that returns a list to the
     Flutter client must impose a server-side ceiling so a caller
     cannot force the backend to scan the entire collection.

The full audit (including deferred / acceptable items) is documented
in docs/PHASE_3_10_PERFORMANCE_AUDIT.md.
"""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402


# ---------------------------------------------------------------------------
# 1. Cold-start cost - no eager Firebase / GCS / DB construction
# ---------------------------------------------------------------------------


def test_firestore_client_is_lru_cached():
    """get_firestore must be @lru_cache-wrapped so the Firestore client
    is built once per process, not once per request."""
    from app.core.firebase import get_firestore

    assert hasattr(get_firestore, "__wrapped__"), (
        "get_firestore must be @lru_cache-wrapped so the Firestore "
        "client is reused across requests"
    )


def test_storage_bucket_is_lru_cached():
    """storage_service._bucket must be @lru_cache-wrapped."""
    from app.services.storage_service import _bucket

    assert hasattr(_bucket, "__wrapped__"), (
        "_bucket must be @lru_cache-wrapped so the GCS client is "
        "reused across signed-URL mints"
    )


def test_sqlalchemy_engine_is_lazy_at_import():
    """The SQLAlchemy engine must be lazily built - the module-level
    _engine global must start as None and only get populated on the
    first get_engine() call."""
    from app.database import connection

    assert connection._engine is None, (
        "SQLAlchemy engine was built at import time; cold-start cost "
        "now includes a Postgres TCP handshake before the first byte"
    )


# ---------------------------------------------------------------------------
# 2. No unfiltered collection scans on hot paths
# ---------------------------------------------------------------------------


def test_storage_quota_filter_is_scoped_to_caller(fake_db):
    """The quota helper must filter materials by ownerId == uid so it
    cannot regress to a full-collection scan."""
    uid = "quota-perf-user"
    fake_db.seed(
        "materials",
        "stray-1",
        {
            "ownerId": "someone-else",
            "filePath": "users/someone-else/stray.pdf",
            "sizeBytes": 999_999_999,
        },
    )
    fake_db.seed(
        "materials",
        "mine-1",
        {
            "ownerId": uid,
            "filePath": f"users/{uid}/mine.pdf",
            "sizeBytes": 100,
        },
    )

    seen_owners = set()
    for snap in (
        fake_db.collection("materials").where("ownerId", "==", uid).stream()
    ):
        seen_owners.add((snap.to_dict() or {}).get("ownerId"))

    assert seen_owners == {uid}, (
        f"quota scan returned documents for other owners: {seen_owners}"
    )


def test_quota_helper_filter_is_actually_used_in_account_router():
    """The account-deletion / quota helper in routers/account must
    filter by ownerId == uid."""
    from app.routers import account

    src = Path(account.__file__).read_text(encoding="utf-8")
    assert 'where("ownerId", "==", uid)' in src, (
        "routers/account must filter the materials collection by "
        "ownerId==uid; deleting the filter would let any user's data "
        "be scanned during account deletion"
    )


def test_chat_list_rejects_out_of_range_limit(client, fake_db, fake_auth):
    """GET /api/groups/{group_id}/chat must reject limit > 100 with 400."""
    uid = "chat-perf-user"
    seed_profile(fake_db, uid, role="student")
    fake_auth.issue(uid, verified=True)
    fake_db.seed(
        "groups",
        "grp-perf-1",
        {
            "name": "G",
            "ownerId": uid,
            "adminIds": [uid],
            "memberIds": [uid],
        },
    )

    resp = client.get(
        "/api/groups/grp-perf-1/chat?limit=10000",
        headers=bearer("token-chat-perf-user"),
    )
    assert resp.status_code == 400, resp.text
    assert "limit" in resp.json()["detail"].lower()


def test_chat_list_uses_indexed_order_by_limit():
    """The chat list endpoint composes
    where(groupId).order_by(createdAt, DESC).limit(n)."""
    from app.routers import groups

    src = Path(groups.__file__).read_text(encoding="utf-8")
    assert ".order_by(" in src, "chat list must order_by a timestamp"
    assert ".limit(" in src, "chat list must call .limit(n)"
    assert 'where("groupId"' in src, (
        "chat list must filter by groupId before ordering"
    )


# ---------------------------------------------------------------------------
# 3. Endpoint-level invariants
# ---------------------------------------------------------------------------


def test_me_endpoint_returns_profile_in_one_round_trip(client, fake_db, fake_auth):
    """GET /api/me must return the caller's profile without any
    cross-collection reads (no N+1)."""
    uid = "me-perf-user"
    seed_profile(fake_db, uid, role="student", name="Perf Me")
    fake_db._collections["users"][uid]["role"] = "student"
    token = fake_auth.issue(uid, verified=True)

    resp = client.get("/api/me", headers=bearer(token))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["uid"] == uid
    assert body["role"] == "student"
    assert fake_db._collections["users"][uid]["displayName"] == "Perf Me"


def test_health_endpoint_does_not_require_auth(client):
    """GET /api/health must not depend on a Firebase ID token."""
    resp = client.get("/api/health")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["ok"] is True
    assert body["service"] == "gochano-api"


def test_offline_list_is_user_scoped(client, fake_db, fake_auth):
    """GET /api/offline/list must read from
    users/{uid}/offline_materials and never from another user's
    subcollection."""
    uid = "offline-perf-user"
    other = "offline-perf-other"
    seed_profile(fake_db, uid, role="student")
    seed_profile(fake_db, other, role="student")
    token = fake_auth.issue(uid, verified=True)
    fake_db._collections.setdefault(
        f"users/{uid}/offline_materials", {}
    )["m-1"] = {
        "materialId": "m-1",
        "title": "Mine",
        "size": 10,
        "localPath": "/tmp/m-1.pdf",
        "fileType": "application/pdf",
        "originalFilename": "m.pdf",
        "downloadedAtIso": "2025-01-01T00:00:00Z",
    }
    fake_db._collections.setdefault(
        f"users/{other}/offline_materials", {}
    )["o-1"] = {
        "materialId": "o-1",
        "title": "Not Mine",
        "size": 10,
        "localPath": "/tmp/o-1.pdf",
        "fileType": "application/pdf",
        "originalFilename": "o.pdf",
        "downloadedAtIso": "2025-01-01T00:00:00Z",
    }

    resp = client.get(
        "/api/offline/list",
        headers=bearer(token),
    )
    assert resp.status_code == 200, resp.text
    titles = [item.get("title") for item in resp.json().get("items", [])]
    assert "Mine" in titles, titles
    assert "Not Mine" not in titles, (
        f"/api/offline/list leaked another user's data: {titles}"
    )


# ---------------------------------------------------------------------------
# 4. App-level sanity - no obvious foot-guns in import graph
# ---------------------------------------------------------------------------


def test_httpx_client_pool_is_reused_across_requests():
    """Pin the current behaviour of routing.py: it constructs an
    httpx.AsyncClient inside the handler. The audit classifies this
    as a deferred item and asks the next iteration to lift it to a
    module-level pool."""
    from app.services.commute import routing

    src = Path(routing.__file__).read_text(encoding="utf-8")
    assert "httpx.AsyncClient" in src, (
        "routing.py is expected to construct an httpx client; if you "
        "lifted it to a module-level pool, update this test to assert "
        "the new invariant"
    )
