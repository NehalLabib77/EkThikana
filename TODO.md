# Gochano — Final Release TODO

## Implemented in source

- [x] Gochano user-facing branding
- [x] Student/General role architecture
- [x] Study workspace, PDF reader, groups/shared box, Student Community Library, Study Planner
- [x] No MCQ/question/quiz generation and no chat/messaging
- [x] LifeHub limited to Medicine, BazarBuddy, Daily Expenses, CommuteBD
- [x] Medicine manual + OCR-confirmation flow and Taken-only cost logic
- [x] Central idempotent spending ledger for daily/bazar/medicine/commute
- [x] Savings/cash-flow/net-difference removed from active product scope
- [x] CommuteBD real-map/routing/fare-engine architecture and supplied dataset bundle
- [x] Profile monthly spending breakdown
- [x] Firestore expense-only rules updated
- [x] Account export/delete active collections updated; old savings/removed modules are legacy cleanup only
- [x] No standalone `Community Library / Browse Resources` promo block on Study dashboard

## Must be run locally / in your accounts

- [ ] `flutter clean && flutter pub get && flutter analyze && flutter test`
- [ ] backend `pytest -q`
- [ ] `firebase use --add` only if your selected project differs from `gochano-a30c8`
- [ ] ensure Firestore `(default)` database exists
- [ ] `firebase deploy --only firestore`
- [ ] apply any pending Supabase DB migration/import needed by CommuteBD
- [ ] push latest backend to GitHub and let Render redeploy
- [ ] verify Render env variables (reuse existing keys; do not regenerate them just for Gochano rename)
- [ ] test Gemini, OCR, private Supabase files and Commute route/fare paths on real device
- [ ] test duplicate-expense safety for Bazar/Medicine/Commute retries
- [ ] create `android/key.properties` + release keystore
- [ ] build signed AAB with production Render HTTPS URL
- [ ] optionally replace generic Flutter launcher icon with final Gochano icon
