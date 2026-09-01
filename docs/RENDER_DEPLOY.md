# Render deployment

The backend is stateless and safe for Render's ephemeral filesystem. User files are stored in Supabase Storage and metadata in Firestore.

## Create the service

1. Push this repository to a private GitHub repository.
2. Render → New → Web Service.
3. Connect the repository.
4. Root directory:

```text
backend
```

5. Runtime: Docker.
6. Instance: Free.

Or use the included `backend/render.yaml` as a blueprint.

## Environment variables

Add these in Render:

```text
APP_ENV=production
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_SERVICE_ACCOUNT_B64=BASE64_FROM_SERVICE_ACCOUNT_JSON

SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_BUCKET=ekthikana-files

GEMINI_API_KEY=your-key
GEMINI_MODEL=gemini-3.7-flash

MAX_UPLOAD_MB=15
SIGNED_URL_TTL_SECONDS=3600
AI_DAILY_LIMIT=30
CORS_ORIGINS=*
```

Do not commit secrets.

## Health check

Set Render health check path to:

```text
/api/health
```

## Free-instance behavior

The Flutter API service uses long timeouts because a free Render service can take time to wake after idling.

No persistent file is written to the Render filesystem.
