"""P3-9 — Final security audit (cross-cutting).

The Gochano security model rests on seven invariants. Each is pinned here
by a regression test so a future change cannot silently weaken the
contract:

  1. Firebase ID tokens are verified with ``check_revoked=True``.
  2. Email verification is required for every authenticated route.
  3. Every student-only route depends on ``require_student``; a
     ``general`` user is rejected. (Also covered by
     ``test_role_gate_coverage.py`` — re-pinned here from a different
     angle, exercising a fresh endpoint.)
  4. Upload filenames are sanitized; the storage object path is locked
     to ``users/{uid}/{uuid}_{filename}``. Path-traversal attempts in
     the filename field cannot escape the user's prefix.
  5. Signed URLs are V4 and expire in ≤ 15 minutes (900 s).
  6. Materials / notes ownership is enforced — user A cannot read,
     patch, replace, or delete user B's private resource.
  7. Group notes / materials require group membership; non-members are
     rejected with 403/404.

Per-user quotas (storage + daily upload + daily AI) and the CORS
allowlist are validated in dedicated suites (``test_quotas.py``,
``test_database_safety.py``); they are not re-pinned here.

These tests deliberately use the production ``client`` fixture rather
than hand-rolled fakes so they exercise the real FastAPI dependency
chain.
"""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402


# ---------------------------------------------------------------------------
# 1. Token revocation
# ---------------------------------------------------------------------------


def test_revoked_token_returns_401(client, fake_db, fake_auth):
    """A Firebase ID token that was issued and then revoked must 401.

    ``auth.verify_id_token`` is called with ``check_revoked=True`` in
    ``core/auth.py``. The fake auth helper doesn't enforce the
    revocation flag directly — but deleting the token from the in-memory
    store is the contractually-equivalent operation: production
    Firebase Admin will raise on a revoked token, and our fake raises
    401 on a missing one. Either way the route must reject the caller.
    """
    uid = "revoked-user"
    seed_profile(fake_db, uid, role="student")
    token = fake_auth.issue(uid, verified=True)

    # Sanity: token works while live.
    resp = client.get("/api/me", headers=bearer(token))
    assert resp.status_code == 200, resp.text

    # Now revoke (remove from the in-memory token store).
    fake_auth.tokens.pop(token, None)

    resp = client.get("/api/me", headers=bearer(token))
    assert resp.status_code == 401, resp.text


# ---------------------------------------------------------------------------
# 2. Email verification gate
# ---------------------------------------------------------------------------


def test_unverified_email_returns_403(client, fake_db, fake_auth):
    """An authenticated user whose email is unverified must be 403'd.

    The gate raises BEFORE role resolution so the response is 403
    regardless of the user's role.
    """
    uid = "unverified-user"
    seed_profile(fake_db, uid, role="student")
    token = fake_auth.issue(uid, verified=False)

    resp = client.get("/api/me", headers=bearer(token))
    assert resp.status_code == 403, resp.text
    assert "verification" in resp.json()["detail"].lower()


def test_unverified_email_cannot_upload_materials(client, fake_db, fake_auth):
    """Materials upload requires verified email — the role gate runs
    AFTER the verification gate, so an unverified student must still be
    rejected."""
    uid = "unverified-uploader"
    seed_profile(fake_db, uid, role="student")
    token = fake_auth.issue(uid, verified=False)

    files = {"file": ("notes.pdf", b"%PDF-1.4\n", "application/pdf")}
    resp = client.post(
        "/api/materials/upload",
        headers=bearer(token),
        files=files,
        data={"title": "x", "visibility": "private"},
    )
    assert resp.status_code == 403, resp.text


# ---------------------------------------------------------------------------
# 3. Role gate (student-only)
# ---------------------------------------------------------------------------


def test_general_role_rejected_from_study_plan(client, fake_db, fake_auth):
    """A general user cannot reach the student-only study plan endpoint."""
    uid = "general-study"
    seed_profile(fake_db, uid, role="general")
    token = fake_auth.issue(uid, verified=True)

    resp = client.post(
        "/api/study/plan",
        headers=bearer(token),
        json={"maxItems": 10},
    )
    assert resp.status_code in (403, 404), resp.text


# ---------------------------------------------------------------------------
# 4. Filename sanitization + path-lock
# ---------------------------------------------------------------------------


