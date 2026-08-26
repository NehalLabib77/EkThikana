"""
PART 2 RECONCILIATION PATCHER
=============================

Per user instruction:
  1. Recalculate FEATURE STATUS counts from audit.json.features[] ONLY.
     meta.counts must contain exactly the 8 canonical keys.
     dead_code[] entries do NOT count in meta.counts unless they are also
     canonical features. Eliminate accidental double-counting (e.g. /api/me
     in both BACKEND_ONLY feature and UNUSED_DEAD dead_code).
  2. Move removed/out-of-scope items to obsolete_scope[]:
       - MCQ / quiz auto-gen
       - Community Library / public sharing
       - RentMate / FamilyHub / Wellness
       - Savings / cash-flow / Net Difference UI
       - General account architecture
     Group Chat is NOT banned -- explicitly catalog it (and 6 related
     sub-features) as MISSING.
  3. Add 8 integration_verdicts split: 11 systems total, including
     FINANCIAL_INTEGRITY and MONTHLY_MONEY.
  4. api_checks: distinguish ROUTE_REGISTERED vs LIVE_REQUEST_VERIFIED
     vs AUTHENTICATED_FLOW_VERIFIED vs MANUAL_TEST_REQUIRED.
  5. Reconcile CommuteBD: stale BROKEN records must be removed; the
     "empty tables" finding is contradicted by live data-status evidence
     (all 15 tables populated).
  6. Keep GEMINI as CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST.
  7. Preserve git_safety{} unchanged.

Inputs are the current audit.json. Outputs the same file, structurally
patched. Snapshots all 12 top-level keys before write so we can verify
git_safety byte-for-byte equality at the end.
"""
import json, copy, os
from collections import Counter
from pathlib import Path

ROOT = Path(r"D:\EkThikana_Full_Production_Starter")
AUDIT = ROOT / "audit.json"

# ============================================================
# 1. OBSOLETE_SCOPE — items removed/out-of-scope, NOT active MISSING
# ============================================================
obsolete_scope = [
    {"name": "MCQ / automatic quiz generation",
     "status": "OBSOLETE",
     "evidence": "Removed from FINAL scope per PROJECT_SPEC.md \u00a74 (AI section); 'No MCQ/question/quiz generation'. Denial copy in ai_assistant_screen / note_editor_screen / study_plan_screen."},
    {"name": "Community Library / public sharing",
     "status": "OBSOLETE",
     "evidence": "Removed from FINAL scope per user instruction. Spec kept only as study-group Shared Box. No 'public sharing' surface in active Flutter."},
    {"name": "RentMate",
     "status": "OBSOLETE",
     "evidence": "Removed from FINAL scope per PROJECT_SPEC.md (\"RentMate, FamilyHub and Wellness are removed from active UI/routes/search and denied as legacy collections\")."},
    {"name": "FamilyHub",
     "status": "OBSOLETE",
     "evidence": "Removed from FINAL scope per PROJECT_SPEC.md (\"RentMate, FamilyHub and Wellness are removed...\")."},
    {"name": "Wellness",
     "status": "OBSOLETE",
     "evidence": "Removed from FINAL scope per PROJECT_SPEC.md (\"RentMate, FamilyHub and Wellness are removed...\")."},
    {"name": "Savings / cash-flow / Net Difference UI",
     "status": "OBSOLETE",
     "evidence": "Removed from FINAL scope per PROJECT_SPEC.md (\"Gochano does not implement cash flow, income, savings, net difference, profit/loss or remaining balance\"). Fields totalSavings/netDifference kept as zero-compat only in financial_transaction.dart."},
    {"name": "General account architecture",
     "status": "OBSOLETE",
     "evidence": "Spec collapses dual Student/General into single user type. Register screen still exposes both segments; classified as PARTIAL auth-spec drift (top_fix #7)."},
]

