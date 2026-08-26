import 'package:gochano/models/financial_transaction.dart';
import 'package:gochano/services/financial_service.dart';
import 'package:flutter_test/flutter_test.dart';

FinancialTransactionModel _tx({
  String id = 't',
  String type = 'expense',
  String source = 'daily',
  String sourceRecordId = 'src1',
  String title = 'Test',
  double amount = 0,
}) {
  return FinancialTransactionModel(
    id: id,
    userId: 'user1',
    type: type,
    source: source,
    sourceRecordId: sourceRecordId,
    category: 'Other',
    title: title,
    amount: amount,
    date: DateTime(2026, 8, 25),
  );
}

void main() {
  group('transactionId (central ledger idempotency)', () {
    test('is deterministic for the same (source, sourceRecordId) pair', () {
      final a = FinancialService.transactionId('daily', 'abc123');
      final b = FinancialService.transactionId('daily', 'abc123');
      expect(a, equals(b));
    });

    test('differs when source changes', () {
      final daily = FinancialService.transactionId('daily', 'abc123');
      final bazar = FinancialService.transactionId('bazar', 'abc123');
      expect(daily, isNot(equals(bazar)));
    });

    test('differs when sourceRecordId changes', () {
      final one = FinancialService.transactionId('daily', 'abc123');
      final two = FinancialService.transactionId('daily', 'abc456');
      expect(one, isNot(equals(two)));
    });

    test('sanitizes characters that are illegal in document ids', () {
      final raw = FinancialService.transactionId('commute', 'a/b c?id=1');
      expect(raw.contains('/'), isFalse);
      expect(raw.contains('?'), isFalse);
      expect(raw.contains(' '), isFalse);
      expect(raw.endsWith('_a_b_c_id_1'), isTrue);
    });
  });

  group('FinancialSummary.fromTransactions (savings never counted as expense)', () {
    test('expense transactions contribute to spending', () {
      final summary = FinancialSummary.fromTransactions([
        _tx(source: 'daily', amount: 100),
        _tx(source: 'bazar', amount: 250.5),
      ]);
      expect(summary.totalSpending, equals(350.5));
      expect(summary.totalSavings, equals(0));
      expect(summary.bySource['daily'], equals(100));
      expect(summary.bySource['bazar'], equals(250.5));
    });

    test('saving transactions contribute to savings only', () {
      final summary = FinancialSummary.fromTransactions([
        _tx(source: 'saving', type: 'saving', amount: 500),
        _tx(source: 'daily', amount: 200),
      ]);
      expect(summary.totalSpending, equals(200));
      expect(summary.totalSavings, equals(500));
      expect(summary.bySource.containsKey('saving'), isFalse,
          reason: 'savings must never appear in spending breakdown');
    });

    test('mixed set keeps savings separate from spending', () {
      final summary = FinancialSummary.fromTransactions([
        _tx(source: 'medicine', amount: 75),
        _tx(source: 'commute', amount: 40),
        _tx(source: 'saving', type: 'saving', amount: 1000),
        _tx(source: 'daily', amount: 60),
      ]);
      expect(summary.totalSpending, equals(175));
      expect(summary.totalSavings, equals(1000));
      expect(summary.bySource.keys.toSet(),
          equals({'medicine', 'commute', 'daily'}));
      expect(summary.netDifference, equals(825));
    });

    test('empty input is a clean zero summary', () {
      final summary = FinancialSummary.fromTransactions(const []);
      expect(summary.totalSpending, equals(0));
      expect(summary.totalSavings, equals(0));
      expect(summary.bySource, isEmpty);
      expect(summary.netDifference, equals(0));
    });
  });

  group('monthKey/dateKey (used by ledger filters)', () {
    test('dateKey is YYYY-MM-DD zero-padded', () {
      expect(FinancialService.dateKey(DateTime(2026, 1, 9)),
          equals('2026-01-09'));
    });

    test('monthKey is YYYY-MM zero-padded', () {
      expect(FinancialService.monthKey(DateTime(2026, 11, 30)),
          equals('2026-11'));
    });
  });
}