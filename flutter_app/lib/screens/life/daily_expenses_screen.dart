import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/financial_transaction.dart';
import '../../services/financial_service.dart';
import 'expense_tracker_screen.dart';

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

    var category = existing?.category ??
        source['category']?.toString() ??
        presetCategory ??
        categories.first.$1;
    final title = TextEditingController(
      text: existing?.title ?? source['title']?.toString() ?? '',
    );
    final amount = TextEditingController(
      text: existing == null
          ? ''
          : existing.amount.toStringAsFixed(
              existing.amount == existing.amount.roundToDouble() ? 0 : 2,
            ),
    );
    final note = TextEditingController(text: source['note']?.toString() ?? '');
    var date = existing?.date ?? selectedDate;
    var time = TimeOfDay.fromDateTime(existing?.date ?? DateTime.now());

    final save = await showModalBottomSheet<bool>(
      // ignore: use_build_context_synchronously
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            18 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  EkLanguage.text(existing == null ? 'Add Daily Expense' : 'Edit Daily Expense', existing == null ? 'দৈনিক খরচ যোগ করুন' : 'দৈনিক খরচ সম্পাদনা'),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: EkLanguage.text('Category', 'ক্যাটাগরি'),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c.$1,
                        child: Text('${c.$3} ${EkLanguage.text(c.$1, c.$2)}'),
                      ),
                  ],
                  onChanged: (value) => setSheet(() => category = value ?? categories.first.$1),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: EkLanguage.text('Expense title', 'খরচের নাম'),
                    hintText: EkLanguage.text('e.g. Chicken Rice', 'যেমন: চিকেন রাইস'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: EkLanguage.text('Amount (৳)', 'পরিমাণ (৳)'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
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
                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                            initialDate: date,
                          );
                          if (picked != null) setSheet(() => date = picked);
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(DateFormat('dd MMM yyyy').format(date)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: time,
                          );
                          if (picked != null) setSheet(() => time = picked);
                        },
                        icon: const Icon(Icons.schedule),
                        label: Text(time.format(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(EkLanguage.text(existing == null ? 'Save Expense' : 'Update Expense', existing == null ? 'খরচ সংরক্ষণ' : 'খরচ আপডেট করুন')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: const Color(0xFF2FAE47),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (save == true) {
      try {
        final value = double.tryParse(amount.text.trim()) ?? 0;
        if (title.text.trim().isEmpty) throw Exception('Expense title is required.');
        final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        if (existing == null) {
          await FinancialService.addDailyExpense(
            category: category,
            title: title.text.trim(),
            amount: value,
            note: note.text.trim(),
            date: when,
          );
        } else {
          await FinancialService.updateDailyExpense(
            id: existing.sourceRecordId,
            category: category,
            title: title.text.trim(),
            amount: value,
            note: note.text.trim(),
            date: when,
          );
        }
        if (mounted) setState(() => selectedDate = date);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }

    title.dispose();
    amount.dispose();
    note.dispose();
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
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final all = snap.data!;
            final daily = all.where((e) => e.type == 'expense' && e.source == 'daily').toList();
            final dailyTotal = daily.fold<double>(0, (s, e) => s + e.amount);
            final overallDayTotal = all
                .where((e) => e.type == 'expense')
                .fold<double>(0, (s, e) => s + e.amount);

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
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9E9),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, color: Color(0xFF187E2D)),
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
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  EkLanguage.text("Today's Categories", 'আজকের ক্যাটাগরি'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final c in categories) ...[
                  _categoryRow(c, daily),
                  const SizedBox(height: 8),
                ],
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
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF3FCEB), Color(0xFFFFF9E6)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFDCECCB)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        EkLanguage.text("Today's Daily Expense", 'আজকের দৈনিক খরচ'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '৳${dailyTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF126C25),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${EkLanguage.text('All Gochano spending today', 'আজ Gochano-তে মোট খরচ')}: ৳${overallDayTotal.toStringAsFixed(0)}',
                        style: const TextStyle(color: EkColors.muted),
                      ),
                    ],
                  ),
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
                    MaterialPageRoute(
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

  Widget _categoryRow(
    (String, String, String, Color) c,
    List<FinancialTransactionModel> daily,
  ) {
    final total = daily
        .where((e) => e.category == c.$1)
        .fold<double>(0, (s, e) => s + e.amount);

    return InkWell(
      onTap: () => addExpense(presetCategory: c.$1),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.$4,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: .04)),
        ),
        child: Row(
          children: [
            Text(c.$3, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                EkLanguage.text(c.$1, c.$2),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '৳${total.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}
