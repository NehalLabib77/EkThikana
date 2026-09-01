"""Per-endpoint latency tracking for Gochano.

P4-1 deliverable: ships a small in-process latency recorder that the
``LatencyMiddleware`` (registered in ``app.main``) feeds on every
request. The aggregated p50 / p95 / p99 / count per route is exposed
behind ``GET /api/_internal/latency`` and gated behind a shared secret
header so it never leaks in production by accident.

Design notes
------------

- The recorder uses a bounded ring buffer (default 128 samples per route)
  so memory stays predictable regardless of traffic. ``collections.deque``
  gives us O(1) append and O(N log N) quantile computation, which is fine
  for N ≤ 128.
- Route key is ``(method, route_template)`` where the template is the
  FastAPI route's pattern (e.g. ``/api/groups/{gid}``). The template is
  derived from ``request.scope["route"].path`` if FastAPI matched the
  request to a route; otherwise we fall back to the literal path with
  query string stripped so health-check storms don't blow up the keyspace.
- The internal endpoint is opt-in. When ``settings.internal_metrics_token``
  is empty the route returns 404; this is the safe default for a public
  Render deploy. Setting the token explicitly enables the endpoint.
"""

from __future__ import annotations

import logging
import math
import os
import time
from collections import deque
from dataclasses import dataclass, field
from threading import Lock
from typing import Deque, Dict, Tuple

from fastapi import APIRouter, Header, Request
from fastapi.responses import JSONResponse

logger = logging.getLogger("gochano.latency")

# Bounded per-route sample buffer. 128 samples is enough to compute a
# meaningful p95 while keeping memory at a few KB even across thousands
# of distinct routes.
DEFAULT_WINDOW_SIZE = int(os.getenv("GOCHANO_LATENCY_WINDOW", "128"))


@dataclass
class _RouteStats:
    samples: Deque[float] = field(default_factory=lambda: deque(maxlen=DEFAULT_WINDOW_SIZE))
    total_count: int = 0

    def add(self, elapsed_ms: float) -> None:
        self.samples.append(elapsed_ms)
        self.total_count += 1


class LatencyRecorder:
    """Thread-safe, in-process per-route latency recorder."""

    def __init__(self, window_size: int = DEFAULT_WINDOW_SIZE) -> None:
        self._lock = Lock()
        self._stats: Dict[Tuple[str, str], _RouteStats] = {}
        self._window_size = window_size

    def record(self, method: str, route: str, elapsed_ms: float) -> None:
        key = (method.upper(), route)
        with self._lock:
            stats = self._stats.get(key)
            if stats is None:
                stats = _RouteStats(samples=deque(maxlen=self._window_size))
                self._stats[key] = stats
            stats.add(elapsed_ms)

    def snapshot(self) -> Dict[Tuple[str, str], Dict[str, float]]:
        with self._lock:
            return {
                key: _compute_quantiles(stats.samples, stats.total_count)
                for key, stats in self._stats.items()
            }

    def reset(self) -> None:
        """For tests."""
        with self._lock:
            self._stats.clear()


def _compute_quantiles(samples: Deque[float], total_count: int) -> Dict[str, float]:
    """Return ``count / window_count / p50 / p95 / p99 / mean`` for the buffer.

    The reported ``count`` is the *window* size (most recent N samples);
    ``total_count`` is the lifetime counter and is included as ``total``.
    This matches the contract pinned by ``tests/test_latency_middleware.py``.
    """
    if not samples:
        return {"count": 0, "total": total_count, "p50": 0.0, "p95": 0.0, "p99": 0.0, "mean": 0.0}
    sorted_samples = sorted(samples)
    n = len(sorted_samples)

    def percentile(p: float) -> float:
        # Nearest-rank percentile. n=1 → that single sample. n≥2 → use
        # ceil(p * n) - 1 as the index so p95 of 20 samples is index 18
        # rather than 19 (which would be the maximum).
        if n == 1:
            return sorted_samples[0]
        rank = max(0, min(n - 1, math.ceil(p * n) - 1))
        return sorted_samples[rank]

    return {
        "count": n,
        "total": total_count,
        "p50": percentile(0.50),
        "p95": percentile(0.95),
        "p99": percentile(0.99),
        "mean": sum(sorted_samples) / n,
    }


_recorder = LatencyRecorder()


def get_recorder() -> LatencyRecorder:
    """Return the process-wide recorder. Tests use this to reset state."""
    return _recorder


def _resolve_route_template(request: Request) -> str:
    """Pick the most useful route key for the recorder.

    FastAPI populates ``request.scope["route"].path`` with the matched
    route template (e.g. ``/api/groups/{gid}``). If no route matched —
    404 path, raw Starlette middleware — we fall back to the literal
    path, which is good enough for monitoring but never ideal.
    """
    route = request.scope.get("route")
    template = getattr(route, "path", None)
    if isinstance(template, str) and template:
        return template
    return request.url.path


async def latency_middleware(request: Request, call_next):
    """Measure wall-clock latency for every request and record it."""
    start = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        # If the downstream raised, still record the elapsed time and
        # re-raise so the FastAPI exception handler can shape the
        # response. The route template is still meaningful here.
        elapsed_ms = (time.perf_counter() - start) * 1000.0
        _recorder.record(request.method, _resolve_route_template(request), elapsed_ms)
        raise
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    _recorder.record(request.method, _resolve_route_template(request), elapsed_ms)
    # Emit a structured log line at INFO so operators can correlate
    # spikes without scraping the JSON endpoint. Skip /health so the
    # common probe doesn't drown the log.
    if _resolve_route_template(request) != "/api/health":
        logger.info(
            "route=%s method=%s status=%s elapsed_ms=%.2f",
            _resolve_route_template(request),
            request.method,
            response.status_code,
            elapsed_ms,
        )
    return response


# ---------------------------------------------------------------------------
# Internal snapshot endpoint
# ---------------------------------------------------------------------------

router = APIRouter()


@router.get("/api/_internal/latency")
async def latency_snapshot(
    request: Request,
    x_internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
) -> JSONResponse:
    """Return the current latency snapshot.

    Gated behind ``settings.internal_metrics_token``. If the token is
    unset the endpoint returns 404 — that is the safe default for a
    public Render deploy. Setting the token explicitly enables the
    endpoint; the caller must then send it as the ``X-Internal-Token``
    header.
    """
    # Imported here to avoid pulling settings into module import time.
    from app.core.config import get_settings

    expected = (get_settings().internal_metrics_token or "").strip()
    if not expected:
        return JSONResponse(status_code=404, content={"detail": "Not found"})
    if x_internal_token != expected:
        return JSONResponse(status_code=401, content={"detail": "Unauthorized"})

    snapshot = _recorder.snapshot()
    routes = [
        {
            "method": method,
            "route": route,
            **stats,
        }
        for (method, route), stats in sorted(snapshot.items())
    ]
    return JSONResponse(
        status_code=200,
        content={
            "window_size": _recorder._window_size,
            "routes": routes,
        },
    )
