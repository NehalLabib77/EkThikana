// Add / edit a daily expense (spec §50).
//
// "Adding an expense should be extremely fast." The sheet opens with the
// amount field already focused and the numeric keypad up; category defaults to
// the meal that matches the current time of day; the date defaults to today.
// A student who just wants to log ৳120 for lunch types three digits and taps
// Save.
//
// Every write goes through `FinancialService.addDailyExpense`, which writes
// the source document and its ledger mirror in one batch — so the expense and
// the money total can never disagree (spec §36).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/financial_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../domain/expense_categories.dart';

/// Opens the add/edit expense sheet. Returns true when an expense was saved.
Future<bool> showAddExpenseSheet(
  BuildContext context, {
  String? expenseId,
  String? initialCategory,
  String? initialTitle,
  double? initialAmount,
  DateTime? initialDate,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ExpenseForm(
      expenseId: expenseId,
      initialCategory: initialCategory,
      initialTitle: initialTitle,
      initialAmount: initialAmount,
      initialDate: initialDate,
    ),
  );
  return saved ?? false;
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({
    this.expenseId,
    this.initialCategory,
    this.initialTitle,
    this.initialAmount,
    this.initialDate,
  });

  final String? expenseId;
  final String? initialCategory;
  final String? initialTitle;
  final double? initialAmount;
  final DateTime? initialDate;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late ExpenseCategory _category;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.expenseId != null;

  /// The meal a student is most likely logging right now.
  ///
  /// Saves a tap in the common case without ever being wrong in a costly
  /// way — the category chips are right there to change.
  static ExpenseCategory _categoryForNow(DateTime now) {
    final hour = now.hour;
    if (hour < 11) return ExpenseCategories.all[0]; // Breakfast / Nasta
    if (hour < 16) return ExpenseCategories.all[1]; // Lunch
    if (hour < 19) return ExpenseCategories.all[2]; // Snacks
    if (hour < 23) return ExpenseCategories.all[3]; // Dinner
    return ExpenseCategories.fallback;
  }

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
    _amount = TextEditingController(
      text: widget.initialAmount == null || widget.initialAmount == 0
          ? ''
          : _trimAmount(widget.initialAmount!),
    );
    _title = TextEditingController(text: widget.initialTitle ?? '');
    _category = widget.initialCategory == null
        ? _categoryForNow(_date)
        : ExpenseCategories.byId(widget.initialCategory);
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    super.dispose();
  }

  static String _trimAmount(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Keep the original clock time so same-day ordering stays sensible.
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() {
        _error = GochanoLanguage.text(
          'Enter an amount greater than zero.',
          'শূন্যের বেশি একটি পরিমাণ লিখুন।',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    // An empty note is fine — the category already says what it was.
    final title = _title.text.trim().isEmpty ? _category.id : _title.text.trim();

    try {
      if (_isEdit) {
        await FinancialService.updateDailyExpense(
          id: widget.expenseId!,
          category: _category.id,
          title: title,
          amount: amount,
          date: _date,
        );
      } else {
        await FinancialService.addDailyExpense(
          category: _category.id,
          title: title,
          amount: amount,
          date: _date,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.lg,
            GochanoSpacing.xs,
            GochanoSpacing.lg,
            GochanoSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit
                    ? GochanoLanguage.text('Edit expense', 'খরচ সম্পাদনা')
                    : GochanoLanguage.text('Add expense', 'খরচ যোগ করুন'),
                style: type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.md),

              // Amount is the one field that always has to be filled, so it is
              // the one field that gets focus and the numeric keypad.
              TextField(
                controller: _amount,
                autofocus: !_isEdit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: type.statistic,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text('Amount', 'পরিমাণ'),
                  prefixText: '৳ ',
                  prefixStyle: type.statistic.copyWith(color: colors.textSecondary),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: GochanoSpacing.md),

              Text(GochanoLanguage.text('Category', 'ধরন'), style: type.label),
              const SizedBox(height: GochanoSpacing.xs),
              Wrap(
                spacing: GochanoSpacing.xs,
                runSpacing: GochanoSpacing.xs,
                children: [
                  for (final category in ExpenseCategories.all)
                    ChoiceChip(
                      selected: category.id == _category.id,
                      onSelected: (_) => setState(() => _category = category),
                      avatar: GochanoIllustration(
                        category.illustration,
                        size: 18,
                        accent: category.id == _category.id
                            ? colors.brand
                            : colors.textSecondary,
                      ),
                      label: Text(category.label),
                    ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.md),

              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text('Note (optional)', 'নোট (ঐচ্ছিক)'),
                  hintText: GochanoLanguage.text(
                    'Rice and curry at the canteen',
                    'ক্যান্টিনে ভাত ও তরকারি',
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: GochanoSpacing.sm),

              InkWell(
                onTap: _pickDate,
                borderRadius: GochanoRadius.mdAll,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Date', 'তারিখ'),
                    prefixIcon: const Icon(Icons.event_rounded),
                  ),
                  child: Text(_formatDate(_date), style: type.body),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  _error!,
                  style: type.bodySecondary.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: GochanoSpacing.md),
              PrimaryButton(
                label: GochanoLanguage.text('Save expense', 'খরচ সংরক্ষণ'),
                busy: _saving,
                busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime when) {
  final today = DateTime.now();
  final isToday = when.year == today.year &&
      when.month == today.month &&
      when.day == today.day;
  if (isToday) return GochanoLanguage.text('Today', 'আজ');

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
