"""Tests for /api/ai/exam-rescue/plan endpoint.

Validates:
- Authentication & student role gate
- Date validation (past dates rejected, today accepted as emergency 1-day plan, max 14 days)
- Input constraints (title, duration, max 3 materials)
- Material ownership verification & image rejection
- Zero-material mode (source_mode: 'general_subject')
- AI JSON parsing (clean JSON & fenced JSON)
- Fallback activation on malformed JSON or 503/504 provider errors
- Quota exhaustion (429) MUST NOT fall back
- Weak topics integration
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


# ---------------------------------------------------------------------------
# 1. Authentication & Role Gate
# ---------------------------------------------------------------------------

def test_exam_rescue_requires_auth(client):
    """Unauthenticated request must return 401 or 403."""
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        json={"exam_title": "Physics Final", "exam_date": "2026-10-05T00:00:00Z"},
    )
    assert resp.status_code in (401, 403), resp.status_code


def test_exam_rescue_requires_student_role(client, fake_db, fake_auth):
    """Non-student role (e.g. driver) must be rejected with 403."""
    uid = "rescue-driver-user"
    fake_db.seed("users", uid, {"role": "driver"})

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics Final", "exam_date": "2026-10-05T00:00:00Z"},
    )
    assert resp.status_code == 403, resp.text


# ---------------------------------------------------------------------------
# 2. Date Validation
# ---------------------------------------------------------------------------

def test_exam_rescue_past_date_rejected(client, fake_db, fake_auth):
    """Past exam date must return 400."""
    uid = "rescue-student-past"
    fake_db.seed("users", uid, {"role": "student"})

    past_date = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat()
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics Final", "exam_date": past_date},
    )
    assert resp.status_code == 400, resp.text
    assert "past" in resp.json()["detail"].lower()


def test_exam_rescue_invalid_date_format_rejected(client, fake_db, fake_auth):
    """Invalid date format must return 400."""
    uid = "rescue-student-bad-date"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics Final", "exam_date": "not-a-date"},
    )
    assert resp.status_code == 400, resp.text


def test_exam_rescue_beyond_14_days_rejected(client, fake_db, fake_auth):
    """Exam date > 14 days ahead must return 400."""
    uid = "rescue-student-far-date"
    fake_db.seed("users", uid, {"role": "student"})

    far_date = (datetime.now(timezone.utc) + timedelta(days=16)).isoformat()
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics Final", "exam_date": far_date},
    )
    assert resp.status_code == 400, resp.text
    assert "14 days" in resp.json()["detail"]


def test_exam_rescue_today_accepted_as_one_day_plan(client, fake_db, fake_auth, monkeypatch):
    """Today's date must be accepted as a 1-day emergency rescue plan."""
    uid = "rescue-student-today"
    fake_db.seed("users", uid, {"role": "student"})

    today_iso = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    valid_plan = {
        "title": "Physics Emergency Cram Plan",
        "strategy_summary": "1-day emergency cram plan.",
        "days": [
            {
                "day_number": 1,
                "theme": "High-yield formulas and concepts",
                "items": [
                    {
                        "title": "Review Key Formulas",
                        "type": "study",
                        "estimated_minutes": 60,
                        "action_note": "Memorize definitions and high-yield equations.",
                    },
                    {
                        "title": "Emergency Practice Quiz",
                        "type": "quiz",
                        "estimated_minutes": 30,
                        "action_note": "Rapid testing.",
                    },
                ],
            }
        ],
    }

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(return_value=json.dumps(valid_plan)),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": today_iso},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["daysRemaining"] == 1
    assert body["generationMode"] == "ai"
    assert len(body["days"]) == 1


# ---------------------------------------------------------------------------
# 3. Input Validation Constraints
# ---------------------------------------------------------------------------

def test_exam_rescue_title_too_short(client, fake_db, fake_auth):
    """Title with < 2 chars must return 422 or 400."""
    uid = "rescue-student-short-title"
    fake_db.seed("users", uid, {"role": "student"})

    future_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "P", "exam_date": future_date},
    )
    assert resp.status_code in (400, 422), resp.text


def test_exam_rescue_duration_bounds(client, fake_db, fake_auth):
    """daily_minutes < 30 or > 720 must return 422."""
    uid = "rescue-student-duration"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()

    # < 30
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": future_date, "daily_minutes": 20},
    )
    assert resp.status_code == 422, resp.text

    # > 720
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": future_date, "daily_minutes": 800},
    )
    assert resp.status_code == 422, resp.text


