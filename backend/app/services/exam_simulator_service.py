"""Phase 3 — AI Real Exam Simulator.

The exam hall, its paper handling and its post-exam analysis. Four Firestore
collections per student (``exams``, ``exam_attempts``, ``exam_results`` plus
the per-exam ``exam_questions`` subcollection) hold everything; this module is
the only writer of attempts and results, so the client can never grade itself.

Nothing here is a silo:

* **Quiz system** — a submitted exam also writes a ``quiz_results`` document
  with the same shape ``/api/ai/quiz/save-result`` produces, so the exam shows
  up in quiz history, Academic Health's Understanding metric and the weak-topic
  service for free. "Saved questions" are re-used quiz questions.
* **Mistake Memory** — wrong answers go through
  ``mistake_memory_service.capture_mistakes`` (the exact Phase 1 call), and the
  result keeps a per-question preview with a mistake type and the 1/7/30-day
  review ladder the Learning Brain will follow.
* **Academic Health** — ``get_academic_health`` reads back the live score in
  the analysis payload, and new exam results feed the ``practiceExams`` signal
  that nudges Exam readiness.
* **Exam Rescue** — the Ziku plan is built around the active rescue plan's
  exam date when the subject matches, so a mini test never lands after the
  real exam.
* **Ziku** — one AI paragraph per attempt (best effort, cached on the result)
  plus a ready-made prompt for the in-app assistant.

The hall itself is deliberately dumb: questions are served without answers or
explanations and there is no AI endpoint to call mid-exam.
"""

from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import mistake_memory_service as mistake_memory
from app.services import pdf_service, ocr_service
from app.services.ai_service import AiFeature
from app.services.weak_topic_service import DEFAULT_WEAK_THRESHOLD

logger = logging.getLogger("gochano.exam_simulator")

EXAMS = "exams"
QUESTIONS = "exam_questions"
ATTEMPTS = "exam_attempts"
RESULTS = "exam_results"
QUIZ_RESULTS = "quiz_results"

SOURCES = ("ai", "upload", "manual", "saved")
DIFFICULTIES = ("easy", "medium", "hard", "real_exam")
MISTAKE_TYPES = ("concept", "calculation", "memory")

MIN_QUESTIONS = 1
MAX_QUESTIONS = 200
MAX_TIME_MINUTES = 480
MAX_OPTIONS = 6

UPLOAD_MAX_BYTES = 10 * 1024 * 1024  # mirrors /api/ai attachment policy (413)
UPLOAD_MAX_CHARS = 20000
UPLOAD_ALLOWED = (
    "application/pdf",
    "text/plain",
    "image/png",
    "image/jpeg",
    "image/webp",
)

# A wrong answer is worth -0.25 marks in the reference configuration
# (50 questions / 100 marks / -0.25 per wrong / +2 per correct).
DEFAULT_PENALTY = 0.25
DEFAULT_SKIP_MARKS = 0.0
SUBMIT_GRACE_SECONDS = 300

# Mistake typing. The stored exam preview classifies each wrong answer so the
# result screen can say *why* it was wrong before Ziku's analysis lands.
_NUMERIC_RE = re.compile(
    r"\d\s*[+\-*/x×÷=]\s*\d|\d+(?:\.\d+)?\s*(?:km|cm|mm|ms|kg|mg|ml|kpa|pa|hz|"
    r"ohm|°|deg|%|mol|n|j|w|v|a|s|m|g|l)\b",
    re.IGNORECASE,
)
_MEMORY_HINTS = (
    "define",
    "state ",
    "list ",
    "recall",
    "remember",
    "formula for",
    "what is the formula",
    "unit of",
    "who ",
)
_FENCE_RE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


class ExamError(Exception):
    """Mapped to an HTTP error by the router (code, detail)."""

    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status = status
        self.detail = detail


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
def _db():
    db = get_firestore()
    if db is None:
        raise ExamError(503, "Firestore unavailable")
    return db


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _day_key(moment: datetime) -> str:
    return moment.strftime("%Y-%m-%d")


def _month_key(moment: datetime) -> str:
    return moment.strftime("%Y-%m")


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _round(value: float, places: int = 1) -> float:
    return round(float(value) + 0.0, places)


def _to_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _to_dt(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str) and value:
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def _exams_collection(uid: str):
    return _db().collection("users").document(uid).collection(EXAMS)


def _questions_collection(uid: str, exam_id: str):
    return (
        _db()
        .collection("users")
        .document(uid)
        .collection(EXAMS)
        .document(exam_id)
        .collection(QUESTIONS)
    )


def _attempts_collection(uid: str):
    return _db().collection("users").document(uid).collection(ATTEMPTS)


def _results_collection(uid: str):
    return _db().collection("users").document(uid).collection(RESULTS)


def _read_doc(collection, doc_id: str) -> tuple[str, dict[str, Any]] | None:
    snap = collection.document(doc_id).get()
    if not snap.exists:
        return None
    return snap.id, (snap.to_dict() or {})


def _load_exam(uid: str, exam_id: str) -> tuple[str, dict[str, Any]]:
    found = _read_doc(_exams_collection(uid), exam_id)
    if found is None:
        raise ExamError(404, "Exam not found")
    return found


def _load_questions(uid: str, exam_id: str) -> list[dict[str, Any]]:
    rows = []
    for snap in _questions_collection(uid, exam_id).stream():
        data = snap.to_dict() or {}
        if data:
            rows.append(data)
    rows.sort(key=lambda row: int(row.get("index") or 0))
    return rows


async def _ai_generate(uid: str, prompt: str, feature: str = AiFeature.QUIZ) -> str:
    """Single AI seam — tests replace this instead of the provider cascade."""
    from app.services import ai_service

    try:
        return await ai_service.generate(uid, prompt, feature=feature)
    except TypeError:  # older provider signatures take no feature kwarg
        return await ai_service.generate(uid, prompt)


def _extract_json(raw: Any) -> dict[str, Any]:
    """Pull the first JSON object out of a model reply (fences tolerated)."""
    if isinstance(raw, dict):
        return raw
    text = str(raw or "").strip()
    fenced = _FENCE_RE.search(text)
    if fenced:
        text = fenced.group(1).strip()
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object in response")
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return json.loads(text[start : index + 1])
    raise ValueError("unterminated JSON object in response")


