"""P2-parity — pin that every study-only endpoint is require_student-gated.

The senior-engineer pipeline needs a single, permanent source of truth
for the role-gate invariant. The check has two parts:

  1. **Static introspection.** Walk the FastAPI app's ``routes`` tree
     (including nested ``_IncludedRouter`` mounts) and assert that every
     student-only path uses ``require_student`` in its dependency list.
     If a future PR adds an endpoint under ``/api/study``, ``/api/ai``,
     ``/api/materials``, ``/api/groups``, ``/api/reports`` without
     gating it, this test fails.

  2. **Runtime black-box.** With the conftest fakes installed, hit each
     student-only endpoint with a ``general``-role token and confirm
     the server returns 403 (or 404 when the gate raises before the
     handler runs).

Together these pin the security invariant against accidental bypass.

The list of student-only prefixes is intentionally hand-maintained so
adding a brand-new surface requires an explicit decision to either
include it here (and gate it) or exclude it (and document why)."""

from __future__ import annotations

from fastapi.routing import APIRoute

from app.core.auth import require_student
from app.main import app

# Surface prefixes the security review has classified as student-only.
# ``/api/prescriptions`` is NOT in this list: the prescription OCR
# extractor is review-only and the medical app must be reachable by
# ``general`` users who may manage a non-student's medication. The
# extracted text is *not* auto-saved; explicit user confirmation is
# required (P1-4 contract).
STUDENT_ONLY_PREFIXES = (
    "/api/study",
    "/api/ai",
    "/api/materials",
    "/api/groups",
    "/api/reports",
)


def _walk_all_routes() -> list[APIRoute]:
    """Recursively walk ``app.routes`` so nested ``_IncludedRouter`` mounts
    are inspected the same as routes registered on the top-level app.

    Returns a list of :class:`APIRoute` objects annotated with a private
    ``_resolved_path`` attribute carrying the cumulative URL prefix so
    assertions can use the real path (``/api/study/plan``, not ``/plan``).
    """
    out: list[APIRoute] = []

    def _walk(prefix: str, routes) -> None:
        for route in routes:
            if isinstance(route, APIRoute):
                full = prefix + route.path
                object.__setattr__(route, "_resolved_path", full)  # type: ignore[attr-defined]
                out.append(route)
                continue
            # Nested router: figure out its sub-prefix from include_context.
            sub_prefix = prefix
            ic = getattr(route, "include_context", None)
            if ic is not None:
                p = getattr(ic, "prefix", "") or ""
                if p:
                    sub_prefix = prefix + p
            sub_routes = getattr(route, "routes", None)
            if sub_routes is None:
                orig = getattr(route, "original_router", None)
                if orig is not None:
                    sub_routes = getattr(orig, "routes", None)
            if sub_routes:
                _walk(sub_prefix, sub_routes)

    _walk("", app.routes)
    return out


def _resolved_path(route: APIRoute) -> str:
    """Return the prefix-aware path recorded by :func:`_walk_all_routes`."""
    cached = getattr(route, "_resolved_path", None)
    if cached is not None:
        return cached
    return route.path


def _route_dependencies(route: APIRoute) -> list:
    """Return the callable dependency list for a FastAPI route."""
    return [dep.call for dep in route.dependant.dependencies]


def test_every_student_only_route_uses_require_student():
    """Static invariant: every student-only path depends on require_student."""
    missing: list[tuple[str, str]] = []
    for route in _walk_all_routes():
        path = _resolved_path(route)
        if not any(path.startswith(p) for p in STUDENT_ONLY_PREFIXES):
            continue
        # OPTIONS preflight handled by CORS middleware, not a real route.
        if route.methods and route.methods == {"OPTIONS"}:
            continue

        deps = _route_dependencies(route)
        if require_student not in deps:
            missing.append((",".join(sorted(route.methods or [])), path))

    assert not missing, (
        "Student-only routes missing `require_student`:\n  "
        + "\n  ".join(f"{m:>7} {p}" for m, p in missing)
        + "\n\nEither add `Depends(require_student)` to the handler, or remove "
        "the prefix from STUDENT_ONLY_PREFIXES with an explanatory comment."
    )


def test_general_role_is_rejected_from_study_only_routes(client, fake_auth, fake_db):
    """Runtime invariant: every student-only route rejects general users."""
    fake_auth.tokens["token-general"] = {
        "uid": "u-general",
        "email": "g@example.com",
        "email_verified": True,
        "role": "general",
    }
    # ``require_student`` resolves role from the Firestore profile document
    # under ``users/{uid}`` — seed it so the gate has something to look at.
    fake_db.seed(
        "users",
        "u-general",
        {"role": "general", "displayName": "General User", "emailVerified": True},
    )

    # Pick the first GET-or-POST route under each student-only prefix.
    # Discovery from the actual route table keeps it valid as the surface
    # evolves; if a prefix is added but no probe route exists yet, the static
    # ``test_every_student_only_route_uses_require_student`` still catches the
    # missing gate.
    all_routes = _walk_all_routes()
    probes: list[tuple[str, str]] = []
    for prefix in STUDENT_ONLY_PREFIXES:
        for route in all_routes:
            path = _resolved_path(route)
            if not path.startswith(prefix):
                continue
            methods = set(route.methods or set())
            if not (methods & {"GET", "POST"}):
                continue
            method = "GET" if "GET" in methods else "POST"
            probes.append((method, path))
            break
        else:
            raise AssertionError(
                f"No GET/POST route discovered under {prefix}; "
                "the runtime gate test cannot probe this prefix."
            )

    for method, path in probes:
        # Some POST probes need a JSON body — sending an empty ``{}`` keeps
        # the handler past the auth gate (where validation may legitimately
        # 422, but we expect 403 because require_student raises first).
        response = client.request(
            method,
            path,
            json={},
            headers={"Authorization": "Bearer token-general"},
        )
        # Either 403 (gated) or 404 (route gated before path-matching).
        # Anything else — 200, 422 with payload, etc. — is a security bug.
        assert response.status_code in (403, 404), (
            f"{method} {path} returned {response.status_code} for general role: "
            f"{response.text!r}. A 200 means the gate is missing; a 422 with "
            "payload means the request body was processed past the gate."
        )


def test_role_gate_does_not_apply_to_open_surfaces(client, fake_auth, fake_db):
    """Negative control: health/me are reachable by any signed-in user."""
    fake_auth.tokens["token-general"] = {
        "uid": "u-general",
        "email": "g@example.com",
        "email_verified": True,
        "role": "general",
    }
    # ``/api/me`` reads the Firestore profile; seed it so the route succeeds.
    fake_db.seed(
        "users",
        "u-general",
        {"role": "general", "displayName": "General User", "emailVerified": True},
    )

    # ``/api/health`` is intentionally unauthenticated.
    response = client.get("/api/health")
    assert response.status_code == 200, response.text

    # ``/api/me`` accepts any authenticated identity regardless of role.
    response = client.get(
        "/api/me",
        headers={"Authorization": "Bearer token-general"},
    )
    assert response.status_code == 200, response.text
