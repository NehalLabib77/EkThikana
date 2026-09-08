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
    required this.bySource,
  });

  /// Sum of every expense-only ledger entry (the only kind Gochano records).
  final double totalSpending;

  final Map<String, double> bySource;

  factory FinancialSummary.fromTransactions(
    Iterable<FinancialTransactionModel> items,
  ) {
    var spending = 0.0;
    final bySource = <String, double>{};

    for (final item in items) {
      // Gochano only writes `expense` rows. Anything else (legacy `saving`
      // rows on older devices) is intentionally excluded from spending and
      // from the per-source breakdown.
      if (item.type == 'expense') {
        spending += item.amount;
        bySource[item.source] = (bySource[item.source] ?? 0) + item.amount;
      }
    }
    return FinancialSummary(
      totalSpending: spending,
      bySource: bySource,
    );
  }
}
