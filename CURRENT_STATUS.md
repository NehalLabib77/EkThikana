# Gochano — Current Handoff Status

This copy includes the accumulated UI/OCR/API/Commute/financial updates from the prior handoff plus the latest scope corrections.

## Latest corrections included

- Brand is Gochano in user-facing Flutter/Android text.
- Final LifeHub: Medicine, BazarBuddy, Daily Expenses, CommuteBD.
- RentMate, FamilyHub and Wellness remain legacy-only/denied and are not active modules.
- Finance is now **expense tracking only**. Savings/cash-flow/net-difference UI and active write rules were removed.
- Central expense sources are only `daily`, `bazar`, `medicine`, `commute`.
- Study dashboard must not add a separate `Community Library / Browse Resources` promotional block.
- Existing Community Library feature remains Student-only and reachable through the compact Library entry.
- `.firebaserc` default project is aligned with the checked-in FlutterFire project id `gochano-a30c8`.

## Still operator-dependent

- Firebase `(default)` Firestore database must exist in the selected project.
- Existing Render/Supabase/Gemini secrets must be present in Render.
- Firestore rules/indexes and any Supabase migrations must be deployed after pulling this code.
- Run Flutter analyze/tests and build on a machine with Flutter/Android SDK.
- Configure Android release keystore before `flutter build appbundle --release`.
- Replace the generic Flutter launcher icon with a final Gochano icon if desired.
