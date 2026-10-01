"""Phase AI-FLOAT-1 — Ziku chat, AI activity inventory, and quota switch.

Covers the contract the Profile → AI Usage dashboard depends on:

* ``POST /api/ai/chat`` — auth, role gate, history order, user/assistant
  roles only, bounded history, and one counter increment per successful turn.
* ``record_ai_activity`` — server-side, per-UID, atomic, counters only.
* Quiz generations vs. actual generated questions as two DISTINCT counters.
* Exam Rescue / Assignment / Note / PDF / Image / Planner counters.
* ``AI_QUOTA_ENFORCEMENT`` on (429 at limit) vs off (no 429, counters still
  increment).
* User isolation: nobody can read another user's numbers.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

# Captured at import time — the shared ``client`` fixture replaces
# ``ai_service._consume_quota`` with a no-op for unrelated tests, so the real
# implementation has to be grabbed before any fixture runs.
import app.services.ai_service as ai_service_module  # noqa: E402

REAL_CONSUME_QUOTA = ai_service_module._consume_quota


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


def _summary(fake_db, uid: str) -> dict:
    doc = fake_db._collections.get("ai_usage_summary", {}).get(uid, {})
    return doc


# ---------------------------------------------------------------------------
# Chat — auth, validation, history semantics
# ---------------------------------------------------------------------------


def test_chat_requires_auth(client):
    resp = client.post(
        "/api/ai/chat",
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert resp.status_code in (401, 403), resp.status_code


def test_chat_requires_student_role(client, fake_db, fake_auth):
    uid = "chat-driver"
    fake_db.seed("users", uid, {"role": "driver"})
    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    assert resp.status_code == 403, resp.text


def test_chat_rejects_unknown_role(client, fake_db, fake_auth):
    uid = "chat-bad-role"
    fake_db.seed("users", uid, {"role": "student"})
    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={"messages": [{"role": "system", "content": "be nice"}]},
    )
    assert resp.status_code in (400, 422), resp.text


def test_chat_rejects_assistant_ending_history(client, fake_db, fake_auth):
    """The newest turn must be the student's, otherwise nothing to answer."""
    uid = "chat-bad-tail"
    fake_db.seed("users", uid, {"role": "student"})
    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={
            "messages": [
                {"role": "user", "content": "what is reflection?"},
                {"role": "assistant", "content": "total internal reflection..."},
            ]
        },
    )
    assert resp.status_code == 400, resp.text


def test_chat_rejects_empty_history(client, fake_db, fake_auth):
    uid = "chat-empty"
    fake_db.seed("users", uid, {"role": "student"})
    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={"messages": []},
    )
    assert resp.status_code in (400, 422), resp.text


def test_normalize_chat_messages_bounds_and_preserves_order():
    from app.services.ai_service import normalize_chat_messages

    raw = []
    for i in range(15):
        raw.append({"role": "user" if i % 2 == 0 else "assistant", "content": f"turn-{i}"})
    raw.append({"role": "user", "content": "latest question"})

    out = normalize_chat_messages(raw)

    assert len(out) == 10, "history must be bounded to the last 10 turns"
    assert out[-1] == {"role": "user", "content": "latest question"}
    # Order is preserved exactly as supplied (no re-sorting).
    assert [m["content"] for m in out] == [m["content"] for m in raw[-10:]]
    # Roles are only ever user/assistant.
    assert {m["role"] for m in out} <= {"user", "assistant"}


def test_normalize_chat_messages_rejects_non_string_content():
    from app.services.ai_service import normalize_chat_messages

    with pytest.raises(HTTPException) as exc:
        normalize_chat_messages([{"role": "user", "content": 42}])
    assert exc.value.status_code == 400


