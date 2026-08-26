import 'package:gochano/services/financial_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Commute trip ledger guard (actual fare only)', () {
    test('transactionId format pins Commute records to one ledger entry',
        () {
      final id = FinancialService.transactionId('commute', 'trip42');
      expect(id, equals('commute_trip42'));
    });

    test('Commute and Medicine transactions never share an id', () {
      final commute =
          FinancialService.transactionId('commute', 'shared-source');
      final medicine =
          FinancialService.transactionId('medicine', 'shared-source');
      expect(commute, isNot(equals(medicine)));
    });
  });
}