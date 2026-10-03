"""Phase 10.5 - long-term learning memory.

This is a derived memory layer, not a second AI system. It joins the existing
Mistake Memory, Academic Health, Adaptive Learning, focus, exam and generated
content records into one explainable student profile.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import mistake_memory_service as mistakes

logger = logging.getLogger("gochano.learning_memory")

MEMORY_COLLECTION = "learning_memory"
EFFECTIVENESS_COLLECTION = "content_effectiveness"
MAX_ROWS = 300

# Phase 12.2.4 — canonical concept mastery constants.
DEFAULT_MASTERY = 0.50
WEAK_MASTERY_THRESHOLD = 0.60
MAX_QUIZ_PENALTY = 0.35
CONFIDENCE_SPAN = 5.0


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _to_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, date):
        return datetime.combine(value, datetime.min.time(), tzinfo=timezone.utc)
    if isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    for method in ("to_datetime", "toDate"):
        converter = getattr(value, method, None)
        if callable(converter):
            try:
                parsed = converter()
            except Exception:
                return None
            if isinstance(parsed, datetime):
                return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _read(collection: str, *, uid: str | None = None) -> list[tuple[str, dict[str, Any]]]:
    db = get_firestore()
    if db is None:
        return []
    try:
        ref = db.collection(collection)
        if uid is not None:
            ref = ref.where("studentId", "==", uid)
        return [(snap.id, snap.to_dict() or {}) for snap in ref.limit(MAX_ROWS).stream()]
    except Exception as exc:  # pragma: no cover
        logger.debug("learning memory read failed for %s: %s", collection, exc)
        return []


def _user_read(uid: str, collection: str) -> list[tuple[str, dict[str, Any]]]:
    db = get_firestore()
    if db is None:
        return []
    try:
        ref = db.collection("users").document(uid).collection(collection)
        return [(snap.id, snap.to_dict() or {}) for snap in ref.limit(MAX_ROWS).stream()]
    except Exception as exc:  # pragma: no cover
        logger.debug("learning memory user read failed for %s: %s", collection, exc)
        return []


def _average(values: list[float]) -> float | None:
    return round(sum(values) / len(values), 1) if values else None


def _quiz_topic_history(uid: str) -> dict[str, list[tuple[datetime, float]]]:
    history: dict[str, list[tuple[datetime, float]]] = defaultdict(list)
    for _, data in _user_read(uid, "quiz_results"):
        stamp = _to_datetime(data.get("createdAt") or data.get("dayKey")) or _now()
        topic_scores = data.get("topicScores") or {}
        if isinstance(topic_scores, dict):
            for topic, score in topic_scores.items():
                if str(topic).strip():
                    history[str(topic).strip()].append((stamp, _number(score)))
    for values in history.values():
        values.sort(key=lambda item: item[0])
    return history


def _content_rows(uid: str) -> list[tuple[str, dict[str, Any]]]:
    return _read("ai_content", uid=uid)


def _community_signals() -> list[dict[str, Any]]:
    """Return aggregate public discussion signals only, never private bodies."""
    db = get_firestore()
    if db is None:
        return []
    counts: dict[tuple[str, str], int] = defaultdict(int)
    try:
        for snap in db.collection("community_posts").limit(MAX_ROWS).stream():
            data = snap.to_dict() or {}
            if str(data.get("groupId") or "").strip():
                continue
            subject = str(data.get("subject") or "General").strip()
            topic = str(data.get("chapter") or data.get("concept") or "General").strip()
            counts[(subject, topic)] += 1
    except Exception as exc:  # pragma: no cover
        logger.debug("community memory read failed: %s", exc)
    return [
        {"subject": subject, "topic": topic, "discussionCount": count}
        for (subject, topic), count in sorted(counts.items(), key=lambda item: -item[1])[:30]
    ]


def _effectiveness_for(uid: str, content_id: str, content: dict[str, Any], history: dict[str, list[tuple[datetime, float]]]) -> dict[str, Any]:
    topic = str(content.get("topic") or "General").strip() or "General"
    created = _to_datetime(content.get("createdAt")) or _now()
    scores = history.get(topic, [])
    before_values = [score for stamp, score in scores if stamp <= created]
    after_values = [score for stamp, score in scores if stamp > created]
    before = _average(before_values)
    after = _average(after_values[-10:])
    if before is None and scores:
        before = scores[0][1]
    improvement = round(after - before, 1) if after is not None and before is not None else None
    new_mistakes = 0
    for mistake in mistakes.get_review_queue(uid, limit=MAX_ROWS):
        if str(mistake.get("topic") or "").strip().casefold() != topic.casefold():
            continue
        seen = _to_datetime(mistake.get("lastSeenAt") or mistake.get("createdAt"))
        if seen is not None and seen > created:
            new_mistakes += int(mistake.get("occurrences") or 1)
    if improvement is not None and improvement >= 10:
        outcome = "helped"
    elif improvement is not None and improvement <= -10:
        outcome = "needs_review"
    elif after is not None:
        outcome = "stable"
    else:
        outcome = "awaiting_evidence"
    return {
        "contentId": content_id,
        "type": content.get("type", "unknown"),
        "topic": topic,
        "createdAt": created,
        "beforeAccuracy": before,
        "afterAccuracy": after,
        "improvement": improvement,
        "newMistakes": new_mistakes,
        "reviewResult": content.get("reviewStatus", "new"),
        "outcome": outcome,
        "evidence": "later_quiz" if after is not None else "awaiting_quiz",
    }


def get_content_effectiveness(uid: str, *, persist: bool = True) -> dict[str, Any]:
    history = _quiz_topic_history(uid)
    items = [_effectiveness_for(uid, doc_id, data, history) for doc_id, data in _content_rows(uid)]
    items.sort(key=lambda item: item["createdAt"], reverse=True)
    type_scores: dict[str, list[float]] = defaultdict(list)
    for item in items:
        if item["improvement"] is not None:
            type_scores[str(item["type"])].append(item["improvement"])
    best_type = max(type_scores, key=lambda kind: _average(type_scores[kind]) or 0, default=None)
    payload = {
        "studentId": uid,
        "items": items[:50],
        "bestContentType": best_type,
        "typeEffectiveness": {kind: _average(values) for kind, values in type_scores.items()},
        "generatedAt": _now(),
    }
    if persist:
        db = get_firestore()
        if db is not None:
            for item in items[:50]:
                try:
                    db.collection(EFFECTIVENESS_COLLECTION).document(item["contentId"]).set(
                        {**item, "studentId": uid, "updatedAt": _now()}
                    )
                except Exception as exc:  # pragma: no cover
                    logger.debug("effectiveness cache write failed: %s", exc)
    return payload


def _study_pattern(uid: str) -> str:
    hours: list[int] = []
    for _, data in _user_read(uid, "focus_sessions"):
        stamp = _to_datetime(data.get("startedAtIso") or data.get("startedAt") or data.get("createdAt"))
        if stamp is not None:
            hours.append(stamp.hour)
    if not hours:
        return "not enough focus data"
    average = sum(hours) / len(hours)
    if average < 12:
        return "morning"
    if average < 18:
        return "afternoon"
    return "evening"


def _profile(uid: str, graph: dict[str, Any], effectiveness: dict[str, Any]) -> dict[str, Any]:
    subject_scores: dict[str, list[float]] = defaultdict(list)
    for _, data in _user_read(uid, "quiz_results"):
        subject = str(data.get("subjectId") or data.get("subject") or "General").strip()
        subject_scores[subject].append(_number(data.get("score")))
    strongest = max(subject_scores, key=lambda key: _average(subject_scores[key]) or 0, default=None)
    topic_history = _quiz_topic_history(uid)
    first_last: list[float] = []
    for values in topic_history.values():
        if len(values) >= 2:
            first_last.append(values[-1][1] - values[0][1])
    improvement = _average(first_last)
    return {
        "studentId": uid,
        "strongestSubject": strongest,
        "weakestTopics": [item["topic"] for item in graph.get("topics", [])[:5]],
        "preferredLearningStyle": "examples + practice" if (effectiveness.get("bestContentType") in {"flashcards", "study_pack"}) else "guided explanation",
        "bestContentType": effectiveness.get("bestContentType"),
        "studyTimePattern": _study_pattern(uid),
        "improvementRate": improvement,
    }


def build_memory(uid: str, *, persist: bool = True) -> dict[str, Any]:
    mistakes_rows = mistakes.get_review_queue(uid, limit=MAX_ROWS)
    history = _quiz_topic_history(uid)
    topics: dict[str, dict[str, Any]] = {}
    for topic, values in history.items():
        topics[topic] = {
            "topic": topic,
            "accuracy": _average([score for _, score in values]),
            "beforeAccuracy": values[0][1] if values else None,
            "improvement": round(values[-1][1] - values[0][1], 1) if len(values) > 1 else 0,
            "attempts": len(values),
            "concepts": [],
            "mistakes": 0,
            "revisions": 0,
        }
    for item in mistakes_rows:
        topic = str(item.get("topic") or "General").strip() or "General"
        entry = topics.setdefault(topic, {"topic": topic, "accuracy": None, "beforeAccuracy": None, "improvement": 0, "attempts": 0, "concepts": [], "mistakes": 0, "revisions": 0})
        analysis = item.get("analysis") or {}
        concept = str(analysis.get("conceptGap") or topic).strip()
        if concept and concept not in entry["concepts"]:
            entry["concepts"].append(concept)
        entry["mistakes"] += int(item.get("occurrences") or 1)
        entry["revisions"] += int(item.get("reviewCount") or 0)
    ordered_topics = sorted(topics.values(), key=lambda item: (item.get("accuracy") is not None, item.get("accuracy") or 0, -item["mistakes"]))
    effectiveness = get_content_effectiveness(uid, persist=persist)
    community_signals = _community_signals()
    graph = {
        "studentId": uid,
        "topics": ordered_topics[:50],
        "generatedContent": [_effectiveness_for(uid, doc_id, data, history) for doc_id, data in _content_rows(uid)][:50],
        "communityDiscussions": community_signals,
        "revisionHistory": [{"topic": item["topic"], "revisions": item["revisions"]} for item in ordered_topics if item["revisions"]],
        "improvement": [{"topic": item["topic"], "before": item["beforeAccuracy"], "now": item["accuracy"], "delta": item["improvement"]} for item in ordered_topics if item["accuracy"] is not None],
        "profile": _profile(uid, {"topics": ordered_topics}, effectiveness),
        "updatedAt": _now(),
    }
    if persist:
        db = get_firestore()
        if db is not None:
            try:
                db.collection(MEMORY_COLLECTION).document(uid).set(graph)
            except Exception as exc:  # pragma: no cover
                logger.debug("learning memory cache write failed: %s", exc)
    return graph


# ---------------------------------------------------------------------------
# Phase 12.2.4 — Canonical concept / topic mastery.
# ---------------------------------------------------------------------------
#
# Single source of truth for topic mastery, confidence and weakness flags.
# Consumers (weak_topic_service, ziku_adaptive_service, ziku_tutor_service,
# study_coach_service, dashboard bootstrap) read these functions instead of
# re-deriving their own weakness heuristic.
#
# Rules:
#   * strictly read-only against ``quiz_results`` and ``mistakes``;
#   * mastery and confidence are bounded to [0.0, 1.0];
#   * no raw answers, questions, notes, transcripts or answer keys are copied
#     into a mastery record — only normalized numeric signals and timestamps;
#   * every query is partitioned by student UID, so users never influence each
#     other's records;
#   * ``db`` may be injected by tests; production callers pass ``None`` and the
#     module's Firestore getter is used.


def _resolve_db(db: Any = None) -> Any:
    if db is not None:
        return db
    try:
        return get_firestore()
    except Exception as exc:  # pragma: no cover - unconfigured environment
        logger.debug("learning memory: firestore unavailable: %s", exc)
        return None


def _mastery_rows(
    uid: str, collection: str, db: Any = None
) -> list[tuple[str, dict[str, Any]]]:
    client = _resolve_db(db)
    if client is None:
        return []
    try:
        ref = client.collection("users").document(uid).collection(collection)
        return [(snap.id, snap.to_dict() or {}) for snap in ref.limit(MAX_ROWS).stream()]
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug(
            "learning memory: %s read failed for %s: %s", collection, uid, exc
        )
        return []


def _new_evidence(topic: str) -> dict[str, Any]:
    return {
        "topic": topic,
        "subject": None,
        "chapter": None,
        "scores": [],
        "quizAttempts": 0,
        "scoreTotal": 0.0,
        "mistakeCount": 0,
        "totalOccurrences": 0,
        "repeatedMistakes": 0,
        "reviewDue": 0,
        "first": None,
        "last": None,
    }


def _note_subject(entry: dict[str, Any], candidate: str) -> None:
    if not candidate:
        return
    current = entry["subject"]
    if current is None or (current == "General" and candidate != "General"):
        entry["subject"] = candidate


def _note_stamp(entry: dict[str, Any], stamp: datetime | None) -> None:
    if stamp is None:
        return
    if entry["first"] is None or stamp < entry["first"]:
        entry["first"] = stamp
    if entry["last"] is None or stamp > entry["last"]:
        entry["last"] = stamp


def _collect_topic_evidence(uid: str, db: Any = None) -> dict[str, dict[str, Any]]:
    """Read-only evidence pass over one student's quiz and mistake records."""
    topics: dict[str, dict[str, Any]] = {}
    today = _now().date().isoformat()

    for _, data in _mastery_rows(uid, "quiz_results", db):
        raw_scores = data.get("topicScores")
        if not isinstance(raw_scores, dict):
            continue
        subject = str(data.get("subjectId") or data.get("subject") or "").strip()
        chapter = str(data.get("chapter") or "").strip() or None
        stamp = _to_datetime(data.get("createdAt") or data.get("dayKey")) or _now()
        for raw_topic, raw_score in raw_scores.items():
            topic = str(raw_topic or "").strip()
            if not topic:
                continue
            try:
                score = float(raw_score)
            except (TypeError, ValueError):
                continue
            entry = topics.setdefault(topic, _new_evidence(topic))
            entry["quizAttempts"] += 1
            entry["scoreTotal"] += score
            entry["scores"].append((stamp, score))
            _note_subject(entry, subject)
            if entry["chapter"] is None:
                entry["chapter"] = chapter
            _note_stamp(entry, stamp)

    for _, data in _mastery_rows(uid, "mistakes", db):
        topic = str(data.get("topic") or "").strip() or "General"
        subject = str(data.get("subjectId") or data.get("subject") or "").strip()
        chapter = str(data.get("chapter") or "").strip() or None
        stamp = _to_datetime(data.get("lastSeenAt") or data.get("createdAt")) or _now()
        entry = topics.setdefault(topic, _new_evidence(topic))
        entry["mistakeCount"] += 1
        occurrences = max(1, int(_number(data.get("occurrences"), 1.0)))
        entry["totalOccurrences"] += occurrences
        if occurrences >= 2:
            entry["repeatedMistakes"] += 1
        next_review = data.get("nextReviewDate")
        if isinstance(next_review, str) and next_review and next_review <= today:
            entry["reviewDue"] += 1
        _note_subject(entry, subject)
        if entry["chapter"] is None:
            entry["chapter"] = chapter
        _note_stamp(entry, stamp)

    return topics


