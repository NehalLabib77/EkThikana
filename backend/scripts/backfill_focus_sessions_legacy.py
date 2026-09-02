"""One-time backfill: clamp legacy focus session ``accumulatedSeconds`` rows.

Why this script exists
----------------------

``users/{uid}/focus_sessions/{id}`` carries a per-session ``accumulatedSeconds``
integer. The Flutter focus timer started in 2026 reading a different field
name (``elapsedSeconds``) which no backend response ever contained; while that
client bug was live, several test installs and at least one production
student populated the row with a value that **looks like minutes stored in a
seconds-shaped column**. The most visible symptom on the affected account
was a single session row reporting ``98h 37m`` and a Profile card reporting
``5917 min`` of focus this month — exactly the unit-mismatch you'd see when
5_917 minutes (354_920 s) is dropped into an ``accumulatedSeconds`` field.

The backend now clamps any value larger than ``24h`` at read time
(``_coerce_focus_seconds`` in ``app/routers/part3.py``), so new API calls
already return sane numbers. This script is the belt-and-braces companion:
it walks every existing ``focus_sessions`` doc and rewrites the on-disk value
to the clamped form, so subsequent cache hits, Firestore listeners and ad-hoc
``admin`` reads all see the same thing.

Usage
-----

::

    python -m scripts.backfill_focus_sessions_legacy            # dry-run (default)
    python -m scripts.backfill_focus_sessions_legacy --apply    # perform writes
    python -m scripts.backfill_focus_sessions_legacy --user <uid>  # one user only

Dry-run prints the planned changes per doc and exits without writing. The
``--apply`` flag is required for any writes; without it, the script is a
read-only audit. Re-running the script is safe: a doc whose value is already
within bounds is skipped.

Required environment
--------------------

* ``FIREBASE_SERVICE_ACCOUNT_JSON`` — full JSON of the service account
  credential (the same one the backend uses).
* OR ``GOOGLE_APPLICATION_CREDENTIALS`` — path to a credentials JSON file.

Exit codes
----------

* ``0`` — every legacy doc was either rewritten to its clamped value or was
  already within bounds. Dry-run is also exit 0; the absence of writes is
  not an error.
* ``1`` — could not initialise Firebase (no service account in the
  environment) or an unexpected exception was raised.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from collections import Counter
from typing import Iterable

logger = logging.getLogger("gochano.backfill_focus_legacy")


# Same value the router uses at read time. Kept in sync deliberately — the
# router clamps if the doc still says 354_920, this script rewrites the doc
# so the next read is naturally correct without going through the helper.
_FOCUS_MAX_SECONDS = 24 * 60 * 60  # 86_400 s


def _coerce(raw) -> int:
    """Mirror the router-side read-time coercion."""
    if isinstance(raw, bool):
        return 0
    if isinstance(raw, int):
        seconds = raw
    elif isinstance(raw, float):
        seconds = int(raw)
    elif isinstance(raw, str):
        try:
            seconds = int(raw)
        except ValueError:
            seconds = 0
    else:
        seconds = 0
    if seconds < 0:
        return 0
    if seconds > _FOCUS_MAX_SECONDS:
        return 0
    return seconds


def _init_firebase() -> tuple[object, object]:
    """Initialise the Firebase Admin SDK with the same fallback the backend
    uses for its service-account resolution."""
    try:  # pragma: no cover - exercised only at runtime with real creds
        import firebase_admin  # type: ignore
        from firebase_admin import credentials, firestore  # type: ignore
    except ImportError as exc:  # pragma: no cover - exercised only at runtime
        raise RuntimeError(
            "firebase-admin is required to run this script; "
            "install backend/requirements.txt before invoking."
        ) from exc

    if not firebase_admin._apps:
        sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
        if sa_json:
            cred = credentials.Certificate(json.loads(sa_json))
        else:
            cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred)
    return firebase_admin, firestore


def _iter_focus_docs(db) -> Iterable[tuple[str, str, dict]]:
    """Yield ``(uid, doc_id, data)`` for every focus session across every user."""
    for user_doc in db.collection("users").stream():
        uid = user_doc.id
        sessions = (
            db.collection("users")
            .document(uid)
            .collection("focus_sessions")
            .stream()
        )
        for s in sessions:
            yield uid, s.id, s.to_dict() or {}


def _plan_changes(docs) -> tuple[list[tuple[str, str, int, int]], Counter]:
    """Return the list of docs that would change and a summary counter.

    The list entries are ``(uid, doc_id, before, after)`` so the dry-run can
    print human-readable diffs without re-querying Firestore.
    """
    changes: list[tuple[str, str, int, int]] = []
    summary: Counter = Counter()
    for uid, doc_id, data in docs:
        raw = data.get("accumulatedSeconds", 0)
        before = _coerce(raw)  # we always display in canonical form
        coerced = _coerce(raw)
        if coerced != raw or coerced != before:
            # Either the field itself was out of range, or its type coerced
            # into a different integer. We rewrite only when the canonical
            # form differs from the raw stored value.
            changes.append((uid, doc_id, raw if isinstance(raw, (int, float, str)) else 0, coerced))
        summary["docs_total"] += 1
        summary["docs_already_canonical"] += int(coerced == before)
        summary["docs_rewritten"] += int(coerced != before and (coerced != raw))
    return changes, summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Backfill users/*/focus_sessions/* so legacy minutes-in-seconds "
            "rows are clamped down to a sane max. Dry-run by default."
        )
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Perform writes. Without this flag the script is a read-only audit.",
    )
    parser.add_argument(
        "--user",
        default=None,
        help="Limit the backfill to a single uid (handy when triaging a known bad row).",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress per-doc output; print only the summary line.",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")

    try:
        _, firestore = _init_firebase()
    except Exception as exc:
        logger.error("Firebase init failed: %s", exc)
        return 1

    db = firestore.client()

    if args.user:
        all_docs = [
            (args.user, doc.id, doc.to_dict() or {})
            for doc in (
                db.collection("users")
                .document(args.user)
                .collection("focus_sessions")
                .stream()
            )
        ]
    else:
        all_docs = list(_iter_focus_docs(db))

    changes, summary = _plan_changes(all_docs)

    if not args.quiet:
        for uid, doc_id, before, after in changes:
            action = "would rewrite" if not args.apply else "rewrote"
            print(
                f"[{action}] users/{uid}/focus_sessions/{doc_id}: "
                f"accumulatedSeconds {before!r} -> {after} "
            )

    if args.apply and changes:
        for uid, doc_id, _before, after in changes:
            (
                db.collection("users")
                .document(uid)
                .collection("focus_sessions")
                .document(doc_id)
                .update({"accumulatedSeconds": after})
            )

    would_rewrite = len(changes)
    rewritten = would_rewrite if args.apply else 0
    already_canonical = len(all_docs) - would_rewrite
    print(
        json.dumps(
            {
                "mode": "apply" if args.apply else "dry-run",
                "scanned_users": (
                    1 if args.user else len({uid for uid, *_ in all_docs})
                ),
                "docs_scanned": len(all_docs),
                "docs_rewritten": rewritten,
                "docs_would_rewrite": would_rewrite if not args.apply else 0,
                "docs_already_canonical": already_canonical,
            }
        )
    )
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main(sys.argv[1:]))
