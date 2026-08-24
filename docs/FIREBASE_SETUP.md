# Firebase setup

EkThikana uses Firebase Authentication (email/password) and Cloud Firestore. This doc covers the one-time console work and the credential handoff to the backend. The Flutter app talks to Firebase directly; the FastAPI backend talks via the Firebase Admin SDK.

## 1. Create a project

1. Open the Firebase console.
2. Project name: `ekthikana-prod` (or anything you like — the project id is what matters).
3. Disable Google Analytics if you do not need it (saves a confirmation step).

## 2. Enable Authentication

1. Build → Authentication → Get started.
2. Sign-in method → **Email/Password** → Enable → Save.

No other provider is required.

## 3. Enable Firestore

1. Build → Firestore Database → Create database.
2. Choose region close to your Render service region.
3. Start in **production mode** — the rules file in `firebase/firestore.rules` is already locked down.

## 4. Configure Flutter

```powershell
cd flutter_app
dart pub global activate flutterfire_cli
flutterfire configure
```

Select the project from step 1, the Android platform, and confirm the application id `com.ekthikana.ekthikana`. This writes `flutter_app/lib/firebase_options.dart`.

## 5. Deploy rules + indexes

The repo already contains `firebase/firestore.rules` and `firebase/firestore.indexes.json`. From the repo root:

```powershell
firebase use --add
firebase deploy --only firestore
```

This uploads rules and creates the composite indexes Firestore will need for `array_contains` + equality queries.

## 6. Service account for the backend

Firebase Console → Project settings → **Service accounts** → Generate new private key.

Save the JSON locally. Convert to one-line base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\service-account.json"))
```

The output becomes `FIREBASE_SERVICE_ACCOUNT_B64` in `backend/.env` (local) and in Render's environment (production).

The backend decodes this at startup. If decoding fails or the JSON is malformed, the backend will fail to boot — there is no silent fallback.

## 7. Email verification

`firestore.rules` denies data access to unverified accounts. Verify the template:

1. Authentication → Templates → Email address verification.
2. From address: a domain you control (the default `noreply@…` works for development).
3. Subject and body: at minimum mention "EkThikana" so users know what they are verifying.

## 8. What lives where

- **Flutter ↔ Firestore**: direct reads/writes under the user's `ownerId`. Rules enforce owner-only writes for personal collections.
- **Flutter ↔ Firebase Auth**: sign-in / sign-up / sign-out / email verification.
- **Backend ↔ Firebase Admin**: privileged writes for account deletion, quotas, reports, group cleanup, and `users` profile creation during sign-up.
- **Backend cannot access Cloud Storage** (we use Supabase). It does not need the Firebase Storage SDK.

## 9. Production checklist

Before the first public launch:

- Disable Firebase Authentication "Email enumeration protection" only if you want public sign-ups to return distinct errors for "user exists" vs "wrong password" (default is more privacy-friendly).
- Add the privacy-policy URL to Firebase Authentication settings.
- Add a support email to Firebase project settings so email-template replies route somewhere.
- Review `firestore.rules` and remove any leftover `allow read, write: if true` lines before launch. The committed file should be tight already.

## 10. Common errors

### `auth/invalid-api-key`

`firebase_options.dart` was not regenerated after creating the project, or the API key in the Firebase console is restricted to specific package names. Check both.

### `permission-denied` on first Firestore read

The signed-in user's email is not verified. Rules block data access until verification completes.

### `Failed to fetch` from the Flutter app

The device cannot reach Firebase. Check the device has internet, the package name matches the one registered in the Firebase console, and the SHA-1 of the debug keystore is registered (for Google Sign-In; not required for email/password but useful to add early).

### `Missing or insufficient permissions` on backend writes

The service account is missing the **Firebase Admin SDK Administrator** or **Cloud Datastore Owner** role. Generate a new private key with default roles from the console.
