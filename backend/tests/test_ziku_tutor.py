"""Phase 12 — Ziku Socratic AI Tutor Tests.

Tests the interactive Socratic tutoring layer over existing Gochano systems:
- Socratic session start & diagnostic question generation
- Student auth gating & ownership verification
- Direct answer escape hatch ("answerটা বলে দাও" / "just explain")
- Step-by-step reasoning evaluation with structured outputs
- 3-level progressive hint ladder
- Dynamic mode switching (socratic, explain, practice, exam_prep)
- Final mastery estimation and structured completion summary
- Recent sessions retrieval
"""

from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402
from app.services import ziku_tutor_service as tutor_service  # noqa: E402


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return bearer(fake_auth.issue(uid))


@pytest.mark.asyncio
async def test_auth_required(client, fake_db, fake_auth):
    """Anonymous or non-student requests must be rejected."""
    # Unauthenticated
    res = client.post(
        "/api/tutor/session",
        json={"subject": "Physics", "topic": "Optics"},
    )
    assert res.status_code == 401

    # Non-student role (e.g. parent)
    uid = "parent_user_1"
    seed_profile(fake_db, uid, role="parent")
    res = client.post(
        "/api/tutor/session",
        json={"subject": "Physics", "topic": "Optics"},
        headers=_auth(fake_auth, uid),
    )
    assert res.status_code == 403


@pytest.mark.asyncio
async def test_start_session_socratic(client, fake_db, fake_auth):
    """Starting a session initializes session in Firestore, level, and diagnostic question."""
    uid = "student_tutor_1"
    seed_profile(fake_db, uid, role="student")

    res = client.post(
        "/api/tutor/session",
        json={"subject": "Physics", "topic": "Optics", "concept": "Refraction"},
        headers=_auth(fake_auth, uid),
    )
    assert res.status_code == 200
    data = res.json()

    assert data["status"] == "active"
    assert data["mode"] == "socratic"
    assert data["subject"] == "Physics"
    assert data["topic"] == "Optics"
    assert data["concept"] == "Refraction"
    assert data["step"] == 1
    assert data["understandingLevel"] == 0.0
    assert data["masteryScore"] == 0.0
    assert data["hintsUsed"] == 0
    assert "question" in data and len(data["question"]) > 0
    assert "sessionId" in data

    # Verify session can be retrieved
    session_id = data["sessionId"]
    get_res = client.get(
        f"/api/tutor/{session_id}",
        headers=_auth(fake_auth, uid),
    )
    assert get_res.status_code == 200
    assert get_res.json()["sessionId"] == session_id


@pytest.mark.asyncio
async def test_session_ownership_protection(client, fake_db, fake_auth):
    """Students cannot access or respond to another student's session."""
    uid1 = "student_owner"
    uid2 = "student_intruder"
    seed_profile(fake_db, uid1, role="student")
    seed_profile(fake_db, uid2, role="student")

    # Student 1 creates session
    start_res = client.post(
        "/api/tutor/session",
        json={"subject": "Chemistry", "topic": "Periodic Table"},
        headers=_auth(fake_auth, uid1),
    )
    assert start_res.status_code == 200
    session_id = start_res.json()["sessionId"]

    # Student 2 attempts to get session
    res = client.get(
        f"/api/tutor/{session_id}",
        headers=_auth(fake_auth, uid2),
    )
    assert res.status_code == 403

    # Student 2 attempts to respond
    res = client.post(
        f"/api/tutor/{session_id}/respond",
        json={"response": "my answer"},
        headers=_auth(fake_auth, uid2),
    )
    assert res.status_code == 403



@pytest.mark.asyncio
async def test_direct_answer_escape_hatch(client, fake_db, fake_auth):
    """Detects direct escape ('answerটা বলে দাও') and seamlessly explains without reprimand."""
    uid = "student_tutor_escape"
    seed_profile(fake_db, uid, role="student")

    start_res = client.post(
        "/api/tutor/session",
        json={"subject": "Math", "topic": "Calculus"},
        headers=_auth(fake_auth, uid),
    )
    session_id = start_res.json()["sessionId"]

    # Student requests direct answer
    respond_res = client.post(
        f"/api/tutor/{session_id}/respond",
        json={"response": "আমাকে direct answerটা বলে দাও, please!"},
        headers=_auth(fake_auth, uid),
    )
    assert respond_res.status_code == 200
    data = respond_res.json()

    assert data["mode"] == "explain"
    assert "directExplanation" in data
    assert len(data["directExplanation"]) > 0


@pytest.mark.asyncio
async def test_respond_evaluation_and_step(client, fake_db, fake_auth):
    """Submitting reasoning evaluates the response into structured evaluation feedback."""
    uid = "student_tutor_eval"
    seed_profile(fake_db, uid, role="student")

    start_res = client.post(
        "/api/tutor/session",
        json={"subject": "Physics", "topic": "Thermodynamics"},
        headers=_auth(fake_auth, uid),
    )
    session_id = start_res.json()["sessionId"]

    respond_res = client.post(
        f"/api/tutor/{session_id}/respond",
        json={"response": "Entropy is the measure of disorder in a closed system."},
        headers=_auth(fake_auth, uid),
    )
    assert respond_res.status_code == 200
    data = respond_res.json()

    assert "evaluation" in data
    eval_data = data["evaluation"]
    assert "understanding" in eval_data
    assert "feedback" in eval_data
    assert data["step"] >= 2