# ---------------------------------------------------------------------------
# question normalisation
# ---------------------------------------------------------------------------
def _normalize_question(
    raw: Any,
    index: int,
    *,
    subject: str = "",
    default_marks: float = 0.0,
) -> dict[str, Any]:
    """One canonical shape for AI, uploaded and saved questions alike."""
    if not isinstance(raw, dict):
        raw = {"question": str(raw or "")}

    text = str(raw.get("question") or raw.get("text") or "").strip()
    q_type = str(raw.get("type") or "").strip().lower()
    options = raw.get("options") or []
    if not isinstance(options, (list, tuple)):
        options = []
    options = [str(option).strip() for option in options if str(option).strip()]
    # de-duplicate while preserving order, and drop "A)" prefixes the model
    # sometimes adds twice ("A. A. Something")
    cleaned: list[str] = []
    for option in options:
        stripped = re.sub(r"^\s*([A-F])[.)]\s*", "", option).strip()
        if stripped and stripped not in cleaned:
            cleaned.append(stripped)
    options = cleaned[:MAX_OPTIONS]

    if not q_type:
        q_type = "mcq" if options else "short_answer"
    if q_type not in ("mcq", "short_answer", "numerical"):
        q_type = "mcq" if options else "short_answer"

    correct = str(raw.get("correct") or raw.get("answer") or "").strip()
    # MCQ answers are stored as the bare option letter — the same reference
    # ``quiz_results`` uses, and the only form ``answers_match`` accepts in
    # both directions (the exam screen submits "B", never a paraphrase).
    if q_type == "mcq" and options:
        correct = _mcq_letter(correct, options)

    topic = str(raw.get("topic") or "").strip() or (subject.strip() or "General")
    explanation = str(raw.get("explanation") or "").strip()[:1000]
    try:
        marks = float(raw.get("marks") or 0)
    except (TypeError, ValueError):
        marks = 0.0
    if marks <= 0:
        marks = default_marks

    needs_review = bool(raw.get("needsReview"))
    if not text or len(text) < 4:
        needs_review = True
    if q_type == "mcq" and (
        len(options) < 2
        or not (len(correct) == 1 and correct.isalpha())
    ):
        # an MCQ the key cannot point at (missing option, or an answer the
        # options do not contain) has to be fixed before the hall opens.
        needs_review = True
    if not correct:
        needs_review = True

    return {
        "index": index,
        "question": text[:2000],
        "type": q_type,
        "options": options,
        "correct": correct[:500],
        "explanation": explanation,
        "topic": topic[:120],
        "marks": _round(marks, 2),
        "difficulty": str(raw.get("difficulty") or "").strip().lower()
        or "medium",
        "mistakeTypeHint": str(raw.get("mistakeType") or raw.get("mistakeTypeHint") or "")
        .strip()
        .lower(),
        "needsReview": needs_review,
    }


def _mcq_letter(correct: str, options: list[str]) -> str:
    """Resolve an answer key to a bare option letter (or return it as-is)."""
    value = (correct or "").strip()
    if not value:
        return ""
    if len(value) == 1 and value.isalpha():
        position = ord(value.upper()) - ord("A")
        if 0 <= position < len(options):
            return value.upper()
        return ""
    wanted = re.sub(r"\s+", " ", value).strip().lower().rstrip(".")
    for position, option in enumerate(options):
        candidate = re.sub(r"\s+", " ", option).strip().lower().rstrip(".")
        if candidate == wanted or (len(wanted) >= 5 and candidate.startswith(wanted)):
            return chr(ord("A") + position)
    return value


def _validate_for_exam(questions: list[dict[str, Any]]) -> None:
    """Manual correction means every question has an answer before the hall."""
    if not questions:
        raise ExamError(422, "No questions to examine")
    broken = [
        int(q.get("index") or 0)
        for q in questions
        if not q.get("question") or not q.get("correct")
    ]
    if broken:
        raise ExamError(
            400,
            "Questions "
            + ", ".join(str(i + 1) for i in broken[:10])
            + " need a correct answer before the exam can start",
        )


def _distribute_marks(
    questions: list[dict[str, Any]], total_marks: float, correct_marks: float | None
) -> tuple[list[dict[str, Any]], float, float]:
    """Make per-question marks and the global correct value agree.

    Uniform papers (the default) come out exactly as the spec describes:
    50 questions × 100 marks → 2 marks each, +2 correct, -0.25 wrong, 0 skip.
    """
    count = len(questions)
    if not count:
        return questions, correct_marks or 0.0, 0.0

    if correct_marks is None:
        explicit = [q.get("marks") or 0 for q in questions]
        if all(float(m) > 0 for m in explicit):
            # uploaded papers carry their own marks: scale them to the total
            raw_total = sum(float(m) for m in explicit)
            scale = total_marks / raw_total if raw_total else 1.0
            for question in questions:
                question["marks"] = _round(float(question["marks"]) * scale, 2)
            correct = _round(total_marks / count, 2)
        else:
            correct = _round(total_marks / count, 2)
            for question in questions:
                question["marks"] = correct
    else:
        correct = _round(correct_marks, 2)
        for question in questions:
            question["marks"] = correct
        total_marks = _round(correct * count, 2)

    return questions, correct, _round(total_marks, 2)


# ---------------------------------------------------------------------------
# AI question generation
# ---------------------------------------------------------------------------
_DIFFICULTY_BRIEF = {
    "easy": "basic recall and single-step understanding",
    "medium": "application and analysis, mixed conceptual and numerical",
    "hard": "synthesis, evaluation and multi-step problem solving",
    "real_exam": "the mix of a real university final: definitions, derivations "
    "and numerical problems in the proportions a paper setter would use",
}


async def _generate_questions(
    uid: str,
    *,
    subject: str,
    topic: str,
    difficulty: str,
    count: int,
    material_text: str = "",
) -> list[dict[str, Any]]:
    prompt = (
        "You are an exam paper setter for university students in Bangladesh.\n"
        f"Write {count} {subject} exam questions.\n"
        f"Difficulty: {_DIFFICULTY_BRIEF.get(difficulty, _DIFFICULTY_BRIEF['medium'])}.\n"
    )
    if topic:
        prompt += f"Focus topic: {topic}\n"
    if material_text:
        prompt += (
            "\nBase the questions on this study material:\n"
            f"{material_text[:6000]}\n"
        )
    prompt += (
        "\nEach question needs: the question text, 4 options (A-D) for MCQs, "
        "the correct answer, a one-line explanation and its topic.\n"
        "Return ONLY valid JSON:\n"
        '{"questions": [{"question": "...", "type": "mcq", '
        '"options": ["...", "...", "...", "..."], "correct": "B", '
        '"explanation": "...", "topic": "...", "marks": 0}]}\n'
        "Short-answer questions are allowed only when a numeric or one-word "
        "answer is natural."
    )

    try:
        raw = await _ai_generate(uid, prompt, AiFeature.QUIZ)
        payload = _extract_json(raw)
    except Exception as exc:  # quota, provider, malformed reply
        logger.warning("exam question generation failed: %s", exc)
        raise ExamError(
            502,
            "Could not generate questions right now — try again, or upload "
            "your own question paper instead.",
        ) from exc

    items = payload.get("questions") or []
    if isinstance(items, dict):  # {"0": {...}} style
        items = list(items.values())
    return items


# ---------------------------------------------------------------------------
# upload / extraction
# ---------------------------------------------------------------------------
def _detect_kind(filename: str, content_type: str) -> str:
    name = (filename or "").lower()
    ctype = (content_type or "").lower()
    if "pdf" in ctype or name.endswith(".pdf"):
        return "pdf"
    if ctype.startswith("image/") or name.endswith((".png", ".jpg", ".jpeg", ".webp")):
        return "image"
    if "text" in ctype or name.endswith((".txt", ".text")):
        return "text"
    raise ExamError(415, "Upload a PDF, image or text file")