def test_chat_forwards_history_in_order_with_roles_only(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "chat-order"
    fake_db.seed("users", uid, {"role": "student"})

    captured: dict = {}

    async def _fake_chat_generate(uid_arg, messages, **kwargs):
        captured["uid"] = uid_arg
        captured["messages"] = messages
        captured["kwargs"] = kwargs
        return {"reply": "Because light stays inside the denser medium.", "suggested_followups": ["Why?"]}

    import app.routers.ai as ai_router

    monkeypatch.setattr(ai_router, "chat_generate", _fake_chat_generate)

    history = [
        {"role": "user", "content": "What is total internal reflection?"},
        {"role": "assistant", "content": "It is when light is fully reflected inside a denser medium."},
        {"role": "user", "content": "What is the second condition?"},
    ]
    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={"messages": history, "current_destination": "Today", "app_mode": "study"},
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["reply"].startswith("Because light")
    assert body["suggested_followups"] == ["Why?"]

    forwarded = captured["messages"]
    assert [m["role"] for m in forwarded] == ["user", "assistant", "user"]
    assert [m["content"] for m in forwarded] == [m["content"] for m in history]
    assert captured["uid"] == uid


def test_chat_success_increments_activity_counter(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "chat-counter"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai as ai_router

    monkeypatch.setattr(
        ai_router,
        "chat_generate",
        AsyncMock(return_value={"reply": "ok", "suggested_followups": []}),
    )

    for _ in range(2):
        resp = client.post(
            "/api/ai/chat",
            headers=_auth(fake_auth, uid),
            json={"messages": [{"role": "user", "content": "hello"}]},
        )
        assert resp.status_code == 200, resp.text

    # One follow-up chip submission counts exactly like a typed message.
    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={"messages": [
            {"role": "user", "content": "hello"},
            {"role": "assistant", "content": "hi"},
            {"role": "user", "content": "Give me an example"},
        ]},
    )
    assert resp.status_code == 200, resp.text

    assert _summary(fake_db, uid)["ai_chat_messages"] == 3


def test_chat_failure_does_not_increment(client, fake_db, fake_auth, monkeypatch):
    uid = "chat-fail"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai as ai_router

    async def _boom(*args, **kwargs):
        raise HTTPException(status_code=503, detail="AI service configuration error")

    monkeypatch.setattr(ai_router, "chat_generate", _boom)

    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={"messages": [{"role": "user", "content": "hello"}]},
    )
    assert resp.status_code == 503, resp.text
    assert _summary(fake_db, uid).get("ai_chat_messages", 0) == 0


def test_opening_usage_screen_increments_nothing(client, fake_db, fake_auth):
    uid = "chat-peek"
    fake_db.seed("users", uid, {"role": "student"})

    for _ in range(3):
        resp = client.get("/api/ai/usage", headers=_auth(fake_auth, uid))
        assert resp.status_code == 200, resp.text

    assert _summary(fake_db, uid) == {}, "reading usage must never write counters"


def test_usage_response_exposes_summary_and_quota_flag(client, fake_db, fake_auth):
    uid = "usage-shape"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "ai_usage_summary",
        uid,
        {"uid": uid, "ai_chat_messages": 4, "quiz_generations": 2, "quiz_questions": 7},
    )

    resp = client.get("/api/ai/usage", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["quota_enforcement_enabled"] is True, "safe default must be enforced"
    assert body["summary"]["ai_chat_messages"] == 4
    assert body["summary"]["quiz_generations"] == 2
    assert body["summary"]["quiz_questions"] == 7


def test_usage_stores_counters_only_never_content(client, fake_db, fake_auth, monkeypatch):
    uid = "usage-privacy"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai as ai_router

    monkeypatch.setattr(
        ai_router,
        "chat_generate",
        AsyncMock(return_value={"reply": "secret answer", "suggested_followups": []}),
    )

    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid),
        json={"messages": [{"role": "user", "content": "my private question"}]},
    )
    assert resp.status_code == 200, resp.text

    doc = _summary(fake_db, uid)
    blob = str(doc)
    assert "my private question" not in blob
    assert "secret answer" not in blob
    assert doc["ai_chat_messages"] == 1


def test_usage_is_isolated_per_user(client, fake_db, fake_auth, monkeypatch):
    uid_a, uid_b = "usage-user-a", "usage-user-b"
    fake_db.seed("users", uid_a, {"role": "student"})
    fake_db.seed("users", uid_b, {"role": "student"})

    import app.routers.ai as ai_router

    monkeypatch.setattr(
        ai_router,
        "chat_generate",
        AsyncMock(return_value={"reply": "ok", "suggested_followups": []}),
    )

    resp = client.post(
        "/api/ai/chat",
        headers=_auth(fake_auth, uid_a),
        json={"messages": [{"role": "user", "content": "hello"}]},
    )
    assert resp.status_code == 200, resp.text

    resp_b = client.get("/api/ai/usage", headers=_auth(fake_auth, uid_b))
    assert resp_b.status_code == 200, resp_b.text
    assert resp_b.json()["summary"]["ai_chat_messages"] == 0
    assert uid_b not in fake_db._collections.get("ai_usage_summary", {})
    assert _summary(fake_db, uid_a)["ai_chat_messages"] == 1


