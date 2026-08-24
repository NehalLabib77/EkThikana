# Security and privacy decisions

1. Firebase ID tokens are verified by FastAPI before protected API operations.
2. Email verification is required for app data access.
3. User role is stored in `users/{uid}` and Firestore rules prevent changing the role after profile creation.
4. General users cannot access student-only Firestore collections.
5. Groups have no chat.
6. Group material access requires membership.
7. Public academic material is available only to authenticated Student users.
8. Supabase bucket is private. The service-role key exists only on the backend.
9. Downloads use short-lived signed URLs.
10. Render local disk is not used as permanent storage.
11. AI API keys never ship in the Flutter application.
12. Prescription extraction uses OCR; it does not automatically save medicine information.
13. Users must confirm prescription-derived information before creating a medicine record.
14. Automatic question/MCQ generation is intentionally absent.

## AI privacy

The free tier of an AI provider can have different data-use terms from paid tiers. Before a public launch, review the provider's current privacy/data-retention terms and disclose AI processing in the privacy policy.

Do not use the Study AI endpoint for medical or other highly sensitive content.