def _extract_text(filename: str, content_type: str, data: bytes) -> tuple[str, str]:
    """(text, source) — PDF text layer first, then OCR, then plain decode."""
    kind = _detect_kind(filename, content_type)
    if kind == "text":
        return data.decode("utf-8", errors="replace"), "text"
    if kind == "pdf":
        try:
            text = pdf_service.extract_pdf_text(data, max_chars=UPLOAD_MAX_CHARS)
        except Exception:
            text = ""
        if len(text.strip()) >= 40:
            return text, "pdf_text"
        try:
            return ocr_service.extract_text(data, content_type or "application/pdf"), "ocr"
        except Exception as exc:
            raise ExamError(422, "This PDF has no readable text") from exc
    try:
        return ocr_service.extract_text(data, content_type), "ocr"
    except ExamError:
        raise
    except Exception as exc:
        raise ExamError(422, "Could not read this image") from exc


# Deterministic second pass: numbered lines and A/B/C/D option rows. Used on
# its own when the AI is unavailable, so a student can still get their paper
# into the hall without a network round trip.
_NUMBERED_RE = re.compile(r"^\s*(?:Q(?:uestion)?\s*)?(\d{1,3})[.)]\s+(.*)$")
_OPTION_RE = re.compile(r"^\s*\(?([A-F])[.)]\s+(.*)$")


def _fallback_parse(text: str, limit: int) -> list[dict[str, Any]]:
    questions: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    def _close() -> None:
        nonlocal current
        if current and current.get("question"):
            questions.append(current)
        current = None

    for line in str(text or "").splitlines():
        numbered = _NUMBERED_RE.match(line)
        option = _OPTION_RE.match(line)
        if numbered and not (option and len(numbered.group(2)) < 3):
            _close()
            current = {"question": numbered.group(2).strip(), "options": []}
        elif option and current is not None:
            current.setdefault("options", []).append(option.group(2).strip())
        elif line.strip():
            if current is None:
                current = {"question": line.strip(), "options": []}
            else:
                current["question"] = f"{current['question']} {line.strip()}".strip()
        if len(questions) >= limit:
            break
    _close()
    return questions[:limit]


async def _ai_parse_paper(
    uid: str, text: str, *, subject: str, count: int
) -> list[dict[str, Any]]:
    prompt = (
        "You are digitising a question paper for an exam simulator.\n"
        f"Subject: {subject or 'unknown'}.\n"
        "Extract up to "
        f"{count} questions. For each one detect: the question text, the MCQ "
        "options when present, the correct answer (infer it when the paper "
        "does not give an answer key — leave it empty only if you truly "
        "cannot), the topic, the marks when stated, and a one-line "
        "explanation. Mark needsReview true whenever the answer was inferred "
        "or is missing.\n\n"
        "Return ONLY valid JSON:\n"
        '{"questions": [{"question": "...", "type": "mcq", "options": ["..."],'
        ' "correct": "A", "topic": "...", "marks": 0, "explanation": "...",'
        ' "needsReview": true}]}\n\n'
        f"PAPER:\n{text[:12000]}"
    )
    raw = await _ai_generate(uid, prompt, AiFeature.QUIZ)
    payload = _extract_json(raw)
    items = payload.get("questions") or []
    if isinstance(items, dict):
        items = list(items.values())
    return items[:count]


async def upload_paper(
    uid: str,
    *,
    filename: str,
    content_type: str,
    data: bytes,
    subject: str = "",
    question_count: int = 25,
) -> dict[str, Any]:
    """Extract + digitise a paper. Stateless: the corrected list is sent back
    with ``POST /api/exams/create``, which is the manual-correction step."""
    if not data:
        raise ExamError(400, "The file is empty")
    if len(data) > UPLOAD_MAX_BYTES:
        raise ExamError(413, "File is larger than 10 MB")

    _detect_kind(filename, content_type)
    text, source = _extract_text(filename, content_type, data)
    text = (text or "").strip()
    if len(text) < 20:
        raise ExamError(422, "No readable text found in this file")

    limit = _clamp(int(question_count), MIN_QUESTIONS, MAX_QUESTIONS)

    items: list[dict[str, Any]] = []
    parser = "ai"
    try:
        items = await _ai_parse_paper(uid, text, subject=subject, count=int(limit))
    except Exception as exc:  # quota / provider / malformed — still usable
        logger.warning("upload AI parse failed, using line parser: %s", exc)
        parser = "line_parser"
        items = _fallback_parse(text, int(limit))
    if not items:
        parser = "line_parser"
        items = _fallback_parse(text, int(limit))
    if not items:
        raise ExamError(422, "Could not find any questions in this file")

    questions = [
        _normalize_question(item, index, subject=subject)
        for index, item in enumerate(items)
    ]
    warnings: list[str] = []
    review = [q["index"] for q in questions if q["needsReview"]]
    if review:
        warnings.append(
            f"{len(review)} question(s) need an answer or a check before the "
            "exam can start"
        )

    return {
        "filename": filename or "paper",
        "textSource": source,
        "parser": parser,
        "questionCount": len(questions),
        "questions": questions,
        "needsReview": review,
        "warnings": warnings,
        "preview": text[:600],
    }


# ---------------------------------------------------------------------------
# exam creation
# ---------------------------------------------------------------------------
def _questions_from_quiz_results(
    uid: str, *, subject: str, count: int
) -> list[dict[str, Any]]:
    """Option C — re-use questions the student has already been tested on."""
    collection = _db().collection("users").document(uid).collection(QUIZ_RESULTS)
    rows = list(collection.order_by("createdAt", direction="DESCENDING").limit(50).stream())

    picked: list[dict[str, Any]] = []
    for snap in rows:
        data = snap.to_dict() or {}
        if subject and str(data.get("subjectId") or "").lower() not in (
            "",
            subject.lower(),
        ):
            continue
        questions = data.get("questions") or []
        answers = data.get("correctAnswers") or []
        topics = data.get("topicScores") or {}
        for index, question in enumerate(questions):
            if len(picked) >= count:
                break
            if isinstance(question, dict):
                item = dict(question)
                if not item.get("correct") and index < len(answers):
                    item["correct"] = answers[index]
                item.setdefault("topic", str(data.get("subjectId") or "General"))
                picked.append(item)
        if len(picked) >= count:
            break

    if not picked:
        raise ExamError(
            404,
            "No saved questions yet — finish a quiz first, or use AI / upload",
        )
    return picked


def _questions_from_exam(uid: str, source_exam_id: str, count: int) -> list[dict[str, Any]]:
    _load_exam(uid, source_exam_id)  # 404 when it is not theirs / not there
    rows = _load_questions(uid, source_exam_id)
    if not rows:
        raise ExamError(404, "That exam has no questions")
    return [{k: v for k, v in row.items()} for row in rows[:count]]


