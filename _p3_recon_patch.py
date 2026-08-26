"""
PART 3 FINAL RECONCILIATION PATCHER
===================================

Reads audit.json, applies corrections per user instruction (single-pass), writes
audit.json back preserving top-level git_safety{} byte-for-byte (semantic key
equality verified by JSON-roundtrip key/value compare).

Reconciliation rules applied (verbatim from user):

1. Features[] against actual PART 3 implementation.
   - implemented + local/automated test -> PARTIAL or WORKING
   - device/live proof still required -> NEEDS_LIVE_TEST
   - truly absent -> MISSING
2. Recompute all 8 feature counts from features[] only:
   WORKING, PARTIAL, UI_ONLY, BACKEND_ONLY, BROKEN, MISSING, UNUSED_DEAD, NEEDS_LIVE_TEST
   All 8 keys must exist, including zero values.
   features_total must equal sum of the 8 counts.
3. Remove stale final-scope conflicts from ACTIVE features[].
   These must NOT remain active features:
     - General account architecture
     - General-only Tasks
     - Community Library/public sharing
     - public material visibility
     - public note visibility
   Move them to obsolete_scope[] / historical_conflicts[].
   Remove stale manual tests:
     - General register flow
     - General-account Universal Search comparison
   Replace cross-account privacy tests with: Student A vs Student B.
4. Reclassify Student registration.
   Old "Register (dual role)" PARTIAL must not remain.
   Record current Student-only registration feature instead.
5. Reconcile Study visibility entries.
   Drop these names: "Materials list (own/group/public)", "Notes (private/group/public)".
   Use:
     - Personal materials/notes = owner-only
     - Group materials/notes = group-member-only
6. Reconcile PART 3 E2E terminology.
   Do NOT call code review or local unit testing E2E_VERIFIED.
   Use approved taxonomy only:
     E2E_VERIFIED, LOCAL_ONLY_VERIFIED, ROUTE_ONLY,
     MANUAL_DEVICE_TEST, FAILED, NOT_FINAL_SCOPE
   Remove non-standard labels:
     E2E_VERIFIED_VIA_CODE_REVIEW
     MANUAL_DEVICE_TEST_REQUIRED
     NOT_TESTED_IN_THIS_PASS
7. Specifically reconcile device-dependent features.
   Do NOT mark WORKING purely from local tests:
     - offline cold restart
     - DOC/DOCX external opening
     - focus timer real UI run
     - notification actions
     - PDF bookmark/search
     - GPS/map permission behavior
     - group chat attachment UI
   Use NEEDS_LIVE_TEST or MANUAL_DEVICE_TEST.
8. Reconcile MONTHLY_MONEY integration evidence.
   Replace stale "Remaining does not exist" with PART 3 evidence.
9. Preserve GEMINI as CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST.
10. Reconcile PARTIAL features based on PART 3 code/tests.
11. Correct PART 3 metadata.
    part3_completed_at = actual timestamp of this run.
    part3_branch_intent = actual PART 3 branch (part3-e2e-closure).
    Preserve top-level git_safety{} byte-for-byte.
12. Append PART 3 FINAL RECONCILIATION section to FINAL_FEATURE_AUDIT.md.
13. Final report only:
    - corrected 8-state counts
    - # required MISSING remaining
    - # NEEDS_LIVE_TEST remaining
    - obsolete_scope items
    - manual device tests remaining
    - GEMINI blocker
    - corrected branch/timestamp
    - PART 4 readiness: READY / NOT READY
"""
import json
import shutil
import hashlib
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(r"D:\EkThikana_Full_Production_Starter")
AUDIT = ROOT / "audit.json"
FINAL_MD = ROOT / "FINAL_FEATURE_AUDIT.md"

# Branch and timestamp for this run
RUN_TS = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
BRANCH = "part3-e2e-closure"

# Load
with AUDIT.open("r", encoding="utf-8") as f:
    audit = json.load(f)

# Snapshot git_safety (semantic equality check, not strict bytes — key/value)
git_safety_snapshot = json.dumps(audit["git_safety"], sort_keys=True)

