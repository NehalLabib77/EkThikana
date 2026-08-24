# What You Need To Do From Now

> Build phase is complete. `EkThikana_Full_Production.zip` is ready, all backend tests pass, `flutter analyze` is clean, and `docs/FINAL_AUDIT.md` records every spec line as satisfied.
>
> The only remaining work is operator-side setup that requires **your** accounts, credentials, and decisions. Follow the steps below in order.

---

## Step 1 — Create the four external services (free tiers are enough)

### 1.1 Firebase project
1. Open https://console.firebase.google.com and click **Add project** → name it (e.g. `ekthikana-prod`) → continue.
2. In **Build → Authentication → Sign-in method**, enable **Email/Password**.
3. In **Build → Firestore Database**, click **Create database** → choose **Production mode** → pick a region close to your users.
4. In **Project settings → General → Your apps**, register an **Android app** with package id `com.ekthikana.ekthikana`.
5. (Optional) Register a **Web app** too — `flutterfire configure` will need it.

### 1.2 Supabase project
1. Open https://supabase.com and create a new project.
2. In **Storage**, click **New bucket** → name it `ekthikana-files` → set **Public bucket = OFF** (must stay private).
3. Copy the **Project URL** and the **`service_role` secret** from **Settings → API**. You will paste these into Render in Step 3.

### 1.3 Gemini API key
1. Open https://aistudio.google.com/app/apikey → **Create API key**.
2. Copy the key. Paste into Render in Step 3. Without it, all features except Study AI still work.