@pytest.mark.asyncio
async def test_progressive_hint_ladder(client, fake_db, fake_auth):
    """Requesting hints gives progressive 3-level hints (conceptual -> relationship -> worked setup)."""
    uid = "student_tutor_hints"
    seed_profile(fake_db, uid, role="student")

    start_res = client.post(
        "/api/tutor/session",
        json={"subject": "Physics", "topic": "Kinematics"},
        headers=_auth(fake_auth, uid),
    )
    session_id = start_res.json()["sessionId"]

    # Hint 1
    h1_res = client.post(
        f"/api/tutor/{session_id}/hint",
        headers=_auth(fake_auth, uid),
    )
    assert h1_res.status_code == 200
    h1 = h1_res.json()
    assert h1["hintLevel"] == 1
    assert h1["hintsUsed"] == 1
    assert h1["maxHintsReached"] is False
    assert len(h1["hint"]) > 0

    # Hint 2
    h2_res = client.post(
        f"/api/tutor/{session_id}/hint",
        headers=_auth(fake_auth, uid),
    )
    assert h2_res.status_code == 200
    h2 = h2_res.json()
    assert h2["hintLevel"] == 2
    assert h2["hintsUsed"] == 2
    assert h2["maxHintsReached"] is False

    # Hint 3
    h3_res = client.post(
        f"/api/tutor/{session_id}/hint",
        headers=_auth(fake_auth, uid),
    )
    assert h3_res.status_code == 200
    h3 = h3_res.json()
    assert h3["hintLevel"] == 3
    assert h3["hintsUsed"] == 3
    assert h3["maxHintsReached"] is True


@pytest.mark.asyncio
async def test_switch_mode(client, fake_db, fake_auth):
    """Allows student to switch between tutor modes."""
    uid = "student_tutor_mode"
    seed_profile(fake_db, uid, role="student")

    start_res = client.post(
        "/api/tutor/session",
        json={"subject": "Biology", "topic": "Cell Structure"},
        headers=_auth(fake_auth, uid),
    )
    session_id = start_res.json()["sessionId"]

    # Switch to explain
    res = client.post(
        f"/api/tutor/{session_id}/mode",
        json={"mode": "explain"},
        headers=_auth(fake_auth, uid),
    )
    assert res.status_code == 200
    assert res.json()["mode"] == "explain"

    # Switch to practice
    res = client.post(
        f"/api/tutor/{session_id}/mode",
        json={"mode": "practice"},
        headers=_auth(fake_auth, uid),
    )
    assert res.status_code == 200
    assert res.json()["mode"] == "practice"


@pytest.mark.asyncio
async def test_complete_session(client, fake_db, fake_auth):
    """Finalizes session, generates summary, mastery band, and marks status completed."""
    uid = "student_tutor_complete"
    seed_profile(fake_db, uid, role="student")

    start_res = client.post(
        "/api/tutor/session",
        json={"subject": "Physics", "topic": "Optics"},
        headers=_auth(fake_auth, uid),
    )
    session_id = start_res.json()["sessionId"]

    # Submit 1 response first
    client.post(
        f"/api/tutor/{session_id}/respond",
        json={"response": "Light refracts due to change in speed."},
        headers=_auth(fake_auth, uid),
    )

    # Complete session
    comp_res = client.post(
        f"/api/tutor/{session_id}/complete",
        headers=_auth(fake_auth, uid),
    )
    assert comp_res.status_code == 200
    data = comp_res.json()

    assert data["status"] == "completed"
    assert "masteryScore" in data
    assert data["masteryBand"] in {"High", "Medium", "Developing"}
    assert "summary" in data
    assert "overview" in data["summary"]
    assert "conceptsMastered" in data["summary"]
    assert "conceptsToReview" in data["summary"]


@pytest.mark.asyncio
async def test_get_recent_sessions(client, fake_db, fake_auth):
    """Retrieves recent tutor sessions for student."""
    uid = "student_tutor_recent"
    seed_profile(fake_db, uid, role="student")

    # Create 2 sessions
    client.post(
        "/api/tutor/session",
        json={"subject": "Physics", "topic": "Optics"},
        headers=_auth(fake_auth, uid),
    )
    client.post(
        "/api/tutor/session",
        json={"subject": "Chemistry", "topic": "Bonding"},
        headers=_auth(fake_auth, uid),
    )

    recent_res = client.get(
        "/api/tutor/recent?limit=5",
        headers=_auth(fake_auth, uid),
    )
    assert recent_res.status_code == 200
    sessions = recent_res.json()
    assert len(sessions) >= 2
    assert any(s["topic"] == "Optics" for s in sessions)
    assert any(s["topic"] == "Bonding" for s in sessions)
