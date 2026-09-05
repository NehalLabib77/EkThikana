// Dena / Pawna — lending and borrowing tracker (spec §47).
//
// "Dena" (দেনা) = I owe money to someone.
// "Pawna" (পাওনা) = Someone owes money to me.
//
// Records are stored in `dena_pawna_items` with inline settlement history.
// Settlements do NOT write to financial_transactions — the UI adjusts
// Remaining by querying settlement totals from this collection.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class DenaPawnaTab extends StatelessWidget {
  const DenaPawnaTab({super.key, this.onChanged});

  /// Called when a Dena/Pawna record is added, edited, settled, or deleted.
  /// The parent can use this to refresh dependent data (e.g. Overview tab).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FinancialService.denaPawnaStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading records…',
              'রেকর্ড লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        final docs = [...?snapshot.data?.docs];

        if (docs.isEmpty) {
          return EmptyState(
            illustration: GochanoArt.featureProfile,
            title: GochanoLanguage.text(
              'No records yet',
              'এখনো কোনো রেকর্ড নেই',
            ),
            message: GochanoLanguage.text(
              'Track who you lent money to or who owes you.',
              'কাকে টাকা দিয়েছেন বা কে আপনাকে ঋণগ্রস্ত তা ট্র্যাক করুন।',
            ),
          );
        }

        // Separate into outstanding / partially settled / settled.
        final unsettled = docs
            .where((d) =>
                d.data()['status'] != 'settled')
            .toList();
        final settledDocs = docs
            .where((d) => d.data()['status'] == 'settled')
            .toList();

        // Compute totals from outstanding + partially settled records.
        double totalDenaOutstanding = 0;
        double totalPawnaOutstanding = 0;
        for (final doc in unsettled) {
          final data = doc.data();
          final outstanding =
              (data['outstandingAmount'] as num?)?.toDouble() ?? 0;
          final type = data['type']?.toString() ?? 'lend';
          if (type == 'lend') {
            totalPawnaOutstanding += outstanding;
          } else {
            totalDenaOutstanding += outstanding;
          }
        }

        return ListView(
          padding: GochanoSpacing.scrollBody,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    compact: true,
                    label: GochanoLanguage.text('Dena outstanding', 'দেনা বাকি'),
                    value: formatTaka(totalDenaOutstanding),
                    accent: context.colors.warning,
                    caption: totalDenaOutstanding > 0
                        ? GochanoLanguage.text(
                            'You owe others',
                            'আপনি ঋণগ্রস্ত',
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: StatCard(
                    compact: true,
                    label: GochanoLanguage.text(
                      'Pawna outstanding',
                      'পাওনা বাকি',
                    ),
                    value: formatTaka(totalPawnaOutstanding),
                    accent: context.colors.success,
                    caption: totalPawnaOutstanding > 0
                        ? GochanoLanguage.text(
                            'Others owe you',
                            'অন্যরা আপনাকে ঋণগ্রস্ত',
                          )
                        : null,
                  ),
                ),
              ],
            ),
            SectionHeader(
              title: GochanoLanguage.text('Open', 'খোলা'),
              action: TextButton.icon(
                onPressed: () => showDenaPawnaSheet(context, onChanged: onChanged),
                icon: const Icon(Icons.add_rounded, size: GochanoSizes.iconSm),
                label: Text(GochanoLanguage.text('Add', 'যোগ')),
              ),
            ),
            if (unsettled.isEmpty)
              AppCard(
                child: Text(
                  GochanoLanguage.text(
                    'All settled up.',
                    'সব মিটমাট হয়ে গেছে।',
                  ),
                  style: context.type.bodySecondary,
                ),
              )
            else
              CardGroup(
                children: [
                  for (final doc in unsettled)
                    _DenaPawnaRow(doc: doc, onChanged: onChanged),
                ],
              ),
            if (settledDocs.isNotEmpty) ...[
              SectionHeader(
                title: GochanoLanguage.text('Settled', 'মিটমাট'),
              ),
              CardGroup(
                children: [
                  for (final doc in settledDocs)
                    _DenaPawnaRow(doc: doc, onChanged: onChanged),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DenaPawnaRow extends StatelessWidget {
  const _DenaPawnaRow({required this.doc, this.onChanged});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = doc.data();
    final personName = data['personName']?.toString() ?? '';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final outstanding =
        (data['outstandingAmount'] as num?)?.toDouble() ?? amount;
    final type = data['type']?.toString() ?? 'lend';
    final status = data['status']?.toString() ?? 'outstanding';
    final note = data['note']?.toString() ?? '';
    final date = (data['date'] as Timestamp?)?.toDate();
    final dueDate = (data['dueDate'] as Timestamp?)?.toDate();
    final totalSettled = amount - outstanding;

    final isLend = type == 'lend';
    final accent = isLend ? colors.success : colors.warning;
    final typeLabel = isLend
        ? GochanoLanguage.text('I lent (Pawna)', 'আমি দিয়েছি (পাওনা)')
        : GochanoLanguage.text('I owe (Dena)', 'আমি দিয়েছি (দেনা)');

    final statusLabel = switch (status) {
      'settled' => GochanoLanguage.text('Settled', 'মিটমাট'),
      'partially_settled' =>
        GochanoLanguage.text('Partially settled', 'আংশিক মিটমাট'),
      _ => GochanoLanguage.text('Outstanding', 'বাকি'),
    };

    return GochanoListRow(
      illustration: isLend
          ? GochanoArt.featureProfile
          : GochanoArt.featureProfile,
      accent: accent,
      title: personName,
      subtitle: typeLabel,
      metadata: [
        if (note.isNotEmpty) note,
        if (date != null) _formatDate(date),
        if (dueDate != null)
          GochanoLanguage.text(
            'Due: ${_formatDate(dueDate)}',
            'বকেয়া: ${_formatDate(dueDate)}',
          ),
        if (totalSettled > 0 && status != 'settled')
          GochanoLanguage.text(
            'Settled: ${formatTaka(totalSettled)} of ${formatTaka(amount)}',
            'মিটমাট: ${formatTaka(amount)} এর ${formatTaka(totalSettled)}',
          ),
      ],
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'settled')
            Text(
              formatTaka(amount),
              style: context.type.cardHeading.copyWith(
                decoration: TextDecoration.lineThrough,
                color: colors.textTertiary,
              ),
            )
          else
            Text(formatTaka(outstanding), style: context.type.cardHeading),
          Text(
            statusLabel,
            style: context.type.caption.copyWith(
              color: status == 'settled'
                  ? colors.textTertiary
                  : status == 'partially_settled'
                      ? colors.warning
                      : colors.textSecondary,
            ),
          ),
        ],
      ),
      menuItems: [
        if (status != 'settled') ...[
          GochanoMenuAction(
            label: GochanoLanguage.text('Settle', 'মিটমাট'),
            icon: Icons.check_circle_outline_rounded,
            onSelected: () => _showSettleDialog(context, outstanding, isLend),
          ),
          GochanoMenuAction(
            label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
            icon: Icons.edit_outlined,
            onSelected: () => showDenaPawnaSheet(context, existing: doc, onChanged: onChanged),
          ),
        ],
        GochanoMenuAction(
          label: GochanoLanguage.text('Delete', 'মুছুন'),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => _confirmDelete(context),
        ),
      ],
    );
  }

  Future<void> _showSettleDialog(
    BuildContext context,
    double outstanding,
    bool isLend,
  ) async {
    final amountController = TextEditingController(
      text: outstanding.toStringAsFixed(0),
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _SettleForm(
        outstanding: outstanding,
        isLend: isLend,
        amountController: amountController,
      ),
    );

    if (result == true && context.mounted) {
      final settleAmount =
          double.tryParse(amountController.text.trim()) ?? 0;
      if (settleAmount > 0 && settleAmount <= outstanding + 0.001) {
        try {
          await FinancialService.settleDenaPawna(
            doc.id,
            settleAmount: settleAmount,
          );
          onChanged?.call();
        } catch (error) {
          if (context.mounted) {
            showGochanoMessage(
              context,
              friendlyErrorMessage(error),
              isError: true,
            );
          }
        }
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmationSheet(
      context,
      title: GochanoLanguage.text('Delete this record?', 'রেকর্ডটি মুছবেন?'),
      message: GochanoLanguage.text(
        'This cannot be undone. Any settlement history will also be removed.',
        'এটি পূর্বাবস্থায় ফেরানো যাবে না। সব মিটমাটের ইতিহাসও মুছে যাবে।',
      ),
      confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
    );
    if (!confirmed || !context.mounted) return;
    try {
      await FinancialService.deleteDenaPawna(doc.id);
      onChanged?.call();
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(
          context,
          friendlyErrorMessage(error),
          isError: true,
        );
      }
    }
  }
}

