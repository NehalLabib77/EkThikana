# Changelog

All notable changes to **Gochano** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are date-stamped per audit pass, not released as `1.0.0/1.1.0/…`.

---

## [Audit Pass] — 2025

### Summary

A safe, surgical pass grounded in the real codebase (not the prior 14-phase wishlist, most of which was already implemented). 6 Flutter files modified, 3 docs added. **No backend changes. No destructive edits.** See `FINAL_AUDIT_REPORT.md` for full evidence.

### Added
- `FINAL_AUDIT_REPORT.md` — full audit covering what was already correct, what was actually broken, and the P2 backlog.
- `CHANGELOG.md` — this file.
- `lib/core/theme.dart` — `EkTheme.dark()` factory + dark palette tokens (`bgDark`, `cardDark`, `lineDark`, `textDark`, `mutedDark`). Scaffolding only; full per-screen dark migration is P2.

### Changed
- `lib/app.dart` — wired `darkTheme: EkTheme.dark()` and `themeMode: ThemeMode.system`. AppBar/Scaffold will now flip with the device theme on screens that read from `Theme.of(context).colorScheme`.
- `lib/screens/study/study_screen.dart` — removed the redundant **Subjects** tile from the quick-action row (it routed to the same `AcademicStructureScreen` as the **Semesters** tile). Row is now 3 tiles (Semesters / Groups / Focus) instead of 4 duplicates.
- `lib/screens/life/bazar_buddy_screen.dart` —
  - Save validation now blocks `quantity <= 0`, `price < 0`, and titles longer than 60 characters (previously only empty title was rejected, allowing zero-qty / zero-price items).
  - Save uses the trimmed title consistently.
  - Bare `CircularProgressIndicator()` replaced with `GochanoLoading` so loading has a branded identity and a future retry hook.
- `lib/screens/life/daily_expenses_screen.dart` —
  - Removed the **Today's Categories** strip (it duplicated data already shown in the Entries list and routed into the same Add-Expense sheet the FAB already opens).
  - Removed the now-dead `_categoryRow` helper.
  - Save validation now blocks `amount <= 0` and titles longer than 80 characters.
  - Save uses the trimmed title consistently.
  - Bare `CircularProgressIndicator()` replaced with `GochanoLoading`.

### Confirmed already correct (not regressed)
- Medicine flow: OCR → explicit **Review** → manual form → explicit **Save**. No auto-save.
- Notifications: Asia/Dhaka TZ; body format `medicineName • instruction`; **Taken** / **Skip** actions; `confirmedByUser: true` flag on every saved medicine.
- Splash: 8s hard timeout + retry button + error display; precache deferred past `initState`.
- `GochanoLoading` widget already exists with `compact / loading / error / empty` variants and `onRetry`.
- API service already handles nginx 502 plain-text responses and adds a "check Render logs" hint on 5xx.
- No client-side secrets (Gemini / Supabase / Firebase admin) — verified via grep.
- `AppConfig.validateRelease()` blocks release builds with empty / loopback `API_BASE_URL`.

### Deferred to P2 backlog (out of scope for a safe pass)
- AI Assistant chat-style rewrite (needs streaming endpoint decision).
- Subject-level resource upload UI (current Materials flow already covers backend need).
- Money + Statistics tiles moved out of Study Hub into a Profile Insights section.
- CommuteBD trip history (new Firestore collection, new screen).
- Full per-screen dark color migration (depends on a design tokens audit).
- iOS / Web parity.

---

## Earlier Passes

### Branding rename (pre-audit)
- Renamed app launcher label, MaterialApp title, login/setup/error user-facing strings to **Gochano**.
- `docs/GOCHANO_BRANDING.md` records what was and wasn't renamed (Android package ID, Supabase bucket, Render service, notification channel IDs all preserved by design).

### PART 3 — Community Library / Groups
- Removed `community_screen.dart` and its tiles (no public runtime; correction #4 from the project spec). Groups tile retained.
- See `PART4_REMOVAL_MANIFEST.json` for removal evidence.