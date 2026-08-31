# Phase 3-8 — Theme polish / dark-mode parity / system theme

**Status: ✅ shipped. Full Flutter suite 106/106, full backend 101/101, analyzer clean.**

P3-8 is the "polish pass" before P3-9..16. The audit found that
`core/theme.dart` already provides structurally symmetric light/dark
themes and `ThemeMode.system` was already wired in `app.dart`. The
remaining work was housekeeping: removing one dead file, completing one
missing parity item on the dark theme, and migrating four hardcoded
shadow / banner literals to design-system tokens.

## 1. Changes

### 1.1 Dead orphan removed
- `flutter_app/lib/screens/home/widgets/brutalist.dart` deleted.
  Confirmed via repo-wide grep that no production code imports or
  references it after the P3-2 bento migration.

### 1.2 `core/theme.dart` additions
- **New `EkShadows` token class** with two static lists:
  - `EkShadows.elevated` — blur 12, y-offset 4 (splash logo)
  - `EkShadows.hero` — blur 18, y-offset 6 (login/register logo plate)
- **Dark theme parity fix**: added `pageTransitionsTheme:
  PredictiveBackPageTransitionsBuilder` to `EkTheme.dark()`, mirroring
  the light theme. Previously the dark branch silently fell back to
  the platform default, so animations differed between modes.

### 1.3 Hardcoded literals tokenized
- `lib/main.dart` — splash logo shadow → `EkShadows.elevated`
- `lib/screens/auth/login_screen.dart` — logo plate shadow → `EkShadows.hero`
- `lib/screens/auth/register_screen.dart` — logo plate shadow → `EkShadows.elevated`
- `lib/widgets/offline_banner.dart` — orange surface + text now routed
  through a private `_OfflineBannerPalette.of(context)` that picks the
  light pair (`#FFE7CC` / `#6B3D00`) or dark pair (`#3A2510` /
  `#F1C26B`) using `Theme.of(context).brightness`. This is the same
  tonal pair the `GochanoChipTone.warning` entry already exposes in
  `widgets/gochano_primitives.dart`, so the banner reads as part of
  the same visual family whether the device is in light or dark mode.

### 1.4 Stale comment cleanup
- `lib/screens/system/gochano_splash_screen.dart` — removed the
  "brutalist palette" reference (orphan after P3-2 migration).

## 2. New test

- `flutter_app/test/theme_parity_test.dart` — 11 tests:
  - `EkTheme.light()` — Material3, brand seed, pageTransitionsTheme
  - `EkTheme.dark()` — Material3 dark, same pageTransitionsTheme
    builder as light, `EkColors.bgDark` scaffold
  - `EkShadows` — elevated (blur 12 / y 4), hero (blur 18 / y 6)
  - Static guards — `brutalist.dart` deleted, `ThemeMode.system` wired
    in `app.dart`, no screen hardcodes the `0x14000000` shadow literal
    (allowlist = `lib/core/theme.dart`).

## 3. Validation results

### 3.1 Flutter analyzer
```
$ flutter analyze lib test
Analyzing 2 items...
No issues found! (ran in 2.6s)
```

### 3.2 Flutter test suite
```
00:07 +106: All tests passed!
```

| Suite                       | Count | New |
|-----------------------------|------:|-----:|
| `theme_parity_test.dart`    |    11 |  +11 |
| **Full Flutter**            |   **106** | **+11** (was 95 after P3-7) |

### 3.3 Backend pytest
```
101 passed, 1 warning in 5.58s
```

## 4. Files touched

### Added
- `flutter_app/test/theme_parity_test.dart` (11 tests)

### Modified
- `flutter_app/lib/core/theme.dart` — added `EkShadows`, added
  `pageTransitionsTheme` to `dark()`
- `flutter_app/lib/main.dart` — splash logo uses `EkShadows.elevated`,
  added `core/theme.dart` import
- `flutter_app/lib/screens/auth/login_screen.dart` — logo plate uses
  `EkShadows.hero`
- `flutter_app/lib/screens/auth/register_screen.dart` — added
  `core/theme.dart` import, logo plate uses `EkShadows.elevated`
- `flutter_app/lib/widgets/offline_banner.dart` — light/dark palette
  via private `_OfflineBannerPalette.of(context)`
- `flutter_app/lib/screens/system/gochano_splash_screen.dart` —
  removed "brutalist palette" doc reference

### Deleted
- `flutter_app/lib/screens/home/widgets/brutalist.dart`

## 5. Out of scope (deferred)

- The per-screen `Color(0xFFF0F1F7)` chip / surface literals scattered
  across `tasks_screen.dart`, `profile_screen.dart`, `medicine_screen.dart`,
  `location_picker.dart` are *intentional one-off accents*, not theme
  tokens — they are not part of the parity contract and would
  unnecessarily inflate the token surface. They are excluded from the
  parity test allowlist intentionally.
- The `_accentFor` switch in `widgets/gochano_primitives.dart` still
  returns raw module accent colors; a future pass can lift them to
  `EkColors.*` once the bento module accent system is formalized.
- Snackbar `Color(0xFF2A2D33)` dark overlay in `core/ui.dart` is
  intentional (always-dark toast); left untouched.