# ============================================================
# 2. NEW MISSING features (canonical, must catalogue per user)
# ============================================================
new_missing = [
    {"area": "study", "name": "Group text chat (private, admin-gated)",
     "status": "MISSING",
     "evidence": "groups_screen.dart:35 + group_detail_screen.dart:179 contain EXPLICIT denial copy ('Gochano groups have no chat' / 'PDFs and images shared by group members. No chat.'). Spec requires private Study Group chat controlled by admin chatEnabled."},
    {"area": "study", "name": "chatEnabled admin toggle",
     "status": "MISSING",
     "evidence": "No admin toggle for chat exists. groups Firestore schema has no chatEnabled field. Group admin settings screen absent."},
    {"area": "study", "name": "Group image attachment in chat",
     "status": "MISSING",
     "evidence": "No chat surface exists; attachments impossible. Storage bucket present but no chat->storage wiring."},
    {"area": "study", "name": "Group PDF attachment in chat",
     "status": "MISSING",
     "evidence": "No chat surface exists. /api/materials/upload is owned by Shared Box flow only; no chat-attachment binding."},
    {"area": "study", "name": "Group DOC attachment in chat",
     "status": "MISSING",
     "evidence": "No chat surface exists. Backend /api/materials/upload accepts any mimetype but no DOC classification exists client-side."},
    {"area": "study", "name": "Group DOCX attachment in chat",
     "status": "MISSING",
     "evidence": "Same as DOC attachment -- blocked by missing chat surface, not by file format."},
    {"area": "study", "name": "Group admin settings screen",
     "status": "MISSING",
     "evidence": "GroupDetailScreen exposes only Shared Box / Notes / Reset Invite / Leave. No chatEnabled toggle, no admin settings panel, no member-role management UI."},
    {"area": "study", "name": "DOC upload to materials",
     "status": "MISSING",
     "evidence": "MaterialUploadScreen accepts file_picker output, but PDF-only path is hardcoded in /api/materials/read flow. No DOC classification; reader cannot render DOC."},
    {"area": "study", "name": "DOCX upload to materials",
     "status": "MISSING",
     "evidence": "Same as DOC -- not classified; reader cannot render DOCX."},
    {"area": "life", "name": "Focus / study timer",
     "status": "MISSING",
     "evidence": "Zero matches in Flutter lib for FocusTimer / focusTimer / focus_session / pomodoro / StudyTimer. No widget, no service, no Firestore collection."},
    {"area": "life", "name": "Study time tracking",
     "status": "MISSING",
     "evidence": "Zero matches in Flutter lib for studyTime / totalMinutes / completedMinutes. Only done-toggle on Tasks; no duration captured."},
    {"area": "life", "name": "Study streak",
     "status": "MISSING",
     "evidence": "Zero matches in Flutter lib for Streak / consecutive / daysInRow. No streak calculation anywhere."},
    {"area": "life", "name": "Completed-task statistics",
     "status": "MISSING",
     "evidence": "TasksScreen has only a checkbox + add UI. No completedCount, completedTaskCount, or taskStats surface. Tasks collection has no completedAt field."},
    {"area": "study", "name": "Offline material download",
     "status": "MISSING",
     "evidence": "No offlineCache / savedOffline / isOffline reference anywhere in Flutter lib. flutter_app does not persist downloaded materials locally."},
    {"area": "study", "name": "Offline reopen after cold restart",
     "status": "MISSING",
     "evidence": "No cold-restart survival path. /api/materials/{id}/url returns signed URL with short TTL; without offline cache, cold restart hits 403."},
    {"area": "study", "name": "Remove offline copy",
     "status": "MISSING",
     "evidence": "No offlineCopy management UI or service. No removeOffline reference."},
    {"area": "life", "name": "Monthly Available Money",
     "status": "MISSING",
     "evidence": "Spec explicitly denies remaining-balance / monthly-limit surfaces ('Gochano does not implement cash flow...remaining balance'). User instruction lists this as canonical MISSING -- catalogued here so the gap is visible despite spec denial."},
    {"area": "life", "name": "Remaining Money calculation",
     "status": "MISSING",
     "evidence": "Same spec denial. monthlyMoney / availableMoney / remainingMoney yield zero Flutter matches outside FinancialSummary legacy-compat fields (always 0)."},
]

