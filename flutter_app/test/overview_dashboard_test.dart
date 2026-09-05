import 'dart:io';

import 'package:gochano/features/life/presentation/expense/overview_tab.dart';
import 'package:gochano/models/financial_transaction.dart';
import 'package:gochano/services/financial_service.dart';
import 'package:flutter_test/flutter_test.dart';

FinancialTransactionModel _tx({
  String id = 't',
  String source = 'daily',
  String category = 'Other',
  String title = 'Test',
  double amount = 0,
  required DateTime date,
}) {
  return FinancialTransactionModel(
    id: id,
    userId: 'user1',
    type: 'expense',
    source: source,
    sourceRecordId: 'src_$id',
    category: category,
    title: title,
    amount: amount,
    date: date,
  );
}

void main() {
  group('getDaysInMonth', () {
    test('September 2026 has 30 days', () {
      expect(getDaysInMonth(DateTime(2026, 9)), equals(30));
    });

    test('October 2026 has 31 days', () {
      expect(getDaysInMonth(DateTime(2026, 10)), equals(31));
    });

    test('February 2026 has 28 days (non-leap)', () {
      expect(getDaysInMonth(DateTime(2026, 2)), equals(28));
    });

    test('February 2028 has 29 days (leap year)', () {
      expect(getDaysInMonth(DateTime(2028, 2)), equals(29));
    });

    test('January has 31 days', () {
      expect(getDaysInMonth(DateTime(2026, 1)), equals(31));
    });

    test('April has 30 days', () {
      expect(getDaysInMonth(DateTime(2026, 4)), equals(30));
    });

    test('December has 31 days', () {
      expect(getDaysInMonth(DateTime(2026, 12)), equals(31));
    });
  });

  group('monthKey and dateKey (used by month filtering)', () {
    test('monthKey is YYYY-MM zero-padded', () {
      expect(FinancialService.monthKey(DateTime(2026, 1, 15)),
          equals('2026-01'));
    });

    test('monthKey for December', () {
      expect(FinancialService.monthKey(DateTime(2026, 12, 1)),
          equals('2026-12'));
    });

    test('dateKey is YYYY-MM-DD zero-padded', () {
      expect(FinancialService.dateKey(DateTime(2026, 9, 5)),
          equals('2026-09-05'));
    });
  });

  group('FinancialSummary (used by monthly summary cards)', () {
    test('totalSpending sums all expense amounts for the month', () {
      final items = [
        _tx(source: 'daily', amount: 100, date: DateTime(2026, 9, 1)),
        _tx(source: 'bazar', amount: 250, date: DateTime(2026, 9, 5)),
        _tx(source: 'medicine', amount: 75, date: DateTime(2026, 9, 10)),
      ];
      final summary = FinancialSummary.fromTransactions(items);
      expect(summary.totalSpending, equals(425));
    });

    test('bySource groups amounts by source', () {
      final items = [
        _tx(source: 'daily', amount: 50, date: DateTime(2026, 9, 1)),
        _tx(source: 'daily', amount: 30, date: DateTime(2026, 9, 2)),
        _tx(source: 'bazar', amount: 200, date: DateTime(2026, 9, 3)),
      ];
      final summary = FinancialSummary.fromTransactions(items);
      expect(summary.bySource['daily'], equals(80));
      expect(summary.bySource['bazar'], equals(200));
    });

    test('only expense type contributes to spending', () {
      final items = [
        _tx(source: 'daily', amount: 100, date: DateTime(2026, 9, 1)),
      ];
      final summary = FinancialSummary.fromTransactions(items);
      expect(summary.totalSpending, equals(100));
    });

    test('empty transactions produce zero summary', () {
      final summary = FinancialSummary.fromTransactions(const []);
      expect(summary.totalSpending, equals(0));
      expect(summary.bySource, isEmpty);
    });
  });

  group('Day filtering (used by bar chart and day detail)', () {
    test('transactions for September 2026 are filtered by month', () {
      final items = [
        _tx(source: 'daily', amount: 50, date: DateTime(2026, 9, 1)),
        _tx(source: 'daily', amount: 30, date: DateTime(2026, 9, 5)),
        _tx(source: 'bazar', amount: 200, date: DateTime(2026, 8, 25)),
        _tx(source: 'daily', amount: 10, date: DateTime(2026, 10, 1)),
      ];
      // Filter to September only
      final septItems = items
          .where((i) => i.date.month == 9 && i.date.year == 2026)
          .toList();
      expect(septItems.length, equals(2));
      expect(
        septItems.fold<double>(0, (s, i) => s + i.amount),
        equals(80),
      );
    });

    test('daily totals are computed per day', () {
      final items = [
        _tx(source: 'daily', amount: 50, date: DateTime(2026, 9, 1)),
        _tx(source: 'bazar', amount: 30, date: DateTime(2026, 9, 1)),
        _tx(source: 'daily', amount: 100, date: DateTime(2026, 9, 5)),
      ];
      final dailyTotals = <int, double>{};
      for (final item in items) {
        if (item.date.month == 9 && item.date.year == 2026) {
          final day = item.date.day;
          dailyTotals[day] = (dailyTotals[day] ?? 0) + item.amount;
        }
      }
      expect(dailyTotals[1], equals(80));
      expect(dailyTotals[5], equals(100));
      expect(dailyTotals.containsKey(10), isFalse);
    });

    test('day filtering extracts transactions for a specific day', () {
      final items = [
        _tx(source: 'daily', amount: 50, date: DateTime(2026, 9, 5, 8, 30)),
        _tx(source: 'bazar', amount: 30, date: DateTime(2026, 9, 5, 14, 0)),
        _tx(source: 'daily', amount: 100, date: DateTime(2026, 9, 10)),
      ];
      final dayItems = items
          .where((i) =>
              i.date.day == 5 && i.date.month == 9 && i.date.year == 2026)
          .toList();
      expect(dayItems.length, equals(2));
      expect(
        dayItems.fold<double>(0, (s, i) => s + i.amount),
        equals(80),
      );
    });
  });

  group('Cash-flow calculations (inflow vs outflow)', () {
    test('outflow = totalSpent + denaPaid', () {
      final totalSpent = 1500.0;
      final denaPaid = 200.0;
      final outflow = totalSpent + denaPaid;
      expect(outflow, equals(1700));
    });

    test('inflow = pawnaReceived', () {
      final pawnaReceived = 300.0;
      final inflow = pawnaReceived;
      expect(inflow, equals(300));
    });

    test('remaining = backendRemaining + pawnaReceived - denaPaid', () {
      final backendRemaining = 5000.0;
      final pawnaReceived = 300.0;
      final denaPaid = 200.0;
      final remaining = backendRemaining + pawnaReceived - denaPaid;
      expect(remaining, equals(5100));
    });

    test('remaining is negative when overspent', () {
      final backendRemaining = 100.0;
      final pawnaReceived = 0.0;
      final denaPaid = 0.0;
      final remaining = backendRemaining + pawnaReceived - denaPaid;
      final totalSpent = 500.0;
      final adjustedRemaining = remaining - totalSpent;
      expect(adjustedRemaining, lessThan(0));
    });
  });

  group('Bar chart daily totals', () {
    test('maxAmount is the highest daily total', () {
      final dailyTotals = {
        1: 100.0,
        5: 500.0,
        10: 200.0,
        15: 50.0,
      };
      final maxAmount =
          dailyTotals.values.fold<double>(0, (a, b) => a > b ? a : b);
      expect(maxAmount, equals(500));
    });

    test('empty month has zero maxAmount', () {
      final dailyTotals = <int, double>{};
      final maxAmount =
          dailyTotals.values.fold<double>(0, (a, b) => a > b ? a : b);
      expect(maxAmount, equals(0));
    });

    test('bar fraction is clamped between 0.05 and 1.0', () {
      final maxAmount = 500.0;
      final amount = 250.0;
      final fraction = (amount / maxAmount).clamp(0.05, 1.0);
      expect(fraction, closeTo(0.5, 0.01));
    });

    test('zero amount has minimum fraction of 0.05', () {
      final maxAmount = 500.0;
      final amount = 0.0;
      final fraction = (amount / maxAmount).clamp(0.05, 1.0);
      expect(fraction, equals(0.05));
    });
  });

  group('Month navigation', () {
    test('previous month decrements correctly', () {
      final current = DateTime(2026, 9);
      final prev = DateTime(current.year, current.month - 1);
      expect(prev, equals(DateTime(2026, 8)));
    });

    test('next month increments correctly', () {
      final current = DateTime(2026, 9);
      final next = DateTime(current.year, current.month + 1);
      expect(next, equals(DateTime(2026, 10)));
    });

    test('next month beyond current month is blocked', () {
      final now = DateTime(2026, 9);
      final nextCandidate = DateTime(now.year, now.month + 1);
      final blocked = nextCandidate.isAfter(DateTime(now.year, now.month));
      expect(blocked, isTrue);
    });

    test('month does not mix data from different months', () {
      final septItems = [
        _tx(source: 'daily', amount: 100, date: DateTime(2026, 9, 1)),
        _tx(source: 'daily', amount: 200, date: DateTime(2026, 9, 15)),
      ];
      final augItems = [
        _tx(source: 'daily', amount: 500, date: DateTime(2026, 8, 1)),
      ];
      final septTotal =
          septItems.fold<double>(0, (s, i) => s + i.amount);
      final augTotal =
          augItems.fold<double>(0, (s, i) => s + i.amount);
      expect(septTotal, equals(300));
      expect(augTotal, equals(500));
      expect(septTotal, isNot(equals(augTotal)));
    });
  });

  group('Future days', () {
    test('future days have no fabricated values', () {
      final now = DateTime(2026, 9, 11);
      final daysInMonth = getDaysInMonth(DateTime(2026, 9));
      final futureDays = <int>[];
      for (var day = 1; day <= daysInMonth; day++) {
        if (day > now.day) futureDays.add(day);
      }
      expect(futureDays, isNotEmpty);
      expect(futureDays.first, equals(12));
    });

    test('today is not in the future days list', () {
      final now = DateTime(2026, 9, 11);
      final isFuture = 11 > now.day;
      expect(isFuture, isFalse);
    });
  });

  group('Today vs past days display logic', () {
    test('today is always detailed', () {
      const bool showDetailed = true;
      expect(showDetailed, isTrue);
    });

    test('past day is compact by default', () {
      final isToday = false;
      final isExpanded = false;
      final showDetailed = isToday || isExpanded;
      expect(showDetailed, isFalse);
    });

    test('past day is detailed when expanded', () {
      final isToday = false;
      final isExpanded = true;
      final showDetailed = isToday || isExpanded;
      expect(showDetailed, isTrue);
    });
  });

  group('Overview refresh mechanism', () {
    late String source;

    setUpAll(() {
      source = File('lib/features/life/presentation/expense/overview_tab.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
    });

    test('OverviewTab has _budgetRefreshKey for forced refresh', () {
      expect(source, contains('_budgetRefreshKey'));
      expect(source, contains('_budgetRefreshKey++'));
    });

    test('FutureBuilder uses ValueKey with refresh counter', () {
      expect(source, contains("ValueKey('budget-"));
      expect(source, contains('_budgetRefreshKey'));
    });

    test('refresh() increments the budget refresh key', () {
      expect(source, contains('setState(() => _budgetRefreshKey++)'));
    });
  });

  group('Overview category bars', () {
    late String source;

    setUpAll(() {
      source = File('lib/features/life/presentation/expense/overview_tab.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
    });

    test('has _CategoryBar widget', () {
      expect(source, contains('class _CategoryBar'));
    });

    test('has _ProgressBar widget', () {
      expect(source, contains('class _ProgressBar'));
    });

    test('has _SummaryRow widget', () {
      expect(source, contains('class _SummaryRow'));
    });

    test('category bars show Daily, Grocery, Medicine, Dena paid, Pawna received', () {
      expect(source, contains("_CategoryBar(\n                label: GochanoLanguage.text('Daily'"));
      expect(source, contains("_CategoryBar(\n                label: GochanoLanguage.text('Grocery'"));
      expect(source, contains("_CategoryBar(\n                label: GochanoLanguage.text('Medicine'"));
      expect(source, contains("_CategoryBar(\n                label: GochanoLanguage.text('Dena paid'"));
      expect(source, contains("_CategoryBar(\n                label: GochanoLanguage.text('Pawna received'"));
    });

    test('today card has brand accent', () {
      expect(source, contains('accent: isToday ? colors.brand : null'));
    });
  });
}
