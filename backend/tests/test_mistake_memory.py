"""Phase 1 — AI Mistake Memory: capture, Ziku analysis, review ladder, brain.

Covers the four contracts this phase has to keep:

1. **Capture parity.** A wrong answer recorded server-side must match what
   the quiz screen showed the student (bare-letter MCQ reference answers),
   and every wrong answer must become one durable record.
2. **One record per distinct mistake.** Re-encountering a question bumps
   ``occurrences`` and resets the review ladder instead of duplicating.
3. **Analysis is explicit.** Nothing runs in the background: the student
   triggers it, and an unavailable provider leaves mistakes pending.
4. **Learning Brain** aggregates without inventing its own mastery numbers.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import HTTPException

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.services import mistake_memory_service as mistakes  # noqa: E402


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


def _today() -> "datetime.date":
    return datetime.now(timezone.utc).date()


def _seed_student(db, uid: str, role: str = "student") -> None:
    db.seed("users", uid, {"role": role, "displayName": "Mistake Tester"})


def _quiz_payload(**overrides) -> dict:
    """Three questions: one answered correctly by letter, two wrong.

    The first mirrors the real MCQ generator shape — reference answer is the
    bare option letter while the screen stored the tapped option text.
    """
    payload = {
        "subject_id": "Physics",
        "material_id": "mat-1",
        "questions": [
            {
                "question": "Which engine reaches Carnot efficiency?",
                "topic": "Thermodynamics",
                "explanation": "A reversible engine between two reservoirs reaches Carnot efficiency.",
            },
            {
                "question": "What does entropy measure?",
                "topic": "Entropy",
                "explanation": "Entropy measures the dispersal of energy.",
            },
            {
                "question": "What is absolute zero?",
                "topic": "Temperature",
                "explanation": "Absolute zero is the lowest possible temperature.",
            },
        ],
        "user_answers": ["B. Reversible engine", "Disorder of particles", "Z"],
        "correct_answers": ["B", "Disorder of particles", "C"],
        "score": 33,
        "topic_scores": {},
        "difficulty": "medium",
        "time_spent_seconds": 60,
    }
    payload.update(overrides)
    return payload


def _save(client, fake_auth, fake_db, uid: str, **overrides) -> dict:
    resp = client.post(
        "/api/ai/quiz/save-result",
        headers=_auth(fake_auth, uid),
        json=_quiz_payload(**overrides),
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


def _mistakes(db, uid: str) -> dict[str, dict]:
    path = f"users/{uid}/mistakes"
    return dict(db._collections.get(path, {}))


# ---------------------------------------------------------------------------
# Pure helpers — these mirror the Flutter quiz screen, so they are pinned.
# ---------------------------------------------------------------------------

def test_answers_match_mirrors_flutter_letter_scoring():
    # Reference answer is the bare letter, student tapped the option text.
    assert mistakes.answers_match("B. Reversible engine", "B") is True
    assert mistakes.answers_match("b) Reversible engine", "B") is True
    assert mistakes.answers_match("B", "b") is True
    assert mistakes.answers_match("A. Wrong one", "B") is False
    # Long-form references must not be letter-matched.
    assert mistakes.answers_match("Disorder of particles", "Disorder of particles") is True
    assert mistakes.answers_match("Disorder", "Disorder of particles") is False
    # Blank submission is never a match (it is still captured as a mistake).
    assert mistakes.answers_match("", "C") is False
    assert mistakes.answers_match(None, "C") is False


def test_extract_topic_prefers_the_tagged_topic():
    assert mistakes.extract_topic({"topic": "Thermodynamics", "question": "Q"}) == "Thermodynamics"
    # Fallbacks mirror Dart's _extractTopic: first explanation sentence, then
    # the question text, both capped at 40 characters.
    assert mistakes.extract_topic(
        {"explanation": "Entropy measures dispersal of energy. Second sentence."}
    ) == "Entropy measures dispersal of energy"
    long = {"explanation": "x" * 60}
    assert mistakes.extract_topic(long) == "x" * 40
    assert mistakes.extract_topic({"question": "y" * 60}) == "y" * 40
    assert mistakes.extract_topic({}) == "General"


def test_fingerprint_is_deterministic_and_case_insensitive():
    a = mistakes.mistake_fingerprint("physics", "Thermodynamics", "What  is entropy?")
    b = mistakes.mistake_fingerprint("PHYSICS", "thermodynamics", "what is entropy?")
    assert a == b
    assert a != mistakes.mistake_fingerprint("Physics", "Entropy", "What is entropy?")
    # The wrong answer is deliberately not part of the identity.
    assert len(a) == 24


def test_review_ladder_advances_and_is_bounded():
    today = _today()
    assert mistakes.review_due_date(0, today) == (today + timedelta(days=1)).isoformat()
    assert mistakes.review_due_date(1, today) == (today + timedelta(days=3)).isoformat()
    assert mistakes.review_due_date(4, today) == (today + timedelta(days=30)).isoformat()
    # Out-of-range counts clamp to the last step rather than blowing up.
    assert mistakes.review_due_date(99, today) == (today + timedelta(days=30)).isoformat()
    assert mistakes.review_due_date(-1, today) == (today + timedelta(days=1)).isoformat()


# ---------------------------------------------------------------------------
# Capture via /api/ai/quiz/save-result
# ---------------------------------------------------------------------------

def test_save_result_captures_every_wrong_answer(client, fake_db, fake_auth):
    uid = "mistake-capture"
    _seed_student(fake_db, uid)

    body = _save(client, fake_auth, fake_db, uid)

    # The letter-reference answer must score as correct (it used to be a miss).
    assert body["totalQuestions"] == 3
    assert body["correctCount"] == 2
    assert body["mistakeCount"] == 1
    assert body["newMistakes"] == 1
    assert body["repeatedMistakes"] == 0
    # Capture only — analysis is a separate, deliberate step.
    assert body["pendingAnalysis"] == 1

    stored = _mistakes(fake_db, uid)
    assert len(stored) == 1
    record = next(iter(stored.values()))
    assert record["subjectId"] == "Physics"
    assert record["topic"] == "Temperature"
    assert record["wrongAnswer"] == "Z"
    assert record["correctAnswer"] == "C"
    assert record["occurrences"] == 1
    assert record["reviewCount"] == 0
    assert record["analysisStatus"] == "pending"
    assert record["nextReviewDate"] == (_today() + timedelta(days=1)).isoformat()
    assert record["quizId"]


def test_repeated_mistake_updates_one_record_and_resets_ladder(
    client, fake_db, fake_auth
):
    uid = "mistake-repeat"
    _seed_student(fake_db, uid)

    first = _save(client, fake_auth, fake_db, uid)
    assert first["newMistakes"] == 1

    # Advance the ladder, then get the same question wrong again.
    mistake_id = next(iter(_mistakes(fake_db, uid)))
    assert client.post(
        f"/api/ai/mistakes/{mistake_id}/review", headers=_auth(fake_auth, uid)
    ).status_code == 200
    assert _mistakes(fake_db, uid)[mistake_id]["reviewCount"] == 1

    second = _save(client, fake_auth, fake_db, uid)
    assert second["mistakeCount"] == 1
    assert second["newMistakes"] == 0
    assert second["repeatedMistakes"] == 1

    stored = _mistakes(fake_db, uid)
    assert len(stored) == 1, "the same question must not create a second record"
    record = stored[mistake_id]
    assert record["occurrences"] == 2
    assert record["reviewCount"] == 0, "a repeat resets the review ladder"
    assert record["nextReviewDate"] == (_today() + timedelta(days=1)).isoformat()


def test_save_result_never_fails_because_of_mistake_storage(
    client, fake_db, fake_auth, monkeypatch
):
    """A mistake-storage outage must not cost the student their result."""
    uid = "mistake-resilient"
    _seed_student(fake_db, uid)
    monkeypatch.setattr(
        "app.services.mistake_memory_service.capture_mistakes",
        lambda *a, **k: (_ for _ in ()).throw(RuntimeError("firestore down")),
    )

    body = _save(client, fake_auth, fake_db, uid)
    assert body["mistakeCount"] == 0
    assert body["pendingAnalysis"] == 0
    assert body["quizId"]


# ---------------------------------------------------------------------------
# Ziku analysis
# ---------------------------------------------------------------------------

def _analysis_json(today=None, review_date=None, indices=(0,)) -> str:
    today = today or _today()
    review_date = review_date or (today + timedelta(days=2)).isoformat()
    return json.dumps(
        {
            "mistakes": [
                {
                    "index": i,
                    "mistake_reason": "They confused absolute zero with 0 C.",
                    "concept_gap": "Kelvin scale vs Celsius scale.",
                    "correction_explanation": "Absolute zero is 0 K (-273.15 C), the point where particle motion stops.",
                    "memory_trick": "K for Kinetic energy at its lowest.",
                    "recommended_review_date": review_date,
                }
                for i in indices
            ]
        }
    )


async def _fake_generate(uid, prompt, feature=None, **kwargs):
    return _analysis_json()


def test_analyze_stores_ziku_analysis_and_records_activity(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-analyze"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)

    captured_prompts = []

    async def generate(user_uid, prompt, feature=None, **kwargs):
        captured_prompts.append(prompt)
        assert feature == "mistake_analysis"
        return _analysis_json()

    monkeypatch.setattr("app.services.ai_service.generate", generate)

    resp = client.post("/api/ai/mistakes/analyze", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["analyzed"] == 1
    assert body["pending"] == 0
    assert body["status"] == "ok"

    # One prompt covered the batch, and it carried the mistake itself.
    assert len(captured_prompts) == 1
    assert "What is absolute zero?" in captured_prompts[0]
    assert f"TODAY'S DATE: {_today().isoformat()}" in captured_prompts[0]

    record = next(iter(_mistakes(fake_db, uid).values()))
    assert record["analysisStatus"] == "analyzed"
    assert record["analysisSource"] == "ai"
    analysis = record["analysis"]
    assert analysis["conceptGap"] == "Kelvin scale vs Celsius scale."
    assert analysis["recommendedReviewDate"] == (_today() + timedelta(days=2)).isoformat()
    assert record["nextReviewDate"] == (_today() + timedelta(days=2)).isoformat()

    # Lifetime activity counter must reflect the AI-authored analyses.
    usage = fake_db._collections.get("ai_usage_summary", {}).get(uid, {})
    assert usage.get("mistake_analyses") == 1


def test_analyze_rejects_ai_dates_outside_the_window(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-bad-date"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)

    async def generate(user_uid, prompt, feature=None, **kwargs):
        # Both a far-future date and garbage: neither may move the schedule.
        return json.dumps(
            {"mistakes": [{"index": 0, "recommended_review_date": "2099-01-01",
                           "mistake_reason": "r", "concept_gap": "g",
                           "correction_explanation": "c", "memory_trick": "m"}]}
        )

    monkeypatch.setattr("app.services.ai_service.generate", generate)
    assert client.post("/api/ai/mistakes/analyze", headers=_auth(fake_auth, uid)).status_code == 200

    record = next(iter(_mistakes(fake_db, uid).values()))
    assert record["analysis"]["recommendedReviewDate"] == ""
    assert record["nextReviewDate"] == (_today() + timedelta(days=1)).isoformat()


def test_analyze_never_moves_an_already_due_mistake_out_of_the_queue(
    fake_db, fake_auth, client, monkeypatch
):
    uid = "mistake-due"
    _seed_student(fake_db, uid)
    due_today = _today().isoformat()
    path = f"users/{uid}/mistakes"
    fake_db._collections[path] = {
        "ms_due": {
            "ownerId": uid,
            "subjectId": "Physics",
            "topic": "Temperature",
            "question": "What is absolute zero?",
            "wrongAnswer": "Z",
            "correctAnswer": "C",
            "occurrences": 1,
            "reviewCount": 0,
            "nextReviewDate": due_today,
            "analysisStatus": "pending",
            "analysis": None,
        }
    }

    async def generate(user_uid, prompt, feature=None, **kwargs):
        return _analysis_json(indices=(0,))

    monkeypatch.setattr("app.services.ai_service.generate", generate)
    resp = client.post("/api/ai/mistakes/analyze", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text

    record = _mistakes(fake_db, uid)["ms_due"]
    assert record["analysisStatus"] == "analyzed"
    assert record["nextReviewDate"] == due_today, (
        "analysing a due mistake must not quietly postpone the revision"
    )


def test_provider_failure_keeps_mistakes_pending(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-provider-down"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)

    async def generate(user_uid, prompt, feature=None, **kwargs):
        raise HTTPException(status_code=503, detail="All AI providers failed")

    monkeypatch.setattr("app.services.ai_service.generate", generate)

    resp = client.post("/api/ai/mistakes/analyze", headers=_auth(fake_auth, uid))
    assert resp.status_code == 503, resp.text
    record = next(iter(_mistakes(fake_db, uid).values()))
    assert record["analysisStatus"] == "pending", (
        "a failed analysis must stay retryable"
    )
    usage = fake_db._collections.get("ai_usage_summary", {}).get(uid, {})
    assert usage.get("mistake_analyses", 0) == 0


def test_unparsable_ai_reply_stores_nothing_and_reports_it(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-unparsable"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)

    async def generate(user_uid, prompt, feature=None, **kwargs):
        return "Sorry, I cannot help with that."

    monkeypatch.setattr("app.services.ai_service.generate", generate)

    resp = client.post("/api/ai/mistakes/analyze", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    assert resp.json()["analyzed"] == 0
    assert resp.json()["status"] == "no_analysis"
    record = next(iter(_mistakes(fake_db, uid).values()))
    assert record["analysisStatus"] == "pending"


def test_analyze_with_nothing_pending_costs_no_ai_request(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-nothing"
    _seed_student(fake_db, uid)

    async def generate(user_uid, prompt, feature=None, **kwargs):
        raise AssertionError("no AI call should happen with an empty queue")

    monkeypatch.setattr("app.services.ai_service.generate", generate)
    resp = client.post("/api/ai/mistakes/analyze", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"analyzed": 0, "pending": 0, "failed": 0, "status": "empty"}


def test_analysis_batch_is_bounded(client, fake_db, fake_auth, monkeypatch):
    uid = "mistake-batch"
    _seed_student(fake_db, uid)
    path = f"users/{uid}/mistakes"
    today = _today().isoformat()
    fake_db._collections[path] = {
        f"ms_{i}": {
            "ownerId": uid,
            "topic": "Topic",
            "question": f"Question {i}",
            "wrongAnswer": "Z",
            "correctAnswer": "C",
            "occurrences": 1,
            "reviewCount": 0,
            "nextReviewDate": today,
            "analysisStatus": "pending",
            "analysis": None,
        }
        for i in range(10)
    }

    seen = []

    async def generate(user_uid, prompt, feature=None, **kwargs):
        seen.append(prompt)
        return _analysis_json(indices=tuple(range(5)))

    monkeypatch.setattr("app.services.ai_service.generate", generate)
    resp = client.post(
        "/api/ai/mistakes/analyze?limit=5", headers=_auth(fake_auth, uid)
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["analyzed"] == 5
    assert resp.json()["pending"] == 5
    assert len(seen) == 1


# ---------------------------------------------------------------------------
# Learning Brain
# ---------------------------------------------------------------------------

def test_learning_brain_aggregates_totals_and_revision_queue(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-brain"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)
    _save(client, fake_auth, fake_db, uid)  # same question again -> repeat

    path = f"users/{uid}/mistakes"
    # A second, already-analysed mistake that is due for revision today.
    fake_db._collections.setdefault(path, {})["ms_old"] = {
        "ownerId": uid,
        "subjectId": "Chemistry",
        "topic": "Entropy",
        "question": "What does entropy measure?",
        "wrongAnswer": "Disorder of particles",
        "correctAnswer": "Disorder of particles",
        "occurrences": 3,
        "reviewCount": 4,
        "nextReviewDate": _today().isoformat(),
        "analysisStatus": "analyzed",
        "analysis": {"conceptGap": "g", "mistakeReason": "r",
                     "correctionExplanation": "c", "memoryTrick": "m",
                     "recommendedReviewDate": ""},
    }

    monkeypatch.setattr(
        "app.services.weak_topic_service.get_weak_topics",
        lambda uid, threshold=60: [
            {"topic": "Temperature", "average_score": 40, "attempts": 2,
             "recommendation": "Revise the Kelvin scale"}
        ],
    )

    resp = client.get("/api/ai/mistakes/brain", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["totalMistakes"] == 2
    assert body["totalOccurrences"] == 5  # Temperature missed twice + Entropy thrice
    assert body["repeatedCount"] == 2
    assert body["analyzedCount"] == 1
    assert body["pendingAnalysis"] == 1
    assert body["revisionDueCount"] == 1
    assert body["nextReviewDate"] == _today().isoformat()

    # Weak topics come from quiz mastery, enriched with mistake counts.
    weak = {w["topic"]: w for w in body["weakTopics"]}
    assert "Temperature" in weak
    assert weak["Temperature"]["averageScore"] == 40
    assert weak["Temperature"]["mistakes"] == 1
    assert weak["Temperature"]["recommendation"] == "Revise the Kelvin scale"
    # The mistake-only topic is folded in rather than dropped.
    assert "Entropy" in weak
    assert weak["Entropy"]["mistakes"] == 1

    assert [m["topic"] for m in body["revisionDue"]] == ["Entropy"]
    assert [m["topic"] for m in body["repeatedMistakes"]][0] == "Entropy"
    assert {s["subjectId"] for s in body["subjectBreakdown"]} == {"Physics", "Chemistry"}


def test_learning_brain_survives_weak_topic_lookup_failure(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-brain-degraded"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)

    def failing(uid, threshold=60):
        raise RuntimeError("firestore down")

    monkeypatch.setattr(
        "app.services.weak_topic_service.get_weak_topics", failing
    )

    resp = client.get("/api/ai/mistakes/brain", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    assert resp.json()["totalMistakes"] == 1


def test_empty_brain_is_an_honest_empty_state(client, fake_db, fake_auth):
    uid = "mistake-brain-empty"
    _seed_student(fake_db, uid)

    resp = client.get("/api/ai/mistakes/brain", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["totalMistakes"] == 0
    assert body["weakTopics"] == []
    assert body["revisionDue"] == []
    assert body["nextReviewDate"] is None
    assert body["subjectBreakdown"] == []


# ---------------------------------------------------------------------------
# Review ladder + list filters
# ---------------------------------------------------------------------------

def test_review_marks_advance_the_spaced_ladder(client, fake_db, fake_auth):
    uid = "mistake-review"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)
    mistake_id = next(iter(_mistakes(fake_db, uid)))

    first = client.post(
        f"/api/ai/mistakes/{mistake_id}/review", headers=_auth(fake_auth, uid)
    )
    assert first.status_code == 200, first.text
    assert first.json()["reviewCount"] == 1
    assert first.json()["nextReviewDate"] == (_today() + timedelta(days=3)).isoformat()

    second = client.post(
        f"/api/ai/mistakes/{mistake_id}/review", headers=_auth(fake_auth, uid)
    )
    assert second.json()["nextReviewDate"] == (_today() + timedelta(days=7)).isoformat()


def test_review_of_an_unknown_mistake_is_404(client, fake_db, fake_auth):
    uid = "mistake-review-missing"
    _seed_student(fake_db, uid)
    resp = client.post(
        "/api/ai/mistakes/ms_does_not_exist/review", headers=_auth(fake_auth, uid)
    )
    assert resp.status_code == 404, resp.text


def test_list_filters_and_rejects_unknown_status(client, fake_db, fake_auth):
    uid = "mistake-list"
    _seed_student(fake_db, uid)
    _save(client, fake_auth, fake_db, uid)

    resp = client.get("/api/ai/mistakes", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    assert resp.json()["count"] == 1

    assert client.get(
        "/api/ai/mistakes?status=pending", headers=_auth(fake_auth, uid)
    ).json()["count"] == 1
    assert client.get(
        "/api/ai/mistakes?status=due", headers=_auth(fake_auth, uid)
    ).json()["count"] == 0

    bad = client.get("/api/ai/mistakes?status=everything", headers=_auth(fake_auth, uid))
    assert bad.status_code == 400, bad.text


# ---------------------------------------------------------------------------
# Access control + quota wiring
# ---------------------------------------------------------------------------

def test_mistake_endpoints_require_a_student(client, fake_db, fake_auth):
    uid = "mistake-general"
    _seed_student(fake_db, uid, role="general")
    headers = _auth(fake_auth, uid)

    assert client.get("/api/ai/mistakes", headers=headers).status_code == 403
    assert client.get("/api/ai/mistakes/brain", headers=headers).status_code == 403
    assert client.post("/api/ai/mistakes/analyze", headers=headers).status_code == 403
    assert client.post(
        "/api/ai/mistakes/ms_anything/review", headers=headers
    ).status_code == 403


def test_mistakes_are_scoped_to_the_signed_in_student(client, fake_db, fake_auth):
    owner = "mistake-owner"
    other = "mistake-intruder"
    _seed_student(fake_db, owner)
    _seed_student(fake_db, other)
    _save(client, fake_auth, fake_db, owner)

    body = client.get(
        "/api/ai/mistakes", headers=_auth(fake_auth, other)
    ).json()
    assert body["count"] == 0, "one student must never see another's mistakes"

    # An id from someone else's subcollection is a 404, not a read.
    stolen_id = next(iter(_mistakes(fake_db, owner)))
    assert client.post(
        f"/api/ai/mistakes/{stolen_id}/review", headers=_auth(fake_auth, other)
    ).status_code == 404


def test_mistake_analysis_has_its_own_quota_feature():
    from app.core.config import get_settings
    from app.services.ai_service import _get_feature_limit, AiFeature

    limit, period = _get_feature_limit(AiFeature.MISTAKE)
    assert period == "daily"
    assert limit == get_settings().ai_limit_mistake_daily


# ---------------------------------------------------------------------------
# Exam Rescue integration
# ---------------------------------------------------------------------------

def test_exam_rescue_prompt_prioritises_recorded_mistakes(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "mistake-rescue"
    _seed_student(fake_db, uid)
    import app.routers.ai_study as ai_study_mod

    monkeypatch.setattr("app.routers.ai_study.get_firestore", lambda: fake_db)
    _save(client, fake_auth, fake_db, uid)

    captured = []

    async def mock_generate(user_uid, prompt, feature=None):
        captured.append(prompt)
        return json.dumps({
            "exam_title": "Physics",
            "days_remaining": 1,
            "total_estimated_minutes": 60,
            "strategy_summary": "Focused rescue.",
            "days": [{
                "day_number": 1,
                "date_offset": 0,
                "theme": "Cram",
                "target_minutes": 60,
                "items": [{"title": "Review", "type": "study",
                           "estimated_minutes": 60, "material_id": "",
                           "action_note": "focus"}],
            }],
        })

    monkeypatch.setattr(ai_study_mod, "_call_generate", mock_generate)

    resp = client.post(
        "/api/ai/exam-rescue/plan",
        headers=_auth(fake_auth, uid),
        json={
            "exam_title": "Physics",
            "exam_date": (datetime.now(timezone.utc) + timedelta(days=3)).isoformat(),
        },
    )
    assert resp.status_code == 200, resp.text
    assert len(captured) == 1
    assert "STUDENT'S RECORDED MISTAKES (PRIORITIZE THESE TOO)" in captured[0]
    assert "Temperature" in captured[0]
