"""Phase 3 — AI Real Exam Simulator tests.

Covers the five endpoints (``/api/exams/create``, ``/upload``, ``/{id}``,
``/{id}/start``, ``/{id}/submit``, ``/{id}/analysis``) and the four things
they promise:

* the hall is server-graded — questions leave without answers, results are
  written only by the backend, and re-submitting conflicts;
* the marks model from the spec (50 questions / 100 marks / +2 correct /
  -0.25 wrong / 0 skip) is computed, not assumed;
* submitting lands in the Quiz system, Mistake Memory and Academic Health;
* the analysis screen has score, accuracy, time management, weak topics,
  mistake counts and Ziku's three-day plan.

Every test runs against the real FastAPI app through the shared ``client``
fixture (FakeFirestore + FakeAuth); the AI is replaced per-test by patching
the service's single ``_ai_generate`` seam.
"""

from __future__ import annotations

import json
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402
from app.services import exam_simulator_service as exam_mod  # noqa: E402
from app.services.ai_service import AiFeature  # noqa: E402


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
UID = "exam-student"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _auth(fake_auth, uid: str = UID) -> dict[str, str]:
    return bearer(fake_auth.issue(uid))


def _student(fake_db, fake_auth, uid: str = UID):
    seed_profile(fake_db, uid)
    return _auth(fake_auth, uid)


def _paper_questions() -> list[dict]:
    """Four questions across two topics — two right, one blank, one wrong."""
    return [
        {
            "question": "Which colour does a prism split white light into?",
            "type": "mcq",
            "options": ["Spectrum", "Shadow", "Sound", "Smoke"],
            "correct": "A",
            "topic": "Optics",
            "explanation": "Dispersion spreads white light into a spectrum.",
        },
        {
            "question": "The speed of light in vacuum is closest to:",
            "type": "mcq",
            "options": ["3 x 10^8 m/s", "3 x 10^6 m/s", "3 x 10^5 m/s", "None"],
            "correct": "B",
            "topic": "Optics",
            "explanation": "c is about 3 x 10^8 metres per second.",
        },
        {
            "question": "Calculate 2 + 2.",
            "type": "numerical",
            "options": [],
            "correct": "4",
            "topic": "Mechanics",
            "explanation": "Simple addition.",
        },
        {
            "question": "State the formula for momentum.",
            "type": "mcq",
            "options": ["p = mv", "F = ma", "E = mc^2", "V = IR"],
            "correct": "A",
            "topic": "Mechanics",
            "explanation": "Momentum is mass times velocity.",
        },
    ]


def _mcq_paper(count: int, topic: str = "Optics") -> list[dict]:
    """A uniform N-question paper — the shape mark maths is tested against."""
    return [
        {
            "question": f"Question {i + 1}?",
            "type": "mcq",
            "options": ["Yes", "No", "Maybe", "Later"],
            "correct": "A",
            "topic": topic,
            "explanation": "Because.",
        }
        for i in range(count)
    ]


def _payload(**overrides) -> dict:
    body = {
        "subject": "Physics",
        "source": "upload",
        "questionCount": 4,
        "totalMarks": 100.0,
        "timeLimitMinutes": 60,
        "negativeMarking": {"enabled": True, "penalty": 0.25},
        "difficulty": "real_exam",
        "topic": "Optics",
        "title": "Physics mock 1",
        "questions": _paper_questions(),
    }
    body.update(overrides)
    return body


def _create(client, auth, **overrides) -> dict:
    resp = client.post("/api/exams/create", json=_payload(**overrides), headers=auth)
    assert resp.status_code == 200, resp.text
    return resp.json()


def _start(client, auth, exam_id: str) -> dict:
    resp = client.post(f"/api/exams/{exam_id}/start", headers=auth)
    assert resp.status_code == 200, resp.text
    return resp.json()


def _submit(client, auth, exam_id: str, attempt_id: str, **extra) -> dict:
    body = {
        "attemptId": attempt_id,
        # 2 right, 2 wrong, none blank — the default paper for score maths
        "answers": ["A", "B", "1", "Z"],
        "timeSpentSeconds": 900,
        "withAiAnalysis": False,
    }
    body.update(extra)
    resp = client.post(f"/api/exams/{exam_id}/submit", json=body, headers=auth)
    assert resp.status_code == 200, resp.text
    return resp.json()


