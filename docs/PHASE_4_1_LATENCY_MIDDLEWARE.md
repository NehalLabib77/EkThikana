# Phase 4-1 — Per-endpoint latency middleware

**Status:** ✅ Complete
**Phase:** P4-1 (post-launch observability hardening)
**File inventory:** `backend/app/core/latency.py`, `backend/app/core/config.py`,
`backend/app/main.py`, `backend/tests/test_latency_middleware.py`, `docs/PHASE_4_1_LATENCY_MIDDLEWARE.md`

---

## 1. Why this ships

The P3-10 performance audit deferred a *per-endpoint latency histogram*
as the single most useful piece of production observability that wasn't
yet in place. The build worked, the tests passed, and the response times
were acceptable — but in production we had no way to distinguish between
"the backend is slow" and "one specific endpoint is slow". Health was
the only signal.

P4-1 closes that gap with a small in-process recorder that:

1. Measures wall-clock latency for every request.
2. Keeps a bounded ring buffer (default 128 samples) per
   `(method, route-template)` pair.
3. Aggregates each window into `count / total / p50 / p95 / p99 / mean`.
4. Exposes the snapshot behind a token-gated internal endpoint so
   on-call can `curl` it from a private monitoring host.

The middleware is shipped in-process rather than via OpenTelemetry /
Prometheus on purpose: this is a single FastAPI service, the traffic
profile is human-scale (hundreds of requests per minute, not millions),
and pulling in a collector / exporter would add infrastructure surface
area for no operational gain.

---

## 2. What ships

### 2.1 `backend/app/core/latency.py`

A new module containing:

- `_RouteStats` — a dataclass wrapping a `collections.deque(maxlen=N)`
  for the rolling window plus a lifetime `total_count`.
- `LatencyRecorder` — a thread-safe recorder (one `threading.Lock` per
  recorder; the lock is held briefly during `record()` and `snapshot()`
  only).
- `_compute_quantiles()` — computes the percentile set from a buffer
  using nearest-rank (`ceil(p * n) - 1`, clamped to `n - 1`). See
  §3.1 for why nearest-rank over linear interpolation.
- `_resolve_route_template()` — reads
  `request.scope["route"].path` and falls back to `request.url.path`.
- `latency_middleware(request, call_next)` — measures
  `time.perf_counter()` around `call_next` and records the elapsed
  time, in milliseconds, regardless of whether `call_next` raised
  (the exception is re-raised so FastAPI's exception handlers can
  shape the response).
- `get_recorder()` — a process-wide singleton; tests use `reset()` on
  it to clear state between cases.
- `router = APIRouter()` exposing `GET /api/_internal/latency`. The
  endpoint is gated by the `X-Internal-Token` request header whose
  value is compared against `settings.internal_metrics_token`.

### 2.2 `backend/app/core/config.py`

Adds one field:

```python
internal_metrics_token: str = ""
```

Default is empty, which makes the internal endpoint return **404** on
every request. This is the safe default for a public Render deploy — the
endpoint is invisible until an operator explicitly opts in by setting
the env var.

### 2.3 `backend/app/main.py`

Wires the middleware (registered after `CORSMiddleware` so CORS
handshake errors are still measured) and includes the router between
the health and `me` routers. After wiring the route count went from
15 → 16.

### 2.4 `backend/tests/test_latency_middleware.py`

Ten regression tests that pin the contract. See §4.

---

## 3. Design decisions

### 3.1 Nearest-rank percentiles, not linear interpolation

`_compute_quantiles` uses `ceil(p * n) - 1`, the nearest-rank method.
Alternatives considered:

- **Linear interpolation** (NumPy's default) — smoother at small N but
  produces numbers like `195.6ms` for p95 of 20 samples, which feels
  false-precision at a percentile granularity operators actually use.
- **scipy `stats.scoreatpercentile`** — would add a dependency for
  one helper function.

Nearest-rank with the test-suite-pinned input (`10..200 step 10`,
n=20) produces p50=100, p95=190, p99=200. The math is exact and
auditable in the test docstring; an interpolating refactor would
change p95 to 195 and p99 to 199 and the tests would fail loudly.
That is the intended behavior — breaking the operator-visible numbers
should require a deliberate test update.

### 3.2 Bounded ring buffer, not unbounded list

`collections.deque(maxlen=N)` with `N=128`. Memory is bounded
(`128 * routes * sizeof(float)` — 1KB per active route), and the
recent-sample semantics are what matters for "is X slow right now?"

Lifetime counts (`total_count`, exposed as `total` in the snapshot)
are kept separately so the API surface distinguishes "we have 128
samples; how do they look?" from "how many requests have we handled
since restart?"

### 3.3 Skip-logging `/health`

The middleware logs an INFO line for every non-health request:

```
route=/api/materials method=POST status=201 elapsed_ms=42.31
```

`/api/health` is skipped deliberately — a Kubernetes liveness probe at
5-second intervals would emit ~17,000 lines per day into the log
pipeline without telling operators anything they don't already know.

### 3.4 Internal endpoint is gated, not "internal by IP"

The typical pattern is "internal on a private network." Gochano is a
single Render service with no VPC isolation, so that doesn't apply.
Instead the endpoint requires a shared secret in the
`X-Internal-Token` header. When the secret is unset (the default), the
endpoint returns 404, matching the security invariant that "things
that aren't configured should look like they don't exist" rather
than "things that aren't configured should respond with an
unauthorized error" (the latter leaks the endpoint's existence to
unauthenticated probers).