def test_usage_requires_auth(client):
    assert client.get("/api/ai/usage").status_code in (401, 403)


# ---------------------------------------------------------------------------
# Quota enforcement switch
# ---------------------------------------------------------------------------


def test_quota_enforcement_on_blocks_at_limit(client, fake_db, fake_auth, monkeypatch):
    """Default (safe) behaviour: an exhausted Gochano limit returns 429."""
    uid = "quota-on"
    fake_db.seed("users", uid, {"role": "student"})
    month = datetime.now(timezone.utc).strftime("%Y%m")
    from app.core.config import get_settings

    limit = get_settings().ai_limit_note_monthly
    fake_db.seed(
        "ai_usage_monthly",
        f"{uid}_{month}",
        {"uid": uid, "month": month, "features": {"note_ai": limit}},
    )

    import app.services.ai_service as ai_mod
    import app.routers.ai as ai_router

    async def _realish_generate(uid_arg, prompt, *args, feature=None, **kwargs):
        REAL_CONSUME_QUOTA(uid_arg, feature=feature or "note")
        return "generated"

    monkeypatch.setattr(ai_mod, "_consume_quota", REAL_CONSUME_QUOTA)
    monkeypatch.setattr(ai_mod, "generate", _realish_generate)
    monkeypatch.setattr(ai_router, "generate", _realish_generate)
    monkeypatch.setattr(ai_mod, "quota_enforcement_enabled", lambda: True)

    resp = client.post(
        "/api/ai/note",
        headers=_auth(fake_auth, uid),
        json={"action": "summary", "text": "one more note"},
    )
    assert resp.status_code == 429, resp.text
    # Attempt counted by quota accounting, but NO lifetime activity counter.
    assert _summary(fake_db, uid).get("ai_notes", 0) == 0


def test_quota_enforcement_off_does_not_block_but_still_counts(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "quota-off"
    fake_db.seed("users", uid, {"role": "student"})
    month = datetime.now(timezone.utc).strftime("%Y%m")
    from app.core.config import get_settings

    limit = get_settings().ai_limit_note_monthly
    fake_db.seed(
        "ai_usage_monthly",
        f"{uid}_{month}",
        {"uid": uid, "month": month, "features": {"note_ai": limit}},
    )

    import app.services.ai_service as ai_mod
    import app.routers.ai as ai_router

    async def _realish_generate(uid_arg, prompt, *args, feature=None, **kwargs):
        REAL_CONSUME_QUOTA(uid_arg, feature=feature or "note")
        return "generated"

    monkeypatch.setattr(ai_mod, "_consume_quota", REAL_CONSUME_QUOTA)
    monkeypatch.setattr(ai_mod, "generate", _realish_generate)
    monkeypatch.setattr(ai_router, "generate", _realish_generate)
    monkeypatch.setattr(ai_mod, "quota_enforcement_enabled", lambda: False)

    resp = client.post(
        "/api/ai/note",
        headers=_auth(fake_auth, uid),
        json={"action": "summary", "text": "one more note"},
    )
    assert resp.status_code == 200, resp.text

    # Quota counter still increments (attempt accounting) …
    monthly = fake_db._collections["ai_usage_monthly"][f"{uid}_{month}"]
    assert monthly["features"]["note_ai"] == limit + 1
    # … and the lifetime activity counter increments too.
    assert _summary(fake_db, uid)["ai_notes"] == 1

    # The usage payload reports the switch so the app can show the banner.
    usage = client.get("/api/ai/usage", headers=_auth(fake_auth, uid)).json()
    assert usage["quota_enforcement_enabled"] is False


# ---------------------------------------------------------------------------
# Note / PDF / Image / Assignment / Planner counters
# ---------------------------------------------------------------------------


def test_note_ai_counts_every_action(client, fake_db, fake_auth):
    uid = "note-counter"
    fake_db.seed("users", uid, {"role": "student"})

    for action in ("summary", "cleanup", "explain", "key_topics"):
        resp = client.post(
            "/api/ai/note",
            headers=_auth(fake_auth, uid),
            json={"action": action, "text": "Mitochondria are the powerhouse of the cell."},
        )
        assert resp.status_code == 200, resp.text

    assert _summary(fake_db, uid)["ai_notes"] == 4


def test_pdf_question_counts_as_material_qa(client, fake_db, fake_auth, fake_storage):
    uid = "pdf-counter"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-pdf-count",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "lecture.pdf",
            "mimeType": "application/pdf",
            "filePath": "users/pdf-counter/lecture.pdf",
        },
    )
    fake_storage.set_bytes("users/pdf-counter/lecture.pdf", b"%PDF-1.4\nTopic 1\nTopic 2\n")

    resp = client.post(
        "/api/ai/pdf-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-pdf-count", "question": "What is covered?"},
    )
    assert resp.status_code == 200, resp.text
    assert _summary(fake_db, uid)["pdf_questions"] == 1