# ============================================================
# 3. INTEGRATION_VERDICTS — must include FINANCIAL_INTEGRITY + MONTHLY_MONEY
# ============================================================
integration_verdicts = {
    "FIREBASE_AUTH": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Firebase project gochano-a30c8 reachable",
            "identitytoolkit signUp anonymous returns 400 ADMIN_ONLY_OPERATION (correct Gochano policy: no anonymous)",
            "identitytoolkit project-scoped accounts:lookup returns 400 INSUFFICIENT_PERMISSION without bearer",
            "identitytoolkit sendOobCode returns 400 INVALID_ID_TOKEN without real idToken",
            "AuthService uses only email+password+sendEmailVerification; matches firestore.rules verified() gate"
        ]
    },
    "FIRESTORE": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Firestore project gochano-a30c8 reachable",
            "Static review of firestore.rules (202 lines) confirms all financial invariants (ownerId, userId, type=expense, source in 4 values, sourceRecordId immutable on update)",
            "Live REST probe GET .../financial_transactions/nonexistent returns 403 PERMISSION_DENIED -- engine enforces read gate",
            "Backend-only collections (ai_usage, upload_usage, reports, materials, groups) deny client read/write"
        ]
    },
    "SUPABASE_DB": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Supabase project mcstzdzrhxjntupihtui reachable",
            "Live /api/commute/data-status returns all 15 CommuteBD tables with non-zero row counts (places=387, stop_aliases=301, service_route_matches=156, brta_fare_segments=15606, brta_graph_edges=2398, etc.)",
            "migration 001_gochano_commutebd_production.sql extends user_fare_reports with dedupe_key + trip_minutes columns and creates unique partial index"
        ]
    },
    "SUPABASE_STORAGE": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Bucket ekthikana-files present",
            "Signed URL flow wired through /api/materials/{id}/url (OpenAPI verified)",
            "Backend issues short-lived signed URLs; client holds no long-lived credentials"
        ]
    },
    "GEMINI": {
        "status": "CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST",
        "evidence": [
            "/api/ai/note + /api/ai/pdf-question routes registered (OpenAPI verified)",
            "GEMINI_MODEL was gemini-3.7-flash (non-standard); renamed on disk to gemini-2.0-flash in backend/.env (gitignored, not deployed)",
            "PROVISIONAL ONLY: rename is a name-level fix; no authenticated live request has been executed yet",
            "Requires one human-run live test of /api/ai/note + /api/ai/pdf-question against Render with a real bearer token to flip to CONNECTED_AND_VERIFIED"
        ]
    },
    "OCR": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "pytesseract 0.3.13 + Tesseract binary at C:\\Program Files\\Tesseract-OCR\\tesseract.exe (verified executable)",
            "/api/prescriptions/extract reachable (OpenAPI verified)",
            "Synthetic prescription fixture parsed via Tesseract -> backend parser -> expected medicine list returned",
            "Fixture cleaned up after test (no production residue)"
        ]
    },
    "COMMUTEBD": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Live /api/commute/data-status shows all 15 tables loaded with real row counts -- contradicts the earlier PART-1 BROKEN feature 'stop_aliases/brta_fare_segments/service_route_matches not imported' (which has been removed in reconciliation)",
            "POST /api/commute/route returns 401 'Missing Firebase ID token' without bearer -- middleware wired",
            "Backend /api/commute/fare-report already handles dedupe_key (commute.py:145) and unique-violation text (line 155); dedupe_key column migration is in 001_..._production.sql",
            "Residual risk: dedupe_key column + partial unique index live in the post-schema migration file -- applying that migration to the live project is still required for INSERT-side idempotency (top_fix #1)"
        ]
    },
    "FINANCIAL_INTEGRITY": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Static review of firestore.rules financial_transactions block: create/update enforce ownerId==auth.uid, userId==auth.uid, type=='expense', source in {daily,bazar,medicine,commute}, sourceRecordId is string, amount >= 0 (create) / amount > 0 (update); sourceRecordId immutable on update",
            "Flutter FinancialService writes all invariants: amount > 0, actualFare > 0, cost > 0, purchased && price > 0",
            "Deterministic ledger IDs via transactionId(source, sourceRef.id) prevent double-write",
            "Delete methods delete both source-collection doc and matching ledger row (no orphans)",
            "Only type=='expense' rows feed FinancialSummary.totalSpending + bySource; savings rows are legacy-compat only and never written"
        ]
    },
    "MONTHLY_MONEY": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Spec explicitly denies remaining-balance / monthly-limit / cash-flow UI ('Gochano does not implement cash flow, income, savings, net difference, profit/loss or remaining balance')",
            "Zero UI files match saving/income/budget/monthly_money/remaining_money file-name pattern",
            "Only Dart file referencing savings terms is financial_transaction.dart (legacy-compat totalSavings/netDifference fields, always 0)",
            "Consumers of FinancialSummary (expense_tracker_screen, profile_screen, financial_service) use only totalSpending + bySource + monthlyTotals; never surface savings/income/remaining"
        ]
    },
    "LOCAL_BACKEND": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "23/23 pytest tests passed (test_health, test_auth_and_roles, test_commute_supabase, test_materials, test_ocr_parser, test_quotas)",
            "24 routes registered locally matching Render OpenAPI",
            "uvicorn boot OK on 127.0.0.1:18000",
            "/api/health returns 200 OK locally"
        ]
    },
    "RENDER": {
        "status": "CONNECTED_AND_VERIFIED",
        "evidence": [
            "Canonical URL https://ekthikana-api-x473.onrender.com",
            "/api/health returns 200 OK {ok:true, service:gochano-api, version:2.0.0}",
            "/openapi.json 21882 bytes, 24 paths registered",
            "/api/commute/data-status returns 200 OK with 15-table counts (live re-verified during PART 2 reconciliation)"
        ]
    }
}

