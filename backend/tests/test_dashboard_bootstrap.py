"""Phase 12.2.3 — Consolidated student dashboard bootstrap tests.

Covers the single ``GET /api/student/dashboard-bootstrap`` endpoint:

* authentication / role gating (401, 403) and derivation from the token only;
* the full section contract (profile, academicHealth, coach, focus, aiUsage,
  recommendation, examRescue, generatedAt);
* router -> service -> section delegation;
* isolated section failure handling (one section may throw without failing
  the payload);
* privacy (no sensitive keys or raw learning content in the payload);
* concurrency: parallel requests stay strictly isolated per student.

Every test runs against the real FastAPI app through the shared ``client``
fixture (FakeFirestore + FakeAuth).
"""

from __future__ import annotations

import sys
import threading
from datetime import datetime
from pathlib import Path
from typing import Any

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402

BOOTSTRAP_PATH = "/api/student/dashboard-bootstrap"

EXPECTED_SECTIONS = (
    "profile",
    "academicHealth",
    "coach",
    "focus",
    "aiUsage",
    "recommendation",
    "examRescue",
    "generatedAt",
)

# Keys that must never appear anywhere in the bootstrap payload.
# ``note`` is deliberately absent: ``aiUsage.features.note`` is an AI quota
# feature name, not raw learner content (its *value* is asserted separately).
FORBIDDEN_KEYS = {
    "password",
    "passwordhash",
    "resettoken",
    "idtoken",
    "accesstoken",
    "apikey",
    "answer",
    "answerkey",
    "answers",
    "rawanswer",
    "solution",
    "questions",
    "notes",
    "transcript",
    "rawnotes",
}


def _walk_keys(node: Any) -> list[str]:
    keys: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            keys.append(str(key))
            keys.extend(_walk_keys(value))
    elif isinstance(node, list):
        for item in node:
            keys.extend(_walk_keys(item))
    return keys


# ---------------------------------------------------------------------------
# Authentication & authorization
# ---------------------------------------------------------------------------


def test_bootstrap_requires_auth(client):
    """No token -> 401; an unverifiable token -> 401."""
    assert client.get(BOOTSTRAP_PATH).status_code == 401
    assert (
        client.get(BOOTSTRAP_PATH, headers=bearer("not-a-real-token")).status_code
        == 401
    )


def test_bootstrap_rejects_non_student(client, fake_db, fake_auth):
    """Only the student role may read the bootstrap payload."""
    seed_profile(fake_db, "staff-uid", role="admin", name="Staff")
    token = fake_auth.issue("staff-uid")

    resp = client.get(BOOTSTRAP_PATH, headers=bearer(token))

    assert resp.status_code == 403
    assert "Student account required" in resp.text


# ---------------------------------------------------------------------------
# Contract
# ---------------------------------------------------------------------------


def test_bootstrap_returns_all_sections(client, fake_db, fake_auth):
    """200 with every documented section and the caller's own profile."""
    seed_profile(fake_db, "student-uid", role="student", name="Alice")
    token = fake_auth.issue("student-uid")

    resp = client.get(BOOTSTRAP_PATH, headers=bearer(token))

    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert set(payload) == set(EXPECTED_SECTIONS)

    profile = payload["profile"]
    assert profile["uid"] == "student-uid"
    assert profile["role"] == "student"
    assert profile["displayName"] == "Alice"
    assert profile["email"]

    for section in EXPECTED_SECTIONS[1:-1]:
        assert isinstance(payload[section], dict), section
        assert "available" in payload[section], section

    generated = datetime.fromisoformat(payload["generatedAt"])
    assert generated.tzinfo is not None


def test_bootstrap_ignores_uid_query_parameter(client, fake_db, fake_auth):
    """The payload comes from the token only — ?uid= cannot select a user."""
    seed_profile(fake_db, "student-uid", role="student", name="Alice")
    seed_profile(fake_db, "attacker-uid", role="student", name="Mallory")
    token = fake_auth.issue("student-uid")

    resp = client.get(
        f"{BOOTSTRAP_PATH}?uid=attacker-uid", headers=bearer(token)
    )

    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["profile"]["uid"] == "student-uid"
    assert "attacker-uid" not in resp.text
    assert "Mallory" not in resp.text


# ---------------------------------------------------------------------------
# Delegation & failure isolation
# ---------------------------------------------------------------------------


def test_bootstrap_delegates_to_service_sections(
    client, fake_db, fake_auth, monkeypatch
):
    """The router must surface whatever the service sections return."""
    from app.services import dashboard_bootstrap_service as svc

    sentinel = {"available": True, "sessionId": "exam-rescue-42", "subject": "Physics"}
    monkeypatch.setattr(svc, "_get_exam_rescue", lambda uid: dict(sentinel))

    seed_profile(fake_db, "student-uid", role="student")
    token = fake_auth.issue("student-uid")

    resp = client.get(BOOTSTRAP_PATH, headers=bearer(token))

    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["examRescue"] == sentinel
    # Untouched sections still come from the service.
    assert set(payload) == set(EXPECTED_SECTIONS)


