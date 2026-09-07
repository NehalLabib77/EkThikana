# Gochano

**"One place for everything"**
Gochano is a student-focused Android super app, offering tools for study planning, finance management, medicine reminders, intelligent commuting (CommuteBD), AI assistance, and document tracking in a single platform.

## Main Technology

- **Frontend:** Flutter
- **Backend:** FastAPI
- **Authentication & Real-time:** Firebase Auth, Firestore, FCM
- **Telecom Login:** bdApps telecom subscription authentication
- **Database:** Neon PostgreSQL with PostGIS extension
- **AI Providers:** Groq (Primary), Gemini (Fallback)
- **Storage:** Backblaze B2
- **Hosting:** Render
- **Routing & Maps:** OSM, OSRM, CommuteBD datasets

## Top-Level Folder Structure

- flutter_app/ - The Flutter Android application.
- backend/ - The FastAPI backend, ML models, scripts, and service integrations.
- docs/ - Essential project documentation (e.g., PostgreSQL runbook).
- firebase/ - Firebase Firestore rules and index configurations.
- supabase/ - PostgreSQL migrations and schema definitions for the database.
- tool/ - Useful build and delivery scripts (e.g., make_delivery.ps1).

## Important Flutter Structure (flutter_app/)

- lib/core/ - Foundational architecture (design system, navigation, localization, routing).
- lib/features/ - Core application modules (auth, community, home, life, profile, search, shell, study, tasks).
- lib/models/ - Shared data models.
- lib/services/ - External API and service communication layers.
- lib/shared/ - Shared state and UI widgets across the app.
- lib/widgets/ - Common UI elements.
- assets/ - Fonts, branding, localized data, and CommuteBD assets.
- android/ - Android native configuration, Gradle scripts, and app manifest.

## Important Backend Structure (backend/)

- app/main.py - FastAPI application entrypoint.
- app/routers/ - API route controllers (commute, study, ai, health, telecom, etc.).
- app/core/ - Security, authentication, and core configuration logic.
- app/services/ - Business logic (AI processing, OCR, routing engine, commute quality checking).
- app/database/ - SQLAlchemy models, connection management, and repositories.
- data/ - CommuteBD and medicine datasets, ML training templates.
- migrations/ & alembic/ - Database schema migrations.
- scripts/ - Operational scripts for database import, migration, and verification.

## Important Configuration Files

- pubspec.yaml (in flutter_app/) - Flutter dependencies and asset definitions.
- requirements.txt (in backend/) - Python dependencies for the backend.
- firebase.json (root) - Firebase deployment rules.
- backend/.env.example - Template for backend environment variables.
- .gitignore - Git ignore rules for the entire repository.
- backend/render.yaml - Blueprint for Render deployment.

## Run Commands

To verify and test the Flutter application locally:

cd flutter_app
flutter pub get
flutter analyze
flutter test

## Production Endpoint

The backend is currently deployed to:
https://ekthikana-api-x473.onrender.com

## Environment Variables

The backend relies on the following environment variables (defined in .env.example):

- APP_ENV, CORS_ORIGINS
- FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT_B64
- SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_BUCKET (legacy)
- DATABASE_URL (Neon PostgreSQL)
- B2_BUCKET_NAME, B2_ENDPOINT_URL, B2_REGION, B2_KEY_ID, B2_APPLICATION_KEY
- GROQ_API_KEY, GROQ_MODEL
- GEMINI_API_KEY, GEMINI_MODEL
- MAX_UPLOAD_MB, USER_STORAGE_LIMIT_MB, UPLOAD_DAILY_LIMIT, SIGNED_URL_TTL_SECONDS, AI_DAILY_LIMIT
- ROUTING_PROVIDER, OSRM_BASE_URL, NOMINATIM_BASE_URL, ROUTING_USER_AGENT
- COMMUTE_ML_MIN_TOTAL_REPORTS, COMMUTE_ML_MIN_MODE_REPORTS