def test_assignment_explain_counts_as_assignment_ai(client, fake_db, fake_auth, monkeypatch):
    uid = "assign-counter"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai_study as ai_study_mod

    monkeypatch.setattr(
        ai_study_mod, "_call_generate", AsyncMock(return_value="Explain the objective.")
    )

    for endpoint in ("explain", "breakdown"):
        resp = client.post(
            f"/api/ai/assignment/{endpoint}",
            headers=_auth(fake_auth, uid),
            json={"title": "Lab report", "deadline": "2026-10-10"},
        )
        assert resp.status_code == 200, resp.text

    assert _summary(fake_db, uid)["assignment_uses"] == 2


def test_planner_recommend_counts_once_per_ai_run(client, fake_db, fake_auth, monkeypatch):
    uid = "planner-counter"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed("tasks", "t-planner", {"ownerId": uid, "title": "Read chapter 4"})

    import app.routers.ai_study as ai_study_mod

    # ``ai_study`` binds its own ``get_firestore`` copy at import time.
    monkeypatch.setattr(ai_study_mod, "get_firestore", lambda: fake_db)
    monkeypatch.setattr(
        ai_study_mod, "_call_generate", AsyncMock(return_value="Study plan for today.")
    )

    resp = client.post(
        "/api/ai/planner/recommend",
        headers=_auth(fake_auth, uid),
        json={"availableHours": 4},
    )
    assert resp.status_code == 200, resp.text
    assert _summary(fake_db, uid)["planner_plans"] == 1

    # No tasks → no AI call → no counter.
    uid2 = "planner-empty"
    fake_db.seed("users", uid2, {"role": "student"})
    resp = client.post(
        "/api/ai/planner/recommend",
        headers=_auth(fake_auth, uid2),
        json={"availableHours": 4},
    )
    assert resp.status_code == 200, resp.text
    assert _summary(fake_db, uid2).get("planner_plans", 0) == 0


# ---------------------------------------------------------------------------
# Quiz — generations vs. actual questions are DISTINCT
# ---------------------------------------------------------------------------


def _quiz_payload(questions: list) -> str:
    return json.dumps({"questions": questions})


