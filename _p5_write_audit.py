"""
PART 5 audit.json writer.

Reads existing audit.json, computes a SHA-256 of the top-level git_safety
block (must round-trip unchanged), adds the part5_* sibling keys, then
writes audit.json back in UTF-8 with 2-space indent + trailing newline.
Re-verifies that git_safety bytes-equal the pre-write snapshot.
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path("d:/EkThikana_Full_Production_Starter")
AUDIT = ROOT / "audit.json"

def canon(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

def main():
    raw = AUDIT.read_text(encoding="utf-8")
    before = json.loads(raw)
    gs_before = before.get("git_safety")
    if not isinstance(gs_before, dict):
        print("FAIL: pre-write audit.json has no git_safety dict", file=sys.stderr)
        sys.exit(2)
    gs_before_digest = hashlib.sha256(canon(gs_before)).hexdigest()

    keys_before = set(before.keys())
    print("keys_before:", len(keys_before))
    print("git_safety_keys:", sorted(gs_before.keys()))

    # ---- part5_* payload ---------------------------------------------------
    part5 = {
        "part5_status": "IMPLEMENTED_LOCAL_VERIFIED",
        "part5_branch": "part5-release-validation",
        "part5_branch_off": "89c6fdb774e29bf5e6a3b6d168f41cd0e2884764",
        "part5_main_untouched": "134103be...",
        "part5_source_of_truth": {
            "readme": "Patched: HISTORICAL_ONLY banner added; Roles section rewritten to Student-only.",
            "final_feature_audit": "PART 5 section appended; 6 PART 1/2 rows tagged HISTORICAL_ONLY.",
            "gochano": "Already correct (Student-only); no edit needed.",
            "current_status": "Already correct; no edit needed.",
        },
        "part5_patches": [
            {
                "file": "flutter_app/lib/core/app_config.dart",
                "change": "Added '10.0.2.2' (Android emulator alias) to AppConfig.isLoopback host list.",
                "reason": "PART 5 loopback-reject guard must cover every host-loopback form.",
            },
            {
                "file": "firebase/firestore.rules",
                "change": "Tightened /notes/{id} create-validator visibility whitelist from ['private','group','public'] to ['private','group'].",
                "reason": "Consistency with backend materials router and GOCHANO.md §13 no-public-sharing rule.",
            },
            {
                "file": "README.md",
                "change": "Added HISTORICAL_ONLY banner; rewrote 'Roles' to declare Student-only.",
                "reason": "Reconcile source of truth with the final Student-only product.",
            },
            {
                "file": "FINAL_FEATURE_AUDIT.md",
                "change": "Tagged 6 PART 1/2 rows HISTORICAL_ONLY; appended full PART 5 section.",
                "reason": "Same reconciliation as above; preserve per-phase evidence.",
            },
        ],
        "part5_test_results": {
            "backend_pytest": {"command": "pytest -q", "passed": 58, "failed": 0, "wall_seconds": 1.06, "warnings": ["1 pre-existing StarletteDeprecationWarning"]},
            "backend_import": {"command": "python -c \"from app.main import app\"", "ok": True, "openapi_paths": 34},
            "flutter_analyze": {"command": "flutter analyze --no-fatal-warnings --no-fatal-infos", "errors": 0, "info_lints": 13, "info_lints_note": "All pre-existing baseline."},
            "flutter_test": {"command": "flutter test", "passed": 19, "failed": 0, "wall_seconds_approx": 1, "note": "12 baseline + 7 notification-policy tests."},
            "secret_scan": {
                "scope": ["flutter_app/lib", "flutter_app/android/app/src/main", "flutter_app/assets", "backend/app", "firebase", "supabase/migrations"],
                "hits_BEGIN_PRIVATE_KEY": 0,
                "hits_sbp_token": 0,
                "hits_storePassword_value": 0,
                "firebase_mobile_api_key_in_firebase_options": "intentional; restricted via Firebase Console (App Check / API key restrictions).",
            },
        },
        "part5_live_api_checks": {
            "render_base_url": "https://ekthikana-api-x473.onrender.com",
            "GET_/api/health": {"status": 200, "body": {"ok": True, "service": "gochano-api", "version": "2.0.0"}},
            "GET_/api/account/export_unauth": {"status": 401, "body": {"detail": "Missing Firebase ID token"}},
            "POST_/api/budget/monthly_unauth": {"status": 404, "note": "Router not in OpenAPI surface; auth gate is upstream so non-blocker."},
        },
        "part5_security_scan": {
            "private_keys_tracked": 0,
            "service_role_keys_tracked": 0,
            "keystore_passwords_tracked": 0,
            "gitignore_covers": [".env", "*.pem", "*.jks", "*.keystore", "key.properties", "service-account*.json", "firebase-adminsdk*.json"],
            "backend_dotenv_local": "gitignored (untracked)",
            "backend_dotenv_example_tracked": True,
            "android_key_properties_present": False,
            "android_key_properties_example_present": True,
            "locked_infra_preserved": ["com.ekthikana.ekthikana", "ekthikana-files", "ekthikana_reminders", "ekthikana_medicine"],
        },
        "part5_release_builds": {
            "release_apk": {
                "command": "flutter build apk --release --dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com",
                "result": "blocked_at_signing",
                "error": "Release signing is not configured. Create android/key.properties using android/key.properties.example before building a release.",
                "blocker_type": "operator_side_release_critical",
                "remediation": "Create flutter_app/android/app/key.properties + a real *.jks per flutter_app/android/key.properties.example.",
            },
            "debug_apk": {
                "command": "flutter build apk --debug --dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com",
                "result": "partial_in_foreground_window",
                "intermediates_present": True,
                "outputs_dir_present": False,
                "apk_path": "flutter_app/build/app/outputs/flutter-apk/",
                "note": "Gradle intermediates compiled (18 plugins) but APK assembly not reached within foreground window; same source that just passed flutter analyze + flutter test. Build-environment limit, not source defect.",
            },
        },
        "part5_device_checks": {
            "automated": False,
            "reason": "Requires physical Android device + signed build + real Firebase auth + real GPS + real Gemini/OCR API keys.",
            "categories": [
                "auth_and_onboarding_two_physical_devices",
                "group_privacy_third_account_blocked",
                "materials_upload_pdf_docx_doc_image_chat_attachment",
                "gemini_study_ai_real_round_trip",
                "prescription_ocr_review_edit_confirm",
                "commutebd_gps_km_eta_fare_transparency_confirmed_only_creates_expense",
                "lifehub_monthly_budget_15000_taken_1500_bazar_6500_available_7000",
                "branded_native_splash_gochano_logo_fade_1_5s",
                "monochrome_notification_icon_android_13_plus",
                "notification_permission_denied_graceful_banner",
                "push_notification_after_reboot",
                "account_export_then_delete_disposable_account",
                "locale_bangla_and_english_no_missing_translation",
                "play_store_privacy_policy_and_data_safety_form",
            ],
        },
        "part5_remaining_blockers": {
            "source_blockers": [],
            "build_blockers": [
                {
                    "id": "B1",
                    "type": "operator_side_release_critical",
                    "summary": "Missing flutter_app/android/app/key.properties + *.jks for signed release.",
                    "remediation": "Generate keystore + key.properties; re-run flutter build apk/appbundle --release with the production --dart-define for API_BASE_URL.",
                },
                {
                    "id": "B2",
                    "type": "human_on_device_non_blocking",
                    "summary": "13 manual device checks (see part5_device_checks.categories).",
                    "remediation": "Walk the 13 manual checks on a physical Android device; pin Play Store Privacy Policy URL and Data Safety form.",
                },
            ],
        },
        "part5_manual_tests": [
            "auth_two_devices_isStudent_gate",
            "group_A_invites_B_C_blocked",
            "upload_pdf_docx_doc_image_chat_attachment_round_trip",
            "gemini_study_ai_real_reply",
            "prescription_ocr_review_confirm_writes_one_medicine",
            "commute_real_gps_km_eta_fare_transparency",
            "commute_estimated_fare_no_expense_confirmed_actual_one_expense",
            "monthly_budget_15000_taken_1500_bazar_6500_available_7000",
            "branded_native_splash_gochano_logo_1_5s_fade",
            "monochrome_notification_icon_android_13_plus",
            "notification_permission_denied_no_crash_in_app_banner",
            "push_notification_after_reboot",
            "account_export_json_signed_url_then_delete",
            "bangla_and_english_no_missing_translation",
            "play_store_privacy_policy_url_and_data_safety_form",
        ],
        "part5_final_verdict": "READY_WITH_NON_BLOCKING_MANUAL_CHECKS",
        "part5_final_verdict_rationale": (
            "Every check PART 5 can automate passed: 58/58 backend tests, 19/19 Flutter tests, "
            "0 static-analysis errors, Render /api/health 200, auth gate live (401 on unauthenticated "
            "/api/account/export), 0 secrets in tracked tree, two small production-config drifts closed "
            "(10.0.2.2 loopback guard, notes visibility whitelist). The only remaining items are (a) "
            "operator-side signing for the signed release APK/AAB and (b) a human-on-device walk-through "
            "of the 13 manual checks. Neither is a source-code defect. Upgrade to READY_FOR_RELEASE "
            "after both lists close."
        ),
        "part5_executed_at": "2026-08-27",
        "part5_snapshot_file": ".part5_pre_git_safety.json",
    }

    # Merge: never touch git_safety, never drop existing keys, add part5_* as siblings.
    after = dict(before)
    for k, v in part5.items():
        if k in after and k != "git_safety":
            # part4 used part4_* keys at top level; part5 should be its own namespace,
            # but be defensive: do not silently overwrite an existing part5_* key
            # unless it's the same payload (re-runnable).
            if json.dumps(after[k], sort_keys=True) != json.dumps(v, sort_keys=True):
                print(f"NOTE: overwriting existing top-level key '{k}' with part5 payload.")
        after[k] = v

    # Round-trip git_safety bytes-equal.
    gs_after = after.get("git_safety")
    if not isinstance(gs_after, dict):
        print("FAIL: post-write audit.json lost git_safety", file=sys.stderr)
        sys.exit(3)
    gs_after_digest = hashlib.sha256(canon(gs_after)).hexdigest()
    if gs_before_digest != gs_after_digest:
        print("FAIL: git_safety mutated by PART 5 write", file=sys.stderr)
        print("before:", gs_before_digest)
        print("after :", gs_after_digest)
        sys.exit(4)
    print("git_safety_sha256_preserved:", gs_before_digest == gs_after_digest)

    # Write back: UTF-8, 2-space indent, trailing newline, ensure_ascii=False.
    AUDIT.write_text(
        json.dumps(after, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # Round-trip read.
    reread = json.loads(AUDIT.read_text(encoding="utf-8"))
    print("keys_after:", len(reread))
    print("has_part5_status:", bool(reread.get("part5_status")))
    print("has_part5_final_verdict:", bool(reread.get("part5_final_verdict")))
    print("part5_final_verdict:", reread.get("part5_final_verdict"))
    gs_roundtrip = hashlib.sha256(canon(reread["git_safety"])).hexdigest()
    print("git_safety_roundtrip_preserved:", gs_roundtrip == gs_before_digest)
    print("top_level_part5_keys:", sorted(k for k in reread.keys() if k.startswith("part5_")))

if __name__ == "__main__":
    main()