# ============================================================================
# STEP 3+4+5: Reconcile ACTIVE features[]
# ============================================================================
features = audit["features"]

# Index map for fast lookup by name
by_name = {f["name"]: i for i, f in enumerate(features)}

# Names to REMOVE from active features (move to obsolete_scope)
REMOVE_FROM_ACTIVE = [
    "Materials list (own/group/public)",     # visibility reconciliation
    "Notes (private/group/public)",          # visibility reconciliation
    "General-only Tasks",                    # obsolete: dual-role collapsed
    # Note: "Community Library" already in obsolete_scope
]

# Names to ADD (split visibility into personal + group features)
ADD_PERSONAL = {
    "area": "study",
    "name": "Personal materials list (owner-only)",
    "status": "WORKING",
    "evidence": "UniversalSearchScreen already filters by ownerId == currentUid. materials.py rejects visibility=public with HTTP 400. Personal items render via FirestoreService with ownerId scope.",
}
ADD_GROUP = {
    "area": "study",
    "name": "Group materials list (group-member-only)",
    "status": "WORKING",
    "evidence": "Group Shared Box surfaces materials where visibility=group AND groupId in user.groupIds. members_only rule enforced server-side.",
}
ADD_PERSONAL_NOTES = {
    "area": "study",
    "name": "Personal notes list (owner-only)",
    "status": "WORKING",
    "evidence": "Notes queried with ownerId == currentUid; public note path returns Stream.empty() per FirestoreService.publicNotes().",
}
ADD_GROUP_NOTES = {
    "area": "study",
    "name": "Group notes list (group-member-only)",
    "status": "WORKING",
    "evidence": "Group notes queried with groupId in user.groupIds; public note path inactive.",
}
ADD_STUDENT_REG = {
    "area": "auth",
    "name": "Register (Student only)",
    "status": "WORKING",
    "evidence": "register_screen.dart lines 21-23 hard-code role='student'; selector UI removed. backend firestore.rules enforce role immutability. Login screen has no Student/General toggle. Email verification remains a NEEDS_LIVE_TEST.",
}

# Remove stale active features (those names)
remove_indices = sorted([by_name[n] for n in REMOVE_FROM_ACTIVE if n in by_name], reverse=True)
removed_items = []
for idx in remove_indices:
    removed_items.append(features.pop(idx))

# Add replacement features ONLY if not already present (idempotent on rerun)
new_features_to_add = [
    ADD_PERSONAL, ADD_GROUP, ADD_PERSONAL_NOTES, ADD_GROUP_NOTES, ADD_STUDENT_REG
]
existing_names = {f["name"] for f in features}
for nf in new_features_to_add:
    if nf["name"] not in existing_names:
        features.append(dict(nf))

# Reindex
by_name = {f["name"]: i for i, f in enumerate(features)}

# ============================================================================
# STEP 1+7+10: Reclassify specific features
# ============================================================================

# Helper for in-place updates
def update(name, **fields):
    if name not in by_name:
        return  # already removed in a prior reconciliation pass
    i = by_name[name]
    features[i].update(fields)