def test_quiz_generation_and_question_count_are_distinct(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "quiz-counter"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai_study as ai_study_mod

    five = [
        {"question": f"Q{i}", "type": "mcq", "options": ["A", "B", "C", "D"], "correct": "A"}
        for i in range(5)
    ]
    monkeypatch.setattr(
        ai_study_mod, "_call_generate", AsyncMock(return_value=_quiz_payload(five))
    )

    resp = client.post(
        "/api/ai/quiz/generate",
        headers=_auth(fake_auth, uid),
        json={"topic": "Physics", "source": "Reflection and refraction basics.", "questionCount": 5},
    )
    assert resp.status_code == 200, resp.text
    assert len(resp.json()["quiz"]) == 5

    doc = _summary(fake_db, uid)
    assert doc["quiz_generations"] == 1
    assert doc["quiz_questions"] == 5


def test_quiz_partial_usable_questions_counts_actual_number(
    client, fake_db, fake_auth, monkeypatch
):
    """Requested 10, model returned 5 usable → generations 1, questions 5."""
    uid = "quiz-partial"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai_study as ai_study_mod

    mixed = [
        {"question": "Q1", "type": "mcq"},
        {"question": "Q2", "type": "mcq"},
        {"question": "Q3", "type": "mcq"},
        {"question": "   ", "type": "mcq"},   # unusable — blank prompt
        {"type": "mcq"},                       # unusable — no question field
    ]
    monkeypatch.setattr(
        ai_study_mod, "_call_generate", AsyncMock(return_value=_quiz_payload(mixed))
    )

    resp = client.post(
        "/api/ai/quiz/generate",
        headers=_auth(fake_auth, uid),
        json={"topic": "Chemistry", "source": "Covalent and ionic bonding rules.", "questionCount": 10},
    )
    assert resp.status_code == 200, resp.text

    doc = _summary(fake_db, uid)
    assert doc["quiz_generations"] == 1
    assert doc["quiz_questions"] == 3


def test_failed_quiz_generation_does_not_increment(client, fake_db, fake_auth, monkeypatch):
    uid = "quiz-fail"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai_study as ai_study_mod

    async def _boom(*args, **kwargs):
        raise HTTPException(status_code=502, detail="AI provider temporarily unavailable.")

    monkeypatch.setattr(ai_study_mod, "_call_generate", _boom)

    resp = client.post(
        "/api/ai/quiz/generate",
        headers=_auth(fake_auth, uid),
        json={"topic": "Biology", "source": "Cell division overview.", "questionCount": 5},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["quiz"] == []

    doc = _summary(fake_db, uid)
    assert doc.get("quiz_generations", 0) == 0
    assert doc.get("quiz_questions", 0) == 0


def test_unparsable_quiz_payload_does_not_increment(client, fake_db, fake_auth, monkeypatch):
    uid = "quiz-unparsed"
    fake_db.seed("users", uid, {"role": "student"})

    import app.routers.ai_study as ai_study_mod

    monkeypatch.setattr(
        ai_study_mod, "_call_generate", AsyncMock(return_value="Sorry, I cannot do that.")
    )

    resp = client.post(
        "/api/ai/quiz/generate",
        headers=_auth(fake_auth, uid),
        json={"topic": "History", "source": "Causes of the world wars.", "questionCount": 5},
    )
    assert resp.status_code == 200, resp.text
    assert _summary(fake_db, uid).get("quiz_generations", 0) == 0


def test_quiz_quota_attempts_remain_separate_from_generation_counter(
    client, fake_db, fake_auth, monkeypatch
):
    """Monthly quota attempts are tracked separately from 'Quiz Generations'."""
    uid = "quiz-quota-split"
    fake_db.seed("users", uid, {"role": "student"})
    month = datetime.now(timezone.utc).strftime("%Y%m")
    fake_db.seed(
        "ai_usage_monthly",
        f"{uid}_{month}",
        {"uid": uid, "month": month, "features": {"quiz": 2}},
    )

    import app.services.ai_service as ai_mod
    import app.routers.ai_study as ai_study_mod

    async def _realish_generate(uid_arg, prompt, *args, feature=None, **kwargs):
        REAL_CONSUME_QUOTA(uid_arg, feature=feature or "quiz")
        return _quiz_payload([{"question": "Only one"}])

    monkeypatch.setattr(ai_mod, "_consume_quota", REAL_CONSUME_QUOTA)
    monkeypatch.setattr(ai_study_mod, "generate", _realish_generate)
    monkeypatch.setattr(ai_study_mod, "_call_generate", _realish_generate)

    resp = client.post(
        "/api/ai/quiz/generate",
        headers=_auth(fake_auth, uid),
        json={"topic": "Physics", "source": "Reflection and refraction basics.", "questionCount": 5},
    )
    assert resp.status_code == 200, resp.text

    monthly = fake_db._collections["ai_usage_monthly"][f"{uid}_{month}"]
    assert monthly["features"]["quiz"] == 3, "attempt quota still counts the try"
    doc = _summary(fake_db, uid)
    assert doc["quiz_generations"] == 1, "only ONE successful generation recorded"
    assert doc["quiz_questions"] == 1


# ---------------------------------------------------------------------------
# Exam Rescue counter
# ---------------------------------------------------------------------------


def _valid_rescue_plan_json(days: int) -> str:
    plan = {
        "title": "Physics Rescue",
        "strategy_summary": "Focused rescue.",
        "days": [
            {
                "day_number": i,
                "theme": f"Day {i} focus",
                "items": [
                    {
                        "title": "Review chapter",
                        "type": "study",
                        "estimated_minutes": 60,
                        "action_note": "Read and summarize.",
                    }
                ],
            }
            for i in range(1, days + 1)
        ],
    }
    return json.dumps(plan)


def test_exam_rescue_ai_plan_increments_counter(client, fake_db, fake_auth, monkeypatch):
    uid = "rescue-counter"
    fake_db.seed("users", uid, {"role": "student"})
    exam_date = (datetime.now(timezone.utc) + timedelta(days=3)).strftime("%Y-%m-%d")

    import app.routers.ai_study as ai_study_mod

    monkeypatch.setattr(
        ai_study_mod,
        "_call_generate",
        AsyncMock(return_value=_valid_rescue_plan_json(3)),
    )

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": exam_date},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["generationMode"] == "ai"
    assert _summary(fake_db, uid)["exam_rescue_plans"] == 1

    # Generating a second plan increments again.
    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Chemistry", "exam_date": exam_date},
    )
    assert resp.status_code == 200, resp.text
    assert _summary(fake_db, uid)["exam_rescue_plans"] == 2


def test_exam_rescue_fallback_plan_does_not_increment(client, fake_db, fake_auth, monkeypatch):
    uid = "rescue-fallback"
    fake_db.seed("users", uid, {"role": "student"})
    exam_date = (datetime.now(timezone.utc) + timedelta(days=3)).strftime("%Y-%m-%d")

    import app.routers.ai_study as ai_study_mod

    async def _boom(*args, **kwargs):
        raise HTTPException(status_code=502, detail="AI provider temporarily unavailable.")

    monkeypatch.setattr(ai_study_mod, "_call_generate", _boom)

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "Physics", "exam_date": exam_date},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["generationMode"] == "fallback"
    assert _summary(fake_db, uid).get("exam_rescue_plans", 0) == 0


