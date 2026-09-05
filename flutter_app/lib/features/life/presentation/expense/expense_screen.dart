// Expense — the one financial module (spec §47).
//
// Overview / Daily / Grocery / History as tabs on a single screen, rather
// than "Daily Expenses" and "BazarBuddy" as two unrelated products in Life.
// Every tab reads the same `financial_transactions` ledger, so the number on
// Overview is always the sum of what the other tabs show.
//
// Budget lives on Overview rather than in its own tab: a budget with no
// spending next to it is not useful, and a fifth tab on a phone is one too
// many (spec §86).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../models/financial_transaction.dart';
import '../../../../services/api_service.dart';
import '../../../../services/financial_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../home/presentation/home_screen.dart' show formatTaka;
import '../../domain/expense_categories.dart';
import 'add_expense_sheet.dart';
import 'grocery_tab.dart';
import 'monthly_budget_sheet.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Expense', 'খরচ'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: GochanoLanguage.text('Overview', 'সারাংশ')),
            Tab(text: GochanoLanguage.text('Daily', 'দৈনিক')),
            Tab(text: GochanoLanguage.text('Grocery', 'বাজার')),
            Tab(text: GochanoLanguage.text('History', 'ইতিহাস')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _OverviewTab(),
          _DailyTab(),
          GroceryTab(),
          _HistoryTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final isGrocery = _tabs.index == 2;
          if (isGrocery) {
            final sessionId = FinancialService.bazarSessionId(DateTime.now());
            showGroceryItemSheet(context, sessionId: sessionId);
          } else {
            showAddExpenseSheet(context);
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(GochanoLanguage.text('Add expense', 'খরচ যোগ')),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview (spec §48)
// ---------------------------------------------------------------------------

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  late Future<Map<String, dynamic>> _budget;

  @override
  void initState() {
    super.initState();
    _budget = _loadBudget();
  }

  Future<Map<String, dynamic>> _loadBudget() =>
      ApiService.getRemaining(DateTime.now());

  void _reloadBudget() => setState(() => _budget = _loadBudget());

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();

    return StreamBuilder<List<FinancialTransactionModel>>(
      stream: FinancialService.monthStream(now),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading your spending…',
              'আপনার খরচ লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: friendlyErrorMessage(snapshot.error),
            onRetry: _reloadBudget,
          );
        }

        final items = snapshot.data ?? const <FinancialTransactionModel>[];
        final summary = FinancialSummary.fromTransactions(items);
        final todayKey = FinancialService.dateKey(now);
        final todayTotal = items
            .where((e) => FinancialService.dateKey(e.date) == todayKey)
            .fold<double>(0, (running, e) => running + e.amount);

        return ListView(
          padding: GochanoSpacing.scrollBody,
          children: [
            // Monthly available / spent / remaining — the three numbers a
            // student opens this screen for (spec §48).
            FutureBuilder<Map<String, dynamic>>(
              future: _budget,
              builder: (context, budgetSnap) {
                // "We could not read your budget" and "you have not set one"
                // are different facts. Collapsing them meant a failed request
                // rendered as "Not set" forever: a student would set the
                // amount, see "Not set" again, and reasonably conclude that
                // saving was broken.
                if (budgetSnap.hasError) {
                  return ErrorState(
                    compact: true,
                    message: friendlyErrorMessage(budgetSnap.error),
                    onRetry: _reloadBudget,
                  );
                }

                final available =
                    (budgetSnap.data?['available'] as num?)?.toDouble();
                final remaining =
                    (budgetSnap.data?['remaining'] as num?)?.toDouble();
                final hasBudget = available != null && available > 0;

                return Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _RemainingSummaryCard(
                              available: available,
                              remaining: remaining,
                              hasBudget: hasBudget,
                              onTap: () async {
                                final changed =
                                    await showMonthlyBudgetSheet(context);
                                if (changed) _reloadBudget();
                              },
                            ),
                          ),
                          const SizedBox(width: GochanoSpacing.sm),
                          Expanded(
                            child: StatCard(
                              compact: true,
                              label: GochanoLanguage.text('Spent', 'খরচ'),
                              value: formatTaka(summary.totalSpending),
                              accent: colors.expense,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!hasBudget) ...[
                      const SizedBox(height: GochanoSpacing.sm),
                      _SetBudgetPrompt(onSet: () async {
                        final changed = await showMonthlyBudgetSheet(context);
                        if (changed) _reloadBudget();
                      }),
                    ],
                  ],
                );
              },
            ),

            SectionHeader(
              title: GochanoLanguage.text('Today', 'আজ'),
            ),
            StatCard(
              label: GochanoLanguage.text('Spent today', 'আজকের খরচ'),
              value: formatTaka(todayTotal),
              caption: todayTotal == 0
                  ? GochanoLanguage.text(
                      'Nothing recorded yet today.',
                      'আজ এখনো কিছু যোগ করা হয়নি।',
                    )
                  : null,
            ),

            SectionHeader(
              title: GochanoLanguage.text('Where it went', 'কোথায় গেল'),
            ),
            _SourceBreakdown(summary: summary),

            SectionHeader(
              title: GochanoLanguage.text('Recent', 'সাম্প্রতিক'),
            ),
            if (items.isEmpty)
              EmptyState(
                compact: true,
                illustration: GochanoArt.emptyExpenses,
                title: GochanoLanguage.text('No expenses yet', 'এখনো কোনো খরচ নেই'),
                message: GochanoLanguage.text(
                  'Nothing has been recorded this month.',
                  'এই মাসে এখনো কিছু রেকর্ড করা হয়নি।',
                ),
              )
            else
              CardGroup(
                children: [
                  for (final item in items.take(6))
                    _LedgerRow(item: item),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Top summary card for Remaining — shows amount, progress bar, and usage text.
///
/// Reuses the same budget calculations as the former _RemainingCard.
class _RemainingSummaryCard extends StatelessWidget {
  const _RemainingSummaryCard({
    required this.available,
    required this.remaining,
    required this.hasBudget,
    this.onTap,
  });

  final double? available;
  final double? remaining;
  final bool hasBudget;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    if (!hasBudget || available == null) {
      return StatCard(
        compact: true,
        label: GochanoLanguage.text('Remaining', 'বাকি'),
        value: GochanoLanguage.text('Not set', 'সেট করা নেই'),
        onTap: onTap,
      );
    }

    final avail = available!;
    final rem = remaining ?? avail;
    final used = (avail - rem).clamp(0, avail);
    final fraction = avail <= 0 ? 0.0 : (used / avail).clamp(0.0, 1.0);
    final overspent = rem < 0;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  GochanoLanguage.text('Remaining', 'বাকি'),
                  style: type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (overspent)
                GochanoBadge(
                  label: GochanoLanguage.text('Over budget', 'বাজেট পেরিয়েছে'),
                  tone: GochanoBadgeTone.error,
                  icon: Icons.warning_amber_rounded,
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            formatTaka(rem),
            style: type.statistic.copyWith(
              color: overspent ? colors.error : colors.success,
            ),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              color: overspent ? colors.error : colors.expense,
            ),
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            GochanoLanguage.text(
              '${formatTaka(used.toDouble())} of ${formatTaka(avail)} used',
              '${formatTaka(avail)} এর মধ্যে ${formatTaka(used.toDouble())} খরচ',
            ),
            style: type.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SetBudgetPrompt extends StatelessWidget {
  const _SetBudgetPrompt({required this.onSet});

  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onSet,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  GochanoLanguage.text(
                    'Set your monthly money',
                    'মাসিক টাকা নির্ধারণ করুন',
                  ),
                  style: context.type.cardHeading,
                ),
                const SizedBox(height: 2),
                Text(
                  GochanoLanguage.text(
                    'Gochano can then show what is left after each expense.',
                    'তাহলে প্রতিটি খরচের পর কত বাকি তা দেখানো যাবে।',
                  ),
                  style: context.type.bodySecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Icon(Icons.chevron_right_rounded, color: context.colors.textTertiary),
        ],
      ),
    );
  }
}