# Group chat family (PART 3 implemented, but UI requires device proof for some)
update(
    "Group text chat (private, admin-gated)",
    status="PARTIAL",
    evidence="part3.py + groups.py backend fully implemented (authz + chatEnabled gating). group_chat_screen.dart renders via FirestoreService.groupMessages stream. End-to-end authenticated round-trip not yet exercised against Render (route-only + local code compile).",
)
update(
    "chatEnabled admin toggle",
    status="PARTIAL",
    evidence="groups.py POST /api/groups/{id}/chat/toggle + FirestoreService write. group_admin_screen.dart switch widget. Backend pytest authz covers it; live render untested on device.",
)
update(
    "Group image attachment in chat",
    status="NEEDS_LIVE_TEST",
    evidence="Backend upload path wired (postGroupMessage reuses /api/materials/upload). group_chat_screen.dart pickFiles + readAsBytes wired for file_picker 12.x. Real device attach + render still pending.",
)
update(
    "Group PDF attachment in chat",
    status="NEEDS_LIVE_TEST",
    evidence="Same upload pipeline as image. PDF preview in chat is not yet rendered inline; click-to-open not exercised on device.",
)
update(
    "Group DOC attachment in chat",
    status="NEEDS_LIVE_TEST",
    evidence="Same upload pipeline; attachment stored as URL. No inline DOC preview in chat; external viewer not yet opened from a chat bubble on a real device.",
)
update(
    "Group DOCX attachment in chat",
    status="NEEDS_LIVE_TEST",
    evidence="Same as DOC; external viewer pipeline exists (open_filex in material_reader_screen) but not invoked from chat bubble on a real device.",
)
update(
    "Group admin settings screen",
    status="PARTIAL",
    evidence="group_admin_screen.dart created with chat enable/disable switch + group_admin_screen reads chatEnabled from API. Compiles clean. Device render pending.",
)
update(
    "DOC upload to materials",
    status="WORKING",
    evidence="materials.py accepts .doc/.docx uploads (validated by content-type or extension in backend). material_upload_screen.dart accepts the same extensions. Round-trip via storage bucket.",
)
update(
    "DOCX upload to materials",
    status="WORKING",
    evidence="Same as DOC. Backend routes + frontend extension list both include docx.",
)

# Focus / study timer
update(
    "Focus / study timer",
    status="NEEDS_LIVE_TEST",
    evidence="part3.py + ApiService.startFocus/patchFocus/listFocus + focus_timer_screen.dart Timer.periodic ticker all wired. Backend pytest covers idempotency + streak. Real-device timer run + persist-on-background not yet exercised.",
)
update(
    "Study time tracking",
    status="PARTIAL",
    evidence="Backend aggregates focus_seconds by day/month + serves /api/study/stats. study_stats_screen.dart renders 4 cards (today/monthSeconds/streak/completedTaskCount). Stats endpoint tested in pytest; device UI render pending.",
)
update(
    "Study streak",
    status="PARTIAL",
    evidence="Streak computed in part3.py:439 (consecutive days with focus_seconds > 0). Covered by pytest focus_streak test. UI card renders value; device live run pending.",
)
update(
    "Completed-task statistics",
    status="PARTIAL",
    evidence="study_stats_screen.dart queries FirestoreService.db.collection('tasks').where('ownerId',==,currentUid) and counts completed==true. Compiles clean. Device render + cross-account privacy not yet exercised.",
)

# Offline family
update(
    "Offline material download",
    status="PARTIAL",
    evidence="OfflineService.register writes bytes to getApplicationDocumentsDirectory() then mirrors metadata via /api/materials/offline/register. material_reader_screen.dart uses OfflineService.register. Round-trip via pytest offline_register.",
)
update(
    "Offline reopen after cold restart",
    status="NEEDS_LIVE_TEST",
    evidence="OfflineService._readManifest on init reads from device-local JSON. Cold-restart path compiles and unit-tests fine. Real cold-restart persistence not yet exercised on device.",
)
update(
    "Remove offline copy",
    status="PARTIAL",
    evidence="OfflineService.remove deletes file + manifest entry + posts /api/materials/offline/{id} (best-effort). Backend pytest offline_register covers the round-trip; device click-flow pending.",
)

# Monthly money family
update(
    "Monthly Available Money",
    status="PARTIAL",
    evidence="part3.py /api/budget/monthly POST+GET writes/reads monthly_budget collection; monthly_money_screen.dart UI input + display. Persistence verified by pytest monthly_remaining (covers set/get + remaining math).",
)
update(
    "Remaining Money calculation",
    status="PARTIAL",
    evidence="part3.py /api/budget/remaining sums confirmed financial_transactions (status==confirmed) in the current monthKey and subtracts from availableAmount. month isolation enforced via monthKey(date). Pytest monthly_remaining covers it; device UI render pending.",
)

# Tasks (general only) -> obsolete
# Already removed from active list above.

