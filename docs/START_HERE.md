# START HERE — exact order

Do these steps in this exact order.

## Stage 1 — Install tools on your Windows PC

Install:

1. Flutter stable.
2. Android Studio with Android SDK.
3. Git.
4. Node.js.
5. Python 3.11+.
6. VS Code or Android Studio as your editor.

Then run:

```powershell
flutter doctor
```

Fix every Android item marked with a red X before continuing.

## Stage 2 — Create Firebase

Use your existing Firebase project. The current checked-in FlutterFire config points to `gochano-a30c8`; do not create another project just because the app was renamed.

Enable:

1. Authentication → Sign-in method → Email/Password.
2. Firestore Database → create a database.

Do **not** enable Cloud Storage unless you intentionally choose Firebase Blaze billing.

Your Android application id in this project is:

```text
com.ekthikana.ekthikana
```

Install Firebase CLI and FlutterFire CLI:

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
```

## Stage 3 — Build the Flutter Android shell

Open PowerShell in:

```text
Gochano_Full_Production_Starter\flutter_app
```

Run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
..\tool\bootstrap_flutter_windows.ps1
```

Then configure Firebase:

```powershell
flutterfire configure
```

Select your Firebase project and Android platform. Confirm the Android package is:

```text
com.ekthikana.ekthikana
```

Then:

```powershell
flutter pub get
```

## Stage 4 — Deploy Firestore rules/indexes

The repository already contains `firebase.json`, Firestore rules and indexes.

From the repository root:

```powershell
firebase use --add
```

Select your Firebase project and give the alias `default`.

Then deploy:

```powershell
firebase deploy --only firestore
```

## Stage 5 — Create free file storage

Create a Supabase project.

Create a **private** Storage bucket named:

```text
ekthikana-files
```

You need two values later:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
```

Never place the service-role key in Flutter.

## Stage 6 — Create Firebase Admin credentials

Firebase Console → Project settings → Service accounts → Generate new private key.

Save the JSON on your PC. Do not commit it.

Convert it to one-line Base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\service-account.json"))
```

Keep the result. It will become:

```text
FIREBASE_SERVICE_ACCOUNT_B64
```

in Render.

## Stage 7 — Optional AI key

For study AI, create a Gemini Developer API key in Google AI Studio.

The backend expects:

```text
GEMINI_API_KEY
GEMINI_MODEL=gemini-3.7-flash
```

You may leave the key empty initially. Everything except AI actions will still work.

Important: do not send prescription images/text to the AI route. Prescription extraction in this project uses OCR locally on the backend.

## Stage 8 — Test backend locally

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
```

Fill `.env` with your credentials.

Run:

```powershell
uvicorn app.main:app --reload
```

Open:

```text
http://127.0.0.1:8000/api/health
```

## Stage 9 — Run Flutter against local backend

Find your PC IPv4 address:

```powershell
ipconfig
```

Keep phone and PC on the same Wi-Fi.

Run from `flutter_app`:

```powershell
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_IP:8000
```

Test in this order:

1. Register a Student account.
2. Verify email.
3. Login.
4. Create semester and subject.
5. Create note.
6. Create a group.
7. Upload a PDF to the group Shared Box.
8. Open PDF.
9. Search PDF text.
10. Bookmark a page.
11. Add a page note.
12. Close and reopen to verify resume.
13. Publish a note/material.
14. Login with another Student and test Community.
15. Create a General account and confirm Study/Groups are not visible.
16. Create a task/reminder.
17. Test Medicine, BazarBuddy, Daily Expenses and CommuteBD, including central expense sync.

## Stage 10 — Deploy backend to Render

Follow `docs/RENDER_DEPLOY.md`.

## Stage 11 — Point Flutter to Render

After Render gives you a URL:

```text
https://YOUR-SERVICE.onrender.com
```

run:

```powershell
flutter run --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

## Stage 12 — Release preparation

Only after all tests pass:

1. Replace placeholder branding/icon.
2. Create privacy policy and terms.
3. Create Android signing key.
4. Build release App Bundle.
5. Internal-test on Play Console.
6. Test Firestore rules with multiple accounts.
7. Test abuse limits and file-size limits.
8. Test Render cold-start behavior.
