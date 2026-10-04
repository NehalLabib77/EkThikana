"""Phase 6 — Real Exam Simulator Pro tests.

Covers what Phase 6 adds on top of the Phase 3 simulator:

* **spec 6.4 controls** — save progress (answers + flags + remaining time),
  pause gated by the paper's optional ``allowPause`` setting, and resume
  (including the 404 that tells the client to start fresh);
* **spec 6.9 history** — ``GET /api/exams/history`` with the improvement
  between the last two papers, plus the ``/list`` and ``/{id}/result``
  aliases the spec names;
* **spec 6.10 community prep** — a share code that hands out the *paper
  only*: redacted questions, no answers, no scores, no owner;
* the Phase 6 builder changes: the ``manual`` source, the pause toggle and
  the "Careless mistake" label the result screen shows.

Every test runs against the real FastAPI app through the shared ``client``
fixture (FakeFirestore + FakeAuth).
"""

from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402
from app.services import exam_pro_service as pro_mod  # noqa: E402
from app.services import exam_simulator_service as exam_mod  # noqa: E402


UID = "exam-pro-student"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _auth(fake_auth, uid: str = UID) -> dict[str, str]:
    return bearer(fake_auth.issue(uid))


def _student(fake_db, fake_auth, uid: str = UID):
    seed_profile(fake_db, uid)
    return _auth(fake_auth, uid)


def _paper_questions() -> list[dict]:
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
        "title": "Physics Model Test",
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
        "answers": ["A", "B", "1", "Z"],
        "timeSpentSeconds": 900,
        "withAiAnalysis": False,
    }
    body.update(extra)
    resp = client.post(f"/api/exams/{exam_id}/submit", json=body, headers=auth)
    assert resp.status_code == 200, resp.text
    return resp.json()


def _save(client, auth, exam_id: str, attempt_id: str, **extra) -> dict:
    body = {
        "attemptId": attempt_id,
        "answers": ["A", "", "", ""],
        "markedForReview": [1],
        "remainingSeconds": 1234,
    }
    body.update(extra)
    resp = client.post(f"/api/exams/{exam_id}/save", json=body, headers=auth)
    assert resp.status_code == 200, resp.text
    return resp.json()


def _attempt(fake_db, exam_id: str, attempt_id: str) -> dict:
    rows = fake_db._collections.get(f"users/{UID}/exam_attempts") or {}
    return rows[attempt_id]


# ---------------------------------------------------------------------------
# spec 6.4 — save / pause / resume
# ---------------------------------------------------------------------------
def test_save_progress_keeps_answers_flags_and_remaining_time(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])

    saved = _save(client, auth, exam["examId"], hall["attemptId"])
    assert saved["saved"] is True
    assert saved["status"] == "running"
    assert saved["answered"] == 1
    assert saved["remainingSeconds"] == 1234

    row = _attempt(fake_db, exam["examId"], hall["attemptId"])
    assert row["answers"] == {"0": "A"}
    assert row["markedForReview"] == [1]
    assert row["remainingSeconds"] == 1234
    assert row["status"] == "running"


