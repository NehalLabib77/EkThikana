"""Phase 7 — Ziku Learning Community: the service layer.

One module owns every new community concept so the existing group/chat
surface in ``routers/groups.py`` is never duplicated:

* **Learning posts** (``community_posts`` + ``answers``) — the Question
  Bank and the learning post kinds (question / solution / notes /
  achievement) with study categories, AI subject+chapter tagging and
  rule-based duplicate detection.
* **Learning Points** (``community_reputation``) — +5 answer accepted,
  +3 helpful explanation, +10 useful notes, with a per-group split for
  the group leaderboard. Nothing else awards points.
* **Exam challenges** (``community_challenges``) — built from an
  existing exam paper through the Phase 3 loader, graded server-side,
  readable only through this module's API (Firestore rules deny the
  client outright so the answer key never leaves the backend).
* **Ziku Moderator** — ask / disagreement analysis / discussion topics /
  group quiz generation. Group quizzes live in ``groups/{id}/quizzes``
  with a backend-only answer key and per-member attempts.
* **Coach hand-off** — ``group_trend_line`` is the one sentence Study
  Coach chat context appends when a study group has a hot topic.

AI flows all sit behind the :func:`_ai` seam (and ``quiz_generate`` for
group quizzes); offline they degrade to rule-based tagging so no test or
device ever needs a provider key.
"""

from __future__ import annotations

import json
import logging
import re
import secrets
import string
from datetime import datetime, timedelta, timezone
from typing import Any

from app.core.auth import CurrentUser
from app.core.firebase import get_firestore
from app.services import ai_service
from app.services import mistake_memory_service as mistake_memory
from app.services.ai_service import AiFeature
from firebase_admin import firestore

logger = logging.getLogger("gochano.community")

# ---------------------------------------------------------------------------
# constants
# ---------------------------------------------------------------------------

#: Spec 7.5 — study categories. Free-form strings are rejected at the door.
STUDY_CATEGORIES: tuple[str, ...] = (
    "hsc",
    "university",
    "admission",
    "ielts",
    "coding",
    "engineering",
)

#: Phase 11 extends the academic post types without introducing social-media
#: entities or a second community store.
POST_KINDS: tuple[str, ...] = (
    "question",
    "solution",
    "notes",
    "achievement",
    "discussion",
    "study_challenge",
)

#: Spec 7.7 — teacher/class groups are architecture-only for now (created
#: through the API, no UI), but the shape is validated from day one.
GROUP_KINDS: tuple[str, ...] = ("study", "class", "teacher")

#: Spec 7.6 — the complete Learning Points table. Nothing else scores.
POINT_RULES: dict[str, int] = {
    "answer_accepted": 5,
    "helpful_explanation": 3,
    "useful_notes": 10,
    "quiz_created": 5,
}

POSTS = "community_posts"
ANSWERS = "answers"
REPUTATION = "community_reputation"
CHALLENGES = "community_challenges"
FAMILY_LINKS = "family_links"
GROUPS = "groups"
QUIZZES = "quizzes"
ATTEMPTS = "attempts"

_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
_MAX_FETCH = 300
_STOPWORDS = {
    "the", "and", "for", "with", "that", "this", "from", "are", "was",
    "were", "have", "has", "had", "you", "your", "not", "but", "can",
    "how", "why", "what", "when", "who", "does", "did", "into", "than",
    "then", "them", "they", "their", "there", "about", "which", "will",
    "would", "could", "should", "question", "answer", "explain",
}
_SUBJECT_KEYWORDS: dict[str, tuple[str, ...]] = {
    "physics": ("physics", "optics", "kinematics", "newton", "circuit", "wave"),
    "chemistry": ("chemistry", "mole", "organic", "reaction", "titration"),
    "biology": ("biology", "cell", "photosynthesis", "genetics", "enzyme"),
    "mathematics": ("math", "algebra", "calculus", "trigonometry", "geometry", "integral"),
    "bangla": ("bangla", "গল্প", "কবিতা"),
    "english": ("english", "grammar", "essay", "tenses", "paragraph"),
    "ict": ("ict", "database", "programming", "algorithm", "python", "website"),
    "economics": ("economics", "market", "demand", "supply", "gdp"),
    "accounting": ("accounting", "ledger", "journal", "balance sheet"),
}


class CommunityError(Exception):
    """Mapped to an HTTP error by the community routers (code, detail)."""

    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status = status
        self.detail = detail


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------

def _db():
    return get_firestore()


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(moment: datetime) -> str:
    return moment.isoformat()


