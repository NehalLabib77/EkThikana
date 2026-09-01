# If you later want Firebase Storage

The codebase defaults to Supabase Storage so the initial build can avoid enabling Firebase billing.

If you later enable Firebase Blaze:

1. Create a Firebase Storage bucket.
2. Add a Firebase storage adapter in `backend/app/services/storage_service.py`.
3. Keep the same `filePath` field in Firestore.
4. Switch storage provider through environment configuration.

Do not store user PDFs/images directly on Render's local filesystem.
