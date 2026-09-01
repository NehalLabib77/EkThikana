"""Guards for the Firebase-to-B2 migration and for explicit provider reads.

Two properties are worth more than everything else here.

**The migration never deletes.** The first pass is a copy and only a copy.
Removing a source object is a separate decision for a human who has already
confirmed the copies are good, and it is not automated anywhere in this
codebase. A static guard over the script's own source enforces that, so it
holds for edits made after this file.

**Reads are not a blind fallback.** Trying B2 and falling back to Firebase on
failure hides two different disasters: a real B2 outage looks like a slow
success, and an incomplete migration looks like a complete one. The record
states where its file is, and that statement is honoured.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.services import legacy_storage, storage_provider
from app.services.storage_provider import B2, FIREBASE, UNKNOWN


@pytest.fixture
def no_legacy(monkeypatch):
    """The state after migration: nothing but B2 exists."""
    monkeypatch.setattr(legacy_storage, "is_configured", lambda: False)


@pytest.fixture
def with_legacy(monkeypatch):
    """Mid-migration: both buckets are live."""
    monkeypatch.setattr(legacy_storage, "is_configured", lambda: True)

    state = {"b2": set(), "firebase": set()}

    monkeypatch.setattr(
        storage_provider.storage_service,
        "object_exists",
        lambda path: path in state["b2"],
    )
    monkeypatch.setattr(legacy_storage, "exists", lambda path: path in state["firebase"])
    return state


# ---------------------------------------------------------------------------
# Provider resolution
# ---------------------------------------------------------------------------


def test_a_declared_provider_is_believed_without_probing(with_legacy, monkeypatch):
    # The statement on the record is the whole point of the field. Probing
    # anyway would make it decorative.
    probed = []
    monkeypatch.setattr(
        storage_provider.storage_service,
        "object_exists",
        lambda path: probed.append(path) or True,
    )

    resolved = storage_provider.resolve(
        {"filePath": "users/u1/a.pdf", "storageProvider": "firebase"}
    )

    assert resolved.provider == FIREBASE
    assert resolved.should_persist is False
    assert probed == [], "a declared provider must not be second-guessed"


def test_no_legacy_bucket_means_no_probe_at_all(no_legacy, monkeypatch):
    # Once migration is done there is only one place a file can be. Probing
    # would turn a momentary B2 hiccup into a 404 on a perfectly good file,
    # and add a HEAD to every read forever.
    monkeypatch.setattr(
        storage_provider.storage_service,
        "object_exists",
        lambda path: pytest.fail("must not probe when there is no legacy bucket"),
    )

    resolved = storage_provider.resolve({"filePath": "users/u1/a.pdf"})

    assert resolved.provider == B2
    assert resolved.missing is False
    assert resolved.should_persist is False


def test_an_unlabelled_file_is_probed_once_and_marked_for_recording(with_legacy):
    with_legacy["b2"].add("users/u1/migrated.pdf")

    resolved = storage_provider.resolve({"filePath": "users/u1/migrated.pdf"})

    assert resolved.provider == B2
    # The caller records this so the probe is paid once per file, not once
    # per read. That is what stops it being a fallback in disguise.
    assert resolved.should_persist is True


def test_an_unlabelled_file_still_in_firebase_resolves_there(with_legacy):
    with_legacy["firebase"].add("users/u1/old.pdf")

    resolved = storage_provider.resolve({"filePath": "users/u1/old.pdf"})

    assert resolved.provider == FIREBASE
    assert resolved.should_persist is True


def test_a_file_in_neither_bucket_is_not_labelled(with_legacy):
    # Writing a provider for a file that is not there would make a missing
    # file look migrated.
    resolved = storage_provider.resolve({"filePath": "users/u1/gone.pdf"})

    assert resolved.missing is True
    assert resolved.provider == UNKNOWN
    assert resolved.should_persist is False


def test_a_record_with_no_path_is_missing_not_guessed():
    resolved = storage_provider.resolve({"filePath": ""})

    assert resolved.missing is True
    assert resolved.provider == UNKNOWN


def test_an_unrecognised_provider_value_is_treated_as_unstated():
    # A typo or a future provider name must not be passed to a bucket lookup.
    assert storage_provider.declared_provider({"storageProvider": "s3"}) == UNKNOWN
    assert storage_provider.declared_provider({"storageProvider": ""}) == UNKNOWN
    assert storage_provider.declared_provider(None) == UNKNOWN
    assert storage_provider.declared_provider({"storageProvider": "B2"}) == B2


def test_a_missing_resolution_never_produces_a_url_or_bytes():
    missing = storage_provider.Resolution(provider=UNKNOWN, path="x", missing=True)

    assert storage_provider.signed_url_for(missing) is None
    assert storage_provider.download_for(missing) is None


# ---------------------------------------------------------------------------
# The legacy reader is read-only
# ---------------------------------------------------------------------------


def test_the_legacy_module_offers_no_way_to_write_or_delete():
    # New files go to B2; old files are copied out. Nothing in the running
    # app may modify the bucket it is being migrated out of.
    for forbidden in ("upload", "delete", "put", "remove", "write"):
        assert not hasattr(legacy_storage, forbidden), (
            f"legacy storage must stay read-only, found {forbidden}()"
        )


def test_an_unconfigured_legacy_bucket_is_a_normal_state(monkeypatch):
    # After migration, FIREBASE_STORAGE_BUCKET is unset. That must not raise.
    monkeypatch.setattr(
        legacy_storage, "_bucket", lambda: pytest.fail("should not be reached")
    )
    from app.core.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "firebase_storage_bucket", "", raising=False)

    assert legacy_storage.is_configured() is False


# ---------------------------------------------------------------------------
# The migration script
# ---------------------------------------------------------------------------


SCRIPT = Path("scripts/migrate_firebase_to_b2.py")


def test_the_migration_script_exists():
    assert SCRIPT.exists()


def test_the_migration_never_deletes_anything():
    # The single most important property of the first pass. A static guard,
    # so it holds for edits made after this test was written.
    source = SCRIPT.read_text(encoding="utf-8")

    code = "\n".join(
        line for line in source.splitlines() if not line.strip().startswith("#")
    )
    for forbidden in ("delete_file(", ".delete()", "delete_object(", "bulk_delete"):
        assert forbidden not in code, (
            f"the migration must never delete a source object, found {forbidden}"
        )


def test_dry_run_is_the_default():
    source = SCRIPT.read_text(encoding="utf-8")

    # `--apply` is opt-in: running the script by accident must not move data.
    assert '"--apply"' in source
    assert 'action="store_true"' in source
    assert "if not args.apply" in source


def test_the_script_documents_that_it_does_not_delete():
    # An operator reading --help must be told, not left to infer it.
    assert "never deletes anything" in SCRIPT.read_text(encoding="utf-8").lower()


def test_the_script_never_prints_a_credential():
    source = SCRIPT.read_text(encoding="utf-8")

    for secret in (
        "b2_application_key",
        "b2_key_id",
        "B2_APPLICATION_KEY",
        "B2_KEY_ID",
        "service_account",
    ):
        assert secret not in source, f"the migration must not touch {secret}"


# ---------------------------------------------------------------------------
# Copying one file
# ---------------------------------------------------------------------------


@pytest.fixture
def migration(monkeypatch):
    """The migration module with both buckets faked."""
    import importlib.util
    import sys

    spec = importlib.util.spec_from_file_location("migrate_fb_b2", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    # Registered before execution: @dataclass resolves its own module by name
    # while the class body runs, and fails outright if it is not there yet.
    monkeypatch.setitem(sys.modules, "migrate_fb_b2", module)
    spec.loader.exec_module(module)

    b2: dict[str, bytes] = {}
    firebase: dict[str, bytes] = {}

    monkeypatch.setattr(
        module.storage_service,
        "object_size",
        lambda path: len(b2[path]) if path in b2 else None,
    )

    def _upload(path, data, content_type):
        b2[path] = data
        return path

    monkeypatch.setattr(module.storage_service, "upload_bytes", _upload)
    monkeypatch.setattr(
        module.legacy_storage,
        "metadata",
        lambda path: (
            {"size": len(firebase[path]), "contentType": "application/pdf"}
            if path in firebase
            else None
        ),
    )
    monkeypatch.setattr(
        module.legacy_storage, "download_bytes", lambda path: firebase.get(path)
    )

    module._b2 = b2
    module._firebase = firebase
    return module


def test_a_dry_run_writes_nothing(migration):
    migration._firebase["users/u1/a.pdf"] = b"hello world"

    outcome = migration.migrate_one("users/u1/a.pdf", apply=False)

    assert outcome.status == "copied"
    assert "dry run" in outcome.detail
    assert migration._b2 == {}, "a dry run must not write"


def test_applying_copies_and_verifies(migration):
    migration._firebase["users/u1/a.pdf"] = b"hello world"

    outcome = migration.migrate_one("users/u1/a.pdf", apply=True)

    assert outcome.status == "copied"
    assert outcome.size == 11
    assert migration._b2["users/u1/a.pdf"] == b"hello world"


def test_a_second_run_skips_what_is_already_there(migration):
    migration._firebase["users/u1/a.pdf"] = b"hello world"
    migration._b2["users/u1/a.pdf"] = b"hello world"

    outcome = migration.migrate_one("users/u1/a.pdf", apply=True)

    # This is what makes re-running safe and nearly free.
    assert outcome.status == "already"


def test_a_size_mismatch_is_a_failure_not_an_overwrite(migration):
    # One of the two copies is wrong and a human has to say which. Silently
    # overwriting would destroy whichever one was right.
    migration._firebase["users/u1/a.pdf"] = b"the full document"
    migration._b2["users/u1/a.pdf"] = b"trunc"

    outcome = migration.migrate_one("users/u1/a.pdf", apply=True)

    assert outcome.status == "failed"
    assert "size mismatch" in outcome.detail
    assert migration._b2["users/u1/a.pdf"] == b"trunc", "must not overwrite"


def test_a_source_that_is_gone_is_reported_not_retried_forever(migration):
    outcome = migration.migrate_one("users/u1/vanished.pdf", apply=True)

    assert outcome.status == "missing"


def test_a_record_without_a_path_is_reported(migration):
    assert migration.migrate_one("", apply=True).status == "no_path"


def test_a_b2_outage_is_not_mistaken_for_absence(migration, monkeypatch):
    # If "could not ask" were read as "not there", a B2 outage would make the
    # migration re-upload the entire library.
    def _boom(path):
        raise ConnectionError("B2 unreachable")

    monkeypatch.setattr(migration.storage_service, "object_size", _boom)
    migration._firebase["users/u1/a.pdf"] = b"hello"

    outcome = migration.migrate_one("users/u1/a.pdf", apply=True)

    assert outcome.status == "failed"
    assert "could not check B2" in outcome.detail
    assert migration._b2 == {}


def test_a_truncated_upload_is_caught_by_the_read_back(migration, monkeypatch):
    # An unverified short write is a data-loss bug wearing a success message.
    migration._firebase["users/u1/a.pdf"] = b"the full document"

    def _short_upload(path, data, content_type):
        migration._b2[path] = data[:4]
        return path

    monkeypatch.setattr(migration.storage_service, "upload_bytes", _short_upload)

    outcome = migration.migrate_one("users/u1/a.pdf", apply=True)

    assert outcome.status == "failed"
    assert "expected" in outcome.detail


def test_a_transient_failure_is_retried(migration, monkeypatch):
    migration._firebase["users/u1/a.pdf"] = b"hello world"
    attempts = {"n": 0}
    real_upload = migration.storage_service.upload_bytes

    def _flaky(path, data, content_type):
        attempts["n"] += 1
        if attempts["n"] == 1:
            raise TimeoutError("network blip")
        return real_upload(path, data, content_type)

    monkeypatch.setattr(migration.storage_service, "upload_bytes", _flaky)
    monkeypatch.setattr(migration.time, "sleep", lambda seconds: None)

    outcome = migration.migrate_one("users/u1/a.pdf", apply=True)

    assert outcome.status == "copied"
    assert attempts["n"] == 2


def test_retries_are_bounded(migration, monkeypatch):
    migration._firebase["users/u1/a.pdf"] = b"hello world"
    attempts = {"n": 0}

    def _always_fails(path, data, content_type):
        attempts["n"] += 1
        raise TimeoutError("still down")

    monkeypatch.setattr(migration.storage_service, "upload_bytes", _always_fails)
    monkeypatch.setattr(migration.time, "sleep", lambda seconds: None)

    outcome = migration.migrate_one("users/u1/a.pdf", apply=True)

    assert outcome.status == "failed"
    assert attempts["n"] == migration.MAX_ATTEMPTS


# ---------------------------------------------------------------------------
# Resume
# ---------------------------------------------------------------------------


def test_state_survives_a_round_trip(migration, tmp_path):
    path = tmp_path / "state.json"
    state = migration.MigrationState()
    state.done["users/u1/a.pdf"] = "b2"
    state.failed["users/u1/b.pdf"] = "size mismatch"
    state.counters.copied = 3
    state.save(path)

    reloaded = migration.MigrationState.load(path)

    assert reloaded.done == {"users/u1/a.pdf": "b2"}
    assert reloaded.failed == {"users/u1/b.pdf": "size mismatch"}
    assert reloaded.counters.copied == 3


def test_state_is_written_atomically(migration, tmp_path):
    # An interrupt mid-write must not leave a half-written file that the next
    # --resume trusts and skips real work because of.
    path = tmp_path / "state.json"
    migration.MigrationState().save(path)

    assert json.loads(path.read_text(encoding="utf-8"))["done"] == {}
    assert not list(tmp_path.glob("*.tmp")), "the temporary file must be replaced"


def test_a_corrupt_state_file_starts_fresh_rather_than_crashing(migration, tmp_path):
    path = tmp_path / "state.json"
    path.write_text("{not json", encoding="utf-8")

    state = migration.MigrationState.load(path)

    assert state.done == {}
    assert state.counters.copied == 0


def test_a_missing_state_file_starts_fresh(migration, tmp_path):
    assert migration.MigrationState.load(tmp_path / "nope.json").done == {}
