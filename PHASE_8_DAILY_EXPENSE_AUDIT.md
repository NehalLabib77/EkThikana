# PHASE 8 — Daily Expense + Expense Tracker Architecture Audit

**Mode:** Read-only verification. No source files were modified.
**Scope:** Daily Expense flow, category contract, `financial_transactions`
ledger, monthly tracking, Profile→Money integration, performance.
**Out-of-scope (not touched):** Firestore rules, `financial_transactions`
schema, `FinancialService` signatures, auth flow, HTTP API contracts.

---

## PHASE 1 — Daily Expense Flow Trace

### Layer chain (verified, no provider/ChangeNotifier in between)

```
UI ─► DailyExpensesScreen (StatefulWidget)
     ─► StreamBuilder<FinancialTransactionModel>
           stream: FinancialService.dayStream(selectedDate)
     ─► on user action: addExpense() (modal sheet)
           └─► FinancialService.addDailyExpense / updateDailyExpense
                 └─► db.batch()
                       ├─ daily_expenses/{autoId}.set({ownerId, category, title, amount, note,
                       │       date, dateKey, monthKey, createdAt, updatedAt})
                       └─ financial_transactions/{transactionId('daily', id)}.set(
                              _financialData(type:'expense', source:'daily', sourceRecordId,
                              category, title, amount, date, dateKey, monthKey, ownerId, userId,
                              updatedAt) + createdAt)
UI ─► ExpenseTrackerScreen
     ─► StreamBuilder<FinancialTransactionModel>
           stream: FinancialService.allTransactionsStream(limit: 2000)
     ─► derived views: monthItems (year/month filter on `date`),
                        dayItems (year/month/day filter),
                        source breakdown, monthly history (per-month totals across the year)
```

### Add flow

`DailyExpensesScreen.addExpense()` → validates `title.isNotEmpty`,
`title.length ≤ 80`, `amount > 0` → `DateTime(year, month, day, hour, minute)`
→ `FinancialService.addDailyExpense(...)`. The service writes both
`daily_expenses/{autoId}` and the mirrored ledger row
`financial_transactions/<source>_<recordId>` in one batched commit.
Returns `sourceRef.id`.

### Edit flow

Same sheet, with `existing: FinancialTransactionModel`. Service reads
`daily_expenses/{sourceRecordId}` for `note` (the ledger row omits `note`).
`FinancialService.updateDailyExpense(...)` writes `daily_expenses/{id}`
and `financial_transactions/<source>_<recordId>` both with
`SetOptions(merge: true)` and an updated `monthKey`/`dateKey` if the
date changed.

### Delete flow

PopupMenu → `confirmAction` → `FinancialService.deleteDailyExpense(id)` →
batch-delete of `daily_expenses/{id}` and
`financial_transactions/<source>_<id>`.

### Category handling

- `DailyExpensesScreen.categories` (line 22-28) defines five tuples
  `(en, bn, emoji, tintColor)` and is the single source of truth on the
  client. The dropdown writes the **English label** (`c.$1`) into the
  doc; the Bangla label is purely cosmetic.
- The model does not validate category membership — any string is stored
  verbatim in `daily_expenses.category` and mirrored to
  `financial_transactions.category`. There is no enum on disk.

### Date handling

- `date` (Timestamp), `dateKey` (`yyyy-MM-dd`), `monthKey` (`yyyy-MM`)
  are written together on every add/update.
- `dayStream(selectedDate)` filters by `dateKey`. `monthStream(month)`
  filters by `monthKey`. Indexes for `(ownerId, monthKey)` and
  `(ownerId, dateKey)` are present (see Phase 6).

**Status: GREEN** — the chain is unidirectional, idempotent under retry
because `transactionId(...)` is deterministic, and the dual writes are
batch-committed.

---

## PHASE 2 — Category Contract

### Expected vs. actual