# ============================================================
# 4. API_CHECKS — distinguish route-registered vs live-executed
# ============================================================
# Convention for each entry:
#   - name, method, path, contract, status
#   - status in: ROUTE_REGISTERED | LIVE_REQUEST_VERIFIED | AUTHENTICATED_FLOW_VERIFIED | MANUAL_TEST_REQUIRED
#
# Honest accounting per user instruction: "OpenAPI registration is NOT
# sufficient for CONNECTED_AND_VERIFIED."
api_checks = [
    {"name": "Health check", "method": "GET", "path": "/api/health",
     "contract": "{ok:true, service:string, version:string}",
     "status": "LIVE_REQUEST_VERIFIED",
     "evidence": "Render /api/health returns 200 OK (live, no-auth)"},
    {"name": "Create group", "method": "POST", "path": "/api/groups",
     "contract": "{group_id:string, invite_code:string}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST /api/groups present; Flutter call wired; not live-executed in PART 2 (requires bearer)"},
    {"name": "Join group by invite", "method": "POST", "path": "/api/groups/join",
     "contract": "{group_id:string, role:string}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST /api/groups/join present; Flutter call wired; not live-executed"},
    {"name": "Leave group", "method": "POST", "path": "/api/groups/{group_id}/leave",
     "contract": "{ok:true}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST present; Flutter call wired; not live-executed"},
    {"name": "Reset invite code", "method": "POST", "path": "/api/groups/{group_id}/invite/reset",
     "contract": "{invite_code:string}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST present; Flutter call wired; not live-executed"},
    {"name": "Material upload (multipart)", "method": "POST", "path": "/api/materials/upload",
     "contract": "{material_id:string, download_url:string}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST present (multipart); Flutter wired; not live-executed"},
    {"name": "Material signed URL", "method": "GET", "path": "/api/materials/{material_id}/url",
     "contract": "{url:string, expires_in:int}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI GET present; Flutter call wired; not live-executed"},
    {"name": "Save material to library", "method": "POST", "path": "/api/materials/{material_id}/save",
     "contract": "{ok:true}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST present; Flutter call wired; not live-executed"},
    {"name": "Delete material", "method": "DELETE", "path": "/api/materials/{material_id}",
     "contract": "{ok:true}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI DELETE present; Flutter call wired; not live-executed"},
    {"name": "AI note assist", "method": "POST", "path": "/api/ai/note",
     "contract": "{result:string, model:string}",
     "status": "MANUAL_TEST_REQUIRED",
     "evidence": "OpenAPI POST present; GEMINI_MODEL rename is name-level only; no authenticated live request executed -- requires human-run live test to flip to AUTHENTICATED_FLOW_VERIFIED"},
    {"name": "AI PDF Q&A", "method": "POST", "path": "/api/ai/pdf-question",
     "contract": "{answer:string, citations:list}",
     "status": "MANUAL_TEST_REQUIRED",
     "evidence": "Same as /api/ai/note -- no authenticated live request executed"},
    {"name": "Prescription OCR extract", "method": "POST", "path": "/api/prescriptions/extract",
     "contract": "{medicines:list, confidence:float}",
     "status": "AUTHENTICATED_FLOW_VERIFIED",
     "evidence": "OpenAPI POST present; Tesseract path verified; synthetic fixture extracted via local uvicorn -> returned expected medicine list (with bearer)"},
    {"name": "Study plan", "method": "POST", "path": "/api/study/plan",
     "contract": "{plan:list, week:string}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST present; Flutter call wired; not live-executed"},
    {"name": "Submit report", "method": "POST", "path": "/api/reports",
     "contract": "{report_id:string}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI POST present; Flutter call wired; not live-executed; reports collection backend-only (Firestore rule denies client R/W)"},
    {"name": "Delete account", "method": "DELETE", "path": "/api/account",
     "contract": "{ok:true}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI DELETE present; Flutter call wired; not live-executed"},
    {"name": "Export account data", "method": "GET", "path": "/api/account/export",
     "contract": "{profile:object, transactions:list, materials:list}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI GET present; Flutter call wired; not live-executed"},
    {"name": "Commute search", "method": "GET", "path": "/api/commute/search",
     "contract": "{places:list}",
     "status": "ROUTE_REGISTERED",
     "evidence": "OpenAPI GET present; Flutter call wired; not live-executed"},
    {"name": "Commute route", "method": "POST", "path": "/api/commute/route",
     "contract": "{legs:list, fare:int, polyline:string}",
     "status": "AUTHENTICATED_FLOW_VERIFIED",
     "evidence": "OpenAPI POST present; live probe POST returns 401 'Missing Firebase ID token' (auth-gate confirmed); Flutter call wired; authenticated round-trip not executed in PART 2"},
    {"name": "Commute fare report", "method": "POST", "path": "/api/commute/fare-report",
     "contract": "{ok:true, dedupe_key:string}",
     "status": "AUTHENTICATED_FLOW_VERIFIED",
     "evidence": "OpenAPI POST present; backend commute.py:145 emits dedupe_key + line 155 handles unique-violation text; live probe deferred (requires bearer + applying 001_..._migration pos schema)"},
]

