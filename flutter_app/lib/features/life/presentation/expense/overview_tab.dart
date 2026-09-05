// Overview — Monthly Financial Dashboard (Part 5 redesign).
//
// Replaces the former simple Remaining/Spent overview with a full monthly
// financial dashboard: month selector, summary cards, daily bar chart,
// and day-by-day breakdown. All data comes from real Firestore transactions.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../models/financial_transaction.dart';
import '../../../../services/api_service.dart';
import '../../../../services/financial_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../home/presentation/home_screen.dart' show formatTaka;
import '../../domain/expense_categories.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});

  @override
  State<OverviewTab> createState() => OverviewTabState();
}

class OverviewTabState extends State<OverviewTab> {
  DateTime _selectedMonth = DateTime.now();
  int? _selectedDay;
  bool _dayExpanded = false;
  int _budgetRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _selectedDay = now.day;
  }

  /// Called by the parent ExpenseScreen when the user switches to this tab
  /// or after an expense is added. Forces a full re-fetch of budget data.
  void refresh() {
    if (mounted) setState(() => _budgetRefreshKey++);
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      _selectedDay = null;
      _dayExpanded = false;
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final nextCandidate = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (nextCandidate.isAfter(DateTime(now.year, now.month))) return;
    setState(() {
      _selectedMonth = nextCandidate;
      _selectedDay = null;
      _dayExpanded = false;
    });
  }

  bool get _canGoNext {
    final now = DateTime.now();
    final nextCandidate = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    return !nextCandidate.isAfter(DateTime(now.year, now.month));
  }

  bool get _canGoPrev => true;

  void _onDaySelected(int day) {
    setState(() {
      if (_selectedDay == day) {
        _selectedDay = null;
        _dayExpanded = false;
      } else {
        _selectedDay = day;
        _dayExpanded = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = getDaysInMonth(_selectedMonth);
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return StreamBuilder<List<FinancialTransactionModel>>(
      stream: FinancialService.monthStream(_selectedMonth),
      builder: (context, txSnap) {
        if (txSnap.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading spending data…',
              'খরচের তথ্য লোড হচ্ছে…',
            ),
          );
        }
        if (txSnap.hasError) {
          return ErrorState(
            message: friendlyErrorMessage(txSnap.error),
            onRetry: () => setState(() {}),
          );
        }

        final items = txSnap.data ?? const <FinancialTransactionModel>[];
        final summary = FinancialSummary.fromTransactions(items);

        // Daily totals: day -> amount
        final dailyTotals = <int, double>{};
        for (final item in items) {
          final day = item.date.day;
          if (item.date.month == _selectedMonth.month &&
              item.date.year == _selectedMonth.year) {
            dailyTotals[day] = (dailyTotals[day] ?? 0) + item.amount;
          }
        }

        // Source breakdown
        final sourceTotals = <String, double>{};
        for (final item in items) {
          sourceTotals[item.source] = (sourceTotals[item.source] ?? 0) + item.amount;
        }

        // Today's total (only when viewing current month)
        final todayKey = FinancialService.dateKey(now);
        final todayTotal = items
            .where((e) => FinancialService.dateKey(e.date) == todayKey)
            .fold<double>(0, (running, e) => running + e.amount);

        // Dena/Pawna settlement totals for the selected month
        return StreamBuilder<Map<String, double>>(
          stream: FinancialService.denaPawnaSettlementTotalsStream(
            _selectedMonth,
          ),
          builder: (context, settlementSnap) {
            final settlements = settlementSnap.data ??
                const {'pawnaReceived': 0, 'denaPaid': 0};
            final pawnaReceived = settlements['pawnaReceived'] ?? 0;
            final denaPaid = settlements['denaPaid'] ?? 0;

            // Budget for the selected month — keyed to force re-fetch on refresh()
            return FutureBuilder<Map<String, dynamic>>(
              key: ValueKey('budget-${_selectedMonth.year}-${_selectedMonth.month}-$_budgetRefreshKey'),
              future: ApiService.getRemaining(_selectedMonth),
              builder: (context, budgetSnap) {
                final available =
                    (budgetSnap.data?['available'] as num?)?.toDouble();
                final backendRemaining =
                    (budgetSnap.data?['remaining'] as num?)?.toDouble();
                final hasBudget = available != null && available > 0;
                final adjustedRemaining =
                    (backendRemaining ?? (available ?? 0)) +
                        pawnaReceived -
                        denaPaid;

                // Category breakdown
                final groceryTotal = sourceTotals['bazar'] ?? 0;
                final medicineTotal = sourceTotals['medicine'] ?? 0;
                final dailyTotal = sourceTotals['daily'] ?? 0;
                final commuteTotal = sourceTotals['commute'] ?? 0;

                // Net cash change (only from actual settlements this month)
                final netCashChange = pawnaReceived - denaPaid;

                return _OverviewBody(
                  selectedMonth: _selectedMonth,
                  daysInMonth: daysInMonth,
                  isCurrentMonth: isCurrentMonth,
                  selectedDay: _selectedDay,
                  dayExpanded: _dayExpanded,
                  summary: summary,
                  dailyTotals: dailyTotals,
                  sourceTotals: sourceTotals,
                  todayTotal: todayTotal,
                  todayKey: todayKey,
                  hasBudget: hasBudget,
                  monthlyMoney: available,
                  adjustedRemaining: adjustedRemaining,
                  totalSpent: summary.totalSpending,
                  moneyIn: pawnaReceived,
                  groceryTotal: groceryTotal,
                  medicineTotal: medicineTotal,
                  dailyExpenseTotal: dailyTotal,
                  commuteTotal: commuteTotal,
                  denaPaid: denaPaid,
                  pawnaReceived: pawnaReceived,
                  netCashChange: netCashChange,
                  items: items,
                  onPrevMonth: _canGoPrev ? _prevMonth : null,
                  onNextMonth: _canGoNext ? _nextMonth : null,
                  onDaySelected: _onDaySelected,
                  onDayExpanded: () => setState(() => _dayExpanded = !_dayExpanded),
                  onSetBudget: refresh,
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns the actual number of days in [month].
int getDaysInMonth(DateTime month) =>
    DateTime(month.year, month.month + 1, 0).day;

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({
    required this.selectedMonth,
    required this.daysInMonth,
    required this.isCurrentMonth,
    required this.selectedDay,
    required this.dayExpanded,
    required this.summary,
    required this.dailyTotals,
    required this.sourceTotals,
    required this.todayTotal,
    required this.todayKey,
    required this.hasBudget,
    required this.monthlyMoney,
    required this.adjustedRemaining,
    required this.totalSpent,
    required this.moneyIn,
    required this.groceryTotal,
    required this.medicineTotal,
    required this.dailyExpenseTotal,
    required this.commuteTotal,
    required this.denaPaid,
    required this.pawnaReceived,
    required this.netCashChange,
    required this.items,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDaySelected,
    required this.onDayExpanded,
    required this.onSetBudget,
  });

  final DateTime selectedMonth;
  final int daysInMonth;
  final bool isCurrentMonth;
  final int? selectedDay;
  final bool dayExpanded;
  final FinancialSummary summary;
  final Map<int, double> dailyTotals;
  final Map<String, double> sourceTotals;
  final double todayTotal;
  final String todayKey;
  final bool hasBudget;
  final double? monthlyMoney;
  final double adjustedRemaining;
  final double totalSpent;
  final double moneyIn;
  final double groceryTotal;
  final double medicineTotal;
  final double dailyExpenseTotal;
  final double commuteTotal;
  final double denaPaid;
  final double pawnaReceived;
  final double netCashChange;
  final List<FinancialTransactionModel> items;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;
  final ValueChanged<int> onDaySelected;
  final VoidCallback onDayExpanded;
  final VoidCallback onSetBudget;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        // A. Month Selector
        _MonthSelector(
          month: selectedMonth,
          onPrev: onPrevMonth,
          onNext: onNextMonth,
        ),

        // B. Monthly Summary Cards
        SectionHeader(
          title: GochanoLanguage.text('Monthly summary', 'মাসিক সারাংশ'),
        ),
        _SummaryGrid(
          monthlyMoney: monthlyMoney,
          hasBudget: hasBudget,
          totalSpent: totalSpent,
          moneyIn: moneyIn,
          adjustedRemaining: adjustedRemaining,
          dailyExpenseTotal: dailyExpenseTotal,
          groceryTotal: groceryTotal,
          medicineTotal: medicineTotal,
          denaPaid: denaPaid,
          pawnaReceived: pawnaReceived,
        ),

        // Set budget prompt if not set
        if (!hasBudget) ...[
          const SizedBox(height: GochanoSpacing.sm),
          _SetBudgetPrompt(onSet: onSetBudget),
        ],

        // Outflow / Inflow
        SectionHeader(
          title: GochanoLanguage.text('Cash flow', 'ক্যাশ ফ্লো'),
        ),
        _CashFlowCard(
          outflow: totalSpent + denaPaid,
          inflow: pawnaReceived,
          remaining: adjustedRemaining,
        ),

        // C. Daily Spending Bar Chart
        SectionHeader(
          title: GochanoLanguage.text('Daily spending', 'দৈনিক খরচ'),
        ),
        _DailyBarChart(
          dailyTotals: dailyTotals,
          daysInMonth: daysInMonth,
          selectedMonth: selectedMonth,
          selectedDay: selectedDay,
          isCurrentMonth: isCurrentMonth,
          onDaySelected: onDaySelected,
        ),

        // D/E. Day-by-Day Summary
        SectionHeader(
          title: GochanoLanguage.text('Day details', 'দিনের বিবরণ'),
        ),
        if (selectedDay != null)
          _DayDetail(
            day: selectedDay!,
            month: selectedMonth,
            items: items,
            dailyTotals: dailyTotals,
            isToday: isCurrentMonth &&
                selectedDay == DateTime.now().day,
            isExpanded: dayExpanded,
            onToggle: onDayExpanded,
          )
        else
          AppCard(
            child: Text(
              GochanoLanguage.text(
                'Select a day in the chart above to see details.',
                'বিস্তারিত দেখতে উপরের চার্টে একটি দিন নির্বাচন করুন।',
              ),
              style: context.type.bodySecondary,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// A. Month Selector
// ---------------------------------------------------------------------------

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  static const _months = [
    '', // index 0 unused
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _monthsBn = [
    '', 'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
  ];

  String _monthLabel() {
    final en = '${_months[month.month]} ${month.year}';
    final bn = '${_monthsBn[month.month]} ${month.year}';
    return GochanoLanguage.text(en, bn);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            color: onPrev != null ? colors.textPrimary : colors.disabled,
            visualDensity: VisualDensity.compact,
            tooltip: GochanoLanguage.text('Previous month', 'আগের মাস'),
          ),
          Expanded(
            child: Text(
              _monthLabel(),
              style: type.cardHeading,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            color: onNext != null ? colors.textPrimary : colors.disabled,
            visualDensity: VisualDensity.compact,
            tooltip: GochanoLanguage.text('Next month', 'পরের মাস'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// B. Monthly Summary Cards
// ---------------------------------------------------------------------------

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.monthlyMoney,
    required this.hasBudget,
    required this.totalSpent,
    required this.moneyIn,
    required this.adjustedRemaining,
    required this.dailyExpenseTotal,
    required this.groceryTotal,
    required this.medicineTotal,
    required this.denaPaid,
    required this.pawnaReceived,
  });

  final double? monthlyMoney;
  final bool hasBudget;
  final double totalSpent;
  final double moneyIn;
  final double adjustedRemaining;
  final double dailyExpenseTotal;
  final double groceryTotal;
  final double medicineTotal;
  final double denaPaid;
  final double pawnaReceived;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final budget = monthlyMoney ?? 0;
    final spentRatio = hasBudget && budget > 0
        ? (totalSpent / budget).clamp(0.0, 1.0)
        : 0.0;
    final remainingRatio = hasBudget && budget > 0
        ? (adjustedRemaining / budget).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      children: [
        // ── Top summary: Monthly Money / Spent / Remaining ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Monthly Money
              _SummaryRow(
                label: GochanoLanguage.text('Monthly money', 'মাসিক টাকা'),
                value: hasBudget ? formatTaka(budget) : GochanoLanguage.text('Not set', 'সেট করা নেই'),
                color: colors.brand,
              ),
              if (hasBudget) ...[
                const SizedBox(height: GochanoSpacing.xs),
                _ProgressBar(
                  ratio: spentRatio,
                  color: colors.expense,
                  height: 6,
                ),
              ],
              const SizedBox(height: GochanoSpacing.md),
              // Spent
              _SummaryRow(
                label: GochanoLanguage.text('Total spent', 'মোট খরচ'),
                value: formatTaka(totalSpent),
                color: colors.expense,
              ),
              const SizedBox(height: GochanoSpacing.md),
              // Remaining
              _SummaryRow(
                label: GochanoLanguage.text('Remaining', 'বাকি'),
                value: hasBudget ? formatTaka(adjustedRemaining) : '—',
                color: adjustedRemaining < 0 ? colors.error : colors.success,
                isBold: true,
              ),
              if (hasBudget) ...[
                const SizedBox(height: GochanoSpacing.xs),
                _ProgressBar(
                  ratio: remainingRatio,
                  color: adjustedRemaining < 0 ? colors.error : colors.success,
                  height: 4,
                ),
              ],
            ],
          ),
        ),

        // ── Money In (only when positive) ──
        if (moneyIn > 0) ...[
          const SizedBox(height: GochanoSpacing.sm),
          AppCard(
            accent: colors.success,
            child: _SummaryRow(
              label: GochanoLanguage.text('Money in', 'আয়'),
              value: formatTaka(moneyIn),
              color: colors.success,
            ),
          ),
        ],

        // ── Category breakdown: colored horizontal bars ──
        const SizedBox(height: GochanoSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                GochanoLanguage.text('Categories', 'ক্যাটাগরি'),
                style: type.cardHeading,
              ),
              const SizedBox(height: GochanoSpacing.sm),
              _CategoryBar(
                label: GochanoLanguage.text('Daily', 'দৈনিক'),
                value: dailyExpenseTotal,
                total: totalSpent > 0 ? totalSpent : 1,
                color: colors.expense,
              ),
              _CategoryBar(
                label: GochanoLanguage.text('Grocery', 'বাজার'),
                value: groceryTotal,
                total: totalSpent > 0 ? totalSpent : 1,
                color: colors.community,
              ),
              _CategoryBar(
                label: GochanoLanguage.text('Medicine', 'ওষুধ'),
                value: medicineTotal,
                total: totalSpent > 0 ? totalSpent : 1,
                color: colors.medicine,
              ),
              _CategoryBar(
                label: GochanoLanguage.text('Dena paid', 'দেনা'),
                value: denaPaid,
                total: totalSpent > 0 ? totalSpent : 1,
                color: colors.warning,
              ),
              _CategoryBar(
                label: GochanoLanguage.text('Pawna received', 'পাওনা'),
                value: pawnaReceived,
                total: totalSpent > 0 ? totalSpent : 1,
                color: colors.success,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Set Budget Prompt
// ---------------------------------------------------------------------------

/// A compact label + value row used inside summary cards.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Row(
      children: [
        Expanded(
          child: Text(label, style: isBold ? type.cardHeading : type.body),
        ),
        Text(
          value,
          style: (isBold ? type.cardHeading : type.body).copyWith(
            color: color,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A thin horizontal progress bar.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.ratio,
    required this.color,
    this.height = 6,
  });

  final double ratio;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // Track
            Container(color: colors.surfaceVariant),
            // Fill
            FractionallySizedBox(
              widthFactor: ratio,
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A category summary row: label, amount, and a colored bar showing proportion.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final double value;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final ratio = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: type.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: colors.surfaceVariant),
                    if (value > 0)
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(color: color),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          SizedBox(
            width: 72,
            child: Text(
              formatTaka(value),
              style: type.body.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
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

// ---------------------------------------------------------------------------
// Cash Flow Card
// ---------------------------------------------------------------------------

class _CashFlowCard extends StatelessWidget {
  const _CashFlowCard({
    required this.outflow,
    required this.inflow,
    required this.remaining,
  });

  final double outflow;
  final double inflow;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CashFlowRow(
            label: GochanoLanguage.text('Outflow', 'ব্যয়'),
            value: formatTaka(outflow),
            color: colors.error,
            icon: Icons.arrow_upward_rounded,
          ),
          Divider(height: GochanoSpacing.md, color: colors.divider),
          _CashFlowRow(
            label: GochanoLanguage.text('Inflow', 'আয়'),
            value: formatTaka(inflow),
            color: colors.success,
            icon: Icons.arrow_downward_rounded,
          ),
          Divider(height: GochanoSpacing.md, color: colors.divider),
          _CashFlowRow(
            label: GochanoLanguage.text('Remaining', 'বাকি'),
            value: formatTaka(remaining),
            color: remaining >= 0 ? colors.success : colors.error,
            icon: remaining >= 0
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _CashFlowRow extends StatelessWidget {
  const _CashFlowRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isBold = false,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: GochanoSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: isBold ? type.cardHeading : type.body,
          ),
        ),
        Text(
          value,
          style: (isBold ? type.cardHeading : type.body).copyWith(
            color: color,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// C. Daily Bar Chart
// ---------------------------------------------------------------------------

class _DailyBarChart extends StatelessWidget {
  const _DailyBarChart({
    required this.dailyTotals,
    required this.daysInMonth,
    required this.selectedMonth,
    required this.selectedDay,
    required this.isCurrentMonth,
    required this.onDaySelected,
  });

  final Map<int, double> dailyTotals;
  final int daysInMonth;
  final DateTime selectedMonth;
  final int? selectedDay;
  final bool isCurrentMonth;
  final ValueChanged<int> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final now = DateTime.now();

    final maxAmount = dailyTotals.values.fold<double>(0, (a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Y-axis label
          if (maxAmount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
              child: Text(
                GochanoLanguage.text(
                  'Max: ${formatTaka(maxAmount)}',
                  'সর্বোচ্চ: ${formatTaka(maxAmount)}',
                ),
                style: type.caption,
              ),
            ),
          // Bars
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var day = 1; day <= daysInMonth; day++)
                  Expanded(
                    child: _Bar(
                      day: day,
                      amount: dailyTotals[day] ?? 0,
                      maxAmount: maxAmount,
                      isSelected: selectedDay == day,
                      isToday: isCurrentMonth && day == now.day,
                      isFuture: isCurrentMonth && day > now.day,
                      onTap: () => onDaySelected(day),
                    ),
                  ),
              ],
            ),
          ),
          // X-axis labels (5th, 10th, 15th, 20th, 25th)
          Padding(
            padding: const EdgeInsets.only(top: GochanoSpacing.xxs),
            child: Row(
              children: [
                for (var day = 1; day <= daysInMonth; day++)
                  if (day == 1 || day % 5 == 0)
                    Expanded(
                      child: Text(
                        '$day',
                        style: type.caption.copyWith(fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.amount,
    required this.maxAmount,
    required this.isSelected,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final int day;
  final double amount;
  final double maxAmount;
  final bool isSelected;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final fraction = maxAmount > 0 ? (amount / maxAmount).clamp(0.05, 1.0) : 0.0;
    final barHeight = maxAmount > 0 ? fraction * 120.0 : 0.0;

    Color barColor;
    if (isFuture) {
      barColor = colors.surfaceVariant;
    } else if (isSelected) {
      barColor = colors.brand;
    } else if (isToday) {
      barColor = colors.expense;
    } else if (amount > 0) {
      barColor = colors.expense.withValues(alpha: 0.6);
    } else {
      barColor = colors.surfaceVariant;
    }

    return GestureDetector(
      onTap: isFuture ? null : onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Amount label on selected bar
          if (isSelected && amount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                formatTaka(amount),
                style: type.caption.copyWith(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // Bar
          Container(
            height: barHeight.clamp(2.0, 120.0),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
            ),
          ),
          // Selection indicator
          if (isSelected)
            Container(
              height: 3,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: colors.brand,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          else
            const SizedBox(height: 5),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// D/E. Day Detail
// ---------------------------------------------------------------------------

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.day,
    required this.month,
    required this.items,
    required this.dailyTotals,
    required this.isToday,
    required this.isExpanded,
    required this.onToggle,
  });

  final int day;
  final DateTime month;
  final List<FinancialTransactionModel> items;
  final Map<int, double> dailyTotals;
  final bool isToday;
  final bool isExpanded;
  final VoidCallback onToggle;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdaysBn = ['শনি', 'রবি', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final date = DateTime(month.year, month.month, day);
    final dayTotal = dailyTotals[day] ?? 0;

    // Filter transactions for this day
    final dayItems = items
        .where((item) =>
            item.date.day == day &&
            item.date.month == month.month &&
            item.date.year == month.year)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final weekdayIdx = date.weekday - 1; // 0=Monday
    final weekdayEn = _weekdays[weekdayIdx.clamp(0, 6)];
    final weekdayBn = _weekdaysBn[weekdayIdx.clamp(0, 6)];
    final weekday = GochanoLanguage.text(weekdayEn, weekdayBn);

    final dateLabel = isToday
        ? GochanoLanguage.text(
            '$weekday, $day ${_monthName(month.month)} (Today)',
            '$weekday, $day ${_monthNameBn(month.month)} (আজ)',
          )
        : GochanoLanguage.text(
            '$weekday, $day ${_monthName(month.month)}',
            '$weekday, $day ${_monthNameBn(month.month)}',
          );

    // Today's view: always detailed. Past days: compact by default, expandable.
    final showDetailed = isToday || isExpanded;

    return AppCard(
      accent: isToday ? colors.brand : null,
      onTap: isToday ? null : onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(dateLabel, style: type.cardHeading),
              ),
              Text(
                formatTaka(dayTotal),
                style: type.cardHeading.copyWith(
                  color: dayTotal > 0 ? colors.expense : colors.textSecondary,
                ),
              ),
              if (!isToday) ...[
                const SizedBox(width: GochanoSpacing.xs),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ],
          ),

          if (!showDetailed) ...[
            // Compact view: just total
            if (dayItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: GochanoSpacing.xxs),
                child: Text(
                  GochanoLanguage.text(
                    '${dayItems.length} transaction${dayItems.length == 1 ? '' : 's'}',
                    '${dayItems.length}টি লেনদেন',
                  ),
                  style: type.caption,
                ),
              ),
          ] else ...[
            // Detailed view
            if (dayItems.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: GochanoSpacing.xs),
                child: Text(
                  GochanoLanguage.text(
                    'No transactions this day.',
                    'এই দিনে কোনো লেনদেন নেই।',
                  ),
                  style: type.bodySecondary,
                ),
              )
            else ...[
              const SizedBox(height: GochanoSpacing.sm),
              CardGroup(
                children: [
                  for (final item in dayItems) _TransactionRow(item: item),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              // Total
              Row(
                children: [
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('Total spent', 'মোট খরচ'),
                      style: type.cardHeading,
                    ),
                  ),
                  Text(formatTaka(dayTotal), style: type.cardHeading),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _monthName(int month) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][month];

  static String _monthNameBn(int month) => const [
        '', 'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
        'জুলাই', 'আগস্ট', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
      ][month];
}

// ---------------------------------------------------------------------------
// Transaction Row
// ---------------------------------------------------------------------------

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.item});

  final FinancialTransactionModel item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, accent, sourceLabel) = switch (item.source) {
      'bazar' => (
          Icons.shopping_cart_rounded,
          colors.community,
          GochanoLanguage.text('Grocery', 'বাজার'),
        ),
      'medicine' => (
          Icons.medication_rounded,
          colors.medicine,
          GochanoLanguage.text('Medicine', 'ওষুধ'),
        ),
      'commute' => (
          Icons.directions_bus_rounded,
          colors.commute,
          GochanoLanguage.text('Commute', 'যাতায়াত'),
        ),
      _ => (
          Icons.receipt_long_rounded,
          colors.expense,
          ExpenseCategories.byId(item.category).label,
        ),
    };

    final hour = item.date.hour % 12 == 0 ? 12 : item.date.hour % 12;
    final minute = item.date.minute.toString().padLeft(2, '0');
    final amPm = item.date.hour < 12 ? 'am' : 'pm';
    final timeStr = '$hour:$minute $amPm';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.isEmpty ? sourceLabel : item.title,
                  style: context.type.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$sourceLabel · $timeStr',
                  style: context.type.caption,
                ),
              ],
            ),
          ),
          Text(
            formatTaka(item.amount),
            style: context.type.cardHeading,
          ),
        ],
      ),
    );
  }
}

// Re-export daysInMonth for tests.