async def create_exam(
    uid: str,
    *,
    subject: str,
    source: str = "ai",
    question_count: int = 25,
    total_marks: float = 100.0,
    time_limit_minutes: int = 60,
    negative_marking: bool = True,
    penalty: float | None = None,
    correct_marks: float | None = None,
    skip_marks: float = DEFAULT_SKIP_MARKS,
    difficulty: str = "medium",
    topic: str = "",
    title: str = "",
    questions: list[dict[str, Any]] | None = None,
    source_exam_id: str = "",
    material_text: str = "",
    allow_pause: bool = True,
) -> dict[str, Any]:
    subject = (subject or "").strip() or "General"
    source = (source or "ai").strip().lower()
    difficulty = (difficulty or "medium").strip().lower()

    if source not in SOURCES:
        raise ExamError(400, f"source must be one of: {', '.join(SOURCES)}")
    if difficulty not in DIFFICULTIES:
        raise ExamError(400, f"difficulty must be one of: {', '.join(DIFFICULTIES)}")

    count = int(question_count)
    if count < MIN_QUESTIONS or count > MAX_QUESTIONS:
        raise ExamError(
            400, f"totalQuestions must be between {MIN_QUESTIONS} and {MAX_QUESTIONS}"
        )
    if total_marks <= 0:
        raise ExamError(400, "totalMarks must be greater than 0")
    if time_limit_minutes < 1 or time_limit_minutes > MAX_TIME_MINUTES:
        raise ExamError(400, f"timeLimitMinutes must be 1-{MAX_TIME_MINUTES}")

    material_text = str(material_text or "")[:15000]

    raw_items: list[dict[str, Any]]
    if questions:
        raw_items = questions
        source = source if source in ("upload", "manual", "saved") else "upload"
    elif source == "saved":
        if source_exam_id:
            raw_items = _questions_from_exam(uid, source_exam_id, count)
        else:
            raw_items = _questions_from_quiz_results(uid, subject=subject, count=count)
    else:
        raw_items = await _generate_questions(
            uid,
            subject=subject,
            topic=topic,
            difficulty=difficulty,
            count=count,
            material_text=material_text,
        )
        if not raw_items:
            raise ExamError(502, "The AI returned no questions — try again")

    normalized = [
        _normalize_question(item, index, subject=subject)
        for index, item in enumerate(raw_items[:count])
    ]
    _validate_for_exam(normalized)

    default_correct = _round(total_marks / len(normalized), 2)
    normalized, correct_value, total_value = _distribute_marks(
        normalized, float(total_marks), correct_marks
    )

    penalty_value = DEFAULT_PENALTY if negative_marking else 0.0
    if penalty is not None:
        penalty_value = max(0.0, _round(float(penalty), 2))
        if not negative_marking:
            penalty_value = 0.0
    skip_value = _round(float(skip_marks), 2)

    now = _now()
    exam_ref = _exams_collection(uid).document()
    exam_id = exam_ref.id

    exam_doc = {
        "ownerId": uid,
        "examId": exam_id,
        "title": (title or "").strip() or f"{subject} exam",
        "subject": subject,
        "topic": (topic or "").strip(),
        "source": source,
        "sourceExamId": source_exam_id or "",
        "difficulty": difficulty,
        "questionCount": len(normalized),
        "totalMarks": total_value,
        "timeLimitMinutes": int(time_limit_minutes),
        "negativeMarking": bool(negative_marking),
        "correctMarks": correct_value or default_correct,
        "penalty": penalty_value,
        "skipMarks": skip_value,
        "attemptCount": 0,
        # Phase 6 — the exam-room controls and the community-ready privacy
        # fields. ``allowPause`` is the builder's optional "pause exam"
        # setting; ``visibility`` keeps every paper private until its owner
        # deliberately shares it (marks are never shared, only the paper).
        "allowPause": bool(allow_pause),
        "visibility": "private",
        "shareCode": "",
        "createdAt": now,
        "dayKey": _day_key(now),
        "monthKey": _month_key(now),
    }
    exam_ref.set(exam_doc)

    question_collection = _questions_collection(uid, exam_id)
    for question in normalized:
        question_collection.document(f"q_{question['index']:03d}").set(
            {"ownerId": uid, "examId": exam_id, **question}
        )

    logger.info(
        "exam created: uid=%s exam=%s source=%s questions=%d difficulty=%s",
        uid,
        exam_id,
        source,
        len(normalized),
        difficulty,
    )
    return {
        **_public_exam(exam_doc),
        "questions": [_redact_question(q) for q in normalized],
        "questionCount": len(normalized),
    }


def _public_exam(data: dict[str, Any]) -> dict[str, Any]:
    return {
        "examId": str(data.get("examId") or ""),
        "title": str(data.get("title") or ""),
        "subject": str(data.get("subject") or ""),
        "topic": str(data.get("topic") or ""),
        "source": str(data.get("source") or "ai"),
        "difficulty": str(data.get("difficulty") or "medium"),
        "questionCount": int(data.get("questionCount") or 0),
        "totalMarks": _to_float(data.get("totalMarks")),
        "timeLimitMinutes": int(data.get("timeLimitMinutes") or 0),
        "negativeMarking": bool(data.get("negativeMarking")),
        "correctMarks": _to_float(data.get("correctMarks")),
        "penalty": _to_float(data.get("penalty")),
        "skipMarks": _to_float(data.get("skipMarks")),
        "attemptCount": int(data.get("attemptCount") or 0),
        "allowPause": bool(data.get("allowPause", True)),
        "visibility": str(data.get("visibility") or "private"),
        "shareCode": str(data.get("shareCode") or ""),
        "createdAt": data.get("createdAt"),
        "dayKey": str(data.get("dayKey") or ""),
    }


def _redact_question(question: dict[str, Any]) -> dict[str, Any]:
    """Questions leave the server without answers — no hints, ever."""
    return {
        "index": int(question.get("index") or 0),
        "question": str(question.get("question") or ""),
        "type": str(question.get("type") or "mcq"),
        "options": list(question.get("options") or []),
        "topic": str(question.get("topic") or ""),
        "marks": _to_float(question.get("marks")),
        "difficulty": str(question.get("difficulty") or "medium"),
        "needsReview": bool(question.get("needsReview")),
    }


def get_exam(uid: str, exam_id: str, *, include_questions: bool = False) -> dict[str, Any]:
    _, exam = _load_exam(uid, exam_id)
    payload = _public_exam(exam)
    payload["questions"] = [
        _redact_question(q) for q in _load_questions(uid, exam_id)
    ] if include_questions else []
    payload["hasQuestions"] = len(payload["questions"]) > 0 or bool(
        exam.get("questionCount")
    )
    payload["attempts"] = _attempt_summaries(uid, exam_id)
    payload["results"] = _result_summaries(uid, exam_id, limit=5)
    return payload


def list_exams(uid: str, *, limit: int = 20) -> list[dict[str, Any]]:
    rows = (
        _exams_collection(uid)
        .order_by("createdAt", direction="DESCENDING")
        .limit(limit)
        .stream()
    )
    return [_public_exam(snap.to_dict() or {}) for snap in rows]


def _attempt_summaries(uid: str, exam_id: str) -> list[dict[str, Any]]:
    rows = (
        _attempts_collection(uid)
        .where("examId", "==", exam_id)
        .order_by("startedAt", direction="DESCENDING")
        .limit(10)
        .stream()
    )
    out = []
    for snap in rows:
        data = snap.to_dict() or {}
        out.append(
            {
                "attemptId": str(data.get("attemptId") or snap.id),
                "status": str(data.get("status") or "running"),
                "startedAt": data.get("startedAt"),
                "submittedAt": data.get("submittedAt"),
                "timeSpentSeconds": int(data.get("timeSpentSeconds") or 0),
            }
        )
    return out