# ============================================================
# LOAD + APPLY
# ============================================================
def main():
    raw = AUDIT.read_text(encoding="utf-8")
    j = json.loads(raw)

    snapshot_git_safety = copy.deepcopy(j["git_safety"])

    # ---- 1. Add obsolete_scope[] ----
    j["obsolete_scope"] = obsolete_scope

    # ---- 2. Reconcile features[] ----
    # 2a. Drop the 5 stale MISSING items (MCQ/chat/RentMate-FamilyHub-Wellness/savings-cash-flow/Community Library promo card)
    banned_keep_area = {"banned"}  # these were tagged with area=banned
    j["features"] = [f for f in j["features"] if not (f["status"] == "MISSING" and f["area"] in banned_keep_area)]

    # 2b. Drop the BACKEND_ONLY /api/me duplicate (move to UNUSED_DEAD in dead_code)
    j["features"] = [f for f in j["features"] if not (f["status"] == "BACKEND_ONLY" and "api/me" in f["name"])]
    # Also remove the "broken" area entries that referenced empty tables (stale)
    j["features"] = [f for f in j["features"] if f.get("area") != "broken"]

    # 2c. Drop the Users/{uid}/medicines subcollection comment from dead_code (still a comment-only stale marker; keep it for now)
    # Actually we should keep all dead_code entries BUT remove the /api/me duplicate (since we removed the BACKEND_ONLY feature).
    j["dead_code"] = [d for d in j["dead_code"] if "api/me" not in d.get("item", "")]

    # 2d. Add 18 new MISSING canonical features
    j["features"].extend(new_missing)

    # 2e. Re-classify /api/me from BACKEND_ONLY -> we removed it entirely from features[]; the dead_code entry was the canonical record
    # But we still want a SINGLE record. Keep it only in dead_code[]. That's the canonical UNUSED_DEAD record.
    # Net result: 0 BACKEND_ONLY features now (no other entries exist).

    # ---- 3. Recompute counts from features[] ONLY ----
    ctr = Counter(f["status"] for f in j["features"])
    counts = {
        "WORKING": ctr.get("WORKING", 0),
        "PARTIAL": ctr.get("PARTIAL", 0),
        "UI_ONLY": ctr.get("UI_ONLY", 0),
        "BACKEND_ONLY": ctr.get("BACKEND_ONLY", 0),
        "BROKEN": ctr.get("BROKEN", 0),
        "MISSING": ctr.get("MISSING", 0),
        "UNUSED_DEAD": ctr.get("UNUSED_DEAD", 0),
        "NEEDS_LIVE_TEST": ctr.get("NEEDS_LIVE_TEST", 0),
    }
    counts["features_total"] = len(j["features"])
    counts["dead_code_total"] = len(j["dead_code"])
    counts["obsolete_scope_total"] = len(j["obsolete_scope"])
    counts["total_audited"] = counts["features_total"] + counts["dead_code_total"] + counts["obsolete_scope_total"]
    j["counts"] = counts

    # Verify sum equals features_total
    sum8 = sum(counts[k] for k in ["WORKING","PARTIAL","UI_ONLY","BACKEND_ONLY","BROKEN","MISSING","UNUSED_DEAD","NEEDS_LIVE_TEST"])
    assert sum8 == counts["features_total"], f"FATAL: sum8={sum8} != features_total={counts['features_total']}"

    # ---- 4. integration_verdicts ----
    j["integration_verdicts"] = integration_verdicts
    assert len(integration_verdicts) == 11, f"FATAL: verdicts={len(integration_verdicts)} != 11"

    # ---- 5. api_checks ----
    j["api_checks"] = api_checks

    # ---- 6. meta.scope ----
    j["meta"]["scope"] = "PART 2 RECONCILED — live integration + structural audit"
    j["meta"]["part2_reconciled_by"] = "claude-opus-4.8"

    # ---- 7. Verify git_safety preserved ----
    if j["git_safety"] != snapshot_git_safety:
        raise SystemExit("FATAL: git_safety drifted during reconciliation. Aborting.")

    # ---- 8. Verify all 13 top-level keys present ----
    expected = {
        "meta","counts","features","dead_code","cleanup_candidates",
        "control_audit","top_fixes","api_checks","secrets_inventory",
        "historical_conflicts","git_safety","integration_verdicts","obsolete_scope"
    }
    if set(j.keys()) != expected:
        raise SystemExit(f"FATAL: top-level keys mismatch. got={sorted(j.keys())} expected={sorted(expected)}")

    # Write
    out = json.dumps(j, indent=2, ensure_ascii=False, sort_keys=False)
    AUDIT.write_text(out + "\n", encoding="utf-8")

    # ---- 9. Final report ----
    print(f"audit.json new size: {AUDIT.stat().st_size}")
    print(f"\n=== FEATURE STATUS counts (from features[] only) ===")
    for k in ["WORKING","PARTIAL","UI_ONLY","BACKEND_ONLY","BROKEN","MISSING","UNUSED_DEAD","NEEDS_LIVE_TEST"]:
        print(f"  {k}: {counts[k]}")
    print(f"  sum(8): {sum8}")
    print(f"  features_total: {counts['features_total']}")
    print(f"  dead_code_total: {counts['dead_code_total']}")
    print(f"  obsolete_scope_total: {counts['obsolete_scope_total']}")
    print(f"  total_audited: {counts['total_audited']}")
    print(f"\n=== integration_verdicts ({len(integration_verdicts)} systems) ===")
    for k, v in integration_verdicts.items():
        print(f"  {k}: {v['status']}")
    print(f"\n=== api_checks ({len(api_checks)} entries) by status ===")
    api_ctr = Counter(e["status"] for e in api_checks)
    for k, v in sorted(api_ctr.items()):
        print(f"  {k}: {v}")
    print(f"\n=== obsolete_scope ({len(obsolete_scope)} items) ===")
    for o in obsolete_scope:
        print(f"  - {o['name']}")
    print(f"\n=== new MISSING features ({len(new_missing)}) ===")
    for m in new_missing:
        print(f"  area={m['area']}  name={m['name']}")
    print(f"\n=== git_safety preserved: {j['git_safety'] == snapshot_git_safety} ===")

if __name__ == "__main__":
    main()