def _trend(scores: list[tuple[datetime, float]]) -> tuple[float, str]:
    if len(scores) < 2:
        return 0.0, "insufficient_data"
    ordered = sorted(scores, key=lambda item: item[0])
    delta = round(ordered[-1][1] - ordered[0][1], 1)
    if delta >= 5.0:
        return delta, "improving"
    if delta <= -5.0:
        return delta, "declining"
    return delta, "stable"


def _build_mastery_record(entry: dict[str, Any]) -> dict[str, Any]:
    attempts = int(entry["quizAttempts"])
    total_occurrences = int(entry["totalOccurrences"])
    repeated = int(entry["repeatedMistakes"])
    review_due = int(entry["reviewDue"])
    evidence_count = attempts + total_occurrences

    quiz_accuracy = round(entry["scoreTotal"] / attempts, 1) if attempts else None
    confidence = round(min(1.0, max(0.0, evidence_count / CONFIDENCE_SPAN)), 2)
    improvement_delta, trend = _trend(entry["scores"])

    if attempts:
        # Deterministic quiz baseline minus a bounded mistake penalty.
        base = (quiz_accuracy or 0.0) / 100.0
        penalty = min(
            MAX_QUIZ_PENALTY,
            0.05 * repeated + 0.05 * review_due + 0.01 * total_occurrences,
        )
        mastery = max(0.0, min(1.0, base - penalty))
    else:
        # Mistake-only topics stay deliberately conservative.
        penalty = 0.10 * repeated + 0.10 * review_due + 0.02 * total_occurrences
        mastery = max(0.05, min(DEFAULT_MASTERY, DEFAULT_MASTERY - penalty))
    mastery = round(float(mastery), 2)

    if evidence_count == 0:
        is_weak = False
    elif mastery < WEAK_MASTERY_THRESHOLD:
        is_weak = True
    elif review_due > 0 and mastery < 0.70:
        is_weak = True
    elif repeated > 0 and mastery < 0.75:
        is_weak = True
    else:
        is_weak = False

    return {
        "subject": entry["subject"] or "General",
        "chapter": entry["chapter"],
        "topic": entry["topic"],
        "mastery": mastery,
        "confidence": float(confidence),
        "evidenceCount": evidence_count,
        "lastObservedAt": entry["last"].isoformat() if entry["last"] else None,
        "isWeak": is_weak,
        "signals": {
            "quizAccuracy": float(quiz_accuracy) if quiz_accuracy is not None else None,
            "quizAttempts": attempts,
            "mistakeCount": int(entry["mistakeCount"]),
            "repeatedMistakes": repeated,
            "reviewDue": review_due,
            "improvementDelta": float(improvement_delta),
            "trend": trend,
        },
    }