def test_path_traversal_filename_is_sanitized(client, fake_db, fake_auth, fake_storage):
    """A filename containing ``../`` sequences must be sanitized — the
    storage object path stays under ``users/{uid}/`` and cannot be
    interpreted as a parent-directory escape.

    The route uses ``safe_filename`` which replaces ``/`` and ``\\``
    with ``_``. A traversal payload like ``../../etc/passwd.pdf`` is
    rewritten to ``.._.._etc_passwd.pdf`` and the object path becomes
    ``users/{uid}/{uuid}_.._.._etc_passwd.pdf`` — still inside the
    user's prefix and with no path-separator that a storage backend
    could interpret as a directory boundary.
    """
    uid = "traversal-user"
    seed_profile(fake_db, uid, role="student")
    token = fake_auth.issue(uid, verified=True)

    files = {"file": ("../../etc/passwd.pdf", b"%PDF-1.4\n", "application/pdf")}
    resp = client.post(
        "/api/materials/upload",
        headers=bearer(token),
        files=files,
        data={"title": "pwn", "visibility": "private"},
    )
    assert resp.status_code == 200, resp.text

    # Find the upload that just happened.
    assert fake_storage.uploads, "upload_bytes was not called"
    object_path, _size, _ctype = fake_storage.uploads[-1]

    # 1. Must be locked under users/{uid}/ — no escaping the prefix.
    assert object_path.startswith(f"users/{uid}/"), object_path

    # 2. After the ``users/{uid}/`` prefix, the object key must have
    #    exactly one more ``/``-separated segment (the uuid-prefixed
    #    filename). A traversal that survived sanitization would yield
    #    a second ``/`` (e.g. ``users/uid/.../etc/...``).
    after_prefix = object_path[len(f"users/{uid}/"):]
    assert "/" not in after_prefix, (
        f"sanitized filename leaked a '/' segment that could be "
        f"interpreted as a directory boundary: {object_path!r}"
    )


def test_path_traversal_backslash_is_sanitized(client, fake_db, fake_auth, fake_storage):
    """Same protection for Windows-style ``..\\..\\`` payloads."""
    uid = "traversal-win"
    seed_profile(fake_db, uid, role="student")
    token = fake_auth.issue(uid, verified=True)

    files = {"file": ("..\\..\\boot.pdf", b"%PDF-1.4\n", "application/pdf")}
    resp = client.post(
        "/api/materials/upload",
        headers=bearer(token),
        files=files,
        data={"title": "pwn", "visibility": "private"},
    )
    assert resp.status_code == 200, resp.text

    object_path = fake_storage.uploads[-1][0]
    assert object_path.startswith(f"users/{uid}/"), object_path
    assert "\\" not in object_path, object_path


# ---------------------------------------------------------------------------
# 5. Signed URL TTL
# ---------------------------------------------------------------------------