### 1.4 Render account
1. Open https://render.com and sign up.
2. Connect your GitHub account (you'll push the repo from Step 2 first, or upload the zip).

---

## Step 2 — Push the code to a fresh GitHub repo

The zip is the source. Either push the contents to GitHub or upload the zip directly to Render.

**Option A — push to GitHub (recommended for CI):**
1. Extract `EkThikana_Full_Production.zip` somewhere local.
2. Create a new empty GitHub repo (e.g. `ekthikana`).
3. From the extracted folder:
   ```bash
   git init
   git add .
   git commit -m "Initial EkThikana production code"
   git branch -M main
   git remote add origin https://github.com/<you>/ekthikana.git
   git push -u origin main
   ```
4. Make sure the repo is **private**.

**Option B — upload zip directly to Render** — skip GitHub, use Render's "Deploy from a zip" workflow. Note: this makes ongoing updates harder.

---

## Step 3 — Deploy the backend to Render

1. In Render, click **New → Web Service**.
2. Connect the GitHub repo from Step 2 (or upload the zip).
3. Configure:
   - **Root directory:** `backend`
   - **Runtime:** Docker
   - **Region:** pick the same region as your Firestore database
   - **Plan:** Free
4. Add the **Environment Variables** listed in `docs/FINAL_SETUP_GUIDE.md` §3 — fill in:
   - `FIREBASE_PROJECT_ID`
   - `FIREBASE_SERVICE_ACCOUNT_B64` (base64 of the service-account JSON from Firebase console → Project settings → Service accounts → Generate new private key)
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `SUPABASE_BUCKET` (= `ekthikana-files`)
   - `GEMINI_API_KEY`
   - `GEMINI_MODEL` (= `gemini-3.7-flash`)
   - `CORS_ORIGINS` (leave empty for now)
5. Click **Create Web Service**. First build takes ~3 minutes.
6. When the deploy succeeds, copy the URL Render gives you (e.g. `https://ekthikana-api.onrender.com`).

---

## Step 4 — Wire the Flutter app to your backend and Firebase

On your development machine:

1. Install Flutter ≥ 3.38 if you don't have it (`flutter doctor` to verify).
2. Install the FlutterFire CLI:
   ```bash
   dart pub global activate flutterfire_cli
   ```
3. Download your `google-services.json` from Firebase console (Project settings → General → Your apps → Android app → `google-services.json`) and place it at:
   ```
   flutter_app/android/app/google-services.json
   ```
4. From the `flutter_app/` folder, run:
   ```bash
   flutterfire configure
   ```
   Select your Firebase project and the Android app. This overwrites `flutter_app/lib/firebase_options.dart` with real values.
5. Open `flutter_app/lib/core/app_config.dart` and set:
   ```dart
   static const String apiBaseUrl = 'https://<your-render-url>';
   ```
6. From `flutter_app/`, run:
   ```bash
   flutter pub get
   flutter analyze    # should report 0 errors, 0 warnings
   ```

---

## Step 5 — Deploy Firestore rules and indexes

The repository contains `firebase/firestore.rules` and `firebase/firestore.indexes.json`. They must be deployed so client-side writes to sensitive collections are denied.

Easiest path — from the repo root:

1. Install Firebase CLI: `npm install -g firebase-tools`
2. Login: `firebase login`
3. From the repo root, run:
   ```bash
   firebase use --add                  # pick your project
   firebase deploy --only firestore:rules,firestore:indexes
   ```

This applies:
- Role immutability (`users/{uid}.role` cannot be changed by the client).
- `reports`, `ai_usage`, `upload_usage` collections are server-only (client writes denied).
- All indexes required by queries in `backend/app/routers/*.py` and Flutter screens.

---

## Step 6 — Build the Android release APK / AAB

From `flutter_app/`:

```bash
flutter build appbundle --release         # produces app-release.aab for Play Store
flutter build apk --release              # produces app-release.apk for direct install
```

Sign the bundle with your own upload key (see `docs/ANDROID_SETUP.md`). Keep the keystore safe — losing it means losing the ability to update the app.

For internal testing on a single device:
```bash
flutter install --release
```

---

## Step 7 — Smoke-test the live deployment

1. Install the APK on an Android device.
2. Register a Student account → confirm the verification email arrives → tap the link → sign in. The **Study** and **Groups** tabs must appear in the bottom nav.
3. Register a second account as General → the **Study** and **Groups** tabs must be **hidden**.
4. From the Student account: create a semester, a subject, a note. Upload a small PDF. Open the PDF in the reader; verify text search and page bookmark work.
5. From the General account: open the universal search — Student-only items must **not** appear.
6. `curl https://<your-render-url>/api/health` should return `{"ok": true}`.

---

## Step 8 — When something goes wrong

| Symptom | Where to look |
| --- | --- |
| Backend 500 on `/api/health` | Render → service → Logs (search for the latest stack trace) |
| `flutter analyze` shows errors | Run `flutter clean && flutter pub get` first |
| Email verification not arriving | Firebase console → Authentication → Templates → check the verification template is enabled |
| AI endpoints return "AI is not configured" | `GEMINI_API_KEY` is missing or wrong in Render env |
| Supabase upload fails | Bucket is private but service-role key is correct — double-check the key in Render env |
| Firestore rule denies legitimate write | Inspect the read/write in the Firebase console → Firestore → Rules playground |

Full troubleshooting: `docs/TROUBLESHOOTING.md`.

---

## Step 9 — Production checklist (don't skip)

Walk through `docs/PRODUCTION_CHECKLIST.md`. The list covers email verification, signed-URL TTL test, file-size limit test, role tampering rejection, AI daily quota, cold-start behaviour, app icon/branding replacement, and Play Console test on at least 3 Android versions.

---

## What you should NOT do

- Do not paste any service-account JSON, Supabase `service_role` key, Gemini key, or upload/signing key into chat, GitHub issues, screenshots, or public docs.
- Do not edit `firebase/firestore.rules` to allow client-side role changes or public writes to `reports` / `ai_usage` / `upload_usage`.
- Do not raise `SIGNED_URL_TTL_SECONDS` above 900 seconds (15 min) — the spec caps it.
- Do not add a chat or messaging UI to any group — the spec forbids it.

---

## Done when

Every line in `docs/PRODUCTION_CHECKLIST.md` is ticked, and the smoke test in Step 7 passes for both Student and General accounts.