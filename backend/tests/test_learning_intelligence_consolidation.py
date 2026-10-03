"""Phase 12.2.4 — Learning Intelligence Consolidation Test Suite.

Verifies:
1. Canonical concept mastery in learning_memory_service (bounded 0.0 - 1.0).
2. Deterministic weak topic identification without contradictions.
3. Legacy adapter compatibility (weak_topic_service.get_weak_topics & get_learning_summary).
4. Consumer alignment (study_coach, ziku_adaptive, ziku_tutor, content_recommendation).
5. Non-destructive reads (zero alteration of historical Firestore records).
6. Privacy protection (no raw question bodies, transcripts, or notes leaked in mastery records).
7. Strict cross-user isolation.
8. Graceful degradation on empty memory.
9. Acyclic module dependency graph (no circular imports).
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone
from typing import Any


def _seed_subcol(db: Any, uid: str, subcol: str, doc_id: str, data: dict[str, Any]) -> None:
    db.collection("users").document(uid).collection(subcol).document(doc_id).set(data)


def test_acyclic_import_dependency_graph():
    """Verify clean import of all learning intelligence services without circular dependencies."""
    import subprocess
    cmd = [
        sys.executable,
        "-c",
        "import app.services.academic_health_service; "
        "import app.services.content_recommendation_service; "
        "import app.services.learning_memory_service; "
        "import app.services.study_coach_service; "
        "import app.services.weak_topic_service; "
        "import app.services.ziku_adaptive_service; "
        "import app.services.ziku_tutor_service; "
        "print('SUCCESS')"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "SUCCESS" in result.stdout


def test_canonical_mastery_bounded_zero_to_one(client, fake_db):
    """Canonical mastery and confidence must be strictly bounded in [0.0, 1.0]."""
    from app.services import learning_memory_service as memory

    uid = "student-bounded-mastery"
    now_iso = datetime.now(timezone.utc).isoformat()

    # Seed varied quiz results
    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "subjectId": "Physics",
            "score": 40,
            "topicScores": {"Thermodynamics": 30, "Optics": 95},
        },
    )
    # Seed mistakes
    _seed_subcol(
        fake_db, uid, "mistakes", "m1",
        {
            "createdAt": now_iso,
            "subject": "Physics",
            "topic": "Thermodynamics",
            "occurrences": 3,
            "reviewCount": 1,
            "analysis": {"conceptGap": "Carnot Cycle"},
        },
    )

    all_topics = memory.get_all_topics_mastery(uid, db=fake_db)
    assert len(all_topics) == 2

    for item in all_topics:
        mastery = item["mastery"]
        confidence = item["confidence"]
        assert isinstance(mastery, float)
        assert 0.0 <= mastery <= 1.0, f"Mastery {mastery} out of bounds"
        assert isinstance(confidence, float)
        assert 0.0 <= confidence <= 1.0, f"Confidence {confidence} out of bounds"
        assert item["evidenceCount"] >= 1
        assert "signals" in item
        assert "trend" in item["signals"]

    # Check specific topic values
    thermo = memory.get_topic_mastery(uid, "Thermodynamics", db=fake_db)
    assert thermo["mastery"] < 0.60
    assert thermo["isWeak"] is True
    assert thermo["signals"]["quizAccuracy"] == 30.0

    optics = memory.get_topic_mastery(uid, "Optics", db=fake_db)
    assert optics["mastery"] > 0.80
    assert optics["isWeak"] is False
    assert optics["signals"]["quizAccuracy"] == 95.0


def test_weak_topics_detection_deterministic(client, fake_db):
    """Verify weak topics are identified deterministically without contradiction."""
    from app.services import learning_memory_service as memory

    uid = "student-weak-detection"
    now_iso = datetime.now(timezone.utc).isoformat()

    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "subjectId": "Math",
            "score": 50,
            "topicScores": {
                "Integration": 45,
                "Differentiation": 88,
                "Vectors": 52,
            },
        },
    )

    weak = memory.get_weak_topics(uid, threshold=0.60, db=fake_db)
    weak_topic_names = [w["topic"] for w in weak]

    assert "Integration" in weak_topic_names
    assert "Vectors" in weak_topic_names
    assert "Differentiation" not in weak_topic_names

    # Integration must be ranked weaker than Vectors (45 < 52)
    assert weak_topic_names.index("Integration") < weak_topic_names.index("Vectors")


def test_weak_topic_service_adapter_compatibility(client, fake_db):
    """weak_topic_service.get_weak_topics returns legacy dict format."""
    from app.services import weak_topic_service

    uid = "student-adapter-compat"
    now_iso = datetime.now(timezone.utc).isoformat()

    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "subjectId": "Chemistry",
            "score": 40,
            "topicScores": {"Organic Synthesis": 35, "Periodic Table": 90},
        },
    )

    legacy_weak = weak_topic_service.get_weak_topics(uid, threshold=60)
    assert len(legacy_weak) == 1
    item = legacy_weak[0]

    # Required legacy fields
    assert item["topic"] == "Organic Synthesis"
    assert item["average_score"] == 35
    assert item["attempts"] == 1
    assert "recommendation" in item
    assert isinstance(item["recommendation"], str)

    # Canonical fields present without breaking legacy consumers
    assert "mastery" in item
    assert "confidence" in item
    assert "signals" in item


def test_learning_summary_adapter_compatibility(client, fake_db):
    """weak_topic_service.get_learning_summary returns legacy schema with correct totals."""
    from app.services import weak_topic_service

    uid = "student-summary-compat"
    now_iso = datetime.now(timezone.utc).isoformat()

    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "score": 60,
            "topicScores": {"Kinematics": 80, "Dynamics": 40},
        },
    )

    summary = weak_topic_service.get_learning_summary(uid)
    assert summary["total_quizzes"] == 1
    assert summary["average_score"] == 60
    assert summary["total_topics"] == 2
    assert len(summary["strong_topics"]) == 1
    assert summary["strong_topics"][0]["topic"] == "Kinematics"
    assert len(summary["weak_topics"]) == 1
    assert summary["weak_topics"][0]["topic"] == "Dynamics"


def test_study_coach_uses_canonical_mastery(client, fake_db):
    """Study Coach profile weakTopics and strongTopics match canonical intelligence."""
    from app.services import study_coach_service as coach

    uid = "student-coach-canonical"
    now_iso = datetime.now(timezone.utc).isoformat()
    fake_db.seed("users", uid, {"displayName": "Test Student", "role": "student"})

    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "score": 55,
            "topicScores": {"Linear Algebra": 85, "Calculus": 40},
        },
    )

    profile = coach.build_learning_profile(uid, force=True)
    strong_names = [t["topic"] for t in profile.get("strongTopics", [])]

    assert "Linear Algebra" in strong_names
    # Calculus is weak (< 60)
    assert any(t["topic"] == "Calculus" for t in profile.get("weakTopics", [])) or "Calculus" in [
        t["topic"] for t in profile.get("strongTopics", []) if False
    ]


def test_adaptive_learning_uses_canonical_mastery(client, fake_db):
    """ziku_adaptive_service._topic_scores reflects canonical topic mastery."""
    from app.services import ziku_adaptive_service as adaptive

    uid = "student-adaptive-canonical"
    now_iso = datetime.now(timezone.utc).isoformat()

    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "score": 70,
            "topicScores": {"Electrostatics": 72.0},
        },
    )

    scores = adaptive._topic_scores(uid)
    assert "Electrostatics" in scores
    assert scores["Electrostatics"] == 72.0


def test_tutor_adaptation_uses_canonical_mastery(client, fake_db):
    """ziku_tutor_service._gather_student_adaptation sets beginner/advanced using canonical mastery."""
    from app.services import ziku_tutor_service as tutor

    uid = "student-tutor-canonical"
    now_iso = datetime.now(timezone.utc).isoformat()

    # Topic A: weak
    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "score": 35,
            "topicScores": {"Quantum Physics": 35},
        },
    )
    # Topic B: advanced
    _seed_subcol(
        fake_db, uid, "quiz_results", "q2",
        {
            "createdAt": now_iso,
            "score": 90,
            "topicScores": {"Classical Mechanics": 90},
        },
    )

    weak_adapt = tutor._gather_student_adaptation(uid, "Physics", "Quantum Physics")
    assert weak_adapt["level"] == "beginner"
    assert weak_adapt["isWeakTopic"] is True

    adv_adapt = tutor._gather_student_adaptation(uid, "Physics", "Classical Mechanics")
    assert adv_adapt["level"] == "advanced"
    assert adv_adapt["isWeakTopic"] is False


def test_content_recommendations_consistency(client, fake_db):
    """content_recommendation_service generates recommendations consistent with canonical memory."""
    from app.services import content_recommendation_service as content_rec

    uid = "student-content-rec"
    now_iso = datetime.now(timezone.utc).isoformat()

    _seed_subcol(
        fake_db, uid, "quiz_results", "q1",
        {
            "createdAt": now_iso,
            "score": 45,
            "topicScores": {"Genetics": 45},
        },
    )

    recs = content_rec.get_recommendations(uid)
    assert recs["studentId"] == uid
    assert isinstance(recs["items"], list)
    assert len(recs["items"]) >= 1


def test_non_destructive_legacy_resolution(client, fake_db):
    """Mastery derivation never mutates, overwrites, or deletes raw historical quiz or mistake docs."""
    from app.services import learning_memory_service as memory

    uid = "student-non-destructive"
    now_iso = datetime.now(timezone.utc).isoformat()

    quiz_doc = {
        "createdAt": now_iso,
        "score": 50,
        "subjectId": "Physics",
        "topicScores": {"Wave Optics": 50},
        "user_answers": ["A", "B"],
        "correct_answers": ["C", "B"],
    }
    _seed_subcol(fake_db, uid, "quiz_results", "quiz_orig", dict(quiz_doc))

    # Derive mastery multiple times
    for _ in range(3):
        _ = memory.get_all_topics_mastery(uid, db=fake_db)
        _ = memory.get_weak_topics(uid, db=fake_db)
        _ = memory.get_topic_mastery(uid, "Wave Optics", db=fake_db)

    # Inspect stored raw quiz document
    stored = fake_db.collection("users").document(uid).collection("quiz_results").document("quiz_orig").get().to_dict()
    assert stored["score"] == 50
    assert stored["topicScores"] == {"Wave Optics": 50}
    assert stored["user_answers"] == ["A", "B"]


def test_privacy_leak_protection(client, fake_db):
    """Mastery records must NEVER contain raw question bodies, transcripts, or private notes."""
    from app.services import learning_memory_service as memory

    uid = "student-privacy-check"
    now_iso = datetime.now(timezone.utc).isoformat()

    secret_question = "What is the secret equation that must not leak?"
    secret_note = "Private diary: I struggled with question 4 on thermodynamics."

    _seed_subcol(
        fake_db, uid, "quiz_results", "q_leak",
        {
            "createdAt": now_iso,
            "score": 40,
            "topicScores": {"Nuclear Physics": 40},
            "questions": [{"question": secret_question}],
            "notes": secret_note,
        },
    )
    _seed_subcol(
        fake_db, uid, "mistakes", "m_leak",
        {
            "createdAt": now_iso,
            "topic": "Nuclear Physics",
            "questionText": secret_question,
            "privateStudentNote": secret_note,
            "analysis": {"conceptGap": "Binding Energy"},
        },
    )

    mastery_item = memory.get_topic_mastery(uid, "Nuclear Physics", db=fake_db)
    mastery_str = str(mastery_item)

    assert secret_question not in mastery_str
    assert secret_note not in mastery_str
    assert "questionText" not in mastery_item
    assert "privateStudentNote" not in mastery_item
    assert "questions" not in mastery_item
    assert "notes" not in mastery_item


def test_cross_user_isolation(client, fake_db):
    """User A's scores and mistakes must never influence User B's mastery records."""
    from app.services import learning_memory_service as memory

    user_a = "user-alice"
    user_b = "user-bob"
    now_iso = datetime.now(timezone.utc).isoformat()

    # User A is weak in Astronomy
    _seed_subcol(
        fake_db, user_a, "quiz_results", "qa",
        {
            "createdAt": now_iso,
            "topicScores": {"Astronomy": 20},
        },
    )

    # User B is strong in Astronomy
    _seed_subcol(
        fake_db, user_b, "quiz_results", "qb",
        {
            "createdAt": now_iso,
            "topicScores": {"Astronomy": 98},
        },
    )

    mastery_a = memory.get_topic_mastery(user_a, "Astronomy", db=fake_db)
    mastery_b = memory.get_topic_mastery(user_b, "Astronomy", db=fake_db)

    assert mastery_a["mastery"] < 0.30
    assert mastery_a["isWeak"] is True

    assert mastery_b["mastery"] > 0.90
    assert mastery_b["isWeak"] is False


def test_empty_memory_graceful_degradation(client, fake_db):
    """When student has 0 quiz results and 0 mistakes, returns clean defaults without throwing."""
    from app.services import learning_memory_service as memory
    from app.services import weak_topic_service

    uid = "student-empty-fresh"

    # 1. learning_memory_service APIs
    topic = memory.get_topic_mastery(uid, "Anything", db=fake_db)
    assert topic["topic"] == "Anything"
    assert topic["mastery"] == 0.50
    assert topic["confidence"] == 0.0
    assert topic["evidenceCount"] == 0
    assert topic["isWeak"] is False

    weak = memory.get_weak_topics(uid, db=fake_db)
    assert weak == []

    all_t = memory.get_all_topics_mastery(uid, db=fake_db)
    assert all_t == []

    subj = memory.get_subject_mastery(uid, "Physics", db=fake_db)
    assert subj["subject"] == "Physics"
    assert subj["totalTopics"] == 0
    assert subj["mastery"] == 0.50

    # 2. weak_topic_service legacy adapter
    legacy_weak = weak_topic_service.get_weak_topics(uid)
    assert legacy_weak == []

    summary = weak_topic_service.get_learning_summary(uid)
    assert summary["total_quizzes"] == 0
    assert summary["average_score"] == 0
    assert summary["total_topics"] == 0
    assert summary["strong_topics"] == []
    assert summary["weak_topics"] == []