def _result_summaries(uid: str, exam_id: str, *, limit: int = 5) -> list[dict[str, Any]]:
    rows = (
        _results_collection(uid)
        .where("examId", "==", exam_id)
        .order_by("createdAt", direction="DESCENDING")
        .limit(limit)
        .stream()
    )
    out: list[dict[str, Any]] = []
    for snap in rows:
        data = snap.to_dict() or {}
        out.append(
            {
                "resultId": str(snap.id),
                "attemptId": str(data.get("attemptId") or ""),
                "score": _to_float(data.get("score")),
                "totalMarks": _to_float(data.get("totalMarks")),
                "percentage": _to_float(data.get("percentage")),
                "accuracy": _to_float(data.get("accuracy")),
                "weakTopics": list(data.get("weakTopics") or []),
                "createdAt": data.get("createdAt"),
            }
        )
    return out


# ---------------------------------------------------------------------------
# exam hall
# ---------------------------------------------------------------------------
def start_attempt(uid: str, exam_id: str) -> dict[str, Any]:
    _, exam = _load_exam(uid, exam_id)
    questions = _load_questions(uid, exam_id)
    if not questions:
        raise ExamError(409, "This exam has no questions")

    now = _now()
    minutes = int(exam.get("timeLimitMinutes") or 60)
    attempt_ref = _attempts_collection(uid).document()
    attempt_id = attempt_ref.id
    deadline = now + timedelta(minutes=minutes)

    attempt_doc = {
        "ownerId": uid,
        "attemptId": attempt_id,
        "examId": exam_id,
        "subject": str(exam.get("subject") or ""),
        "status": "running",
        "startedAt": now,
        "deadlineAt": deadline,
        "submittedAt": None,
        "timeSpentSeconds": 0,
        "answers": {},
        "markedForReview": [],
        "dayKey": _day_key(now),
    }
    attempt_ref.set(attempt_doc)

    try:
        from app.services.analytics_service import track_event
        track_event(
            uid,
            "exam_started",
            {
                "subject": str(exam.get("subject") or ""),
                "feature": "exam_simulator",
                "exam_type": str(exam.get("difficulty") or "real_exam"),
            },
        )
    except Exception:
        pass

    return {
        "attemptId": attempt_id,
        "examId": exam_id,
        "title": str(exam.get("title") or ""),
        "subject": str(exam.get("subject") or ""),
        "startedAt": now,
        "deadlineAt": deadline,
        "timeLimitMinutes": minutes,
        "timeLimitSeconds": minutes * 60,
        "totalMarks": _to_float(exam.get("totalMarks")),
        "negativeMarking": bool(exam.get("negativeMarking")),
        "correctMarks": _to_float(exam.get("correctMarks")),
        "penalty": _to_float(exam.get("penalty")),
        "skipMarks": _to_float(exam.get("skipMarks")),
        "allowPause": bool(exam.get("allowPause", True)),
        "questions": [_redact_question(q) for q in questions],
    }


def _load_attempt(uid: str, attempt_id: str) -> tuple[str, dict[str, Any]]:
    found = _read_doc(_attempts_collection(uid), attempt_id)
    if found is None:
        raise ExamError(404, "Attempt not found")
    return found


def _normalize_answers(raw: Any, count: int) -> list[str]:
    answers: list[str] = []
    if isinstance(raw, dict):
        for index in range(count):
            value = raw.get(str(index), raw.get(index, ""))
            answers.append(str(value or "").strip())
    elif isinstance(raw, (list, tuple)):
        answers = [str(value or "").strip() for value in list(raw)[:count]]
    while len(answers) < count:
        answers.append("")
    return answers


def classify_mistake_type(question: dict[str, Any]) -> str:
    """Concept / calculation / memory — deterministic, override via the paper."""
    hint = str(question.get("mistakeTypeHint") or "").strip().lower()
    if hint in MISTAKE_TYPES:
        return hint
    blob = f"{question.get('question') or ''} {question.get('explanation') or ''}".lower()
    if any(token in blob for token in _MEMORY_HINTS):
        return "memory"
    if _NUMERIC_RE.search(str(question.get("question") or "")):
        return "calculation"
    return "concept"


def _review_dates(today: datetime) -> list[str]:
    base = today.date()
    return [
        (base + timedelta(days=offset)).isoformat() for offset in (1, 7, 30)
    ]


def _time_management(
    used_seconds: int, limit_seconds: int, unanswered: int, total: int
) -> tuple[str, str, str]:
    ratio = (used_seconds / limit_seconds) if limit_seconds else 0.0
    skipped_ratio = (unanswered / total) if total else 0.0
    if ratio <= 1.05 and skipped_ratio <= 0.10:
        status = "good"
    elif ratio <= 1.30 and skipped_ratio <= 0.30:
        status = "fair"
    else:
        status = "poor"
    label = {"good": "Good", "fair": "Fair", "poor": "Needs work"}[status]
    used_minutes = round(used_seconds / 60)
    limit_minutes = round(limit_seconds / 60) if limit_seconds else 0
    detail = (
        f"{used_minutes} of {limit_minutes} min used · {unanswered} unanswered"
    )
    return status, label, detail