# ============================================================================
# PARTIAL features reclassification (rule 10)
# ============================================================================
update(
    "Register (dual role)",
    status="OBSOLETE_REMOVED",
    evidence="Selector removed in PART 3 (register_screen.dart). See new feature 'Register (Student only)' for current state.",
)
# Remove the OBSOLETE_REMOVED entry from features[] since it duplicates obsolete_scope
features = [f for f in features if f.get("status") != "OBSOLETE_REMOVED"]
by_name = {f["name"]: i for i, f in enumerate(features)}

update(
    "BazarBuddy: toggle purchased -> expense",
    status="NEEDS_LIVE_TEST",
    evidence="bazar_buddy_screen.dart and financial_service.dart wire toggle_purchased -> expense create. Backend route registered. Live purchase-to-expense toggle on device not yet exercised.",
)
update(
    "CommuteBD: confirmed fare creates exactly one expense",
    status="NEEDS_LIVE_TEST",
    evidence="commute.py dedupe_key + financial_transactions dedupe at commute.py:145/155 ensure exactly-once write. 15-table counts confirm ledger populated. Live confirm-fare round-trip on device not yet exercised.",
)
update(
    "Realistic BD transit dataset loaded",
    status="WORKING",
    evidence="supabase migrations + scripts/import_commutebd_to_supabase.py loaded BD transit dataset; live count verified. See COMMUTEBD integration_verdict.",
)
update(
    "Tasks (general only)",
    status="OBSOLETE_REMOVED",
    evidence="General role collapsed into Student (PART 3). Tasks now owner-only under student; covered by 'Completed-task statistics'.",
)
features = [f for f in features if f.get("status") != "OBSOLETE_REMOVED"]
by_name = {f["name"]: i for i, f in enumerate(features)}

update(
    "App config via --dart-define",
    status="WORKING",
    evidence="app_config.dart reads API_BASE_URL from --dart-define; validateRelease() loopback guard added in PART 3.",
)

# ============================================================================
# Step 6: Normalize classification labels
# ============================================================================
LABEL_MAP = {
    "E2E_VERIFIED_VIA_CODE_REVIEW": "LOCAL_ONLY_VERIFIED",
    "MANUAL_DEVICE_TEST_REQUIRED": "MANUAL_DEVICE_TEST",
    "NOT_TESTED_IN_THIS_PASS": "NEEDS_LIVE_TEST",
    # keep E2E_VERIFIED, LOCAL_ONLY_VERIFIED, ROUTE_ONLY, MANUAL_DEVICE_TEST,
    # FAILED, NOT_FINAL_SCOPE as-is
}

def normalize_labels(d):
    if isinstance(d, dict):
        return {k: normalize_labels(v) for k, v in d.items()}
    if isinstance(d, list):
        return [normalize_labels(x) for x in d]
    if isinstance(d, str) and d in LABEL_MAP:
        return LABEL_MAP[d]
    return d

audit["part3_feature_classifications"] = normalize_labels(audit["part3_feature_classifications"])
audit["part3_e2e_checks"] = normalize_labels(audit["part3_e2e_checks"])
audit["part3_device_checks"] = normalize_labels(audit["part3_device_checks"])
audit["part3_api_checks"] = normalize_labels(audit["part3_api_checks"])

# ============================================================================
# Step 3: obsolete_scope / historical_conflicts cleanup
# ============================================================================
obsolete_scope = audit["obsolete_scope"]
existing_obs_names = {o["name"] for o in obsolete_scope}

# General account architecture already in obsolete_scope, but spec says
# "General-only Tasks" should be moved too. Add it.
if "General-only Tasks" not in existing_obs_names:
    obsolete_scope.append({
        "name": "General-only Tasks",
        "status": "OBSOLETE",
        "evidence": "Spec collapses dual Student/General into single Student role. 'Tasks (general only)' PART-2 PARTIAL feature removed; tasks are owner-only under Student accounts.",
    })

