"""Copy legacy Firebase Storage files into Backblaze B2.

    python scripts/migrate_firebase_to_b2.py                  # DRY RUN
    python scripts/migrate_firebase_to_b2.py --apply          # actually copy
    python scripts/migrate_firebase_to_b2.py --apply --resume # continue a run

**This never deletes anything.** Not the Firebase object, not the Firestore
record, not on ``--apply``, not with any flag. The first pass is a copy, and
only a copy. Deleting the source is a separate decision that belongs to a
human who has already confirmed the copies are good and the app is serving
from B2 -- and it is not automated here at all.

What it does, per file
----------------------
1. Reads the material record and the ``filePath`` it points at.
2. If B2 already has that key at the same size, marks it migrated and moves
   on. This is what makes re-running safe and cheap.
3. Otherwise downloads from Firebase, uploads to B2, and reads the object
   back to confirm the size matches before calling it done.
4. Stamps ``storageProvider`` on the record so reads stop having to guess.

A run writes its state to ``--state`` after every file, so ``--resume`` picks
up exactly where an interrupted run stopped instead of re-checking the whole
library.

Nothing here prints a credential.
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from app.services import legacy_storage, storage_service  # noqa: E402
from app.services.storage_provider import B2, FIELD  # noqa: E402

DEFAULT_STATE = BACKEND / ".migration_state.json"

#: Transient failures are worth another go; a missing source file is not.
MAX_ATTEMPTS = 3
RETRY_BACKOFF_SECONDS = (1.0, 4.0)

logger = logging.getLogger("gochano.migration")


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------


@dataclass
class Counters:
    scanned: int = 0
    already_in_b2: int = 0
    copied: int = 0
    skipped_no_path: int = 0
    missing_in_firebase: int = 0
    failed: int = 0
    bytes_copied: int = 0

    def as_lines(self) -> list[str]:
        return [
            f"  records scanned        {self.scanned}",
            f"  already in B2          {self.already_in_b2}",
            f"  copied                 {self.copied}",
            f"  bytes copied           {self.bytes_copied:,}",
            f"  records with no path   {self.skipped_no_path}",
            f"  missing in Firebase    {self.missing_in_firebase}",
            f"  failed                 {self.failed}",
        ]


@dataclass
class MigrationState:
    """What a previous run already finished, so a resume can skip it."""

    done: dict[str, str] = field(default_factory=dict)
    failed: dict[str, str] = field(default_factory=dict)
    counters: Counters = field(default_factory=Counters)

    @classmethod
    def load(cls, path: Path) -> "MigrationState":
        if not path.exists():
            return cls()
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            logger.warning("Could not read the state file; starting fresh")
            return cls()
        return cls(
            done=dict(raw.get("done") or {}),
            failed=dict(raw.get("failed") or {}),
            counters=Counters(**(raw.get("counters") or {})),
        )

    def save(self, path: Path) -> None:
        payload = {
            "done": self.done,
            "failed": self.failed,
            "counters": asdict(self.counters),
        }
        # Write to a sibling then replace, so an interrupt mid-write cannot
        # leave a half-written state file that the next --resume trusts.
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        temporary.replace(path)


# ---------------------------------------------------------------------------
# Records
# ---------------------------------------------------------------------------


def iter_material_records(limit: int | None = None):
    """Every material record, as ``(collection_path, doc_id, data)``.

    Materials live in Firestore under ``users/{uid}/materials``. The Firebase
    Admin SDK's collection-group query walks them all without needing a list
    of user ids.
    """
    from firebase_admin import firestore

    client = firestore.client()
    query = client.collection_group("materials")
    if limit:
        query = query.limit(limit)

    for snapshot in query.stream():
        data = snapshot.to_dict() or {}
        yield snapshot.reference, snapshot.id, data


def stamp_provider(reference, provider: str) -> None:
    """Record which bucket now holds this file."""
    reference.update({FIELD: provider})


# ---------------------------------------------------------------------------
# One file
# ---------------------------------------------------------------------------


@dataclass
class FileOutcome:
    status: str  # already | copied | missing | no_path | failed
    detail: str = ""
    size: int = 0


def migrate_one(path: str, *, apply: bool) -> FileOutcome:
    """Copy one object, or report why it did not need copying."""
    if not path:
        return FileOutcome("no_path", "the record has no filePath")

    # Already there? A HEAD is far cheaper than a download, and this is what
    # makes a repeat run nearly free.
    try:
        existing_size = storage_service.object_size(path)
    except Exception as exc:
        # An outage here must not be read as "absent" -- that would re-upload
        # the whole library.
        return FileOutcome("failed", f"could not check B2: {type(exc).__name__}")

    source = legacy_storage.metadata(path)

    if existing_size is not None:
        if source is None or source["size"] == existing_size:
            return FileOutcome("already", "present in B2", existing_size)
        # Same key, different size. Do not overwrite on a guess: one of the
        # two is wrong and a human needs to say which.
        return FileOutcome(
            "failed",
            f"size mismatch: B2 has {existing_size} bytes, Firebase has {source['size']}",
        )

    if source is None:
        return FileOutcome("missing", "not found in the legacy bucket")

    if not apply:
        return FileOutcome("copied", "would copy (dry run)", source["size"])

    last_error = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            data = legacy_storage.download_bytes(path)
            if data is None:
                return FileOutcome("missing", "not readable from the legacy bucket")

            storage_service.upload_bytes(
                path, data, source.get("contentType") or "application/octet-stream"
            )

            # Read back rather than trusting the write. A truncated upload
            # that is never verified is a data-loss bug wearing a success
            # message.
            written = storage_service.object_size(path)
            if written is None:
                last_error = "upload reported success but the object is not there"
            elif written != len(data):
                last_error = f"wrote {written} bytes, expected {len(data)}"
            else:
                return FileOutcome("copied", "copied and verified", written)

        except Exception as exc:
            last_error = f"{type(exc).__name__}: {exc}"

        if attempt < MAX_ATTEMPTS:
            delay = RETRY_BACKOFF_SECONDS[min(attempt - 1, len(RETRY_BACKOFF_SECONDS) - 1)]
            logger.warning(
                "Attempt %s/%s failed for %s (%s); retrying in %.0fs",
                attempt, MAX_ATTEMPTS, path, last_error, delay,
            )
            time.sleep(delay)

    return FileOutcome("failed", last_error or "unknown failure")


# ---------------------------------------------------------------------------
# The run
# ---------------------------------------------------------------------------


def run(args: argparse.Namespace) -> int:
    state_path = Path(args.state)
    state = MigrationState.load(state_path) if args.resume else MigrationState()
    counters = state.counters if args.resume else Counters()

    mode = "APPLY" if args.apply else "DRY RUN"
    print("=" * 70)
    print(f"Firebase Storage -> Backblaze B2   [{mode}]")
    print("=" * 70)
    print(f"  destination   {storage_service.describe_active_storage()}")
    print(f"  legacy bucket {'configured' if legacy_storage.is_configured() else 'NOT CONFIGURED'}")
    print(f"  state file    {state_path}")
    if args.resume:
        print(f"  resuming with {len(state.done)} file(s) already done")
    if not args.apply:
        print("\n  Nothing will be written. Re-run with --apply to copy.")
    print("  Source objects are never deleted by this script.\n")

    if not legacy_storage.is_configured():
        print("FIREBASE_STORAGE_BUCKET is not set, so there is nothing to migrate from.")
        print("If migration is finished, that is the expected state.")
        return 0

    try:
        records = list(iter_material_records(limit=args.limit))
    except Exception as exc:
        print(f"Could not read material records: {type(exc).__name__}: {exc}")
        return 2

    print(f"Found {len(records)} material record(s).\n")

    for reference, doc_id, data in records:
        counters.scanned += 1
        path = str(data.get("filePath") or "").strip()

        if args.resume and path and path in state.done:
            continue

        outcome = migrate_one(path, apply=args.apply)
        label = f"{doc_id[:12]:<12} {path[:64]}"

        if outcome.status == "already":
            counters.already_in_b2 += 1
            state.done[path] = B2
            if args.apply and str(data.get(FIELD) or "") != B2:
                # Present in B2 but unlabelled: stamping it now is what stops
                # every future read having to probe.
                try:
                    stamp_provider(reference, B2)
                except Exception as exc:
                    logger.warning("Could not stamp %s: %s", doc_id, type(exc).__name__)
            print(f"  = {label}  already in B2")

        elif outcome.status == "copied":
            counters.copied += 1
            counters.bytes_copied += outcome.size
            if args.apply:
                state.done[path] = B2
                try:
                    stamp_provider(reference, B2)
                except Exception as exc:
                    logger.warning("Could not stamp %s: %s", doc_id, type(exc).__name__)
            verb = "would copy" if not args.apply else "copied"
            print(f"  + {label}  {verb} ({outcome.size:,} bytes)")

        elif outcome.status == "missing":
            counters.missing_in_firebase += 1
            print(f"  ? {label}  {outcome.detail}")

        elif outcome.status == "no_path":
            counters.skipped_no_path += 1
            print(f"  - {doc_id[:12]:<12} {outcome.detail}")

        else:
            counters.failed += 1
            if path:
                state.failed[path] = outcome.detail
            print(f"  ! {label}  FAILED: {outcome.detail}")

        state.counters = counters
        if args.apply:
            # After every file, so an interrupt costs one file of progress
            # rather than the whole run.
            state.save(state_path)

    print()
    print("=" * 70)
    print(f"Summary [{mode}]")
    for line in counters.as_lines():
        print(line)

    if state.failed:
        print("\n  Failures needing a human:")
        for path, detail in list(state.failed.items())[:20]:
            print(f"    {path}\n      {detail}")
        if len(state.failed) > 20:
            print(f"    ... and {len(state.failed) - 20} more")

    if not args.apply:
        print("\n  This was a dry run. Nothing was written.")
    else:
        print(f"\n  State written to {state_path}")
        print("  Source files remain in Firebase Storage. Deleting them is a")
        print("  separate, manual decision -- only after the app is verified")
        print("  to be serving every file from B2.")

    return 1 if counters.failed else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="actually copy. Without this the script only reports what it would do.",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="skip files a previous run already finished, per the state file.",
    )
    parser.add_argument("--state", default=str(DEFAULT_STATE), help="state file path")
    parser.add_argument("--limit", type=int, default=None, help="stop after N records")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