/// Spending split by where it came from.
///
/// A labelled bar per source rather than a pie chart: on a phone, four
/// labelled rows are read faster than four slices and a legend (spec §48 —
/// "Use charts only if genuinely useful").
class _SourceBreakdown extends StatelessWidget {
  const _SourceBreakdown({required this.summary});

  final FinancialSummary summary;

  static const _order = ['daily', 'bazar', 'medicine', 'commute'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = summary.totalSpending;

    if (total <= 0) {
      return AppCard(
        child: Text(
          GochanoLanguage.text(
            'No spending recorded this month.',
            'এই মাসে কোনো খরচ রেকর্ড হয়নি।',
          ),
          style: context.type.bodySecondary,
        ),
      );
    }

    final rows = <Widget>[];
    for (final source in _order) {
      final amount = summary.bySource[source] ?? 0;
      if (amount <= 0) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_label(source), style: context.type.body),
                  ),
                  Text(
                    formatTaka(amount),
                    style: context.type.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (amount / total).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: colors.surfaceVariant,
                  color: _color(colors, source),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...rows,
          Row(
            children: [
              Expanded(
                child: Text(
                  GochanoLanguage.text('Total', 'মোট'),
                  style: context.type.cardHeading,
                ),
              ),
              Text(formatTaka(total), style: context.type.cardHeading),
            ],
          ),
        ],
      ),
    );
  }

  static String _label(String source) => switch (source) {
        'daily' => GochanoLanguage.text('Daily expenses', 'দৈনিক খরচ'),
        'bazar' => GochanoLanguage.text('Grocery', 'বাজার'),
        'medicine' => GochanoLanguage.text('Medicine', 'ওষুধ'),
        'commute' => GochanoLanguage.text('Commute', 'যাতায়াত'),
        _ => GochanoLanguage.text('Other', 'অন্যান্য'),
      };

  static Color _color(GochanoColors c, String source) => switch (source) {
        'daily' => c.expense,
        'bazar' => c.community,
        'medicine' => c.medicine,
        'commute' => c.commute,
        _ => c.textSecondary,
      };
}

