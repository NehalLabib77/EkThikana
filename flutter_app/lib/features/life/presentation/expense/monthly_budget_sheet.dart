// Set this month's available money (spec §48, §72).
//
// Writes through `POST /api/budget/monthly`, which stores the figure under
// the student's own Firestore profile. The figure is *not* an expense — it is
// the ceiling that `GET /api/budget/remaining` subtracts confirmed spending
// from.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';

/// Opens the monthly-money sheet. Returns true when the amount was saved.
Future<bool> showMonthlyBudgetSheet(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _BudgetForm(),
  );
  return saved ?? false;
}

class _BudgetForm extends StatefulWidget {
  const _BudgetForm();

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  final _amount = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    try {
      final body = await ApiService.getMonthlyBudget(DateTime.now());
      final current = (body['availableAmount'] as num?)?.toDouble() ?? 0;
      if (!mounted) return;
      setState(() {
        // Only prefill an untouched field. The read can land after the
        // student has started typing, and overwriting them then would be
        // worse than not prefilling at all.
        if (current > 0 && _amount.text.isEmpty) {
          _amount.text = current == current.roundToDouble()
              ? current.toStringAsFixed(0)
              : current.toStringAsFixed(2);
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // A failed read is not a failed write: let the student type a new
      // figure rather than blocking the sheet on a network hiccup.
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount < 0) {
      setState(() {
        _error = GochanoLanguage.text(
          'Enter the amount you have for this month.',
          'এই মাসে আপনার কাছে যত টাকা আছে তা লিখুন।',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiService.setMonthlyBudget(DateTime.now(), amount);
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
                GochanoLanguage.text('Monthly money', 'মাসিক টাকা'),
                style: type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              Text(
                GochanoLanguage.text(
                  'How much you have to spend this month. Gochano subtracts your '
                  'recorded expenses from it.',
                  'এই মাসে আপনার কাছে কত টাকা আছে। গোছানো এটি থেকে আপনার রেকর্ড করা খরচ বাদ দেবে।',
                ),
                style: type.bodySecondary,
              ),
              const SizedBox(height: GochanoSpacing.md),
              // The field is always here. It used to be replaced by a loading
              // state until the current amount arrived, so a slow or failing
              // read left the sheet with nothing to type into and a disabled
              // Save -- which is exactly what "it will not take any value"
              // looks like. Reading the current amount only prefills it.
              TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: type.statistic,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Available', 'উপলব্ধ'),
                    prefixText: '৳ ',
                    prefixStyle:
                        type.statistic.copyWith(color: colors.textSecondary),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              if (_error != null) ...[
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  _error!,
                  style: type.bodySecondary.copyWith(color: colors.error),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: GochanoSpacing.xs),
                StaticLoadingState(
                  compact: true,
                  message: GochanoLanguage.text(
                    'Checking your current amount…',
                    'আপনার বর্তমান পরিমাণ দেখা হচ্ছে…',
                  ),
                ),
              ],
              const SizedBox(height: GochanoSpacing.md),
              PrimaryButton(
                label: GochanoLanguage.text('Save', 'সংরক্ষণ'),
                busy: _saving,
                busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
                // Never gated on the *read*: a student who knows the figure can
                // type it and save while the current one is still loading.
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