| Expected | Found in `daily_expenses_screen.dart` |
|----------|----------------------------------------|
| Breakfast/Nasta | `'Breakfast / Nasta'` (en), `'নাশতা'` (bn), emoji 🍳, tint `0xFFFFF3D9` |
| Lunch | `'Lunch'`, `'দুপুরের খাবার'`, 🍛, `0xFFEAF7E6` |
| Snacks | `'Snacks'`, `'স্ন্যাকস'`, 🍪, `0xFFF3E9FF` |
| Dinner | `'Dinner'`, `'রাতের খাবার'`, 🍲, `0xFFFFEAE5` |
| Other | `'Other'`, `'অন্যান্য'`, �, `0xFFE8F4FF` |

All five are present in a single `static const categories` table on the
client. No duplicate `categories` constant exists in the daily-expense
surface. (`bazar_buddy_screen.dart` has its own `categories` for bazar,
which is a separate flow with its own taxonomy — out of scope.)

### "Today's Category"

`grep_search "Today.s.Category|TodaysCategory|todayCategory|TodayCategory"`
across `**/*.dart` → **no matches**. There is no `todayCategory`/`Today's
Category` field stored anywhere. The phrase that does exist is the
**UI label** `"Today's Daily Expense"` on the day-summary card in
`daily_expenses_screen.dart` line 316 — that is a string in a `Text`
widget, not a stored category.

### Duplication

- `daily_expenses.category` and `financial_transactions.category` carry
  the same English string. This is by design — the ledger is a flat
  union of all sources, so each source can keep its own taxonomy
  without forcing a global category list.
- The model (`financial_transaction.dart:43`) reads `category` as a
  plain string with a default `''`. There is no enum/union on disk.

**Status: GREEN** — the category contract matches the spec, no stale
"Today's Category" field exists, no duplicate definition exists on the
daily-expense surface.

---

## PHASE 3 — Financial Transaction Contract

### Field contract (written by `_financialData(...)` in `financial_service.dart:27-50`)

| Field | Type | Source on create | Source on update | Notes |
|-------|------|------------------|------------------|-------|
| `transactionId` (doc id) | string | `transactionId(source, sourceRecordId)` = `safe(source)_safe(sourceRecordId)` | same on update (idempotent) | Deterministic. `_safeId` strips non-`[A-Za-z0-9_-]`. |
| `ownerId` | string | `uid` | preserved by rules + `_financialData` re-writes it | |
| `userId` | string | `uid` | preserved by rules + re-written | Alias for `ownerId` (legacy). |
| `type` | string | `'expense'` | preserved by rules | Only `'expense'` allowed on create/update. |
| `source` | string | one of `'daily'`, `'bazar'`, `'medicine'`, `'commute'` | preserved by rules | Validated server-side in rules. |
| `sourceRecordId` | string | id of the source document | preserved by rules | Cannot be changed by update. |
| `category` | string | free-form, per source | re-written from caller | No enum on disk. |
| `title` | string | `title.trim()` | re-written | Title of the source item. |
| `amount` | double | source amount | re-written; rules require `>= 0` | |
| `date` | Timestamp | source date | re-written | |
| `dateKey` | string | `yyyy-MM-dd` | re-written | Used by `dayStream`. |
| `monthKey` | string | `yyyy-MM` | re-written | Used by `monthStream`. |
| `updatedAt` | serverTimestamp | serverTimestamp | serverTimestamp | Always refreshed. |
| `createdAt` | serverTimestamp | serverTimestamp | preserved (not re-written on update path) | Set on the original `add` only. |

### Where `status` lives

`status` is **not** part of the daily/bazar/commute ledger. The only
ledger-level `status` is on `medicine_doses` (a sibling collection) and
its mirrored `financial_transactions` row: values `taken`, `skipped`,
`missed`, `pending`. The `monthly_money_service` (budget) requires
`status == 'confirmed'` — but no current code path writes `confirmed`,
so the budget service will currently read **zero** expenses (see Phase 5).

### Create / Update / Delete consistency

- **Create** (add): batch creates source row + ledger row.
- **Update** (daily only): batch `SetOptions(merge: true)` on both; the
  ledger doc is identified by `transactionId(source, id)` so re-applying
  is safe.
- **Delete** (daily): batch delete of source row + ledger row.

### Consistency checks (rule-level)