def test_exam_rescue_max_materials_limit(client, fake_db, fake_auth):
    """More than 3 materials must return 400 or 422."""
    uid = "rescue-student-max-mat"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={
            "exam_title": "Physics",
            "exam_date": future_date,
            "material_ids": ["m1", "m2", "m3", "m4"],
        },
    )
    assert resp.status_code in (400, 422), resp.text
    detail = str(resp.json()["detail"])
    assert "3" in detail


# ---------------------------------------------------------------------------
# 4. Material Ownership & Image Safety
# ---------------------------------------------------------------------------

def test_exam_rescue_material_not_found(client, fake_db, fake_auth):
    """Non-existent material ID must return 404."""
    uid = "rescue-student-notfound"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={
            "exam_title": "Physics",
            "exam_date": future_date,
            "material_ids": ["non-existent-mat-id"],
        },
    )
    assert resp.status_code == 404, resp.text


def test_exam_rescue_material_unauthorized(client, fake_db, fake_auth):
    """Material owned by another user (and private) must return 403 or 404."""
    uid = "rescue-student-victim"
    other_uid = "rescue-student-attacker"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed("users", other_uid, {"role": "student"})

    fake_db.seed(
        "materials",
        "mat-private-victim",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "secret_exam.pdf",
            "mimeType": "application/pdf",
        },
    )

    future_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, other_uid),
        json={
            "exam_title": "Physics",
            "exam_date": future_date,
            "material_ids": ["mat-private-victim"],
        },
    )
    assert resp.status_code in (403, 404), resp.text


def test_exam_rescue_rejects_image_materials(client, fake_db, fake_auth):
    """Selecting an image material must return 400."""
    uid = "rescue-student-img"
    fake_db.seed("users", uid, {"role": "student"})

    fake_db.seed(
        "materials",
        "mat-image-doc",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "diagram.png",
            "mimeType": "image/png",
            "filePath": f"users/{uid}/diagram.png",
        },
    )

    future_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={
            "exam_title": "Physics",
            "exam_date": future_date,
            "material_ids": ["mat-image-doc"],
        },
    )
    assert resp.status_code == 400, resp.text
    assert "cannot be used as a text source for Exam Rescue" in resp.json()["detail"]


# ---------------------------------------------------------------------------
# 5. Zero-Material Mode (source_mode: 'general_subject')
# ---------------------------------------------------------------------------