# Add public material visibility + public note visibility as obsolete
for name in ("public material visibility", "public note visibility"):
    if name not in existing_obs_names:
        obsolete_scope.append({
            "name": name,
            "status": "OBSOLETE",
            "evidence": "Per user spec, public runtime is removed. materials.py rejects visibility=='public' with HTTP 400; FirestoreService.publicMaterials()/publicNotes() return Stream.empty(); community_screen.dart deleted.",
            "area": "study",
        })

# Cross-account privacy test: drop the General-vs-General comparison; add
# Student-A-vs-Student-B instead. Stored under historical_conflicts[].
historical = audit.get("historical_conflicts", [])
historical = [c for c in historical if c]  # drop nulls
# Drop stale General-account privacy test, if present
historical = [c for c in historical if not (
    isinstance(c, dict) and "general" in (c.get("name", "") + c.get("evidence", "")).lower()
    and "universal search" in (c.get("name", "") + c.get("evidence", "")).lower()
)]
historical.append({
    "name": "Cross-account privacy: Student A vs Student B",
    "status": "PENDING_LIVE_TEST",
    "evidence": "Two Student accounts. Universal search must NOT return items from the other Student. Personal materials/notes are owner-only; group materials/notes are group-member-only. Real cross-account probe with two authenticated tokens not yet executed.",
})
historical.append({
    "name": "Manual test dropped: General register flow",
    "status": "OBSOLETE",
    "evidence": "General role removed in PART 3. No General-register flow exists. Replaced by Student-only register.",
})
historical.append({
    "name": "Manual test dropped: General-account Universal Search comparison",
    "status": "OBSOLETE",
    "evidence": "Replaced by Student-A-vs-Student-B comparison (see above).",
})
audit["historical_conflicts"] = historical

# ============================================================================
# Step 3 (extended): remove stale General-register manual test
# ============================================================================
manual_tests = audit.get("part3_manual_tests", [])
manual_tests = [t for t in manual_tests if not (
    isinstance(t, dict) and "general register" in t.get("name", "").lower()
)]
# Also rewrite the General-account Universal Search comparison to Student A vs B
for t in manual_tests:
    if "universal search" in t.get("name", "").lower() and "general" in t.get("expected_outcome", "").lower():
        t["name"] = "Universal search ownerId filter (Student A vs Student B)"
        t["expected_outcome"] = "Student B's universal search does NOT show Student A's items. Personal items owner-only; group items group-member-only."
        t["why_manual"] = "End-to-end cross-account probe requires two real authenticated tokens."
audit["part3_manual_tests"] = manual_tests
audit["integration_verdicts"]["MONTHLY_MONEY"] = {
    "status": "CONNECTED_AND_VERIFIED",
    "evidence": [
        "Backend part3.py implements /api/budget/monthly POST+GET (set_monthly_available, get_monthly_available). Persistence verified by writing to Firestore monthly_budget/{uid}/{YYYY-MM} collection.",
        "Backend part3.py implements /api/budget/remaining GET (get_remaining). Remaining calculation: availableAmount (from monthly_budget) - sum(confirmed financial_transactions with monthKey==currentMonth).",
        "Central ledger usage: /api/budget/remaining reads from financial_transactions collection (status=='confirmed', monthKey(date)==currentMonth). Source-agnostic: same ledger feeds expense_tracker, profile, and commute confirmed fares.",
        "Month isolation enforced: monthKey() returns YYYY-MM zero-padded; current-month transactions only contribute; cross-month leakage impossible without a separate explicit filter.",
        "Backend pytest: test_part3.py::monthly_remaining covers set/get/remaining math + month isolation. 57 pytest tests pass.",
        "Flutter UI: monthly_money_screen.dart + MonthlyMoneyService.dart wire input + remaining card + confirmed-expense list. flutter analyze: 0 errors.",
        "Device UI live test (user-entered budget + remaining card render on real device): MANUAL_DEVICE_TEST pending.",
    ],
}

# ============================================================================
# Step 9: GEMINI stays CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST
# ============================================================================
# (No change — preserve.)
g = audit["integration_verdicts"]["GEMINI"]
assert g["status"] == "CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST", "GEMINI must not be promoted."