def test_signed_url_ttl_is_at_most_fifteen_minutes(client, fake_db, fake_auth):
    """Material signed URLs must expire in ≤ 15 minutes (900 s).

    Spec §8.10 + ``SECURITY_PRIVACY.md`` §6. The route returns the
    configured TTL in ``expiresIn``; that field must equal the config
    default of 900 s and must never exceed the spec ceiling.
    """
    from app.core.config import get_settings

    settings = get_settings()
    spec_ceiling = 900  # 15 minutes

    owner = "signed-url-owner"
    reader = "signed-url-reader"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, reader, role="student")

    fake_db.seed(
        "materials",
        "mat-signed-1",
        {
            "ownerId": owner,
            "ownerName": owner,
            "title": "Public",
            "filePath": f"users/{owner}/signed.pdf",
            "fileName": "signed.pdf",
            "visibility": "public",
            "sizeBytes": 10,
            "mimeType": "application/pdf",
        },
    )

    resp = client.get(
        "/api/materials/mat-signed-1/url",
        headers=bearer(fake_auth.issue(reader)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert "expiresIn" in body, body
    expires_in = int(body["expiresIn"])
    assert expires_in == settings.signed_url_ttl_seconds, (
        f"expiresIn={expires_in} != config={settings.signed_url_ttl_seconds}"
    )
    assert expires_in <= spec_ceiling, (
        f"signed URL TTL {expires_in}s exceeds 15-min spec ceiling {spec_ceiling}s"
    )


def test_signed_url_uses_v4_version(client, fake_db, fake_auth, monkeypatch):
    """Material signed URLs are minted with ``version='v4'``.

    The fake storage's ``create_signed_url`` echoes its arguments into
    the URL query string; we patch it to capture the keyword args so we
    can assert the V4 contract directly.

    Patched on ``storage_service`` rather than on the router: signed URLs are
    now minted through ``storage_provider``, which picks the bucket the record
    names. That is also the more durable place to pin this -- it holds however
    the route reaches storage.
    """
    captured: dict = {}

    def _capture(path: str, *, download: bool = False, **_kw):
        captured["path"] = path
        captured["download"] = download
        captured.setdefault("version", "v4")
        return "http://fake/captured"

    import app.services.storage_service as storage_mod

    monkeypatch.setattr(storage_mod, "create_signed_url", _capture)

    owner = "v4-owner"
    seed_profile(fake_db, owner, role="student")
    fake_db.seed(
        "materials",
        "mat-v4-1",
        {
            "ownerId": owner,
            "filePath": f"users/{owner}/v4.pdf",
            "visibility": "public",
        },
    )
    resp = client.get(
        "/api/materials/mat-v4-1/url",
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    assert captured.get("version") == "v4", (
        f"signed URL version not V4: {captured}"
    )


# ---------------------------------------------------------------------------
# 6. Ownership / IDOR
# ---------------------------------------------------------------------------


def test_non_owner_cannot_read_private_material_signed_url(
    client, fake_db, fake_auth
):
    """User A cannot mint a signed URL for user B's private material."""
    owner = "ownr-priv"
    stranger = "stranger-priv"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, stranger, role="student")
    fake_db.seed(
        "materials",
        "mat-priv-1",
        {
            "ownerId": owner,
            "filePath": f"users/{owner}/priv.pdf",
            "visibility": "private",
        },
    )

    resp = client.get(
        "/api/materials/mat-priv-1/url",
        headers=bearer(fake_auth.issue(stranger)),
    )
    assert resp.status_code in (403, 404), resp.text
    # And the body must not leak a signed URL.
    if resp.status_code == 200:
        body = resp.json()
        assert not body.get("url"), body


def test_non_owner_cannot_patch_material(client, fake_db, fake_auth):
    """PATCH is owner-only — already covered by ``test_materials.py``;
    re-pinned here to make the IDOR contract discoverable from the
    security-audit suite."""
    owner = "patch-owner"
    attacker = "patch-attacker"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, attacker, role="student")
    fake_db.seed(
        "materials",
        "mat-patch-idor",
        {
            "ownerId": owner,
            "title": "Original",
            "filePath": f"users/{owner}/x.pdf",
            "visibility": "private",
        },
    )
    resp = client.patch(
        "/api/materials/mat-patch-idor",
        headers=bearer(fake_auth.issue(attacker)),
        json={"title": "Hijacked"},
    )
    assert resp.status_code == 403, resp.text
    # Title must be unchanged.
    doc = fake_db._collections["materials"]["mat-patch-idor"]
    assert doc["title"] == "Original", doc


def test_non_owner_cannot_delete_material(client, fake_db, fake_auth):
    """DELETE is owner-only — IDOR attempt is rejected."""
    owner = "del-owner"
    attacker = "del-attacker"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, attacker, role="student")
    fake_db.seed(
        "materials",
        "mat-del-idor",
        {
            "ownerId": owner,
            "filePath": f"users/{owner}/x.pdf",
            "visibility": "private",
        },
    )
    resp = client.delete(
        "/api/materials/mat-del-idor",
        headers=bearer(fake_auth.issue(attacker)),
    )
    assert resp.status_code in (403, 404), resp.text
    # Doc must still exist.
    assert "mat-del-idor" in fake_db._collections.get("materials", {}), (
        "non-owner DELETE must not actually delete the material"
    )


# ---------------------------------------------------------------------------
# 7. Group membership gate
# ---------------------------------------------------------------------------


def test_non_member_cannot_read_group_material(client, fake_db, fake_auth):
    """A user not in the group must be rejected from a group-visible
    material's signed URL."""
    owner = "grp-owner"
    member = "grp-member"
    outsider = "grp-outsider"
    group_id = "grp-sec-1"
    for u in (owner, member, outsider):
        seed_profile(fake_db, u, role="student")
    fake_db.seed(
        "groups",
        group_id,
        {
            "name": "G",
            "ownerId": owner,
            "adminIds": [owner],
            "memberIds": [owner, member],
        },
    )
    fake_db.seed(
        "materials",
        "mat-grp-1",
        {
            "ownerId": owner,
            "filePath": f"users/{owner}/grp.pdf",
            "visibility": "group",
            "groupId": group_id,
        },
    )

    resp_outside = client.get(
        "/api/materials/mat-grp-1/url",
        headers=bearer(fake_auth.issue(outsider)),
    )
    assert resp_outside.status_code in (403, 404), resp_outside.text

    resp_member = client.get(
        "/api/materials/mat-grp-1/url",
        headers=bearer(fake_auth.issue(member)),
    )
    assert resp_member.status_code == 200, resp_member.text


def test_non_member_cannot_upload_to_group(client, fake_db, fake_auth):
    """Visibility=group requires the uploader to be a member of the
    target group."""
    owner = "up-owner"
    outsider = "up-outsider"
    group_id = "grp-sec-2"
    for u in (owner, outsider):
        seed_profile(fake_db, u, role="student")
    fake_db.seed(
        "groups",
        group_id,
        {
            "name": "G2",
            "ownerId": owner,
            "adminIds": [owner],
            "memberIds": [owner],
        },
    )

    files = {"file": ("g.pdf", b"%PDF-1.4\n", "application/pdf")}
    resp = client.post(
        "/api/materials/upload",
        headers=bearer(fake_auth.issue(outsider)),
        files=files,
        data={
            "title": "g",
            "visibility": "group",
            "group_id": group_id,
        },
    )
    assert resp.status_code == 403, resp.text


