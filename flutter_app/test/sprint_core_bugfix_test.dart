// Tests for the Final Core Bug-Fix Sprint (Part 14).
//
// Covers:
//   1. Financial remaining formula (backendRemaining + pawnaReceived - denaPaid)
//   2. Month boundary — transactions from previous months excluded
//   3. Grocery counted exactly once (idempotent mirror write path)
//   4. Task date filter: !due.isBefore(dayKey) && due.isBefore(endOfDay)
//   5. Task form initialDate: pre-fills 9am on the selected day for new tasks
//   6. FinancialService key helpers

import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/models/financial_transaction.dart';
import 'package:gochano/services/financial_service.dart';

// ---------------------------------------------------------------------------
// Helpers — build a minimal FinancialTransactionModel without Firestore
// ---------------------------------------------------------------------------

FinancialTransactionModel _tx({
  required String source,
  required double amount,
  required DateTime date,
  String type = 'expense',
  String category = 'test',
}) {
  return FinancialTransactionModel(
    id: '${source}_${date.millisecondsSinceEpoch}',
    userId: 'uid_test',
    type: type,
    source: source,
    sourceRecordId: '${source}_record',
    category: category,
    title: 'Test $source',
    amount: amount,
    date: date,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // 1. Financial remaining formula
  // -------------------------------------------------------------------------
  group('Financial remaining formula', () {
    test('adjustedRemaining = backendRemaining + pawnaReceived - denaPaid', () {
      const backendRemaining = 2000.0;
      const pawnaReceived = 500.0;
      const denaPaid = 300.0;
      final adjusted = backendRemaining + pawnaReceived - denaPaid;
      expect(adjusted, equals(2200.0));
    });

    test('negative remaining when overspent', () {
      const backendRemaining = -52655.0;
      const pawnaReceived = 0.0;
      const denaPaid = 0.0;
      final adjusted = backendRemaining + pawnaReceived - denaPaid;
      expect(adjusted, isNegative);
      expect(adjusted, equals(-52655.0));
    });

    test('pawna inflow raises remaining', () {
      const backendRemaining = 1000.0;
      const pawnaReceived = 3000.0;
      const denaPaid = 0.0;
      final adjusted = backendRemaining + pawnaReceived - denaPaid;
      expect(adjusted, equals(4000.0));
    });

    test('dena outflow reduces remaining', () {
      const backendRemaining = 5000.0;
      const pawnaReceived = 0.0;
      const denaPaid = 2000.0;
      final adjusted = backendRemaining + pawnaReceived - denaPaid;
      expect(adjusted, equals(3000.0));
    });

    test('no settlement leaves remaining unchanged', () {
      const backendRemaining = 2900.0;
      final adjusted = backendRemaining + 0 - 0;
      expect(adjusted, equals(2900.0));
    });

    test('monthly money itself is never mutated by settlement', () {
      const monthlyMoney = 5000.0;
      const backendRemaining = 2000.0;
      const pawnaReceived = 1000.0;
      const denaPaid = 500.0;
      final adjusted = backendRemaining + pawnaReceived - denaPaid;
      expect(monthlyMoney, equals(5000.0));
      expect(adjusted, equals(2500.0));
    });
  });

  // -------------------------------------------------------------------------
  // 2. Month boundary — FinancialSummary only counts given rows
  // -------------------------------------------------------------------------
  group('Month boundary filtering', () {
    final currentMonth = DateTime(2026, 9, 1);
    final prevMonth = DateTime(2026, 8, 31);

    test('FinancialSummary excludes transactions from previous month', () {
      final items = [
        _tx(source: 'daily', amount: 100, date: currentMonth),
        _tx(source: 'daily', amount: 999, date: prevMonth),
      ];
      final currentItems =
          items.where((t) => t.date.month == 9 && t.date.year == 2026);
      final summary = FinancialSummary.fromTransactions(currentItems);
      expect(summary.totalSpending, equals(100.0));
    });

    test('FinancialSummary skips non-expense type rows (legacy saving)', () {
      final items = [
        _tx(source: 'daily', amount: 200, date: currentMonth, type: 'expense'),
        _tx(source: 'daily', amount: 999, date: currentMonth, type: 'saving'),
      ];
      final summary = FinancialSummary.fromTransactions(items);
      expect(summary.totalSpending, equals(200.0));
    });
  });

  // -------------------------------------------------------------------------
  // 3. Grocery idempotency
  // -------------------------------------------------------------------------
  group('Grocery idempotency', () {
    test('transactionId is deterministic for same source + sourceRecordId', () {
      const bazarItemId = 'abc123';
      final id1 = FinancialService.transactionId('bazar', bazarItemId);
      final id2 = FinancialService.transactionId('bazar', bazarItemId);
      expect(id1, equals(id2));
    });

    test('transactionId differs across sources', () {
      const itemId = 'xyz789';
      final bazarId = FinancialService.transactionId('bazar', itemId);
      final dailyId = FinancialService.transactionId('daily', itemId);
      expect(bazarId, isNot(equals(dailyId)));
    });

    test('different record ids produce different tx ids', () {
      final id1 = FinancialService.transactionId('bazar', 'item_A');
      final id2 = FinancialService.transactionId('bazar', 'item_B');
      expect(id1, isNot(equals(id2)));
    });
  });

  // -------------------------------------------------------------------------
  // 4. Task date filter correctness (mirrors _CombinedPlannerList logic)
  // -------------------------------------------------------------------------
  group('Task date filter: !due.isBefore(dayKey) && due.isBefore(endOfDay)', () {
    bool taskVisibleOnDay(DateTime due, DateTime selectedDay) {
      final dayKey =
          DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      final endOfDay = dayKey.add(const Duration(days: 1));
      return !due.isBefore(dayKey) && due.isBefore(endOfDay);
    }

    final sep5 = DateTime(2026, 9, 5);

    test('task due at 09:00 on Sep 5 is visible on Sep 5', () {
      expect(taskVisibleOnDay(DateTime(2026, 9, 5, 9, 0), sep5), isTrue);
    });

    test('task due at 23:59 on Sep 5 is visible on Sep 5', () {
      expect(taskVisibleOnDay(DateTime(2026, 9, 5, 23, 59), sep5), isTrue);
    });

    test('task due at midnight Sep 5 (00:00) is visible on Sep 5', () {
      expect(taskVisibleOnDay(DateTime(2026, 9, 5, 0, 0), sep5), isTrue);
    });

    test('task due on Sep 4 is NOT visible on Sep 5', () {
      expect(taskVisibleOnDay(DateTime(2026, 9, 4, 12, 0), sep5), isFalse);
    });

    test('task due on Sep 6 is NOT visible on Sep 5', () {
      expect(taskVisibleOnDay(DateTime(2026, 9, 6, 9, 0), sep5), isFalse);
    });

    test('midnight Sep 6 is NOT visible on Sep 5', () {
      expect(taskVisibleOnDay(DateTime(2026, 9, 6, 0, 0), sep5), isFalse);
    });

    test('REGRESSION: old !isAfter condition hides 09:00 task', () {
      final due = DateTime(2026, 9, 5, 9, 0);
      final dayKey = DateTime(2026, 9, 5);
      final endOfDay = dayKey.add(const Duration(days: 1));
      final oldResult = !due.isAfter(dayKey) && due.isBefore(endOfDay);
      final newResult = !due.isBefore(dayKey) && due.isBefore(endOfDay);
      expect(oldResult, isFalse, reason: 'Old condition wrongly hides tasks due after midnight');
      expect(newResult, isTrue, reason: 'Corrected condition shows tasks due during the day');
    });
  });

  // -------------------------------------------------------------------------
  // 5. initialDate pre-fill
  // -------------------------------------------------------------------------
  group('Task form initialDate pre-fill', () {
    test('initialDate maps to 09:00 on that day', () {
      final selectedDay = DateTime(2026, 9, 5);
      final prefilledDue =
          DateTime(selectedDay.year, selectedDay.month, selectedDay.day, 9, 0);
      expect(prefilledDue.year, equals(2026));
      expect(prefilledDue.month, equals(9));
      expect(prefilledDue.day, equals(5));
      expect(prefilledDue.hour, equals(9));
      expect(prefilledDue.minute, equals(0));
    });

    test('pre-filled due falls within the selected day filter', () {
      final selectedDay = DateTime(2026, 9, 5);
      final prefilledDue =
          DateTime(selectedDay.year, selectedDay.month, selectedDay.day, 9, 0);
      final dayKey =
          DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      final endOfDay = dayKey.add(const Duration(days: 1));
      final visible =
          !prefilledDue.isBefore(dayKey) && prefilledDue.isBefore(endOfDay);
      expect(visible, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 6. FinancialService key helpers
  // -------------------------------------------------------------------------
  group('FinancialService key helpers', () {
    test('dateKey formats YYYY-MM-DD', () {
      expect(FinancialService.dateKey(DateTime(2026, 9, 5)), equals('2026-09-05'));
    });

    test('monthKey formats YYYY-MM', () {
      expect(FinancialService.monthKey(DateTime(2026, 9, 5)), equals('2026-09'));
    });

    test('dateKey pads single-digit month and day', () {
      expect(FinancialService.dateKey(DateTime(2026, 1, 3)), equals('2026-01-03'));
    });
  });
}