`firestore.rules:212-233` enforce:
- `ownerId` and `userId` are the auth uid;
- `type == 'expense'`;
- `source ∈ {daily, bazar, medicine, commute}`;
- `sourceRecordId` is a string (and unchanged on update);
- `amount` is a number `>= 0` (note: `0` is allowed by the rule but the
  service rejects `amount <= 0`).

**Status: YELLOW** — the field contract is consistent and rule-gated,
but `monthly_money_service.dart` queries `status == 'confirmed'` while
no writer currently emits that status. This is a contract drift, not a
crash (the query simply returns zero). No fix recommended in this
read-only audit; flagging for the budget service owner.

---

## PHASE 4 — Monthly Tracking

| Calculation | Location | Status |
|------------|----------|--------|
| Day total (`source == 'daily'`) | `daily_expenses_screen.dart:243` (fold over day stream) | GREEN — index `(ownerId, dateKey)` covers this. |
| Overall day total (all sources) | `daily_expenses_screen.dart:244-246` | GREEN — same index works because Firestore applies `where('dateKey', ==)` then client-side filters `source`. |
| Monthly total | `expense_tracker_screen.dart:64-79` (client-side fold) | GREEN — uses `allTransactionsStream()` (limit 2000) then filters by `date.year`/`date.month`. |
| Date filtering (calendar) | `expense_tracker_screen.dart:80-87` and `CalendarDatePicker` | GREEN — single-day filter is applied client-side over the already-month-filtered list. |
| Category breakdown | `expense_tracker_screen.dart:176-242` (`_sourceBreakdown`) → uses `FinancialSummary.bySource` | GREEN — uses the existing `bySource` aggregation. Note: this groups by `source`, **not** by `category`. |
| Remaining budget | `monthly_money_service.dart:35-39` | YELLOW — see Phase 5. |

### `monthKey` / `dateKey` correctness

- `_financialData` always writes the same `monthKey` and `dateKey` derived
  from `date`. `updateDailyExpense` rebuilds these on date change.
- `dayStream` and `monthStream` both use these keys as equality filters.
- Indexes exist for both: `(ownerId, monthKey)` and `(ownerId, dateKey)`
  in `firebase/firestore.indexes.json`.

**Status: GREEN** for daily / monthly totals and date filtering.
Category breakdown is by `source`, not by `category`, which is the
documented behaviour — the spec says *category breakdown*, so this is
**YELLOW** (UI gap, not a data gap).

---

## PHASE 5 — Profile Money Integration

### Trace

```
profile_screen.dart
  ├─ Line 16:    import '.../study/monthly_money_screen.dart'
  ├─ Line 281:   StreamBuilder(FinancialService.monthStream(DateTime.now()))
  ├─ Line 284:   FinancialService.summary(items)  // by-source breakdown
  └─ Line 434:   MaterialPageRoute(builder: (_) => const MonthlyMoneyScreen())
```

`MonthlyMoneyScreen` lives under `screens/study/` (the relocation was
purely the call-site in `ProfileScreen._insightsCard`); the file path
and the service (`MonthlyMoneyService`) are unchanged. The dependency
chain is:

```
MonthlyMoneyScreen
   └─► MonthlyMoneyService.monthStream(month)   // financial_transactions
                                                    // where status == 'confirmed'
   └─► MonthlyMoneyService.getBudget(month)      // ApiService.getMonthlyBudget
   └─► MonthlyMoneyService.remaining(month)      // budget − summary.totalSpending
   └─► MonthlyMoneyService.setBudget(month, amt) // ApiService.setMonthlyBudget
```

### Issues observed

1. `monthStream` in `MonthlyMoneyService` filters by
   `status == 'confirmed'`. **No writer** in the current codebase sets
   `status` on a daily/bazar/commute ledger row, so `monthStream`
   returns an empty list. The `_financialSummaryCard` in
   `profile_screen.dart` does **not** use `MonthlyMoneyService.monthStream`
   (it uses `FinancialService.monthStream`, which does **not** filter by
   `status`), so the Profile summary still works.