async def submit_attempt(
    uid: str,
    exam_id: str,
    *,
    attempt_id: str,
    answers: Any,
    time_spent_seconds: int | None = None,
    marked_for_review: list[int] | None = None,
    with_ai_analysis: bool = True,
) -> dict[str, Any]:
    _, exam = _load_exam(uid, exam_id)
    attempt_key, attempt = _load_attempt(uid, attempt_id)

    if str(attempt.get("examId") or "") != exam_id:
        raise ExamError(400, "That attempt belongs to a different exam")
    if str(attempt.get("status") or "") == "submitted":
        raise ExamError(409, "This attempt has already been submitted")

    questions = _load_questions(uid, exam_id)
    if not questions:
        raise ExamError(409, "This exam has no questions")

    started = _to_dt(attempt.get("startedAt")) or _now()
    now = _now()
    limit_seconds = int(exam.get("timeLimitMinutes") or 60) * 60
    if time_spent_seconds is None:
        elapsed = int((now - started).total_seconds())
    else:
        elapsed = int(time_spent_seconds or 0)
    elapsed = max(0, min(elapsed, limit_seconds + SUBMIT_GRACE_SECONDS))
    overtime = max(0, elapsed - limit_seconds)
    used_seconds = min(elapsed, limit_seconds)

    user_answers = _normalize_answers(answers, len(questions))
    correct_count = 0
    wrong_count = 0
    skipped_count = 0
    raw_score = 0.0

    correct_marks = _to_float(exam.get("correctMarks"))
    penalty = _to_float(exam.get("penalty")) if exam.get("negativeMarking") else 0.0
    skip_marks = _to_float(exam.get("skipMarks"))
    negative = bool(exam.get("negativeMarking"))

    topic_total: dict[str, int] = {}
    topic_correct: dict[str, int] = {}
    topic_attempted: dict[str, int] = {}

    mistake_rows: list[dict[str, Any]] = []
    today = _now()
    ladder = _review_dates(today)

    for index, question in enumerate(questions):
        given = user_answers[index] if index < len(user_answers) else ""
        reference = str(question.get("correct") or "").strip()
        topic = str(question.get("topic") or "General") or "General"
        marks = _to_float(question.get("marks"), correct_marks) or correct_marks

        topic_total[topic] = topic_total.get(topic, 0) + 1

        if not given:
            skipped_count += 1
            raw_score += skip_marks
            continue

        topic_attempted[topic] = topic_attempted.get(topic, 0) + 1
        if mistake_memory.answers_match(given, reference):
            correct_count += 1
            raw_score += marks
            topic_correct[topic] = topic_correct.get(topic, 0) + 1
        else:
            wrong_count += 1
            if negative:
                raw_score -= penalty
            mistake_rows.append(
                {
                    "index": index,
                    "topic": topic,
                    "question": str(question.get("question") or "")[:1000],
                    "userAnswer": given[:500],
                    "correctAnswer": reference[:500],
                    "type": classify_mistake_type(question),
                    "explanation": str(question.get("explanation") or "")[:600],
                    "difficulty": str(question.get("difficulty") or "medium"),
                    "reviewDates": list(ladder),
                    "quizId": "",  # filled after the result document exists
                }
            )

    attempted = correct_count + wrong_count
    accuracy = _round((correct_count / attempted) * 100, 1) if attempted else 0.0
    total_marks = _to_float(exam.get("totalMarks"))
    score = _round(max(raw_score, 0.0), 2)
    if total_marks <= 0:
        total_marks = _round(correct_marks * len(questions), 2) or 1.0
    # never report more than the paper is worth
    score = _round(min(score, total_marks), 2)
    percentage = _round((score / total_marks) * 100, 1)

    topic_scores: dict[str, int] = {}
    weak_topics: list[str] = []
    topic_accuracy: dict[str, float] = {}
    for topic, total in topic_total.items():
        attempted_topic = topic_attempted.get(topic, 0)
        if not attempted_topic:
            continue
        value = _round((topic_correct.get(topic, 0) / attempted_topic) * 100, 0)
        topic_scores[topic] = int(value)
        topic_accuracy[topic] = value
        if value < DEFAULT_WEAK_THRESHOLD:
            weak_topics.append(topic)
    weak_topics.sort(key=lambda name: topic_accuracy.get(name, 0))

    time_status, time_label, time_detail = _time_management(
        used_seconds, limit_seconds, skipped_count, len(questions)
    )

    # ---- Quiz system + Mistake Memory -----------------------------------
    result_ref = _results_collection(uid).document()
    result_id = result_ref.id

    quiz_ref = (
        _db()
        .collection("users")
        .document(uid)
        .collection(QUIZ_RESULTS)
        .document()
    )
    quiz_id = quiz_ref.id
    quiz_doc = {
        "ownerId": uid,
        "subjectId": str(exam.get("subject") or ""),
        "materialId": "",
        "examId": exam_id,
        "attemptId": attempt_id,
        "questions": [q.get("question") for q in questions],
        "userAnswers": user_answers,
        "correctAnswers": [str(q.get("correct") or "") for q in questions],
        "totalQuestions": len(questions),
        "correctCount": correct_count,
        "score": int(round(percentage)),
        "topicScores": topic_scores,
        "difficulty": str(exam.get("difficulty") or "medium"),
        "timeSpentSeconds": used_seconds,
        "createdAt": now,
        "dayKey": _day_key(now),
        "monthKey": _month_key(now),
    }
    quiz_ref.set(quiz_doc)

    for row in mistake_rows:
        row["quizId"] = quiz_id

    try:
        mistake_summary = mistake_memory.capture_mistakes(
            uid,
            quiz_id=quiz_id,
            subject_id=str(exam.get("subject") or ""),
            difficulty=str(exam.get("difficulty") or "medium"),
            questions=questions,
            user_answers=user_answers,
            correct_answers=[str(q.get("correct") or "") for q in questions],
        )
    except Exception as memo_err:  # never lose the result over the memory write
        logger.warning("exam mistake capture failed: %s", memo_err)
        mistake_summary = {
            "captured": 0,
            "new": 0,
            "repeated": 0,
            "pendingAnalysis": 0,
            "mistakeIds": [],
        }

    plan = _ziku_plan(
        subject=str(exam.get("subject") or ""),
        weak_topics=weak_topics,
        mistake_count=int(mistake_summary.get("captured") or 0),
        time_status=time_status,
        rescue=_active_rescue(uid, str(exam.get("subject") or "")),
        today=today,
    )

    ai_analysis = ""
    if with_ai_analysis:
        try:
            ai_analysis = await _ai_generate(
                uid,
                _analysis_prompt(
                    subject=str(exam.get("subject") or ""),
                    percentage=percentage,
                    accuracy=accuracy,
                    weak_topics=weak_topics,
                    correct=correct_count,
                    wrong=wrong_count,
                    skipped=skipped_count,
                    total=len(questions),
                    time_label=time_label,
                    mistake_count=int(mistake_summary.get("captured") or 0),
                    plan=plan,
                ),
                AiFeature.CHAT,
            )
            ai_analysis = str(ai_analysis or "").strip()[:4000]
        except Exception as exc:
            logger.info("exam AI analysis unavailable, using plan: %s", exc)
            ai_analysis = ""

    result_doc = {
        "ownerId": uid,
        "resultId": result_id,
        "examId": exam_id,
        "attemptId": attempt_id,
        "quizId": quiz_id,
        "subject": str(exam.get("subject") or ""),
        "difficulty": str(exam.get("difficulty") or "medium"),
        "source": str(exam.get("source") or "ai"),
        "score": score,
        "totalMarks": total_marks,
        "percentage": percentage,
        "correctCount": correct_count,
        "wrongCount": wrong_count,
        "skippedCount": skipped_count,
        "totalQuestions": len(questions),
        "accuracy": accuracy,
        "negativeMarking": bool(exam.get("negativeMarking")),
        "correctMarks": correct_marks,
        "penalty": penalty,
        "timeSpentSeconds": used_seconds,
        "timeLimitSeconds": limit_seconds,
        "overtimeSeconds": overtime,
        "timeManagement": time_status,
        "timeManagementLabel": time_label,
        "timeManagementDetail": time_detail,
        "topicScores": topic_scores,
        "topicAccuracy": topic_accuracy,
        "weakTopics": weak_topics[:5],
        "markedForReview": [int(i) for i in (marked_for_review or [])],
        "mistakes": mistake_rows,
        "mistakeCount": len(mistake_rows),
        "newMistakes": int(mistake_summary.get("new") or 0),
        "repeatedMistakes": int(mistake_summary.get("repeated") or 0),
        "pendingAnalysis": int(mistake_summary.get("pendingAnalysis") or 0),
        "zikuPlan": plan,
        "zikuAnalysis": ai_analysis,
        "createdAt": now,
        "dayKey": _day_key(now),
        "monthKey": _month_key(now),
    }
    result_ref.set(result_doc)

    _attempts_collection(uid).document(attempt_key).set(
        {
            **attempt,
            "status": "submitted",
            "submittedAt": now,
            "timeSpentSeconds": used_seconds,
            "answers": {str(i): a for i, a in enumerate(user_answers) if a},
            "markedForReview": [int(i) for i in (marked_for_review or [])],
            "resultId": result_id,
            "score": score,
            "percentage": percentage,
        }
    )
    _bump_attempt_count(uid, exam_id)

    logger.info(
        "exam submitted: uid=%s exam=%s attempt=%s score=%s/%s accuracy=%s",
        uid,
        exam_id,
        attempt_id,
        score,
        total_marks,
        accuracy,
    )

    try:
        from app.services.analytics_service import track_event
        track_event(
            uid,
            "exam_completed",
            {
                "subject": str(exam.get("subject") or ""),
                "feature": "exam_simulator",
                "exam_type": str(exam.get("difficulty") or "real_exam"),
                "score": score,
                "total": total_marks,
                "mistake_count": wrong_count,
                "duration_seconds": used_seconds,
            },
        )
    except Exception:
        pass

    return _result_payload(result_doc, result_id)