def _empty_mastery_record(topic: str, subject: str | None = None) -> dict[str, Any]:
    """Neutral default for a topic with no evidence yet — never flagged weak."""
    return {
        "subject": subject or "General",
        "chapter": None,
        "topic": topic,
        "mastery": DEFAULT_MASTERY,
        "confidence": 0.0,
        "evidenceCount": 0,
        "lastObservedAt": None,
        "isWeak": False,
        "signals": {
            "quizAccuracy": None,
            "quizAttempts": 0,
            "mistakeCount": 0,
            "repeatedMistakes": 0,
            "reviewDue": 0,
            "improvementDelta": 0.0,
            "trend": "insufficient_data",
        },
    }


def _subject_matches(record_subject: Any, subject: str | None) -> bool:
    if not subject:
        return True
    return str(record_subject or "").strip().casefold() == str(subject).strip().casefold()


def get_all_topics_mastery(
    uid: str,
    subject: str | None = None,
    db: Any = None,
) -> list[dict[str, Any]]:
    """Every topic the student has evidence for, weakest first."""
    entries = _collect_topic_evidence(uid, db=db)
    records = [
        _build_mastery_record(entry)
        for entry in entries.values()
        if _subject_matches(entry["subject"] or "General", subject)
    ]
    records.sort(key=lambda item: (item["mastery"], item["topic"].casefold()))
    return records


