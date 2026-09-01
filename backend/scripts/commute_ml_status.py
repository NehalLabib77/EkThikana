"""Print an honest account of the commute fare model's readiness.

    python scripts/commute_ml_status.py

There is no trained fare model in this project. This script exists so that
claim can be checked against the database rather than taken on trust: it reads
the real approved-report counts and prints them against the thresholds in
settings.

It reports "unknown" when the database cannot be reached. That is deliberate
-- "we have no reports" and "we cannot see how many reports we have" are
different facts, and only one of them is a reason to keep collecting.

Exit codes: 0 when the model is ready to train, 1 when it is not, 2 when
readiness could not be determined.
"""
from __future__ import annotations

import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from app.services.commute.ml_status import readiness  # noqa: E402

BAR_WIDTH = 34


def _bar(have: int, need: int) -> str:
    if need <= 0:
        return ""
    filled = min(BAR_WIDTH, int(BAR_WIDTH * have / need))
    return "[" + "#" * filled + "." * (BAR_WIDTH - filled) + "]"


def main() -> int:
    report = readiness()

    print("Commute fare model readiness")
    print("=" * 60)

    if not report["dataAvailable"]:
        print(f"  status     UNKNOWN ({report['reason']})")
        for blocker in report["blockers"]:
            print(f"  note       {blocker}")
        print()
        print(f"  fares today are {report['fareLabelInUse']}")
        return 2

    thresholds = report["thresholds"]
    total = report["totalApprovedReports"]
    need = thresholds["totalApprovedReports"]

    print(f"  status     {'READY TO TRAIN' if report['active'] else 'INACTIVE'}")
    print(f"  total      {total}/{need}  {_bar(total, need)}")

    per_mode = thresholds["perModeApprovedReports"]
    for mode, detail in report["modes"].items():
        have = detail["approvedReports"]
        print(f"  {mode:<10} {have}/{per_mode}  {_bar(have, per_mode)}")

    if report["blockers"]:
        print()
        print("  Blockers")
        for blocker in report["blockers"]:
            print(f"    - {blocker}")

    print()
    print(f"  fares today are {report['fareLabelInUse']}")
    print(f"  {report['note']}")

    return 0 if report["active"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
