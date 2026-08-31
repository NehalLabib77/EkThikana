"""P1-5 — DELETE /api/account also wipes Postgres-mirrored per-user rows.

Contract pinned by these tests:

  1. The route invokes the Postgres cleanup helper with the deleted
     user's UID so the owner's community fare reports are wiped from
     the Postgres mirror.
  2. The cleanup failure (e.g. Postgres unreachable) does NOT block
     account deletion — the route must still delete auth + Firestore
     records and return 200. Otherwise a transient DB outage would
     leave stale Auth users and orphan Firestore data.
"""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


def test_account_delete_wipes_postgres_fare_reports(client, fake_db, fake_auth, monkeypatch):
    """The account-delete contract explicitly cleans the Postgres
    mirror so community-submitted fare reports don't outlive their
    owner after a §29 delete. The helper is monkeypatched to a recording
    spy — this pins the invocation without needing a live Postgres.
    """
    import app.routers.account as account_mod

    called: list[tuple[str, ...]] = []

    def _spy(uid: str) -> int:
        called.append((uid,))
        return 3  # pretend we wiped three rows

    monkeypatch.setattr(account_mod, "delete_fare_reports_for_user", _spy)

    uid = "p15-deleter"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.delete("/api/account", headers=_auth(fake_auth, uid))

    assert resp.status_code in (200, 204), resp.text
    assert uid in fake_auth.deleted, "Firebase auth user must be deleted"
    assert called == [(uid,)], (
        "delete_account must call delete_fare_reports_for_user(uid); "
        f"saw calls: {called}"
    )


def test_account_delete_survives_postgres_cleanup_failure(client, fake_db, fake_auth, monkeypatch):
    """If Postgres is unreachable, account deletion must still finish
    auth + Firestore cleanup so the user is never stranded with a half-
    deleted identity.
    """
    import app.routers.account as account_mod

    def _boom(uid: str) -> int:
        raise RuntimeError("postgres down")

    monkeypatch.setattr(account_mod, "delete_fare_reports_for_user", _boom)

    uid = "p15-resilient"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed("notes", "n1", {"ownerId": uid, "title": "hello"})

    resp = client.delete("/api/account", headers=_auth(fake_auth, uid))

    assert resp.status_code in (200, 204), resp.text
    assert uid in fake_auth.deleted, (
        "Firebase auth user must be deleted even if Postgres cleanup fails"
    )
    assert uid not in fake_db._collections.get("users", {}), (
        "Firestore profile must be removed even if Postgres cleanup fails"
    )
    assert "n1" not in fake_db._collections.get("notes", {}), (
        "Owned notes must be removed even if Postgres cleanup fails"
    )
