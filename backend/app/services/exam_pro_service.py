"""Phase 6 — Real Exam Simulator Pro: attempt controls, history, sharing.

Everything here sits *on top of* Phase 3's ``exam_simulator_service``: same
Firestore collections, same grading, same redaction rules. Nothing in this
module grades a paper or reads an answer key — it only moves an attempt
between states (save / pause / resume), lists the student's own results and
hands out a paper's share code.

The spec's controls live here:

* **Save progress** — the selected answers, the flags and the remaining
  time are written to the attempt while the paper is still open, so a
  closed app never costs an hour of work.
* **Pause / resume** — gated by the paper's optional ``allowPause``
  setting; a paused clock is frozen on the server by rewriting the
  deadline, not by trusting the phone.
* **My Exams** — recent results with the improvement between the last two
  papers (the ``+8%`` line in the spec).
* **Community prep (spec 6.10)** — papers carry ``visibility`` / ``shareCode``
  and can be shared by code. A share link returns the *paper only* (redacted
  questions, no answers) — never an attempt, a score, or an owner id, so
  personal marks stay private by construction.
"""

from __future__ import annotations

import base64
import logging
from datetime import timedelta
from typing import Any

from app.services import exam_simulator_service as exams
from app.services.exam_simulator_service import ExamError

logger = logging.getLogger("gochano.exam_pro")

# An attempt is resumable while it has neither been submitted nor forgotten:
# "running" (clock ticking) and "paused" (clock frozen) both reopen.
OPEN_STATUSES = ("running", "paused")


def _limit_seconds(exam: dict[str, Any]) -> int:
    return int(exam.get("timeLimitMinutes") or 60) * 60


def _clamp_remaining(raw: Any, exam: dict[str, Any]) -> int:
    limit = _limit_seconds(exam)
    try:
        value = int(raw)
    except (TypeError, ValueError):
        value = limit
    return max(0, min(value, limit))


def _answers_list(raw: Any, count: int) -> list[str]:
    return exams._normalize_answers(raw, count)


def _answers_dict(answers: list[str]) -> dict[str, str]:
    return {str(i): value for i, value in enumerate(answers) if value}


def _flags(raw: Any) -> list[int]:
    if not isinstance(raw, (list, tuple)):
        return []
    flags: list[int] = []
    for value in list(raw)[:400]:
        try:
            flags.append(int(value))
        except (TypeError, ValueError):
            continue
    return sorted(set(flags))


def _latest_open_attempt(
    uid: str, exam_id: str
) -> tuple[str, dict[str, Any]] | None:
    """Newest attempt of this exam that is still open, if there is one."""
    rows = (
        exams._attempts_collection(uid)
        .where("examId", "==", exam_id)
        .order_by("startedAt", direction="DESCENDING")
        .limit(10)
        .stream()
    )
    for snap in rows:
        data = snap.to_dict() or {}
        if str(data.get("status") or "") in OPEN_STATUSES:
            return snap.id, data
    return None


def _require_open(exam_id: str, attempt: dict[str, Any]) -> None:
    if str(attempt.get("examId") or "") != exam_id:
        raise ExamError(400, "That attempt belongs to a different exam")
    if str(attempt.get("status") or "") == "submitted":
        raise ExamError(409, "This attempt has already been submitted")


def _running_or_raise(exam: dict[str, Any], attempt: dict[str, Any]) -> None:
    """Saving/pausing needs a clock that has not already run out."""
    if str(attempt.get("status") or "") != "running":
        return
    deadline = exams._to_dt(attempt.get("deadlineAt"))
    if deadline is not None and deadline < exams._now():
        raise ExamError(409, "Time is up — submit the paper")


