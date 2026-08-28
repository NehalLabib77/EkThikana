# PHASE 9 — Daily Expense + Expense Tracker Improvements

**Status:** ✅ GREEN
**Scope:** `flutter_app/lib/services/monthly_money_service.dart`,
`flutter_app/lib/screens/life/daily_expenses_screen.dart`,
`flutter_app/lib/screens/life/expense_tracker_screen.dart`
**Out of scope (per user constraint):** `FinancialService`,
`financial_transactions` schema, `firestore.rules`,
Add/Edit/Delete flow logic.

This phase is the implementation follow-up to **PHASE 8 — Daily Expense
Audit**. The audit identified one YELLOW contract drift and a handful
of UI papercuts; the user asked for six concrete improvements,
executed below.

---

## Files changed

| File | Steps |
|---|---|
| `flutter_app/lib/services/monthly_money_service.dart` | 1 |
| `flutter_app/lib/screens/life/daily_expenses_screen.dart` | 2, 5, 6 |
| `flutter_app/lib/screens/life/expense_tracker_screen.dart` | 4, 5, 6 |

No other files touched.

---

## Step 1 — Monthly Money contract drift (FIXED)

**File:** `monthly_money_service.dart`

`monthStream` previously filtered by `status == 'confirmed'`, but
**no writer in `FinancialService` emits a `status` field** — so the
query returned an empty list every time, leaving `MonthlyMoneyScreen`
showing zero spending.

**Fix:** dropped the `.where('status', isEqualTo: 'confirmed')` line.
`monthStream` now reads the same set of rows as
`FinancialService.monthStream`. Updated the header comment to record
the drift and the rationale.

**Backwards-compatible:** yes — the old query returned empty, so
restoring parity with `FinancialService` only adds rows, never removes
them.

---

## Step 2 — Daily Expense UI cleanup (DONE)

**File:** `daily_expenses_screen.dart`

- Headline text on the day summary card was the literal string
  `"Today's Daily Expense"` / `'আজকের দৈনিক খরচ'`, even when the user
  had navigated to a different date. Replaced with
  `DateFormat('d MMMM yyyy').format(selectedDate)` so the heading now
  reflects whatever day is selected.
- Secondary text changed from `'All Gochano spending today'` →
  `'All Gochano spending'` (the suffix was redundant once the headline
  shows the date).

---

## Step 3 — Expense categories: Add-only (VERIFIED, no code change)

**File:** `daily_expenses_screen.dart`

Confirmed that `DailyExpensesScreen.categories` (line 22-28) is the
**single source of truth** for category tuples used by both the Add
sheet and the Edit sheet. The edit modal sheet does not maintain a
parallel category list — `existing.category` is fed back into the
same `DropdownButtonFormField` populated from `categories`. No change
needed.

---

## Step 4 — Expense Tracker category breakdown (ADDED)

**File:** `expense_tracker_screen.dart`

Added a new card between `_sourceBreakdown` and `_calendar` that
breaks the **current month's daily-expense rows** down by category.

- New `const List<(String en, String bn, String emoji, Color tint)>
  _kDailyCategories` (file-level constant, 5 entries — must match
  `DailyExpensesScreen.categories`).
- New `_categoryBreakdown(List<FinancialTransactionModel> monthItems)`
  widget:
  - Filters `source == 'daily'` only (other sources already grouped
    by `_sourceBreakdown`).
  - Aggregates per-category totals with an `'Other'` fallback for
    legacy/unknown values.
  - Renders one row per category: emoji tile + bilingual label +
    `LinearProgressIndicator` (relative to max, so the leading
    category always reads at 100 %) + `৳amount`.

The existing `_sourceBreakdown` is untouched — categories are layered
*underneath* sources, not replacing them.

---

## Step 5 — Dark-mode compatibility (DONE)

**Files:** `daily_expenses_screen.dart`, `expense_tracker_screen.dart`

Both screens previously hardcoded a light palette on three surfaces
that are the visual focal point of the screens:

| Surface | File | Before | After |
|---|---|---|---|
| Date-picker card | `daily_expenses_screen.dart` | `Color(0xFFFFF9E9)` bg, `Color(0xFF187E2D)` icon | Dark: `0xFF1E293B` bg + `0xFF334155` border + `0xFF7CD992` icon; Light: original |
| Day summary card | `daily_expenses_screen.dart` | Gradient `0xFFF3FCEB → 0xFFFFF9E6`, border `0xFFDCECCB`, headline `0xFF126C25` | Dark: flat `0xFF1E293B` card + `0xFF334155` border + `0xFF7CD992` headline; Light: original |
| Month summary card | `expense_tracker_screen.dart` | Same gradient + `0xFFD85A3A` total | Dark: flat `0xFF1E293B` card + `0xFF334155` border + `0xFFFF8A6E` total; Light: original |
| Category progress bars | `expense_tracker_screen.dart` | `c.$4.withOpacity(0.45)` track + `c.$4` fill | Dark: `c.$4.withValues(alpha:0.22)` track + `c.$4.withValues(alpha:0.85)` fill (lower saturation so the bar is visible against the dark card); Light: original `withValues(alpha:0.45)` track + `c.$4` fill |

Each surface that branches on theme now reads brightness from a local
`Builder(builder: (context) { final dark = Theme.of(context).brightness
== Brightness.dark; ... })`. `Theme.of(context)` registers the
`Builder` as a dependent of the `Theme` `InheritedWidget`, so the
swaps recompute only on theme/locale changes — not on every snapshot.

