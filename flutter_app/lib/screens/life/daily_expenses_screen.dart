import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/financial_transaction.dart';
import '../../widgets/gochano_loading.dart';
import '../../services/financial_service.dart';
import 'expense_tracker_screen.dart';

import '../../core/page_route.dart';
class DailyExpensesScreen extends StatefulWidget {
  const DailyExpensesScreen({super.key});

  @override
  State<DailyExpensesScreen> createState() => _DailyExpensesScreenState();
}

class _DailyExpensesScreenState extends State<DailyExpensesScreen> {
  DateTime selectedDate = DateTime.now();

  static const categories = [
    ('Breakfast / Nasta', 'নাশতা', '🍳', Color(0xFFFFF3D9)),
    ('Lunch', 'দুপুরের খাবার', '🍛', Color(0xFFEAF7E6)),
    ('Snacks', 'স্ন্যাকস', '🍪', Color(0xFFF3E9FF)),
    ('Dinner', 'রাতের খাবার', '🍲', Color(0xFFFFEAE5)),
    ('Other', 'অন্যান্য', '🧺', Color(0xFFE8F4FF)),
  ];

  Future<void> addExpense({
    String? presetCategory,
    FinancialTransactionModel? existing,
  }) async {
    Map<String, dynamic> source = const {};
    if (existing != null) {
      final snap = await FinancialService.db
          .collection('daily_expenses')
          .doc(existing.sourceRecordId)
          .get();
      source = snap.data() ?? const {};
    }

    final initialCategory = existing?.category ??
        source['category']?.toString() ??
        presetCategory ??
        categories.first.$1;
    final initialTitle =
        existing?.title ?? source['title']?.toString() ?? '';
    final initialAmount = existing == null
        ? ''
        : existing.amount.toStringAsFixed(
            existing.amount == existing.amount.roundToDouble() ? 0 : 2,
          );
    final initialNote = source['note']?.toString() ?? '';
    final initialDate = existing?.date ?? selectedDate;
    final initialTime = TimeOfDay.fromDateTime(
      existing?.date ?? DateTime.now(),
    );

    // Controllers live inside the sheet's own State so they're created
    // and disposed by the bottom-sheet widget itself. The parent screen
    // no longer touches them after the sheet closes, which removes the
    // "TextEditingController used after being disposed" race entirely.
    final result = await showModalBottomSheet<_DailyExpenseSheetResult>(
      // ignore: use_build_context_synchronously
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DailyExpenseSheet(
        isEdit: existing != null,
        initialCategory: initialCategory,
        initialTitle: initialTitle,
        initialAmount: initialAmount,
        initialNote: initialNote,
        initialDate: initialDate,
        initialTime: initialTime,
      ),
    );

    // If the user dismissed the sheet without confirming, the controllers
    // were already disposed by the sheet's State.dispose(). Nothing to do.
    if (result == null) return;

    if (!mounted) return;
    try {
      final cleanTitle = result.title;
      if (cleanTitle.isEmpty) throw Exception('Expense title is required.');
      if (cleanTitle.length > 80) throw Exception('Expense title is too long.');
      if (result.amount <= 0) {
        throw Exception('Amount must be greater than zero.');
      }
      final when = DateTime(
        result.date.year,
        result.date.month,
        result.date.day,
        result.time.hour,
        result.time.minute,
      );
      if (existing == null) {
        await FinancialService.addDailyExpense(
          category: result.category,
          title: cleanTitle,
          amount: result.amount,
          note: result.note,
          date: when,
        );
      } else {
        await FinancialService.updateDailyExpense(
          id: existing.sourceRecordId,
          category: result.category,
          title: cleanTitle,
          amount: result.amount,
          note: result.note,
          date: when,
        );
      }
      if (mounted) setState(() => selectedDate = result.date);
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
                EkLanguage.text('Daily food & personal expense', 'দৈনিক খাবার ও ব্যক্তিগত খরচ'),
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
          stream: FinancialService.dayStream(selectedDate),
          builder: (context, snap) {
            if (!snap.hasData) {
              return GochanoLoading(
                message: EkLanguage.text('Loading…', 'লোড হচ্ছে…'),
              );
            }
            final all = snap.data!;
            // Single-pass split: avoid two separate `.where().toList()` walks
            // over the day snapshot. Per-day count is bounded by the user's
            // daily activity so this stays cheap, but it's the kind of thing
            // that compounds when the same list is iterated for the year
            // total inside `ExpenseTrackerScreen` as well.
            var dailyTotal = 0.0;
            var overallDayTotal = 0.0;
            final daily = <FinancialTransactionModel>[];
            for (final e in all) {
              if (e.type != 'expense') continue;
              overallDayTotal += e.amount;
              if (e.source == 'daily') {
                dailyTotal += e.amount;
                daily.add(e);
              }
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: selectedDate,
                    );
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Builder(
                    builder: (context) {
                      final dark = Theme.of(context).brightness == Brightness.dark;
                      final bg = dark ? const Color(0xFF1E293B) : const Color(0xFFFFF9E9);
                      final accent = dark ? const Color(0xFF7CD992) : const Color(0xFF187E2D);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: dark ? const Color(0xFF334155) : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, color: accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                DateFormat('EEEE, d MMMM yyyy').format(selectedDate),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (daily.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    EkLanguage.text('Entries', 'এন্ট্রি'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < daily.length; i++) ...[
                          _entryTile(daily[i]),
                          if (i != daily.length - 1)
                            const Divider(height: 1, indent: 58),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Builder(
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
                    final headline = dark
                        ? const Color(0xFF7CD992)
                        : const Color(0xFF126C25);
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        children: [
                          Text(
                            DateFormat('d MMMM yyyy').format(selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '৳${dailyTotal.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: headline,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${EkLanguage.text('All Gochano spending', 'Gochano-তে মোট খরচ')}: ৳${overallDayTotal.toStringAsFixed(0)}',
                            style: const TextStyle(color: EkColors.muted),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => addExpense(),
                  icon: const Icon(Icons.add),
                  label: Text(EkLanguage.text('Add Expense', 'খরচ যোগ করুন')),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2FAE47),
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    GochanoRoute.to(
                      builder: (_) => ExpenseTrackerScreen(initialMonth: selectedDate),
                    ),
                  ),
                  icon: const Icon(Icons.insights_outlined),
                  label: Text(
                    EkLanguage.text(
                      'Open Financial Dashboard',
                      'ফাইন্যান্স ড্যাশবোর্ড খুলুন',
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }


  Widget _entryTile(FinancialTransactionModel item) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFFFF3D9),
        child: Text(
          categories.firstWhere(
            (c) => c.$1 == item.category,
            orElse: () => categories.last,
          ).$3,
        ),
      ),
      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${EkLanguage.text(item.category, _categoryBn(item.category))} • ${DateFormat('h:mm a').format(item.date)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '৳${item.amount.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                await addExpense(existing: item);
              } else if (value == 'delete') {
                final ok = await confirmAction(
                  context,
                  title: EkLanguage.text('Delete expense?', 'খরচ মুছবেন?'),
                  message: EkLanguage.text(
                    'This removes both the daily record and its linked financial transaction.',
                    'এতে দৈনিক রেকর্ড ও এর সাথে যুক্ত আর্থিক লেনদেন দুটোই মুছে যাবে।',
                  ),
                  action: EkLanguage.text('Delete', 'মুছুন'),
                );
                if (ok) {
                  await FinancialService.deleteDailyExpense(item.sourceRecordId);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(EkLanguage.text('Edit', 'সম্পাদনা')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(EkLanguage.text('Delete', 'মুছুন')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _categoryBn(String category) {
    for (final c in categories) {
      if (c.$1 == category) return c.$2;
    }
    return 'অন্যান্য';
  }
}

/// Plain-data result returned by [_DailyExpenseSheet] when the user
/// confirms save. We deliberately use a value type instead of leaking
/// the sheet's `TextEditingController`s out to the parent — that way
/// the parent never holds a reference to a controller that the sheet's
/// `State.dispose()` is about to dispose.
class _DailyExpenseSheetResult {
  const _DailyExpenseSheetResult({
    required this.category,
    required this.title,
    required this.amount,
    required this.note,
    required this.date,
    required this.time,
  });

  final String category;
  final String title;
  final double amount;
  final String note;
  final DateTime date;
  final TimeOfDay time;
}

/// Bottom sheet for creating / editing a daily expense.
///
/// All three `TextEditingController`s are created in this widget's
/// `State` (never in `build()`) and are unconditionally disposed in
/// `State.dispose()`. The widget itself is the single owner of those
/// controllers, so there is no possibility of "used after dispose"
/// even if the parent screen is unmounted while the sheet is still
/// animating open.
class _DailyExpenseSheet extends StatefulWidget {
  const _DailyExpenseSheet({
    required this.isEdit,
    required this.initialCategory,
    required this.initialTitle,
    required this.initialAmount,
    required this.initialNote,
    required this.initialDate,
    required this.initialTime,
  });

  final bool isEdit;
  final String initialCategory;
  final String initialTitle;
  final String initialAmount;
  final String initialNote;
  final DateTime initialDate;
  final TimeOfDay initialTime;

  @override
  State<_DailyExpenseSheet> createState() => _DailyExpenseSheetState();
}

class _DailyExpenseSheetState extends State<_DailyExpenseSheet> {
  // All controllers are class fields (created exactly once when the
  // State is created) and are disposed exactly once when the State is
  // disposed. Never created in `build()`.
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late String _category;
  late DateTime _date;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _amountController = TextEditingController(text: widget.initialAmount);
    _noteController = TextEditingController(text: widget.initialNote);
    _category = widget.initialCategory;
    _date = widget.initialDate;
    _time = widget.initialTime;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final result = _DailyExpenseSheetResult(
      category: _category,
      title: _titleController.text.trim(),
      amount: amount,
      note: _noteController.text.trim(),
      date: _date,
      time: _time,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        18 + mq.viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              EkLanguage.text(
                widget.isEdit ? 'Edit Daily Expense' : 'Add Daily Expense',
                widget.isEdit ? 'দৈনিক খরচ সম্পাদনা' : 'দৈনিক খরচ যোগ করুন',
              ),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: EkLanguage.text('Category', 'ক্যাটাগরি'),
              ),
              items: [
                for (final c in _DailyExpensesScreenState.categories)
                  DropdownMenuItem(
                    value: c.$1,
                    child: Text('${c.$3} ${EkLanguage.text(c.$1, c.$2)}'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: EkLanguage.text('Expense title', 'খরচের নাম'),
                hintText: EkLanguage.text(
                  'e.g. Chicken Rice',
                  'যেমন: চিকেন রাইস',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: EkLanguage.text('Amount (৳)', 'পরিমাণ (৳)'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: EkLanguage.text('Note (optional)', 'নোট (ঐচ্ছিক)'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                        initialDate: _date,
                      );
                      if (picked != null) {
                        if (!mounted) return;
                        setState(() => _date = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(DateFormat('dd MMM yyyy').format(_date)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (picked != null) {
                        if (!mounted) return;
                        setState(() => _time = picked);
                      }
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(
                EkLanguage.text(
                  widget.isEdit ? 'Update Expense' : 'Save Expense',
                  widget.isEdit ? 'খরচ আপডেট করুন' : 'খরচ সংরক্ষণ',
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: const Color(0xFF2FAE47),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
