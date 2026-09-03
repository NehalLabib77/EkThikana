// Life — Expense, Medicine, CommuteBD (spec §46).
//
// Three modules, not four. "Daily Expenses" and "BazarBuddy" used to sit here
// as unrelated top-level products, which meant a student had two different
// places to look for "how much did I spend" and no place that answered it.
// Grocery is now a section *inside* Expense (spec §47), so there is exactly
// one financial module and one total.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../models/financial_transaction.dart';
import '../../../services/api_service.dart';
import '../../../services/financial_service.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import '../../home/presentation/home_screen.dart' show formatTaka;
import 'commute/commute_screen.dart';
import 'expense/expense_screen.dart';
import 'medicine/medicine_screen.dart';

class LifeScreen extends StatelessWidget {
  const LifeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Life', 'জীবন'),
        subtitle: GochanoLanguage.text(
          'Money, medicine and getting around',
          'টাকা, ওষুধ ও যাতায়াত',
        ),
        automaticallyImplyLeading: false,
        actions: const [LanguageToggle(), SizedBox(width: GochanoSpacing.xs)],
      ),
      body: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          const _MonthSummary(),
          const SizedBox(height: GochanoSpacing.md),
          _ModuleCard(
            title: GochanoLanguage.text('Expense', 'খরচ'),
            description: GochanoLanguage.text(
              'Daily spending, grocery, budget and history',
              'দৈনিক খরচ, বাজার, বাজেট ও ইতিহাস',
            ),
            illustration: GochanoArt.featureExpense,
            accent: colors.expense,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const ExpenseScreen()),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          _ModuleCard(
            title: GochanoLanguage.text('Medicine', 'ওষুধ'),
            description: GochanoLanguage.text(
              'Reminders, doses taken and prescription scanning',
              'রিমাইন্ডার, ডোজ ও প্রেসক্রিপশন স্ক্যান',
            ),
            illustration: GochanoArt.featureMedicine,
            accent: colors.medicine,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const MedicineScreen()),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          _ModuleCard(
            title: 'CommuteBD',
            description: GochanoLanguage.text(
              'Routes and fares across Bangladesh',
              'বাংলাদেশ জুড়ে রুট ও ভাড়া',
            ),
            illustration: GochanoArt.featureCommute,
            accent: colors.commute,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const CommuteScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// This month's remaining and spent, read from the same central ledger as
/// everywhere else. Shown side-by-side so the student sees both numbers
/// at a glance without opening Expense.
class _MonthSummary extends StatefulWidget {
  const _MonthSummary();

  @override
  State<_MonthSummary> createState() => _MonthSummaryState();
}

class _MonthSummaryState extends State<_MonthSummary> {
  late Future<Map<String, dynamic>> _budget;

  @override
  void initState() {
    super.initState();
    _budget = ApiService.getRemaining(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<List<FinancialTransactionModel>>(
      stream: FinancialService.monthStream(DateTime.now()),
      builder: (context, snapshot) {
        final summary = FinancialSummary.fromTransactions(
          snapshot.data ?? const <FinancialTransactionModel>[],
        );
        final spent = summary.totalSpending;

        return FutureBuilder<Map<String, dynamic>>(
          future: _budget,
          builder: (context, budgetSnap) {
            final available =
                (budgetSnap.data?['available'] as num?)?.toDouble();
            final remaining =
                (budgetSnap.data?['remaining'] as num?)?.toDouble();
            final hasBudget = available != null && available > 0;
            final avail = hasBudget ? available : 0.0;
            final rem = hasBudget ? (remaining ?? avail) : null;
            final overspent = rem != null && rem < 0;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AppCard(
                      padding: const EdgeInsets.all(GochanoSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            GochanoLanguage.text('Remaining', 'বাকি'),
                            style: context.type.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: GochanoSpacing.xxs),
                          Text(
                            rem != null ? formatTaka(rem) : '—',
                            style: context.type.statistic.copyWith(
                              color: overspent
                                  ? colors.error
                                  : hasBudget
                                      ? colors.success
                                      : colors.textTertiary,
                            ),
                          ),
                          if (hasBudget) ...[
                            const SizedBox(height: GochanoSpacing.xs),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: avail <= 0
                                    ? 0.0
                                    : ((avail - (rem ?? 0)) / avail)
                                        .clamp(0.0, 1.0),
                                minHeight: 5,
                                backgroundColor: colors.surfaceVariant,
                                color: overspent
                                    ? colors.error
                                    : colors.expense,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: StatCard(
                      label: GochanoLanguage.text('Spent', 'খরচ'),
                      value: formatTaka(spent),
                      accent: colors.expense,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.description,
    required this.illustration,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String description;
  final String illustration;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: accent,
      onTap: onTap,
      semanticLabel: '$title. $description',
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Row(
        children: [
          GochanoIllustration(illustration, size: 44, accent: accent),
          const SizedBox(width: GochanoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: context.type.sectionHeading),
                const SizedBox(height: 2),
                Text(description, style: context.type.bodySecondary),
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Icon(
            Icons.chevron_right_rounded,
            color: context.colors.textTertiary,
          ),
        ],
      ),
    );
  }
}
