// Expense — the one financial module (spec §47).
//
// Daily / Grocery / Dena-Pawna / Overview as tabs on a single screen, rather
// than "Daily Expenses" and "BazarBuddy" as two unrelated products in Life.
// Every tab reads the same `financial_transactions` ledger, so the number on
// Overview is always the sum of what the other tabs show.
//
// Budget lives on Overview rather than in its own tab: a budget with no
// spending next to it is not useful, and a fifth tab on a phone is one too
// many (spec §86).
//
// Historical data is NOT deleted when the History tab is removed — it remains
// accessible through the Overview tab's Recent section and all financial
// calculations (monthStream, dayStream, etc.) continue to include it.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/financial_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../home/presentation/home_screen.dart' show formatTaka;
import '../../domain/expense_categories.dart';
import 'add_expense_sheet.dart';
import 'dena_pawna_tab.dart';
import 'grocery_tab.dart';
import 'overview_tab.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _overviewKey = GlobalKey<OverviewTabState>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabs.index == 3) {
      _overviewKey.currentState?.refresh();
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onExpenseAdded() {
    _overviewKey.currentState?.refresh();
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
            Tab(text: GochanoLanguage.text('Daily', 'দৈনিক')),
            Tab(text: GochanoLanguage.text('Grocery', 'বাজার')),
            Tab(text: GochanoLanguage.text('Dena/Pawna', 'দেনা/পাওনা')),
            Tab(text: GochanoLanguage.text('Overview', 'সারাংশ')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _DailyTab(),
          const GroceryTab(),
          const DenaPawnaTab(),
          OverviewTab(key: _overviewKey),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final isGrocery = _tabs.index == 1;
          if (isGrocery) {
            final sessionId = FinancialService.bazarSessionId(DateTime.now());
            final saved = await showGroceryItemSheet(
              context,
              sessionId: sessionId,
            );
            if (saved) _onExpenseAdded();
          } else {
            final saved = await showAddExpenseSheet(context);
            if (saved) _onExpenseAdded();
          }
        },
        icon: const Icon(Icons.receipt_long_rounded),
        label: Text(GochanoLanguage.text('Add expense', 'খরচ যোগ')),
      ),
    );
  }
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

String _clock(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${when.hour < 12 ? 'am' : 'pm'}';
}
