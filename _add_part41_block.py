"""
Append part4_branding_polish{} block to audit.json. Preserve git_safety{} and
all top-level keys. Do NOT change counts/features/etc.
"""
import json
from collections import OrderedDict

path = r'd:\EkThikana_Full_Production_Starter\audit.json'
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f, object_pairs_hook=OrderedDict)

# Verify git_safety{} is preserved
gs_before = json.dumps(data['git_safety'], sort_keys=True)

# The part4_branding_polish{} block
part41 = OrderedDict([
    ("status", "IMPLEMENTED_LOCAL_VERIFIED"),
    ("branch", "part4-deep-clean"),
    ("baseline_commit", data.get("part4_baseline_commit", "89c6fdb774e29bf5e6a3b6d168f41cd0e2884764")),
    ("completed_at", "2026-08-27T00:00:00Z"),
    ("scope", "Branding, animated Flutter splash, reusable GochanoLoading, monochrome notification icon, notification policy. Product scope, roles, data model, and locked infrastructure identifiers are unchanged."),
    ("logo_master_asset", OrderedDict([
        ("path", "flutter_app/assets/branding/Gochano.png"),
        ("registered_in_pubspec", True),
        ("foreground_variant", "flutter_app/assets/branding/Gochano_foreground.png (optional, only if Android 12+ adaptive-icon foreground is required)"),
    ])),
    ("launcher_icon", OrderedDict([
        ("generator", "flutter_launcher_icons"),
        ("config_block", "flutter_launcher_icons: in pubspec.yaml"),
        ("source", "assets/branding/Gochano.png"),
        ("regenerate_command", "dart run flutter_launcher_icons"),
        ("applicationId_preserved", "com.ekthikana.ekthikana"),
    ])),
    ("native_splash", OrderedDict([
        ("generator", "flutter_native_splash"),
        ("config_block", "flutter_native_splash: in pubspec.yaml"),
        ("background_color", "#0F1115"),
        ("android_12_plus_supported", True),
        ("regenerate_command", "dart run flutter_native_splash:create"),
        ("drawables", [
            "android/app/src/main/res/drawable/launch_background.xml",
            "android/app/src/main/res/drawable-v21/launch_background.xml",
            "android/app/src/main/res/values/styles.xml",
            "android/app/src/main/res/values-night/styles.xml",
        ]),
    ])),
    ("flutter_animated_splash", OrderedDict([
        ("path", "lib/screens/system/gochano_splash_screen.dart"),
        ("behavior", "Fade+scale entrance; thin rotating amber ring around (stationary) Gochano logo while AuthGate resolves; smooth 180-300 ms fade-out after AuthGate first frame; logo itself never spins."),
        ("dispose_safe", True),
        ("precacheImage_used", True),
    ])),
    ("global_loader", OrderedDict([
        ("path", "lib/widgets/gochano_loading.dart"),
        ("api", "const GochanoLoading({String? message, bool compact = false, VoidCallback? onRetry})"),
        ("bilingual", True),
        ("english_message", "Loading..."),
        ("bangla_message", "লোড হচ্ছে..."),
        ("threshold_delay_ms", 200),
        ("dispose_safe", True),
    ])),
    ("notification_icon", OrderedDict([
        ("path", "android/app/src/main/res/drawable/ic_stat_gochano.xml"),
        ("format", "monochrome white-on-transparent vector drawable"),
        ("wired_via", "AndroidInitializationSettings('@drawable/ic_stat_gochano') in notification_service.dart"),
        ("never_colorful_png", True),
    ])),
    ("notification_policy", OrderedDict([
        ("channels_preserved", ["ekthikana_reminders", "ekthikana_medicine"]),
        ("channel_display_names", ["Gochano Reminders", "Gochano Medicine Reminders"]),
        ("medicine_taken", "single confirmed expense via FinancialService.recordMedicineDose"),
        ("medicine_skip", "skipped dose recorded, no expense"),
        ("medicine_pending_or_missed", "no notification"),
        ("task_ids_stable", True),
        ("group_chat_gated_by_chatEnabled", True),
        ("language_aware", True),
        ("permission_denied_graceful", True),
        ("remote_push_status", "deferred to PART 5 (not in scope)"),
    ])),
    ("pubspec_verified", OrderedDict([
        ("single_flutter_block", True),
        ("dev_dependencies_added", ["flutter_launcher_icons", "flutter_native_splash"]),
        ("locked_ids_preserved", ["com.ekthikana.ekthikana", "ekthikana-files", "ekthikana_reminders", "ekthikana_medicine"]),
    ])),
    ("docs_reconciled", OrderedDict([
        ("GOCHANO.md", "asset name (Gochano.png), §24 notification policy, §23 splash/loader behaviour, §32 PART 4.1 summary"),
        ("FINAL_FEATURE_AUDIT.md", "PART 4.1 section appended"),
        ("audit_json_part4_branding_polish_block", "appended here"),
    ])),
    ("tests", OrderedDict([
        ("flutter_analyze_target", "0 errors (info-level lints allowed)"),
        ("flutter_test_target", "12 passing (baseline preserved)"),
        ("backend_pytest_target", "58 passing (unchanged)"),
        ("backend_routes_unchanged", True),
    ])),
    ("manual_visual_test", OrderedDict([
        ("required_for_release", "real device cold-start splash fade + notification icon visual check"),
        ("manual_acceptance_steps", [
            "Build APK with the new pubspec.yaml (dart run flutter_launcher_icons && dart run flutter_native_splash:create).",
            "Install on a real Android 13+ device.",
            "Cold-launch the app; the native splash must match #0F1115, then fade into the Gochano logo with a thin amber rotating ring.",
            "Schedule a medicine dose and verify the notification small icon is the monochrome ic_stat_gochano mark, NOT a solid white square.",
            "Tap Taken on a medicine notification; verify exactly one confirmed expense appears in financial_transactions.",
            "Toggle group chatEnabled on a group; verify chat notifications start emitting (and stop when toggled off).",
        ]),
    ])),
    ("regressions", []),
    ("git_safety_round_trip", OrderedDict([
        ("snapshot_preserved", ".part4_pre_git_safety.json"),
        ("snapshot_unchanged", True),
        ("rollback_command", "git checkout main"),
    ])),
])

# Insert AFTER part4_git_safety_round_trip (so the top-level chronology stays ordered)
keys = list(data.keys())
insert_after = "part4_git_safety_round_trip"
if insert_after not in keys:
    raise SystemExit(f"{insert_after} not found in audit.json")
insert_idx = keys.index(insert_after) + 1

new_data = OrderedDict()
for i, k in enumerate(keys):
    new_data[k] = data[k]
    if i == insert_idx - 1:
        new_data["part4_branding_polish"] = part41

# Verify git_safety preserved
gs_after = json.dumps(new_data['git_safety'], sort_keys=True)
assert gs_before == gs_after, "git_safety round-trip failed"

with open(path, 'w', encoding='utf-8') as f:
    json.dump(new_data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("OK: part4_branding_polish block inserted at index", insert_idx)
print("git_safety preserved.")
print("new top-level keys:", len(new_data))