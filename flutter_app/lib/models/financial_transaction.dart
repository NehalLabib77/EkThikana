import 'package:cloud_firestore/cloud_firestore.dart';

class FinancialTransactionModel {
  const FinancialTransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.source,
    required this.sourceRecordId,
    required this.category,
    required this.title,
    required this.amount,
    required this.date,
  });

  final String id;
  final String userId;
  // Current Gochano ledger is expense-only. `type` is retained so legacy
  // documents can be read safely; only `expense` records are counted/displayed.
  final String type;
  final String source; // daily | bazar | medicine | commute
  final String sourceRecordId;
  final String category;
  final String title;
  final double amount;
  final DateTime date;

  factory FinancialTransactionModel.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final dateValue = data['date'];
    final date = dateValue is Timestamp
        ? dateValue.toDate()
        : DateTime.tryParse(dateValue?.toString() ?? '') ?? DateTime.now();

    return FinancialTransactionModel(
      id: doc.id,
      userId: data['userId']?.toString() ?? '',
      type: data['type']?.toString() ?? 'expense',
      source: data['source']?.toString() ?? '',
      sourceRecordId: data['sourceRecordId']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      date: date,
    );
  }
}

class FinancialSummary {
  const FinancialSummary({
    required this.totalSpending,
    required this.totalSavings,
    required this.netDifference,
    required this.bySource,
  });

  /// Sum of every expense-only ledger entry (the only kind Gochano records).
  final double totalSpending;

  /// Legacy-compatible zero. Gochano no longer records savings; this field is
  /// retained so older callers/tests can still ask for it without crashing.
  final double totalSavings;

  /// Legacy-compatible alias for [totalSpending] (was: spending − savings).
  final double netDifference;

  final Map<String, double> bySource;

  factory FinancialSummary.fromTransactions(
    Iterable<FinancialTransactionModel> items,
  ) {
    var spending = 0.0;
    var savings = 0.0;
    final bySource = <String, double>{};

    for (final item in items) {
      // Gochano only writes `expense` rows today. Legacy `saving` rows may
      // still exist on older devices and are reflected only in `totalSavings`
      // — they never bleed into spending or `bySource`.
      if (item.type == 'expense') {
        spending += item.amount;
        bySource[item.source] = (bySource[item.source] ?? 0) + item.amount;
      } else if (item.type == 'saving') {
        savings += item.amount;
      }
    }
    return FinancialSummary(
      totalSpending: spending,
      totalSavings: savings,
      netDifference: savings - spending,
      bySource: bySource,
    );
  }
}