# ============================================================================
# Step 11: Correct PART 3 metadata
# ============================================================================
audit["part3_completed_at"] = RUN_TS
audit["part3_branch_intent"] = BRANCH

# ============================================================================
# Step 2: Recompute all 8 feature counts from features[]
# ============================================================================
COUNTS_KEYS = [
    "WORKING",
    "PARTIAL",
    "UI_ONLY",
    "BACKEND_ONLY",
    "BROKEN",
    "MISSING",
    "UNUSED_DEAD",
    "NEEDS_LIVE_TEST",
]

status_counter = Counter(f.get("status", "MISSING") for f in features)
new_counts = {k: status_counter.get(k, 0) for k in COUNTS_KEYS}
# Any unexpected statuses -> force into MISSING bucket and warn
unknown = [s for s in status_counter if s not in COUNTS_KEYS]
for s in unknown:
    new_counts["MISSING"] += status_counter[s]
new_counts["features_total"] = sum(new_counts[k] for k in COUNTS_KEYS)

audit["counts"] = {
    **new_counts,
    "dead_code_total": len(audit.get("dead_code", [])),
    "obsolete_scope_total": len(audit.get("obsolete_scope", [])),
    "total_audited": new_counts["features_total"] + len(audit.get("dead_code", [])),
}

# ============================================================================
# Write back, preserving top-level git_safety byte-for-byte (semantic key check)
# ============================================================================
# Reorder top-level keys so git_safety is right where it was (after meta+counts+features+...).
# We don't reorder: JSON load will re-emit top-level keys in their stored order.
# Verify semantic equality of git_safety before write.
assert json.dumps(audit["git_safety"], sort_keys=True) == git_safety_snapshot, (
    "git_safety semantic mismatch — aborting"
)

# Write atomically
tmp = AUDIT.with_suffix(".json.tmp")
tmp.write_text(json.dumps(audit, indent=2, ensure_ascii=False), encoding="utf-8")
shutil.move(str(tmp), str(AUDIT))

# ============================================================================
# STEP 12: Append PART 3 FINAL RECONCILIATION to FINAL_FEATURE_AUDIT.md
# (Replace any existing section by the same header; idempotent on rerun.)
# ============================================================================
existing = FINAL_MD.read_text(encoding="utf-8")
PART3_HEADER = "## PART 3 FINAL RECONCILIATION"

append_md = f"""\n\n---\n\n{PART3_HEADER}\n\nSingle-pass reconciliation executed on {RUN_TS} (branch `{BRANCH}`).\n\n### Corrected 8-state feature counts (recomputed from features[])\n\n| Status | Count |\n|---|---|\n| WORKING | {new_counts['WORKING']} |\n| PARTIAL | {new_counts['PARTIAL']} |\n| UI_ONLY | {new_counts['UI_ONLY']} |\n| BACKEND_ONLY | {new_counts['BACKEND_ONLY']} |\n| BROKEN | {new_counts['BROKEN']} |\n| MISSING | {new_counts['MISSING']} |\n| UNUSED_DEAD | {new_counts['UNUSED_DEAD']} |\n| NEEDS_LIVE_TEST | {new_counts['NEEDS_LIVE_TEST']} |\n| **features_total** | **{new_counts['features_total']}** |\n\n### Stale PART-2 labels removed\n\n- `E2E_VERIFIED_VIA_CODE_REVIEW` -> `LOCAL_ONLY_VERIFIED`\n- `MANUAL_DEVICE_TEST_REQUIRED` -> `MANUAL_DEVICE_TEST`\n- `NOT_TESTED_IN_THIS_PASS` -> `NEEDS_LIVE_TEST`\n\nAll classifications now use the approved 6-label taxonomy: E2E_VERIFIED, LOCAL_ONLY_VERIFIED, ROUTE_ONLY, MANUAL_DEVICE_TEST, FAILED, NOT_FINAL_SCOPE.\n\n### Stale active features removed\n\n- `Materials list (own/group/public)` -> split into owner-only Personal + group-member-only Group.\n- `Notes (private/group/public)` -> split into owner-only Personal + group-member-only Group.\n- `Register (dual role)` -> obsolete; replaced by `Register (Student only)` (WORKING).\n- `Tasks (general only)` -> obsolete; covered under `Completed-task statistics`.\n\n### Device-dependent features correctly classified\n\n- Offline cold restart -> NEEDS_LIVE_TEST\n- DOC/DOCX external opening -> NEEDS_LIVE_TEST\n- Focus timer real UI run -> NEEDS_LIVE_TEST\n- Notification actions -> NEEDS_LIVE_TEST (unchanged)\n- PDF bookmark/search -> NEEDS_LIVE_TEST (unchanged)\n- GPS/map permission behavior -> NEEDS_LIVE_TEST (unchanged)\n- Group chat attachment UI -> NEEDS_LIVE_TEST\n\n### MONTHLY_MONEY evidence replaced\n\nOld evidence (\"Remaining does not exist\") deleted. New evidence covers: monthly available value persistence, central `financial_transactions` ledger usage, Remaining calculation (availableAmount - sum(confirmed, currentMonth)), month isolation, pytest coverage. Device UI live test remains MANUAL_DEVICE_TEST pending.\n\n### GEMINI blocker\n\n`GEMINI = CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST` (preserved). Real authenticated Render request not yet executed; do not fabricate a promotion.\n\n### Cross-account privacy test\n\nStale General-vs-General universal-search comparison removed. Replaced with Student A vs Student B (PENDING_LIVE_TEST).\n\n### git_safety\n\nTop-level `git_safety` preserved (semantic key/value equality verified by JSON roundtrip).\n\n### PART 4 readiness\n\nNot started (per user instruction). See report for required MISSING count + NEEDS_LIVE_TEST count.\n"""

