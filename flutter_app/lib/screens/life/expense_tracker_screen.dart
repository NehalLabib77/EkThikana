import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../models/financial_transaction.dart';
import '../../services/financial_service.dart';

/// Daily-expense category taxonomy (must match
/// `DailyExpensesScreen.categories` so the tracker breakdown is consistent
/// with what the Add sheet writes).
const List<(String en, String bn, String emoji, Color tint)> _kDailyCategories =
    [
  ('Breakfast / Nasta', 'নাশতা', '🍳', Color(0xFFFFF3D9)),
  ('Lunch', 'দুপুরের খাবার', '🍛', Color(0xFFEAF7E6)),
  ('Snacks', 'স্ন্যাকস', '🍪', Color(0xFFF3E9FF)),
  ('Dinner', 'রাতের খাবার', '🍲', Color(0xFFFFEAE5)),
  ('Other', 'অন্যান্য', '🧺', Color(0xFFE8F4FF)),
];

class ExpenseTrackerScreen extends StatefulWidget {
  const ExpenseTrackerScreen({super.key, this.initialMonth});

  final DateTime? initialMonth;

  @override
  State<ExpenseTrackerScreen> createState() => _ExpenseTrackerScreenState();
}

class _ExpenseTrackerScreenState extends State<ExpenseTrackerScreen> {
  late DateTime selectedMonth;
  late DateTime selectedDate;
  bool showCalendar = true;

  @override
  void initState() {
    super.initState();
    final start = widget.initialMonth ?? DateTime.now();
    selectedMonth = DateTime(start.year, start.month);
    selectedDate = start;
  }

