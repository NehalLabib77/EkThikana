"""Phase 11 - community intelligence adapter.

The existing community service remains the source of truth for posts, groups,
answers, challenges and points. This module connects those records to Ziku's
existing learning memory and adaptive/content signals.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import community_service as community
from app.services import learning_memory_service as memory

INSIGHTS_COLLECTION = "group_insights"


def _text(value: Any) -> str:
    return str(value or "").strip()


def _tokens(value: str) -> set[str]:
    return {word for word in _text(value).lower().replace("?", " ").split() if len(word) >= 4}


def _similar_posts(posts: list[dict[str, Any]], query: str, limit: int = 3) -> list[dict[str, Any]]:
    wanted = _tokens(query)
    scored = []
    for post in posts:
        overlap = len(wanted & _tokens(f"{post.get('title')} {post.get('body')} {post.get('chapter')}"))
        if overlap:
            scored.append((overlap, post))
    scored.sort(key=lambda item: -item[0])
    return [post for _, post in scored[:limit]]


def feed(uid: str, *, kind: str = "", category: str = "", limit: int = 30) -> dict[str, Any]:
    result = community.list_posts(kind=kind, category=category, limit=limit, uid=uid)
    posts = result.get("posts") or []
    profile = memory.build_memory(uid, persist=False).get("profile") or {}
    weak_topics = set(str(topic) for topic in (profile.get("weakestTopics") or []))
    for post in posts:
        post["relatedToYourLearning"] = bool(
            _text(post.get("chapter")) in weak_topics
            or _text(post.get("concept")) in weak_topics
        )
    return {**result, "learningContext": {"weakTopics": list(weak_topics)[:5]}}


def question_context(uid: str, question: str) -> dict[str, Any]:
    result = community.list_posts(kind="question", limit=50, uid=uid)
    related = _similar_posts(result.get("posts") or [], question)
    profile = memory.build_memory(uid, persist=False).get("profile") or {}
    weak = [str(topic) for topic in (profile.get("weakestTopics") or [])]
    related_weak = [topic for topic in weak if _tokens(topic) & _tokens(question)]
    return {
        "relatedPosts": related,
        "weakTopics": related_weak[:5] or weak[:3],
        "profile": {
            "bestContentType": profile.get("bestContentType"),
            "learningStyle": profile.get("preferredLearningStyle"),
        },
        "suggestedAction": (
            "Start with a targeted explanation, then try a group challenge."
            if related or related_weak
            else "Create a short practice question to give Ziku more evidence."
        ),
    }


def group_insights(group_id: str, uid: str) -> dict[str, Any]:
    result = community.group_insights(group_id, uid)
    result["commonStruggles"] = [
        {"topic": item.get("topic"), "reason": f"Group accuracy is {item.get('accuracy')}%"}
        for item in result.get("weakTopics") or []
    ]
    result["suggestedChallenge"] = (
        f"{result['commonStruggles'][0]['topic']} Master Challenge"
        if result["commonStruggles"]
        else "Weekly Study Challenge"
    )
    result["updatedAt"] = datetime.now(timezone.utc)
    db = get_firestore()
    if db is not None:
        try:
            db.collection(INSIGHTS_COLLECTION).document(group_id).set(result)
        except Exception:
            pass
    return result
