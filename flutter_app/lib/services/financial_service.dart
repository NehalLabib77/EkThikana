import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/financial_transaction.dart';
import 'firestore_service.dart';

class FinancialService {
  FinancialService._();

  static FirebaseFirestore get db => FirestoreService.db;
  static String? get uid => FirestoreService.uid;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  static String _safeId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String transactionId(String source, String sourceRecordId) =>
      '${_safeId(source)}_${_safeId(sourceRecordId)}';

  static Map<String, dynamic> _financialData({
    required String type,
    required String source,
    required String sourceRecordId,
    required String category,
    required String title,
    required double amount,
    required DateTime date,
  }) {
    final currentUid = uid;
    return {
      'ownerId': currentUid,
      'userId': currentUid,
      'type': type,
      'source': source,
      'sourceRecordId': sourceRecordId,
      'category': category,
      'title': title.trim(),
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'dateKey': dateKey(date),
      'monthKey': monthKey(date),
      // Gochano only mirrors a ledger row once the underlying thing is real:
      // a logged daily expense, a *purchased* bazar item, a *taken* medicine
      // dose, a *confirmed* actual commute fare. Estimated values never reach
      // this collection, so every row we write is confirmed. Stating it
      // explicitly means `GET /api/budget/remaining` reads the status from
      // the document instead of relying on its absent-field default.
      'status': 'confirmed',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }


  static Stream<List<FinancialTransactionModel>> allTransactionsStream({
    int limit = 2000,
  }) {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<List<FinancialTransactionModel>>.fromFuture(
        Future.value(<FinancialTransactionModel>[]),
      );
    }
    return db
        .collection('financial_transactions')
        .where('ownerId', isEqualTo: currentUid)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map(FinancialTransactionModel.fromDoc)
              .where((item) => item.type == 'expense')
              .toList();
          items.sort((a, b) => b.date.compareTo(a.date));
          return items;
        });
  }

  static Stream<List<FinancialTransactionModel>> monthStream(DateTime month) {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<List<FinancialTransactionModel>>.fromFuture(
        Future.value(<FinancialTransactionModel>[]),
      );
    }
    return db
        .collection('financial_transactions')
        .where('ownerId', isEqualTo: currentUid)
        .where('monthKey', isEqualTo: monthKey(month))
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map(FinancialTransactionModel.fromDoc)
              .where((item) => item.type == 'expense')
              .toList();
          items.sort((a, b) => b.date.compareTo(a.date));
          return items;
        });
  }

  static Stream<List<FinancialTransactionModel>> dayStream(DateTime day) {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<List<FinancialTransactionModel>>.fromFuture(
        Future.value(<FinancialTransactionModel>[]),
      );
    }
    return db
        .collection('financial_transactions')
        .where('ownerId', isEqualTo: currentUid)
        .where('dateKey', isEqualTo: dateKey(day))
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map(FinancialTransactionModel.fromDoc)
              .where((item) => item.type == 'expense')
              .toList();
          items.sort((a, b) => b.date.compareTo(a.date));
          return items;
        });
  }

  static Future<String> addDailyExpense({
    required String category,
    required String title,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (amount <= 0) throw Exception('Amount must be greater than zero.');
    final sourceRef = db.collection('daily_expenses').doc();
    final financialRef = db
        .collection('financial_transactions')
        .doc(transactionId('daily', sourceRef.id));
    final batch = db.batch();

    batch.set(sourceRef, {
      'ownerId': uid,
      'category': category,
      'title': title.trim(),
      'amount': amount,
      'note': note.trim(),
      'date': Timestamp.fromDate(date),
      'dateKey': dateKey(date),
      'monthKey': monthKey(date),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(financialRef, {
      ..._financialData(
        type: 'expense',
        source: 'daily',
        sourceRecordId: sourceRef.id,
        category: category,
        title: title,
        amount: amount,
        date: date,
      ),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return sourceRef.id;
  }


  static Future<void> updateDailyExpense({
    required String id,
    required String category,
    required String title,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (amount <= 0) throw Exception('Amount must be greater than zero.');
    final sourceRef = db.collection('daily_expenses').doc(id);
    final financialRef = db
        .collection('financial_transactions')
        .doc(transactionId('daily', id));
    final batch = db.batch();

    batch.set(
      sourceRef,
      {
        'ownerId': uid,
        'category': category,
        'title': title.trim(),
        'amount': amount,
        'note': note.trim(),
        'date': Timestamp.fromDate(date),
        'dateKey': dateKey(date),
        'monthKey': monthKey(date),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      financialRef,
      {
        ..._financialData(
          type: 'expense',
          source: 'daily',
          sourceRecordId: id,
          category: category,
          title: title,
          amount: amount,
          date: date,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  static Future<void> deleteDailyExpense(String id) async {
    final batch = db.batch();
    batch.delete(db.collection('daily_expenses').doc(id));
    batch.delete(
      db.collection('financial_transactions').doc(transactionId('daily', id)),
    );
    await batch.commit();
  }

  static String bazarSessionId(DateTime date) {
    final currentUid = uid;
    if (currentUid == null) {
      return 'unknown_${dateKey(date).replaceAll('-', '')}';
    }
    return '${currentUid}_${dateKey(date).replaceAll('-', '')}';
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> bazarItemsForSession(
    String sessionId,
  ) {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.fromFuture(
        db.collection('bazar_items').limit(0).get(),
      );
    }
    return db
        .collection('bazar_items')
        .where('ownerId', isEqualTo: currentUid)
        .where('sessionId', isEqualTo: sessionId)
        .snapshots();
  }

  static Future<String> saveBazarItem({
    String? id,
    required String sessionId,
    required String category,
    required String title,
    required double quantity,
    required String unit,
    required double price,
    required bool purchased,
    required DateTime date,
  }) async {
    if (quantity <= 0) throw Exception('Quantity must be greater than zero.');
    if (price < 0) throw Exception('Price cannot be negative.');

    final sourceRef = id == null
        ? db.collection('bazar_items').doc()
        : db.collection('bazar_items').doc(id);
    final financialRef = db
        .collection('financial_transactions')
        .doc(transactionId('bazar', sourceRef.id));
    final batch = db.batch();

    batch.set(
      sourceRef,
      {
        'ownerId': uid,
        'sessionId': sessionId,
        'category': category,
        'title': title.trim(),
        'quantity': quantity,
        'unit': unit,
        'price': price,
        'purchased': purchased,
        'date': Timestamp.fromDate(date),
        'dateKey': dateKey(date),
        'monthKey': monthKey(date),
        if (id == null) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (purchased && price > 0) {
      batch.set(
        financialRef,
        {
          ..._financialData(
            type: 'expense',
            source: 'bazar',
            sourceRecordId: sourceRef.id,
            category: category,
            title: title,
            amount: price,
            date: date,
          ),
          if (id == null) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } else if (id != null) {
      // Only an *existing* item can have left a mirror row behind. A brand
      // new item has no ledger row to clear, and asking to delete one that
      // has never existed used to fail the security rule -- which rejected
      // the whole batch, so an item could not be added at all unless it was
      // marked purchased. That is why adding to the list appeared to require
      // "Already purchased".
      batch.delete(financialRef);
    }

    // A Phase-7 debug block used to sit here. It forced a token refresh
    // (`getIdTokenResult(true)`) on *every* bazar save — a network round trip
    // per keystroke-driven write — and printed the signed-in email and the
    // full set of auth claims into the device log. Both are removed: the
    // performance cost violated spec §83 and the log contents violated §82.
    try {
      await batch.commit();
    } on FirebaseException catch (fe) {
      // Keep the diagnosis in the log without the identity: the rule that
      // rejected the write is the useful part.
      debugPrint('Bazar ledger write rejected: ${fe.code}');
      rethrow;
    }
    return sourceRef.id;
  }

  static Future<void> toggleBazarPurchased(
    DocumentReference<Map<String, dynamic>> ref,
    bool purchased,
  ) async {
    final snap = await ref.get();
    final data = snap.data();
    if (data == null) throw Exception('Bazar item no longer exists.');
    final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    await saveBazarItem(
      id: ref.id,
      sessionId: data['sessionId']?.toString() ?? bazarSessionId(date),
      category: data['category']?.toString() ?? 'Other',
      title: data['title']?.toString() ?? 'Bazar item',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 1,
      unit: data['unit']?.toString() ?? 'pcs',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      purchased: purchased,
      date: date,
    );
  }

  static Future<void> deleteBazarItem(String id) async {
    final batch = db.batch();
    batch.delete(db.collection('bazar_items').doc(id));
    batch.delete(
      db.collection('financial_transactions').doc(transactionId('bazar', id)),
    );
    await batch.commit();
  }

  static String doseId(String medicineId, DateTime date, String hhmm) {
    final key = dateKey(date).replaceAll('-', '');
    return '${medicineId}_${key}_${hhmm.replaceAll(':', '')}';
  }

  static Future<void> recordMedicineDose({
    required String medicineId,
    required String medicineName,
    required String scheduledTime,
    required DateTime date,
    required String status,
    double actualQuantityTaken = 0,
    double unitPriceSnapshot = 0,
    String unit = 'tablet',
    String note = '',
  }) async {
    if (!{'taken', 'skipped', 'missed', 'pending'}.contains(status)) {
      throw Exception('Invalid dose status.');
    }
    if (status == 'taken' && actualQuantityTaken <= 0) {
      throw Exception('Actual quantity taken must be greater than zero.');
    }

    final id = doseId(medicineId, date, scheduledTime);
    final doseRef = db.collection('medicine_doses').doc(id);
    final financialRef = db
        .collection('financial_transactions')
        .doc(transactionId('medicine', id));
    final cost = status == 'taken'
        ? actualQuantityTaken * unitPriceSnapshot
        : 0.0;
    final batch = db.batch();

    batch.set(
      doseRef,
      {
        'ownerId': uid,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'scheduledTime': scheduledTime,
        'scheduledDate': dateKey(date),
        'status': status,
        'unit': unit,
        'unitPriceSnapshot': unitPriceSnapshot,
        'actualQuantityTaken': status == 'taken' ? actualQuantityTaken : 0,
        'cost': cost,
        'takenAt':
            status == 'taken' ? FieldValue.serverTimestamp() : null,
        'note': note.trim(),
        'date': Timestamp.fromDate(date),
        'dateKey': dateKey(date),
        'monthKey': monthKey(date),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (status == 'taken' && cost > 0) {
      batch.set(
        financialRef,
        {
          ..._financialData(
            type: 'expense',
            source: 'medicine',
            sourceRecordId: id,
            category: 'Medicine',
            title: medicineName,
            amount: cost,
            date: date,
          ),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } else {
      batch.delete(financialRef);
    }

    await batch.commit();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> medicineDoseHistory(
    String medicineId,
  ) {
    final currentUid = uid;
    if (currentUid == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.fromFuture(
        db.collection('medicine_doses').limit(0).get(),
      );
    }
    return db
        .collection('medicine_doses')
        .where('ownerId', isEqualTo: currentUid)
        .where('medicineId', isEqualTo: medicineId)
        .limit(500)
        .snapshots();
  }

  /// Delete a medicine and every trace of it: scheduled doses and any
  /// expense-mirror rows that were created when a dose was marked taken.
  ///
  /// Firestore batches are capped at 500 operations, so the work is split
  /// into chunks of at most 200 deletes (one medicine delete plus up to 199
  /// dose + mirror deletes per batch). A chronic-medicine user with years of
  /// history needs many batches; this method walks until everything is gone.
  ///
  /// Cascade behaviour:
  ///   * ``medicines/{medicineId}`` is removed.
  ///   * Every ``medicine_doses`` row whose ``medicineId`` matches is
  ///     removed.
  ///   * Every ``financial_transactions`` row whose
  ///     ``source == 'medicine'`` AND whose deterministic ``sourceRecordId``
  ///     equals a removed dose id is removed (a no-op delete on a doc that
  ///     was never written is permitted by the financial_transactions
  ///     delete rule; ``batch.delete`` on a non-existing doc is safe).
  ///
  /// ``medicineId`` must belong to the current user. If the medicine is
  /// missing the call still succeeds (no-op) so the UI can call this from
  /// a list that just streamed a stale snapshot.
  static Future<void> deleteMedicine(String medicineId) async {
    if (medicineId.isEmpty) {
      throw Exception('Medicine id is required.');
    }

    final medicineRef = db.collection('medicines').doc(medicineId);
    final medicineSnap = await medicineRef.get();
    if (!medicineSnap.exists) {
      // Already gone. Treat as success so the UI can call this defensively.
      return;
    }
    final medicineData = medicineSnap.data() ?? const <String, dynamic>{};
    if (medicineData['ownerId'] != uid) {
      // Firestore rules would refuse anyway; fail fast with a clearer
      // message instead of the generic "permission-denied".
      throw Exception('You can only delete your own medicines.');
    }

    // Walk every dose for this medicine, paging with ``startAfter`` so a
    // chronic-medicine user with thousands of doses is not capped at the
    // page-size limit.
    const pageSize = 200;
    const maxOpsPerBatch = 200; // 1 medicine + up to 199 dose+mirror pairs.

    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;

    while (true) {
      var query = db
          .collection('medicine_doses')
          .where('ownerId', isEqualTo: uid)
          .where('medicineId', isEqualTo: medicineId)
          .orderBy(FieldPath.documentId)
          .limit(pageSize);

      if (cursor != null) {
        query = query.startAfter([cursor]);
      }

      final snap = await query.get();
      if (snap.docs.isEmpty) {
        break;
      }

      // Two deletes per dose (dose row + mirror transaction). Cap each
      // batch so the 500-operation Firestore limit is never approached.
      final pairs = <List<DocumentReference<Map<String, dynamic>>>>[];
      for (final doseDoc in snap.docs) {
        pairs.add([
          doseDoc.reference,
          db
              .collection('financial_transactions')
              .doc(transactionId('medicine', doseDoc.id)),
        ]);
      }

      var batch = db.batch();
      var opsInBatch = 0;

      for (final pair in pairs) {
        if (opsInBatch + 2 > maxOpsPerBatch) {
          await batch.commit();
          batch = db.batch();
          opsInBatch = 0;
        }
        batch.delete(pair[0]);
        batch.delete(pair[1]);
        opsInBatch += 2;
      }

      await batch.commit();

      // We page until we get a short page (< pageSize), which is the
      // only signal Firestore gives that no more docs exist.
      if (snap.docs.length < pageSize) {
        break;
      }
      cursor = snap.docs.last;
    }

    // Finally, remove the medicine itself. A direct delete is a single op
    // so it does not need batching.
    await medicineRef.delete();
  }

  static Future<String> recordCommuteTrip({
    required String origin,
    required String destination,
    required String mode,
    required double distanceKm,
    required int estimatedMinutes,
    required double actualFare,
    required DateTime date,
    String fareSource = '',
    String fareConfidence = '',
  }) async {
    if (actualFare <= 0) throw Exception('Actual fare must be greater than zero.');
    final tripRef = db.collection('commute_trips').doc();
    final financialRef = db
        .collection('financial_transactions')
        .doc(transactionId('commute', tripRef.id));
    final batch = db.batch();

    batch.set(tripRef, {
      'ownerId': uid,
      'origin': origin,
      'destination': destination,
      'mode': mode,
      'distanceKm': distanceKm,
      'estimatedMinutes': estimatedMinutes,
      'actualFare': actualFare,
      'fareSource': fareSource,
      'fareConfidence': fareConfidence,
      'date': Timestamp.fromDate(date),
      'dateKey': dateKey(date),
      'monthKey': monthKey(date),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(financialRef, {
      ..._financialData(
        type: 'expense',
        source: 'commute',
        sourceRecordId: tripRef.id,
        category: mode,
        title: '$origin → $destination',
        amount: actualFare,
        date: date,
      ),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return tripRef.id;
  }

  static Future<void> deleteCommuteTrip(String id) async {
    final batch = db.batch();
    batch.delete(db.collection('commute_trips').doc(id));
    batch.delete(
      db.collection('financial_transactions').doc(transactionId('commute', id)),
    );
    await batch.commit();
  }

  static FinancialSummary summary(
    Iterable<FinancialTransactionModel> transactions,
  ) {
    return FinancialSummary.fromTransactions(transactions);
  }
}
