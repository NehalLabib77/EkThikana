// Guards the ledger-mirror writes that reached a device as
// "You do not have access to this item."
//
// The expense ledger keeps one mirrored `financial_transactions` row per
// purchased bazar item and per taken medicine dose. When an item is *not*
// purchased, or a dose is skipped, that mirror row has to go away — so the
// code issued a `batch.delete()` on it.
//
// For a row that was never written, that delete is denied: the rule reads
// `resource.data.ownerId`, and on a non-existent document `resource` is null.
// Because the delete rode in the same batch as the item write, the denial
// rejected the *whole batch*. A student could not add an unpurchased item at
// all, which is why adding to the bazar list appeared to require ticking
// "Already purchased", and marking a dose skipped or missed failed the same
// way on the Medicine screen.
//
// Two fixes, pinned here:
//   1. A brand-new bazar item never asks to delete a row that cannot exist.
//   2. The security rule treats deleting a missing mirror row as the no-op it
//      is, which covers the medicine and delete paths too.
//
// These are static guards over the source, because the failure lives in the
// interaction between a batched write and a security rule — neither of which
// a widget test reaches.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('A new bazar item does not delete a row that cannot exist', () {
    late String source;

    setUpAll(() => source = _read('lib/services/financial_service.dart'));

    test('the mirror delete is guarded by the item already existing', () {
      // `id == null` means the item is being created, so no mirror row has
      // ever been written for it.
      expect(
        source,
        contains('} else if (id != null) {'),
        reason: 'the bazar mirror delete must be reachable only for an edit',
      );
    });

    test('the guard sits on the bazar save, not somewhere incidental', () {
      final save = source.substring(
        source.indexOf('static Future<String> saveBazarItem('),
        source.indexOf('static Future<void> toggleBazarPurchased('),
      );

      expect(save, contains('batch.delete(financialRef)'));
      expect(save, contains('} else if (id != null) {'));
      // And the purchased branch still writes the mirror row, so the ledger
      // total is unaffected by this fix.
      expect(save, contains('if (purchased && price > 0) {'));
    });
  });

  group('The security rule allows an idempotent mirror delete', () {
    late String rules;

    setUpAll(() => rules = _read('../firebase/firestore.rules'));

    test('financial_transactions delete tolerates a missing document', () {
      final section = rules.substring(
        rules.indexOf('match /financial_transactions/{id}'),
      );

      expect(
        section,
        contains('resource == null || resource.data.ownerId == request.auth.uid'),
        reason:
            'deleting a mirror row that was never written must be a no-op, '
            'not a denial that rejects the whole batch',
      );
    });

    test('read is still restricted to the owner', () {
      // The delete became permissive on purpose; the read must not have.
      final section = rules.substring(
        rules.indexOf('match /financial_transactions/{id}'),
      );

      expect(
        section,
        contains('allow read: if verified() && resource.data.ownerId == request.auth.uid'),
        reason: 'loosening delete must not have loosened read',
      );
      expect(section, isNot(contains('allow read, delete:')));
    });

    test('create and update still require ownership', () {
      final section = rules.substring(
        rules.indexOf('match /financial_transactions/{id}'),
      );

      expect(section, contains("request.resource.data.ownerId == request.auth.uid"));
      expect(section, contains("request.resource.data.type == 'expense'"));
    });
  });
}
