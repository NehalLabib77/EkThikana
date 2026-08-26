# EkThikana UI + API Error + Medicine OCR Update

This patch was built from the uploaded `lib(3).zip` and `backend(3).zip`.

## What was fixed

1. Flutter no longer calls `jsonDecode()` blindly on a plain-text Render `500 Internal Server Error` response. It now surfaces a readable server error.
2. FastAPI has a global JSON exception handler, so unhandled backend failures return JSON and the full traceback remains in Render logs.
3. `127.0.0.1:8000` is no longer a silent default. On a physical phone, localhost points to the phone itself. Build with your Render HTTPS URL or use `adb reverse` during local testing.
4. Study-plan timestamp handling was hardened.
5. The old gray/basic scaffold UI was replaced on the key reference screens with the latest purple/pastel EkThikana visual system: Home, Study Hub, AI, Life Hub, Medicine/OCR, BazarBuddy, Tasks, Profile and PDF reader controls.
6. English/Bangla is a real single-language toggle on the updated screens (not both languages shown at once).
7. Medicine OCR now uses Tesseract with image preprocessing and Bengali+English OCR support on Render.
8. OCR parses likely medicine names, visible doses, schedule shorthand/meal hints, and explicit clock times from the prescription.
9. EkThikana **does not invent a medicine time**. The user must review and choose at least one real reminder time before anything is saved.
10. Confirmed medicine times schedule repeating Android local notifications.

## Why your screenshots showed those errors

### `FormatException: Unexpected character ... Internal Server Error`
The Flutter client assumed every HTTP body was JSON. Render/FastAPI sometimes returned the plain text `Internal Server Error`, so `jsonDecode()` itself crashed and hid the real API problem.

### `SocketException ... address = 127.0.0.1 ... /api/account/export`
The APK was started with `API_BASE_URL=http://127.0.0.1:8000`. On a physical phone that address means the phone, not your PC or Render service.

## Apply automatically

Extract this patch somewhere, for example:

```text
D:\EkThikana_Updated_UI_OCR
```

Then PowerShell:

```powershell
cd D:\EkThikana_Updated_UI_OCR
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\APPLY_PATCH.ps1 -ProjectRoot "D:\EkThikana_Full_Production"
```

The script creates backups before replacing files and runs `flutter pub add image_picker`, `flutter clean`, `flutter pub get`, and `flutter analyze`.

If your real project folder has another name, change `-ProjectRoot`.

## Redeploy the backend

Commit/push the changed backend after reviewing that no `.env` file is staged:

```powershell
cd D:\EkThikana_Full_Production
git status
git add backend flutter_app/lib
git commit -m "Fix API errors and add EkThikana UI medicine OCR"
git push
```

If Render auto-deploy is enabled it will rebuild. The updated Dockerfile installs:

```text
tesseract-ocr
tesseract-ocr-eng
tesseract-ocr-ben
poppler-utils
```

Wait until Render shows **Live**, then test:

```powershell
Invoke-RestMethod https://YOUR-SERVICE.onrender.com/api/health
```

## Rebuild the Android app with Render URL

```powershell
cd D:\EkThikana_Full_Production\flutter_app
flutter clean
flutter pub get
flutter analyze
flutter run --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

For a release APK/AAB, use the same define:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
flutter build appbundle --release --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

## Local backend alternative

If the backend runs on your PC and a USB Android phone is connected:

```powershell
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Without `adb reverse`, use the PC's Wi-Fi IPv4 instead of 127.0.0.1.

## Medicine OCR test

1. Open Life → Medicine.
2. Tap Upload Prescription.
3. Choose Gallery/PDF or Camera.
4. Wait for OCR.
5. Review every extracted medicine name/dose/instruction.
6. Schedule phrases such as `1+0+1` are shown only as **OCR hints**.
7. Explicit printed times, if detected, can appear as candidate times.
8. Confirm/add the actual reminder time yourself.
9. Tap Confirm & Save Reminders.
10. Verify the medicine appears in Today's Schedule and an Android notification is scheduled.

The prescription workflow deliberately requires confirmation because OCR can be wrong and EkThikana is not providing medical advice.