def test_bootstrap_isolates_section_failures(
    client, fake_db, fake_auth, monkeypatch
):
    """A throwing section falls back to its default and never fails the call."""
    from app.services import dashboard_bootstrap_service as svc
    from app.services import study_coach_service

    def _boom(uid: str) -> dict[str, Any]:
        raise RuntimeError("focus engine exploded")

    healthy = {"available": True, "requestsToday": 7}
    monkeypatch.setattr(svc, "_get_focus", _boom)
    monkeypatch.setattr(svc, "_get_ai_usage", lambda uid: dict(healthy))
    monkeypatch.setattr(study_coach_service, "daily_recommendation", _boom)

    seed_profile(fake_db, "student-uid", role="student")
    token = fake_auth.issue("student-uid")

    resp = client.get(BOOTSTRAP_PATH, headers=bearer(token))

    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert set(payload) == set(EXPECTED_SECTIONS)

    # Broken sections degrade to their documented defaults...
    assert payload["focus"] == {
        "available": False,
        "minutesDone": 0,
        "goalMinutes": 60,
        "focusScore": 0,
    }
    assert payload["coach"] == {
        "available": False,
        "headline": "Coach currently unavailable",
        "mission": [],
    }
    # ...while healthy sections still surface their real values.
    assert payload["aiUsage"] == healthy
    assert payload["profile"]["uid"] == "student-uid"
    assert "available" in payload["academicHealth"]
    assert "available" in payload["recommendation"]
    assert "available" in payload["examRescue"]


# ---------------------------------------------------------------------------
# Privacy
# ---------------------------------------------------------------------------


def test_bootstrap_payload_excludes_sensitive_fields(client, fake_db, fake_auth):
    """No credentials, raw questions, notes or transcripts are serialised."""
    fake_db.seed(
        "users",
        "student-uid",
        {
            "displayName": "Alice",
            "email": "student-uid@example.com",
            "role": "student",
            "passwordHash": "s3cr3t-password-hash",
            "resetToken": "reset-token-value",
        },
    )
    fake_db.collection("users").document("student-uid").collection(
        "mistakes"
    ).document("m1").set(
        {
            "topic": "Thermodynamics",
            "subjectId": "Physics",
            "occurrences": 3,
            "note": "PRIVATE RAW NOTE about cheating on the exam",
            "transcript": "PRIVATE TRANSCRIPT text",
        }
    )
    token = fake_auth.issue("student-uid")

    resp = client.get(BOOTSTRAP_PATH, headers=bearer(token))

    assert resp.status_code == 200, resp.text
    body = resp.text
    assert "s3cr3t-password-hash" not in body
    assert "reset-token-value" not in body
    assert "PRIVATE RAW NOTE" not in body
    assert "PRIVATE TRANSCRIPT" not in body

    payload = resp.json()
    lowered = {key.lower() for key in _walk_keys(payload)}
    assert not (lowered & FORBIDDEN_KEYS), sorted(lowered & FORBIDDEN_KEYS)


# ---------------------------------------------------------------------------
# Concurrency & isolation
# ---------------------------------------------------------------------------


def test_bootstrap_concurrent_requests_are_isolated(
    client, fake_db, fake_auth
):
    """Four simultaneous students each get exactly their own payload."""
    from fastapi.testclient import TestClient

    from app.main import app as fastapi_app

    uids = [f"concurrent-{index}" for index in range(4)]
    for index, uid in enumerate(uids):
        seed_profile(fake_db, uid, role="student", name=f"Student {index}")
        fake_auth.issue(uid)

    barrier = threading.Barrier(len(uids))
    results: dict[str, tuple[int, dict[str, Any]]] = {}
    errors: list[BaseException] = []
    lock = threading.Lock()

    def worker(uid: str) -> None:
        try:
            thread_client = TestClient(fastapi_app)
            barrier.wait(timeout=15)
            resp = thread_client.get(
                BOOTSTRAP_PATH, headers=bearer(f"token-{uid}")
            )
            with lock:
                results[uid] = (resp.status_code, resp.json())
        except BaseException as exc:  # noqa: BLE001
            with lock:
                errors.append(exc)

    threads = [
        threading.Thread(target=worker, args=(uid,), name=f"bootstrap-{uid}")
        for uid in uids
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=60)

    assert not errors, errors
    assert set(results) == set(uids)

    for index, uid in enumerate(uids):
        status, payload = results[uid]
        assert status == 200, f"{uid} -> {status}"
        assert set(payload) == set(EXPECTED_SECTIONS)
        assert payload["profile"]["uid"] == uid
        assert payload["profile"]["displayName"] == f"Student {index}"

    # No payload may reference another student.
    for uid, (_, payload) in results.items():
        for other in uids:
            if other == uid:
                continue
            assert other not in str(payload), f"{uid} leaked {other}"


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(pytest.main([__file__, "-v"]))
