// Daily expense categories (spec §50).
//
// The English string in [id] is the value stored on every `daily_expenses`
// document and mirrored onto the `financial_transactions` ledger. It is a
// **stored identifier**, not a label: changing one would orphan every
// historical expense filed under the old value. Spec §50 is explicit —
// "Do not change stored identifiers without migration" — so the ids below are
// byte-identical to what the previous Daily Expenses screen wrote.
//
// The Bangla name and the illustration are presentation only and are safe to
// change.

import '../../../core/design_system/gochano_art.dart';
import '../../../core/localization/gochano_language.dart';

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.bangla,
    required this.illustration,
  });

  /// The stored value. Never change these.
  final String id;

  final String bangla;

  /// Id from `GochanoArt`.
  final String illustration;

  /// The category name in the active language.
  String get label => GochanoLanguage.text(id, bangla);
}

abstract final class ExpenseCategories {
  static const List<ExpenseCategory> all = [
    ExpenseCategory(
      id: 'Breakfast / Nasta',
      bangla: 'নাশতা',
      illustration: GochanoArt.featureGrocery,
    ),
    ExpenseCategory(
      id: 'Lunch',
      bangla: 'দুপুরের খাবার',
      illustration: GochanoArt.featureExpense,
    ),
    ExpenseCategory(
      id: 'Snacks',
      bangla: 'স্ন্যাকস',
      illustration: GochanoArt.featureGrocery,
    ),
    ExpenseCategory(
      id: 'Dinner',
      bangla: 'রাতের খাবার',
      illustration: GochanoArt.featureExpense,
    ),
    ExpenseCategory(
      id: 'Other',
      bangla: 'অন্যান্য',
      illustration: GochanoArt.fileGeneric,
    ),
  ];

  static ExpenseCategory get fallback => all.last;

  /// Resolves a stored category id back to its definition.
  ///
  /// An unrecognised value — from an older build, or a category that was once
  /// available — resolves to "Other" rather than throwing, so a historical
  /// expense always renders.
  static ExpenseCategory byId(String? id) {
    for (final category in all) {
      if (category.id == id) return category;
    }
    return fallback;
  }

  /// The Bangla name for a stored id, for screens that only need the label.
  static String labelFor(String? id) => byId(id).label;
}