def _bump_attempt_count(uid: str, exam_id: str) -> None:
    try:
        exam = _exams_collection(uid).document(exam_id)
        snap = exam.get()
        if snap.exists:
            data = snap.to_dict() or {}
            exam.set({**data, "attemptCount": int(data.get("attemptCount") or 0) + 1})
    except Exception as exc:  # cosmetic counter
        logger.debug("attempt counter update failed: %s", exc)


def _result_payload(result: dict[str, Any], result_id: str) -> dict[str, Any]:
    return {
        "resultId": result_id,
        "examId": str(result.get("examId") or ""),
        "attemptId": str(result.get("attemptId") or ""),
        "score": _to_float(result.get("score")),
        "totalMarks": _to_float(result.get("totalMarks")),
        "percentage": _to_float(result.get("percentage")),
        "accuracy": _to_float(result.get("accuracy")),
        "correctCount": int(result.get("correctCount") or 0),
        "wrongCount": int(result.get("wrongCount") or 0),
        "skippedCount": int(result.get("skippedCount") or 0),
        "totalQuestions": int(result.get("totalQuestions") or 0),
        "timeSpentSeconds": int(result.get("timeSpentSeconds") or 0),
        "timeLimitSeconds": int(result.get("timeLimitSeconds") or 0),
        "timeManagement": str(result.get("timeManagement") or ""),
        "timeManagementLabel": str(result.get("timeManagementLabel") or ""),
        "timeManagementDetail": str(result.get("timeManagementDetail") or ""),
        "topicScores": dict(result.get("topicScores") or {}),
        "weakTopics": list(result.get("weakTopics") or []),
        "mistakeCount": int(result.get("mistakeCount") or 0),
        "mistakes": list(result.get("mistakes") or []),
        "newMistakes": int(result.get("newMistakes") or 0),
        "repeatedMistakes": int(result.get("repeatedMistakes") or 0),
        "pendingAnalysis": int(result.get("pendingAnalysis") or 0),
        "zikuPlan": dict(result.get("zikuPlan") or {}),
        "zikuAnalysis": str(result.get("zikuAnalysis") or ""),
        "quizId": str(result.get("quizId") or ""),
        "createdAt": result.get("createdAt"),
    }


