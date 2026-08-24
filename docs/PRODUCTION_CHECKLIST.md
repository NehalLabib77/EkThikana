# EkThikana production checklist

## Functional
- [ ] Student registration/login/email verification
- [ ] General registration/login/email verification
- [ ] General user cannot see Study or Groups
- [ ] Semester/subject creation
- [ ] Private note
- [ ] Group note
- [ ] Public note
- [ ] PDF/image upload
- [ ] PDF reader
- [ ] PDF text search
- [ ] last-page resume
- [ ] page bookmark
- [ ] page-linked note
- [ ] save material to library
- [ ] offline download
- [ ] Community Library
- [ ] Community search/filter/sort
- [ ] report public/group content
- [ ] group creation
- [ ] invite-code join
- [ ] leave group
- [ ] admin invite-code reset
- [ ] Shared Box
- [ ] no group chat UI/endpoints
- [ ] note AI actions
- [ ] PDF Q&A
- [ ] no MCQ/question-generation feature
- [ ] tasks
- [ ] reminders
- [ ] Medicine
- [ ] prescription OCR review + explicit confirmation
- [ ] BazarBuddy
- [ ] FamilyHub
- [ ] RentMate
- [ ] CommuteBD
- [ ] Wellness
- [ ] universal search
- [ ] export my data
- [ ] permanent account deletion

## Security
- [ ] Firestore rules deployed
- [ ] Firestore rules tested with two Student accounts
- [ ] rules tested with one General account
- [ ] Supabase bucket is private
- [ ] service-role key only on backend
- [ ] Firebase Admin key only on backend
- [ ] Gemini key only on backend
- [ ] no secrets committed
- [ ] email verification enforced
- [ ] file-size limit tested
- [ ] signed URLs expire
- [ ] role cannot be changed by profile update
- [ ] AI daily quota tested

## Release
- [ ] HTTPS Render URL configured
- [ ] cold start tested
- [ ] app icon and launch branding replaced
- [ ] privacy policy published
- [ ] AI processing disclosed
- [ ] Android signing key created and backed up securely
- [ ] release App Bundle built
- [ ] Play Console internal test completed
- [ ] test on at least 3 Android versions/devices