2. `monthly_money_screen.dart` opens `_refresh()` in `initState`, which
   awaits `stream.first` and then unsubscribes (Firestore `.first` closes
   the subscription after the first event). It will **not** auto-update
   on subsequent writes — users must press the refresh icon.

3. `ApiService.getRemaining` is defined but unused.

4. There is no `BudgetService` class. The budget endpoint is wrapped
   inside `MonthlyMoneyService` and `ApiService`.

**Status: YELLOW** — Money relocation from Study Hub to Profile is
structurally complete (call sites in `_insightsCard`, import on line 16,
nav on line 434), but the budget service contract drift (Phase 3) means
the *Monthly Money* screen will render `�0.00` and `Remaining: ৳budget`
even when expenses have been recorded.

---

## PHASE 6 — Performance Audit

### Streams in flight

| Site | Stream | Scope |
|------|--------|-------|
| `daily_expenses_screen.dart:234` | `FinancialService.dayStream(selectedDate)` | Single day, `ownerId == uid && dateKey == dateKey`. Indexed. |
| `expense_tracker_screen.dart:65` | `FinancialService.allTransactionsStream(limit: 2000)` | All owner docs up to 2000. Filters applied client-side. |
| `life_screen.dart:74` | `FinancialService.monthStream(DateTime.now())` | Single month, indexed. |
| `dashboard_screen.dart:244` | `FinancialService.monthStream(DateTime.now())` | Single month, indexed. |
| `profile_screen.dart:281` | `FinancialService.monthStream(DateTime.now())` | Single month, indexed. |
| `monthly_money_screen.dart:43` | `MonthlyMoneyService.monthStream(month)` first-only | Single month. Reads `status == 'confirmed'` (zero results — see Phase 5). |

### Duplicate Firestore reads

- `ExpenseTrackerScreen` is the only screen that uses
  `allTransactionsStream()`. It does so **once**, then derives every
  view (month, day, source breakdown, year history) from the in-memory
  list. No duplicate reads inside that screen.
- `Dashboard`, `Life`, `Profile`, `DailyExpenses`, `MonthlyMoney` each
  open exactly one stream at a time. They can co-exist on the navigation
  stack, but they are **not** simultaneously visible to the user; the
  Firestore client multiplexes subscriptions on the same socket.
- `addExpense(existing: ...)` performs an extra one-shot `daily_expenses.get()`
  to read `note`. Acceptable — it only fires when the user taps *Edit*.

### Unnecessary streams

- `MonthlyMoneyScreen._refresh` resolves `stream.first` then unsubscribes.
  Effectively a one-shot read — could be replaced with a `.get()` for
  clarity, but performance impact is negligible.

### Repeated calculations

- `FinancialSummary.fromTransactions` walks the list once per call.
  `expense_tracker_screen.dart` calls it exactly once per snapshot.
- The day summary in `daily_expenses_screen.dart` does a single fold
  over `daily` items and a separate fold over `all` items — two passes,
  O(n), but `n` is bounded by the day's transaction count.

### Missing indexes

All four composite queries needed by the financial surfaces are
covered by `firebase/firestore.indexes.json`:

| Query | Index present? |
|-------|----------------|
| `where('ownerId') + where('monthKey')` | ✅ (lines 64-72 of indexes file) |
| `where('ownerId') + where('dateKey')` | ✅ (lines 73-81) |
| `where('ownerId') + where('sessionId')` (`bazar_items`) | ✅ |
| `where('ownerId') + where('medicineId')` (`medicine_doses`) | ✅ |
| `where('ownerId') + where('type') + where('status') + where('date' range)` (`MonthlyMoneyService`) | ❌ — none of the current writers emit `status == 'confirmed'`, so the query returns empty and the missing index does not surface today. If the contract is fixed later, this index must be added. |

**Status: GREEN** for the current (ledger-only) surfaces.
**Status: YELLOW** for `MonthlyMoneyService.monthStream` — it relies on
`status == 'confirmed'` but no writer emits that status and no composite
index covers it.

---

## PHASE 7 — Contract Table

