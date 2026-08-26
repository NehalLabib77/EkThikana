# Storage setup

Gochano uses Supabase Storage as a private object bucket. All user-uploaded files (notes, materials, prescriptions, group shared box) live in this bucket. The bucket is **private** — direct reads are denied. Every read is mediated by the FastAPI backend, which mints short-lived signed URLs.

## Why Supabase

- Free tier covers development and small production workloads.
- Native support for short-lived signed URLs.
- Works with a single pair of credentials (`SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`).
- Decoupled from Firebase Storage so Firebase billing stays off until you intentionally turn it on.

## Step 1 — Create the project

1. Create a free Supabase project.
2. Note the **Project URL** and the **service role key** from `Project Settings → API`.
3. The service-role key bypasses row-level security. It never leaves the backend. **Do not paste it into Flutter.**

## Step 2 — Create the bucket

In the Supabase dashboard:

1. Storage → **New bucket**.
2. Name: `ekthikana-files`.
3. Visibility: **Private**.
4. Do not enable public access.

## Step 3 — Provide credentials to the backend

### Local development (`backend/.env`)

```env
SUPABASE_URL=https://YOUR-PROJECT.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...
SUPABASE_BUCKET=ekthikana-files
```

### Render

Render uses a different variable name. In the service's Environment tab set:

| Variable                     | Value                                  |
| ---------------------------- | -------------------------------------- |
| `SUPABASE_URL`               | `https://YOUR-PROJECT.supabase.co`     |
| `SUPABASE_SERVICE_ROLE_KEY`  | service-role secret from Supabase      |
| `SUPABASE_BUCKET`            | `ekthikana-files`                      |

`get_settings()` in `backend/app/core/config.py` reads both names, so a copy-paste between local `.env` and Render works without translation.

## Step 4 — Test the upload path

```powershell
cd backend
py -m uvicorn app.main:app --reload
```

Then from Flutter, sign in as a Student, upload a small PDF to a private material. Confirm:

1. Upload succeeds (200 response, returns `{ "id": "..." }`).
2. Signed-URL fetch returns a 60-second URL pointing to `https://YOUR-PROJECT.supabase.co/...`.
3. Opening the URL in a browser works within the TTL window.
4. After TTL expiry, the URL returns 403 from Supabase.

If any of these fail, check the bucket name and the service-role key. The backend raises `RuntimeError("Supabase storage credentials are not configured")` if either is missing.

## Step 5 — Backup and lifecycle

Supabase free tier does not support lifecycle policies. Treat the bucket as durable enough for normal use; do not rely on it as the sole copy of any user file. When the user deletes their account, `DELETE /api/account` removes the metadata and asks Supabase to remove the binaries (`storage_service.delete_file`).

If a user deletes a material but the binary lingers, the next `admin garbage collection` you write should sweep `users/{uid}/*` prefixes whose Firestore metadata no longer exists.

## Notes

- The bucket name is `ekthikana-files`. If you change it, change `SUPABASE_BUCKET` in both local and Render env. The path structure used inside the bucket is `users/{uid}/{random}_{filename}` — the leading `users/` is significant for any future prefix-based policies.
- The service-role key has full admin rights to your Supabase project. If you suspect it leaked, rotate it from the dashboard; treat it like a database root password.
- Do not enable public access on `ekthikana-files` "to make life easier". The entire security model assumes the bucket stays private.