class _SettleForm extends StatefulWidget {
  const _SettleForm({
    required this.outstanding,
    required this.isLend,
    required this.amountController,
  });

  final double outstanding;
  final bool isLend;
  final TextEditingController amountController;

  @override
  State<_SettleForm> createState() => _SettleFormState();
}

class _SettleFormState extends State<_SettleForm> {
  String? _error;

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
                GochanoLanguage.text('Settle amount', 'মিটমাটের পরিমাণ'),
                style: type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text(
                  'Outstanding: ${formatTaka(widget.outstanding)}',
                  'বাকি: ${formatTaka(widget.outstanding)}',
                ),
                style: type.bodySecondary,
              ),
              const SizedBox(height: GochanoSpacing.md),
              TextField(
                controller: widget.amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text('Amount to settle', 'মিটমাটের পরিমাণ'),
                  prefixText: '৳ ',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              // Quick buttons for common amounts
              Row(
                children: [
                  _QuickAmountChip(
                    label: GochanoLanguage.text('Full', 'পুরো'),
                    amount: widget.outstanding,
                    controller: widget.amountController,
                    onTap: () => setState(() {}),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  _QuickAmountChip(
                    label: GochanoLanguage.text('Half', 'অর্ধেক'),
                    amount: widget.outstanding / 2,
                    controller: widget.amountController,
                    onTap: () => setState(() {}),
                  ),
                ],
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
                label: GochanoLanguage.text('Settle', 'মিটমাট'),
                onPressed: () {
                  final entered =
                      double.tryParse(widget.amountController.text.trim()) ?? 0;
                  if (entered <= 0) {
                    setState(() => _error = GochanoLanguage.text(
                          'Enter an amount greater than zero.',
                          'শূন্যের বেশি পরিমাণ লিখুন।',
                        ));
                    return;
                  }
                  if (entered > widget.outstanding + 0.001) {
                    setState(() => _error = GochanoLanguage.text(
                          'Amount cannot exceed outstanding.',
                          'পরিমাণ বাকি থেকে বেশি হতে পারে না।',
                        ));
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({
    required this.label,
    required this.amount,
    required this.controller,
    required this.onTap,
  });

  final String label;
  final double amount;
  final TextEditingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        controller.text = amount.toStringAsFixed(0);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.sm,
          vertical: GochanoSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: GochanoRadius.mdAll,
          border: Border.all(color: context.colors.border),
        ),
        child: Text(
          '$label (${formatTaka(amount)})',
          style: context.type.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Add or edit a Dena/Pawna record.
Future<bool> showDenaPawnaSheet(
  BuildContext context, {
  DocumentSnapshot<Map<String, dynamic>>? existing,
  VoidCallback? onChanged,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _DenaPawnaForm(existing: existing, onChanged: onChanged),
  );
  return saved ?? false;
}

class _DenaPawnaForm extends StatefulWidget {
  const _DenaPawnaForm({this.existing, this.onChanged});

  final DocumentSnapshot<Map<String, dynamic>>? existing;
  final VoidCallback? onChanged;

  @override
  State<_DenaPawnaForm> createState() => _DenaPawnaFormState();
}

class _DenaPawnaFormState extends State<_DenaPawnaForm> {
  late final TextEditingController _personName;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _type;
  late DateTime? _dueDate;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existing?.data() ?? const <String, dynamic>{};
    _personName = TextEditingController(
        text: data['personName']?.toString() ?? '');
    _amount = TextEditingController(
      text: (data['amount'] as num?)?.toDouble() == 0
          ? ''
          : '${(data['amount'] as num?)?.toDouble() ?? ''}',
    );
    _note = TextEditingController(text: data['note']?.toString() ?? '');
    _type = data['type']?.toString() ?? 'lend';
    _dueDate = (data['dueDate'] as Timestamp?)?.toDate();
  }

  @override
  void dispose() {
    _personName.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final personName = _personName.text.trim();
    final amount = double.tryParse(_amount.text.trim()) ?? 0;

    if (personName.isEmpty) {
      setState(() => _error = GochanoLanguage.text(
            'Enter the person\'s name.',
            'ব্যক্তির নাম লিখুন।',
          ));
      return;
    }
    if (amount <= 0) {
      setState(() => _error = GochanoLanguage.text(
            'Amount must be greater than zero.',
            'পরিমাণ শূন্যের বেশি হতে হবে।',
          ));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FinancialService.saveDenaPawna(
        id: widget.existing?.id,
        personName: personName,
        amount: amount,
        type: _type,
        date: _isEdit
            ? ((widget.existing?.data()?['date'] as Timestamp?)?.toDate() ??
                DateTime.now())
            : DateTime.now(),
        note: _note.text.trim(),
        dueDate: _dueDate,
      );
      widget.onChanged?.call();
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
                    ? GochanoLanguage.text('Edit record', 'রেকর্ড সম্পাদনা')
                    : GochanoLanguage.text('Add record', 'রেকর্ড যোগ'),
                style: type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.md),
              TextField(
                controller: _personName,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'Person\'s name',
                    'ব্যক্তির নাম',
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text('Amount', 'পরিমাণ'),
                  prefixText: '৳ ',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              // Type selector: lend or borrow.
              Row(
                children: [
                  Expanded(
                    child: _TypeChip(
                      label: GochanoLanguage.text(
                        'I lent (Pawna)',
                        'আমি দিয়েছি (পাওনা)',
                      ),
                      icon: Icons.arrow_upward_rounded,
                      color: colors.success,
                      selected: _type == 'lend',
                      onTap: () => setState(() => _type = 'lend'),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: _TypeChip(
                      label: GochanoLanguage.text(
                        'I owe (Dena)',
                        'আমি দিয়েছি (দেনা)',
                      ),
                      icon: Icons.arrow_downward_rounded,
                      color: colors.warning,
                      selected: _type == 'borrow',
                      onTap: () => setState(() => _type = 'borrow'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.sm),
              // Due date picker
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? DateTime.now().add(
                      const Duration(days: 7),
                    ),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _dueDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Due date (optional)',
                      'বকেয়ার তারিখ (ঐচ্ছিক)',
                    ),
                    suffixIcon: _dueDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: GochanoLanguage.text('Clear due date', 'তারিখ মুছুন'),
                            onPressed: () =>
                                setState(() => _dueDate = null),
                          )
                        : const Icon(Icons.calendar_today_rounded, size: 18),
                  ),
                  child: Text(
                    _dueDate != null
                        ? _formatDate(_dueDate!)
                        : GochanoLanguage.text('No due date', 'বকেয়ার তারিখ নেই'),
                    style: _dueDate != null
                        ? type.body
                        : type.bodySecondary,
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'Note (optional)',
                    'নোট (ঐচ্ছিক)',
                  ),
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  _error!,
                  style: type.bodySecondary.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: GochanoSpacing.sm),
              PrimaryButton(
                label: _isEdit
                    ? GochanoLanguage.text('Save', 'সংরক্ষণ')
                    : GochanoLanguage.text('Add record', 'রেকর্ড যোগ'),
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

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.sm,
          vertical: GochanoSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : context.colors.surfaceVariant,
          borderRadius: GochanoRadius.mdAll,
          border: Border.all(
            color: selected ? color : context.colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? color : context.colors.textSecondary,
            ),
            const SizedBox(width: GochanoSpacing.xxs),
            Flexible(
              child: Text(
                label,
                style: context.type.body.copyWith(
                  color: selected ? color : context.colors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime when) {
  final day = when.day.toString().padLeft(2, '0');
  final month = when.month.toString().padLeft(2, '0');
  return '$day/$month/${when.year}';
}
