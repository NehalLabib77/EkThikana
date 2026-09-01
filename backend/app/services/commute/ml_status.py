"""An honest account of whether the fare model is usable yet.

The fare model is *not* active, and this module exists so that fact can be
stated with numbers rather than asserted. It reports the approved-report count
the database actually holds against the thresholds in settings, names every
blocker, and never rounds a shortfall in the project's favour.

Two rules govern everything here:

  * **No fabricated readiness.** If the database cannot be reached, the answer
    is "unknown", not "zero" and certainly not "ready". A missing count and a
    count of nothing are different facts.
  * **No moving the goalposts.** The thresholds come from settings and are
    reported alongside the counts, so lowering one to manufacture a green
    light shows up plainly in the output.

Read it from ``GET /api/commute/ml-status`` or from
``scripts/commute_ml_status.py``.
"""
from __future__ import annotations

from typing import Any

from app.core.config import get_settings
from app.services.commute.crowd import CrowdFareRepository

#: Only these modes have market-negotiated fares, so only these could ever
#: justify a model. Bus and metro fares are published; predicting them would
#: replace a known number with a guess.
MODELLED_MODES: tuple[str, ...] = ("rickshaw", "cng")


def readiness(crowd: CrowdFareRepository | None = None) -> dict[str, Any]:
    """Report how far the fare model is from being trainable.

    ``dataAvailable`` false means the counts below are unknown, not zero.
    """
    settings = get_settings()
    repository = crowd or CrowdFareRepository()

    min_total = int(settings.commute_ml_min_total_reports)
    min_mode = int(settings.commute_ml_min_mode_reports)

    if not repository.enabled:
        return {
            "active": False,
            "dataAvailable": False,
            "reason": "database_unavailable",
            "thresholds": {"totalApprovedReports": min_total, "perModeApprovedReports": min_mode},
            "blockers": [
                "The report database is not configured, so the approved-report "
                "count cannot be read. Model readiness is unknown, not zero."
            ],
            "modes": {},
            "fareLabelInUse": "rule-based and crowdsourced estimates only",
        }

    counts_known = True
    try:
        total_approved = int(repository.count_approved() or 0)
    except Exception:
        counts_known = False
        total_approved = 0

    modes: dict[str, Any] = {}
    if counts_known:
        for mode in MODELLED_MODES:
            try:
                approved = int(repository.count_approved(mode=mode) or 0)
            except Exception:
                counts_known = False
                break
            modes[mode] = {
                "approvedReports": approved,
                "required": min_mode,
                "shortfall": max(0, min_mode - approved),
                "ready": approved >= min_mode,
            }

    if not counts_known:
        return {
            "active": False,
            "dataAvailable": False,
            "reason": "count_query_failed",
            "thresholds": {"totalApprovedReports": min_total, "perModeApprovedReports": min_mode},
            "blockers": [
                "The approved-report count could not be queried. Model "
                "readiness is unknown, not zero."
            ],
            "modes": {},
            "fareLabelInUse": "rule-based and crowdsourced estimates only",
        }

    blockers: list[str] = []
    if total_approved < min_total:
        blockers.append(
            f"{total_approved} approved reports in total; {min_total} are "
            f"required ({min_total - total_approved} short)."
        )
    for mode, detail in modes.items():
        if not detail["ready"]:
            blockers.append(
                f"{detail['approvedReports']} approved {mode} reports; "
                f"{min_mode} are required ({detail['shortfall']} short)."
            )

    active = not blockers

    return {
        "active": active,
        "dataAvailable": True,
        "reason": None if active else "insufficient_training_data",
        "totalApprovedReports": total_approved,
        "thresholds": {"totalApprovedReports": min_total, "perModeApprovedReports": min_mode},
        "modes": modes,
        "blockers": blockers,
        # Stated explicitly so nobody has to read the fare engine to find out
        # what the numbers a student sees are actually based on today.
        "fareLabelInUse": (
            "quantile model on approved reports"
            if active
            else "rule-based and crowdsourced estimates only"
        ),
        "note": (
            "Fares shown in the app are labelled official, crowdsourced, "
            "historical or estimated according to their real source. No fare "
            "is ever labelled as a model prediction unless a trained model "
            "produced it."
        ),
    }


def summary_line(report: dict[str, Any]) -> str:
    """One line for a log or a console, saying only what is known."""
    if not report.get("dataAvailable"):
        return "commute fare model: readiness unknown (report database unavailable)"
    if report.get("active"):
        return (
            "commute fare model: active "
            f"({report.get('totalApprovedReports')} approved reports)"
        )
    thresholds = report.get("thresholds", {})
    return (
        "commute fare model: inactive -- "
        f"{report.get('totalApprovedReports')}/{thresholds.get('totalApprovedReports')} "
        "approved reports"
    )


__all__ = ["MODELLED_MODES", "readiness", "summary_line"]