// ---------------------------------------------------------------------------
// Daily (spec §50)
// ---------------------------------------------------------------------------

class _DailyTab extends StatelessWidget {
  const _DailyTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FinancialService.db
          .collection('daily_expenses')
          .where('ownerId', isEqualTo: FinancialService.uid)
          .where('dateKey', isEqualTo: FinancialService.dateKey(DateTime.now()))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              "Loading today's expenses…",
              'আজকের খরচ লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) {
            final at = a.data()['date'] as Timestamp?;
            final bt = b.data()['date'] as Timestamp?;
            if (at == null || bt == null) return 0;
            return bt.compareTo(at);
          });

        if (docs.isEmpty) {
          return EmptyState(
            illustration: GochanoArt.emptyExpenses,
            title: GochanoLanguage.text('No expenses today', 'আজ কোনো খরচ নেই'),
            message: GochanoLanguage.text(
              'Nothing has been recorded yet.',
              'এখনো কিছু রেকর্ড করা হয়নি।',
            ),
          );
        }

        final total = docs.fold<double>(
          0,
          (running, d) => running + ((d.data()['amount'] as num?)?.toDouble() ?? 0),
        );

        return ListView(
          padding: GochanoSpacing.scrollBody,
          children: [
            StatCard(
              label: GochanoLanguage.text('Spent today', 'আজকের খরচ'),
              value: formatTaka(total),
              accent: context.colors.expense,
            ),
            const SizedBox(height: GochanoSpacing.md),
            CardGroup(
              children: [
                for (final doc in docs) _DailyExpenseRow(doc: doc),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DailyExpenseRow extends StatelessWidget {
  const _DailyExpenseRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final category = ExpenseCategories.byId(data['category']?.toString());
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final title = data['title']?.toString() ?? category.id;
    final date = (data['date'] as Timestamp?)?.toDate();

    return GochanoListRow(
      illustration: category.illustration,
      accent: context.colors.expense,
      title: title,
      subtitle: category.label,
      metadata: [if (date != null) _clock(date)],
      trailing: Text(
        formatTaka(amount),
        style: context.type.cardHeading,
      ),
      onTap: () => showAddExpenseSheet(
        context,
        expenseId: doc.id,
        initialCategory: category.id,
        initialTitle: title,
        initialAmount: amount,
        initialDate: date,
      ),
      menuItems: [
        GochanoMenuAction(
          label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
          icon: Icons.edit_outlined,
          onSelected: () => showAddExpenseSheet(
            context,
            expenseId: doc.id,
            initialCategory: category.id,
            initialTitle: title,
            initialAmount: amount,
            initialDate: date,
          ),
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Delete', 'মুছুন'),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () async {
            final confirmed = await showConfirmationSheet(
              context,
              title: GochanoLanguage.text('Delete this expense?', 'খরচটি মুছবেন?'),
              message: GochanoLanguage.text(
                'It will be removed from your monthly total as well.',
                'এটি আপনার মাসিক মোট থেকেও বাদ যাবে।',
              ),
              confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
            );
            if (!confirmed || !context.mounted) return;
            try {
              await FinancialService.deleteDailyExpense(doc.id);
            } catch (error) {
              if (context.mounted) {
                showGochanoMessage(
                  context,
                  friendlyErrorMessage(error),
                  isError: true,
                );
              }
            }
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// History (spec §47)
// ---------------------------------------------------------------------------

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinancialTransactionModel>>(
      stream: FinancialService.allTransactionsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading your history…',
              'আপনার ইতিহাস লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        final items = snapshot.data ?? const <FinancialTransactionModel>[];
        if (items.isEmpty) {
          return EmptyState(
            illustration: GochanoArt.emptyExpenses,
            title: GochanoLanguage.text('No history yet', 'এখনো কোনো ইতিহাস নেই'),
            message: GochanoLanguage.text(
              'Expenses you record will be listed here by day.',
              'আপনার রেকর্ড করা খরচ এখানে দিন অনুযায়ী দেখা যাবে।',
            ),
          );
        }

        // Group by day so the list reads as a diary rather than a flat dump.
        final byDay = <String, List<FinancialTransactionModel>>{};
        for (final item in items) {
          byDay.putIfAbsent(FinancialService.dateKey(item.date), () => []).add(item);
        }
        final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

        return ListView.builder(
          padding: GochanoSpacing.scrollBody,
          itemCount: days.length,
          itemBuilder: (context, i) {
            final day = days[i];
            final entries = byDay[day]!;
            final total = entries.fold<double>(0, (running, e) => running + e.amount);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: _dayLabel(entries.first.date),
                  action: Text(
                    formatTaka(total),
                    style: context.type.cardHeading,
                  ),
                  padding: const EdgeInsets.only(
                    top: GochanoSpacing.md,
                    bottom: GochanoSpacing.xs,
                  ),
                ),
                CardGroup(
                  children: [for (final e in entries) _LedgerRow(item: e)],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A read-only ledger entry, used by Overview and History.
///
/// Entries mirrored from grocery, medicine and commute are shown but not
/// editable here: the truth lives in the source record, and editing it from
/// two places is how a ledger drifts (spec §36).
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item});

  final FinancialTransactionModel item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (illustration, accent, sourceLabel) = switch (item.source) {
      'bazar' => (
          GochanoArt.featureGrocery,
          colors.community,
          GochanoLanguage.text('Grocery', 'বাজার'),
        ),
      'medicine' => (
          GochanoArt.featureMedicine,
          colors.medicine,
          GochanoLanguage.text('Medicine', 'ওষুধ'),
        ),
      'commute' => (
          GochanoArt.featureCommute,
          colors.commute,
          GochanoLanguage.text('Commute', 'যাতায়াত'),
        ),
      _ => (
          ExpenseCategories.byId(item.category).illustration,
          colors.expense,
          ExpenseCategories.byId(item.category).label,
        ),
    };

    return GochanoListRow(
      illustration: illustration,
      accent: accent,
      title: item.title.isEmpty ? sourceLabel : item.title,
      subtitle: sourceLabel,
      metadata: [_clock(item.date)],
      trailing: Text(formatTaka(item.amount), style: context.type.cardHeading),
    );
  }
}

String _clock(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${when.hour < 12 ? 'am' : 'pm'}';
}

String _dayLabel(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return GochanoLanguage.text('Today', 'আজ');
  if (diff == 1) return GochanoLanguage.text('Yesterday', 'গতকাল');

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