def _install_ai(monkeypatch, payload, calls=None):
    """Replace the service's single AI seam with a canned reply."""

    async def _fake(uid, prompt, feature=None):
        if calls is not None:
            calls.append({"uid": uid, "feature": feature, "prompt": prompt})
        if isinstance(payload, Exception):
            raise payload
        if callable(payload):
            result = payload(prompt)
            return json.dumps(result) if isinstance(result, dict) else result
        return payload if isinstance(payload, str) else json.dumps(payload)

    monkeypatch.setattr(exam_mod, "_ai_generate", _fake)


# ---------------------------------------------------------------------------
# create
# ---------------------------------------------------------------------------
def test_create_requires_a_signed_in_student(client, fake_auth):
    resp = client.post("/api/exams/create", json={"subject": "Physics"})
    assert resp.status_code in (401, 403)


def test_create_rejects_general_role(client, fake_db, fake_auth):
    token = fake_auth.issue("general-user")
    seed_profile(fake_db, "general-user", role="general")
    resp = client.post(
        "/api/exams/create",
        json={"subject": "Physics"},
        headers=bearer(token),
    )
    assert resp.status_code == 403, resp.text


def test_create_stores_exam_and_questions(client, fake_db, fake_auth):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)

    assert exam["examId"]
    assert exam["subject"] == "Physics"
    assert exam["source"] == "upload"
    assert exam["questionCount"] == 4
    # 100 marks / 4 questions → 25 each, and the spec's default penalty
    assert exam["totalMarks"] == 100.0
    assert exam["correctMarks"] == 25.0
    assert exam["penalty"] == 0.25
    assert exam["negativeMarking"] is True

    stored = fake_db._collections[f"users/{UID}/exams/{exam['examId']}/exam_questions"]
    assert len(stored) == 4
    assert stored["q_000"]["topic"] == "Optics"
    assert stored["q_002"]["correct"] == "4"

    # questions are redacted on the way out: no answers, no explanations
    for question in exam["questions"]:
        assert "correct" not in question
        assert "explanation" not in question
        assert question["options"] or question["type"] != "mcq"


