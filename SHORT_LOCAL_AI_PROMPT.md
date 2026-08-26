# Short Local-AI Continuation Prompt

Read the **entire existing Gochano project first**. Do **not rebuild** or rewrite working unrelated features.

The latest user requirement is the Gochano production update: LifeHub must contain only **Medicine, BazarBuddy, Daily Expenses, CommuteBD**; use **one idempotent central financial ledger** for Daily/Bazar/Medicine-Taken/Commute-Actual-Fare plus separate Savings; Medicine supports manual + OCR confirmation, unit/pack pricing, Taken/Skipped/Missed history and Taken-only cost; CommuteBD uses a real map, supplied dataset, deterministic BRTA/Metro fares, crowd/ML only for uncertain market fares, source/confidence labels, and actual-fare-only expense creation. Remove RentMate/FamilyHub/Wellness. Preserve Student/General roles, Study, Firebase, FastAPI, Supabase, OCR, notifications, bilingual UI, security, and no chat/MCQ/question generation.

First compare current code with the latest requirements and **fix only missing/broken/insecure/inconsistent parts**. Also update `PROJECT_SPEC.md`, `TODO.md`, README and docs because some still reflect the old scope.

Mandatory before finishing:
- run `flutter pub get`, `flutter analyze`, `flutter test`
- run backend tests
- fix all errors
- audit duplicate/orphan financial transactions and retry safety
- verify Student/General security and Firestore rules
- verify OCR never auto-saves medicine details/schedules
- verify Commute estimates do not create expenses; only confirmed actual fare does
- verify no fabricated transport/live data
- remove obsolete LifeHub references/dead routes
- test Firebase/Supabase/Render configuration paths
- update TODO with exact remaining external-credential/device tasks

Do not stop at explanations. Modify the existing files. At the end give: (1) changed files, (2) tests/results, (3) remaining external steps, (4) whether it is genuinely production-ready.
