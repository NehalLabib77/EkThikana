# Gochano branding: what changed and what you should NOT rename

## Already changed in source

- Flutter app name / MaterialApp title -> Gochano
- Android launcher label -> Gochano
- Login/setup/error/reminder user-facing brand text -> Gochano
- pubspec project name/description -> Gochano
- documentation -> Gochano current scope

## Keep these technical identifiers unless you intentionally migrate infrastructure

### Android package/application ID
`com.ekthikana.ekthikana`

Keep it because Firebase Android registration and an existing Play Store identity are tied to it. Renaming the visible app does not require changing this ID.

### Supabase bucket
`ekthikana-files`

You may keep it. It is private infrastructure, not user-facing. Renaming it would require moving objects and changing Render env `SUPABASE_BUCKET`.

### Render service
An existing `ekthikana-api` service/URL may remain. Changing the service name is optional and may change deployment/URL behavior.

### Notification channel IDs
Legacy internal channel IDs can remain even though the displayed channel names say Gochano. IDs are not user-facing and changing them creates new Android channels.

## Operator actions

1. Confirm Firebase CLI targets the real project: `firebase use`.
2. Current FlutterFire project id is `gochano-a30c8`; `.firebaserc` is aligned to it in this ZIP.
3. If this is not your intended Firebase project, run `firebase use --add` and `flutterfire configure` before deploying.
4. Ensure Firestore `(default)` database exists, then run `firebase deploy --only firestore`.
5. Reuse your existing Render/Supabase/Gemini keys; do not regenerate them simply because of the brand rename.
6. Replace the generic Flutter launcher icon with your final Gochano icon before store release if you have one.
