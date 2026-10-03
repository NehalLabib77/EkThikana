"""Tests for Phase 12.2.2 Firestore Optimization & Data Scaling."""

from __future__ import annotations

import json
from pathlib import Path
import pytest
from fastapi import HTTPException

from app.services import ziku_tutor_service as tutor_svc
from app.services.ziku_tutor_service import (
    _load_session,
    _save_session,
    get_session,
    start_session,
    respond_to_step,
)


def test_index_configuration_exists():
    """Verify that required composite indexes are defined in firestore.indexes.json."""
    repo_root = Path(__file__).resolve().parents[2]
    indexes_file = repo_root / "firebase" / "firestore.indexes.json"
    assert indexes_file.exists(), f"Missing indexes file: {indexes_file}"

    with open(indexes_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    indexes = data.get("indexes", [])
    assert len(indexes) > 0

    indexed_collections = {idx.get("collectionGroup") for idx in indexes}
    assert "analytics_events" in indexed_collections
    assert "tutor_sessions" in indexed_collections
    assert "exam_attempts" in indexed_collections
    assert "exam_results" in indexed_collections
    assert "mistakes" in indexed_collections

    # Verify analytics_events index fields
    analytics_idx = next(i for i in indexes if i.get("collectionGroup") == "analytics_events")
    field_paths = [f["fieldPath"] for f in analytics_idx["fields"]]
    assert field_paths == ["event_name", "timestamp"]
    orders = [f["order"] for f in analytics_idx["fields"]]
    assert orders == ["ASCENDING", "DESCENDING"]

    # Verify tutor_sessions index fields
    tutor_idx = next(i for i in indexes if i.get("collectionGroup") == "tutor_sessions")
    tutor_fields = [f["fieldPath"] for f in tutor_idx["fields"]]
    assert tutor_fields == ["studentId", "createdAt"]
    assert [f["order"] for f in tutor_idx["fields"]] == ["ASCENDING", "DESCENDING"]


@pytest.mark.asyncio
async def test_tutor_session_creation_stores_metadata_correctly(fake_db, monkeypatch):
    """start_session must write lightweight parent metadata and initial turn."""
    uid = "student_scale_1"
    fake_db.seed("users", uid, {"role": "student"})

    res = await start_session(
        uid=uid,
        subject="Physics",
        topic="Optics",
        mode="socratic",
    )
    session_id = res["sessionId"]
    assert session_id.startswith("tutor_")
    assert res["status"] == "active"
    assert res["topic"] == "Optics"

    # Check parent document in Firestore
    parent_snap = fake_db.collection("tutor_sessions").document(session_id).get()
    assert parent_snap.exists
    parent_data = parent_snap.to_dict()

    assert parent_data["studentId"] == uid
    assert parent_data["topic"] == "Optics"
    assert parent_data["turnCount"] >= 1
    assert "createdAt" in parent_data
    assert "updatedAt" in parent_data
    assert "mastery" in parent_data


@pytest.mark.asyncio
async def test_turn_storage_in_subcollection(fake_db, monkeypatch):
    """Individual turns must be stored in tutor_sessions/{sessionId}/turns subcollection."""
    uid = "student_scale_2"
    fake_db.seed("users", uid, {"role": "student"})

    res = await start_session(
        uid=uid,
        subject="Chemistry",
        topic="Periodic Table",
        mode="socratic",
    )
    session_id = res["sessionId"]

    # Subcollection check for turn_1
    turns_ref = fake_db.collection("tutor_sessions").document(session_id).collection("turns")
    turn_docs = [snap.to_dict() for snap in turns_ref.stream()]
    assert len(turn_docs) >= 1
    assert turn_docs[0]["role"] == "tutor"
    assert "Periodic Table" in (turn_docs[0].get("content") or turn_docs[0].get("message") or "")

    # Now simulate a student response
    step_res = await respond_to_step(
        uid=uid,
        session_id=session_id,
        student_response="Elements are ordered by atomic number.",
    )
    assert step_res["sessionId"] == session_id

    # Verify additional turns are saved into the subcollection
    updated_turns = [snap.to_dict() for snap in turns_ref.stream()]
    assert len(updated_turns) >= 2
    student_turns = [t for t in updated_turns if t.get("role") == "student"]
    assert len(student_turns) == 1
    assert "atomic number" in (student_turns[0].get("content") or student_turns[0].get("message") or "")


@pytest.mark.asyncio
async def test_legacy_embedded_turn_fallback(fake_db):
    """Sessions saved prior to subcollections must seamlessly load from embedded history."""
    uid = "student_legacy_user"
    legacy_id = "tutor_legacy_999"
    fake_db.seed("users", uid, {"role": "student"})

    # Seed legacy document without any subcollection
    legacy_history = [
        {"role": "tutor", "content": "What is momentum?", "timestamp": "2026-10-01T10:00:00Z"},
        {"role": "student", "content": "Mass times velocity", "timestamp": "2026-10-01T10:01:00Z"},
    ]
    fake_db.seed("tutor_sessions", legacy_id, {
        "sessionId": legacy_id,
        "studentId": uid,
        "subject": "Physics",
        "topic": "Momentum",
        "history": legacy_history,
        "masteryEstimate": 0.7,
        "completed": False,
    })

    # Load via get_session
    loaded = await get_session(uid=uid, session_id=legacy_id)
    assert loaded["sessionId"] == legacy_id
    assert len(loaded["turns"]) == 2
    assert loaded["turns"][0]["role"] == "tutor"
    assert loaded["turns"][0]["message"] == "What is momentum?"
    assert loaded["turns"][1]["role"] == "student"
    assert loaded["turns"][1]["message"] == "Mass times velocity"
    assert loaded["turnCount"] == 2


@pytest.mark.asyncio
async def test_student_ownership_validation(fake_db):
    """Accessing another student's tutoring session must raise 403 Forbidden."""
    owner_uid = "owner_student_123"
    other_uid = "intruder_student_456"
    session_id = "tutor_private_session"

    fake_db.seed("users", owner_uid, {"role": "student"})
    fake_db.seed("users", other_uid, {"role": "student"})
    fake_db.seed("tutor_sessions", session_id, {
        "sessionId": session_id,
        "studentId": owner_uid,
        "topic": "Calculus",
        "history": [],
    })

    # Legitimate owner can read
    owner_data = await get_session(uid=owner_uid, session_id=session_id)
    assert owner_data["sessionId"] == session_id

    # Another student must receive 403
    with pytest.raises(HTTPException) as exc_info:
        await get_session(uid=other_uid, session_id=session_id)
    assert exc_info.value.status_code == 403

    # Non-existent session must receive 404
    with pytest.raises(HTTPException) as exc_404:
        await get_session(uid=owner_uid, session_id="non_existent_session_id")
    assert exc_404.value.status_code == 404