def _hall_payload(
    *,
    exam_id: str,
    exam: dict[str, Any],
    questions: list[dict[str, Any]],
    attempt_id: str,
    attempt: dict[str, Any],
    remaining: int,
    resumed: bool = False,
) -> dict[str, Any]:
    """The same shape ``start_attempt`` returns, plus the saved progress."""
    started_at = exams._to_dt(attempt.get("startedAt")) or exams._now()
    deadline = exams._to_dt(attempt.get("deadlineAt"))
    if deadline is None:
        deadline = exams._now() + timedelta(seconds=remaining)
    count = len(questions)
    return {
        "attemptId": attempt_id,
        "examId": exam_id,
        "title": str(exam.get("title") or ""),
        "subject": str(exam.get("subject") or ""),
        "startedAt": started_at,
        "deadlineAt": deadline,
        "timeLimitMinutes": int(exam.get("timeLimitMinutes") or 60),
        "timeLimitSeconds": _limit_seconds(exam),
        "totalMarks": exams._to_float(exam.get("totalMarks")),
        "negativeMarking": bool(exam.get("negativeMarking")),
        "correctMarks": exams._to_float(exam.get("correctMarks")),
        "penalty": exams._to_float(exam.get("penalty")),
        "skipMarks": exams._to_float(exam.get("skipMarks")),
        "allowPause": bool(exam.get("allowPause", True)),
        "status": str(attempt.get("status") or "running"),
        "resumed": bool(resumed),
        "remainingSeconds": max(0, int(remaining)),
        "answers": _answers_list(attempt.get("answers"), count),
        "markedForReview": _flags(attempt.get("markedForReview")),
        "questions": [exams._redact_question(q) for q in questions],
    }


# ---------------------------------------------------------------------------
# save / pause / resume — spec 6.4 exam controls
# ---------------------------------------------------------------------------
def save_progress(
    uid: str,
    exam_id: str,
    *,
    attempt_id: str,
    answers: Any,
    marked_for_review: list[int] | None = None,
    remaining_seconds: int | None = None,
) -> dict[str, Any]:
    """Write the selected answers, the flags and the remaining time.

    Called from the hall on every answered question and periodically while
    the clock runs, so the server — not the phone — owns the recovery point.
    """
    _, exam = exams._load_exam(uid, exam_id)
    key, attempt = exams._load_attempt(uid, attempt_id)
    _require_open(exam_id, attempt)
    _running_or_raise(exam, attempt)

    questions = exams._load_questions(uid, exam_id)
    now = exams._now()
    answers_list = _answers_list(answers, len(questions))
    remaining = (
        _clamp_remaining(remaining_seconds, exam)
        if remaining_seconds is not None
        else _remaining_of(attempt, exam)
    )
    saved = {
        **attempt,
        "answers": _answers_dict(answers_list),
        "markedForReview": _flags(marked_for_review),
        "remainingSeconds": remaining,
        "savedAt": now,
        "updatedAt": now,
    }
    exams._attempts_collection(uid).document(key).set(saved)

    return {
        "attemptId": attempt_id,
        "examId": exam_id,
        "saved": True,
        "status": str(saved.get("status") or "running"),
        "answered": sum(1 for value in answers_list if value.strip()),
        "remainingSeconds": remaining,
        "savedAt": now,
    }


def _remaining_of(attempt: dict[str, Any], exam: dict[str, Any]) -> int:
    """Server-side remaining time for a running attempt."""
    if str(attempt.get("status") or "") == "paused":
        return _clamp_remaining(attempt.get("remainingSeconds"), exam)
    deadline = exams._to_dt(attempt.get("deadlineAt"))
    if deadline is None:
        return _limit_seconds(exam)
    return _clamp_remaining((deadline - exams._now()).total_seconds(), exam)


def pause_attempt(
    uid: str,
    exam_id: str,
    *,
    attempt_id: str,
    remaining_seconds: int | None = None,
) -> dict[str, Any]:
    """Freeze the clock — only for papers whose builder allowed a pause."""
    _, exam = exams._load_exam(uid, exam_id)
    if not bool(exam.get("allowPause", True)):
        raise ExamError(403, "Pausing is switched off for this paper")
    key, attempt = exams._load_attempt(uid, attempt_id)
    _require_open(exam_id, attempt)
    if str(attempt.get("status") or "") != "running":
        raise ExamError(409, "Only a running paper can be paused")

    now = exams._now()
    remaining = _clamp_remaining(
        remaining_seconds if remaining_seconds is not None
        else _remaining_of(attempt, exam),
        exam,
    )
    saved = {
        **attempt,
        "status": "paused",
        "pausedAt": now,
        "remainingSeconds": remaining,
        "savedAt": now,
        "updatedAt": now,
    }
    exams._attempts_collection(uid).document(key).set(saved)
    logger.info(
        "exam paused: uid=%s exam=%s attempt=%s remaining=%ss",
        uid,
        exam_id,
        attempt_id,
        remaining,
    )
    return {
        "attemptId": attempt_id,
        "examId": exam_id,
        "status": "paused",
        "remainingSeconds": remaining,
        "pausedAt": now,
    }