  void moveMonth(int delta) {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + delta);
      selectedDate = DateTime(selectedMonth.year, selectedMonth.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(EkLanguage.text('Expense Tracker', 'খরচ ট্র্যাকার')),
              Text(
                EkLanguage.text(
                  'Your spending history in one place',
                  'আপনার সব খরচের ইতিহাস এক জায়গায়',
                ),
                style: const TextStyle(fontSize: 11, color: EkColors.muted),
              ),
            ],
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: LanguageToggle(),
            ),
          ],
        ),
        body: StreamBuilder<List<FinancialTransactionModel>>(
          stream: FinancialService.allTransactionsStream(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Single-pass partition: avoid walking the expense list three
            // times (`.where('expense')`, then `.where(year/month)`, then
            // `.where(year/month/day)`). With the 2000-doc snapshot cap this
            // keeps the build path linear and gives downstream widgets
            // (`_sourceBreakdown`, `_categoryBreakdown`, `_calendar`,
            // `_dayTransactions`) lists they can iterate once.
            final raw = snap.data!;
            final all = <FinancialTransactionModel>[];
            final monthItems = <FinancialTransactionModel>[];
            final dayItems = <FinancialTransactionModel>[];
            for (final e in raw) {
              if (e.type != 'expense') continue;
              all.add(e);
              if (e.date.year == selectedMonth.year &&
                  e.date.month == selectedMonth.month) {
                monthItems.add(e);
                if (e.date.year == selectedDate.year &&
                    e.date.month == selectedDate.month &&
                    e.date.day == selectedDate.day) {
                  dayItems.add(e);
                }
              }
            }
            final summary = FinancialService.summary(monthItems);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                _monthSelector(),
                const SizedBox(height: 14),
                _summaryCard(summary),
                const SizedBox(height: 14),
                _sourceBreakdown(monthItems, summary),
                const SizedBox(height: 14),
                _categoryBreakdown(monthItems),
                const SizedBox(height: 14),
                _calendar(monthItems),
                const SizedBox(height: 14),
                _dayTransactions(dayItems),
                const SizedBox(height: 14),
                _yearHistory(all),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _monthSelector() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => moveMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy').format(selectedMonth),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () => moveMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _summaryCard(FinancialSummary summary) {
  return Builder(
    builder: (context) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final gradient = dark
          ? const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF1E293B)],
            )
          : const LinearGradient(
              colors: [Color(0xFFF3FCEB), Color(0xFFFFF9E6)],
            );
      final border = dark
          ? const Color(0xFF334155)
          : const Color(0xFFDCECCB);
      final totalColor = dark
          ? const Color(0xFFFF8A6E)
          : const Color(0xFFD85A3A);
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            const Text('💰', style: TextStyle(fontSize: 42)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    EkLanguage.text('Total Spending', 'মোট খরচ'),
                    style: const TextStyle(fontSize: 13, color: EkColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '৳${summary.totalSpending.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: totalColor,
                    ),
                  ),
                  Text(
                    DateFormat('MMMM yyyy').format(selectedMonth),
                    style: const TextStyle(fontSize: 11, color: EkColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

  Widget _sourceBreakdown(
    List<FinancialTransactionModel> monthItems,
    FinancialSummary summary,
  ) {
    const sources = [
      ('daily', 'Daily Expenses', 'দৈনিক খরচ', '🍽️', Color(0xFFFFF3D9)),
      ('bazar', 'BazarBuddy', 'বাজারবাডি', '🛒', Color(0xFFEAF7E6)),
      ('medicine', 'Medicine', 'ওষুধ', '💊', Color(0xFFE7F7F3)),
      ('commute', 'CommuteBD', 'যাতায়াত', '🚌', Color(0xFFE8F1FF)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              EkLanguage.text('Monthly Breakdown', 'মাসিক খরচের হিসাব'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final source in sources) ...[
              InkWell(
                onTap: () => _showSourceDetails(
                  EkLanguage.text(source.$2, source.$3),
                  monthItems.where((e) => e.source == source.$1).toList(),
                ),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: source.$5,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Text(source.$4, style: const TextStyle(fontSize: 23)),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          EkLanguage.text(source.$2, source.$3),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '৳${(summary.bySource[source.$1] ?? 0).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 19, color: EkColors.muted),
                    ],
                  ),
                ),
              ),
              if (source != sources.last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryBreakdown(List<FinancialTransactionModel> monthItems) {
    // Aggregate only `source == 'daily'` rows — those are the ones that
    // carry a category from the Add sheet. Other sources (bazar / medicine /
    // commute) are already grouped by `_sourceBreakdown` above.
    final daily = monthItems.where((e) => e.source == 'daily');
    final totals = <String, double>{
      for (final c in _kDailyCategories) c.$1: 0.0,
    };
    for (final item in daily) {
      final key = totals.containsKey(item.category) ? item.category : 'Other';
      totals[key] = (totals[key] ?? 0) + item.amount;
    }
    final maxValue = totals.values.fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              EkLanguage.text('Category Breakdown', 'ক্যাটাগরি অনুযায়ী খরচ'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              EkLanguage.text(
                'Daily expense categories only',
                'শুধু দৈনিক খরচের ক্যাটাগরি',
              ),
              style: const TextStyle(fontSize: 11, color: EkColors.muted),
            ),
            const SizedBox(height: 10),
            for (final c in _kDailyCategories) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.$4,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(c.$3, style: const TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EkLanguage.text(c.$1, c.$2),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final dark =
                                  Theme.of(context).brightness == Brightness.dark;
                              // In dark mode the tint itself is a soft pastel;
                              // using it as a track would wash out. We blend
                              // it with the card surface so the bar is
                              // visible against the dark card.
                              final track = dark
                                  ? c.$4.withValues(alpha: 0.22)
                                  : c.$4.withValues(alpha: 0.45);
                              final fill = dark
                                  ? c.$4.withValues(alpha: 0.85)
                                  : c.$4;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: maxValue == 0
                                      ? 0
                                      : totals[c.$1]! / maxValue,
                                  minHeight: 6,
                                  backgroundColor: track,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(fill),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 11),
                    Text(
                      '৳${totals[c.$1]!.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (c != _kDailyCategories.last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _calendar(List<FinancialTransactionModel> monthItems) {
    final activeDays = monthItems.map((e) => e.date.day).toSet();
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
              EkLanguage.text('Calendar', 'ক্যালেন্ডার'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              EkLanguage.text(
                'Choose a day to inspect spending',
                'এক দিনের খরচ দেখতে দিন নির্বাচন করুন',
              ),
            ),
            trailing: IconButton(
              tooltip: showCalendar ? 'Hide calendar' : 'Show calendar',
              onPressed: () => setState(() => showCalendar = !showCalendar),
              icon: Icon(showCalendar ? Icons.expand_less : Icons.expand_more),
            ),
          ),
          if (showCalendar)
            CalendarDatePicker(
              initialDate: selectedDate.month == selectedMonth.month
                  ? selectedDate
                  : DateTime(selectedMonth.year, selectedMonth.month, 1),
              firstDate: DateTime(selectedMonth.year, selectedMonth.month, 1),
              lastDate: DateTime(selectedMonth.year, selectedMonth.month + 1, 0),
              onDateChanged: (date) => setState(() => selectedDate = date),
            ),
          if (activeDays.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                EkLanguage.text(
                  'Logged spending days: ${activeDays.toList()..sort()}',
                  'খরচ রেকর্ড আছে: ${activeDays.toList()..sort()}',
                ),
                style: const TextStyle(fontSize: 11, color: EkColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayTransactions(List<FinancialTransactionModel> items) {
    final spending = items.fold<double>(0, (sum, item) => sum + item.amount);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('d MMMM').format(selectedDate),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    EkLanguage.text(
                      'No spending recorded on this date.',
                      'এই তারিখে কোনো খরচ রেকর্ড নেই।',
                    ),
                  ),
                ),
              )
            else
              for (final item in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _sourceColor(item.source),
                    child: Text(_sourceEmoji(item.source)),
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    '${_sourceLabel(item.source)} • ${DateFormat('h:mm a').format(item.date)}',
                  ),
                  trailing: Text(
                    '৳${item.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFD45A3A),
                    ),
                  ),
                ),
            if (items.isNotEmpty) ...[
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${EkLanguage.text('Total', 'মোট')}: ৳${spending.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _yearHistory(List<FinancialTransactionModel> all) {
    final year = selectedMonth.year;
    final monthTotals = <int, double>{};
    for (final item in all) {
      if (item.date.year != year || item.type != 'expense') continue;
      monthTotals[item.date.month] = (monthTotals[item.date.month] ?? 0) + item.amount;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${EkLanguage.text('Monthly History', 'মাসিক ইতিহাস')} • $year',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (var month = 1; month <= 12; month++)
              if (monthTotals.containsKey(month))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat('MMMM').format(DateTime(year, month))),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '৳${monthTotals[month]!.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => setState(() {
                    selectedMonth = DateTime(year, month);
                    selectedDate = DateTime(year, month, 1);
                  }),
                ),
            if (monthTotals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    EkLanguage.text(
                      'No spending history for $year.',
                      '$year সালের কোনো খরচের ইতিহাস নেই।',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSourceDetails(
    String source,
    List<FinancialTransactionModel> items,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * .7,
        child: Column(
          children: [
            ListTile(
              title: Text(source, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(DateFormat('MMMM yyyy').format(selectedMonth)),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(EkLanguage.text('No expenses.', 'কোনো খরচ নেই।')))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return ListTile(
                          title: Text(item.title),
                          subtitle: Text(DateFormat('dd MMM, h:mm a').format(item.date)),
                          trailing: Text(
                            '৳${item.amount.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'daily':
        return EkLanguage.text('Daily', 'দৈনিক');
      case 'bazar':
        return 'BazarBuddy';
      case 'medicine':
        return EkLanguage.text('Medicine', 'ওষুধ');
      case 'commute':
        return 'CommuteBD';
      default:
        return source;
    }
  }

  String _sourceEmoji(String source) {
    switch (source) {
      case 'daily':
        return '🍽️';
      case 'bazar':
        return '🛒';
      case 'medicine':
        return '💊';
      case 'commute':
        return '🚌';
      default:
        return '•';
    }
  }

  Color _sourceColor(String source) {
    switch (source) {
      case 'daily':
        return const Color(0xFFFFF3D9);
      case 'bazar':
        return const Color(0xFFEAF7E6);
      case 'medicine':
        return const Color(0xFFE7F7F3);
      case 'commute':
        return const Color(0xFFE8F1FF);
      default:
        return const Color(0xFFF2F2F2);
    }
  }
}
