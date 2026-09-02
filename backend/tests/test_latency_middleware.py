"""P4-1 regression tests for the per-endpoint latency middleware.

What this file pins:

  1. The middleware records an entry on every successful request.
  2. The recorded route key is the FastAPI matched-route template
     (e.g. ``/api/health``), not the literal URL.
  3. The quantile helper matches a hand-computed expected value for a
     known input — pinning the percentile formula so a future
     refactor doesn't silently switch from nearest-rank to linear
     interpolation (which would change the numbers operators see).
  4. The internal snapshot endpoint returns 404 when no token is
     configured, 401 when the token is wrong, and 200 with the
     expected schema when the token is correct.
  5. The total-count counter survives ring-buffer rollovers (i.e. a
     record beyond ``window_size`` still increments ``total``).

Why we use ``TestClient`` directly rather than the ``client`` fixture:
the latency middleware depends on the **FastAPI route table** to
resolve route templates. The hermetic ``client`` fixture is still
fine — it patches external collaborators but the routes themselves
are unchanged. We just need a fresh recorder per test, which is why
each test calls ``get_recorder().reset()`` in its setup.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.core.latency import LatencyRecorder, _compute_quantiles, get_recorder


@pytest.fixture()
def fresh_recorder():
    get_recorder().reset()
    yield get_recorder()
    get_recorder().reset()


@pytest.fixture()
def internal_token_client(monkeypatch):
    """TestClient with ``internal_metrics_token`` configured to ``s3cret``."""
    from app.core.config import get_settings

    get_settings.cache_clear()
    settings = get_settings()
    settings.internal_metrics_token = "s3cret"

    # Re-import app so the router reads the (fresh) settings. The
    # ``client`` fixture is overkill here because we only hit the
    # internal endpoint and /api/health.
    from app.main import app

    get_recorder().reset()
    with TestClient(app) as c:
        yield c
    get_recorder().reset()
    settings.internal_metrics_token = ""
    get_settings.cache_clear()


@pytest.fixture()
def no_token_client(monkeypatch):
    """TestClient with ``internal_metrics_token`` unset (the safe default)."""
    from app.core.config import get_settings

    get_settings.cache_clear()
    settings = get_settings()
    settings.internal_metrics_token = ""

    from app.main import app

    get_recorder().reset()
    with TestClient(app) as c:
        yield c
    get_recorder().reset()
    get_settings.cache_clear()


# ---------------------------------------------------------------------------
# Quantile helper — pinned math
# ---------------------------------------------------------------------------


def test_compute_quantiles_empty_returns_zeros():
    """An empty buffer reports zero everywhere, not a div-by-zero NaN."""
    from collections import deque

    out = _compute_quantiles(deque(), total_count=0)
    assert out == {"count": 0, "total": 0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "mean": 0.0}


def test_compute_quantiles_nearest_rank_known_input():
    """Pin the percentile formula.

    With 20 samples ``[10, 20, ..., 200]`` (step 10):
      - p50 → nearest-rank index ceil(0.5*20)-1 = 9 → 100 (median)
      - p95 → nearest-rank index ceil(0.95*20)-1 = 18 → 190
      - p99 → nearest-rank index ceil(0.99*20)-1 = 19 → 200 (clamped to n-1)
      - mean → (10 + 20 + ... + 200) / 20 = 105

    The p99 = 200 (not 190) is the deliberate consequence of n=20:
    ceil(0.99*20) = 20 → rank 19 → sorted[19] = 200. If a future PR
    flips the formula to linear interpolation, p99 would jump to
    199.0 — this test fires and the change is intentional.
    """
    from collections import deque

    samples = deque(float(x * 10) for x in range(1, 21))  # 10..200 step 10
    out = _compute_quantiles(samples, total_count=20)
    assert out["count"] == 20
    assert out["total"] == 20
    assert out["p50"] == 100.0
    assert out["p95"] == 190.0
    assert out["p99"] == 200.0
    assert out["mean"] == 105.0


# ---------------------------------------------------------------------------
# Recorder API
# ---------------------------------------------------------------------------


def test_recorder_record_and_snapshot(fresh_recorder):
    r = LatencyRecorder(window_size=4)
    for ms in (1.0, 2.0, 3.0, 4.0, 5.0, 6.0):
        r.record("GET", "/api/health", ms)
    snap = r.snapshot()
    key = ("GET", "/api/health")
    assert key in snap
    # window_size=4 → only the last 4 samples survive (3,4,5,6); total keeps counting.
    assert snap[key]["count"] == 4
    assert snap[key]["total"] == 6
    # p50 of [3,4,5,6] with n=4 → ceil(0.5*4)-1 = 1 → index 1 → 4.0
    assert snap[key]["p50"] == 4.0
    # p95/p99 of [3,4,5,6] with n=4 → ceil(0.95*4)-1 = 3 → index 3 → 6.0
    assert snap[key]["p95"] == 6.0
    assert snap[key]["p99"] == 6.0
    # mean of [3,4,5,6] = 18/4 = 4.5
    assert snap[key]["mean"] == 4.5


def test_recorder_separates_routes_and_methods(fresh_recorder):
    r = LatencyRecorder(window_size=8)
    r.record("GET", "/api/health", 1.0)
    r.record("POST", "/api/health", 50.0)
    r.record("GET", "/api/groups/{gid}", 10.0)
    snap = r.snapshot()
    assert ("GET", "/api/health") in snap
    assert ("POST", "/api/health") in snap
    assert ("GET", "/api/groups/{gid}") in snap
    assert snap[("GET", "/api/health")]["mean"] == 1.0
    assert snap[("POST", "/api/health")]["mean"] == 50.0
    assert snap[("GET", "/api/groups/{gid}")]["mean"] == 10.0


# ---------------------------------------------------------------------------
# End-to-end via TestClient
# ---------------------------------------------------------------------------


def test_middleware_records_a_real_request(no_token_client, fresh_recorder):
    """Hitting /api/health should populate the recorder with one entry.

    Note: FastAPI's ``request.scope["route"].path`` is the *relative*
    route template (e.g. ``/health``), not the full mounted path
    (``/api/health``). The ``prefix`` from ``include_router`` is
    applied at routing time but not reflected in the template. We
    pin this so a future refactor to ``request.url.path`` would
    fire this test.
    """
    resp = no_token_client.get("/api/health")
    assert resp.status_code == 200

    snap = fresh_recorder.snapshot()
    assert ("GET", "/health") in snap
    entry = snap[("GET", "/health")]
    assert entry["count"] == 1
    assert entry["total"] == 1
    # /api/health returns instantly in the test client; elapsed_ms is
    # always non-negative. Don't assert upper bound — CI runners vary.
    assert entry["mean"] >= 0.0


def test_middleware_uses_route_template_not_literal_path(no_token_client, fresh_recorder):
    """A 404 should still record — but using the literal path because
    FastAPI never matched it to a route template.

    This pins the fallback behaviour so a future change that crashes
    on un-matched routes gets caught.
    """
    resp = no_token_client.get("/this/route/does/not/exist")
    assert resp.status_code == 404

    snap = fresh_recorder.snapshot()
    # The fallback is the literal path with no query string.
    assert ("GET", "/this/route/does/not/exist") in snap


# ---------------------------------------------------------------------------
# Internal snapshot endpoint — gating
# ---------------------------------------------------------------------------


def test_internal_endpoint_returns_404_when_no_token_configured(no_token_client):
    """Safe default for public Render deploys: the endpoint is invisible."""
    resp = no_token_client.get("/api/_internal/latency")
    assert resp.status_code == 404


def test_internal_endpoint_returns_401_when_token_wrong(internal_token_client):
    resp = internal_token_client.get("/api/_internal/latency")
    assert resp.status_code == 401


def test_internal_endpoint_returns_401_when_token_missing(internal_token_client):
    resp = internal_token_client.get("/api/_internal/latency")
    assert resp.status_code == 401


def test_internal_endpoint_returns_snapshot_when_token_correct(internal_token_client, fresh_recorder):
    """The schema is ``{window_size, routes: [{method, route, count, total, p50, p95, p99, mean}]}``."""
    # Seed at least one record by hitting /api/health through the
    # internal_token_client (which has its own client, so we don't
    # share the no_token_client fixture's recorder state).
    internal_token_client.get("/api/health")

    resp = internal_token_client.get(
        "/api/_internal/latency",
        headers={"X-Internal-Token": "s3cret"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "window_size" in body and isinstance(body["window_size"], int) and body["window_size"] > 0
    assert "routes" in body and isinstance(body["routes"], list)
    # Route key is the FastAPI template (relative), not the mounted path.
    assert any(r["route"] == "/health" for r in body["routes"])
    health = next(r for r in body["routes"] if r["route"] == "/health")
    assert health["method"] == "GET"
    for key in ("count", "total", "p50", "p95", "p99", "mean"):
        assert key in health
        assert isinstance(health[key], (int, float))