def resume_attempt(
    uid: str,
    exam_id: str,
    *,
    attempt_id: str | None = None,
) -> dict[str, Any]:
    """Reopen the student's unfinished attempt (the Phase 3 follow-up).

    * paused → the clock restarts from the frozen remaining time;
    * running → the deadline still rules; an expired paper comes back with
      ``remainingSeconds: 0`` so the hall auto-submits the saved answers
      instead of losing them;
    * nothing open → 404, and the client falls back to a fresh ``/start``.
    """
    _, exam = exams._load_exam(uid, exam_id)
    questions = exams._load_questions(uid, exam_id)

    if attempt_id:
        key, attempt = exams._load_attempt(uid, attempt_id)
        _require_open(exam_id, attempt)
    else:
        found = _latest_open_attempt(uid, exam_id)
        if found is None:
            raise ExamError(404, "No unfinished attempt for this paper")
        key, attempt = found

    now = exams._now()
    status = str(attempt.get("status") or "running")
    if status == "paused":
        remaining = _clamp_remaining(attempt.get("remainingSeconds"), exam)
        attempt = {
            **attempt,
            "status": "running",
            "pausedAt": None,
            "deadlineAt": now + timedelta(seconds=remaining),
            "resumedAt": now,
            "updatedAt": now,
        }
        exams._attempts_collection(uid).document(key).set(attempt)
        logger.info(
            "exam resumed: uid=%s exam=%s attempt=%s remaining=%ss",
            uid,
            exam_id,
            key,
            remaining,
        )
    else:
        remaining = _remaining_of(attempt, exam)

    return _hall_payload(
        exam_id=exam_id,
        exam=exam,
        questions=questions,
        attempt_id=str(attempt.get("attemptId") or key),
        attempt=attempt,
        remaining=remaining,
        resumed=True,
    )


# ---------------------------------------------------------------------------
# results — spec 6.9 history and the per-result drill-down
# ---------------------------------------------------------------------------
def latest_result(
    uid: str, exam_id: str, *, attempt_id: str | None = None
) -> dict[str, Any]:
    """One finished attempt in the same shape the submit endpoint returns."""
    result_id, result = exams._latest_result(uid, exam_id, attempt_id)
    return exams._result_payload(result, result_id)


def history(uid: str, *, limit: int = 20) -> dict[str, Any]:
    """"My Exams": the student's own recent papers, newest first.

    Only the caller's own ``exam_results`` are ever read — there is no
    cross-user query and no field that another account could reach.
    """
    rows = (
        exams._results_collection(uid)
        .order_by("createdAt", direction="DESCENDING")
        .limit(max(1, min(limit, 50)))
        .stream()
    )

    titles: dict[str, dict[str, Any]] = {}
    items: list[dict[str, Any]] = []
    for snap in rows:
        data = snap.to_dict() or {}
        exam_id = str(data.get("examId") or "")
        if exam_id not in titles:
            try:
                _, exam = exams._load_exam(uid, exam_id)
                titles[exam_id] = {
                    "title": str(exam.get("title") or ""),
                    "subject": str(exam.get("subject") or ""),
                }
            except ExamError:
                titles[exam_id] = {"title": "", "subject": ""}
        meta = titles[exam_id]
        items.append(
            {
                "resultId": str(snap.id),
                "examId": exam_id,
                "attemptId": str(data.get("attemptId") or ""),
                "title": meta["title"]
                or str(data.get("subject") or "")
                or "Exam",
                "subject": meta["subject"] or str(data.get("subject") or ""),
                "score": exams._to_float(data.get("score")),
                "totalMarks": exams._to_float(data.get("totalMarks")),
                "percentage": exams._to_float(data.get("percentage")),
                "accuracy": exams._to_float(data.get("accuracy")),
                "correctCount": int(data.get("correctCount") or 0),
                "wrongCount": int(data.get("wrongCount") or 0),
                "skippedCount": int(data.get("skippedCount") or 0),
                "totalQuestions": int(data.get("totalQuestions") or 0),
                "timeManagementLabel": str(
                    data.get("timeManagementLabel") or ""
                ),
                "mistakeCount": int(data.get("mistakeCount") or 0),
                "weakTopics": list(data.get("weakTopics") or []),
                "createdAt": data.get("createdAt"),
                "dayKey": str(data.get("dayKey") or ""),
            }
        )

    percentages = [item["percentage"] for item in items]
    improvement: float | None = None
    if len(percentages) >= 2:
        improvement = exams._round(percentages[0] - percentages[1], 1)

    return {
        "exams": items,
        "count": len(items),
        "improvement": improvement,
        "bestPercentage": max(percentages) if percentages else 0.0,
        "averagePercentage": (
            exams._round(sum(percentages) / len(percentages), 1)
            if percentages
            else 0.0
        ),
    }