def get_topic_mastery(
    uid: str,
    topic: str,
    subject: str | None = None,
    db: Any = None,
) -> dict[str, Any]:
    """Canonical mastery for one topic; neutral defaults when evidence is absent."""
    name = str(topic or "").strip()
    if not name:
        return _empty_mastery_record(str(topic or ""), subject)

    entries = _collect_topic_evidence(uid, db=db)
    key = name if name in entries else next(
        (candidate for candidate in entries if candidate.casefold() == name.casefold()),
        None,
    )
    if key is None:
        return _empty_mastery_record(name, subject)

    record = _build_mastery_record(entries[key])
    if not _subject_matches(record["subject"], subject):
        return _empty_mastery_record(name, subject)
    return record


def get_weak_topics(
    uid: str,
    threshold: float = WEAK_MASTERY_THRESHOLD,
    min_attempts: int = 1,
    limit: int = 10,
    subject: str | None = None,
    db: Any = None,
) -> list[dict[str, Any]]:
    """Canonical weak topics, weakest first.

    ``threshold`` is a mastery bound in ``[0.0, 1.0]`` (the legacy adapter that
    speaks the 0-100 scale converts before delegating).
    """
    records = get_all_topics_mastery(uid, subject=subject, db=db)
    min_evidence = max(1, int(min_attempts or 1))
    bound = float(threshold)
    weak = [
        record
        for record in records
        if record["evidenceCount"] >= min_evidence and record["mastery"] < bound
    ]
    return weak[: max(0, int(limit or 0))]


