# Gochano production checklist

## Build
- [ ] `flutter pub get`
- [ ] `flutter analyze` has no errors
- [ ] `flutter test` passes
- [ ] backend `pytest -q` passes
- [ ] signed Android release AAB builds

## Firebase
- [ ] correct project selected (`firebase use`)
- [ ] Firestore `(default)` database exists
- [ ] `firebase deploy --only firestore` succeeds
- [ ] Student/General rules tested with separate accounts

## Core Study
- [ ] semester -> subject -> notes/materials
- [ ] PDF reader/search/resume/bookmarks/page notes
- [ ] groups/shared box works; no chat
- [ ] Community Library is Student-only
- [ ] no standalone Community Library/Browse Resources promo block on Study dashboard
- [ ] no MCQ/question/quiz generation

## LifeHub
- [ ] Medicine manual entry
- [ ] Prescription OCR -> review/edit/confirm before save
- [ ] Taken-only medicine expense and actual quantity
- [ ] Bazar purchased/unpurchased expense sync
- [ ] Daily Expenses daily/month/calendar/year history
- [ ] Commute real route, km, ETA and fare transparency
- [ ] estimated Commute fare creates no expense
- [ ] confirmed actual fare creates exactly one expense
- [ ] RentMate/FamilyHub/Wellness absent from active app
- [ ] no Savings/cash-flow/net-difference feature

## Cloud
- [ ] existing Supabase private bucket works
- [ ] Commute DB migration/import applied if required
- [ ] Render redeployed latest commit
- [ ] `/api/health` succeeds
- [ ] Gemini Study AI succeeds
- [ ] OCR succeeds in Render image
- [ ] no secret keys embedded in Flutter/Git

## Release
- [ ] production build uses Render HTTPS API URL, not localhost
- [ ] notification permission/reminders tested on device
- [ ] offline/cold-start/error states tested
- [ ] account export/delete tested with disposable account
- [ ] privacy policy / Play Store Data Safety prepared
- [ ] final Gochano launcher icon supplied if replacing generic Flutter icon