# ---------------------------------------------------------------------------
# analysis
# ---------------------------------------------------------------------------
def _active_rescue(uid: str, subject: str) -> dict[str, Any] | None:
    """Nearest active Exam Rescue plan — read only, never written from here."""
    try:
        rows = (
            _db()
            .collection("users")
            .document(uid)
            .collection("exam_rescue")
            .stream()
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("rescue lookup failed: %s", exc)
        return None

    today = _now().date()
    best: tuple[datetime, dict[str, Any]] | None = None
    for snap in rows:
        data = snap.to_dict() or {}
        if str(data.get("status") or "") != "active":
            continue
        exam_day = _to_dt(data.get("examDate"))
        if exam_day is None:
            continue
        if subject and str(data.get("subject") or "").lower() not in (
            "",
            subject.lower(),
        ):
            continue
        if exam_day.date() < today:
            continue
        if best is None or exam_day < best[0]:
            best = (exam_day, data)
    if best is None:
        return None
    exam_day, data = best
    return {
        "sessionId": str(data.get("sessionId") or ""),
        "title": str(data.get("examTitle") or data.get("title") or ""),
        "examDate": _day_key(exam_day),
        "daysRemaining": (exam_day.date() - today).days,
        "dailyTargetMinutes": int(data.get("dailyTargetMinutes") or 0),
    }


def _ziku_plan(
    *,
    subject: str,
    weak_topics: list[str],
    mistake_count: int,
    time_status: str,
    rescue: dict[str, Any] | None,
    today: datetime,
) -> dict[str, Any]:
    """The fixed 3-day recovery plan the result screen renders verbatim.

    Deliberately deterministic: the plan is the same every time the result is
    opened, and it is built from data the student already owns. The AI
    paragraph on top of it is the only generated part.
    """
    topics = [t for t in weak_topics if t][:3]
    if not topics:
        topics = ["the topics you found hardest"]
    days_remaining = int((rescue or {}).get("daysRemaining") or 0)

    day1 = f"Review {', '.join(topics[:2])}"
    day2 = (
        f"Solve 20 MCQ on {topics[0]}"
        + (f" and {topics[1]}" if len(topics) > 1 else "")
    )
    day3 = "Take a mini test on " + (subject or "the subject")
    if rescue and days_remaining and days_remaining <= 7:
        # Exam Rescue owns the calendar: never schedule a mock after the real
        # exam, and pull the last day in when the real paper is close.
        day3 = (
            f"Mini test on {subject} before your exam on "
            f"{rescue.get('examDate')}"
        )
    if mistake_count:
        day1 += f" · revise {mistake_count} mistake(s)"

    steps = [
        {"day": 1, "focus": day1, "kind": "review"},
        {"day": 2, "focus": day2, "kind": "practice"},
        {"day": 3, "focus": day3, "kind": "test"},
    ]
    headline = (
        f"{subject} exam analysis: "
        f"{', '.join(topics)} need work."
    )
    if time_status == "poor":
        headline += " Practice under a timer."
    return {
        "subject": subject,
        "weakTopics": topics,
        "days": steps,
        "daysRemaining": days_remaining,
        "rescueSessionId": str((rescue or {}).get("sessionId") or ""),
        "headline": headline,
        "text": headline + " " + " ".join(f"Day {s['day']}: {s['focus']}." for s in steps),
    }


def _analysis_prompt(
    *,
    subject: str,
    percentage: float,
    accuracy: float,
    weak_topics: list[str],
    correct: int,
    wrong: int,
    skipped: int,
    total: int,
    time_label: str,
    mistake_count: int,
    plan: dict[str, Any],
) -> str:
    return (
        "You are Ziku, the in-app study assistant for Gochano, a university "
        "student app in Bangladesh.\n"
        "A student just finished a timed mock exam. Write a short, warm "
        "analysis of 5-7 short lines and end with the three-day plan.\n\n"
        f"Subject: {subject}\n"
        f"Score: {percentage:.0f}% · Accuracy: {accuracy:.0f}% · "
        f"Correct {correct} / Wrong {wrong} / Skipped {skipped} of {total}\n"
        f"Time management: {time_label}\n"
        f"Weak topics: {', '.join(weak_topics) or 'none'}\n"
        f"Wrong answers saved to mistake memory: {mistake_count}\n\n"
        "Use the exact plan below for the Day 1 / Day 2 / Day 3 lines:\n"
        + "\n".join(f"Day {d['day']}: {d['focus']}" for d in plan.get("days", []))
        + "\n\nNo markdown headings, no lists longer than the plan, no invented "
        "marks. Reply in the language of the subject's questions (Bangla when "
        "the questions are Bangla, otherwise English)."
    )


def _latest_result(
    uid: str, exam_id: str, attempt_id: str | None
) -> tuple[str, dict[str, Any]]:
    query = _results_collection(uid).where("examId", "==", exam_id)
    if attempt_id:
        query = _results_collection(uid).where("attemptId", "==", attempt_id)
    rows = list(query.order_by("createdAt", direction="DESCENDING").limit(1).stream())
    if not rows:
        raise ExamError(
            404, "No result yet — submit the exam before asking for analysis"
        )
    snap = rows[0]
    return snap.id, (snap.to_dict() or {})


async def get_analysis(
    uid: str,
    exam_id: str,
    *,
    attempt_id: str | None = None,
    with_ai: bool = False,
) -> dict[str, Any]:
    """Everything the result screen shows — no AI spend unless asked twice."""
    _load_exam(uid, exam_id)
    result_id, result = _latest_result(uid, exam_id, attempt_id)

    weak_topics = list(result.get("weakTopics") or [])
    topic_accuracy = dict(result.get("topicAccuracy") or {})
    mistakes = list(result.get("mistakes") or [])
    by_type: dict[str, int] = {}
    for row in mistakes:
        key = str(row.get("type") or "concept")
        by_type[key] = by_type.get(key, 0) + 1

    health = _live_health(uid)
    rescue = _active_rescue(uid, str(result.get("subject") or ""))
    plan = dict(result.get("zikuPlan") or {})
    if not plan:
        plan = _ziku_plan(
            subject=str(result.get("subject") or ""),
            weak_topics=weak_topics,
            mistake_count=int(result.get("mistakeCount") or 0),
            time_status=str(result.get("timeManagement") or "fair"),
            rescue=rescue,
            today=_now(),
        )

    payload = {
        **_result_payload(result, result_id),
        "weakTopicDetails": [
            {
                "topic": topic,
                "accuracy": _round(topic_accuracy.get(topic, 0), 0),
                "action": _weak_action(topic, result),
            }
            for topic in weak_topics
        ],
        "mistakeTypes": [
            {"type": key, "label": _mistake_label(key), "count": value}
            for key, value in sorted(
                by_type.items(), key=lambda item: -item[1]
            )
        ],
        "mistakesSaved": {
            "saved": int(result.get("mistakeCount") or 0),
            "new": int(result.get("newMistakes") or 0),
            "repeated": int(result.get("repeatedMistakes") or 0),
            "pendingAnalysis": int(result.get("pendingAnalysis") or 0),
            "reviewDates": (mistakes[0].get("reviewDates") if mistakes else [])
            or [],
        },
        "health": health,
        "rescue": rescue,
        "zikuPlan": plan,
        "zikuAnalysis": str(result.get("zikuAnalysis") or ""),
        "zikuPrompt": (
            f"Analyse my {result.get('subject') or ''} mock exam: "
            f"{_round(result.get('percentage') or 0, 0)}% score, "
            f"accuracy {_round(result.get('accuracy') or 0, 0)}%, weak topics: "
            f"{', '.join(weak_topics) or 'none'}. "
            f"Wrong answers: {result.get('mistakeCount') or 0}. "
            f"Give me a 3-day revision plan."
        ),
        "hasAiAnalysis": bool(str(result.get("zikuAnalysis") or "").strip()),
    }

    # The AI paragraph is generated once per attempt and cached on the result:
    # opening the screen twice never spends quota a second time.
    if with_ai and not payload["hasAiAnalysis"]:
        try:
            text = str(
                await _ai_generate(
                    uid,
                    _analysis_prompt(
                        subject=str(result.get("subject") or ""),
                        percentage=_to_float(result.get("percentage")),
                        accuracy=_to_float(result.get("accuracy")),
                        weak_topics=weak_topics,
                        correct=int(result.get("correctCount") or 0),
                        wrong=int(result.get("wrongCount") or 0),
                        skipped=int(result.get("skippedCount") or 0),
                        total=int(result.get("totalQuestions") or 0),
                        time_label=str(
                            result.get("timeManagementLabel") or "Fair"
                        ),
                        mistake_count=int(result.get("mistakeCount") or 0),
                        plan=plan,
                    ),
                    AiFeature.CHAT,
                )
            ).strip()[:4000]
        except Exception as exc:
            logger.info("exam AI analysis unavailable: %s", exc)
            text = ""
        if text:
            _results_collection(uid).document(result_id).set(
                {**result, "zikuAnalysis": text}
            )
            payload["zikuAnalysis"] = text
            payload["hasAiAnalysis"] = True

    return payload


def _mistake_label(kind: str) -> str:
    return {
        "concept": "Concept error",
        "calculation": "Calculation error",
        # Phase 6 — the result screen says "Careless mistake", which is how a
        # student reads a forgot-the-fact answer; the stored type stays
        # ``memory`` so the Learning Brain's grouping never changes.
        "memory": "Careless mistake",
        "careless": "Careless mistake",
    }.get(kind, "Concept error")


def _weak_action(topic: str, result: dict[str, Any]) -> str:
    accuracy = _round((result.get("topicAccuracy") or {}).get(topic, 0), 0)
    if accuracy < 40:
        return f"Re-learn {topic} from your notes, then retry 10 questions"
    if accuracy < 60:
        return f"Solve 20 MCQ on {topic}"
    return f"Revise {topic} before your next paper"


def _live_health(uid: str) -> dict[str, Any]:
    """The student's health *after* this result landed (read-only)."""
    try:
        from app.services import academic_health_service as health_service

        payload = health_service.get_academic_health(uid, persist=False)
    except Exception as exc:
        logger.debug("academic health unavailable in analysis: %s", exc)
        return {}

    metrics = {
        str(item.get("key")): item for item in payload.get("metrics") or []
    }
    return {
        "score": payload.get("score"),
        "grade": payload.get("grade"),
        "understanding": (metrics.get("understanding") or {}).get("score"),
        "understandingDetail": (metrics.get("understanding") or {}).get("detail"),
        "examReadiness": (metrics.get("examReadiness") or {}).get("score"),
        "examReadinessDetail": (metrics.get("examReadiness") or {}).get("detail"),
        "weakTopics": payload.get("weakAreas") or [],
    }