# ---------------------------------------------------------------------------
# sharing — spec 6.10 community preparation
# ---------------------------------------------------------------------------
def _share_code(uid: str, exam_id: str) -> str:
    raw = f"{uid}|{exam_id}".encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _decode_share(code: str) -> tuple[str, str]:
    value = str(code or "").strip()
    if not value or len(value) > 256:
        raise ExamError(404, "That share link is not valid")
    try:
        padded = value + "=" * (-len(value) % 4)
        raw = base64.urlsafe_b64decode(padded.encode("ascii")).decode("utf-8")
    except Exception as exc:  # noqa: BLE001 - any bad input is a 404
        raise ExamError(404, "That share link is not valid") from exc
    owner_id, _, exam_id = raw.partition("|")
    if not owner_id or not exam_id or len(owner_id) > 128 or len(exam_id) > 64:
        raise ExamError(404, "That share link is not valid")
    return owner_id, exam_id


def set_visibility(
    uid: str, exam_id: str, *, share: bool
) -> dict[str, Any]:
    """Turn sharing on or off for one of the student's own papers."""
    ref = exams._exams_collection(uid).document(exam_id)
    found = exams._read_doc(exams._exams_collection(uid), exam_id)
    if found is None:
        raise ExamError(404, "Exam not found")
    data = dict(found[1])
    now = exams._now()
    if share:
        data.update(
            {
                "visibility": "link",
                "shareCode": _share_code(uid, exam_id),
                "sharedAt": now,
            }
        )
    else:
        data.update(
            {"visibility": "private", "shareCode": "", "sharedAt": None}
        )
    ref.set(data)
    logger.info(
        "exam visibility: uid=%s exam=%s share=%s", uid, exam_id, share
    )
    return {
        "examId": exam_id,
        "title": str(data.get("title") or ""),
        "visibility": str(data.get("visibility") or "private"),
        "shareCode": str(data.get("shareCode") or ""),
        "shared": bool(share),
    }


def get_shared(uid: str, code: str) -> dict[str, Any]:
    """Open a shared *paper* — redacted questions only, for every student.

    ``uid`` is unused on purpose: any signed-in student holding the code may
    read the paper, and what they get back contains no answers, no scores,
    no attempts and no owner id.
    """
    owner_id, exam_id = _decode_share(code)
    ref = (
        exams._db()
        .collection("users")
        .document(owner_id)
        .collection(exams.EXAMS)
        .document(exam_id)
    )
    snap = ref.get()
    data = snap.to_dict() if snap is not None and snap.exists else None
    if not data or str(data.get("visibility") or "") != "link":
        raise ExamError(404, "That paper is not shared")

    questions = [
        exams._redact_question(row)
        for row in exams._load_questions(owner_id, exam_id)
    ]
    if not questions:
        raise ExamError(404, "That paper has no questions")

    return {
        "examId": exam_id,
        "title": str(data.get("title") or ""),
        "subject": str(data.get("subject") or ""),
        "topic": str(data.get("topic") or ""),
        "difficulty": str(data.get("difficulty") or "medium"),
        "questionCount": len(questions),
        "totalMarks": exams._to_float(data.get("totalMarks")),
        "timeLimitMinutes": int(data.get("timeLimitMinutes") or 60),
        "negativeMarking": bool(data.get("negativeMarking")),
        "correctMarks": exams._to_float(data.get("correctMarks")),
        "penalty": exams._to_float(data.get("penalty")),
        "allowPause": bool(data.get("allowPause", True)),
        "questions": questions,
        "shared": True,
    }