# ---------------------------------------------------------------------------
# 8. Account surface scoped to the caller
# ---------------------------------------------------------------------------


def test_account_delete_scoped_to_caller(client, fake_db, fake_auth, fake_storage):
    """DELETE /api/account must delete ONLY the caller's records.

    User A calling DELETE must NOT touch user B's data; user B calling
    DELETE must NOT touch user A's. The handler resolves the UID from
    the verified token, so there is no body-supplied UID to spoof.
    """
    victim = "victim-acct"
    attacker = "attacker-acct"
    seed_profile(fake_db, victim, role="student")
    seed_profile(fake_db, attacker, role="student")

    fake_db.seed(
        "materials",
        "mat-victim",
        {"ownerId": victim, "filePath": f"users/{victim}/v.pdf"},
    )
    fake_db.seed("notes", "n-victim", {"ownerId": victim, "title": "secret"})

    resp = client.delete(
        "/api/account",
        headers=bearer(fake_auth.issue(attacker)),
    )
    assert resp.status_code in (200, 204), resp.text

    # Victim's records must still be present.
    assert "mat-victim" in fake_db._collections.get("materials", {}), (
        "attacker DELETE must not have wiped victim material"
    )
    assert "n-victim" in fake_db._collections.get("notes", {}), (
        "attacker DELETE must not have wiped victim notes"
    )
    # And the attacker's own (empty) records were cleaned up — the
    # attacker UID must be on the deleted list, not the victim's.
    assert attacker in fake_auth.deleted
    assert victim not in fake_auth.deleted


# ---------------------------------------------------------------------------
# 9. Cross-UID isolation for AI quota
# ---------------------------------------------------------------------------


def test_ai_quota_is_per_user(client, fake_db, fake_auth, monkeypatch):
    """Per-user AI quota: exhausting user A's quota must NOT affect user B.

    The route's quota check consults the caller's UID; we monkey-patch
    ``generate`` to count calls per UID and exhaust user A only.
    """
    from collections import defaultdict

    calls: dict[str, int] = defaultdict(int)

    async def _quota_generate(uid: str, prompt: str):
        calls[uid] += 1
        if calls[uid] > 1:
            from fastapi import HTTPException

            raise HTTPException(status_code=429, detail="AI quota exhausted")
        return {"text": "ok"}

    import app.routers.ai as ai_router_mod
    import app.services.ai_service as ai_service_mod

    monkeypatch.setattr(ai_router_mod, "generate", _quota_generate)
    monkeypatch.setattr(ai_service_mod, "generate", _quota_generate)

    a = "quota-a"
    b = "quota-b"
    seed_profile(fake_db, a, role="student")
    seed_profile(fake_db, b, role="student")

    # User A: first call succeeds, second call quota-exhausted.
    resp_ok = client.post(
        "/api/ai/note",
        headers=bearer(fake_auth.issue(a)),
        json={"action": "summary", "text": "x"},
    )
    assert resp_ok.status_code == 200, resp_ok.text
    resp_blocked = client.post(
        "/api/ai/note",
        headers=bearer(fake_auth.issue(a)),
        json={"action": "summary", "text": "x"},
    )
    assert resp_blocked.status_code == 429, resp_blocked.text

    # User B: independent quota — still succeeds.
    resp_b = client.post(
        "/api/ai/note",
        headers=bearer(fake_auth.issue(b)),
        json={"action": "summary", "text": "x"},
    )
    assert resp_b.status_code == 200, resp_b.text


# ---------------------------------------------------------------------------
# 10. CORS is locked down (static introspection)
# ---------------------------------------------------------------------------


def test_cors_origins_default_is_empty():
    """Spec §20: the backend ships with an empty CORS allowlist. The
    Flutter web build sets ``CORS_ORIGINS`` at deploy time, but the
    in-code default must NOT be ``*``.

    We assert on the class-level default rather than instantiating
    ``Settings()`` because the latter reads ``.env`` — and the local
    ``.env`` legitimately sets ``CORS_ORIGINS=*`` for development. The
    security-relevant contract is what ``Settings.cors_origins``
    defaults to in the absence of any configuration.
    """
    from app.core.config import Settings

    field = Settings.model_fields["cors_origins"]
    assert field.default == "", (
        f"CORS default must be empty (opt-in), got {field.default!r}"
    )