def test_exam_rescue_zero_materials_sets_general_subject_mode(client, fake_db, fake_auth, monkeypatch):
    """When no material IDs are provided, source_mode must be 'general_subject'."""
    uid = "rescue-student-zero-mat"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()

    valid_ai_response = {
        "title": "General Chemistry Rescue Plan",
        "strategy_summary": "AI generated rescue plan based on standard curriculum.",
        "days": [
            {
                "day_number": 1,
                "theme": "Periodic Trends & Bonding",
                "items": [
                    {
                        "title": "Periodic Table Trends",
                        "type": "study",
                        "estimated_minutes": 60,
                        "action_note": "Electronegativity, ionization energy.",
                    }
                ],
            },
            {
                "day_number": 2,
                "theme": "Revision & Quiz",
                "items": [
                    {
                        "title": "Mock Quiz",
                        "type": "quiz",
                        "estimated_minutes": 60,
                        "action_note": "Comprehensive practice.",
                    }
                ],
            },
        ],
    }

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(return_value=json.dumps(valid_ai_response)),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={
            "exam_title": "Chemistry",
            "exam_date": future_date,
            "material_ids": [],
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["sourceMode"] == "general_subject"
    assert body["generationMode"] == "ai"
    assert len(body["days"]) == 2


# ---------------------------------------------------------------------------
# 6. AI Output Handling & Fenced JSON Parsing
# ---------------------------------------------------------------------------

def test_exam_rescue_handles_markdown_code_fenced_json(client, fake_db, fake_auth, monkeypatch):
    """AI output wrapped in ```json ... ``` must be parsed cleanly."""
    uid = "rescue-student-fenced"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()

    raw_ai_text = """Here is the exam rescue plan:
```json
{
  "title": "Calculus Fast-Track Plan",
  "strategy_summary": "Master limits and derivatives in 2 days.",
  "days": [
    {
      "day_number": 1,
      "theme": "Limits and Continuity",
      "items": [
        {
          "title": "Limit Rules & L'Hopital",
          "type": "study",
          "estimated_minutes": 60,
          "action_note": "Core concepts."
        }
      ]
    },
    {
      "day_number": 2,
      "theme": "Derivatives & Review",
      "items": [
        {
          "title": "Derivative Rules Quiz",
          "type": "quiz",
          "estimated_minutes": 60,
          "action_note": "Test yourself."
        }
      ]
    }
  ]
}
```
Good luck with your calculus exam!"""

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(return_value=raw_ai_text),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Calculus", "exam_date": future_date},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["generationMode"] == "ai"
    assert body["examTitle"] == "Calculus"
    assert len(body["days"]) == 2


# ---------------------------------------------------------------------------
# 7. Fallback Behavior on Malformed JSON or Provider Errors
# ---------------------------------------------------------------------------

def test_exam_rescue_falls_back_on_malformed_json(client, fake_db, fake_auth, monkeypatch):
    """Malformed AI response must trigger deterministic fallback with generation_mode='fallback'."""
    uid = "rescue-student-malformed"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(return_value="I am an AI and here is a plan: Day 1 study physics, Day 2 do questions."),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": future_date},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["generationMode"] == "fallback"
    assert body["examTitle"] == "Physics"
    assert len(body["days"]) == 3
    # Check that day 3 contains mock exam / final review
    assert any(item["type"] in ("quiz", "revision") for item in body["days"][-1]["items"])


def test_exam_rescue_falls_back_on_provider_error(client, fake_db, fake_auth, monkeypatch):
    """Provider 503 or 504 error must trigger deterministic fallback with generation_mode='fallback'."""
    uid = "rescue-student-503"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(side_effect=HTTPException(status_code=503, detail="AI provider temporarily unavailable.")),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": future_date},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["generationMode"] == "fallback"
    assert len(body["days"]) == 2


# ---------------------------------------------------------------------------
# 8. Quota Exhaustion (429) Must NOT Fall Back
# ---------------------------------------------------------------------------

def test_exam_rescue_quota_exhausted_raises_429(client, fake_db, fake_auth, monkeypatch):
    """When quota is exhausted (429), endpoint must raise 429 and NOT fall back."""
    uid = "rescue-student-quota"
    fake_db.seed("users", uid, {"role": "student"})
    future_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(side_effect=HTTPException(status_code=429, detail="Daily AI request limit reached.")),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": future_date},
    )
    assert resp.status_code == 429, resp.text
    assert "limit" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# 9. Material Extraction & Sanitization of Item Material IDs
# ---------------------------------------------------------------------------

