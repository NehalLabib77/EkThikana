# What EkThikana needs from you

The source code is prepared, but no assistant can create your private production accounts, billing decisions, credentials, signing key, privacy policy identity, or Play Console ownership for you.

Do these items yourself.

## 1. Firebase project

Create a Firebase project and enable:

- Email/Password Authentication
- Cloud Firestore

Use Android application id:

```text
com.ekthikana.ekthikana
```

Then run:

```powershell
flutterfire configure
```

## 2. Firebase Admin credential

Generate a service-account JSON from Firebase.

Convert it to Base64 and put the Base64 value directly into:

- your local backend `.env`
- Render Environment Variables

Variable:

```text
FIREBASE_SERVICE_ACCOUNT_B64
```

**Do not paste the private key or service-account JSON into ChatGPT, GitHub, Flutter code, screenshots, or public documents.**

## 3. Supabase project for private file storage

Create a Supabase project and a private Storage bucket:

```text
ekthikana-files
```

Put these values only in backend/Render environment variables:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_BUCKET=ekthikana-files
```

Do not place the service-role key in Flutter.

## 4. Gemini key (optional until AI testing)

Create your own Gemini Developer API key and put it in the backend/Render only:

```text
GEMINI_API_KEY
GEMINI_MODEL=gemini-3.7-flash
```

Without this key, normal EkThikana features still work but AI note/PDF actions return “AI is not configured.”

## 5. Render account

Create a free Render Web Service from your GitHub repository.

Use:

```text
backend/
```

as the root directory and Docker runtime.

Add all variables listed in:

```text
backend/.env.example
```

## 6. Your real app identity

Before Play Store release, decide/provide:

- official developer/company name
- support email
- privacy-policy URL
- terms URL
- app icon/logo
- Play Store short and full descriptions
- screenshots
- content-rating answers
- whether you will enable Firebase Blaze later

## 7. Android signing and Play Console

You must own and protect:

- your Android upload/signing key
- Play Console developer account

Never send your signing key or passwords in chat.

## What you should send me if something fails

Safe things to paste:

- full terminal error
- Flutter/Gradle error
- Render build log with secrets redacted
- Firebase rules error
- screenshots that contain no secret keys

Do not send API keys or private credentials.