def _invite_code(length: int = 8) -> str:
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def _text(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def _int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _iso_sort_key(data: dict[str, Any]) -> str:
    return _text(data.get("createdAtIso"))


async def _ai(uid: str, prompt: str, feature: str = AiFeature.CHAT) -> str:
    """Single AI seam — tests replace this instead of the provider cascade."""
    try:
        return await ai_service.generate(uid, prompt, feature=feature)
    except TypeError:  # older provider signatures take no feature kwarg
        return await ai_service.generate(uid, prompt)


def _parse_json(raw: Any) -> dict[str, Any]:
    """Accept raw model output with or without markdown fences."""
    text = _text(raw).strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1]
    if text.endswith("```"):
        text = text[:-3]
    try:
        parsed = json.loads(text)
    except (json.JSONDecodeError, ValueError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _invite_code_query(db, code: str):
    return (
        db.collection(CHALLENGES)
        .where("inviteCode", "==", code)
        .limit(1)
        .stream()
    )


def _tokens(value: str) -> set[str]:
    words = re.sub(r"[^a-z0-9\u0980-\u09ff]+", " ", _text(value).lower())
    return {w for w in words.split() if len(w) >= 3 and w not in _STOPWORDS}


def _similarity(a: str, b: str) -> float:
    ta, tb = _tokens(a), _tokens(b)
    if not ta or not tb:
        return 0.0
    return round(len(ta & tb) / len(ta | tb), 3)


def _guess_subject(value: str, category: str = "") -> str:
    lowered = _text(value).lower()
    for subject, keywords in _SUBJECT_KEYWORDS.items():
        if any(keyword in lowered for keyword in keywords):
            return subject.title()
    if category in ("hsc", "admission"):
        return "General"
    if category == "ielts":
        return "IELTS"
    if category == "coding":
        return "Programming"
    if category == "engineering":
        return "Engineering"
    return ""


# ---------------------------------------------------------------------------
# learning posts — Question Bank + learning post kinds (spec 7.3, 7.5)
# ---------------------------------------------------------------------------

def _public_post(doc_id: str, data: dict[str, Any], *, with_answers: bool = False,
                 answers: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    payload = {
        "id": doc_id,
        "kind": _text(data.get("kind")) or "question",
        "title": _text(data.get("title")),
        "body": _text(data.get("body")),
        "category": _text(data.get("category")),
        "groupId": _text(data.get("groupId")),
        "groupName": _text(data.get("groupName")),
        "authorId": _text(data.get("authorId")),
        "authorName": _text(data.get("authorName")),
        "subject": _text(data.get("subject")),
        "chapter": _text(data.get("chapter")),
        "concept": _text(data.get("concept")),
        "difficulty": _text(data.get("difficulty")),
        "relatedTopics": list(data.get("relatedTopics") or []),
        "analyzedBy": _text(data.get("analyzedBy")),
        "duplicateOf": _text(data.get("duplicateOf")),
        "duplicateOfTitle": _text(data.get("duplicateOfTitle")),
        "duplicateConfidence": _float(data.get("duplicateConfidence")),
        "answerCount": _int(data.get("answerCount")),
        "usefulCount": _int(data.get("usefulCount")),
        "acceptedAnswerId": _text(data.get("acceptedAnswerId")),
        "attachments": list(data.get("attachments") or []),
        "createdAtIso": _text(data.get("createdAtIso")),
    }
    if with_answers:
        payload["answers"] = answers or []
    return payload

def _public_answer(doc_id: str, data: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": doc_id,
        "postId": _text(data.get("postId")),
        "authorId": _text(data.get("authorId")),
        "authorName": _text(data.get("authorName")),
        "body": _text(data.get("body")),
        "accepted": bool(data.get("accepted")),
        "helpful": bool(data.get("helpful")),
        "createdAtIso": _text(data.get("createdAtIso")),
    }


def _load_post(post_id: str) -> tuple[str, dict[str, Any]]:
    snap = _db().collection(POSTS).document(post_id).get()
    if not snap.exists:
        raise CommunityError(404, "Post not found")
    return snap.id, snap.to_dict() or {}


def _require_group_member(group_id: str, uid: str) -> dict[str, Any]:
    if not group_id:
        raise CommunityError(400, "groupId is required")
    snap = _db().collection(GROUPS).document(group_id).get()
    if not snap.exists:
        raise CommunityError(404, "Group not found")
    data = snap.to_dict() or {}
    if uid not in (data.get("memberIds") or []):
        raise CommunityError(403, "Members only")
    return data


def _read_reputation(uid: str) -> dict[str, Any]:
    snap = _db().collection(REPUTATION).document(uid).get()
    return snap.to_dict() or {}


def _award_points(uid: str, display_name: str, event: str, *, group_id: str = "") -> dict[str, Any]:
    """One Learning Points credit. ``event`` must be a POINT_RULES key."""
    if event not in POINT_RULES:
        raise CommunityError(500, f"Unknown reputation event {event}")
    points = POINT_RULES[event]
    current = _read_reputation(uid)
    breakdown = dict(current.get("breakdown") or {})
    breakdown[event] = _int(breakdown.get(event)) + 1
    group_points = dict(current.get("groupPoints") or {})
    if group_id:
        group_points[group_id] = _int(group_points.get(group_id)) + points
    payload = {
        "uid": uid,
        "displayName": _text(display_name) or _text(current.get("displayName")),
        "points": _int(current.get("points")) + points,
        "breakdown": breakdown,
        "groupPoints": group_points,
        "updatedAt": _iso(_now()),
    }
    _db().collection(REPUTATION).document(uid).set(payload, merge=True)
    return payload


def _find_duplicate_candidate(title: str, body: str) -> dict[str, Any] | None:
    """Rule-based near-duplicate scan over recent questions.

    Deterministic and offline: an AI confirmation can add a weaker match,
    but a 75% token overlap always flags on its own.
    """
    rows = [
        {**(snap.to_dict() or {}), "id": snap.id}
        for snap in _db().collection(POSTS).where("kind", "==", "question").stream()
    ]
    rows = [r for r in rows if _text(r.get("status", "active")) != "hidden"]
    rows.sort(key=_iso_sort_key, reverse=True)
    text = f"{_text(title)} {_text(body)}"
    best: dict[str, Any] | None = None
    best_score = 0.0
    for data in rows[:_MAX_FETCH]:
        score = _similarity(text, f"{_text(data.get('title'))} {_text(data.get('body'))}")
        if score > best_score:
            best_score = score
            best = data
    if best is None or best_score < 0.45:
        return None
    return {"data": best, "score": best_score}


async def _analyze_post(uid: str, title: str, body: str, category: str) -> dict[str, Any]:
    """AI subject/chapter tagging + duplicate confirmation, offline-safe."""
    candidate = _find_duplicate_candidate(title, body)
    candidate_hint = ""
    if candidate is not None:
        candidate_hint = (
            f"Possible duplicate: {candidate['data'].get('title')!r} "
            f"(similarity {candidate['score']:.2f}).\n"
        )
    prompt = (
        "You tag study-community posts for students.\n"
        f"POST KIND CONTEXT: category={category or 'general'}.\n"
        f"TITLE: {title}\n"
        f"BODY:\n{body[:2000]}\n\n"
        f"{candidate_hint}"
        "Return ONLY JSON: {\"subject\": \"Physics\", \"chapter\": \"Optics\", "
        "\"concept\": \"Total internal reflection\", \"difficulty\": "
        "\"easy|medium|hard\", \"relatedTopics\": [\"...\"], "
        "\"isDuplicate\": true|false}. "
        "subject is a school/university subject (short). chapter is the "
        "specific topic (e.g. Optics, Derivatives) or \"\" when unclear. "
        "isDuplicate says whether the post asks the same question as the "
        "possible duplicate."
    )
    analyzed_by = "ai"
    subject = ""
    chapter = ""
    concept = ""
    difficulty = "medium"
    related_topics: list[str] = []
    ai_duplicate: bool | None = None
    try:
        parsed = _parse_json(await _ai(uid, prompt, AiFeature.CHAT))
    except Exception as exc:  # provider down / offline
        logger.info("post analysis unavailable (%s); using rule-based tags", exc)
        parsed = {}
        analyzed_by = "fallback"
    if parsed:
        subject = _text(parsed.get("subject"))
        chapter = _text(parsed.get("chapter"))
        concept = _text(parsed.get("concept"))
        difficulty = _text(parsed.get("difficulty"), "medium").lower()
        if difficulty not in {"easy", "medium", "hard"}:
            difficulty = "medium"
        related_topics = [_text(topic)[:100] for topic in (parsed.get("relatedTopics") or []) if _text(topic)][:8]
        if isinstance(parsed.get("isDuplicate"), bool):
            ai_duplicate = parsed["isDuplicate"]
    else:
        # Provider offline or returned prose: keep the tags honest.
        analyzed_by = "fallback"
        subject = _guess_subject(f"{title} {body}", category)
        concept = chapter or title[:120]
        related_topics = [chapter] if chapter else []
    duplicate_of = ""
    duplicate_title = ""
    confidence = 0.0
    if candidate is not None:
        score = candidate["score"]
        confirmed = score >= 0.75 or (ai_duplicate is True and score >= 0.45)
        if confirmed:
            duplicate_of = _text(candidate["data"].get("id")) or _text(candidate["data"].get("title"))
            duplicate_title = _text(candidate["data"].get("title"))
            confidence = score
    return {
        "subject": subject,
        "chapter": chapter,
        "concept": concept,
        "difficulty": difficulty,
        "relatedTopics": related_topics,
        "analyzedBy": analyzed_by,
        "duplicateOf": duplicate_of,
        "duplicateOfTitle": duplicate_title,
        "duplicateConfidence": confidence,
    }


async def create_post(
    uid: str,
    display_name: str,
    *,
    kind: str,
    title: str,
    body: str,
    category: str = "",
    group_id: str = "",
    attachments: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    kind = _text(kind).strip().lower()
    if kind not in POST_KINDS:
        raise CommunityError(400, f"kind must be one of {list(POST_KINDS)}")
    category = _text(category).strip().lower()
    if category and category not in STUDY_CATEGORIES:
        raise CommunityError(400, f"category must be one of {list(STUDY_CATEGORIES)}")
    title = _text(title).strip()
    body = _text(body).strip()
    if not title and not body:
        raise CommunityError(400, "Post needs a title or some text")
    group_name = ""
    if group_id:
        group = _require_group_member(group_id, uid)
        group_name = _text(group.get("name"))

    analysis = await _analyze_post(uid, title, body, category)

    now = _now()
    ref = _db().collection(POSTS).document()
    ref.set(
        {
            "kind": kind,
            "title": title[:300],
            "body": body[:8000],
            "category": category,
            "groupId": group_id,
            "groupName": group_name,
            "authorId": uid,
            "authorName": _text(display_name),
            "subject": analysis["subject"],
            "chapter": analysis["chapter"],
            "concept": analysis["concept"],
            "difficulty": analysis["difficulty"],
            "relatedTopics": analysis["relatedTopics"],
            "analyzedBy": analysis["analyzedBy"],
            "duplicateOf": analysis["duplicateOf"],
            "duplicateOfTitle": analysis["duplicateOfTitle"],
            "duplicateConfidence": analysis["duplicateConfidence"],
            "status": "active",
            "answerCount": 0,
            "usefulCount": 0,
            "usefulBy": [],
            "acceptedAnswerId": "",
            "attachments": list(attachments or []),
            "createdAt": firestore.SERVER_TIMESTAMP,
            "createdAtIso": _iso(now),
        }
    )
    _, data = _load_post(ref.id)
    from app.services.analytics_service import track_event

    if kind == "question":
        track_event(uid, "community_question_posted", {"subject": analysis["subject"], "chapter": analysis["chapter"], "source": "community"})
    return _public_post(ref.id, data)


def list_posts(
    *,
    kind: str = "",
    category: str = "",
    group_id: str = "",
    popular: bool = False,
    limit: int = 30,
    uid: str = "",
) -> dict[str, Any]:
    limit = max(1, min(_int(limit, 30), 50))
    if group_id:
        _require_group_member(group_id, uid)
    kind = _text(kind).strip().lower()
    if kind and kind not in POST_KINDS:
        raise CommunityError(400, f"kind must be one of {list(POST_KINDS)}")
    category = _text(category).strip().lower()
    if category and category not in STUDY_CATEGORIES:
        raise CommunityError(400, f"category must be one of {list(STUDY_CATEGORIES)}")

    query = _db().collection(POSTS).stream()
    rows: list[tuple[str, dict[str, Any]]] = []
    for snap in query:
        data = snap.to_dict() or {}
        if kind and _text(data.get("kind")) != kind:
            continue
        if category and _text(data.get("category")) != category:
            continue
        if group_id and _text(data.get("groupId")) != group_id:
            continue
        if _text(data.get("status")) == "hidden":
            continue
        rows.append((snap.id, data))

    if popular:
        rows.sort(
            key=lambda item: (
                _int(item[1].get("answerCount")) + _int(item[1].get("usefulCount"))
            ),
            reverse=True,
        )
    else:
        rows.sort(key=lambda item: _iso_sort_key(item[1]), reverse=True)

    return {
        "posts": [_public_post(doc_id, data) for doc_id, data in rows[:limit]],
        "popular": bool(popular),
    }


def get_post(post_id: str, uid: str) -> dict[str, Any]:
    doc_id, data = _load_post(post_id)
    group_id = _text(data.get("groupId"))
    if group_id:
        _require_group_member(group_id, uid)
    answers = []
    for snap in _db().collection(POSTS).document(post_id).collection(ANSWERS).stream():
        answers.append(_public_answer(snap.id, snap.to_dict() or {}))
    answers.sort(key=lambda a: a["createdAtIso"])
    return _public_post(doc_id, data, with_answers=True, answers=answers)


def add_answer(
    uid: str,
    display_name: str,
    post_id: str,
    body: str,
) -> dict[str, Any]:
    _, data = _load_post(post_id)
    if _text(data.get("groupId")):
        _require_group_member(_text(data.get("groupId")), uid)
    if _text(data.get("kind")) != "question":
        raise CommunityError(400, "Only question posts take answers")
    body = _text(body).strip()
    if not body:
        raise CommunityError(400, "Answer is empty")

    now = _now()
    ref = _db().collection(POSTS).document(post_id).collection(ANSWERS).document()
    ref.set(
        {
            "postId": post_id,
            "authorId": uid,
            "authorName": _text(display_name),
            "body": body[:6000],
            "accepted": False,
            "helpful": False,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "createdAtIso": _iso(now),
        }
    )
    _db().collection(POSTS).document(post_id).set(
        {"answerCount": _int(data.get("answerCount")) + 1},
        merge=True,
    )
    from app.services.analytics_service import track_event

    track_event(uid, "community_answer_given", {"subject": data.get("subject"), "chapter": data.get("chapter"), "source": "community"})
    _, fresh = _load_post(post_id)
    return _public_answer(ref.id, {
        "postId": post_id,
        "authorId": uid,
        "authorName": _text(display_name),
        "body": body[:6000],
        "createdAtIso": _iso(now),
    }) | {"postAnswerCount": _int(fresh.get("answerCount"))}


def accept_answer(uid: str, post_id: str, answer_id: str) -> dict[str, Any]:
    """Spec 7.6 — +5 Learning Points when the asker accepts an answer."""
    _, post = _load_post(post_id)
    if _text(post.get("authorId")) != uid:
        raise CommunityError(403, "Only the asker can accept an answer")
    if _text(post.get("acceptedAnswerId")):
        raise CommunityError(400, "Another answer is already accepted")
    answer_ref = _db().collection(POSTS).document(post_id).collection(ANSWERS).document(answer_id)
    snap = answer_ref.get()
    if not snap.exists:
        raise CommunityError(404, "Answer not found")
    answer = snap.to_dict() or {}
    answer_ref.set({"accepted": True}, merge=True)
    _db().collection(POSTS).document(post_id).set(
        {"acceptedAnswerId": answer_id},
        merge=True,
    )
    awarded = 0
    if _text(answer.get("authorId")) != uid:
        _award_points(
            _text(answer.get("authorId")),
            _text(answer.get("authorName")),
            "answer_accepted",
            group_id=_text(post.get("groupId")),
        )
        awarded = POINT_RULES["answer_accepted"]
    return {
        "postId": post_id,
        "answerId": answer_id,
        "accepted": True,
        "pointsAwarded": awarded,
    }


def mark_helpful(uid: str, post_id: str, answer_id: str) -> dict[str, Any]:
    """Spec 7.6 — +3 for a helpful explanation (once, non-authors only)."""
    _, post = _load_post(post_id)
    answer_ref = _db().collection(POSTS).document(post_id).collection(ANSWERS).document(answer_id)
    snap = answer_ref.get()
    if not snap.exists:
        raise CommunityError(404, "Answer not found")
    answer = snap.to_dict() or {}
    if _text(answer.get("authorId")) == uid:
        raise CommunityError(400, "You cannot mark your own answer helpful")
    if answer.get("helpful"):
        return {"postId": post_id, "answerId": answer_id, "helpful": True, "pointsAwarded": 0}
    answer_ref.set({"helpful": True}, merge=True)
    _award_points(
        _text(answer.get("authorId")),
        _text(answer.get("authorName")),
        "helpful_explanation",
        group_id=_text(post.get("groupId")),
    )
    return {
        "postId": post_id,
        "answerId": answer_id,
        "helpful": True,
        "pointsAwarded": POINT_RULES["helpful_explanation"],
    }


def mark_useful(uid: str, post_id: str) -> dict[str, Any]:
    """Spec 7.6 — +10 when a notes post is first marked useful by a peer."""
    doc_id, post = _load_post(post_id)
    if _text(post.get("kind")) != "notes":
        raise CommunityError(400, "Only notes posts can be marked useful")
    if _text(post.get("authorId")) == uid:
        raise CommunityError(400, "You cannot mark your own note useful")
    useful_by = list(post.get("usefulBy") or [])
    if uid in useful_by:
        return {"postId": doc_id, "usefulCount": _int(post.get("usefulCount")), "pointsAwarded": 0}
    first = _int(post.get("usefulCount")) == 0
    useful_by.append(uid)
    _db().collection(POSTS).document(post_id).set(
        {"usefulBy": useful_by, "usefulCount": _int(post.get("usefulCount")) + 1},
        merge=True,
    )
    awarded = 0
    if first:
        _award_points(
            _text(post.get("authorId")),
            _text(post.get("authorName")),
            "useful_notes",
            group_id=_text(post.get("groupId")),
        )
        awarded = POINT_RULES["useful_notes"]
    return {
        "postId": doc_id,
        "usefulCount": _int(post.get("usefulCount")) + 1,
        "pointsAwarded": awarded,
    }


# ---------------------------------------------------------------------------
# leaderboard (spec 7.6)
# ---------------------------------------------------------------------------

def leaderboard(*, scope: str = "global", group_id: str = "", limit: int = 20,
                uid: str = "") -> dict[str, Any]:
    limit = max(1, min(_int(limit, 20), 50))
    entries: list[dict[str, Any]] = []

    if scope == "group":
        group = _require_group_member(group_id, uid)
        member_ids = list(group.get("memberIds") or [])
        for member in member_ids[:100]:
            data = _read_reputation(member)
            group_points = _int((data.get("groupPoints") or {}).get(group_id))
            if group_points <= 0:
                continue
            entries.append(
                {
                    "uid": member,
                    "displayName": _text(data.get("displayName")),
                    "points": group_points,
                    "totalPoints": _int(data.get("points")),
                    "breakdown": data.get("breakdown") or {},
                }
            )
        entries.sort(key=lambda e: e["points"], reverse=True)
        return {"scope": "group", "groupId": group_id, "entries": entries[:limit]}

    for snap in _db().collection(REPUTATION).stream():
        data = snap.to_dict() or {}
        entries.append(
            {
                "uid": snap.id,
                "displayName": _text(data.get("displayName")),
                "points": _int(data.get("points")),
                "totalPoints": _int(data.get("points")),
                "breakdown": data.get("breakdown") or {},
            }
        )
    entries.sort(key=lambda e: e["points"], reverse=True)
    return {"scope": "global", "entries": entries[:limit]}


# ---------------------------------------------------------------------------
# exam challenges (spec 7.4)
# ---------------------------------------------------------------------------

def _public_challenge(doc_id: str, data: dict[str, Any], *, uid: str = "",
                      questions: bool = False) -> dict[str, Any]:
    results = data.get("results") or {}
    my_role = (
        "challenger" if uid == _text(data.get("challengerId"))
        else "opponent" if uid == _text(data.get("opponentId"))
        else ""
    )
    mine = results.get(uid) or {}
    opponent_uid = (
        _text(data.get("opponentId")) if my_role == "challenger"
        else _text(data.get("challengerId"))
    )
    other = results.get(opponent_uid) or {}
    completed = _text(data.get("status")) == "completed"

    def _result_view(entry: dict[str, Any]) -> dict[str, Any] | None:
        if not entry or not entry.get("completedAt"):
            return None
        return {
            "score": _int(entry.get("score")),
            "total": _int(entry.get("total")),
            "accuracy": _float(entry.get("accuracy")),
            "durationSeconds": _int(entry.get("durationSeconds")),
            "topicScores": entry.get("topicScores") or {},
            "completedAt": _text(entry.get("completedAt")),
        }

    payload = {
        "id": doc_id,
        "title": _text(data.get("title")),
        "subject": _text(data.get("subject")),
        "examId": _text(data.get("examId")),
        "examTitle": _text(data.get("examTitle")),
        "status": _text(data.get("status")),
        "inviteCode": _text(data.get("inviteCode")),
        "questionCount": _int(data.get("questionCount")),
        "timeLimitMinutes": _int(data.get("timeLimitMinutes")),
        "challengerId": _text(data.get("challengerId")),
        "challengerName": _text(data.get("challengerName")),
        "opponentId": _text(data.get("opponentId")),
        "opponentName": _text(data.get("opponentName")),
        "myRole": my_role,
        "started": bool((results.get(uid) or {}).get("startedAt")),
        "myResult": _result_view(mine),
        # The comparison only exists once both students have finished — the
        # two participants agreed to compete, so their accuracy/time/topics
        # are shareable with each other, and with nobody else.
        "opponentResult": _result_view(other) if completed else None,
        "createdAtIso": _text(data.get("createdAtIso")),
    }
    if questions:
        payload["questions"] = [
            {
                "index": _int(q.get("index")),
                "question": _text(q.get("question")),
                "type": _text(q.get("type")) or "mcq",
                "options": list(q.get("options") or []),
                "topic": _text(q.get("topic")),
                "marks": _float(q.get("marks")),
            }
            for q in (data.get("questions") or [])
        ]
    else:
        payload["questions"] = []
    return payload


def _load_challenge(challenge_id: str, uid: str) -> tuple[str, dict[str, Any]]:
    snap = _db().collection(CHALLENGES).document(challenge_id).get()
    if not snap.exists:
        raise CommunityError(404, "Challenge not found")
    data = snap.to_dict() or {}
    if uid not in {_text(data.get("challengerId")), _text(data.get("opponentId"))}:
        raise CommunityError(403, "Only the two participants can see this challenge")
    return snap.id, data


def _shared_group(uid: str, other_uid: str) -> str:
    for snap in _db().collection(GROUPS).where("memberIds", "array_contains", uid).stream():
        data = snap.to_dict() or {}
        if other_uid in (data.get("memberIds") or []):
            return snap.id
    raise CommunityError(404, "You are not in a shared group with that student")


def create_challenge(
    uid: str,
    display_name: str,
    *,
    title: str,
    exam_id: str,
    question_count: int = 10,
    time_limit_minutes: int = 15,
    opponent_id: str = "",
) -> dict[str, Any]:
    from app.services import exam_simulator_service as exams

    _, exam = exams._load_exam(uid, exam_id)  # ExamError → router maps it
    source_questions = exams._load_questions(uid, exam_id)
    if not source_questions:
        raise CommunityError(400, "That paper has no questions yet")
    if opponent_id and opponent_id == uid:
        raise CommunityError(400, "Pick a classmate, not yourself")
    if opponent_id:
        _shared_group(uid, opponent_id)

    count = max(1, min(_int(question_count, 10), 50, len(source_questions)))
    minutes = max(1, min(_int(time_limit_minutes, 15), 480))
    selected = source_questions[:count]
    questions = [
        {
            "index": _int(q.get("index"), i),
            "question": _text(q.get("question")),
            "type": _text(q.get("type")) or "mcq",
            "options": list(q.get("options") or []),
            "correct": _text(q.get("correct")),
            "explanation": _text(q.get("explanation")),
            "topic": _text(q.get("topic")) or _text(exam.get("subject")) or "General",
            "marks": _float(q.get("marks"), 1.0),
        }
        for i, q in enumerate(selected)
    ]

    now = _now()
    ref = _db().collection(CHALLENGES).document()
    code = _invite_code()
    ref.set(
        {
            "title": _text(title).strip()[:120]
            or f"{_text(exam.get('subject')) or 'Exam'} Challenge",
            "examId": exam_id,
            "examTitle": _text(exam.get("title")),
            "subject": _text(exam.get("subject")),
            "questionCount": len(questions),
            "timeLimitMinutes": minutes,
            "challengerId": uid,
            "challengerName": _text(display_name),
            "opponentId": _text(opponent_id),
            "opponentName": "",
            "inviteCode": code,
            "status": "pending",
            "questions": questions,
            "results": {},
            "createdAt": firestore.SERVER_TIMESTAMP,
            "createdAtIso": _iso(now),
        }
    )
    _, data = _load_challenge(ref.id, uid)
    return _public_challenge(ref.id, data, uid=uid)


def join_challenge(uid: str, display_name: str, code: str) -> dict[str, Any]:
    code = _text(code).strip().upper()
    if not code:
        raise CommunityError(400, "Enter the challenge code")
    rows = list(_invite_code_query(_db(), code))
    if not rows:
        raise CommunityError(404, "Challenge code not found")
    snap = rows[0]
    data = snap.to_dict() or {}
    if _text(data.get("status")) != "pending":
        raise CommunityError(400, "That challenge is no longer waiting for a player")
    if uid == _text(data.get("challengerId")):
        raise CommunityError(400, "You created this challenge")
    target = _text(data.get("opponentId"))
    if target and target != uid:
        raise CommunityError(403, "This challenge is waiting for a specific classmate")
    snap.reference.set(
        {
            "opponentId": uid,
            "opponentName": _text(display_name),
            "status": "accepted",
            "acceptedAt": _iso(_now()),
        },
        merge=True,
    )
    fresh_data = snap.reference.get().to_dict() or {}
    return _public_challenge(snap.id, fresh_data, uid=uid)


def decline_challenge(uid: str, challenge_id: str) -> dict[str, Any]:
    _, data = _load_challenge(challenge_id, uid)
    status = _text(data.get("status"))
    if status == "pending" and uid == _text(data.get("challengerId")):
        new_status = "cancelled"
    elif status == "accepted" and uid == _text(data.get("opponentId")):
        new_status = "declined"
    else:
        raise CommunityError(400, "This challenge cannot be declined now")
    _db().collection(CHALLENGES).document(challenge_id).set(
        {"status": new_status}, merge=True
    )
    data = {**data, "status": new_status}
    return _public_challenge(challenge_id, data, uid=uid)


def list_challenges(uid: str) -> dict[str, Any]:
    seen: dict[str, dict[str, Any]] = {}
    for query in (
        _db().collection(CHALLENGES).where("challengerId", "==", uid).stream(),
        _db().collection(CHALLENGES).where("opponentId", "==", uid).stream(),
    ):
        for snap in query:
            seen[snap.id] = snap.to_dict() or {}
    rows = sorted(seen.items(), key=lambda item: _iso_sort_key(item[1]), reverse=True)
    return {
        "challenges": [
            _public_challenge(doc_id, data, uid=uid) for doc_id, data in rows[:50]
        ]
    }


def get_challenge(challenge_id: str, uid: str) -> dict[str, Any]:
    doc_id, data = _load_challenge(challenge_id, uid)
    return _public_challenge(doc_id, data, uid=uid)


def start_challenge(challenge_id: str, uid: str) -> dict[str, Any]:
    doc_id, data = _load_challenge(challenge_id, uid)
    if _text(data.get("status")) != "accepted":
        raise CommunityError(409, "Waiting for the other player to join")
    results = dict(data.get("results") or {})
    entry = dict(results.get(uid) or {})
    if entry.get("completedAt"):
        raise CommunityError(400, "You already finished this challenge")
    if not entry.get("startedAt"):
        entry["startedAt"] = _iso(_now())
        results[uid] = entry
        _db().collection(CHALLENGES).document(doc_id).set(
            {"results": results}, merge=True
        )
    payload = _public_challenge(doc_id, {**data, "results": results}, uid=uid, questions=True)
    payload["timeLimitSeconds"] = _int(data.get("timeLimitMinutes")) * 60
    payload["startedAt"] = _text(entry.get("startedAt"))
    return payload


def _grade_answers(questions: list[dict[str, Any]], answers: Any) -> dict[str, Any]:
    from app.services.mistake_memory_service import answers_match

    if not isinstance(answers, list):
        answers = []
    score = 0
    topic_scores: dict[str, dict[str, int]] = {}
    correct_flags: list[bool] = []
    for i, question in enumerate(questions):
        given = answers[i] if i < len(answers) else ""
        correct = _text(question.get("correct"))
        q_type = _text(question.get("type")) or "mcq"
        if q_type == "mcq":
            hit = bool(answers_match(given, correct))
        else:
            hit = _text(given).strip().lower() == correct.strip().lower()
        correct_flags.append(hit)
        if hit:
            score += 1
        topic = _text(question.get("topic")) or "General"
        bucket = topic_scores.setdefault(topic, {"correct": 0, "total": 0})
        bucket["total"] += 1
        if hit:
            bucket["correct"] += 1
    total = len(questions)
    accuracy = round((score / total) * 100, 1) if total else 0.0
    return {
        "score": score,
        "total": total,
        "accuracy": accuracy,
        "topicScores": topic_scores,
        "correctFlags": correct_flags,
    }


def _clamp_duration(entry: dict[str, Any], requested: Any, limit_seconds: int) -> tuple[int, bool]:
    duration = max(0, min(_int(requested), limit_seconds))
    timed_out = False
    started = _text(entry.get("startedAt"))
    if started:
        try:
            began = datetime.fromisoformat(started)
            if began.tzinfo is None:
                began = began.replace(tzinfo=timezone.utc)
            if _now() > began + timedelta(seconds=limit_seconds + 15):
                duration = limit_seconds
                timed_out = True
        except ValueError:
            pass
    return duration, timed_out


def submit_challenge(
    challenge_id: str,
    uid: str,
    answers: Any,
    duration_seconds: int = 0,
) -> dict[str, Any]:
    doc_id, data = _load_challenge(challenge_id, uid)
    results = dict(data.get("results") or {})
    entry = dict(results.get(uid) or {})
    if not entry.get("startedAt"):
        raise CommunityError(400, "Start the challenge before submitting")
    if entry.get("completedAt"):
        raise CommunityError(400, "You already submitted this challenge")

    questions = list(data.get("questions") or [])
    graded = _grade_answers(questions, answers)
    limit_seconds = _int(data.get("timeLimitMinutes")) * 60
    duration, timed_out = _clamp_duration(entry, duration_seconds, limit_seconds)

    entry.update(
        {
            "answers": list(answers) if isinstance(answers, list) else [],
            "correctFlags": graded["correctFlags"],
            "score": graded["score"],
            "total": graded["total"],
            "accuracy": graded["accuracy"],
            "topicScores": graded["topicScores"],
            "durationSeconds": duration,
            "timedOut": timed_out,
            "completedAt": _iso(_now()),
        }
    )
    results[uid] = entry

    challenger_done = bool((results.get(_text(data.get("challengerId"))) or {}).get("completedAt"))
    opponent_id = _text(data.get("opponentId"))
    opponent_done = bool((results.get(opponent_id) or {}).get("completedAt")) if opponent_id else False
    status = "completed" if (challenger_done and opponent_done) else _text(data.get("status"))

    _db().collection(CHALLENGES).document(doc_id).set(
        {"results": results, "status": status},
        merge=True,
    )
    from app.services.analytics_service import track_event

    track_event(
        uid,
        "challenge_completed",
        {
            "subject": data.get("subject"),
            "topic": data.get("title"),
            "score": entry.get("score"),
            "total": entry.get("total"),
            "duration_seconds": entry.get("durationSeconds"),
            "source": "community_challenge",
        },
    )
    _, fresh = _load_challenge(doc_id, uid)
    return _public_challenge(doc_id, fresh, uid=uid)


# ---------------------------------------------------------------------------
# family links — spec 7.7 architecture only (no UI anywhere)
# ---------------------------------------------------------------------------

def create_family_code(uid: str, role: str, display_name: str) -> dict[str, Any]:
    if role != "student":
        raise CommunityError(403, "Student account required")
    db = _db()
    # One live code per student: re-issuing invalidates the previous one.
    for snap in db.collection(FAMILY_LINKS).where("childId", "==", uid).stream():
        data = snap.to_dict() or {}
        if _text(data.get("status")) == "open":
            snap.reference.delete()
    now = _now()
    ref = db.collection(FAMILY_LINKS).document()
    code = _invite_code(6)
    ref.set(
        {
            "code": code,
            "childId": uid,
            "childName": _text(display_name),
            "parentId": "",
            "parentName": "",
            "status": "open",
            "createdAt": firestore.SERVER_TIMESTAMP,
            "createdAtIso": _iso(now),
        }
    )
    return {"id": ref.id, "code": code, "status": "open"}


def redeem_family_code(uid: str, role: str, display_name: str, code: str) -> dict[str, Any]:
    if role != "general":
        raise CommunityError(403, "Only a parent or guardian account can link")
    code = _text(code).strip().upper()
    rows = list(
        _db().collection(FAMILY_LINKS).where("code", "==", code).limit(1).stream()
    )
    if not rows:
        raise CommunityError(404, "Link code not found")
    snap = rows[0]
    data = snap.to_dict() or {}
    if _text(data.get("status")) != "open":
        raise CommunityError(400, "That link code was already used")
    if uid == _text(data.get("childId")):
        raise CommunityError(400, "A student cannot link to themselves")
    snap.reference.set(
        {
            "parentId": uid,
            "parentName": _text(display_name),
            "status": "active",
            "linkedAt": _iso(_now()),
        },
        merge=True,
    )
    fresh = snap.reference.get().to_dict() or {}
    return _public_family_link(snap.id, fresh, uid=uid)


def _public_family_link(doc_id: str, data: dict[str, Any], *, uid: str) -> dict[str, Any]:
    # Deliberately thin: ids and names only. Scores, exams and mistakes are
    # NOT part of this payload — a parent view will request them explicitly
    # in a later phase, behind its own permission check.
    return {
        "id": doc_id,
        "status": _text(data.get("status")),
        "childId": _text(data.get("childId")),
        "childName": _text(data.get("childName")),
        "parentId": _text(data.get("parentId")),
        "parentName": _text(data.get("parentName")),
        "linkedAt": _text(data.get("linkedAt")),
        "myRole": "child" if uid == _text(data.get("childId")) else "parent",
    }


def list_family_links(uid: str) -> dict[str, Any]:
    links: dict[str, dict[str, Any]] = {}
    for snap in _db().collection(FAMILY_LINKS).stream():
        data = snap.to_dict() or {}
        if uid in {_text(data.get("childId")), _text(data.get("parentId"))}:
            if _text(data.get("status")) == "open":
                continue
            links[snap.id] = _public_family_link(snap.id, data, uid=uid)
    return {"links": list(links.values())}


# ---------------------------------------------------------------------------
# group insights — shared by moderator, quiz generation and Study Coach
# ---------------------------------------------------------------------------

def _group_questions(group_id: str, limit: int = _MAX_FETCH) -> list[dict[str, Any]]:
    rows = []
    for snap in _db().collection(POSTS).where("groupId", "==", group_id).stream():
        data = snap.to_dict() or {}
        if _text(data.get("kind")) == "question":
            rows.append(data)
    rows.sort(key=_iso_sort_key, reverse=True)
    return rows[:limit]


def _group_quiz_attempts(group_id: str) -> list[dict[str, Any]]:
    attempts: list[dict[str, Any]] = []
    try:
        quiz_rows = list(
            _db().collection(GROUPS).document(group_id).collection(QUIZZES).stream()
        )
    except Exception:  # pragma: no cover - defensive
        return attempts
    for quiz_snap in quiz_rows:
        for attempt_snap in (
            _db()
            .collection(GROUPS)
            .document(group_id)
            .collection(QUIZZES)
            .document(quiz_snap.id)
            .collection(ATTEMPTS)
            .stream()
        ):
            attempts.append(attempt_snap.to_dict() or {})
    return attempts


def group_insights_data(group_id: str) -> dict[str, Any]:
    questions = _group_questions(group_id)
    chapter_counts: dict[tuple[str, str], int] = {}
    for data in questions:
        chapter = _text(data.get("chapter")) or _text(data.get("title"))[:60]
        if not chapter:
            continue
        key = (chapter, _text(data.get("subject")))
        chapter_counts[key] = chapter_counts.get(key, 0) + 1
    hot_chapters = sorted(
        (
            {"chapter": chapter, "subject": subject, "count": count}
            for (chapter, subject), count in chapter_counts.items()
        ),
        key=lambda e: e["count"],
        reverse=True,
    )

    topic_totals: dict[str, list[float]] = {}
    attempts = _group_quiz_attempts(group_id)
    for attempt in attempts:
        for topic, bucket in (attempt.get("topicScores") or {}).items():
            total = _int((bucket or {}).get("total"))
            correct = _int((bucket or {}).get("correct"))
            if total > 0:
                topic_totals.setdefault(str(topic), []).append(correct / total)
    weak_topics = sorted(
        (
            {
                "topic": topic,
                "accuracy": round(sum(values) / len(values) * 100, 1),
                "attempts": len(values),
            }
            for topic, values in topic_totals.items()
        ),
        key=lambda e: e["accuracy"],
    )

    return {
        "hotChapters": hot_chapters[:5],
        "weakTopics": [t for t in weak_topics if t["accuracy"] < 70][:5],
        "questionCount": len(questions),
        "quizCount": len(attempts),
    }


def group_insights(group_id: str, uid: str) -> dict[str, Any]:
    _require_group_member(group_id, uid)
    return {"groupId": group_id, **group_insights_data(group_id)}


def group_trend_line(uid: str) -> str | None:
    """One sentence for Ziku Coach's chat context (Phase 7 hand-off).

    Read-only and defensive: no group with at least two questions on the
    same chapter means no line.
    """
    try:
        db = _db()
        best: tuple[int, str, str] | None = None  # count, chapter, group name
        groups = list(
            db.collection(GROUPS).where("memberIds", "array_contains", uid).limit(5).stream()
        )
        for snap in groups:
            data = snap.to_dict() or {}
            questions = _group_questions(snap.id, limit=30)
            counts: dict[str, int] = {}
            for question in questions:
                chapter = _text(question.get("chapter"))
                if chapter:
                    counts[chapter] = counts.get(chapter, 0) + 1
            for chapter, count in counts.items():
                if count >= 2 and (best is None or count > best[0]):
                    best = (count, chapter, _text(data.get("name")))
        if best is None:
            return None
        _, chapter, group_name = best
        return (
            f"Group hotspot: {chapter} is the hottest question topic in your "
            f"{group_name} study group."
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("community trend unavailable (%s)", exc)
        return None


# ---------------------------------------------------------------------------
# Ziku Moderator (spec 7.2)
# ---------------------------------------------------------------------------

def _group_context(group_id: str, group: dict[str, Any]) -> str:
    parts = [
        f"Group: {_text(group.get('name'))}",
        f"About: {_text(group.get('description')) or 'study group'}",
    ]
    try:
        messages = list(
            _db()
            .collection("group_messages")
            .where("groupId", "==", group_id)
            .stream()
        )
    except Exception:  # pragma: no cover - defensive
        messages = []
    rows = [s.to_dict() or {} for s in messages]
    rows.sort(key=lambda d: _text(d.get("createdAtIso")), reverse=True)
    recent = [
        f"- {_text(r.get('senderName')) or 'Student'}: {_text(r.get('text'))[:160]}"
        for r in rows[:10]
        if _text(r.get("text"))
    ]
    if recent:
        parts.append("Recent chat:\n" + "\n".join(recent))
    questions = _group_questions(group_id, limit=8)
    titles = [f"- {_text(q.get('subject'))}: {_text(q.get('title'))[:120]}" for q in questions]
    if titles:
        parts.append("Recent questions in the question bank:\n" + "\n".join(titles))
    return "\n".join(parts)


async def ziku_ask(uid: str, group_id: str, question: str) -> dict[str, Any]:
    group = _require_group_member(group_id, uid)
    question = _text(question).strip()
    if not question:
        raise CommunityError(400, "Ask Ziku something first")
    context = _group_context(group_id, group)
    prompt = (
        "You are Ziku, the AI moderator inside a student study group. "
        "Answer the doubt clearly, step by step, in the same language as "
        "the question. Be encouraging and academic - no marks, no grades, "
        "no personal data.\n\n"
        f"{context}\n\n"
        f"STUDENT'S DOUBT: {question[:2000]}\n\n"
        "Answer:"
    )
    try:
        answer = await _ai(uid, prompt, AiFeature.CHAT)
    except Exception as exc:
        logger.warning("ziku ask failed: %s", exc)
        raise CommunityError(502, "Ziku could not answer right now")
    return {"groupId": group_id, "question": question, "answer": _text(answer).strip()[:6000]}


async def ziku_moderate(
    uid: str,
    group_id: str,
    claim_a: str,
    claim_b: str,
    context: str = "",
) -> dict[str, Any]:
    group = _require_group_member(group_id, uid)
    claim_a = _text(claim_a).strip()
    claim_b = _text(claim_b).strip()
    if not claim_a or not claim_b:
        raise CommunityError(400, "Give both sides of the disagreement")
    prompt = (
        "You are Ziku, the AI moderator of a student study group. Two "
        "students disagree about an academic answer. Analyse both sides "
        "fairly. IMPORTANT: start your reply with exactly "
        '"Let\'s analyze both solutions..."' ", then explain each side, then "
        "give the correct conclusion with a short reason.\n\n"
        f"GROUP CONTEXT:\n{_group_context(group_id, group)}\n\n"
        f"STUDENT A SAYS: {claim_a[:1500]}\n"
        f"STUDENT B SAYS: {claim_b[:1500]}\n"
        f"EXTRA CONTEXT: {_text(context)[:1000]}\n"
    )
    try:
        analysis = await _ai(uid, prompt, AiFeature.CHAT)
    except Exception as exc:
        logger.warning("ziku moderate failed: %s", exc)
        raise CommunityError(502, "Ziku could not analyse that right now")
    return {
        "groupId": group_id,
        "claimA": claim_a,
        "claimB": claim_b,
        "analysis": _text(analysis).strip()[:8000],
    }


def _rule_topics(insights: dict[str, Any]) -> list[dict[str, str]]:
    topics: list[dict[str, str]] = []
    for weak in insights.get("weakTopics") or []:
        topics.append(
            {
                "title": f"Revise {weak['topic']}",
                "reason": f"Group quiz accuracy is {weak['accuracy']}% here.",
            }
        )
    for hot in insights.get("hotChapters") or []:
        topics.append(
            {
                "title": f"Discuss {hot['chapter']}",
                "reason": f"{hot['count']} student question(s) this week.",
            }
        )
    if not topics:
        topics.append(
            {
                "title": "Set up a weekly revision plan",
                "reason": "No strong signal yet - start with the syllabus.",
            }
        )
    return topics[:5]


async def ziku_topics(uid: str, group_id: str) -> dict[str, Any]:
    group = _require_group_member(group_id, uid)
    insights = group_insights_data(group_id)
    fallback = _rule_topics(insights)
    prompt = (
        "You are Ziku, the AI moderator of a student study group. Suggest "
        "3 to 5 academic discussion topics for this group based on the "
        "signal below. Return ONLY JSON: "
        '{"topics": [{"title": "...", "reason": "..."}]}\n\n'
        f"GROUP: {_text(group.get('name'))}\n"
        f"HOT CHAPTERS: {json.dumps(insights.get('hotChapters') or [])}\n"
        f"WEAK TOPICS: {json.dumps(insights.get('weakTopics') or [])}\n"
        f"OPEN QUESTIONS: {insights.get('questionCount', 0)}\n"
    )
    source = "rule"
    topics = fallback
    try:
        parsed = _parse_json(await _ai(uid, prompt, AiFeature.CHAT))
        raw_topics = parsed.get("topics")
        if isinstance(raw_topics, list) and raw_topics:
            cleaned = [
                {
                    "title": _text(t.get("title")),
                    "reason": _text(t.get("reason")),
                }
                for t in raw_topics
                if isinstance(t, dict) and _text(t.get("title"))
            ]
            if cleaned:
                topics = cleaned[:5]
                source = "ai"
    except Exception as exc:
        logger.info("ziku topics falling back to rules (%s)", exc)
    return {"groupId": group_id, "topics": topics, "source": source}


async def group_quiz(
    uid: str,
    display_name: str,
    group_id: str,
    *,
    topic: str = "",
    question_count: int = 5,
) -> dict[str, Any]:
    """Spec 7.1/7.2 — Ziku generates a group quiz through the existing
    QUIZ quota and activity counters (``quiz_generate``), with the group's
    weak topics and the caller's Mistake Memory priorities as the source.
    """
    from app.core.auth import CurrentUser
    from app.routers.ai_study import QuizGenerateRequest, quiz_generate

    group = _require_group_member(group_id, uid)
    insights = group_insights_data(group_id)
    priority = mistake_memory.get_priority_topics(uid, 3)
    priority_topics = [_text(p.get("topic")) for p in priority if _text(p.get("topic"))]

    chosen = _text(topic).strip()
    if not chosen and insights["weakTopics"]:
        chosen = _text(insights["weakTopics"][0].get("topic"))
    if not chosen and insights["hotChapters"]:
        chosen = _text(insights["hotChapters"][0].get("chapter"))
    if not chosen and priority_topics:
        chosen = priority_topics[0]

    lines = [f"Group: {_text(group.get('name'))}"]
    if chosen:
        lines.append(f"Focus topic: {chosen}")
    if priority_topics:
        lines.append(
            "The student's own mistake-memory priorities: "
            + ", ".join(priority_topics)
        )
    for hot in insights["hotChapters"]:
        lines.append(f"Hot chapter: {hot['chapter']} ({hot['subject']}, {hot['count']} Qs)")
    questions_preview = [
        _text(q.get("title"))[:120] for q in _group_questions(group_id, limit=8)
    ]
    if questions_preview:
        lines.append("Recent group questions: " + " | ".join(questions_preview))
    source = "\n".join(lines)[:5000]

    count = max(1, min(_int(question_count, 5), 10))
    user = CurrentUser(uid=uid, email="", role="student", display_name=display_name)
    result = await quiz_generate(
        QuizGenerateRequest(source=source, topic=chosen, question_count=count),
        user,
    )
    quiz = result.get("quiz") or []
    if not quiz:
        return {
            "quizId": "",
            "questions": [],
            "topic": chosen,
            "error": "Ziku could not generate a quiz right now",
        }

    now = _now()
    questions = []
    for i, raw in enumerate(quiz):
        if not isinstance(raw, dict):
            continue
        text = _text(raw.get("question") or raw.get("text"))
        if not text:
            continue
        questions.append(
            {
                "index": i,
                "question": text[:2000],
                "type": _text(raw.get("type")) or "mcq",
                "options": [str(o) for o in (raw.get("options") or [])][:8],
                "correct": _text(raw.get("correct") or raw.get("answer")),
                "explanation": _text(raw.get("explanation"))[:1000],
                "topic": _text(raw.get("topic")) or chosen or "General",
            }
        )
    if not questions:
        return {
            "quizId": "",
            "questions": [],
            "topic": chosen,
            "error": "Ziku could not generate a quiz right now",
        }

    ref = (
        _db()
        .collection(GROUPS)
        .document(group_id)
        .collection(QUIZZES)
        .document()
    )
    title = f"{chosen or 'Group'} revision quiz"
    ref.set(
        {
            "title": title,
            "topic": chosen,
            "subject": _text(group.get("subject")) or _text(chosen),
            "questions": questions,
            "createdBy": uid,
            "createdByName": _text(display_name),
            "attemptCount": 0,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "createdAtIso": _iso(now),
        }
    )
    _award_points(uid, display_name, "quiz_created", group_id=group_id)
    from app.services.analytics_service import track_event

    track_event(uid, "group_quiz_created", {"topic": chosen, "source": "community_group"})
    reason = (
        f"Many students in your {_text(group.get('name'))} group struggled "
        f"with {chosen or 'the course so far'}. Ziku created a revision quiz."
    )
    return {
        "quizId": ref.id,
        "title": title,
        "topic": chosen,
        "reason": reason,
        "groupId": group_id,
        "questions": [
            {
                "index": q["index"],
                "question": q["question"],
                "type": q["type"],
                "options": q["options"],
                "topic": q["topic"],
            }
            for q in questions
        ],
    }


def list_group_quizzes(group_id: str, uid: str) -> dict[str, Any]:
    _require_group_member(group_id, uid)
    rows = []
    for snap in (
        _db().collection(GROUPS).document(group_id).collection(QUIZZES).stream()
    ):
        data = snap.to_dict() or {}
        rows.append(
            {
                "id": snap.id,
                "title": _text(data.get("title")),
                "topic": _text(data.get("topic")),
                "createdByName": _text(data.get("createdByName")),
                "questionCount": len(data.get("questions") or []),
                "attemptCount": _int(data.get("attemptCount")),
                "createdAtIso": _text(data.get("createdAtIso")),
            }
        )
    rows.sort(key=lambda r: r["createdAtIso"], reverse=True)
    return {"groupId": group_id, "quizzes": rows}


def _quiz_ref(group_id: str, quiz_id: str):
    return _db().collection(GROUPS).document(group_id).collection(QUIZZES).document(quiz_id)


def get_group_quiz(group_id: str, quiz_id: str, uid: str) -> dict[str, Any]:
    _require_group_member(group_id, uid)
    snap = _quiz_ref(group_id, quiz_id).get()
    if not snap.exists:
        raise CommunityError(404, "Quiz not found")
    data = snap.to_dict() or {}
    return {
        "id": snap.id,
        "groupId": group_id,
        "title": _text(data.get("title")),
        "topic": _text(data.get("topic")),
        "createdByName": _text(data.get("createdByName")),
        "attemptCount": _int(data.get("attemptCount")),
        "createdAtIso": _text(data.get("createdAtIso")),
        # Redacted — the answer key never leaves the backend before submit.
        "questions": [
            {
                "index": _int(q.get("index"), i),
                "question": _text(q.get("question")),
                "type": _text(q.get("type")) or "mcq",
                "options": list(q.get("options") or []),
                "topic": _text(q.get("topic")),
            }
            for i, q in enumerate(data.get("questions") or [])
        ],
    }


async def attempt_group_quiz(
    group_id: str,
    quiz_id: str,
    uid: str,
    display_name: str,
    answers: Any,
    duration_seconds: int = 0,
) -> dict[str, Any]:
    _require_group_member(group_id, uid)
    ref = _quiz_ref(group_id, quiz_id)
    snap = ref.get()
    if not snap.exists:
        raise CommunityError(404, "Quiz not found")
    data = snap.to_dict() or {}
    questions = list(data.get("questions") or [])
    if not questions:
        raise CommunityError(400, "This quiz has no questions")

    graded = _grade_answers(questions, answers)
    now = _now()
    attempt_ref = ref.collection(ATTEMPTS).document()
    attempt_ref.set(
        {
            "uid": uid,
            "displayName": _text(display_name),
            "answers": list(answers) if isinstance(answers, list) else [],
            "correctFlags": graded["correctFlags"],
            "score": graded["score"],
            "total": graded["total"],
            "accuracy": graded["accuracy"],
            "topicScores": graded["topicScores"],
            "durationSeconds": max(0, _int(duration_seconds)),
            "completedAt": _iso(now),
        }
    )
    ref.set(
        {"attemptCount": _int(data.get("attemptCount")) + 1},
        merge=True,
    )
    return {
        "quizId": quiz_id,
        "attemptId": attempt_ref.id,
        "score": graded["score"],
        "total": graded["total"],
        "accuracy": graded["accuracy"],
        "topicScores": graded["topicScores"],
        "correctFlags": graded["correctFlags"],
        "explanations": [
            _text(q.get("explanation")) if graded["correctFlags"][i] else ""
            for i, q in enumerate(questions)
        ],
    }
