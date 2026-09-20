"""Firebase UID Migration Tool.

Migrates Firestore ownership and identity references from OLD_UID to NEW_UID.
Reads OLD_UID and NEW_UID strictly from environment variables:
    GOCHANO_OLD_UID
    GOCHANO_NEW_UID

Default mode is DRY RUN (no writes performed).
Use --apply to perform backup and batch updates.

Usage:
    python backend/scripts/migrate_uid.py                 # Dry run
    python backend/scripts/migrate_uid.py --apply         # Backup + Apply
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Ensure backend modules can be imported
BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from dotenv import load_dotenv

# Load backend/.env if present for Firebase Admin credentials
env_file = BACKEND_DIR / ".env"
if env_file.exists():
    load_dotenv(str(env_file))

from app.core.firebase import _ensure_firebase, get_firestore
from firebase_admin import firestore

BATCH_LIMIT = 400


def get_uids() -> tuple[str, str]:
    """Retrieve UIDs from environment variables."""
    old_uid = os.environ.get("GOCHANO_OLD_UID", "").strip()
    new_uid = os.environ.get("GOCHANO_NEW_UID", "").strip()

    if not old_uid:
        print("ERROR: GOCHANO_OLD_UID environment variable is not set.", file=sys.stderr)
        sys.exit(1)
    if not new_uid:
        print("ERROR: GOCHANO_NEW_UID environment variable is not set.", file=sys.stderr)
        sys.exit(1)
    if old_uid == new_uid:
        print("ERROR: GOCHANO_OLD_UID and GOCHANO_NEW_UID cannot be identical.", file=sys.stderr)
        sys.exit(1)

    return old_uid, new_uid


def json_serializer(obj: Any) -> Any:
    """JSON serializer for Firestore datatypes (timestamps, refs, etc.)."""
    if hasattr(obj, "isoformat"):
        return obj.isoformat()
    if hasattr(obj, "path"):
        return obj.path
    return str(obj)


def audit_and_plan(db: Any, old_uid: str, new_uid: str) -> dict[str, Any]:
    """Audit all references to old_uid and prepare migration plan."""
    plan = {
        "profile": {"old_exists": False, "new_exists": False, "old_data": None, "new_data": None},
        "owner_docs": [],  # list of {"collection": col, "doc_id": id, "data": data, "field": "ownerId"}
        "group_memberships": [],  # list of {"doc_id": id, "data": data, "updates": dict}
        "group_messages": [],  # list of {"doc_id": id, "data": data, "updates": dict}
        "user_subcollections": [],  # list of {"subcollection": sub, "doc_id": id, "data": data}
        "counts": {},
    }

    # 1. Profile documents in users/
    old_user_ref = db.collection("users").document(old_uid)
    old_user_snap = old_user_ref.get()
    if old_user_snap.exists:
        plan["profile"]["old_exists"] = True
        plan["profile"]["old_data"] = old_user_snap.to_dict() or {}

    new_user_ref = db.collection("users").document(new_uid)
    new_user_snap = new_user_ref.get()
    if new_user_snap.exists:
        plan["profile"]["new_exists"] = True
        plan["profile"]["new_data"] = new_user_snap.to_dict() or {}

    # Check user subcollections under users/{old_uid}/
    user_subcollections = [
        "saved_materials",
        "material_state",
        "monthly_budget",
        "focus_sessions",
        "offline_materials",
    ]
    for sub in user_subcollections:
        sub_docs = list(db.collection("users").document(old_uid).collection(sub).stream())
        for sdoc in sub_docs:
            plan["user_subcollections"].append({
                "subcollection": sub,
                "doc_id": sdoc.id,
                "data": sdoc.to_dict() or {},
            })

    # 2. Standard ownerId collections
    owner_collections = [
        "tasks",
        "medicines",
        "medicine_doses",
        "bazar_items",
        "daily_expenses",
        "commute_trips",
        "planned_commute_trips",
        "financial_transactions",
        "dena_pawna_items",
        "notes",
        "semesters",
        "subjects",
    ]

    for col in owner_collections:
        docs = list(db.collection(col).where("ownerId", "==", old_uid).stream())
        for doc in docs:
            d = doc.to_dict() or {}
            plan["owner_docs"].append({
                "collection": col,
                "doc_id": doc.id,
                "field": "ownerId",
                "data": d,
            })

    # Extra check for financial_transactions where userId == old_uid
    # (some financial_transactions have both ownerId and userId)
    ft_user_docs = list(db.collection("financial_transactions").where("userId", "==", old_uid).stream())
    existing_ft_ids = {item["doc_id"] for item in plan["owner_docs"] if item["collection"] == "financial_transactions"}
    for doc in ft_user_docs:
        if doc.id not in existing_ft_ids:
            plan["owner_docs"].append({
                "collection": "financial_transactions",
                "doc_id": doc.id,
                "field": "userId",
                "data": doc.to_dict() or {},
            })

    # 3. Groups (memberIds, adminIds, ownerId)
    all_groups = list(db.collection("groups").stream())
    for g in all_groups:
        gdata = g.to_dict() or {}
        g_updates = {}
        dirty = False

        # memberIds array
        members = list(gdata.get("memberIds") or [])
        if old_uid in members:
            new_members = [new_uid if m == old_uid else m for m in members]
            # Deduplicate preserving order
            seen = set()
            dedup_members = [m for m in new_members if not (m in seen or seen.add(m))]
            g_updates["memberIds"] = dedup_members
            g_updates["memberCount"] = len(dedup_members)
            dirty = True

        # adminIds array
        admins = list(gdata.get("adminIds") or [])
        if old_uid in admins:
            new_admins = [new_uid if a == old_uid else a for a in admins]
            seen = set()
            dedup_admins = [a for a in new_admins if not (a in seen or seen.add(a))]
            g_updates["adminIds"] = dedup_admins
            dirty = True

        # ownerId
        if gdata.get("ownerId") == old_uid:
            g_updates["ownerId"] = new_uid
            dirty = True

        if dirty:
            plan["group_memberships"].append({
                "doc_id": g.id,
                "data": gdata,
                "updates": g_updates,
            })

    # 4. Group Messages (senderId, reactions)
    all_messages = list(db.collection("group_messages").stream())
    for msg in all_messages:
        mdata = msg.to_dict() or {}
        m_updates = {}
        dirty = False

        # senderId
        if mdata.get("senderId") == old_uid:
            m_updates["senderId"] = new_uid
            dirty = True

        # reactions: { emoji: [uid1, uid2] }
        reactions = mdata.get("reactions")
        if isinstance(reactions, dict):
            new_reactions = {}
            reactions_changed = False
            for emoji, uids in reactions.items():
                if isinstance(uids, list) and old_uid in uids:
                    reactions_changed = True
                    updated_uids = [new_uid if u == old_uid else u for u in uids]
                    # Deduplicate
                    seen = set()
                    dedup_uids = [u for u in updated_uids if not (u in seen or seen.add(u))]
                    new_reactions[emoji] = dedup_uids
                else:
                    new_reactions[emoji] = uids
            if reactions_changed:
                m_updates["reactions"] = new_reactions
                dirty = True

        if dirty:
            plan["group_messages"].append({
                "doc_id": msg.id,
                "data": mdata,
                "updates": m_updates,
            })

    # Summary counts
    counts = {
        "users profile": 1 if plan["profile"]["old_exists"] else 0,
        "users subcollections": len(plan["user_subcollections"]),
    }
    for col in owner_collections:
        c = sum(1 for item in plan["owner_docs"] if item["collection"] == col)
        counts[f"{col}.ownerId"] = c

    counts["groups (membership/admin/owner)"] = len(plan["group_memberships"])
    sender_count = sum(1 for m in plan["group_messages"] if "senderId" in m["updates"])
    reactions_count = sum(1 for m in plan["group_messages"] if "reactions" in m["updates"])
    counts["group_messages.senderId"] = sender_count
    counts["group_messages.reactions"] = reactions_count

    plan["counts"] = counts
    return plan


def create_backup(backup_dir: Path, plan: dict[str, Any], old_uid: str, new_uid: str) -> Path:
    """Export affected data and manifest to a local backup directory."""
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    run_backup_path = backup_dir / timestamp
    run_backup_path.mkdir(parents=True, exist_ok=True)

    data_export: dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "profile": plan["profile"],
        "user_subcollections": plan["user_subcollections"],
        "owner_docs": plan["owner_docs"],
        "group_memberships": plan["group_memberships"],
        "group_messages": plan["group_messages"],
    }

    data_file = run_backup_path / "data_backup.json"
    with open(data_file, "w", encoding="utf-8") as f:
        json.dump(data_export, f, indent=2, default=json_serializer)

    manifest_entries = []
    if plan["profile"]["old_exists"]:
        manifest_entries.append({
            "collection": "users",
            "doc_id": "users/<OLD_UID>",
            "action": "copy_profile_to_new_uid",
            "old_key": "users/<OLD_UID>",
            "new_key": "users/<NEW_UID>",
        })

    for item in plan["user_subcollections"]:
        manifest_entries.append({
            "collection": f"users/<OLD_UID>/{item['subcollection']}",
            "doc_id": item["doc_id"],
            "action": "copy_subcollection_doc",
            "target": f"users/<NEW_UID>/{item['subcollection']}/{item['doc_id']}",
        })

    for item in plan["owner_docs"]:
        manifest_entries.append({
            "collection": item["collection"],
            "doc_id": item["doc_id"],
            "field": item["field"],
            "action": "update_owner_id",
            "old_value": "<OLD_UID>",
            "new_value": "<NEW_UID>",
        })

    for item in plan["group_memberships"]:
        fields_changed = list(item["updates"].keys())
        manifest_entries.append({
            "collection": "groups",
            "doc_id": item["doc_id"],
            "field": ", ".join(fields_changed),
            "action": "update_group_members",
        })

    for item in plan["group_messages"]:
        fields_changed = list(item["updates"].keys())
        manifest_entries.append({
            "collection": "group_messages",
            "doc_id": item["doc_id"],
            "field": ", ".join(fields_changed),
            "action": "update_message",
        })

    manifest_file = run_backup_path / "manifest.json"
    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "total_items": len(manifest_entries),
            "entries": manifest_entries,
        }, f, indent=2)

    return run_backup_path


def apply_migration(db: Any, plan: dict[str, Any], old_uid: str, new_uid: str) -> None:
    """Execute batch writes to migrate data from old_uid to new_uid."""
    batches = [db.batch()]
    op_count = [0]

    def add_op(op_type: str, ref: Any, data: Any = None):
        if op_count[0] >= BATCH_LIMIT:
            batches.append(db.batch())
            op_count[0] = 0

        current_batch = batches[-1]
        if op_type == "set":
            current_batch.set(ref, data, merge=True)
        elif op_type == "update":
            current_batch.update(ref, data)
        elif op_type == "delete":
            current_batch.delete(ref)
        op_count[0] += 1

    # A. USERS PROFILE
    if plan["profile"]["old_exists"]:
        old_data = plan["profile"]["old_data"] or {}
        new_data = plan["profile"]["new_data"] or {}

        # Merge fields: preserve existing new_uid fields if valid, copy missing fields from old_data
        merged_profile = dict(old_data)
        for k, v in new_data.items():
            if v is not None and v != "":
                merged_profile[k] = v

        # Always ensure role is valid
        if "role" not in merged_profile or merged_profile["role"] not in {"student", "general"}:
            merged_profile["role"] = old_data.get("role", "student")

        merged_profile["updatedAt"] = firestore.SERVER_TIMESTAMP

        new_user_ref = db.collection("users").document(new_uid)
        add_op("set", new_user_ref, merged_profile)

    # Subcollections under users/{old_uid} -> users/{new_uid}
    for subdoc in plan["user_subcollections"]:
        target_ref = (
            db.collection("users")
            .document(new_uid)
            .collection(subdoc["subcollection"])
            .document(subdoc["doc_id"])
        )
        add_op("set", target_ref, subdoc["data"])

    # B. OWNER DATA
    for item in plan["owner_docs"]:
        doc_ref = db.collection(item["collection"]).document(item["doc_id"])
        field_name = item["field"]
        update_dict = {field_name: new_uid, "updatedAt": firestore.SERVER_TIMESTAMP}
        # If financial_transactions had userId == old_uid as well, update both
        if item["collection"] == "financial_transactions" and item["data"].get("userId") == old_uid:
            update_dict["userId"] = new_uid
        add_op("update", doc_ref, update_dict)

    # C. COMMUNITY GROUP MEMBERSHIP
    for item in plan["group_memberships"]:
        doc_ref = db.collection("groups").document(item["doc_id"])
        updates = dict(item["updates"])
        updates["updatedAt"] = firestore.SERVER_TIMESTAMP
        add_op("update", doc_ref, updates)

    # D & E. GROUP MESSAGES & REACTIONS
    for item in plan["group_messages"]:
        doc_ref = db.collection("group_messages").document(item["doc_id"])
        add_op("update", doc_ref, item["updates"])

    # Commit all batches
    total_ops = sum(len(b._write_pbs) if hasattr(b, "_write_pbs") else 1 for b in batches)
    print(f"\nCommitting {len(batches)} batch(es)...")
    for idx, b in enumerate(batches, 1):
        b.commit()
        print(f"  Batch {idx}/{len(batches)} committed.")


def print_counts(counts: dict[str, int]) -> None:
    """Print clean counts without exposing sensitive data."""
    for key, count in counts.items():
        print(f"{key}: {count}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Gochano Firebase UID Migration Tool")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply migration changes with backup. Defaults to DRY RUN.",
    )
    parser.add_argument(
        "--backup-dir",
        default=r"D:\Gochano_UID_Backup",
        help="Directory to store migration backups.",
    )
    args = parser.parse_args()

    old_uid, new_uid = get_uids()

    mode_str = "APPLY" if args.apply else "DRY RUN"
    print("=" * 60)
    print(f"Gochano Firebase UID Migration [{mode_str}]")
    print("=" * 60)

    _ensure_firebase()
    db = get_firestore()

    print("\nAuditing references...")
    plan = audit_and_plan(db, old_uid, new_uid)

    print("\nAudit Summary:")
    print("-" * 40)
    print_counts(plan["counts"])
    print("-" * 40)

    if not args.apply:
        print("\nDRY RUN COMPLETE. No changes were written to Firestore.")
        print("To apply these changes and back up affected documents, run with --apply.")
        return 0

    # Apply Mode:
    # 1. Backup
    print(f"\nCreating pre-migration backup in {args.backup_dir}...")
    backup_path = create_backup(Path(args.backup_dir), plan, old_uid, new_uid)
    print(f"Backup created successfully at: {backup_path}")

    # 2. Batch writes
    print("\nApplying migration updates...")
    apply_migration(db, plan, old_uid, new_uid)

    # 3. Post-migration audit
    print("\nRunning post-migration verification audit...")
    post_plan = audit_and_plan(db, old_uid, new_uid)

    print("\nPost-Migration Audit Summary (OLD_UID references):")
    print("-" * 40)
    print_counts(post_plan["counts"])
    print("-" * 40)

    # Check for remaining old_uid references
    remaining = sum(
        v for k, v in post_plan["counts"].items()
        if k != "users profile"  # Old profile intentionally preserved for rollback
    )

    if remaining == 0:
        print("\nSUCCESS: All non-profile references to OLD_UID successfully migrated to NEW_UID.")
        print("Old profile users/<OLD_UID> preserved for rollback as required.")
    else:
        print(f"\nWARNING: {remaining} reference(s) still point to OLD_UID. Inspect post-audit above.")

    return 0


if __name__ == "__main__":
    sys.exit(main())