def test_saved_progress_comes_back_when_the_attempt_resumes(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _save(client, auth, exam["examId"], hall["attemptId"])

    resp = client.post(
        f"/api/exams/{exam['examId']}/resume", json={}, headers=auth
    )
    assert resp.status_code == 200, resp.text
    resumed = resp.json()

    assert resumed["attemptId"] == hall["attemptId"]
    assert resumed["resumed"] is True
    assert resumed["answers"][0] == "A"
    assert resumed["answers"][1:] == ["", "", ""]
    assert resumed["markedForReview"] == [1]
    # the clock is still server-owned: it counts down from the deadline
    assert 0 < resumed["remainingSeconds"] <= 60 * 60
    # and the questions are still redacted
    assert "correct" not in resumed["questions"][0]
    assert "explanation" not in resumed["questions"][0]


def test_save_progress_conflicts_once_the_attempt_is_submitted(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    resp = client.post(
        f"/api/exams/{exam['examId']}/save",
        json={"attemptId": hall["attemptId"], "answers": ["A"]},
        headers=auth,
    )
    assert resp.status_code == 409


def test_pause_freezes_the_clock_and_resume_thaws_it(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])

    paused = client.post(
        f"/api/exams/{exam['examId']}/pause",
        json={"attemptId": hall["attemptId"], "remainingSeconds": 1500},
        headers=auth,
    )
    assert paused.status_code == 200, paused.text
    assert paused.json()["status"] == "paused"
    assert paused.json()["remainingSeconds"] == 1500

    row = _attempt(fake_db, exam["examId"], hall["attemptId"])
    assert row["status"] == "paused"
    assert row["remainingSeconds"] == 1500

    # while paused the paper cannot be saved again as "running" work
    blocked = client.post(
        f"/api/exams/{exam['examId']}/pause",
        json={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    assert blocked.status_code == 409

    resumed = client.post(
        f"/api/exams/{exam['examId']}/resume",
        json={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    assert resumed.status_code == 200, resumed.text
    body = resumed.json()
    assert body["status"] == "running"
    # the deadline was rewritten from the frozen remaining time
    assert body["remainingSeconds"] <= 1500
    assert body["remainingSeconds"] > 1400


def test_pause_is_refused_when_the_builder_switched_it_off(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth, allowPause=False)
    assert exam["allowPause"] is False
    hall = _start(client, auth, exam["examId"])
    assert hall["allowPause"] is False

    resp = client.post(
        f"/api/exams/{exam['examId']}/pause",
        json={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    assert resp.status_code == 403


def test_resume_404s_when_nothing_is_open_so_the_client_starts_fresh(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)

    missing = client.post(f"/api/exams/{exam['examId']}/resume", headers=auth)
    assert missing.status_code == 404

    hall = _start(client, auth, exam["examId"])
    again = client.post(f"/api/exams/{exam['examId']}/resume", headers=auth)
    assert again.status_code == 200
    assert again.json()["attemptId"] == hall["attemptId"]

    _submit(client, auth, exam["examId"], hall["attemptId"])
    closed = client.post(f"/api/exams/{exam['examId']}/resume", headers=auth)
    assert closed.status_code == 404


def test_an_expired_running_attempt_resumes_with_zero_seconds(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth, timeLimitMinutes=60)
    hall = _start(client, auth, exam["examId"])
    _save(
        client,
        auth,
        exam["examId"],
        hall["attemptId"],
        remainingSeconds=0,
        answers=["A", "B", "", ""],
    )

    # rewind the deadline so the paper is out of time
    rows = fake_db._collections[f"users/{UID}/exam_attempts"]
    row = dict(rows[hall["attemptId"]])
    row["deadlineAt"] = _now().replace(year=_now().year - 1)
    rows[hall["attemptId"]] = row

    resp = client.post(
        f"/api/exams/{exam['examId']}/resume", json={}, headers=auth
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["remainingSeconds"] == 0
    # the saved answers survive so the hall can auto-submit them
    assert body["answers"] == ["A", "B", "", ""]


# ---------------------------------------------------------------------------
# spec 6.9 — My Exams history and the spec's aliases
# ---------------------------------------------------------------------------
def test_history_reports_the_improvement_between_the_last_two_papers(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)

    first = _create(client, auth, title="Physics Model Test")
    hall_a = _start(client, auth, first["examId"])
    weak = _submit(
        client, auth, first["examId"], hall_a["attemptId"], answers=["Z"] * 4
    )

    second = _create(client, auth, title="Physics Model Test 2")
    hall_b = _start(client, auth, second["examId"])
    strong = _submit(
        client,
        auth,
        second["examId"],
        hall_b["attemptId"],
        answers=["A", "B", "4", "A"],
    )

    resp = client.get("/api/exams/history", headers=auth)
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["count"] == 2
    assert [row["title"] for row in body["exams"]] == [
        "Physics Model Test 2",
        "Physics Model Test",
    ]
    assert body["exams"][0]["resultId"]
    assert body["exams"][0]["percentage"] == strong["percentage"]
    assert body["exams"][1]["percentage"] == weak["percentage"]
    expected = round(strong["percentage"] - weak["percentage"], 1)
    assert body["improvement"] == expected
    assert body["improvement"] > 0
    assert body["bestPercentage"] == strong["percentage"]


def test_history_only_reads_the_callers_own_results(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"])

    other = _auth(fake_auth, "other-student")
    seed_profile(fake_db, "other-student")
    empty = client.get("/api/exams/history", headers=other)
    assert empty.status_code == 200
    assert empty.json() == {
        "exams": [],
        "count": 0,
        "improvement": None,
        "bestPercentage": 0.0,
        "averagePercentage": 0.0,
    }


def test_the_spec_list_alias_matches_the_list_endpoint(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)

    alias = client.get("/api/exams/list", headers=auth)
    real = client.get("/api/exams", headers=auth)
    assert alias.status_code == 200, alias.text
    assert alias.json() == real.json()
    assert [row["examId"] for row in alias.json()["exams"]] == [exam["examId"]]


def test_the_spec_result_alias_returns_the_submit_payload(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    submitted = _submit(client, auth, exam["examId"], hall["attemptId"])

    resp = client.get(f"/api/exams/{exam['examId']}/result", headers=auth)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["resultId"] == submitted["resultId"]
    assert body["score"] == submitted["score"]
    assert body["attemptId"] == hall["attemptId"]

    scoped = client.get(
        f"/api/exams/{exam['examId']}/result",
        params={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    assert scoped.status_code == 200
    assert scoped.json()["resultId"] == submitted["resultId"]


def test_the_result_endpoint_404s_before_anything_is_submitted(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    resp = client.get(f"/api/exams/{exam['examId']}/result", headers=auth)
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# spec 6.10 — sharing a paper, never the marks
# ---------------------------------------------------------------------------
def test_sharing_hands_out_a_code_that_returns_the_paper_without_answers(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth, title="Physics Model Test")

    shared = client.post(
        f"/api/exams/{exam['examId']}/share", json={"share": True}, headers=auth
    )
    assert shared.status_code == 200, shared.text
    code = shared.json()["shareCode"]
    assert code
    assert shared.json()["visibility"] == "link"

    # another student opens the link
    reader = _auth(fake_auth, "classmate")
    seed_profile(fake_db, "classmate")
    resp = client.get(f"/api/exams/shared/{code}", headers=reader)
    assert resp.status_code == 200, resp.text
    paper = resp.json()

    assert paper["title"] == "Physics Model Test"
    assert paper["questionCount"] == 4
    assert paper["shared"] is True
    assert len(paper["questions"]) == 4
    for question in paper["questions"]:
        assert "correct" not in question
        assert "explanation" not in question
    # no marks, no attempts, no owner — privacy by construction
    banned = {
        "ownerId",
        "percentage",
        "score",
        "attempts",
        "attemptCount",
        "results",
        "visibility",
    }
    assert banned.isdisjoint(paper.keys())


def test_unsharing_closes_the_link_immediately(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    code = client.post(
        f"/api/exams/{exam['examId']}/share",
        json={"share": True},
        headers=auth,
    ).json()["shareCode"]

    client.post(
        f"/api/exams/{exam['examId']}/share",
        json={"share": False},
        headers=auth,
    )
    resp = client.get(f"/api/exams/shared/{code}", headers=auth)
    assert resp.status_code == 404

    stored = exam_mod._read_doc(
        exam_mod._exams_collection(UID), exam["examId"]
    )
    assert stored[1]["visibility"] == "private"
    assert stored[1]["shareCode"] == ""


def test_a_bad_or_unshared_code_is_just_a_404(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    assert (
        client.get("/api/exams/shared/not-a-real-code", headers=auth).status_code
        == 404
    )

    exam = _create(client, auth)
    never_shared = pro_mod._share_code(UID, exam["examId"])
    resp = client.get(f"/api/exams/shared/{never_shared}", headers=auth)
    assert resp.status_code == 404


def test_a_private_paper_cannot_be_read_by_a_guessing_classmate(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    classmate = _auth(fake_auth, "classmate")
    seed_profile(fake_db, "classmate")

    # even with the raw code, a paper that was never shared stays closed
    code = pro_mod._share_code(UID, exam["examId"])
    resp = client.get(f"/api/exams/shared/{code}", headers=classmate)
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# spec 6.1 / 6.6 — builder inputs and the result labels
# ---------------------------------------------------------------------------
def test_the_manual_source_creates_a_hand_written_paper(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(
        client,
        auth,
        source="manual",
        title="Physics Model Test",
        allowPause=False,
    )
    assert exam["source"] == "manual"
    assert exam["title"] == "Physics Model Test"
    assert exam["allowPause"] is False
    # the paper is private until the student shares it
    assert exam["visibility"] == "private"


def test_an_explicit_pause_setting_survives_a_public_exam_fetch(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)

    resp = client.get(
        f"/api/exams/{exam['examId']}",
        params={"includeQuestions": "true"},
        headers=auth,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["allowPause"] is True
    assert body["visibility"] == "private"


def test_the_result_screen_labels_a_forgot_the_fact_mistake_careless(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _submit(client, auth, exam["examId"], hall["attemptId"], answers=["Z"] * 4)

    resp = client.get(
        f"/api/exams/{exam['examId']}/analysis",
        params={"attemptId": hall["attemptId"]},
        headers=auth,
    )
    assert resp.status_code == 200
    labels = {row["type"]: row["label"] for row in resp.json()["mistakeTypes"]}
    assert labels["memory"] == "Careless mistake"
    assert labels["concept"] == "Concept error"
    assert labels["calculation"] == "Calculation error"


# ---------------------------------------------------------------------------
# route hygiene
# ---------------------------------------------------------------------------
def test_the_static_paths_are_not_swallowed_by_the_path_parameter(
    client, fake_db, fake_auth
):
    """``/list`` and ``/history`` must not be read as an exam id."""
    auth = _student(fake_db, fake_auth)

    # both would be a 404 "Exam not found" if the router order were wrong
    assert client.get("/api/exams/list", headers=auth).status_code == 200
    assert client.get("/api/exams/history", headers=auth).status_code == 200


def test_every_phase_6_endpoint_requires_a_signed_in_student(client, fake_auth):
    for method, path, body in (
        ("get", "/api/exams/history", None),
        ("get", "/api/exams/list", None),
        ("post", "/api/exams/any/save", {"attemptId": "a1", "answers": []}),
        ("post", "/api/exams/any/pause", {"attemptId": "a1"}),
        ("post", "/api/exams/any/resume", {}),
        ("post", "/api/exams/any/share", {"share": True}),
        ("get", "/api/exams/any/result", None),
        ("get", "/api/exams/shared/abc", None),
    ):
        resp = getattr(client, method)(path, json=body) if body is not None else getattr(client, method)(path)
        assert resp.status_code in (401, 403), f"{method} {path} is open"


def test_saving_progress_never_touches_another_students_attempt(
    client, fake_db, fake_auth
):
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])

    intruder = _auth(fake_auth, "intruder")
    seed_profile(fake_db, "intruder")
    resp = client.post(
        f"/api/exams/{exam['examId']}/save",
        json={"attemptId": hall["attemptId"], "answers": ["B"]},
        headers=intruder,
    )
    # the paper itself is not the intruder's, so nothing can be written
    assert resp.status_code == 404


def test_submit_still_works_after_the_phase_6_saves(
    client, fake_db, fake_auth
):
    """Phase 6 must not break the Phase 3 submit path."""
    auth = _student(fake_db, fake_auth)
    exam = _create(client, auth)
    hall = _start(client, auth, exam["examId"])
    _save(client, auth, exam["examId"], hall["attemptId"])

    result = _submit(client, auth, exam["examId"], hall["attemptId"])
    assert result["score"] == 49.5
    assert result["mistakeCount"] == 2


@pytest.mark.parametrize("path", ["/api/exams", "/api/exams/list"])
def test_both_list_paths_are_student_only(client, fake_auth, path):
    resp = client.get(path)
    assert resp.status_code in (401, 403)