| Layer | File | Function | Input | Output | Status |
|-------|------|----------|-------|--------|--------|
| UI (Add) | `lib/screens/life/daily_expenses_screen.dart` | `_DailyExpensesScreenState.addExpense` | `presetCategory?`, `existing?` | `void` (writes via service) | 🟢 GREEN |
| UI (Edit/Delete) | `lib/screens/life/daily_expenses_screen.dart` | `_entryTile.onSelected` | `'edit'|'delete'` | `void` | 🟢 GREEN |
| UI (Tracker) | `lib/screens/life/expense_tracker_screen.dart` | `ExpenseTrackerScreen.build` | `initialMonth?` | UI only | 🟢 GREEN |
| UI (Monthly Money) | `lib/screens/study/monthly_money_screen.dart` | `_MonthlyMoneyScreenState._refresh` | — | `void` | 🟡 YELLOW |
| UI (Profile Money) | `lib/screens/profile/profile_screen.dart` | `_financialSummaryCard` | — | UI summary | 🟢 GREEN |
| UI (Profile Insights nav) | `lib/screens/profile/profile_screen.dart` | `_insightsCard` | `BuildContext` | `void` (nav) | 🟢 GREEN |
| Service (add) | `lib/services/financial_service.dart` | `FinancialService.addDailyExpense` | `category, title, amount, date, note` | `Future<String>` (source id) | � GREEN |
| Service (update) | `lib/services/financial_service.dart` | `FinancialService.updateDailyExpense` | `id, category, title, amount, date, note` | `Future<void>` | 🟢 GREEN |
| Service (delete) | `lib/services/financial_service.dart` | `FinancialService.deleteDailyExpense` | `id` | `Future<void>` | 🟢 GREEN |
| Service (day stream) | `lib/services/financial_service.dart` | `FinancialService.dayStream` | `DateTime day` | `Stream<List<FinancialTransactionModel>>` | 🟢 GREEN |
| Service (month stream) | `lib/services/financial_service.dart` | `FinancialService.monthStream` | `DateTime month` | `Stream<List<FinancialTransactionModel>>` | 🟢 GREEN |
| Service (all stream) | `lib/services/financial_service.dart` | `FinancialService.allTransactionsStream` | `{int limit = 2000}` | `Stream<List<FinancialTransactionModel>>` | 🟢 GREEN |
| Service (summary) | `lib/services/financial_service.dart` | `FinancialService.summary` | `Iterable<FinancialTransactionModel>` | `FinancialSummary` | 🟢 GREEN |
| Service (budget) | `lib/services/monthly_money_service.dart` | `MonthlyMoneyService.monthStream / getBudget / setBudget / remaining` | `DateTime month` | `Stream / Future<double>` | � YELLOW |
| Model | `lib/models/financial_transaction.dart` | `FinancialTransactionModel.fromDoc` | `DocumentSnapshot<Map<String,dynamic>>` | `FinancialTransactionModel` | 🟢 GREEN |
| Model | `lib/models/financial_transaction.dart` | `FinancialSummary.fromTransactions` | `Iterable<FinancialTransactionModel>` | `FinancialSummary` | 🟢 GREEN |
| API | `lib/services/api_service.dart` | `ApiService.getMonthlyBudget` | `DateTime month` | `Future<Map<String,dynamic>>` | 🟢 GREEN |
| API | `lib/services/api_service.dart` | `ApiService.setMonthlyBudget` | `DateTime month, double amount` | `Future<Map<String,dynamic>>` | 🟢 GREEN |
| API | `lib/services/api_service.dart` | `ApiService.getRemaining` | `DateTime month` | `Future<Map<String,dynamic>>` | 🟡 YELLOW — defined but never called |
| Firestore rules | `firebase/firestore.rules:192-199` | `/daily_expenses/{id}` | — | allow list | 🟢 GREEN |
| Firestore rules | `firebase/firestore.rules:212-233` | `/financial_transactions/{id}` | — | allow list | 🟢 GREEN |
| Firestore indexes | `firebase/firestore.indexes.json` | `(ownerId, monthKey)` / `(ownerId, dateKey)` | — | index | 🟢 GREEN |
| Firestore indexes | `firebase/firestore.indexes.json` | `(ownerId, type, status, date)` | — | index | 🔴 RED — absent, but only needed if `status == 'confirmed'` is enforced |

