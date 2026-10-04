"""Phase 1 — AI Mistake Memory.

Every wrong answer a student submits becomes one durable record, and Ziku
(the existing AI cascade) explains it: why it happened, which concept is
missing, how to correct it, a memory trick, and when to review it again.

Storage
-------
Firestore subcollection ``users/{uid}/mistakes``. One document per *distinct*
mistake, addressed by a deterministic fingerprint of subject + topic +
question, so meeting the same question twice updates one record
(``occurrences``) instead of creating a second copy. That is the same
deterministic-id discipline the ledger (``financial_transactions``) and the
dose schedule (``medicine_doses``) already use: a retry overwrites, a repeat
counts, nothing duplicates.

The AI analysis lives on that same document, so a mistake and its
explanation can never drift apart.

Review schedule
---------------
Pure arithmetic on ``REVIEW_INTERVALS_DAYS = (1, 3, 7, 14, 30)`` — a spaced
ladder that advances each time the student marks the mistake revised and
resets to day 1 when they get it wrong again. It needs no AI, so the queue
keeps working when a provider is down; only the *advice* needs Ziku. Ziku's
``recommendedReviewDate`` is adopted when it parses and fits the window;
otherwise the arithmetic date stands.

Extension points for later phases — stable functions, no rework needed:
  * AI Study Coach        -> ``get_review_queue`` / ``get_learning_brain``
  * Academic Health Score -> ``get_analytics`` (subject/topic aggregates)
  * Real Exam Simulator   -> ``get_review_queue(due_only=True)``
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any

from firebase_admin import firestore
from fastapi import HTTPException

from app.core.firebase import get_firestore
from app.services import ai_service, weak_topic_service
from app.services.ai_service import AiFeature, record_ai_activity

logger = logging.getLogger("gochano.ai_study")

MISTAKES = "mistakes"

ANALYSIS_PENDING = "pending"
ANALYSIS_ANALYZED = "analyzed"
ANALYSIS_FAILED = "failed"

# Spaced-repetition ladder, indexed by how many times the student has already
# revised this mistake. Reset to 0 whenever they get it wrong again.
REVIEW_INTERVALS_DAYS: tuple[int, ...] = (1, 3, 7, 14, 30)

# One AI call analyses a whole batch — a quiz with four wrong answers costs
# one request, not four.
MAX_ANALYSIS_BATCH = 5
# How far ahead Ziku is allowed to push a review date. Anything outside
# [tomorrow, +30 days] is rejected and the arithmetic date stands.
MAX_RECOMMENDED_DELAY_DAYS = 30
# Bounds read by / written to a single mistake document.
MAX_FETCH = 500
_FIELD_LIMITS = {
    "mistakeReason": 400,
    "conceptGap": 400,
    "correctionExplanation": 800,
    "memoryTrick": 400,
}


# ---------------------------------------------------------------------------
# Small pure helpers (no I/O) — these are what the tests pin down first.
# ---------------------------------------------------------------------------

def _normalize(value: Any) -> str:
    """Collapse case and whitespace so 'What  is X?' == 'what is x?'."""
    return " ".join(str(value or "").lower().split())


def mistake_fingerprint(subject_id: str, topic: str, question: str) -> str:
    """Stable identity of a mistake: subject + topic + question.

    Deliberately excludes the wrong answer, so answering the same question
    wrongly twice counts as one repeated mistake rather than two.
    """
    raw = "|".join(
        (_normalize(subject_id), _normalize(topic), _normalize(question))
    )
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:24]


def extract_topic(question: dict[str, Any]) -> str:
    """Topic of one question.

    Mirrors ``_extractTopic`` in the Flutter ``quiz_result_screen`` so the
    topic a student sees on the result screen and the topic a mistake is
    filed under are the same string. Keep the two in step.
    """
    tagged = str(question.get("topic") or "").strip()
    if tagged:
        return tagged
    explanation = str(question.get("explanation") or "")
    if explanation:
        first = re.split(r"[.!?]", explanation, maxsplit=1)[0].strip()
        return first if len(first) <= 40 else first[:40]
    text = str(question.get("question") or "General")
    return text if len(text) <= 40 else text[:40]


def answers_match(user_answer: Any, correct_answer: Any) -> bool:
    """Whether a submitted answer counts as correct.

    Mirrors ``_isAnswerCorrect`` in the Flutter ``quiz_result_screen``: MCQ
    generators return the bare option letter as the reference while the quiz
    screen stores the tapped option text, so ``"B"`` must accept
    ``"B. Reduce confusion"``. The server used plain equality here, which
    scored a correct tap as wrong — capture and score must agree with what
    the student actually saw.
    """
    user = str(user_answer or "").strip().lower()
    correct = str(correct_answer or "").strip().lower()
    if not user or not correct:
        return False
    if user == correct:
        return True
    if len(correct) != 1 or correct not in "abcd":
        return False
    return re.match(rf"^{re.escape(correct)}[.)\s]", user) is not None


def review_due_date(review_count: int, today: date) -> str:
    """Next review date for the spaced ladder, as an ISO ``YYYY-MM-DD``."""
    index = min(max(int(review_count or 0), 0), len(REVIEW_INTERVALS_DAYS) - 1)
    return (today + timedelta(days=REVIEW_INTERVALS_DAYS[index])).isoformat()


def _is_due(next_review_date: Any, today: date) -> bool:
    return isinstance(next_review_date, str) and next_review_date <= today.isoformat()


# ---------------------------------------------------------------------------
# Firestore access
# ---------------------------------------------------------------------------

def _mistakes_collection(uid: str):
    db = get_firestore()
    if db is None:
        return None
    return db.collection("users").document(uid).collection(MISTAKES)


def _fetch_rows(uid: str, limit: int = MAX_FETCH) -> list[tuple[str, dict[str, Any]]]:
    ref = _mistakes_collection(uid)
    if ref is None:
        return []
    rows: list[tuple[str, dict[str, Any]]] = []
    try:
        for snap in ref.limit(limit).stream():
            rows.append((snap.id, snap.to_dict() or {}))
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Could not read mistake memory for uid=%s: %s", uid, exc)
        return []
    return rows


def _fetch_by_status(
    uid: str, statuses: tuple[str, ...], limit: int = MAX_ANALYSIS_BATCH
) -> list[tuple[str, dict[str, Any]]]:
    ref = _mistakes_collection(uid)
    if ref is None or not statuses:
        return []
    op = "==" if len(statuses) == 1 else "in"
    value = statuses[0] if len(statuses) == 1 else list(statuses)
    rows: list[tuple[str, dict[str, Any]]] = []
    try:
        for snap in ref.where("analysisStatus", op, value).limit(limit).stream():
            rows.append((snap.id, snap.to_dict() or {}))
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("Could not read pending mistakes for uid=%s: %s", uid, exc)
        return []
    return rows


# ---------------------------------------------------------------------------
# Capture
# ---------------------------------------------------------------------------

def capture_mistakes(
    uid: str,
    *,
    quiz_id: str = "",
    subject_id: str = "",
    material_id: str = "",
    difficulty: str = "medium",
    questions: list[dict[str, Any]],
    user_answers: list[str],
    correct_answers: list[str],
) -> dict[str, Any]:
    """Store one record per distinct wrong answer in a saved quiz result.

    Called by ``/api/ai/quiz/save-result``. Never raises: a mistake-storage
    failure must not lose a quiz result the student is waiting to see.
    """
    summary: dict[str, Any] = {
        "captured": 0,
        "new": 0,
        "repeated": 0,
        "pendingAnalysis": 0,
        "mistakeIds": [],
    }
    if not questions:
        return summary

    db_ref = _mistakes_collection(uid)
    if db_ref is None:
        logger.warning("Firestore unavailable, mistake capture skipped")
        return summary

    db = get_firestore()
    now = datetime.now(timezone.utc)
    today = now.date()
    day_key = now.strftime("%Y-%m-%d")
    month_key = now.strftime("%Y-%m")

    for index, question in enumerate(questions):
        if not isinstance(question, dict):
            continue
        user_answer = (
            str(user_answers[index]) if index < len(user_answers) else ""
        )
        correct_answer = (
            str(correct_answers[index]) if index < len(correct_answers) else ""
        )
        if answers_match(user_answer, correct_answer):
            continue

        question_text = str(question.get("question") or question.get("text") or "").strip()
        if not question_text:
            continue

        topic = extract_topic(question)
        fingerprint = mistake_fingerprint(subject_id, topic, question_text)
        ref = db_ref.document(f"ms_{fingerprint}")

        payload = {
            "ownerId": uid,
            "fingerprint": fingerprint,
            "subjectId": str(subject_id or ""),
            "topic": topic,
            "question": question_text[:1000],
            "wrongAnswer": user_answer[:1000],
            "correctAnswer": correct_answer[:1000],
            # The quiz generator's own explanation, kept as context so Ziku's
            # analysis builds on the AI explanation the student already saw.
            "questionExplanation": str(question.get("explanation") or "")[:600],
            "quizId": str(quiz_id or ""),
            "materialId": str(material_id or ""),
            "difficulty": str(difficulty or "medium"),
        }

        tx = db.transaction()

        @firestore.transactional
        def _upsert(
            transaction,
            _ref=ref,
            _payload=payload,
            _now=now,
            _today=today,
            _day=day_key,
            _month=month_key,
        ):
            snap = _ref.get(transaction=transaction)
            if snap.exists:
                previous = snap.to_dict() or {}
                occurrences = int(previous.get("occurrences", 1) or 1) + 1
                previous_status = str(
                    previous.get("analysisStatus") or ANALYSIS_PENDING
                )
                # A repeat resets the review ladder: they got it wrong again,
                # so the schedule starts over at day 1. The stored analysis is
                # kept — the concept gap it describes is the reason for the
                # repeat — so a repeat never re-spends AI quota.
                transaction.set(
                    _ref,
                    {
                        **_payload,
                        "occurrences": occurrences,
                        "reviewCount": 0,
                        "nextReviewDate": review_due_date(0, _today),
                        "firstSeenAt": previous.get("firstSeenAt", _now),
                        "createdAt": previous.get("createdAt", _now),
                        "lastSeenAt": _now,
                        "updatedAt": _now,
                        "analysisStatus": previous_status,
                        "analysis": previous.get("analysis"),
                        "analysisSource": previous.get("analysisSource", ""),
                        "analysisAt": previous.get("analysisAt"),
                        "dayKey": _day,
                        "monthKey": _month,
                    },
                    merge=True,
                )
                return occurrences, False, previous_status

            transaction.set(
                _ref,
                {
                    **_payload,
                    "occurrences": 1,
                    "reviewCount": 0,
                    "nextReviewDate": review_due_date(0, _today),
                    "firstSeenAt": _now,
                    "createdAt": _now,
                    "lastSeenAt": _now,
                    "updatedAt": _now,
                    "analysisStatus": ANALYSIS_PENDING,
                    "analysis": None,
                    "analysisSource": "",
                    "analysisAt": None,
                    "dayKey": _day,
                    "monthKey": _month,
                },
            )
            return 1, True, ANALYSIS_PENDING

        try:
            _occurrences, created, previous_status = _upsert(tx)
        except Exception as exc:
            logger.warning(
                "Mistake capture failed for uid=%s quiz=%s: %s", uid, quiz_id, exc
            )
            continue

        summary["captured"] += 1
        summary["new" if created else "repeated"] += 1
        summary["mistakeIds"].append(f"ms_{fingerprint}")
        # Still waiting on Ziku: a brand-new mistake always is, and a repeat
        # is only not — when the earlier analysis already exists.
        if created or previous_status == ANALYSIS_PENDING:
            summary["pendingAnalysis"] += 1

    logger.info(
        "Mistake capture: uid=%s quiz=%s captured=%d new=%d repeated=%d pending=%d",
        uid, quiz_id, summary["captured"], summary["new"],
        summary["repeated"], summary["pendingAnalysis"],
    )
    return summary


# ---------------------------------------------------------------------------
# AI analysis (Ziku)
# ---------------------------------------------------------------------------

def _pick(raw: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in raw and raw.get(key) is not None:
            return raw.get(key)
    return ""


def _valid_review_date(raw: Any, today: date) -> str | None:
    """Accept only a date inside (today, today + 30 days]."""
    if not isinstance(raw, str):
        return None
    match = re.search(r"\d{4}-\d{2}-\d{2}", raw)
    if not match:
        return None
    try:
        parsed = date.fromisoformat(match.group(0))
    except ValueError:
        return None
    if today < parsed <= today + timedelta(days=MAX_RECOMMENDED_DELAY_DAYS):
        return parsed.isoformat()
    return None


def _clean_analysis(raw: dict[str, Any], today: date) -> dict[str, Any]:
    """Bound and normalise one AI-authored analysis record."""
    analysis = {
        "mistakeReason": str(
            _pick(raw, "mistake_reason", "mistakeReason")
        ).strip()[: _FIELD_LIMITS["mistakeReason"]],
        "conceptGap": str(
            _pick(raw, "concept_gap", "conceptGap")
        ).strip()[: _FIELD_LIMITS["conceptGap"]],
        "correctionExplanation": str(
            _pick(raw, "correction_explanation", "correctionExplanation")
        ).strip()[: _FIELD_LIMITS["correctionExplanation"]],
        "memoryTrick": str(
            _pick(raw, "memory_trick", "memoryTrick")
        ).strip()[: _FIELD_LIMITS["memoryTrick"]],
        "recommendedReviewDate": "",
    }
    review_date = _valid_review_date(
        _pick(raw, "recommended_review_date", "recommendedReviewDate"), today
    )
    if review_date:
        analysis["recommendedReviewDate"] = review_date
    return analysis


def _build_analysis_prompt(
    rows: list[tuple[str, dict[str, Any]]], today: date
) -> str:
    lines: list[str] = []
    for index, (_doc_id, data) in enumerate(rows):
        wrong = str(data.get("wrongAnswer") or "").strip()
        if wrong:
            wrong_line = f"Student's wrong answer: {wrong}"
        else:
            wrong_line = "Student's wrong answer: (left blank)"
        explanation = str(data.get("questionExplanation") or "").strip()
        lines.append(
            "\n".join(
                [
                    f"--- Mistake {index} ---",
                    f"Subject: {data.get('subjectId') or 'General'}",
                    f"Topic: {data.get('topic') or 'General'}",
                    f"Question: {data.get('question') or ''}",
                    wrong_line,
                    f"Correct answer: {data.get('correctAnswer') or ''}",
                ]
                + ([f"Quiz explanation: {explanation}"] if explanation else [])
                + [
                    f"Times missed (including this one): "
                    f"{int(data.get('occurrences', 1) or 1)}",
                ]
            )
        )

    return (
        "You are Ziku, the in-app study assistant for Gochano, a university "
        "student app in Bangladesh.\n"
        "A university student just got the quiz mistakes below wrong. For "
        "EACH mistake explain what went wrong and how to remember it.\n\n"
        f"TODAY'S DATE: {today.isoformat()}\n"
        + "\n".join(lines)
        + "\n\n"
        "Return ONLY valid JSON with this exact shape, no prose around it:\n"
        "{\n"
        '  "mistakes": [\n'
        "    {\n"
        '      "index": 0,\n'
        '      "mistake_reason": "why the student likely chose the wrong answer",\n'
        '      "concept_gap": "the specific concept they are missing",\n'
        '      "correction_explanation": "why the correct answer is right and the wrong one is not",\n'
        '      "memory_trick": "a short mnemonic or hook to recall it",\n'
        '      "recommended_review_date": "YYYY-MM-DD"\n'
        "    }\n"
        "  ]\n"
        "}\n\n"
        "Rules:\n"
        "- \"index\" must match the mistake number it belongs to.\n"
        "- Each of mistake_reason, concept_gap, memory_trick: one sentence.\n"
        "- correction_explanation: one to three sentences.\n"
        f"- recommended_review_date must be between {today.isoformat()} "
        f"and {(today + timedelta(days=MAX_RECOMMENDED_DELAY_DAYS)).isoformat()} "
        "(short mistakes sooner, repeated ones later).\n"
        "- Reply in the same language as the question: English for English "
        "questions, Bangla (বাংলা) for Bangla questions.\n"
        "- Never invent marks, grades, dates or facts outside the question.\n"
        "- Return ONLY the JSON."
    )


def _parse_analysis(raw: str) -> dict[int, dict[str, Any]]:
    """Parse the model reply into ``{index: raw item}``, tolerating fences."""
    cleaned = (raw or "").strip()
    if "```" in cleaned:
        chunks = cleaned.split("```")
        # Prefer the body of a ```json fence, else the longest chunk.
        for chunk in chunks[1::2]:
            cleaned = chunk
            if cleaned.lstrip().startswith("json"):
                cleaned = cleaned.lstrip()[4:]
            break
        else:
            cleaned = max(chunks, key=len)
    cleaned = cleaned.strip()
    if cleaned.startswith("json"):
        cleaned = cleaned[4:].strip()

    try:
        parsed = json.loads(cleaned)
    except (json.JSONDecodeError, TypeError):
        # Last resort: the first {...} block the model produced.
        match = re.search(r"\{.*\}", cleaned or "", re.DOTALL)
        if not match:
            return {}
        try:
            parsed = json.loads(match.group(0))
        except (json.JSONDecodeError, TypeError):
            return {}

    if isinstance(parsed, list):
        items = parsed
    elif isinstance(parsed, dict):
        items = parsed.get("mistakes") or parsed.get("analyses") or []
    else:
        return {}

    out: dict[int, dict[str, Any]] = {}
    if not isinstance(items, list):
        return {}
    for position, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        raw_index = _pick(item, "index", "i", "id")
        try:
            index = int(str(raw_index).strip())
        except (TypeError, ValueError):
            index = position
        out[index] = item
    return out


async def analyze_pending(
    uid: str, limit: int = MAX_ANALYSIS_BATCH
) -> dict[str, Any]:
    """Send every not-yet-analysed mistake to Ziku and store the answer.

    One AI call covers the whole batch. Provider/quota errors propagate as
    HTTP errors (the student deserves to know the difference between
    "the AI is down" and "your analysis is saved"); nothing is written
    unless the reply parsed into at least one usable analysis.
    """
    limit = max(1, min(int(limit or 1), MAX_ANALYSIS_BATCH))
    rows = _fetch_by_status(
        uid, (ANALYSIS_PENDING, ANALYSIS_FAILED), limit=limit
    )
    if not rows:
        return {
            "analyzed": 0,
            "pending": _count_status(uid, ANALYSIS_PENDING),
            "failed": _count_status(uid, ANALYSIS_FAILED),
            "status": "empty",
        }

    today = datetime.now(timezone.utc).date()
    prompt = _build_analysis_prompt(rows, today)

    try:
        raw = await ai_service.generate(uid, prompt, feature=AiFeature.MISTAKE)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("Mistake analysis AI call failed: %s", exc)
        raise HTTPException(
            status_code=502, detail="AI provider temporarily unavailable."
        )

    parsed = _parse_analysis(raw)
    if not parsed:
        logger.warning(
            "Mistake analysis reply did not parse for uid=%s", uid
        )
        return {
            "analyzed": 0,
            "pending": _count_status(uid, ANALYSIS_PENDING),
            "failed": _count_status(uid, ANALYSIS_FAILED),
            "status": "no_analysis",
        }

    ref = _mistakes_collection(uid)
    if ref is None:  # pragma: no cover - defensive
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    now = datetime.now(timezone.utc)
    analyzed = 0
    for index, (doc_id, data) in enumerate(rows):
        item = parsed.get(index)
        if not item:
            continue
        analysis = _clean_analysis(item, today)
        fields: dict[str, Any] = {
            "analysis": analysis,
            "analysisStatus": ANALYSIS_ANALYZED,
            "analysisSource": "ai",
            "analysisAt": now,
            "updatedAt": now,
        }
        current_due = str(data.get("nextReviewDate") or "")
        # Adopt Ziku's date only when the item is not already due: analysing
        # a mistake must never quietly move a review out of today's queue.
        if analysis["recommendedReviewDate"] and not _is_due(current_due, today):
            fields["nextReviewDate"] = analysis["recommendedReviewDate"]
        try:
            ref.document(doc_id).set(fields, merge=True)
            analyzed += 1
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning(
                "Could not store mistake analysis %s: %s", doc_id, exc
            )

    if analyzed:
        record_ai_activity(uid, "mistake_analyses", analyzed)

    return {
        "analyzed": analyzed,
        "pending": _count_status(uid, ANALYSIS_PENDING),
        "failed": _count_status(uid, ANALYSIS_FAILED),
        "status": "ok" if analyzed else "no_analysis",
    }


def _count_status(uid: str, status: str) -> int:
    return len(_fetch_by_status(uid, (status,), limit=MAX_FETCH))


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

def _public_mistake(doc_id: str, data: dict[str, Any]) -> dict[str, Any]:
    analysis = data.get("analysis")
    return {
        "id": doc_id,
        "subjectId": data.get("subjectId", ""),
        "topic": data.get("topic", ""),
        "question": data.get("question", ""),
        "wrongAnswer": data.get("wrongAnswer", ""),
        "correctAnswer": data.get("correctAnswer", ""),
        "questionExplanation": data.get("questionExplanation", ""),
        "occurrences": int(data.get("occurrences", 1) or 1),
        "reviewCount": int(data.get("reviewCount", 0) or 0),
        "nextReviewDate": data.get("nextReviewDate", ""),
        "analysisStatus": data.get("analysisStatus", ANALYSIS_PENDING),
        "analysis": analysis if isinstance(analysis, dict) else None,
        "firstSeenAt": data.get("firstSeenAt"),
        "lastSeenAt": data.get("lastSeenAt"),
    }


def list_mistakes(
    uid: str,
    *,
    status: str = "all",
    limit: int = 50,
    today: date | None = None,
) -> list[dict[str, Any]]:
    """Mistake records for one student, newest encounter first.

    ``status``: ``all`` | ``due`` | ``repeated`` | ``pending``.
    """
    today = today or datetime.now(timezone.utc).date()
    rows = _fetch_rows(uid)
    items = [_public_mistake(doc_id, data) for doc_id, data in rows]

    if status == "due":
        items = [i for i in items if _is_due(i["nextReviewDate"], today)]
    elif status == "repeated":
        items = [i for i in items if i["occurrences"] >= 2]
    elif status == "pending":
        items = [
            i for i in items if i["analysisStatus"] == ANALYSIS_PENDING
        ]

    def _sort_key(item: dict[str, Any]) -> tuple:
        seen = item.get("lastSeenAt")
        stamp = seen.isoformat() if hasattr(seen, "isoformat") else str(seen or "")
        return (item["occurrences"], stamp)

    items.sort(key=_sort_key, reverse=True)
    return items[: max(1, min(int(limit or 50), 200))]


def get_review_queue(
    uid: str, *, due_only: bool = False, limit: int = 50
) -> list[dict[str, Any]]:
    """Ordered revision queue — the shared primitive later phases reuse.

    Due items first (soonest first), then everything else by repeat count.
    """
    today = datetime.now(timezone.utc).date()
    items = list_mistakes(uid, status="all", limit=MAX_FETCH, today=today)
    due = [i for i in items if _is_due(i["nextReviewDate"], today)]
    due.sort(key=lambda i: (i["nextReviewDate"], -i["occurrences"]))
    if due_only:
        return due[: max(1, limit)]
    rest = [i for i in items if not _is_due(i["nextReviewDate"])]
    return (due + rest)[: max(1, limit)]


def get_analytics(uid: str) -> dict[str, Any]:
    """Per-subject and per-topic mistake aggregates (Academic Health Score
    input): counts, repeats, and how many are overdue for revision."""
    today = datetime.now(timezone.utc).date()
    rows = _fetch_rows(uid)

    def _empty() -> dict[str, Any]:
        return {
            "mistakes": 0,
            "occurrences": 0,
            "repeated": 0,
            "due": 0,
            "analyzed": 0,
        }

    subjects: dict[str, dict[str, Any]] = defaultdict(_empty)
    topics: dict[str, dict[str, Any]] = defaultdict(_empty)

    for _doc_id, data in rows:
        occurrences = int(data.get("occurrences", 1) or 1)
        is_repeated = occurrences >= 2
        is_due = _is_due(data.get("nextReviewDate"), today)
        analyzed = data.get("analysisStatus") == ANALYSIS_ANALYZED
        for bucket, key in (
            (subjects, str(data.get("subjectId") or "General")),
            (topics, str(data.get("topic") or "General")),
        ):
            bucket[key]["mistakes"] += 1
            bucket[key]["occurrences"] += occurrences
            bucket[key]["repeated"] += 1 if is_repeated else 0
            bucket[key]["due"] += 1 if is_due else 0
            bucket[key]["analyzed"] += 1 if analyzed else 0

    def _sorted(bucket: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
        out = [{"name": name, **counts} for name, counts in bucket.items()]
        out.sort(key=lambda e: (-e["occurrences"], -e["mistakes"], e["name"]))
        return out

    return {
        "subjects": _sorted(subjects),
        "topics": _sorted(topics),
        "totalMistakes": len(rows),
        "generatedAt": datetime.now(timezone.utc),
    }


def get_priority_topics(uid: str, limit: int = 3) -> list[dict[str, Any]]:
    """Topics worth putting in front of a study planner: most repeats first,
    a topic that is due for revision outranking one that is merely frequent.

    Exam Rescue feeds this into its prompt beside the weak-topic list.
    """
    today = datetime.now(timezone.utc).date()
    rows = _fetch_rows(uid)

    stats: dict[str, dict[str, Any]] = {}
    for _doc_id, data in rows:
        topic = str(data.get("topic") or "").strip()
        if not topic:
            continue
        occurrences = int(data.get("occurrences", 1) or 1)
        entry = stats.setdefault(
            topic,
            {"topic": topic, "mistakes": 0, "occurrences": 0, "repeated": False, "due": False},
        )
        entry["mistakes"] += 1
        entry["occurrences"] += occurrences
        entry["repeated"] = entry["repeated"] or occurrences >= 2
        entry["due"] = entry["due"] or _is_due(data.get("nextReviewDate"), today)

    ranked = sorted(
        stats.values(),
        key=lambda e: (e["due"], e["repeated"], e["occurrences"], e["mistakes"]),
        reverse=True,
    )
    return ranked[: max(1, limit)]


def get_learning_brain(uid: str) -> dict[str, Any]:
    """The "My Learning Brain" summary — everything Profile shows in one read.

    Weak topics come from the existing ``weak_topic_service`` (quiz mastery)
    enriched with mistake counts; repeated mistakes and the revision queue
    come from this service. Nothing is computed twice.
    """
    today = datetime.now(timezone.utc).date()
    rows = _fetch_rows(uid)

    total_mistakes = len(rows)
    total_occurrences = 0
    analyzed = 0
    pending = 0
    repeated_count = 0
    due_count = 0
    repeated: list[dict[str, Any]] = []
    due: list[dict[str, Any]] = []
    mistakes_by_topic: dict[str, int] = defaultdict(int)
    # Topics carrying a real signal: a repeat miss or an overdue revision.
    topic_signal: dict[str, bool] = defaultdict(bool)
    subjects: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"subjectId": "General", "mistakes": 0, "occurrences": 0}
    )

    for doc_id, data in rows:
        occurrences = int(data.get("occurrences", 1) or 1)
        total_occurrences += occurrences
        if data.get("analysisStatus") == ANALYSIS_ANALYZED:
            analyzed += 1
        elif data.get("analysisStatus") == ANALYSIS_PENDING:
            pending += 1
        topic = str(data.get("topic") or "General")
        mistakes_by_topic[topic] += 1

        subject = str(data.get("subjectId") or "General")
        subjects[subject]["subjectId"] = subject
        subjects[subject]["mistakes"] += 1
        subjects[subject]["occurrences"] += occurrences

        item = _public_mistake(doc_id, data)
        if occurrences >= 2:
            repeated.append(item)
            repeated_count += 1
            topic_signal[topic] = True
        if _is_due(data.get("nextReviewDate"), today):
            due.append(item)
            due_count += 1
            topic_signal[topic] = True

    repeated.sort(key=lambda i: (-i["occurrences"], i["topic"]))
    due.sort(key=lambda i: (i["nextReviewDate"], -i["occurrences"]))

    # Reuse the existing weak-topic engine rather than re-deriving mastery.
    weak_topics: list[dict[str, Any]] = []
    try:
        for entry in weak_topic_service.get_weak_topics(uid, threshold=60):
            topic = str(entry.get("topic") or "")
            if not topic:
                continue
            weak_topics.append(
                {
                    "topic": topic,
                    "averageScore": entry.get("average_score"),
                    "attempts": entry.get("attempts", 0),
                    "recommendation": entry.get("recommendation", ""),
                    "mistakes": mistakes_by_topic.pop(topic, 0),
                }
            )
    except Exception as exc:
        logger.warning("Weak-topic lookup failed for learning brain: %s", exc)

    # Topics with recorded mistakes that quiz mastery has not flagged yet.
    # A single stray miss is not a weak topic; a repeat or an overdue
    # revision is, even when quiz averages look healthy.
    for topic, count in mistakes_by_topic.items():
        if count < 2 and not topic_signal.get(topic):
            continue
        weak_topics.append(
            {
                "topic": topic,
                "averageScore": None,
                "attempts": 0,
                "recommendation": "",
                "mistakes": count,
            }
        )

    weak_topics.sort(
        key=lambda e: (-e["mistakes"], e["averageScore"] if e["averageScore"] is not None else 101)
    )

    subject_breakdown = sorted(
        subjects.values(),
        key=lambda e: (-e["occurrences"], -e["mistakes"], e["subjectId"]),
    )

    return {
        "totalMistakes": total_mistakes,
        "totalOccurrences": total_occurrences,
        "analyzedCount": analyzed,
        "pendingAnalysis": pending,
        "repeatedCount": repeated_count,
        "revisionDueCount": due_count,
        "weakTopics": weak_topics[:10],
        "repeatedMistakes": repeated[:10],
        "revisionDue": due[:20],
        "subjectBreakdown": subject_breakdown,
        "nextReviewDate": due[0]["nextReviewDate"] if due else None,
        "generatedAt": datetime.now(timezone.utc),
    }


# ---------------------------------------------------------------------------
# Writes from the review flow
# ---------------------------------------------------------------------------

def mark_reviewed(uid: str, mistake_id: str) -> dict[str, Any] | None:
    """Advance one mistake's spaced-repetition ladder by one step.

    Returns the updated record, or ``None`` when the id does not belong to
    this student (the caller turns that into a 404).
    """
    ref = _mistakes_collection(uid)
    if ref is None:  # pragma: no cover - defensive
        return None
    doc_ref = ref.document(mistake_id)
    try:
        snap = doc_ref.get()
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("mark_reviewed read failed for %s: %s", mistake_id, exc)
        return None
    if not snap.exists:
        return None

    data = snap.to_dict() or {}
    if data.get("ownerId") not in (None, uid):
        return None

    today = datetime.now(timezone.utc).date()
    review_count = int(data.get("reviewCount", 0) or 0) + 1
    fields = {
        "reviewCount": review_count,
        "nextReviewDate": review_due_date(review_count, today),
        "updatedAt": datetime.now(timezone.utc),
    }
    doc_ref.set(fields, merge=True)
    updated = {**data, **fields}
    from app.services.analytics_service import track_event

    track_event(
        uid,
        "mistake_corrected",
        {
            "subject": data.get("subjectId"),
            "topic": data.get("topic"),
            "chapter": data.get("topic"),
            "source": "mistake_memory",
        },
    )
    return _public_mistake(mistake_id, updated)
