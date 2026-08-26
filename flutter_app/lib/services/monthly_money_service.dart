import '../models/financial_transaction.dart';
import 'api_service.dart';
import 'firestore_service.dart';

/// PART 3 — Monthly Money.
///
/// Per correction 6 this reads the central `financial_transactions` ledger.
/// `status == 'confirmed'` is the only kind counted. Estimated/draft entries
/// never bleed into [remaining].
class MonthlyMoneyService {
  MonthlyMoneyService._();

  /// Streams confirmed transactions for the given month, sourced from the
  /// central ledger. Existing UI consumers continue to use
  /// `FinancialService.monthStream`; this wraps the same collection.
  static Stream<List<FinancialTransactionModel>> monthStream(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final next = DateTime(month.year, month.month + 1, 1);
    return FirestoreService.db
        .collection('financial_transactions')
        .where('ownerId', isEqualTo: FirestoreService.uid)
        .where('type', isEqualTo: 'expense')
        .where('status', isEqualTo: 'confirmed')
        .where('date', isGreaterThanOrEqualTo: first)
        .where('date', isLessThan: next)
        .snapshots()
        .map((snap) => snap.docs
            .map(FinancialTransactionModel.fromDoc)
            .toList(growable: false));
  }

  static Future<double> remaining(DateTime month) async {
    final budget = await getBudget(month);
    final tx = await monthStream(month).first;
    final summary = FinancialSummary.fromTransactions(tx);
    return (budget - summary.totalSpending).clamp(double.negativeInfinity, double.infinity);
  }

  static Future<double> getBudget(DateTime month) async {
    try {
      final resp = await ApiService.getMonthlyBudget(month);
      final raw = resp['availableAmount'] ?? resp['available_amount'];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? 0;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<double> setBudget(DateTime month, double amount) async {
    final resp = await ApiService.setMonthlyBudget(month, amount);
    final raw = resp['availableAmount'] ?? resp['available_amount'];
    if (raw is num) return raw.toDouble();
    return amount;
  }
}
