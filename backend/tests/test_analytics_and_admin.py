"""Phase 10.6 — Ziku Analytics Intelligence Foundation & Admin Tests.

Covers:
  * Event normalization & schema boundaries
  * Privacy exclusions (disallowed student fields discarded)
  * Admin authorization (401 unauth, 403 student/general, 200 admin)
  * Subject demand aggregation
  * Feature usage aggregation
  * Topic difficulty calculation & disclaimer
  * Minimum sample handling (topics with < 3 samples excluded)
  * Time-range filtering (7, 30, 90 days cutoff)
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.services.analytics_service import (
    EVENT_NAMES,
    EVENTS_COLLECTION,
    normalize_metadata,
    track_event,
)
from app.services.admin_analytics_service import (
    MIN_TOPIC_SAMPLE,
    feature_usage,
    overview,
    read_events,
    subject_demand,
    topic_difficulty,
)
from tests.conftest import bearer, seed_profile


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return bearer(fake_auth.issue(uid))


# ---------------------------------------------------------------------------
# 1. Event Normalization & Privacy Exclusions
# ---------------------------------------------------------------------------

def test_normalize_metadata_whitelists_allowed_dimensions():
    raw = {
        "subject": "Physics",
        "topic": "Electromagnetism",
        "chapter": "Faraday Law",
        "feature": "quiz",
        "content_type": "mcq",
        "source": "study_pack",
        "exam_type": "midterm",
        "score": 85,
        "total": 100,
        "mistake_count": 3,
        "duration_seconds": 1200,
        "event_date": "2026-10-02",
    }
    normalized = normalize_metadata(raw)
    assert normalized["subject"] == "Physics"
    assert normalized["topic"] == "Electromagnetism"
    assert normalized["chapter"] == "Faraday Law"
    assert normalized["feature"] == "quiz"
    assert normalized["content_type"] == "mcq"
    assert normalized["source"] == "study_pack"
    assert normalized["exam_type"] == "midterm"
    assert normalized["score"] == 85
    assert normalized["total"] == 100
    assert normalized["mistake_count"] == 3
    assert normalized["duration_seconds"] == 1200
    assert normalized["event_date"] == "2026-10-02"


def test_privacy_exclusions_disallow_raw_student_content():
    """Privacy guard: raw chat transcripts, notes, answer texts, and PII are stripped."""
    raw = {
        "subject": "Chemistry",
        "topic": "Organic Synthesis",
        # Disallowed privacy-invasive fields:
        "raw_chat": "I don't understand question 4",
        "chat_transcript": "user: help me with exam",
        "note_body": "Personal thoughts about the teacher",
        "answer_text": "Option B is correct because...",
        "answer_key": ["A", "B", "C", "D"],
        "student_phone": "+8801700000000",
        "parent_email": "parent@example.com",
    }
    normalized = normalize_metadata(raw)
    assert "subject" in normalized
    assert "topic" in normalized
    # Confirm private fields are completely omitted
    assert "raw_chat" not in normalized
    assert "chat_transcript" not in normalized
    assert "note_body" not in normalized
    assert "answer_text" not in normalized
    assert "answer_key" not in normalized
    assert "student_phone" not in normalized
    assert "parent_email" not in normalized


def test_normalize_metadata_handles_invalid_types_and_defaults_date():
    raw = {
        "score": True,  # booleans should be rejected from number fields
        "total": "not-a-number",
        "mistake_count": 5.0,
        "duration_seconds": 45.5,
        "event_date": "invalid-date",
    }
    normalized = normalize_metadata(raw)
    assert "score" not in normalized
    assert "total" not in normalized
    assert normalized["mistake_count"] == 5
    assert normalized["duration_seconds"] == 45.5
    # Should default to today's date in YYYY-MM-DD format
    today_iso = datetime.now(timezone.utc).date().isoformat()
    assert normalized["event_date"] == today_iso


def test_track_event_persists_canonical_event(fake_db):
    event_id = track_event(
        user_id="student_123",
        event_name="quiz_completed",
        metadata={
            "subject": "Math",
            "topic": "Calculus",
            "score": 10,
            "total": 12,
            "secret_note": "Do not store this",
        },
    )
    assert event_id is not None
    doc = fake_db.collection(EVENTS_COLLECTION).document(event_id).get().to_dict()
    assert doc is not None
    assert doc["eventId"] == event_id
    assert doc["userId"] == "student_123"
    assert doc["eventName"] == "quiz_completed"
    assert doc["subject"] == "Math"
    assert doc["topic"] == "Calculus"
    assert doc["score"] == 10
    assert doc["total"] == 12
    assert "secret_note" not in doc


def test_track_event_rejects_unknown_event_or_missing_user():
    assert track_event("", "quiz_completed") is None
    assert track_event("student_1", "button_clicked_everywhere") is None


# ---------------------------------------------------------------------------
# 2. Admin Authorization Gate
# ---------------------------------------------------------------------------

def test_admin_analytics_requires_authentication(client):
    resp = client.get("/api/admin/analytics/overview")
    assert resp.status_code == 401


def test_admin_analytics_forbids_student_account(client, fake_db, fake_auth):
    seed_profile(fake_db, "stu-001", role="student")
    resp = client.get(
        "/api/admin/analytics/overview",
        headers=_auth(fake_auth, "stu-001"),
    )
    assert resp.status_code == 403
    assert "Administrator account required" in resp.json()["detail"]


def test_admin_analytics_forbids_general_account(client, fake_db, fake_auth):
    seed_profile(fake_db, "gen-001", role="general")
    resp = client.get(
        "/api/admin/analytics/overview",
        headers=_auth(fake_auth, "gen-001"),
    )
    assert resp.status_code == 403


def test_admin_analytics_allows_admin_account(client, fake_db, fake_auth):
    seed_profile(fake_db, "adm-001", role="admin")
    resp = client.get(
        "/api/admin/analytics/overview",
        headers=_auth(fake_auth, "adm-001"),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "activeStudents" in data
    assert "aiRequests" in data
    assert "quizAttempts" in data


# ---------------------------------------------------------------------------
# 3. Subject Demand & Feature Usage Aggregations
# ---------------------------------------------------------------------------

def test_subject_demand_aggregation(fake_db):
    now = datetime.now(timezone.utc)
    fake_db.seed(EVENTS_COLLECTION, "e1", {"timestamp": now, "subject": "Biology"})
    fake_db.seed(EVENTS_COLLECTION, "e2", {"timestamp": now, "subject": "Biology"})
    fake_db.seed(EVENTS_COLLECTION, "e3", {"timestamp": now, "subject": "Physics"})

    res = subject_demand(days=30)
    subjects = res["subjects"]
    assert len(subjects) == 2
    assert subjects[0]["subject"] == "Biology"
    assert subjects[0]["eventCount"] == 2
    assert subjects[1]["subject"] == "Physics"
    assert subjects[1]["eventCount"] == 1


def test_feature_usage_aggregation(fake_db):
    now = datetime.now(timezone.utc)
    fake_db.seed(EVENTS_COLLECTION, "f1", {"timestamp": now, "eventName": "ai_chat_used"})
    fake_db.seed(EVENTS_COLLECTION, "f2", {"timestamp": now, "eventName": "ai_chat_used"})
    fake_db.seed(EVENTS_COLLECTION, "f3", {"timestamp": now, "eventName": "quiz_completed"})

    res = feature_usage(days=30)
    features = {item["eventName"]: item["count"] for item in res["features"]}
    assert features["ai_chat_used"] == 2
    assert features["quiz_completed"] == 1


# ---------------------------------------------------------------------------
# 4. Topic Difficulty & Minimum Sample Handling
# ---------------------------------------------------------------------------

def test_topic_difficulty_excludes_topics_below_minimum_sample(fake_db):
    now = datetime.now(timezone.utc)
    # Topic A has only 2 quiz events (< MIN_TOPIC_SAMPLE = 3)
    fake_db.seed(EVENTS_COLLECTION, "t1", {
        "timestamp": now,
        "eventName": "quiz_completed",
        "topic": "Quantum Tunneling",
        "score": 1,
        "total": 10,
    })
    fake_db.seed(EVENTS_COLLECTION, "t2", {
        "timestamp": now,
        "eventName": "quiz_completed",
        "topic": "Quantum Tunneling",
        "score": 2,
        "total": 10,
    })

    res = topic_difficulty(days=30)
    topic_names = [t["topic"] for t in res["topics"]]
    assert "Quantum Tunneling" not in topic_names


def test_topic_difficulty_includes_topics_meeting_minimum_sample(fake_db):
    now = datetime.now(timezone.utc)
    # Topic B has 3 quiz events
    for i in range(3):
        fake_db.seed(EVENTS_COLLECTION, f"tb_{i}", {
            "timestamp": now,
            "eventName": "quiz_completed",
            "topic": "Optics",
            "score": 3,
            "total": 10,
            "mistake_count": 2,
        })

    res = topic_difficulty(days=30)
    topics = res["topics"]
    assert len(topics) >= 1
    optics = next(t for t in topics if t["topic"] == "Optics")
    assert optics["difficultyScore"] > 0
    assert "Observed platform struggle" in optics["interpretation"]
    metrics = optics["supportingMetrics"]
    assert metrics["quizSamples"] == 3
    assert metrics["wrongAnswerRate"] == 0.7  # 7 wrong out of 10
    assert metrics["repeatedMistakes"] == 6


# ---------------------------------------------------------------------------
# 5. Time Filtering Cutoff
# ---------------------------------------------------------------------------

def test_time_filtering_excludes_events_past_cutoff(fake_db):
    now = datetime.now(timezone.utc)
    recent = now - timedelta(days=2)
    old = now - timedelta(days=45)

    fake_db.seed(EVENTS_COLLECTION, "recent_e", {
        "timestamp": recent,
        "userId": "u1",
        "eventName": "ai_chat_used",
        "subject": "Chemistry",
    })
    fake_db.seed(EVENTS_COLLECTION, "old_e", {
        "timestamp": old,
        "userId": "u2",
        "eventName": "ai_chat_used",
        "subject": "History",
    })

    # When querying with days=7, the 45-day old event must be ignored
    res_7d = overview(days=7)
    assert res_7d["eventCount"] == 1
    assert res_7d["activeStudents"] == 1

    # When querying with days=60, both are included
    res_60d = overview(days=60)
    assert res_60d["eventCount"] == 2
    assert res_60d["activeStudents"] == 2

