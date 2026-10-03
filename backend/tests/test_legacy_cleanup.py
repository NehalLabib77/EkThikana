"""Phase 12.2.5 — Legacy & Dead-Code Cleanup Verification Suite.

Verifies:
1. Isolated subprocess imports across all Phase 1-12 active and compatibility modules.
2. weak_topic_service functions as a compatibility adapter over canonical learning_memory_service.
3. storage_provider maintains valid dual-read fallback bindings to legacy_storage.
4. ai_recommendation_service functions remain accessible and functional for ai_study and academic_health.
5. FastAPI application startup (app.main:app) mounts all routers and startup banner without errors.
"""
from __future__ import annotations

import subprocess
import sys


def test_isolated_module_imports_without_circular_dependencies():
    """Verify that all core services, adapters, and routers import cleanly in a fresh process."""
    cmd = [
        sys.executable,
        "-c",
        (
            "import app.main; "
            "import app.services.weak_topic_service; "
            "import app.services.legacy_storage; "
            "import app.services.ai_recommendation_service; "
            "import app.services.storage_provider; "
            "import app.services.learning_memory_service; "
            "import app.services.dashboard_bootstrap_service; "
            "import app.services.ai_router_service; "
            "import app.services.community_intelligence_service; "
            "import app.services.pdf_service; "
            "import app.services.permission_service; "
            "print('ALL_IMPORTS_SUCCESSFUL')"
        ),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Import failed with stderr: {result.stderr}"
    assert "ALL_IMPORTS_SUCCESSFUL" in result.stdout


def test_weak_topic_service_compatibility_adapter(client, fake_db):
    """Verify weak_topic_service retains full backward-compatible signature and returns canonical schema."""
    from app.services import weak_topic_service

    uid = "student-cleanup-adapter"
    # Empty case
    empty_weak = weak_topic_service.get_weak_topics(uid)
    assert isinstance(empty_weak, list)
    assert len(empty_weak) == 0

    summary = weak_topic_service.get_learning_summary(uid)
    assert summary["total_quizzes"] == 0
    assert summary["average_score"] == 0
    assert summary["strong_topics"] == []
    assert summary["weak_topics"] == []

    # Seed quiz
    fake_db.collection("users").document(uid).collection("quiz_results").document("q1").set({
        "createdAt": "2026-10-03T00:00:00Z",
        "score": 45,
        "topicScores": {"Thermodynamics": 45, "Newtonian Mechanics": 85},
    })

    weak = weak_topic_service.get_weak_topics(uid, threshold=60)
    assert len(weak) == 1
    assert weak[0]["topic"] == "Thermodynamics"
    assert weak[0]["average_score"] == 45
    assert weak[0]["attempts"] == 1
    assert "recommendation" in weak[0]
    assert weak[0]["mastery"] == 0.45
    assert weak[0]["confidence"] > 0
    assert "signals" in weak[0]


def test_storage_provider_dual_read_fallback_intact():
    """Verify storage_provider maintains backward-compatible references to legacy_storage."""
    from app.services import legacy_storage
    from app.services import storage_provider

    # Verify storage_provider resolution and dual-provider interfaces
    assert hasattr(storage_provider, "resolve")
    assert hasattr(storage_provider, "signed_url_for")
    assert hasattr(storage_provider, "download_for")
    assert hasattr(storage_provider, "declared_provider")

    # Verify legacy_storage fallback exports
    assert hasattr(legacy_storage, "download_bytes")
    assert hasattr(legacy_storage, "signed_url")
    assert hasattr(legacy_storage, "is_configured")
    assert hasattr(legacy_storage, "exists")


def test_ai_recommendation_service_callers_intact(client, fake_db):
    """Verify ai_recommendation_service remains accessible to ai_study router and academic health."""
    from app.services import academic_health_service
    from app.services import ai_recommendation_service

    assert hasattr(ai_recommendation_service, "generate_study_recommendation")
    assert hasattr(academic_health_service, "get_recommendations")


def test_fastapi_app_initialization_and_routes(client):
    """Verify FastAPI application boots and exposes all Phase 1-12 canonical routes."""
    from app.main import app

    paths = list(app.openapi()["paths"].keys())

    # Verify key endpoints
    assert "/api/health/ping" in paths or "/api/health" in paths
    assert "/api/me" in paths
    assert "/api/student/dashboard-bootstrap" in paths
    assert "/api/tutor/start" in paths
    assert "/api/tutor/step" in paths
    assert "/api/tutor/hint" in paths
    assert "/api/ai/academic-health" in paths
    assert "/api/ai/learning/recommendations" in paths
    assert "/api/ai/learning/weak-topics" in paths
    assert "/api/coach/daily" in paths
    assert "/api/exams/history" in paths
    assert "/api/focus/today" in paths
    assert "/api/community/posts" in paths