def test_exam_rescue_opening_setup_increments_nothing(client, fake_db, fake_auth):
    """Validation-only requests never reach AI and must not count."""
    uid = "rescue-peek"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={"exam_title": "X", "exam_date": "not-a-date"},
    )
    assert resp.status_code in (400, 422), resp.text
    assert _summary(fake_db, uid) == {}


# ---------------------------------------------------------------------------
# record_ai_activity unit contract
# ---------------------------------------------------------------------------


def test_record_ai_activity_accumulates_atomically_per_uid(fake_db, monkeypatch):
    import app.services.ai_service as ai_mod

    monkeypatch.setattr(ai_mod, "get_firestore", lambda: fake_db)

    for _ in range(3):
        ai_mod.record_ai_activity("u-x", "ai_chat_messages", 1)
    ai_mod.record_ai_activity("u-x", "quiz_questions", 7)
    ai_mod.record_ai_activity("u-y", "ai_chat_messages", 1)

    assert fake_db._collections["ai_usage_summary"]["u-x"]["ai_chat_messages"] == 3
    assert fake_db._collections["ai_usage_summary"]["u-x"]["quiz_questions"] == 7
    assert fake_db._collections["ai_usage_summary"]["u-y"]["ai_chat_messages"] == 1
    assert "u-y" not in str(fake_db._collections["ai_usage_summary"]["u-x"])


def test_record_ai_activity_ignores_unknown_keys_and_bad_counts(fake_db, monkeypatch):
    import app.services.ai_service as ai_mod

    monkeypatch.setattr(ai_mod, "get_firestore", lambda: fake_db)

    ai_mod.record_ai_activity("u-z", "prompt_text", 1)      # not a counter key
    ai_mod.record_ai_activity("u-z", "ai_chat_messages", 0)  # zero is a no-op
    ai_mod.record_ai_activity("", "ai_chat_messages", 1)     # missing uid

    assert fake_db._collections.get("ai_usage_summary", {}) == {}


