"""One-time backfill: stamp ``ownerId`` on legacy medicine_doses docs.

Why this script exists
----------------------

``firebase/firestore.rules`` was tightened to require ``ownerId == request.auth.uid``
on every ``medicine_doses`` read/write. Doses written before that rule shipped
have no ``ownerId`` field at all, which made ``mark Taken / Skip`` fail with
"permission-denied" → "You do not have access to this item".

The rule has since been relaxed so a write that *claims* an unowned doc by
setting ``ownerId = request.auth.uid`` is permitted (see the ``ownedUpdate``
helper in ``firebase/firestore.rules``). This script is the belt-and-braces
companion: it walks every existing ``medicine_doses`` doc, looks up the
medicine's owning user via the deterministic dose id format
``{medicineId}_{slot}_{dateKey}``, and stamps ``ownerId`` directly using the
Firebase Admin SDK. Running it once makes the new rule's "unowned claim"
branch irrelevant for every existing row.

Usage
-----

::

    python -m scripts.backfill_medicine_doses_owner --apply

Defaults to dry-run. ``--apply`` is required for any writes. Safe to re-run:
docs that already have the correct ownerId are skipped.

Required environment
--------------------

* ``FIREBASE_SERVICE_ACCOUNT_JSON`` — full JSON of the service account
  credential (the same one the backend uses).
* OR ``GOOGLE_APPLICATION_CREDENTIALS`` — path to a credentials JSON file.

Exit codes
----------

* 0 — every legacy doc was stamped (or was already correctly owned).
* 1 — at least one dose could not be matched to its medicine, or the
      Firebase client failed to initialise.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from collections.abc import Iterable
from dataclasses import dataclass

logger = logging.getLogger("backfill_medicine_doses_owner")


@dataclass
class DoseOutcome:
    doc_id: str
    status: str  # already | stamped | orphan | skipped
    detail: str = ""


def _init_firebase() -> "firestore.Client":  # type: ignore[name-defined]
    """Boot firebase_admin with whichever credential is available."""
    import firebase_admin
    from firebase_admin import credentials, firestore

    if not firebase_admin._apps:
        raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
        if raw:
            import json

            info = json.loads(raw)
            firebase_admin.initialize_app(credentials.Certificate(info))
        else:
            firebase_admin.initialize_app(credentials.ApplicationDefault())

    return firestore.client()


def _iter_doses(client) -> Iterable[tuple[str, dict]]:
    """Yield ``(doc_id, data)`` for every ``medicine_doses`` document."""
    for snap in client.collection("medicine_doses").stream():
        data = snap.to_dict() or {}
        yield snap.id, data


def _medicine_owner(client, dose_id: str, dose_data: dict) -> str | None:
    """Resolve the owner uid of the medicine this dose belongs to.

    The Flutter client builds deterministic ids as
    ``{medicineId}_{slot}_{dateKey}``. We rely on that format.
    """
    explicit = dose_data.get("medicineId")
    if explicit and isinstance(explicit, str):
        medicine_id = explicit
    else:
        # Last three underscore-separated segments are dateKey, slot, and
        # medicineId with arbitrary separators inside; fall back to taking
        # everything before the last two underscores.
        parts = dose_id.rsplit("_", 2)
        if len(parts) != 3:
            return None
        medicine_id = parts[0]

    med_snap = client.collection("medicines").document(medicine_id).get()
    if not med_snap.exists:
        return None
    med_data = med_snap.to_dict() or {}
    return med_data.get("ownerId") or med_data.get("userId")


def backfill(*, apply: bool) -> list[DoseOutcome]:
    """Stamp ``ownerId`` on every legacy medicine_doses doc.

    Returns a per-document outcome list. With ``apply=False`` nothing is
    written; the script still reports what *would* change.
    """
    client = _init_firebase()
    outcomes: list[DoseOutcome] = []

    for doc_id, data in _iter_doses(client):
        existing = data.get("ownerId")
        if existing:
            outcomes.append(DoseOutcome(doc_id, "already", "ownerId present"))
            continue

        owner = _medicine_owner(client, doc_id, data)
        if not owner:
            outcomes.append(
                DoseOutcome(
                    doc_id,
                    "orphan",
                    "no ownerId on dose and medicine not found",
                )
            )
            continue

        if apply:
            client.collection("medicine_doses").document(doc_id).update(
                {"ownerId": owner}
            )
            outcomes.append(DoseOutcome(doc_id, "stamped", f"ownerId={owner}"))
        else:
            outcomes.append(
                DoseOutcome(doc_id, "skipped", f"would stamp ownerId={owner}")
            )

    return outcomes


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument(
        "--apply",
        action="store_true",
        help="actually write to Firestore. Without this flag the script is a dry-run.",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    logging.basicConfig(
        level=args.log_level,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    outcomes = backfill(apply=args.apply)

    by_status: dict[str, int] = {}
    for outcome in outcomes:
        by_status[outcome.status] = by_status.get(outcome.status, 0) + 1

    logger.info("Backfill summary (apply=%s): %s", args.apply, by_status)
    for outcome in outcomes:
        if outcome.status != "already":
            logger.info("  %s: %s -- %s", outcome.status, outcome.doc_id, outcome.detail)

    if by_status.get("orphan", 0) > 0:
        logger.error(
            "%d dose(s) could not be matched to a medicine; review before re-running.",
            by_status["orphan"],
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