def get_subject_mastery(
    uid: str,
    subject: str,
    db: Any = None,
) -> dict[str, Any]:
    """Aggregate mastery for one subject, degrading to neutral with no evidence."""
    records = get_all_topics_mastery(uid, subject=subject, db=db)
    if not records:
        return {
            "subject": subject,
            "totalTopics": 0,
            "mastery": DEFAULT_MASTERY,
            "confidence": 0.0,
            "evidenceCount": 0,
            "weakTopics": [],
            "strongTopics": [],
            "topics": [],
        }

    return {
        "subject": records[0]["subject"],
        "totalTopics": len(records),
        "mastery": round(
            sum(record["mastery"] for record in records) / len(records), 2
        ),
        "confidence": round(
            sum(record["confidence"] for record in records) / len(records), 2
        ),
        "evidenceCount": sum(record["evidenceCount"] for record in records),
        "weakTopics": [
            record["topic"] for record in records if record["isWeak"]
        ],
        "strongTopics": [
            record["topic"] for record in records if record["mastery"] >= 0.75
        ],
        "topics": records,
    }


def get_progress(uid: str) -> dict[str, Any]:
    memory = build_memory(uid, persist=True)
    return {
        "studentId": uid,
        "improvement": memory.get("improvement", [])[:20],
        "topics": memory.get("topics", [])[:20],
        "profile": memory.get("profile", {}),
        "generatedAt": memory.get("updatedAt"),
    }


def chat_context(uid: str) -> str | None:
    try:
        memory = build_memory(uid, persist=False)
        topics = memory.get("topics") or []
        if not topics:
            return None
        top = topics[0]
        improvement = top.get("improvement") or 0
        progress = f" Improvement since first quiz: {int(improvement)}%." if improvement else ""
        public_discussions = memory.get("communityDiscussions") or []
        community_line = ""
        for discussion in public_discussions:
            if str(discussion.get("topic") or "").casefold() == str(top["topic"]).casefold():
                community_line = f" Many students are also discussing {top['topic']} in the community."
                break
        return f"Learning memory: the student has a recurring gap in {top['topic']} with {top.get('mistakes', 0)} mistake(s).{progress}{community_line}"
    except Exception as exc:  # pragma: no cover
        logger.debug("learning memory chat context unavailable: %s", exc)
        return None