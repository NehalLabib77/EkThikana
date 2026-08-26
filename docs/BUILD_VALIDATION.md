# Gochano build validation — handoff

Checks performed in this packaging environment:

- Python backend syntax parse: **PASS (0 errors)**
- Dart relative-import existence check: **PASS (0 missing imports)**
- Dart delimiter/structure check: **PASS (0 mismatches)**
- Firebase JSON files parse: **PASS**
- Firestore rules brace balance: **PASS**
- Active Savings CRUD / net-difference references: **removed**
- Active LifeHub UI: **Medicine, BazarBuddy, Daily Expenses, CommuteBD**
- User-facing app name checked as **Gochano**; remaining `ekthikana` identifiers are compatibility-sensitive technical IDs/bucket/channel names.

Backend pytest could not be executed in this container because the environment does not have `firebase_admin` installed. This is an environment limitation, not a passing test result.

Flutter/Android SDK is also unavailable here, so these are mandatory on your PC before release:

```powershell
cd flutter_app
flutter clean
flutter pub get
flutter analyze
flutter test
```

Backend:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pytest -q
```

Then deploy Firestore/Render and build the signed AAB. See `PRODUCTION_CHECKLIST.md`.