def test_activity_summary_defaults_are_zero(fake_db, monkeypatch):
    import app.services.ai_service as ai_mod

    monkeypatch.setattr(ai_mod, "get_firestore", lambda: fake_db)
    summary = ai_mod.get_ai_activity_summary("nobody")
    assert summary["ai_chat_messages"] == 0
    assert summary["quiz_generations"] == 0
    assert summary["quiz_questions"] == 0
    assert summary["exam_rescue_plans"] == 0


# ---------------------------------------------------------------------------
# Account deletion removes the summary document
# ---------------------------------------------------------------------------


def test_account_deletion_removes_ai_usage_summary(client, fake_db, fake_auth, fake_storage):
    uid = "summary-deleter"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed("ai_usage_summary", uid, {"uid": uid, "ai_chat_messages": 9})
    fake_db.seed("ai_usage_summary", "other-user", {"uid": "other-user", "ai_chat_messages": 5})

    resp = client.delete("/api/account", headers=_auth(fake_auth, uid))
    assert resp.status_code in (200, 204), resp.text

    remaining = fake_db._collections.get("ai_usage_summary", {})
    assert uid not in remaining
    assert "other-user" in remaining, "other users' summaries must survive"


# ---------------------------------------------------------------------------
# AI-FLOAT-1.2 — Ziku language-response policy (system prompt contract)
# ---------------------------------------------------------------------------


def _chat_prompt() -> str:
    from app.services.ai_service import build_chat_system_prompt

    return build_chat_system_prompt()


def test_language_policy_banglish_input_instructs_bangla_script_reply():
    """Banglish in → Bangla-script reply; never a Banglish reply."""
    prompt = _chat_prompt()
    assert "Banglish" in prompt
    assert "always reply in Bangla script" in prompt
    assert "Never reply in Banglish" in prompt


def test_language_policy_bangla_input_replies_primarily_in_bangla():
    prompt = _chat_prompt()
    assert "Bangla script input: reply primarily in Bangla" in prompt


def test_language_policy_english_input_replies_in_english():
    prompt = _chat_prompt()
    assert "English input: reply in English" in prompt


def test_language_policy_mixed_input_keeps_english_technical_terms():
    prompt = _chat_prompt()
    assert "Mixed Bangla + English input" in prompt
    assert "natural Bangla sentence structure" in prompt
    for term in ("API", "Flutter", "optical fiber", "algorithm", "exam", "PDF"):
        assert term in prompt, f"technical term {term!r} must stay in English"
    assert "awkward Bangla translations" in prompt


def test_language_policy_explicit_banglish_request_is_allowed():
    """Only an explicit ask ('Banglish e bolo') unlocks a Banglish reply."""
    prompt = _chat_prompt()
    assert "Banglish e bolo" in prompt
    assert "explicitly asks for it" in prompt
    assert "Banglish is allowed for that response" in prompt


def test_language_policy_applies_to_every_reply_including_followups():
    prompt = _chat_prompt()
    assert "every reply, including follow-up turns" in prompt
    assert "multi-turn conversation" in prompt


@pytest.mark.asyncio
async def test_language_policy_costs_exactly_one_ai_call_per_request():
    """Language handling is prompt-only: never a second provider call."""
    from unittest.mock import MagicMock, patch

    settings = MagicMock()
    settings.groq_api_key = "g-key"
    settings.gemini_api_key = ""
    settings.openrouter_api_key = ""

    with patch("app.services.ai_service.get_settings", return_value=settings), \
         patch("app.services.ai_service._consume_quota"), \
         patch(
             "app.services.ai_service._groq_chat",
             new_callable=AsyncMock,
             return_value="ঠিক আছে, প্ল্যান করি।",
         ) as mock_chat:
        result = await ai_service_module.chat_generate(
            "uid-lang-policy",
            [{"role": "user", "content": "amar kal exam ase kivabe porbo"}],
        )

    assert result["reply"] == "ঠিক আছে, প্ল্যান করি।"
    assert mock_chat.await_count == 1, "language rules must not cost a second AI call"
    _messages, system_prompt = mock_chat.await_args.args
    assert "Never reply in Banglish" in system_prompt
    assert "English input: reply in English" in system_prompt