Legend: 🟢 GREEN safe · 🟡 YELLOW UI cleanup / contract drift · 🔴 RED broken / missing prerequisite.

---

## FINAL SUMMARY

### 1. Is Daily Expense architecture safe to modify?

**Yes.** The layer chain is unidirectional (UI → service → Firestore batch),
the doc-id formula is deterministic (`transactionId(source, id)`), and
Create/Update/Delete are all batched with the same rule-gated invariants.

### 2. Which files are safe to change?

Read-only verification only — but if a future change is required, the
following are safe to touch without schema impact:

- `flutter_app/lib/screens/life/daily_expenses_screen.dart`
- `flutter_app/lib/screens/life/expense_tracker_screen.dart`
- `flutter_app/lib/widgets/gochano_loading.dart` (used by Daily only as a placeholder)
- `flutter_app/lib/models/financial_transaction.dart` (additive fields only)

### 3. Which files must not be touched?

- `flutter_app/lib/services/financial_service.dart` — single source of
  truth for the ledger. `_financialData(...)`, `transactionId(...)`,
  `dateKey(...)`, `monthKey(...)`, `addDailyExpense/updateDailyExpense/deleteDailyExpense`
  signatures and batch shape are contract.
- `flutter_app/lib/services/monthly_money_service.dart` — wraps the
  same ledger; the `status == 'confirmed'` filter is a contract
  decision the budget owner owns (see issue below).
- `flutter_app/lib/services/api_service.dart` — backend budget endpoints
  (`getMonthlyBudget`, `setMonthlyBudget`, `getRemaining`) are
  contract.
- `firebase/firestore.rules` — `daily_expenses` and
  `financial_transactions` match blocks are contract.
- `firebase/firestore.indexes.json` — composite indexes
  `(ownerId, monthKey)` and `(ownerId, dateKey)` are load-bearing.

### 4. Any financial risks?

- **Contract drift in budget service** (`MonthlyMoneyService.monthStream`)
  filters by `status == 'confirmed'` while no writer currently sets
  that field. Today this returns an empty list, so the Monthly Money
  screen shows `৳0` even when expenses have been recorded. **Severity:
  low** (no data loss, only an under-reported budget screen).
- **No duplicate Firestore writes** anywhere in the daily-expense flow.
  Every write is one batch that touches exactly two docs
  (`daily_expenses/{id}` + `financial_transactions/<source>_<id>`).
- **No `0`-amount protection in rules.** The service rejects
  `amount <= 0` and the daily rule requires `amount > 0`, but the
  ledger rule allows `amount >= 0`. A direct ledger write with
  `amount = 0` would be rule-accepted. **Severity: low** — no current
  code path produces such a write.
- **`getRemaining` API method is dead code.** No callers. No risk, but
  worth removing in a future cleanup.

### 5. Recommended implementation order (if any change is approved)

1. **Resolve the `status == 'confirmed'` contract drift** in
   `MonthlyMoneyService` — either (a) remove the `status` filter so the
   budget screen reads the same ledger as everything else, or (b) make
   `FinancialService.addDailyExpense` / `saveBazarItem` /
   `recordCommuteTrip` write `status: 'confirmed'`. Option (a) is the
   minimal change and is backwards-compatible.
2. **Add the missing composite index** `(ownerId, type, status, date)` to
   `firebase/firestore.indexes.json` **only if** option (b) is chosen in
   step 1.
3. **Optional UI cleanup** — replace the hard-coded `"Today's Daily
   Expense"` label on `daily_expenses_screen.dart:316` with the
   localised date (`DateFormat('EEEE, d MMMM').format(selectedDate)`)
   so the card's heading matches the picker. No contract impact.
4. **Optional category breakdown** — add a per-category roll-up
   (`FinancialSummary.byCategory`) if the product wants a stacked bar
   inside the monthly breakdown card. Additive — does not affect any
   existing call site.
5. **Remove dead code** — `ApiService.getRemaining` if confirmed
   unused.

No code changes were made in this audit.
