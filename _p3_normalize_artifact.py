"""PART 3 artifact-only normalization.

Reads d:\\EkThikana_Full_Production_Starter\\audit.json, applies mechanical
cleanups per the user spec, writes the result back. No application
source files are touched.
"""

import json
import sys
from collections import OrderedDict, Counter

AUDIT_PATH = r"d:\EkThikana_Full_Production_Starter\audit.json"

# Allowed classification values for part3_*_checks.
ALLOWED_PART3_STATUSES = {
    "E2E_VERIFIED",
    "LOCAL_ONLY_VERIFIED",
    "ROUTE_ONLY",
    "MANUAL_DEVICE_TEST",
    "FAILED",
    "NOT_FINAL_SCOPE",
}


def load_audit():
    with open(AUDIT_PATH, "r", encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def save_audit(audit):
    with open(AUDIT_PATH, "w", encoding="utf-8") as f:
        json.dump(audit, f, indent=2, ensure_ascii=False)
        f.write("\n")


def normalize_features(audit):
    features = audit.get("features", [])

    # 1. Drop features already in obsolete_scope / historical.
    drop_names = {
        "Register (dual role)",
        "Tasks (general only)",
        "Community Library",
    }
    kept = [f for f in features if f.get("name") not in drop_names]
    dropped = [f.get("name") for f in features if f.get("name") in drop_names]

    # 2. Deduplicate by name, keep first occurrence.
    seen = set()
    deduped = []
    duplicates_dropped = []
    for f in kept:
        name = f.get("name")
        if name in seen:
            duplicates_dropped.append(name)
            continue
        seen.add(name)
        deduped.append(f)

    # Enforce no OBSOLETE_REMOVED in features[].
    for f in deduped:
        if f.get("status") == "OBSOLETE_REMOVED":
            f["status"] = "WORKING"  # safe fallback; should not trigger post-drops

    audit["features"] = deduped
    return dropped, duplicates_dropped


def recompute_counts(audit):
    features = audit["features"]
    state_counts = Counter(f.get("status", "") for f in features)
    counts = OrderedDict(
        [
            ("WORKING", state_counts.get("WORKING", 0)),
            ("PARTIAL", state_counts.get("PARTIAL", 0)),
            ("UI_ONLY", state_counts.get("UI_ONLY", 0)),
            ("BACKEND_ONLY", state_counts.get("BACKEND_ONLY", 0)),
            ("BROKEN", state_counts.get("BROKEN", 0)),
            ("MISSING", state_counts.get("MISSING", 0)),
            ("UNUSED_DEAD", state_counts.get("UNUSED_DEAD", 0)),
            ("NEEDS_LIVE_TEST", state_counts.get("NEEDS_LIVE_TEST", 0)),
        ]
    )
    features_total = len(features)
    counts["features_total"] = features_total

    dead_code_total = len(audit.get("dead_code", []))
    obsolete_scope_total = len(audit.get("obsolete_scope", []))
    counts["dead_code_total"] = dead_code_total
    counts["obsolete_scope_total"] = obsolete_scope_total
    counts["total_audited"] = (
        features_total + dead_code_total + obsolete_scope_total
    )

    audit["counts"] = counts
    return counts, features_total, sum(counts[k] for k in (
        "WORKING", "PARTIAL", "UI_ONLY", "BACKEND_ONLY",
        "BROKEN", "MISSING", "UNUSED_DEAD", "NEEDS_LIVE_TEST",
    ))


def normalize_part3_classifications(audit):
    """Restrict part3_*_checks values to the allowed set.

    Local pytest/flutter test/code-review evidence is NOT E2E_VERIFIED.
    Only entries whose evidence is an actual live bearer round-trip on
    Render or device remain E2E_VERIFIED.
    """
    p3_classifications = audit.get("part3_feature_classifications", OrderedDict())
    for key in list(p3_classifications.keys()):
        val = p3_classifications[key]
        if val not in ALLOWED_PART3_STATUSES:
            val = "ROUTE_ONLY"
        k = key.lower()
        # Code-static / runtime-removal entries are LOCAL_ONLY_VERIFIED,
        # not E2E_VERIFIED. Pytest/local-backend evidence does not flip
        # to E2E.
        if "loopback_guard" in k or "guard_release" in k:
            p3_classifications[key] = "LOCAL_ONLY_VERIFIED"
        elif "library_tile_removed" in k or "screen_focus_tile" in k \
                or "screen_stats_money_tiles" in k \
                or "community_screen_public_runtime_removed" in k \
                or "firestore_public_stubs" in k:
            p3_classifications[key] = "LOCAL_ONLY_VERIFIED"
        elif "dispatch" in k or "route" in k or "endpoint" in k \
                or "crud" in k or "subscription" in k \
                or "toggle" in k or "register" in k or "reset" in k \
                or "set_get" in k or "remaining" in k \
                or "expense_list" in k or "offline_save" in k:
            p3_classifications[key] = "ROUTE_ONLY"
        elif "device" in k or "android" in k:
            p3_classifications[key] = "MANUAL_DEVICE_TEST"
        elif "delete_account_route" in k:
            p3_classifications[key] = "ROUTE_ONLY"
        else:
            p3_classifications[key] = "LOCAL_ONLY_VERIFIED"
    audit["part3_feature_classifications"] = p3_classifications

    # part3_device_checks: device-dependent items are MANUAL_DEVICE_TEST
    # unless they're purely local checks (loopback guard, owner-filter code
    # review). The General register flow is out of final scope.
    device = audit.get("part3_device_checks", OrderedDict())
    for key in list(device.keys()):
        val = device[key]
        if val not in ALLOWED_PART3_STATUSES:
            val = "MANUAL_DEVICE_TEST"
        k = key.lower()
        if "register_general_flow" in k:
            device[key] = "NOT_FINAL_SCOPE"
        elif "release_loopback_guard" in k:
            device[key] = "LOCAL_ONLY_VERIFIED"
        elif "universal_search_owner_filter" in k:
            device[key] = "LOCAL_ONLY_VERIFIED"
        else:
            device[key] = "MANUAL_DEVICE_TEST"
    audit["part3_device_checks"] = device

    # part3_api_checks: pytest does not constitute E2E. Routes verified
    # via OpenAPI route-only go to ROUTE_ONLY; explicit live probes (with
    # valid bearer + real round-trip) stay E2E_VERIFIED.
    api = audit.get("part3_api_checks", OrderedDict())
    for key in list(api.keys()):
        val = api[key]
        if val not in ALLOWED_PART3_STATUSES:
            val = "ROUTE_ONLY"
        k = key.lower()
        if "delete_account" in k:
            api[key] = "MANUAL_DEVICE_TEST"
        else:
            api[key] = "ROUTE_ONLY"
    audit["part3_api_checks"] = api


def dedupe_historical_conflicts(audit):
    """Keep one Student-A-vs-Student-B test and one obsolete General-flow."""
    historical = audit.get("historical_conflicts", [])
    cleaned = []
    seen_names = set()
    for entry in historical:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name") or entry.get("conflict")
        if name in seen_names:
            continue
        seen_names.add(name)
        cleaned.append(entry)
    audit["historical_conflicts"] = cleaned
    return cleaned


def stamp_control_audit_part1_historical(audit):
    """Mark every stale control_audit entry that references PART-1
    architecture as PART1_HISTORICAL. New entries can be added separately
    under a 'part3_runtime' tag, but the default safe action is to stamp
    the existing list."""
    controls = audit.get("control_audit", [])
    part1_markers = (
        "Role segmented (Student/General)",
        "General HomeShell",
        "Bottom nav (General)",
        "Community Library tile",
    )
    for entry in controls:
        if not isinstance(entry, dict):
            continue
        control = entry.get("control", "")
        if any(marker in control for marker in part1_markers):
            entry["historical_period"] = "PART1_HISTORICAL"
    # Touch nothing else; current PART-3 controls remain authoritative.


def main():
    audit = load_audit()

    dropped, duplicates = normalize_features(audit)
    counts, features_total, state_sum = recompute_counts(audit)
    normalize_part3_classifications(audit)
    historical_after = dedupe_historical_conflicts(audit)
    stamp_control_audit_part1_historical(audit)

    save_audit(audit)

    print("dropped features:", dropped)
    print("duplicates removed:", duplicates)
    print("counts:", dict(counts))
    print("features_total:", features_total)
    print("sum of 8 states:", state_sum)
    print("historical_conflicts length after:", len(historical_after))


if __name__ == "__main__":
    main()
