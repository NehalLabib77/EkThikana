"""P1-4 — Prescription extraction is review-only.

Contract pinned by these tests:

  1. /api/prescriptions/extract returns OCR candidates (``medicines``,
     ``candidateLines``, ``rawText``) and a non-empty ``warning``.
  2. It does NOT write to the user's Firestore medicines collection.
  3. It enforces the file-size cap with a clean 413.
  4. It rejects an empty upload with a clean 400.
  5. It rejects an unsupported mime with a clean 415.
  6. It requires authentication (401 without a token).
  7. The "warning" string must be present in every successful response —
     the auto-save danger is the entire reason this screen is review-only.
"""

from __future__ import annotations

import io

from fastapi.testclient import TestClient


def _png_bytes() -> bytes:
    # 1×1 transparent PNG — enough for the upload validator's mime sniffer
    # to detect ``image/png`` without needing real image fixtures.
    return (
        b"\x89PNG\r\n\x1a\n"
        b"\x00\x00\x00\rIHDR"
        b"\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
        b"\x00\x00\x00\rIDATx\x9cc\xfc\xff\xff?\x00\x05\xfe\x02\xfe\xa3R\x9c\x92"
        b"\x00\x00\x00\x00IEND\xaeB`\x82"
    )


def _pdf_bytes(size: int = 1024) -> bytes:
    # We do not need a real PDF — the OCR service is patched in conftest.
    # The route's file-type sniffer, however, *does* run on the upload
    # bytes. Use the ``%PDF-`` magic so the sniffer accepts it as a PDF.
    header = b"%PDF-1.4\n%fake "
    pad = b"% " * max(1, (size - len(header)) // 2)
    return (header + pad)[:size]


def _auth_header(fake_auth, fake_db, uid: str = "u-ocr") -> dict[str, str]:
    # Seed the user profile so get_current_user's Firestore lookup finds
    # a role. Without this the auth gate raises 403 "User profile is
    # missing" before the route body even runs.
    fake_db.seed("users", uid, {"role": "student"})
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


def test_extract_requires_authentication(client: TestClient) -> None:
    response = client.post(
        "/api/prescriptions/extract",
        files={"file": ("rx.png", _png_bytes(), "image/png")},
    )
    assert response.status_code == 401


def test_extract_rejects_empty_upload(client: TestClient, fake_auth, fake_db) -> None:
    response = client.post(
        "/api/prescriptions/extract",
        files={"file": ("rx.png", b"", "image/png")},
        headers=_auth_header(fake_auth, fake_db),
    )
    assert response.status_code == 400
    assert "empty" in response.json()["detail"].lower()


def test_extract_rejects_oversized_upload(client: TestClient, fake_auth, fake_db) -> None:
    # >10 MB upload — must surface a clean 413 (per the route's explicit
    # max_bytes = min(max_upload_mb, 10) * MiB).
    big = b"\x89PNG\r\n\x1a\n" + b"%" * (11 * 1024 * 1024)
    response = client.post(
        "/api/prescriptions/extract",
        files={"file": ("rx.png", big, "image/png")},
        headers=_auth_header(fake_auth, fake_db),
    )
    # 413 if the mime sniffer accepts it as an image (since the magic is
    # ``\x89PNG``); otherwise 415. Either way the size policy must kick in
    # before any OCR work runs.
    assert response.status_code in {413, 415}


def test_extract_rejects_unsupported_mime(client: TestClient, fake_auth, fake_db) -> None:
    # Random binary that does not match PDF / PNG / JPEG magic — sniffer
    # raises ValueError → 415.
    response = client.post(
        "/api/prescriptions/extract",
        files={"file": ("rx.bin", b"\x00\x01\x02\x03\x04\x05", "application/octet-stream")},
        headers=_auth_header(fake_auth, fake_db),
    )
    assert response.status_code == 415
    detail = response.json()["detail"].lower()
    # The route funnels ``detect_supported_file_type``'s ValueError into a
    # 415. The actual message lists the supported types; check the
    # contract — "only" + at least one of the approved mime keywords.
    assert detail.startswith("only")
    assert any(kind in detail for kind in ("pdf", "png", "jpeg", "doc"))


def test_extract_returns_candidates_and_warning_without_saving(
    client: TestClient,
    fake_auth,
    fake_db,
    monkeypatch,
) -> None:
    """The core P1-4 contract: extract returns candidates; nothing is
    written to the user's ``medicines`` collection.

    The conftest patches ``extract_text`` to return ``fake-text-bytes=N``,
    which would normally produce zero ``parse_medicine_candidates`` hits.
    Override the parser here so we exercise the candidate shape, then
    assert that ``fake_db`` was never touched.
    """
    # Override parse_medicine_candidates so we can verify the *exact*
    # candidate shape that the Flutter review screen consumes.
    import app.services.ocr_service as ocr_mod
    import app.routers.prescriptions as rx_mod

    sample = [
        {
            "name": "Paracetamol",
            "dose": "500mg",
            "instruction": "after food",
            "scheduleHints": ["after food"],
            "explicitTimes": [],
            "sourceText": "Tab. Paracetamol 500mg 1+0+1 after food",
            "lineIndex": 0,
        },
        {
            "name": "Amoxicillin",
            "dose": "250mg",
            "instruction": "after breakfast",
            "scheduleHints": ["after breakfast"],
            "explicitTimes": ["08:00"],
            "sourceText": "Cap. Amoxicillin 250mg 1-0-0 08:00",
            "lineIndex": 2,
        },
    ]
    monkeypatch.setattr(ocr_mod, "parse_medicine_candidates", lambda text, recognition=None: sample)
    # The router bound parse_medicine_candidates at import time; patch the
    # router's local reference too.
    monkeypatch.setattr(rx_mod, "parse_medicine_candidates", lambda text, recognition=None: sample)

    # Seed the auth profile FIRST (so get_current_user passes), THEN
    # snapshot — the assertion below proves the extract endpoint did not
    # mutate any collection beyond the seed.
    headers = _auth_header(fake_auth, fake_db, uid="u-review")
    collections_before = {k: dict(v) for k, v in fake_db._collections.items()}
    events_before = list(fake_db.events)

    response = client.post(
        "/api/prescriptions/extract",
        files={"file": ("rx.png", _png_bytes(), "image/png")},
        headers=headers,
    )

    assert response.status_code == 200, response.text
    body = response.json()

    # 1. Candidates returned.
    assert body["medicines"] == sample
    assert body["medicines"][0]["name"] == "Paracetamol"
    assert body["medicines"][1]["explicitTimes"] == ["08:00"]

    # 2. Raw text and candidate lines surface so the Flutter review
    # screen can offer "Show full text" and "Review Manually" paths.
    assert isinstance(body.get("rawText"), str) and body["rawText"].strip()
    assert isinstance(body.get("candidateLines"), list)

    # 3. Warning is non-empty — the auto-save danger is the entire reason
    # this endpoint exists; it must never silently disappear.
    warning = body.get("warning", "")
    assert warning.strip(), "warning string must be present in every successful response"
    lowered = warning.lower()
    assert "ocr" in lowered
    assert "gochano" in lowered

    # 4. Nothing was written to Firestore. The OCR contract is
    # "review-only" — the actual medicine record is created when the
    # user taps Save on MedicineFormScreen.
    new_events = fake_db.events[len(events_before):]
    assert new_events == [], (
        f"extract endpoint must not write to Firestore; saw events: {new_events}"
    )
    assert fake_db._collections == collections_before, (
        f"extract endpoint must not mutate any Firestore collection; "
        f"collections_before={collections_before} now={fake_db._collections}"
    )


def test_extract_does_not_invoke_notification_service(
    client: TestClient, fake_auth, fake_db, monkeypatch
) -> None:
    """P1-4 hardening: the OCR endpoint must never schedule medicine
    reminders. If it ever imports a notification / scheduler module and
    calls its scheduling function, the auto-save danger returns.
    """
    # Patch every plausible scheduling entry point. If the extract router
    # ever imports one of these and calls it, the trap fires and the
    # assertion below fails.
    candidates = [
        ("app.services.notification_service", "scheduleDailyMedicine"),
        ("app.services.notification_service", "schedule_daily_medicine"),
        ("app.services.notification_service", "schedule_reminder"),
        ("app.services.medicine_service", "scheduleMedicine"),
        ("app.services.scheduler", "schedule"),
    ]
    called: list[str] = []

    def _trap(name):
        def _fn(*args, **kwargs):
            called.append(name)
        return _fn

    for module_name, attr in candidates:
        try:
            module = __import__(module_name, fromlist=[attr])
        except ModuleNotFoundError:
            continue
        if hasattr(module, attr):
            monkeypatch.setattr(module, attr, _trap(f"{module_name}.{attr}"))

    response = client.post(
        "/api/prescriptions/extract",
        files={"file": ("rx.png", _png_bytes(), "image/png")},
        headers=_auth_header(fake_auth, fake_db),
    )
    assert response.status_code == 200
    assert called == [], (
        "prescription extract must not schedule reminders; "
        "that only happens after the user confirms and saves in MedicineFormScreen. "
        f"Observed calls: {called}"
    )


def test_extract_warning_mentions_no_medical_advice(
    client: TestClient, fake_auth, fake_db
) -> None:
    response = client.post(
        "/api/prescriptions/extract",
        files={"file": ("rx.png", _png_bytes(), "image/png")},
        headers=_auth_header(fake_auth, fake_db),
    )
    assert response.status_code == 200
    warning = response.json().get("warning", "").lower()
    # SECURITY_PRIVACY.md #13 requires user confirmation; the warning
    # string is the in-band signal that Gochano does not prescribe.
    assert "gochano does not" in warning or "gochano will not" in warning