Palette tokens picked for dark:
- Surface: `0xFF1E293B` (slate-800, matches `EkColors.cardDark`).
- Border: `0xFF334155` (slate-700, matches `EkColors.lineDark`).
- Headline green: `0xFF7CD992` (a brighter green that's still warm) —
  readable on slate-800.
- Total coral: `0xFFFF8A6E` (a desaturated coral) — keeps the
  "expense = warm" semantic without screaming red on dark.

No token collisions with `EkColors.*` so the rest of the app's dark
mode scaffolding continues to work.

---

## Step 6 — Optimization (DONE)

The audit surfaced two avoidable per-rebuild costs. Both addressed.

### 6.1 `daily_expenses_screen.dart` — single-pass split

**Before:**
```dart
final daily = all.where((e) => e.type == 'expense' && e.source == 'daily').toList();
final dailyTotal = daily.fold<double>(0, (s, e) => s + e.amount);
final overallDayTotal = all
    .where((e) => e.type == 'expense')
    .fold<double>(0, (s, e) => s + e.amount);
```
Three walks over `all` (the `where`, the `fold` on `daily`, and the
`where+fold` for the overall).

**After:** one `for` loop that simultaneously partitions into `daily`
and accumulates both `dailyTotal` and `overallDayTotal`.

### 6.2 `expense_tracker_screen.dart` — single-pass partition

**Before:**
```dart
final all = snap.data!.where((e) => e.type == 'expense').toList();
final monthItems = all.where(year/month).toList();
final summary = FinancialService.summary(monthItems);
final dayItems = monthItems.where(year/month/day).toList();
```
Three separate `.where().toList()` walks + one extra `summary()`
traversal. With `allTransactionsStream` capped at 2000 docs, each
rebuild walked the list four times.

**After:** one `for` loop that partitions into `all`, `monthItems`,
`dayItems` simultaneously, then calls `summary(monthItems)` once.
Downstream widgets (`_sourceBreakdown`, `_categoryBreakdown`,
`_calendar`, `_dayTransactions`, `_yearHistory`) continue to receive
the same lists they always did — only the partition logic changed.

### 6.3 Considered but not done

- **Re-running `get_runtime_errors` to fetch `note` in `addExpense`**
  is a single one-shot read on edit, not per-render. Not a
  performance concern.
- **Const-folding the dark-mode `Color`/`LinearGradient` allocations**
  can't be done — they're computed per build against
  `Theme.of(context).brightness`, so they have to be live.
- **Memoizing `_categoryBreakdown` totals across rebuilds** is not
  worth it: the input `monthItems` is a fresh list every snapshot, so
  the totals change anyway.
- **Sub-scoping `_categoryBreakdown`'s per-row `Builder`** would save
  one `Theme.of(context)` call per row, but the underlying cost is
  negligible (theme lookups are O(1) on the inherited tree).

---

## Step 7 — Verification

### `flutter analyze` on changed files

```
$ flutter analyze lib/services/monthly_money_service.dart \
                  lib/screens/life/daily_expenses_screen.dart \
                  lib/screens/life/expense_tracker_screen.dart
Analyzing 3 items...
No issues found! (ran in 1.2s)
```

### Workspace-wide `flutter analyze` (full repo)

The workspace has **pre-existing** errors and infos in files this
phase did not touch. Confirmed by checking `git log` on those files:

| File | Issue | Touched by PHASE 9? |
|---|---|---|
| `lib/screens/profile/profile_screen.dart:368` | `Expected to find ';'` (orphan code) | ❌ no |
| `lib/screens/study/materials_screen.dart:340` | `FilePicker.platform` undefined | ❌ no |
| `lib/screens/study/materials_screen.dart:348` | `BuildContext` across async gap | ❌ no |
| `lib/screens/life/medicine_screen.dart:320,322` | `Radio.groupValue` / `onChanged` deprecation | ❌ no |
| `lib/screens/life/medicine_screen.dart:410,415` | `sum` parameter shadows `Sum` type | ❌ no |
| `lib/screens/life/medicine_history_screen.dart:54` | `sum` parameter shadows `Sum` type | ❌ no |

These were on disk at the `pre-audit-snapshot` tag and are out of
scope for PHASE 9 (the user asked only for the daily-expense /
expense-tracker surfaces). No new analyzer warnings were introduced.

### Manual trace

Walked through the flow end-to-end against the live Firestore rules
mental model — no `status` field exists in `daily_expenses` or
`financial_transactions`, so removing the `where('status', ...)`
filter does not weaken any rule. The category breakdown widget only
**reads** `category` strings the user already wrote; it doesn't
constrain what categories can be written.

---

## Constraints respected

| Constraint | Result |
|---|---|
| Do not add new fields to `FinancialService` | ✅ |
| Do not change `financial_transactions` schema | ✅ |
| Do not edit `firestore.rules` | ✅ |
| Do not rewrite Add/Edit/Delete flow logic | ✅ |
| Do not break the existing source breakdown | ✅ (categories layered underneath) |
| `FinancialService` untouched | ✅ (only `monthly_money_service.dart` and two screens) |

---

## Summary of net changes

- **1 contract bug fixed** (Monthly Money stream returned empty rows)
- **1 UI label fixed** (Daily summary card now reflects the selected
  date instead of always saying "Today")
- **1 new widget added** (`_categoryBreakdown` — per-category
  breakdown in the Expense Tracker)
- **3 surfaces converted to dark-mode-aware** (date picker, daily
  summary card, monthly summary card + category progress bars)
- **2 builds optimized** (single-pass partitioning replaces
  multi-walk `.where().toList()` chains)

No regressions detected. `flutter analyze` clean on the three touched
files. Ready for the live test pass against the emulator.