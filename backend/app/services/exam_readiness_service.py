"""Phase 15.6 — Exam Readiness Engine.

Deterministic, explainable readiness scoring.
AI does NOT select the numeric score. All numbers are computed here.

Formula (documented):
  readiness =
      0.35 * masteryCoverage +
      0.25 * mockExamPerformance +
      0.15 * recentPractice +
      0.15 * revisionCoverage +
      0.10 * focusConsistency

Each component: 0–100.
Missing data: neutral documented fallback (not perfect, not zero).

Readiness labels:
  85–100 → Strong
  70–84  → Good
  55–69  → Developing
  40–54  → Needs Attention
  0–39   → Critical Preparation Gap

Snapshots persisted on meaningful events only (not on every render).
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore

logger = logging.getLogger("gochano.readiness")

# ---------------------------------------------------------------------------
# Formula weights (sum to 1.0)
# ---------------------------------------------------------------------------

W_MASTERY     = 0.35
W_MOCK        = 0.25
W_PRACTICE    = 0.15
W_REVISION    = 0.15
W_FOCUS       = 0.10

# Documented neutral fallback when a component has insufficient data
NEUTRAL_FALLBACK = 50.0

# Minimum data points before a component uses real data (else neutral)
MIN_MASTERY_TOPICS   = 2
MIN_MOCK_ATTEMPTS    = 1
MIN_PRACTICE_SESSIONS = 3
MIN_REVISION_EVENTS  = 2
MIN_FOCUS_SESSIONS   = 3

# Snapshot events (write to Firestore only on these)
SNAPSHOT_EVENTS = frozenset([
    "mock_completed",
    "major_quiz_completed",
    "plan_recalculated",
    "daily_summary",
    "mastery_updated",
])


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _nowiso() -> str:
    return _now().isoformat()


def _today() -> date:
    return _now().date()


def _db():
    return get_firestore()


def _readiness_col(uid: str):
    db = _db()
    if db is None:
        return None
    return (
        db.collection("users").document(uid)
        .collection("exam_ecosystem").document("default")
        .collection("readiness_history")
    )


# ---------------------------------------------------------------------------
# Component calculators
# ---------------------------------------------------------------------------

def _calc_mastery_coverage(uid: str) -> tuple[float, float, int]:
    """
    Returns (score, coverage_fraction, topic_count).
    coverage_fraction = fraction of topics with mastery data.
    """
    try:
        from app.services.learning_memory_service import get_all_topics_mastery
        mastery_data = get_all_topics_mastery(uid)
        if isinstance(mastery_data, dict):
            topics = list(mastery_data.values())
        elif isinstance(mastery_data, list):
            topics = mastery_data
        else:
            topics = []

        if len(topics) < MIN_MASTERY_TOPICS:
            return NEUTRAL_FALLBACK, 0.0, len(topics)

        scores = []
        for t in topics:
            ms = float(t.get("masteryScore") or t.get("mastery") or 0.5)
            scores.append(ms * 100)

        avg_mastery = sum(scores) / len(scores)
        # Coverage: fraction of topics with mastery >= 60 %
        covered = sum(1 for s in scores if s >= 60)
        coverage = covered / len(scores)
        return round(avg_mastery, 1), round(coverage, 3), len(topics)
    except Exception as exc:
        logger.debug("mastery coverage failed: %s", exc)
        return NEUTRAL_FALLBACK, 0.0, 0


def _calc_mock_performance(uid: str) -> tuple[float, int]:
    """Returns (score, attempt_count)."""
    db = _db()
    if db is None:
        return NEUTRAL_FALLBACK, 0
    try:
        cutoff = (_now() - timedelta(days=30)).isoformat()
        docs = (
            db.collection("users").document(uid)
            .collection("exam_results")
            .where("createdAt", ">=", cutoff)
            .order_by("createdAt", direction="DESCENDING")
            .limit(10)
            .stream()
        )
        scores = []
        for doc in docs:
            data = doc.to_dict() or {}
            pct = data.get("percentage") or data.get("score")
            if pct is not None:
                scores.append(float(pct))

        if len(scores) < MIN_MOCK_ATTEMPTS:
            return NEUTRAL_FALLBACK, len(scores)

        # Weight more recent attempts more heavily
        weighted = sum(s * (i + 1) for i, s in enumerate(reversed(scores)))
        total_weight = sum(range(1, len(scores) + 1))
        score = weighted / total_weight
        return round(min(100.0, score), 1), len(scores)
    except Exception as exc:
        logger.debug("mock performance failed: %s", exc)
        return NEUTRAL_FALLBACK, 0


def _calc_recent_practice(uid: str) -> tuple[float, int]:
    """Practice regularity over last 7 days. Returns (score, session_count)."""
    db = _db()
    if db is None:
        return NEUTRAL_FALLBACK, 0
    try:
        cutoff = (_now() - timedelta(days=7)).isoformat()
        docs = (
            db.collection("users").document(uid)
            .collection("practice_sessions")
            .where("startedAt", ">=", cutoff)
            .where("status", "==", "completed")
            .limit(50)
            .stream()
        )
        sessions = [d.to_dict() or {} for d in docs]
        count = len(sessions)
        if count < MIN_PRACTICE_SESSIONS:
            return NEUTRAL_FALLBACK, count

        # Score = (count / 7 days) normalized to 0-100
        # 7+ sessions/week → 100
        score = min(100.0, (count / 7) * 100)

        # Adjust by quiz scores if available
        quiz_scores = []
        for s in sessions:
            outcome = s.get("outcome") or {}
            pct = outcome.get("percentage") or outcome.get("score")
            if pct is not None:
                quiz_scores.append(float(pct))

        if quiz_scores:
            avg_score = sum(quiz_scores) / len(quiz_scores)
            score = 0.60 * score + 0.40 * avg_score

        return round(score, 1), count
    except Exception as exc:
        logger.debug("recent practice failed: %s", exc)
        return NEUTRAL_FALLBACK, 0


def _calc_revision_coverage(uid: str) -> tuple[float, int]:
    """
    Fraction of due revisions that have been completed.
    Returns (score, overdue_count).
    """
    db = _db()
    if db is None:
        return NEUTRAL_FALLBACK, 0
    try:
        today_str = _today().isoformat()
        docs = (
            db.collection("users").document(uid)
            .collection("mistakes")
            .limit(200)
            .stream()
        )
        total = 0
        overdue = 0
        for doc in docs:
            data = doc.to_dict() or {}
            total += 1
            nrd = data.get("nextReviewDate")
            if nrd and str(nrd)[:10] < today_str:
                overdue += 1

        if total < MIN_REVISION_EVENTS:
            return NEUTRAL_FALLBACK, 0

        completion_rate = 1 - (overdue / total)
        score = completion_rate * 100
        return round(score, 1), overdue
    except Exception as exc:
        logger.debug("revision coverage failed: %s", exc)
        return NEUTRAL_FALLBACK, 0


def _calc_focus_consistency(uid: str) -> tuple[float, int]:
    """
    Focus session regularity over last 14 days.
    Returns (score, session_count).
    """
    db = _db()
    if db is None:
        return NEUTRAL_FALLBACK, 0
    try:
        cutoff = (_now() - timedelta(days=14)).isoformat()
        docs = (
            db.collection("users").document(uid)
            .collection("focus_sessions")
            .where("startedAt", ">=", cutoff)
            .where("completed", "==", True)
            .limit(50)
            .stream()
        )
        sessions = [d.to_dict() or {} for d in docs]
        count = len(sessions)
        if count < MIN_FOCUS_SESSIONS:
            return NEUTRAL_FALLBACK, count

        # Score: 14+ sessions in 14 days → 100
        score = min(100.0, (count / 14) * 100)
        return round(score, 1), count
    except Exception as exc:
        logger.debug("focus consistency failed: %s", exc)
        return NEUTRAL_FALLBACK, 0


# ---------------------------------------------------------------------------
# Readiness label
# ---------------------------------------------------------------------------

def _readiness_label(score: float) -> str:
    if score >= 85:
        return "Strong"
    if score >= 70:
        return "Good"
    if score >= 55:
        return "Developing"
    if score >= 40:
        return "Needs Attention"
    return "Critical Preparation Gap"


# ---------------------------------------------------------------------------
# Strong/critical topic identification
# ---------------------------------------------------------------------------

def _identify_critical_and_strong(uid: str) -> tuple[list[str], list[str]]:
    """Return (critical_topics, strong_topics) from priority + mastery data."""
    critical, strong = [], []
    try:
        from app.services.exam_priority_service import get_priority_topics
        prios = get_priority_topics(uid, limit=20)
        for p in prios:
            if p.get("priority") == "critical":
                critical.append(p.get("topic", ""))
            elif p.get("priorityScore", 0) < 45:
                strong.append(p.get("topic", ""))
    except Exception:
        pass
    return critical[:5], strong[:5]


# ---------------------------------------------------------------------------
# Trend calculation
# ---------------------------------------------------------------------------

def _readiness_trend(uid: str, current_score: float) -> float:
    """
    Return trend (positive = improving, negative = declining).
    Compares with 7-day-ago snapshot.
    """
    col = _readiness_col(uid)
    if col is None:
        return 0.0
    try:
        cutoff = (_now() - timedelta(days=7)).isoformat()
        docs = (
            col
            .where("calculatedAt", ">=", cutoff)
            .order_by("calculatedAt")
            .limit(5)
            .stream()
        )
        scores = [float((d.to_dict() or {}).get("overallReadiness", 0))
                  for d in docs]
        if not scores:
            return 0.0
        oldest = scores[0]
        return round(current_score - oldest, 1)
    except Exception:
        return 0.0


# ---------------------------------------------------------------------------
# Recommended next action (deterministic, no LLM)
# ---------------------------------------------------------------------------

def _recommended_action(
    components: dict[str, float],
    critical_topics: list[str],
    overdue_revisions: int,
) -> str:
    # Pick weakest component
    weakest_key = min(components, key=lambda k: components[k])
    if overdue_revisions > 3:
        return "Review overdue revision topics to close your spaced-repetition gap"
    if weakest_key == "masteryCoverage" and critical_topics:
        return f"Study {critical_topics[0]} — highest priority topic with low mastery"
    if weakest_key == "mockExamPerformance":
        return "Take a full mock exam to strengthen exam-condition performance"
    if weakest_key == "recentPractice":
        return "Increase daily practice — aim for at least one quiz session per day"
    if weakest_key == "revisionCoverage":
        return "Clear overdue spaced-repetition items from your revision queue"
    if weakest_key == "focusConsistency":
        return "Schedule focused study blocks using the Focus timer"
    return "Continue your current study plan — readiness is on track"


# ---------------------------------------------------------------------------
# Core readiness calculation
# ---------------------------------------------------------------------------

def calculate_readiness(uid: str) -> dict[str, Any]:
    """
    Calculate the current exam readiness score.
    All numbers are deterministic. AI does NOT select any score.
    """
    mastery_score, mastery_coverage, topic_count = _calc_mastery_coverage(uid)
    mock_score, mock_count = _calc_mock_performance(uid)
    practice_score, practice_count = _calc_recent_practice(uid)
    revision_score, overdue_count = _calc_revision_coverage(uid)
    focus_score, focus_count = _calc_focus_consistency(uid)

    components = {
        "masteryCoverage": mastery_score,
        "mockExamPerformance": mock_score,
        "recentPractice": practice_score,
        "revisionCoverage": revision_score,
        "focusConsistency": focus_score,
    }

    overall = round(
        W_MASTERY   * mastery_score  +
        W_MOCK      * mock_score     +
        W_PRACTICE  * practice_score +
        W_REVISION  * revision_score +
        W_FOCUS     * focus_score,
        1,
    )
    overall = max(0.0, min(100.0, overall))

    label = _readiness_label(overall)
    trend = _readiness_trend(uid, overall)
    critical_topics, strong_topics = _identify_critical_and_strong(uid)
    recommended = _recommended_action(components, critical_topics, overdue_count)

    # Data coverage (fraction of components with real data, not fallback)
    neutral = NEUTRAL_FALLBACK
    real_data_count = sum(1 for v in components.values() if abs(v - neutral) > 1)
    data_coverage = round(real_data_count / len(components), 2)

    return {
        "overallReadiness": overall,
        "label": label,
        "trend": trend,
        "components": components,
        "weights": {
            "masteryCoverage": W_MASTERY,
            "mockExamPerformance": W_MOCK,
            "recentPractice": W_PRACTICE,
            "revisionCoverage": W_REVISION,
            "focusConsistency": W_FOCUS,
        },
        "strongTopics": strong_topics,
        "criticalTopics": critical_topics,
        "overdueRevisions": overdue_count,
        "recommendedNextAction": recommended,
        "dataCoverage": data_coverage,
        "dataPoints": {
            "topicCount": topic_count,
            "mockAttempts": mock_count,
            "practiceSessions": practice_count,
            "focusSessions": focus_count,
        },
        "calculatedAt": _nowiso(),
    }


# ---------------------------------------------------------------------------
# Snapshot persistence
# ---------------------------------------------------------------------------

def save_readiness_snapshot(uid: str, readiness: dict[str, Any]) -> None:
    """
    Persist a readiness snapshot.
    Only call on meaningful events — NOT on every screen render.
    """
    col = _readiness_col(uid)
    if col is None:
        return
    try:
        import uuid as _uuid
        snap_id = str(_uuid.uuid4())[:12]
        col.document(snap_id).set({
            "overallReadiness": readiness["overallReadiness"],
            "label": readiness["label"],
            "components": readiness["components"],
            "dataCoverage": readiness["dataCoverage"],
            "calculatedAt": readiness["calculatedAt"],
        })
    except Exception as exc:
        logger.warning("Failed to save readiness snapshot: %s", exc)


def get_readiness_history(uid: str, *, days: int = 30) -> list[dict[str, Any]]:
    """Return readiness snapshots for trend visualization (7-day or 30-day)."""
    col = _readiness_col(uid)
    if col is None:
        return []
    try:
        cutoff = (_now() - timedelta(days=days)).isoformat()
        docs = (
            col
            .where("calculatedAt", ">=", cutoff)
            .order_by("calculatedAt")
            .limit(90)
            .stream()
        )
        return [d.to_dict() or {} for d in docs]
    except Exception as exc:
        logger.warning("get_readiness_history failed: %s", exc)
        return []
