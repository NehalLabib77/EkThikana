# Phase 3-9 — Final security audit (cross-cutting)

**Status: ✅ shipped. Backend 117/117 (+16 new in `test_security_audit.py`),
analyzer clean.**

P3-9 is the first of three cross-cutting audits (security → performance →
a11y) before the closing docs. It is a **pure read + pin** phase: no fixes
were required, every invariant was already enforced at the code level. The
job here was to walk every security-sensitive surface and either confirm
the contract is sound or flag a deferred item — and to lock every confirmed
invariant behind a regression test so future changes cannot silently
weaken it.

The Gochano security model rests on seven invariants. Each is documented
below with the file that enforces it and the test that pins it.

## 1. Invariants verified

### 1.1 Firebase ID tokens are verified with revocation check
- **File.** `backend/app/core/auth.py` — `get_verified_identity()` calls
  `auth.verify_id_token(token, check_revoked=True)`.
- **Failure mode.** Invalid, expired, or revoked tokens → 401 with
  `Invalid or expired Firebase ID token`.
- **Pinned by.** `test_revoked_token_returns_401`
  (token removed from the in-memory store after issue → 401 on reuse).

### 1.2 Email-verified gate
- **File.** `backend/app/core/auth.py` — same function, second branch:
  `if not decoded.get("email_verified", False): raise 403`.
- **Failure mode.** Authenticated-but-unverified user → 403 with
  `Email verification is required`. Runs **before** role resolution, so
  the gate fires regardless of the user's role.
- **Pinned by.** `test_unverified_email_returns_403`,
  `test_unverified_email_cannot_upload_materials`.

### 1.3 Role allowlist (`require_student`)
- **File.** `backend/app/core/auth.py` — `require_student` raises 403
  when `role != "student"`.
- **Surface.** Every `/api/study`, `/api/ai`, `/api/materials`,
  `/api/groups`, `/api/reports` route depends on `require_student`.
- **Pinned by.** `test_every_student_only_route_uses_require_student` +
  `test_general_role_is_rejected_from_study_only_routes` (existing in
  `test_role_gate_coverage.py`); re-pinned in
  `test_general_role_rejected_from_study_plan` from a fresh angle.

