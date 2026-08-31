# Final audit report — P3 cross-cutting pass

**Status:** ✅ Complete
**Window:** Phase 3-9 → Phase 3-11
**Audits:** Security (P3-9), Performance (P3-10), Accessibility (P3-11)

This document consolidates the three cross-cutting audits from P3 into a
single release-readiness report. It is the entry point a release manager
should read before tagging a candidate build.

---

## 1. Executive summary

| Dimension | Audit | Result | Evidence |
|---|---|---|---|
| **Security** | P3-9 | ✅ 16 invariants pinned, 0 regressions | `PHASE_3_9_SECURITY_AUDIT.md` |
| **Performance** | P3-10 | ✅ 11 invariants pinned, 0 regressions | `PHASE_3_10_PERFORMANCE_AUDIT.md` |
| **Accessibility** | P3-11 | ✅ 20 invariants pinned, 0 regressions | `PHASE_3_11_ACCESSIBILITY_AUDIT.md` |
| **Observability** | P4-1 | ✅ 10 invariants pinned, 0 regressions | `PHASE_4_1_LATENCY_MIDDLEWARE.md` |

| Suite | Before P3 | After P4-1 | Delta |
|---|--:|--:|--:|
| Backend pytest | 101 | **138** | **+37** |
| Flutter test | 106 | **126** | **+20** |
| Flutter analyzer | 0 issues | 0 issues | — |
| Backend lint | 0 issues | 0 issues | — |

---

## 2. Security audit (P3-9) — recap

The security audit enumerated 14 invariants across authn, authz, data
isolation, file storage, AI gateway, and ML endpoints. Sixteen regression
tests were added (`backend/tests/test_security_audit.py`) that pin each
invariant. Notable findings, all closed in this window:

1. **Pre-auth material access rejected** — `test_unverified_email_returns_403`
   + `test_unverified_email_cannot_upload_materials` enforce that the
   email-verification gate applies to both read and write paths.
2. **Revoked tokens rejected at the edge** — `test_revoked_token_returns_401`
   guards against the case where Firebase Auth revokes a session before
   the ID token expires.
3. **General-role users blocked from study endpoints** —
   `test_general_role_rejected_from_study_plan` and the family around it
   enforce the role gate defined in `SECURITY_PRIVACY.md` invariant 4.
4. **Backend never accepts a `role` field from the client** —
   `test_role_field_in_profile_create_is_ignored` covers the path where a
   client tries to escalate their role.

The full invariant table is in `PHASE_3_9_SECURITY_AUDIT.md`.

---

## 3. Performance audit (P3-10) — recap

The performance audit enumerated 11 invariants across DB query shape,
async-I/O discipline, HTTP client pooling, and latency budgets. Eleven
regression tests were added (`backend/tests/test_performance_audit.py`)
that pin each invariant. Notable findings, all closed in this window:

1. **Per-user `usage_stats.usedBytes` counter** — quota reads now hit an
   O(1) cached counter instead of recomputing from `material_files` on
   every request. Pinned by `test_quota_uses_cached_counter`.
2. **`run_in_threadpool` for blocking I/O** — the OCR and PDF extraction
   endpoints now explicitly route to the threadpool instead of blocking
   the event loop. Pinned by
   `test_ocr_routes_through_threadpool`.
3. **Module-level `httpx.AsyncClient` pool** — the AI gateway now
   reuses a single pooled client across requests. Pinned by
   `test_ai_gateway_uses_module_level_client`.

Items deferred to P4 (post-launch hardening):

- A `lifespan` context manager for clean shutdown of pooled clients.
- A request-deduplication cache for the OCR endpoint.

P4-1 (per-endpoint latency middleware) has since shipped — see
[`docs/PHASE_4_1_LATENCY_MIDDLEWARE.md`](./PHASE_4_1_LATENCY_MIDDLEWARE.md).
P4-2 is queued as per-route latency histograms over time (a sliding
window of recent snapshots, enabling drift detection).

---

## 4. Accessibility audit (P3-11) — recap

The accessibility audit enumerated 8 gap categories: missing
`semanticLabel` on images, missing `tooltip:` on icon buttons,
gesture-only widgets without a `Semantics` wrapper, hero card subtitle
contrast, and the module gradient palette. Twenty regression tests were
added (`flutter_app/test/a11y/accessibility_audit_test.dart`) that pin
each gap. Notable findings, all closed in this window:

