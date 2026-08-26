# Gochano troubleshooting

Quick recipes for the issues you're most likely to hit during local dev, Render deploy, or Play Console review.

## Backend

### `uvicorn` exits with "Supabase storage credentials are not configured"

`backend/.env` is missing `SUPABASE_URL` or `SUPABASE_SERVICE_ROLE_KEY`. Both are required for uploads, signed URLs, and downloads. See `docs/RENDER_DEPLOY.md` for the Render equivalents.

### `firebase_admin` raises "default app already exists"

The Admin SDK is being initialised twice. Check that no test script or worker is also calling `firebase_admin.initialize_app(...)`. The app uses `initialize_app(credentials.Certificate(...), {'projectId': ...})` exactly once.

### `pytest` ImportError: No module named `pydantic_settings`

Install the dev deps:

```powershell
cd backend
py -m pip install -r requirements.txt
```

### `pytest` ImportError: `pydantic_settings` import succeeds but a real `supabase` is being imported instead of the stub

The conftest stub for `supabase` only wins if it is installed on `sys.modules` before `app.main` is imported. The shared conftest at `backend/tests/conftest.py` does this; if you write your own test, import `tests.conftest` fixtures via `client` rather than re-creating the FastAPI app from scratch.

### AI route returns `503 AI is not configured`

`GEMINI_API_KEY` is empty in `backend/.env`. The route is intentionally disabled when the key is missing so the rest of the app keeps working.

### AI route returns `429 Daily AI limit reached`

The user exceeded `AI_DAILY_LIMIT`. Increase the limit in `backend/app/core/config.py` (default 30) or wait 24 hours.

### Delete-account cascade misses some materials

Check `backend/.env` for Supabase credentials — without them the binary side cannot be deleted, but the Firestore metadata still goes. The cascade logs but does not raise on individual storage failures.

### Local `uvicorn` works but Render returns 401

Render env vars are missing `FIREBASE_SERVICE_ACCOUNT_B64` or the value is not valid base64 of a service-account JSON. Decode the rendered value once and confirm it round-trips through `json.loads`.

## Flutter

### `flutterfire configure` says no Firebase project found

Run `firebase login` and `firebase use --add` first. Then re-run `flutterfire configure` and pick the same project alias (`default`).

### App stuck on "Verifying email…" forever

The user has not clicked the verification link. Email verification is a hard gate on every data route — there is no bypass.

### PDF reader says "Could not create signed URL"

Backend cannot reach Supabase, or the file no longer exists. Open `backend/app/routers/materials.py` `material_url` and look for the 502 response — that means Supabase rejected the request. Most often it is a missing or expired `SUPABASE_SERVICE_ROLE_KEY`.

### Search returns no results for notes/materials

You are signed in as a General account. The universal search hides notes and materials for non-Student accounts by design (§27). Sign up a Student account to see those.

### `flutter run` says `Connection refused`

The device cannot reach your PC's backend. Check:

```powershell
ipconfig
```

Then re-run with the LAN IPv4:

```powershell
flutter run --dart-define=API_BASE_URL=http://YOUR.PC.IP:8000
```

Phone and PC must be on the same Wi-Fi.

### `flutter analyze` warns about `print(...)` calls

Production builds run `flutter analyze --fatal-infos`. Replace any `print` calls with `debugPrint` or remove them.

### Local notifications never appear on Android 13+

`POST_NOTIFICATIONS` permission is not granted. The `NotificationService` requests it at first use; if the user denied it, the OS dialog never reappears. They must enable it from system settings.

## Render

### First request after idle takes 30–60 seconds

Free-tier services sleep. This is expected. The Flutter client surfaces a retry banner instead of a hard error.

### Build fails on `pip install` step

`backend/requirements.txt` is pinned; the platform-specific wheels for `pypdf`, `pdf2image`, and `pillow` should install cleanly on Render's Linux image. If a wheel is missing, set `PIP_PREFER_BINARY=1` in the Render service environment.

### Deploy succeeds but `/api/health` returns 404

The Render service is running an older build. Trigger a manual redeploy from the Render dashboard and watch the build log for `Starting service with uvicorn` followed by `Application startup complete`.

## Firestore rules

### `Missing or insufficient permissions` on first read

The user is not verified. Email verification is required. The rule denies data access to unverified accounts even if they own the document.

### Cannot change `users.role` after sign-up

By design — see `firebase/firestore.rules`. Roles are immutable from the client. Use a new account to change role.

### Cannot read another user's group material

You are not in `memberIds`. Group material access requires membership; there is no chat or open read.

## Performance

### Cold start of the backend is slow on first PDF question

The Gemini route warms up lazily. The first request after deploy takes longer than subsequent ones. This is provider-side and cannot be optimised by the backend.

### PDF reader hangs on very large files

`pdfrx` loads the entire file into memory. Files larger than ~50 MB may stutter. The backend enforces a max upload size (`MAX_UPLOAD_MB`, default 50 MB) so this should be rare in practice.