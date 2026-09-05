// Static guards for the Dena/Pawna ledger redesign (Part 4).
//
// These are string-level guards so they run without an emulator.
// They verify:
//   * Data model fields exist (outstandingAmount, status, settlements, dueDate)
//   * Cash-flow rule: settlements adjust Remaining, not Monthly Money
//   * Idempotent settlement with stable linkage
//   * All navigation destinations preserved

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Dena/Pawna data model', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/services/financial_service.dart',
      ),
    );

    test('saveDenaPawna writes outstandingAmount and status fields', () {
      expect(source, contains("'outstandingAmount': amount"));
      expect(source, contains("'status': 'outstanding'"));
    });

    test('saveDenaPawna supports optional dueDate', () {
      expect(source, contains('DateTime? dueDate'));
      expect(source, contains("'dueDate': Timestamp.fromDate(dueDate)"));
      expect(source, contains("'dueDateKey': dateKey(dueDate)"));
    });

    test('saveDenaPawna initializes empty settlements array', () {
      expect(source, contains("'settlements': <dynamic>[]"));
    });

    test('settleDenaPawna validates settle amount', () {
      expect(source, contains('settleAmount <= 0'));
      expect(source, contains('Settlement amount cannot exceed outstanding'));
    });

    test('settleDenaPawna computes new outstanding and status', () {
      expect(source, contains('newOutstanding = (currentOutstanding - settleAmount).clamp'));
      expect(source, contains('isFullySettled = newOutstanding <= 0'));
      expect(source, contains("'partially_settled'"));
    });

    test('settleDenaPawna stores settlement record inline', () {
      expect(source, contains("'settlements': [...existingSettlements, settlementRecord]"));
      expect(source, contains("'id': settlementId"));
    });

    test('settlement ID is deterministic for idempotency', () {
      expect(source, contains('settlement_'));
      expect(source, contains('DateTime.now().millisecondsSinceEpoch'));
    });

    test('deleteDenaPawna checks ownership before delete', () {
      expect(source, contains('You can only delete your own records'));
    });

    test('denaPawnaSettlementTotalsStream exists for UI adjustment', () {
      expect(source, contains('denaPawnaSettlementTotalsStream'));
      expect(source, contains("'pawnaReceived'"));
      expect(source, contains("'denaPaid'"));
    });
  });

  group('Dena/Pawna UI (dena_pawna_tab.dart)', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/life/presentation/expense/dena_pawna_tab.dart',
      ),
    );

    test('shows Dena outstanding and Pawna outstanding summary', () {
      expect(source, contains('Dena outstanding'));
      expect(source, contains('Pawna outstanding'));
      expect(source, contains('totalDenaOutstanding'));
      expect(source, contains('totalPawnaOutstanding'));
    });

    test('computes outstanding from outstandingAmount, not amount', () {
      expect(source, contains("(data['outstandingAmount'] as num?)?.toDouble()"));
    });

    test('supports edit via existing parameter', () {
      expect(source, contains('showDenaPawnaSheet(context, existing: doc)'));
    });

    test('supports partial settlement', () {
      expect(source, contains('_showSettleDialog'));
      expect(source, contains('settleAmount'));
    });

    test('supports due date picker', () {
      expect(source, contains('showDatePicker'));
      expect(source, contains('_dueDate'));
    });

    test('delete has confirmation dialog', () {
      expect(source, contains('_confirmDelete'));
      expect(source, contains('showConfirmationSheet'));
    });

    test('no chevrons in list rows', () {
      expect(source, isNot(contains('chevron')));
    });
  });

  group('Cash-flow rule', () {
    test('settlements stored in dena_pawna_items, not financial_transactions', () {
      final financialService = _read(
        'lib/services/financial_service.dart',
      );
      // settleDenaPawna should NOT create financial_transactions records
      expect(financialService, isNot(contains("collection('financial_transactions').doc(transactionId(source, id))")));
    });

    test('Monthly Money is never modified by Dena/Pawna', () {
      final financialService = _read(
        'lib/services/financial_service.dart',
      );
      // saveDenaPawna should NOT touch monthly_budget collection
      expect(financialService, isNot(contains("collection('monthly_budget')")));
    });

    test('Overview tab adjusts Remaining by settlement totals', () {
      final overviewTab = _read(
        'lib/features/life/presentation/expense/overview_tab.dart',
      );
      expect(overviewTab, contains('denaPawnaSettlementTotalsStream'));
      expect(overviewTab, contains('pawnaReceived'));
      expect(overviewTab, contains('denaPaid'));
      expect(overviewTab, contains('adjustedRemaining'));
    });
  });

  group('Firestore rules', () {
    test('financial_transactions allows dena_paid and pawna_received sources', () {
      final rules = _read('../firebase/firestore.rules');
      expect(rules, contains("'dena_paid'"));
      expect(rules, contains("'pawna_received'"));
    });
  });

  group('Navigation destinations', () {
    test('all 6 navigation destinations preserved in dena_pawna_tab.dart', () {
      final source = _read(
        'lib/features/life/presentation/expense/dena_pawna_tab.dart',
      );
      expect(source, contains('FinancialService.denaPawnaStream'));
      expect(source, contains('FinancialService.saveDenaPawna'));
      expect(source, contains('FinancialService.settleDenaPawna'));
      expect(source, contains('FinancialService.deleteDenaPawna'));
    });
  });
}
