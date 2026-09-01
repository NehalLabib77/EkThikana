"""
Task 9 regression tests — pins the contract that links
``firestore.rules`` ⇄ the backend's group-admin writes.

Background
----------
``firebase/firestore.rules`` previously declared::

    function isGroupAdmin(groupId) {
      return isStudent()
        && groupId is string
        && request.auth.uid == get(/databases/$(database)/documents/groups/$(groupId)).data.adminId;
    }

That rule compared against the singular field ``adminId`` with ``==``,
but the backend has always written the **plural list** ``adminIds``
(see ``backend/app/routers/groups.py`` — every write uses
``adminIds: [...]``). The rule therefore evaluated to ``false`` for every
admin, silently denying admin-only operations such as
``POST /api/groups/{id}/chat/toggle``.

The fix lives in two places:
1. ``firebase/firestore.rules`` now uses ``request.auth.uid in
   ... .data.adminIds``.
2. ``firebase/firestore.indexes.json`` now declares a composite index
   on ``group_messages`` for ``(groupId ASC, createdAt DESC)`` so the
   chat-list composite query in ``GET /api/groups/{id}/chat`` can run.

These tests pin those contracts so the bug can never silently regress.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

# These tests do not need any FastAPI fixtures; they read files.
from tests.conftest import bearer, seed_profile  # noqa: E402  (importable check)


_REPO_ROOT = _BACKEND_ROOT.parent
_RULES_PATH = _REPO_ROOT / "firebase" / "firestore.rules"
_INDEXES_PATH = _REPO_ROOT / "firebase" / "firestore.indexes.json"


def _read(path: Path) -> str:
    assert path.exists(), f"Required file missing: {path}"
    return path.read_text(encoding="utf-8")


def _parse_indexes() -> dict:
    return json.loads(_read(_INDEXES_PATH))


# ---------------------------------------------------------------------------
# Rules contract: adminId vs adminIds
# ---------------------------------------------------------------------------


def test_rules_reference_plural_admin_ids() -> None:
    """The ``isGroupAdmin`` helper must use the plural ``adminIds`` field
    with the ``in`` operator — the singular ``adminId`` would always be
    ``false`` against the list the backend actually writes."""
    rules = _read(_RULES_PATH)
    is_group_admin_block = re.search(
        r"function\s+isGroupAdmin\s*\([^)]*\)\s*\{[^}]*\}",
        rules,
        re.DOTALL,
    )
    assert is_group_admin_block, "isGroupAdmin function not found in firestore.rules"
    body = is_group_admin_block.group(0)
    assert "adminIds" in body, (
        "isGroupAdmin must check adminIds (plural). "
        "The singular adminId silently denies every admin because the "
        "backend writes a list, not a string."
    )
    assert "adminId" not in re.sub(r"adminIds", "", body), (
        "isGroupAdmin still references the singular adminId; the rule is broken."
    )
    assert " in " in body, (
        "isGroupAdmin must use the ``in`` operator to test membership in "
        "the adminIds list."
    )
    assert " == " not in body, (
        "isGroupAdmin must not use ``==``; the admin set is a list."
    )


def test_group_messages_delete_rule_uses_admin_helper() -> None:
    """The ``group_messages/{id}`` delete rule must rely on the
    ``isGroupAdmin`` helper so admin moderation works."""
    rules = _read(_RULES_PATH)
    match = re.search(
        r"match\s+/group_messages/\{msgId\}\s*\{[^}]*\}",
        rules,
        re.DOTALL,
    )
    assert match, "match /group_messages/{msgId} block not found"
    block = match.group(0)
    assert "isGroupAdmin" in block, (
        "group_messages delete rule must check isGroupAdmin so admins "
        "can moderate their group's chat. Without it, only the message "
        "sender could delete."
    )


# ---------------------------------------------------------------------------
# Indexes contract: group_messages composite index
# ---------------------------------------------------------------------------


def test_group_messages_composite_index_present() -> None:
    """The ``group_messages`` collection requires a composite index over
    (groupId ASC, createdAt DESC) for ``GET /api/groups/{id}/chat`` to
    work without a runtime ``failed-precondition`` error from Firestore."""
    payload = _parse_indexes()
    indexes = payload.get("indexes", [])
    matches = [
        idx for idx in indexes
        if idx.get("collectionGroup") == "group_messages"
        and idx.get("queryScope") == "COLLECTION"
    ]
    assert matches, (
        "No group_messages composite index declared in "
        "firebase/firestore.indexes.json. The chat list endpoint uses "
        "``where(groupId).orderBy(createdAt DESC).limit(n)`` and will "
        "fail at runtime without this index."
    )
    fields = matches[0]["fields"]
    assert fields[0]["fieldPath"] == "groupId", (
        f"First field must be groupId, got {fields[0]['fieldPath']!r}"
    )
    assert fields[0].get("order", "ASCENDING") == "ASCENDING"
    assert fields[1]["fieldPath"] == "createdAt", (
        f"Second field must be createdAt, got {fields[1]['fieldPath']!r}"
    )
    assert fields[1].get("order") == "DESCENDING", (
        "createdAt ordering must be DESCENDING to match the chat list query"
    )


def test_indexes_json_parses_and_has_field_overrides() -> None:
    """Schema-level sanity check: the file is valid JSON and includes the
    ``fieldOverrides`` key expected by the Firebase CLI."""
    payload = _parse_indexes()
    assert isinstance(payload.get("indexes"), list)
    assert "fieldOverrides" in payload, (
        "firestore.indexes.json must include a ``fieldOverrides`` array."
    )


# ---------------------------------------------------------------------------
# Backend write shape — defensive regression
# ---------------------------------------------------------------------------


def test_groups_router_writes_plural_admin_ids(client, fake_db, fake_auth) -> None:
    """``POST /api/groups`` must persist ``adminIds`` (plural list) — the
    singular field never made it to the schema, but a typo in the router
    would silently desync from the security rules."""
    owner = "admin-shape-owner"
    token = fake_auth.issue(owner)
    seed_profile(fake_db, owner)
    resp = client.post(
        "/api/groups",
        headers=bearer(token),
        json={"name": "Shape", "description": "admin shape regression"},
    )
    assert resp.status_code in (200, 201), resp.text
    body = resp.json()
    group_id = body["id"]
    doc = fake_db._collections["groups"][group_id]
    assert "adminIds" in doc, (
        "Router wrote a doc without adminIds; admin operations will be denied."
    )
    assert isinstance(doc["adminIds"], list), (
        f"adminIds must be a list, got {type(doc['adminIds']).__name__}"
    )
    assert owner in doc["adminIds"]
    # The broken field must not appear anywhere on the doc.
    assert "adminId" not in doc, (
        "Doc contains a singular adminId field — likely a stray write that "
        "mirrors the broken rule schema."
    )