### 3.5 Route templates as group keys, not literal paths

`request.scope["route"].path` returns the **relative template**
(`/health`), not the mounted URL (`/api/health`). The `prefix=`
argument to `include_router()` applies at routing time but is not
reflected in `scope["route"].path`.

This means the snapshot keys are *module-relative* (`/health`,
`/me`, `/groups/{gid}`, `/materials`). A future PR that switches to
`request.url.path` would change the keyspace and over-count the
`/api` prefix; the integration tests
(`test_middleware_records_a_real_request`,
`test_internal_endpoint_returns_snapshot_when_token_correct`)
pin that contract.

---

## 4. Test inventory

`backend/tests/test_latency_middleware.py` adds 10 tests:

| Test | What it pins |
|---|---|
| `test_compute_quantiles_empty_returns_zeros` | Empty buffer → no div-by-zero, all zeros. |
| `test_compute_quantiles_nearest_rank_known_input` | Exact p50/p95/p99/mean for `10..200` step-10 input. Refactors that switch to linear interp fail loudly. |
| `test_recorder_record_and_snapshot` | Rolling-window drops oldest, lifetime counter persists. |
| `test_recorder_separates_routes_and_methods` | Different `(method, route)` keys are independent. |
| `test_middleware_records_a_real_request` | End-to-end via TestClient: `/api/health` populates the recorder. |
| `test_middleware_uses_route_template_not_literal_path` | An unmatched 404 path falls back to the literal path so we don't lose the metric. |
| `test_internal_endpoint_returns_404_when_no_token_configured` | Safe default for public deploys. |
| `test_internal_endpoint_returns_401_when_token_wrong` | Wrong header value → 401. |
| `test_internal_endpoint_returns_401_when_token_missing` | No header → 401 (after the 404 gate is passed). |
| `test_internal_endpoint_returns_snapshot_when_token_correct` | Successful response has the documented schema. |

Full backend suite: **138 passed** (was 128 before P4-1; +10 new).

---

## 5. Operational notes

### 5.1 Enabling the internal endpoint on Render

Set the environment variable:

```
internal_metrics_token=<random-32-bytes>
```

Generate with `python -c "import secrets; print(secrets.token_urlsafe(32))"`.

Then from a monitoring host:

```bash
curl -H "X-Internal-Token: <token>" \
  https://<service>.onrender.com/api/_internal/latency | jq
```

The response body:

```json
{
  "window_size": 128,
  "routes": [
    {
      "method": "GET",
      "route": "/health",
      "count": 128,
      "total": 4521,
      "p50": 1.2,
      "p95": 3.8,
      "p99": 7.1,
      "mean": 1.9
    },
    ...
  ]
}
```

### 5.2 Tuning the window size

The default 128 is a tradeoff between memory and percentile
stability. For very bursty traffic (e.g. an OCR endpoint that gets
hit once per minute), raising this to 256 or 512 will produce more
stable p95 estimates:

```
GOCHANO_LATENCY_WINDOW=512
```

### 5.3 Log volume

The middleware logs ~one INFO line per non-health request. At
expected traffic (≤1 req/s sustained) that's a few thousand
entries per hour — well within Render's default log retention.

---

## 6. Deferred follow-ups

These remain on the P4 backlog; P4-1 did not address them:

- **Per-route latency histograms over time** — the snapshot is a
  point-in-time aggregation. A minimal ring buffer of recent
  snapshots (one per 10s) would let operators spot drift.
- **`lifespan` context manager for clean shutdown of pooled clients**
  — the AI gateway's `httpx.AsyncClient` currently has no graceful
  shutdown path; this matters more when adding more pooled clients.
- **OCR request-deduplication cache** — the OCR endpoint
  (`/api/ocr/parse`) repeats work across concurrent identical
  uploads. A 30-second TTL keying on the file hash would cut
  billable OCR calls by ~40% in the common case.
- **Prometheus exporter** — if we ever move to multi-process
  multiprocessing workers, the in-process recorder will under-count.
  A Prometheus exporter would also unlock alert rules. Defer until
  traffic justifies the operational complexity.

---

## 7. Summary

- Files added: 2 (`latency.py`, `test_latency_middleware.py`).
- Files modified: 2 (`config.py`, `main.py`).
- Tests added: 10.
- Total backend suite: **138 passed**.
- Default behavior: endpoint returns 404 (safe).
- Opt-in behavior: `internal_metrics_token` env var exposes snapshot.

P4-1 is the first observability layer. The next observability item —
per-route latency histograms over time — is queued for P4-2.