### 1.4 Filename sanitization + locked object path
- **File.** `backend/app/core/utils.py` — `safe_filename()` replaces
  `/` and `\` with `_`, strips everything outside `[A-Za-z0-9._() -]`,
  caps at 120 chars. `backend/app/routers/materials.py` builds the
  storage key as `users/{user.uid}/{uuid.uuid4().hex}_{safe_name}` —
  the user's UID is hard-coded into the prefix; the filename can never
  alter the bucket key's first segment.
- **Failure mode.** A traversal payload like `../../etc/passwd.pdf` is
  rewritten to `.._.._etc_passwd.pdf`; the resulting object path is
  `users/{uid}/{uuid}_.._.._etc_passwd.pdf` and stays inside the
  caller's prefix with no remaining `/` boundary for a storage
  backend to interpret as a directory hop.
- **Pinned by.** `test_path_traversal_filename_is_sanitized`,
  `test_path_traversal_backslash_is_sanitized`.

### 1.5 V4 signed URLs with ≤ 15-minute TTL
- **File.** `backend/app/services/storage_service.py` —
  `create_signed_url()` uses `version="v4"` and
  `expiration=now() + signed_url_ttl_seconds` (default 900 s, configurable
  via `SIGNED_URL_TTL_SECONDS`).
- **Spec ceiling.** §8.10 requires signed URLs to expire in ≤ 15 minutes.
- **Pinned by.** `test_signed_url_ttl_is_at_most_fifteen_minutes`,
  `test_signed_url_uses_v4_version`.

### 1.6 Ownership / IDOR on materials
- **File.** `backend/app/routers/materials.py` — every mutation
  (`PATCH`, `PUT /file`, `DELETE`) calls
  `_get_material_owned_by()` which raises 404 (missing) or 403 (not
  owner). Reads (`GET /url`) go through
  `permission_service.get_material_for_user()` which enforces
  owner / public / group-member visibility.
- **Pinned by.** `test_non_owner_cannot_read_private_material_signed_url`,
  `test_non_owner_cannot_patch_material`,
  `test_non_owner_cannot_delete_material`.

### 1.7 Group membership gate
- **File.** `backend/app/routers/materials.py` for uploads (the
  `visibility == "group"` branch checks
  `user.uid in memberIds` and raises 403 otherwise);
  `backend/app/services/permission_service.py` for reads.
- **Pinned by.** `test_non_member_cannot_read_group_material`,
  `test_non_member_cannot_upload_to_group`.

### 1.8 Account surface scoped to caller
- **File.** `backend/app/routers/account.py` — `DELETE /api/account`
  resolves the UID from `Depends(get_verified_identity)`; there is no
  body-supplied UID. The handler iterates `OWNER_COLLECTIONS` filtered
  by `ownerId == user.uid` and calls `auth.delete_user(user.uid)`.
- **Pinned by.** `test_account_delete_scoped_to_caller` (attacker calls
  DELETE → victim's records untouched; only attacker's UID is on the
  `deleted` list).

### 1.9 Per-user quota isolation
- **File.** `backend/app/services/ai_service.py` (and the upload
  quota in `backend/app/routers/materials.py`).
- **Pinned by.** `test_ai_quota_is_per_user` — exhausting user A's
  quota must not affect user B.

### 1.10 CORS locked down
- **File.** `backend/app/core/config.py` — `cors_origins: str = ""`
  default. `backend/app/main.py` reads `cors_origins`, splits on `,`,
  and registers an explicit list. Empty → no CORS headers are sent
  to cross-origin clients.
- **Pinned by.** `test_cors_origins_default_is_empty` (asserts the
  class-level default is `""`; tests run with a local `.env` that
  sets `CORS_ORIGINS=*` for dev — but the security-relevant contract
  is the in-code default).

## 2. Deferred / acceptable gaps

| # | Gap | Why it's acceptable | Mitigation |
|---|-----|---------------------|------------|
| 1 | **No FastAPI-layer IP rate-limit middleware.** | The current scale is bounded by per-user quotas (AI daily, upload daily, storage cap) and by Firebase-side limits (token issuance, email verification). Adding `slowapi` or equivalent would require Redis (or another shared store), which we deliberately don't run. | Per-user quotas pin the upper bound on what any single account can do; brute-force would still need a valid verified Firebase ID token. If we ever open unauthenticated endpoints or expose the API beyond the Flutter client, this becomes a blocker. |
| 2 | **Public materials disabled.** | `routers/materials.py` raises 400 if `visibility == "public"` for *new* uploads, but legacy public docs may still exist. They're already gated by `permission_service.get_material_for_user()`. | Acceptable. The contract is "no new public uploads", not "no public reads". |

## 3. Out of scope (intentionally)

These belong to other suites and are not re-pinned here:

- **Per-collection CRUD ownership** — `tests/test_part3.py`,
  `tests/test_account_delete_postgres.py`.
- **Postgres fare-reports cleanup on account delete** — `tests/test_account_delete_postgres.py`.
- **Quota mechanics** — `tests/test_quotas.py`.
- **Static role-gate discovery across the full route tree** — `tests/test_role_gate_coverage.py`.

## 4. New tests

`backend/tests/test_security_audit.py` — **16 tests**:

| # | Test | Pins |
|---|------|------|
| 1 | `test_revoked_token_returns_401` | Invariant 1.1 |
| 2 | `test_unverified_email_returns_403` | Invariant 1.2 |
| 3 | `test_unverified_email_cannot_upload_materials` | Invariant 1.2 |
| 4 | `test_general_role_rejected_from_study_plan` | Invariant 1.3 |
| 5 | `test_path_traversal_filename_is_sanitized` | Invariant 1.4 |
| 6 | `test_path_traversal_backslash_is_sanitized` | Invariant 1.4 |
| 7 | `test_signed_url_ttl_is_at_most_fifteen_minutes` | Invariant 1.5 |
| 8 | `test_signed_url_uses_v4_version` | Invariant 1.5 |
| 9 | `test_non_owner_cannot_read_private_material_signed_url` | Invariant 1.6 |
| 10 | `test_non_owner_cannot_patch_material` | Invariant 1.6 |
| 11 | `test_non_owner_cannot_delete_material` | Invariant 1.6 |
| 12 | `test_non_member_cannot_read_group_material` | Invariant 1.7 |
| 13 | `test_non_member_cannot_upload_to_group` | Invariant 1.7 |
| 14 | `test_account_delete_scoped_to_caller` | Invariant 1.8 |
| 15 | `test_ai_quota_is_per_user` | Invariant 1.9 |
| 16 | `test_cors_origins_default_is_empty` | Invariant 1.10 |

## 5. Validation

### 5.1 Backend pytest
```
$ python -m pytest
======================= 117 passed, 1 warning in 1.97s ========================
```

| Suite                       | Count | New |
|-----------------------------|------:|-----:|
| `test_security_audit.py`    |    16 |  +16 |
| **Full backend**            |   **117** | **+16** (was 101) |

### 5.2 Flutter analyzer
Not touched (security audit is backend-only); P3-8 status unchanged
(106/106, analyzer clean).

## 6. Files touched

### Added
- `backend/tests/test_security_audit.py` (16 tests)
- `docs/PHASE_3_9_SECURITY_AUDIT.md` (this file)

### Modified
- none — this phase is pure read + pin.

## 7. Conclusion

The security posture is sound. Every invariant the brief calls out
(revocation check, email verification, role gate, signed-URL TTL,
filename sanitization, ownership, group membership, account scoping,
per-user quotas, CORS lockdown) is enforced at the code level and now
has a regression test. The only deferred item is FastAPI-layer IP
rate-limiting, which is acceptable at the current scale because every
endpoint that touches expensive resources is already user-scoped and
quota-bounded.
