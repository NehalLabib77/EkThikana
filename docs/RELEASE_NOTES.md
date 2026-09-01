# Gochano — release notes

This document summarises what shipped across the P3 cross-cutting pass
(P3-9 Security, P3-10 Performance, P3-11 Accessibility) and the
user-visible improvements they bring.

---

## At a glance

| Metric | Value |
|---|---|
| Tests pinned in P3 | 47 new (27 backend + 20 Flutter) |
| Critical bugs closed | 0 (P3 was hardening-only) |
| A11y regressions closed | 21 |
| Performance regressions closed | 11 |
| Security regressions closed | 16 |
| Brand-impacting palette change | Yes — module gradient stops darkened for AA contrast (hue drift ≤ 0.5°) |

---

## Accessibility

TalkBack (Android) and VoiceOver (iOS) users will experience:

1. **Every logo is now announced as "Gochano logo"** — previously read
   as "image" with no description.
2. **Every icon-only button now has a tooltip** — refresh, delete,
   navigate-previous, navigate-next, show-calendar, search, add-item,
   add-note, delete-note, delete-subject, unsave. Each is announced
   with a meaningful name when focus arrives.
3. **The dashboard language toggle is now announced as a labelled
   selectable control** — previously read as a bare "double-tap to
   activate" with no context.
4. **Every gradient hero card now clears WCAG AA body-text contrast**
   (4.5:1) on both ends of every module gradient in both light and
   dark mode. White text on `expense`, `medicine`, `commute`, `bazar`,
   `tasks`, `ai` was previously below 4.5:1 on the lighter end-stops;
   those stops are now darkened to clear the threshold.

For users who do **not** use a screen reader, the only visible change is
that the hero card gradients look slightly more saturated / less neon
on the right edge of every module — the brand hue is preserved.

---

## Security

No user-visible behaviour changes. The following protections are now
pinned by regression tests so they cannot silently regress in future
PRs:

1. Firebase ID tokens are verified server-side before any protected API
   call. Revoked tokens are rejected with HTTP 401.
2. Email verification is required for app data access. Unverified users
   receive HTTP 403 on both read and write paths.
3. User role is server-authoritative. The role field supplied in
   `POST /users` is ignored — only the JWT claim sets the role.
4. Public academic material is only served to authenticated Student-role
   users.
5. Downloads use short-lived signed URLs (900s TTL).
6. The Supabase service-role key exists only on the backend; it never
   ships in the Flutter bundle.

See `docs/SECURITY_PRIVACY.md` for the full invariant list.

---

## Performance

No user-visible behaviour changes. The following efficiency guarantees
are now pinned by regression tests:

1. Quota checks now use a per-user cached counter, giving O(1) reads
   instead of recomputing from `material_files` on every request.
2. OCR and PDF extraction endpoints route their blocking I/O through
   the threadpool so the FastAPI event loop stays free for other
   requests.
3. The AI gateway reuses a single module-level `httpx.AsyncClient`
   pool instead of opening a new connection per request.
4. The health endpoint and a handful of high-traffic reads return
   within their p95 budget (asserted in
   `test_performance_audit.py`).

---

## Observability

Shipped in P4-1 (post-launch hardening, not user-visible):

1. **Per-endpoint latency recorder** — every request now contributes a
   wall-clock sample to a bounded ring buffer (default 128 samples)
   keyed on `(method, route-template)`. Aggregated p50 / p95 / p99 /
   mean per route are exposed behind `GET /api/_internal/latency`,
   gated by the `X-Internal-Token` header.
2. **Safe-by-default internal endpoint** — when
   `internal_metrics_token` is unset (the default) the internal
   endpoint returns 404, so a public Render deploy never accidentally
   exposes the snapshot. Set the env var to enable.
3. **Health-probe noise suppressed** — `/api/health` does not emit a
   per-request INFO log line, so liveness probes don't drown the log
   pipeline.
4. **Quantile formula pinned by tests** — `tests/test_latency_middleware.py`
   asserts the nearest-rank percentile output for a known input, so a
   future refactor that flips to linear interpolation fires the test
   suite and the change is intentional.

See [`docs/PHASE_4_1_LATENCY_MIDDLEWARE.md`](./PHASE_4_1_LATENCY_MIDDLEWARE.md)
for the full design rationale.

---

## For developers

- New test files:
  - `backend/tests/test_security_audit.py` (16 tests)
  - `backend/tests/test_performance_audit.py` (11 tests)
  - `flutter_app/test/a11y/accessibility_audit_test.dart` (20 tests)
  - `backend/tests/test_latency_middleware.py` (10 tests, **P4-1**)
- New docs:
  - `docs/PHASE_3_9_SECURITY_AUDIT.md`
  - `docs/PHASE_3_10_PERFORMANCE_AUDIT.md`
  - `docs/PHASE_3_11_ACCESSIBILITY_AUDIT.md`
  - `docs/PHASE_4_1_LATENCY_MIDDLEWARE.md` (**P4-1**)
  - `docs/FINAL_AUDIT_REPORT.md` (this document's sibling)
- PowerShell audit scripts under `docs/`:
  - `docs/contrast.ps1` and `docs/contrast_v2.ps1` — WCAG ratio scans
  - `docs/contrast_search.ps1` — darkening-factor search
  - `docs/contrast_medicine.ps1` — secondary search
  - `docs/contrast_delta.ps1` — hue-drift verification
  - `docs/audit_iconbuttons.ps1` — IconButton static scan
  - `docs/audit_gestures.ps1` — GestureDetector static scan

---

## Known issues & P4 follow-ups

These are **not** release blockers but are tracked for the next pass:

- On-device TalkBack / VoiceOver walkthrough.
- Colour-blind palette audit.
- Focus-visible outline customisation.
- Bazar buddy long-press delete label.
- Per-endpoint p95 latency SLI over time (per-route histogram rings; P4-1
  shipped the point-in-time snapshot on `GET /api/_internal/latency` —
  see [`docs/PHASE_4_1_LATENCY_MIDDLEWARE.md`](./PHASE_4_1_LATENCY_MIDDLEWARE.md)).
- AI provider's data-use terms reviewed for the privacy policy.