def test_create_marks_follow_the_spec_example(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    questions = [
        {
            "question": f"Question {i}?",
            "type": "mcq",
            "options": ["Yes", "No", "Maybe", "Later"],
            "correct": "A",
            "topic": "Optics",
        }
        for i in range(50)
    ]
    exam = _create(
        client,
        auth,
        questionCount=50,
        totalMarks=100,
        questions=questions,
    )
    assert exam["correctMarks"] == 2.0
    assert exam["totalMarks"] == 100.0
    assert exam["penalty"] == 0.25


def test_create_correct_marks_can_override_the_total(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    exam = _create(
        client,
        auth,
        questionCount=5,
        totalMarks=100,
        correctMarks=2,
        questions=_mcq_paper(5),
    )
    # the achievable maximum follows the per-question value, not the label
    assert exam["correctMarks"] == 2.0
    assert exam["totalMarks"] == 10.0


def test_create_negative_marking_off_means_no_penalty(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth, negativeMarking={"enabled": False})
    assert exam["negativeMarking"] is False
    assert exam["penalty"] == 0.0


def test_create_rejects_a_question_without_an_answer(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    body = _payload()
    body["questions"][1] = {
        "question": "Unanswerable?",
        "type": "mcq",
        "options": ["A", "B"],
        "correct": "",
        "topic": "Optics",
    }
    resp = client.post("/api/exams/create", json=body, headers=auth)
    assert resp.status_code == 400
    assert "correct answer" in resp.json()["detail"]


def test_create_validates_difficulty_and_count(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    assert (
        client.post(
            "/api/exams/create",
            json=_payload(difficulty="nightmare"),
            headers=auth,
        ).status_code
        == 400
    )
    assert (
        client.post(
            "/api/exams/create",
            json=_payload(questionCount=0),
            headers=auth,
        ).status_code
        == 422
    )


def test_create_ai_source_generates_questions(client, fake_auth, fake_db, monkeypatch):
    auth = _student(fake_db, fake_auth)
    calls = []
    _install_ai(
        monkeypatch,
        {
            "questions": [
                {
                    "question": "What is refraction?",
                    "type": "mcq",
                    "options": ["Bending", "Reflection", "Absorption", "None"],
                    "correct": "A",
                    "topic": "Optics",
                    "explanation": "Light bends when it changes medium.",
                },
                {
                    "question": "Define work.",
                    "type": "short_answer",
                    "correct": "Force times displacement",
                    "topic": "Mechanics",
                    "explanation": "Work is force over distance.",
                },
            ]
        },
        calls=calls,
    )

    exam = _create(client, auth, source="ai", questions=None, questionCount=2)
    assert exam["source"] == "ai"
    assert exam["questionCount"] == 2
    assert calls and calls[0]["feature"] == AiFeature.QUIZ
    assert "Physics" in calls[0]["prompt"]

    stored = fake_db._collections[f"users/{UID}/exams/{exam['examId']}/exam_questions"]
    assert stored["q_000"]["correct"] == "A"


def test_create_ai_failure_asks_for_an_uploaded_paper(
    client, fake_auth, fake_db, monkeypatch
):
    auth = _student(fake_db, fake_auth)
    _install_ai(monkeypatch, RuntimeError("quota exhausted"))
    resp = client.post(
        "/api/exams/create",
        json=_payload(source="ai", questions=None),
        headers=auth,
    )
    assert resp.status_code == 502
    assert "upload" in resp.json()["detail"].lower()


def test_create_saved_questions_come_from_quiz_results(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    stamp = _now()
    fake_db.seed(
        f"users/{UID}/quiz_results",
        "quiz-saved-1",
        {
            "ownerId": UID,
            "subjectId": "Physics",
            "score": 60,
            "topicScores": {"Optics": 60},
            "questions": [
                {"question": "Saved question?", "type": "mcq", "options": ["x", "y", "z", "w"]},
            ],
            "correctAnswers": ["A"],
            "createdAt": stamp,
            "dayKey": stamp.strftime("%Y-%m-%d"),
        },
    )
    exam = _create(client, auth, source="saved", questions=None, questionCount=1)
    assert exam["source"] == "saved"
    assert exam["questionCount"] == 1
    assert exam["questions"][0]["question"] == "Saved question?"


def test_create_saved_without_any_quiz_404(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    resp = client.post(
        "/api/exams/create",
        json=_payload(source="saved", questions=None),
        headers=auth,
    )
    assert resp.status_code == 404


def test_create_copies_another_exam(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    first = _create(client, auth)
    copy = _create(
        client,
        auth,
        source="saved",
        sourceExamId=first["examId"],
        questions=None,
        questionCount=4,
    )
    assert copy["examId"] != first["examId"]
    assert copy["questionCount"] == 4
    assert copy["source"] == "saved"


# ---------------------------------------------------------------------------
# upload
# ---------------------------------------------------------------------------
def test_upload_text_paper_uses_the_ai_parser(client, fake_auth, fake_db, monkeypatch):
    auth = _student(fake_db, fake_auth)
    calls = []
    _install_ai(
        monkeypatch,
        {
            "questions": [
                {
                    "question": "1. What is Snell's law?",
                    "type": "mcq",
                    "options": ["n1 sin i = n2 sin r", "F = ma", "E = mc^2", "p = mv"],
                    "correct": "A",
                    "topic": "Optics",
                    "marks": 2,
                    "needsReview": False,
                }
            ]
        },
        calls=calls,
    )
    resp = client.post(
        "/api/exams/upload",
        files={"file": ("paper.txt", b"1. What is Snell's law?\nA) n1 sin i = n2 sin r\nB) F = ma", "text/plain")},
        data={"subject": "Physics", "questionCount": "10"},
        headers=auth,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["parser"] == "ai"
    assert body["textSource"] == "text"
    assert body["questionCount"] == 1
    assert body["questions"][0]["correct"] == "A"
    assert body["needsReview"] == []
    assert calls and calls[0]["feature"] == AiFeature.QUIZ


def test_upload_falls_back_to_the_line_parser(client, fake_auth, fake_db, monkeypatch):
    auth = _student(fake_db, fake_auth)
    _install_ai(monkeypatch, RuntimeError("provider down"))
    paper = (
        "1. What is Snell's law?\n"
        "A) n1 sin i = n2 sin r\n"
        "B) F = ma\n"
        "C) E = mc2\n"
        "D) p = mv\n"
        "2. State the law of reflection.\n"
        "A) angle i = angle r\n"
        "B) always 45 degrees\n"
    ).encode()
    resp = client.post(
        "/api/exams/upload",
        files={"file": ("paper.txt", paper, "text/plain")},
        data={"subject": "Physics"},
        headers=auth,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["parser"] == "line_parser"
    assert body["questionCount"] == 2
    assert body["questions"][0]["options"] == [
        "n1 sin i = n2 sin r",
        "F = ma",
        "E = mc2",
        "p = mv",
    ]
    # the line parser has no answer key, so the drafts are flagged for review
    assert body["needsReview"]
    assert body["warnings"]


def test_upload_reads_pdf_text(client, fake_auth, fake_db, monkeypatch):
    auth = _student(fake_db, fake_auth)
    _install_ai(monkeypatch, {"questions": []})
    resp = client.post(
        "/api/exams/upload",
        files={"file": ("paper.pdf", b"%PDF-1.4 fake", "application/pdf")},
        data={"subject": "Physics"},
        headers=auth,
    )
    # the fixture PDF yields text but the AI returned nothing → line parser
    assert resp.status_code == 200, resp.text
    assert resp.json()["textSource"] == "pdf_text"


def test_upload_rejects_unsupported_types(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    resp = client.post(
        "/api/exams/upload",
        files={"file": ("sheet.xlsx", b"PK\x03\x04", "application/vnd.ms-excel")},
        headers=auth,
    )
    assert resp.status_code == 415


def test_upload_rejects_an_empty_file(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    resp = client.post(
        "/api/exams/upload",
        files={"file": ("paper.txt", b"", "text/plain")},
        headers=auth,
    )
    assert resp.status_code == 400


def test_upload_rejects_oversized_files(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    blob = b"a" * (10 * 1024 * 1024 + 1)
    resp = client.post(
        "/api/exams/upload",
        files={"file": ("huge.txt", blob, "text/plain")},
        headers=auth,
    )
    assert resp.status_code == 413


def test_upload_with_no_readable_text_422(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    resp = client.post(
        "/api/exams/upload",
        files={"file": ("paper.txt", b"tiny", "text/plain")},
        headers=auth,
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# exam detail + hall
# ---------------------------------------------------------------------------
def test_get_exam_never_leaks_answers(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    resp = client.get(
        f"/api/exams/{exam['examId']}",
        params={"includeQuestions": "true"},
        headers=auth,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["examId"] == exam["examId"]
    assert len(body["questions"]) == 4
    for question in body["questions"]:
        assert "correct" not in question
        assert "explanation" not in question
    assert body["attempts"] == []


def test_list_exams_returns_newest_first(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    first = _create(client, auth)
    # datetime.now() only advances every ~15ms on Windows, so two creates in
    # the same clock tick share a createdAt and the fake query - like real
    # Firestore with tied sort keys - returns them in either order. Sleep past
    # one tick so "newest first" means something.
    time.sleep(0.03)
    second = _create(client, auth, title="Second paper")
    resp = client.get("/api/exams", headers=auth)
    assert resp.status_code == 200
    ids = [item["examId"] for item in resp.json()["exams"]]
    assert set(ids) == {first["examId"], second["examId"]}
    assert ids[0] == second["examId"]


def test_start_attempt_opens_the_hall_without_answers(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])

    assert hall["attemptId"]
    assert hall["timeLimitSeconds"] == 3600
    assert hall["totalMarks"] == 100.0
    assert hall["deadlineAt"] is not None
    started = datetime.fromisoformat(str(hall["startedAt"]).replace("Z", "+00:00"))
    deadline = datetime.fromisoformat(str(hall["deadlineAt"]).replace("Z", "+00:00"))
    assert (deadline - started).total_seconds() == 3600

    assert len(hall["questions"]) == 4
    for question in hall["questions"]:
        assert set(question) >= {"index", "question", "type", "options", "topic", "marks"}
        assert "correct" not in question
        assert "explanation" not in question

    attempts = fake_db._collections[f"users/{UID}/exam_attempts"]
    assert attempts[hall["attemptId"]]["status"] == "running"


def test_start_unknown_exam_404(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    assert client.post("/api/exams/nope/start", headers=auth).status_code == 404
    assert client.get("/api/exams/nope", headers=auth).status_code == 404
    assert client.get("/api/exams/nope/analysis", headers=auth).status_code == 404


# ---------------------------------------------------------------------------
# submit
# ---------------------------------------------------------------------------
def test_submit_scores_marks_accuracy_and_weak_topics(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])

    result = _submit(
        client,
        auth,
        exam["examId"],
        hall["attemptId"],
        timeSpentSeconds=900,  # 15 of 60 minutes
    )

    # 2 correct × 25 − 0.25 for each wrong answer, 0 for a blank
    assert result["score"] == 49.5
    assert result["totalMarks"] == 100.0
    assert result["percentage"] == 49.5
    assert result["correctCount"] == 2
    assert result["wrongCount"] == 2
    assert result["skippedCount"] == 0
    assert result["accuracy"] == 50.0
    assert result["timeManagement"] == "good"
    assert result["timeManagementLabel"] == "Good"
    # Mechanics: both attempts wrong → 0%, the only weak topic
    assert result["topicScores"]["Optics"] == 100
    assert result["topicScores"]["Mechanics"] == 0
    assert result["weakTopics"] == ["Mechanics"]
    assert result["mistakeCount"] == 2
    assert "correct" not in result


def test_submit_counts_blanks_and_softens_the_time_grade(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])

    result = _submit(
        client,
        auth,
        exam["examId"],
        hall["attemptId"],
        answers=["A", "B", "", ""],
        timeSpentSeconds=900,
    )
    # nothing deducted for the two blanks, and half the paper left undone is
    # no longer a "Good" use of the hour
    assert result["score"] == 50.0
    assert result["correctCount"] == 2
    assert result["skippedCount"] == 2
    assert result["accuracy"] == 100.0
    assert result["timeManagement"] == "poor"
    assert result["timeManagementLabel"] == "Needs work"
    assert "2 unanswered" in result["timeManagementDetail"]


def test_submit_writes_a_quiz_result_and_captures_mistakes(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    result = _submit(client, auth, exam["examId"], hall["attemptId"])

    quizzes = fake_db._collections[f"users/{UID}/quiz_results"]
    assert len(quizzes) == 1
    quiz = next(iter(quizzes.values()))
    assert quiz["examId"] == exam["examId"]
    assert quiz["subjectId"] == "Physics"
    assert quiz["score"] == 50  # percentage, the shape health reads
    assert quiz["topicScores"] == {"Optics": 100, "Mechanics": 0}
    assert quiz["totalQuestions"] == 4

    mistakes = fake_db._collections.get(f"users/{UID}/mistakes") or {}
    assert len(mistakes) == 2  # the wrong MCQ and the blank-free wrong one
    stored = list(mistakes.values())
    assert {row["topic"] for row in stored} == {"Mechanics"}
    assert all(row["quizId"] for row in stored)
    assert result["newMistakes"] == 2
    assert result["pendingAnalysis"] == 2


def test_submit_mistake_types_and_review_schedule(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    # wrong on every question: numerical → calculation, "State the ..." →
    # memory, the other two default to concept
    result = _submit(
        client,
        auth,
        exam["examId"],
        hall["attemptId"],
        answers=["Z", "Y", "1", "Z"],
    )

    assert result["mistakeCount"] == 4
    kinds = {row["index"]: row["type"] for row in result["mistakes"]}
    assert kinds[2] == "calculation"
    assert kinds[3] == "memory"
    assert kinds[0] == "concept"

    ladder = result["mistakes"][0]["reviewDates"]
    assert len(ladder) == 3
    today = _now().date()
    assert ladder[0] == (today + timedelta(days=1)).isoformat()
    assert ladder[1] == (today + timedelta(days=7)).isoformat()
    assert ladder[2] == (today + timedelta(days=30)).isoformat()

    # per-type rollup for the result screen
    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    types = {row["type"]: row["count"] for row in resp.json()["mistakeTypes"]}
    assert types == {"concept": 2, "calculation": 1, "memory": 1}


def test_submit_without_negative_marking_awards_zero_for_wrong(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth, negativeMarking={"enabled": False})
    hall = _start(client, auth, exam["examId"])
    result = _submit(client, auth, exam["examId"], hall["attemptId"])
    # 2 right × 25 + 1 wrong (0) + 1 blank (0)
    assert result["score"] == 50.0


def test_submit_conflicts_when_already_submitted(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    resp = client.post(
        f"/api/exams/{exam['examId']}/submit",
        json={"attemptId": hall["attemptId"], "answers": []},
        headers=auth,
    )
    assert resp.status_code == 409


def test_submit_rejects_a_foreign_attempt(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    other = _create(client, auth, title="Second paper")
    hall = _start(client, auth, other["examId"])

    resp = client.post(
        f"/api/exams/{exam['examId']}/submit",
        json={"attemptId": hall["attemptId"], "answers": []},
        headers=auth,
    )
    assert resp.status_code == 400


def test_submit_unknown_attempt_404(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    resp = client.post(
        f"/api/exams/{exam['examId']}/submit",
        json={"attemptId": "ghost", "answers": []},
        headers=auth,
    )
    assert resp.status_code == 404


def test_submit_generates_and_caches_the_ziku_analysis(
    client, fake_auth, fake_db, monkeypatch
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])

    calls = []
    _install_ai(
        monkeypatch,
        lambda prompt: "Optics chapter e 40% bhul.\nDay 1: Review Total Internal Reflection",
        calls=calls,
    )
    result = _submit(
        client,
        auth,
        exam["examId"],
        hall["attemptId"],
        withAiAnalysis=True,
    )
    assert "Total Internal Reflection" in result["zikuAnalysis"]
    assert result["mistakeCount"] == 2
    assert any(call["feature"] == AiFeature.CHAT for call in calls)

    # second read costs no AI call — the paragraph lives on the result
    before = len(calls)
    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    assert resp.status_code == 200
    assert resp.json()["hasAiAnalysis"] is True
    assert len(calls) == before


def test_analysis_can_generate_the_ai_paragraph_on_demand(
    client, fake_auth, fake_db, monkeypatch
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"], withAiAnalysis=False)

    calls = []
    _install_ai(monkeypatch, "Your three-day plan starts now.", calls=calls)
    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"], "withAi": "true"},
        headers=auth,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["hasAiAnalysis"] is True
    assert body["zikuAnalysis"] == "Your three-day plan starts now."
    assert len(calls) == 1

    # cached: a plain read does not call the model again
    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"], "withAi": "true"},
        headers=auth,
    )
    assert resp.json()["hasAiAnalysis"] is True
    assert len(calls) == 1


def test_submit_survives_a_failed_ai_analysis(client, fake_auth, fake_db, monkeypatch):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _install_ai(monkeypatch, RuntimeError("quota"))

    result = _submit(
        client,
        auth,
        exam["examId"],
        hall["attemptId"],
        withAiAnalysis=True,
    )
    assert result["zikuAnalysis"] == ""
    assert result["zikuPlan"]["days"]  # the deterministic plan still ships


# ---------------------------------------------------------------------------
# analysis
# ---------------------------------------------------------------------------
def test_analysis_reports_every_result_screen_field(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    assert resp.status_code == 200
    body = resp.json()

    assert body["score"] == 49.5
    assert body["accuracy"] == 50.0
    assert body["timeManagementLabel"] == "Good"
    assert body["weakTopics"] == ["Mechanics"]
    assert body["mistakeCount"] == 2
    assert body["weakTopicDetails"][0]["topic"] == "Mechanics"
    assert body["weakTopicDetails"][0]["action"]
    assert body["mistakesSaved"]["saved"] == 2
    assert body["mistakesSaved"]["reviewDates"]
    assert body["zikuPlan"]["subject"] == "Physics"
    assert [step["day"] for step in body["zikuPlan"]["days"]] == [1, 2, 3]
    assert body["zikuPrompt"]
    assert "Mechanics" in body["zikuPlan"]["text"]


def test_analysis_404_before_the_exam_is_submitted(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    resp = client.get(f"/api/exams/{exam['examId']}/analysis", headers=auth)
    assert resp.status_code == 404


def test_analysis_includes_live_academic_health(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    health = resp.json()["health"]
    assert health["score"] is not None
    assert health["understanding"] is not None
    assert "quiz" in (health["understandingDetail"] or "").lower()
    assert any(area["topic"] == "Mechanics" for area in health["weakTopics"])


def test_analysis_respects_the_active_exam_rescue_plan(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam_date = (_now() + timedelta(days=2)).strftime("%Y-%m-%d")
    fake_db.seed(
        f"users/{UID}/exam_rescue",
        "plan-1",
        {
            "sessionId": "plan-1",
            "status": "active",
            "examTitle": "Physics Final",
            "examDate": exam_date,
            "subject": "Physics",
            "dailyTargetMinutes": 60,
        },
    )
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    body = resp.json()
    assert body["rescue"]["title"] == "Physics Final"
    assert body["rescue"]["daysRemaining"] == 2
    # the mock never lands after the real paper
    assert exam_date in body["zikuPlan"]["days"][2]["focus"]
    assert body["zikuPlan"]["daysRemaining"] == 2


def test_analyses_of_one_attempt_do_not_leak_across_attempts(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    first = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], first["attemptId"])
    second = _start(client, auth, exam["examId"])
    _submit(
        client,
        auth,
        exam["examId"],
        second["attemptId"],
        answers=["A", "B", "4", "A"],
        timeSpentSeconds=600,
    )

    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": second["attemptId"]},
        headers=auth,
    )
    assert resp.json()["accuracy"] == 100.0
    assert resp.json()["mistakeCount"] == 0

    latest = client.get(f"/api/exams/{exam['examId']}", headers=auth).json()
    assert latest["attemptCount"] == 2
    assert len(latest["results"]) == 2


# ---------------------------------------------------------------------------
# cross-module integration
# ---------------------------------------------------------------------------
def test_academic_health_sees_the_exam_result(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    health = client.get("/api/ai/academic-health", headers=auth).json()
    assert health["hasData"] is True

    understanding = next(
        m for m in health["metrics"] if m["key"] == "understanding"
    )
    assert understanding["available"] is True

    practice = health["signals"]["practiceExams"]
    assert practice["count7"] == 1
    assert practice["total"] == 1
    assert practice["weakTopics"] == ["Mechanics"]
    assert "practice exam" in next(
        m for m in health["metrics"] if m["key"] == "examReadiness"
    )["detail"]

    assert any(area["topic"] == "Mechanics" for area in health["weakAreas"])


def test_academic_health_unaffected_without_practice_exams(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    health = client.get("/api/ai/academic-health", headers=auth).json()
    assert health["signals"]["practiceExams"] == {
        "count7": 0,
        "avgAccuracy": 0,
        "total": 0,
        "weakTopics": [],
    }


def test_exam_result_appears_in_quiz_history(client, fake_auth, fake_db):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    resp = client.get("/api/ai/quiz/history", headers=auth)
    assert resp.status_code == 200
    items = resp.json()["items"] if "items" in resp.json() else resp.json()["results"]
    assert any(item.get("examId") == exam["examId"] for item in items), items


def test_mistakes_are_reachable_from_the_learning_brain(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    brain = client.get("/api/ai/mistakes/brain", headers=auth).json()
    assert brain["totalMistakes"] >= 1
    topics = [t.get("topic") for t in brain.get("weakTopics", [])]
    assert "Mechanics" in topics, brain


def test_exam_questions_can_be_reused_for_a_second_paper(
    client, fake_auth, fake_db
):
    auth = _student(fake_db, fake_auth)
    first = _create(client, auth)
    copy = _create(
        client,
        auth,
        source="saved",
        sourceExamId=first["examId"],
        questions=None,
        questionCount=4,
        title="Retake",
    )
    hall = _start(client, auth, copy["examId"])
    assert len(hall["questions"]) == 4
    assert all("correct" not in q for q in hall["questions"])