def test_exam_rescue_with_valid_material_extraction(client, fake_db, fake_auth, fake_storage, monkeypatch):
    """Valid PDF material owned by student is extracted into context and verified in plan."""
    uid = "rescue-student-mat-owner"
    fake_db.seed("users", uid, {"role": "student"})

    fake_db.seed(
        "materials",
        "mat-pdf-lecture",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "thermodynamics.pdf",
            "mimeType": "application/pdf",
            "filePath": f"users/{uid}/thermodynamics.pdf",
            "title": "Thermodynamics Chapter 1",
        },
    )
    fake_storage.set_bytes(f"users/{uid}/thermodynamics.pdf", b"%PDF-1.4 Thermodynamics laws and heat engines")

    future_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()

    valid_response = {
        "title": "Thermodynamics Exam Rescue",
        "strategy_summary": "2-day focused thermodynamics plan.",
        "days": [
            {
                "day_number": 1,
                "theme": "Laws of Thermodynamics",
                "items": [
                    {
                        "title": "Study First Law",
                        "type": "study",
                        "estimated_minutes": 60,
                        "action_note": "Internal energy and work done.",
                        "material_id": "mat-pdf-lecture",
                    },
                    {
                        "title": "Sneaky Fake Material Item",
                        "type": "study",
                        "estimated_minutes": 30,
                        "action_note": "This AI hallucinated an unselected material.",
                        "material_id": "unauthorized-mat-999",
                    },
                ],
            },
            {
                "day_number": 2,
                "theme": "Second Law & Entropy",
                "items": [
                    {
                        "title": "Practice Problems",
                        "type": "practice",
                        "estimated_minutes": 60,
                        "action_note": "Heat engine efficiency calculations.",
                        "material_id": "mat-pdf-lecture",
                    }
                ],
            },
        ],
    }

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(return_value=json.dumps(valid_response)),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={
            "exam_title": "Thermodynamics",
            "exam_date": future_date,
            "material_ids": ["mat-pdf-lecture"],
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["sourceMode"] == "materials"
    assert body["generationMode"] == "ai"

    # Verify that 'mat-pdf-lecture' is preserved, while 'unauthorized-mat-999' was stripped by sanitizer
    items = body["days"][0]["items"]
    assert items[0]["materialId"] == "mat-pdf-lecture"
    assert items[1]["materialId"] == ""


# ---------------------------------------------------------------------------
# 10. Phase T6: Quiz Results & Weak-Topic Closed Loop Integration Tests
# ---------------------------------------------------------------------------

def test_quiz_result_save_and_weak_topic_closed_loop(client, fake_db, fake_auth, monkeypatch):
    """Test 18 & 19: Quiz results with topicScores are saved and consumed by weak_topic_service."""
    uid = "rescue-weak-topic-student"
    fake_db.seed("users", uid, {"role": "student"})
    monkeypatch.setattr("app.routers.ai_study.get_firestore", lambda: fake_db)
    monkeypatch.setattr("app.services.weak_topic_service.get_firestore", lambda: fake_db)

    # 1. Save quiz result via /api/ai/quiz/save-result
    resp = client.post(
        "/api/ai/quiz/save-result",
        headers=_auth(fake_auth, uid),
        json={
            "subject_id": "Physics",
            "material_id": "mat-123",
            "questions": [
                {"question": "What is Carnot efficiency?", "correct": "A"},
                {"question": "What is entropy in reversible process?", "correct": "B"},
            ],
            "user_answers": ["C", "B"],
            "correct_answers": ["A", "B"],
            "score": 50,
            "topic_scores": {"Carnot Cycle": 0, "Entropy": 100},
            "difficulty": "medium",
            "time_spent_seconds": 120,
        },
    )
    assert resp.status_code == 200, resp.text

    # 2. Check weak topic service aggregates it
    from app.services.weak_topic_service import get_weak_topics
    weak_topics = get_weak_topics(uid, threshold=60)
    assert len(weak_topics) >= 1
    assert any(wt["topic"] == "Carnot Cycle" for wt in weak_topics)


def test_future_exam_rescue_incorporates_weak_topics(client, fake_db, fake_auth, monkeypatch):
    """Test 20: Future Exam Rescue generation reads weak topics and passes them to AI prompt."""
    uid = "rescue-weak-student-generation"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai_study as ai_study_mod
    monkeypatch.setattr(
        "app.services.weak_topic_service.get_weak_topics",
        lambda uid, threshold=60: [{"topic": "Dispersion Formulas", "average_score": 35}],
    )

    captured_prompts = []

    async def mock_generate(user_uid, prompt, feature=None):
        captured_prompts.append(prompt)
        return json.dumps({
            "title": "Optics Rescue Plan",
            "strategy_summary": "Targeted rescue plan.",
            "days": [
                {
                    "day_number": 1,
                    "theme": "Dispersion Review",
                    "items": [
                        {"title": "Dispersion Practice", "type": "study", "estimated_minutes": 60}
                    ],
                }
            ],
        })

    monkeypatch.setattr(ai_study_mod, "_call_generate", mock_generate)

    future_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Optics", "exam_date": future_date},
    )
    assert resp.status_code == 200, resp.text
    assert len(captured_prompts) == 1
    assert "Dispersion Formulas (accuracy: 35%)" in captured_prompts[0]


def test_weak_topic_lookup_failure_remains_non_blocking(client, fake_db, fake_auth, monkeypatch):
    """Test 21: Exception in weak topics lookup does not crash or block Exam Rescue plan generation."""
    uid = "rescue-weak-student-failing"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai_study as ai_study_mod

    def failing_weak_topics(uid, threshold=60):
        raise RuntimeError("Simulated Firestore timeout reading quiz results")

    monkeypatch.setattr(
        "app.services.weak_topic_service.get_weak_topics",
        failing_weak_topics,
    )

    async def mock_generate(user_uid, prompt, feature=None):
        return json.dumps({
            "title": "Chemistry Plan",
            "strategy_summary": "Summary",
            "days": [
                {
                    "day_number": 1,
                    "theme": "Theme",
                    "items": [{"title": "Item 1", "type": "study", "estimated_minutes": 30}],
                }
            ],
        })

    monkeypatch.setattr(ai_study_mod, "_call_generate", mock_generate)

    future_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Chemistry", "exam_date": future_date},
    )
    assert resp.status_code == 200, resp.text
