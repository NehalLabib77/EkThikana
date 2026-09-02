// Static guards for the "delete a medicine" cascade.
//
// Spec §53 lets a student permanently remove a medicine along with its dose
// history and any expense-mirror rows that were created when doses were
// marked taken. We do this entirely client-side with batched writes, so the
// safety we can verify without spinning up an emulator is:
//
//   * The cascade reaches *all three* collections (medicines,
//     medicine_doses, financial_transactions). A cascade that forgets the
//     medicine itself or its mirror rows would leave orphaned ledger data
//     and show up as a phantom money line in the Wallet.
//
//   * The batch size is capped below Firestore's 500-op hard limit so a
//     chronic-medicine user with years of doses cannot crash the delete.
//
//   * The Firestore rule that gates update on `ownerId == request.auth.uid`
//     cannot silently bite the delete path — Firestore evaluates the
//     `delete` rule for `batch.delete`, not the `update` rule.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('FinancialService.deleteMedicine reaches every collection', () {
    late String source;

    setUpAll(() => source = _read('lib/services/financial_service.dart'));

    String methodBody() {
      final start = source.indexOf('static Future<void> deleteMedicine(');
      final nextStatic = source.indexOf('\n  static ', start + 1);
      return source.substring(start, nextStatic);
    }

    test('the method exists', () {
      expect(source, contains('static Future<void> deleteMedicine('));
    });

    test('the medicine doc itself is deleted', () {
      final body = methodBody();
      expect(
        body,
        contains('await medicineRef.delete()'),
        reason:
            'the medicine doc must be removed; otherwise the Medicine list '
            'still shows the medicine after a "successful" delete',
      );
    });

    test('every dose row is deleted in a batch', () {
      final body = methodBody();
      expect(body, contains("collection('medicine_doses')"));
      expect(body, contains('batch.delete(pair[0])'));
    });

    test('the financial_transactions mirror row is also deleted', () {
      final body = methodBody();
      expect(body, contains("collection('financial_transactions')"));
      expect(
        body,
        contains('transactionId(\'medicine\', doseDoc.id)'),
        reason:
            'the mirror row id is deterministic from the dose id and must '
            'be reached here so the Wallet does not keep a phantom entry',
      );
      expect(body, contains('batch.delete(pair[1])'));
    });

    test('batches are kept well below the 500-op Firestore cap', () {
      final body = methodBody();
      // 100 dose+mirror pairs per batch is comfortable: two deletes per
      // pair leaves us at 200 ops, leaving headroom for retries and any
      // future field writes.
      expect(
        body,
        contains('const maxOpsPerBatch = 200;'),
        reason: 'a delete cascade must never risk hitting the 500-op cap',
      );
    });

    test('ownership is checked before any write happens', () {
      final body = methodBody();
      expect(
        body,
        contains("medicineData['ownerId'] != uid"),
        reason:
            'a non-owner must not be able to delete someone else\'s '
            'medicine even if the UI lets them tap the menu',
      );
    });

    test('the query is scoped to the current owner', () {
      final body = methodBody();
      expect(
        body,
        contains("where('ownerId', isEqualTo: uid)"),
        reason: 'the dose sweep must filter by uid so no other user is '
            'affected by a stray delete',
      );
    });

    test('paging is in place for chronic users with many doses', () {
      final body = methodBody();
      expect(body, contains('orderBy(FieldPath.documentId)'));
      expect(
        body,
        contains('.startAfter('),
        reason: 'a user with more than one page of doses must still see '
            'every record removed',
      );
    });
  });
}