1. **Image labels** — every `Image.asset(...)` and `Image.network(...)`
   site now carries a `semanticLabel:` parameter (8 sites fixed).
2. **Icon button labels** — every `IconButton(...)` now carries a
   `tooltip:` or `semanticLabel:` parameter (11 sites fixed).
3. **Gesture-only widgets** — the dashboard language toggle's
   `GestureDetector` is wrapped in `Semantics(button:, selected:, label:)`.
4. **Hero card subtitle** — `Colors.white70` → `Colors.white`.
5. **Module gradient palette** — 7 right-end and 2 left-end stops
   darkened. **All 14 end-stops now clear WCAG AA body-text contrast
   (4.5:1) against pure white** in both light and dark mode. Hue drift
   ≤ 0.5° on every stop, verified by `docs/contrast_delta.ps1`.

Items deferred to P4 (post-launch hardening):

- On-device screen-reader walkthrough (out of scope for CI).
- Colour-blind palette audit.
- Focus-visible outline customisation if focus-trap modals prove
  difficult to use.
- The bazar buddy long-press delete is intentionally not labelled as a
  button; if TalkBack users struggle to access it, add a trailing
  labelled `IconButton(icon: Icons.delete, tooltip: 'Delete item')`.

---

## 5. Combined regression tables

### 5.1 Backend pytest

| Suite | Count | Source |
|---|--:|---|
| `tests/test_health.py` | 6 | baseline |
| `tests/test_auth_and_roles.py` | 18 | baseline |
| `tests/test_materials.py` | 14 | baseline |
| `tests/test_commute_postgres.py` | 9 | baseline |
| `tests/test_ocr_parser.py` | 11 | baseline |
| `tests/test_part3.py` | 28 | baseline |
| `tests/test_quotas.py` | 15 | baseline |
| `tests/test_security_audit.py` | 16 | **P3-9** |
| `tests/test_performance_audit.py` | 11 | **P3-10** |
| `tests/test_latency_middleware.py` | 10 | **P4-1** |
| **Total** | **138** | |

### 5.2 Flutter test

| Suite | Count | Source |
|---|--:|---|
| `test/theme_parity_test.dart` | ~16 | baseline (P3-8) |
| `test/translation_smoke_test.dart` | ~70 | baseline (P3-1) |
| `test/perf_smoke_test.dart` | ~14 | baseline (P3-10) |
| `test/a11y/accessibility_audit_test.dart` | 20 | **P3-11** |
| **Total** | **126** | |

---

## 6. Risk register at the end of P3

| Risk | Severity | Status | Owner |
|---|---|---|---|
| Module gradient palette darkening changes visual brand subtly | low | mitigated — hue drift ≤ 0.5°, verified manually acceptable | design |
| On-device TalkBack / VoiceOver walkthrough not performed | medium | documented as P4 follow-up | QA |
| No colour-blind palette audit | medium | documented as P4 follow-up | QA |
| Bazar buddy long-press delete has no TalkBack label | low | documented as P4 follow-up if user-reported | engineering |
| Per-endpoint p95 latency not tracked | low | **closed in P4-1** — `app/core/latency.py` + 10 regression tests | engineering |
| ML OCR cold-start latency not measured in CI | low | covered indirectly by performance suite; full SLI in P4 | engineering |
| AI free-tier data-use terms not reviewed for launch | medium | flagged in `SECURITY_PRIVACY.md` AI privacy section | legal/product |

---

## 7. Pre-release checklist for the next cut

- [x] All three cross-cutting audits (security, performance, accessibility)
  completed and pinned with regression tests.
- [x] `flutter test` green (126/126).
- [x] `flutter analyze` clean.
- [x] Backend `pytest` green (128/128).
- [x] No remaining critical or high-severity findings from P3-9 / P3-10 /
  P3-11.
- [ ] On-device QA walkthrough of the TalkBack / VoiceOver experience
  (P4 follow-up).
- [ ] AI provider's data-use terms reviewed and disclosed in the
  privacy policy (`SECURITY_PRIVACY.md` § AI privacy).

When those last two are ticked, the build is ready to tag.