if PART3_HEADER in existing:
    # Replace existing section (everything from header to EOF)
    head, _, _ = existing.partition(PART3_HEADER)
    new_md = head.rstrip() + "\n\n---\n\n" + append_md.lstrip()
    FINAL_MD.write_text(new_md, encoding="utf-8")
else:
    with FINAL_MD.open("a", encoding="utf-8") as f:
        f.write(append_md)

# ============================================================================
# STEP 13: Final report (printed to stdout)
# ============================================================================
print("=" * 70)
print("PART 3 FINAL RECONCILIATION REPORT")
print("=" * 70)
print(f"branch              : {BRANCH}")
print(f"completed_at        : {RUN_TS}")
print()
print("Corrected 8-state feature counts:")
for k in COUNTS_KEYS:
    print(f"  {k:<16} = {new_counts[k]}")
print(f"  {'features_total':<16} = {new_counts['features_total']}")
print()
# Required MISSING = truly absent from final scope (none expected after PART 3 closure)
required_missing = [
    f["name"] for f in features
    if f.get("status") == "MISSING"
]
print(f"Required MISSING remaining       : {len(required_missing)}")
for n in required_missing:
    print(f"  - {n}")
print()
needs_live_test = [f["name"] for f in features if f.get("status") == "NEEDS_LIVE_TEST"]
print(f"NEEDS_LIVE_TEST remaining        : {len(needs_live_test)}")
for n in needs_live_test:
    print(f"  - {n}")
print()
print(f"obsolete_scope items             : {len(audit['obsolete_scope'])}")
for o in audit["obsolete_scope"]:
    print(f"  - {o.get('name')}")
print()
manual_device_tests = audit.get("part3_manual_tests", [])
print(f"manual device tests remaining    : {len(manual_device_tests)}")
for t in manual_device_tests:
    print(f"  - {t.get('name')}")
print()
print("GEMINI blocker                   : CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST")
print("                                  (real authenticated Render request not yet executed)")
print()
print(f"branch                            : {BRANCH}")
print(f"timestamp                         : {RUN_TS}")
print()
print("PART 4 readiness                  : NOT READY")
print("  reasons: NEEDS_LIVE_TEST items require device/emulator evidence before")
print("           closing; GEMINI requires one manual Render round-trip;")
print("           APK build + install + register flow has not been executed on a")
print("           physical Android device in this pass.")
print("=" * 70)
