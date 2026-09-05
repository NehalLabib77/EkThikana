// Grocery / Bazar — a section inside Expense, not a separate product
// (spec §47, §51).
//
// The workflow is preserved exactly: item → unit price → quantity →
// automatic total → purchased / pending.
//
// Ledger semantics (spec §51), all handled by `FinancialService`:
//   * marking an item purchased writes one ledger row under the deterministic
//     id `bazar_{itemId}`, so a retry overwrites rather than duplicates;
//   * un-purchasing deletes that row;
//   * deleting the item deletes the item and the row together, leaving no
//     orphan transaction.
//
// Note the split of concerns in the data: `price` on a bazar item is the
// *total* (unit price × quantity). The edit sheet divides back out to show
// the unit price the student originally typed.

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

class GroceryTab extends StatelessWidget {
  const GroceryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sessionId = FinancialService.bazarSessionId(now);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FinancialService.bazarItemsForSession(sessionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading your bazar list…',
              'আপনার বাজারের তালিকা লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) {
            // Pending first — the list is a shopping list, and the things
            // still to buy are the ones you need to see.
            final ap = a.data()['purchased'] == true ? 1 : 0;
            final bp = b.data()['purchased'] == true ? 1 : 0;
            if (ap != bp) return ap - bp;
            return (a.data()['title']?.toString() ?? '')
                .compareTo(b.data()['title']?.toString() ?? '');
          });

        if (docs.isEmpty) {
          return EmptyState(
            illustration: GochanoArt.featureGrocery,
            title: GochanoLanguage.text(
              'Nothing on the list',
              'তালিকায় কিছু নেই',
            ),
            message: GochanoLanguage.text(
              'Add what you need to buy. Marking an item purchased records '
              'it as an expense.',
              'যা কিনতে হবে যোগ করুন। কেনা হয়েছে চিহ্নিত করলে সেটি খরচ হিসেবে যোগ হবে।',
            ),
          );
        }

        final purchasedTotal = docs
            .where((d) => d.data()['purchased'] == true)
            .fold<double>(
              0,
              (running, d) =>
                  running + ((d.data()['price'] as num?)?.toDouble() ?? 0),
            );
        final pendingTotal = docs
            .where((d) => d.data()['purchased'] != true)
            .fold<double>(
              0,
              (running, d) =>
                  running + ((d.data()['price'] as num?)?.toDouble() ?? 0),
            );
        final pendingCount =
            docs.where((d) => d.data()['purchased'] != true).length;

        return ListView(
          padding: GochanoSpacing.scrollBody,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    compact: true,
                    label: GochanoLanguage.text('Purchased', 'কেনা হয়েছে'),
                    value: formatTaka(purchasedTotal),
                    accent: context.colors.expense,
                    caption: GochanoLanguage.text(
                      'Counted in your spending',
                      'আপনার খরচে গণনা করা হয়েছে',
                    ),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: StatCard(
                    compact: true,
                    label: GochanoLanguage.text('Still to buy', 'কিনতে বাকি'),
                    value: formatTaka(pendingTotal),
                    caption: GochanoLanguage.text(
                      pendingCount == 1 ? '1 item' : '$pendingCount items',
                      '$pendingCount টি আইটেম',
                    ),
                  ),
                ),
              ],
            ),
            SectionHeader(
              title: GochanoLanguage.text('Bazar list', 'বাজারের তালিকা'),
              action: TextButton.icon(
                onPressed: () =>
                    showGroceryItemSheet(context, sessionId: sessionId),
                icon: const Icon(Icons.add_rounded, size: GochanoSizes.iconSm),
                label: Text(GochanoLanguage.text('Add', 'যোগ')),
              ),
            ),
            CardGroup(
              children: [for (final doc in docs) _GroceryRow(doc: doc)],
            ),
          ],
        );
      },
    );
  }
}

class _GroceryRow extends StatelessWidget {
  const _GroceryRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = doc.data();
    final purchased = data['purchased'] == true;
    final title = data['title']?.toString() ?? '';
    final quantity = (data['quantity'] as num?)?.toDouble() ?? 1;
    final unit = data['unit']?.toString() ?? 'pcs';
    final total = (data['price'] as num?)?.toDouble() ?? 0;
    final unitPrice = quantity > 0 ? total / quantity : total;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.xxs,
      ),
      child: Row(
        children: [
          // The checkbox is the purchase action. Tapping it writes or removes
          // the ledger row through FinancialService.
          Checkbox(
            value: purchased,
            onChanged: (value) async {
              try {
                await FinancialService.toggleBazarPurchased(
                  doc.reference,
                  value ?? false,
                );
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
          Expanded(
            child: InkWell(
              onTap: () => showGroceryItemSheet(
                context,
                sessionId: data['sessionId']?.toString() ??
                    FinancialService.bazarSessionId(DateTime.now()),
                existing: doc,
              ),
              borderRadius: GochanoRadius.smAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GochanoSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: context.type.cardHeading.copyWith(
                        color: purchased ? colors.textSecondary : null,
                        decoration:
                            purchased ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      // Shows the arithmetic so the total is checkable.
                      '${_trim(quantity)} $unit × ${formatTaka(unitPrice)}',
                      style: context.type.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Text(formatTaka(total), style: context.type.cardHeading),
          GochanoOverflowMenu(
            items: [
              GochanoMenuAction(
                label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
                icon: Icons.edit_outlined,
                onSelected: () => showGroceryItemSheet(
                  context,
                  sessionId: data['sessionId']?.toString() ??
                      FinancialService.bazarSessionId(DateTime.now()),
                  existing: doc,
                ),
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Delete', 'মুছুন'),
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: () async {
                  final confirmed = await showConfirmationSheet(
                    context,
                    title: GochanoLanguage.text(
                      'Remove this item?',
                      'আইটেমটি মুছবেন?',
                    ),
                    message: purchased
                        ? GochanoLanguage.text(
                            'Its expense will be removed from your total too.',
                            'এর খরচও আপনার মোট থেকে বাদ যাবে।',
                          )
                        : GochanoLanguage.text(
                            'It will be removed from your bazar list.',
                            'এটি আপনার বাজারের তালিকা থেকে মুছে যাবে।',
                          ),
                    confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
                  );
                  if (!confirmed || !context.mounted) return;
                  try {
                    await FinancialService.deleteBazarItem(doc.id);
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
          ),
        ],
      ),
    );
  }
}

/// Add or edit a bazar item.
Future<bool> showGroceryItemSheet(
  BuildContext context, {
  required String sessionId,
  DocumentSnapshot<Map<String, dynamic>>? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _GroceryForm(sessionId: sessionId, existing: existing),
    ),
  );
  return saved ?? false;
}

class _GroceryForm extends StatefulWidget {
  const _GroceryForm({required this.sessionId, this.existing});

  final String sessionId;
  final DocumentSnapshot<Map<String, dynamic>>? existing;

  @override
  State<_GroceryForm> createState() => _GroceryFormState();
}

class _GroceryFormState extends State<_GroceryForm> {
  static const _units = ['pcs', 'kg', 'g', 'litre', 'ml', 'dozen', 'packet'];

  late final TextEditingController _title;
  late final TextEditingController _quantity;
  late final TextEditingController _unitPrice;
  late String _unit;
  late bool _purchased;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final data = widget.existing?.data() ?? const <String, dynamic>{};
    final quantity = (data['quantity'] as num?)?.toDouble() ?? 1;
    final total = (data['price'] as num?)?.toDouble() ?? 0;

    _title = TextEditingController(text: data['title']?.toString() ?? '');
    _quantity = TextEditingController(text: _trim(quantity));
    // Divide the stored total back out so the field shows what was typed.
    _unitPrice = TextEditingController(
      text: total == 0 ? '' : _trim(quantity > 0 ? total / quantity : total),
    );
    _unit = _units.contains(data['unit']) ? data['unit'].toString() : _units.first;
    _purchased = data['purchased'] == true;
  }

  @override
  void dispose() {
    _title.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    super.dispose();
  }

  double get _total {
    final q = double.tryParse(_quantity.text.trim()) ?? 0;
    final up = double.tryParse(_unitPrice.text.trim()) ?? 0;
    return q * up;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final quantity = double.tryParse(_quantity.text.trim()) ?? 0;
    final unitPrice = double.tryParse(_unitPrice.text.trim()) ?? 0;

    if (title.isEmpty) {
      setState(() => _error = GochanoLanguage.text(
            'Name the item.',
            'আইটেমের নাম দিন।',
          ));
      return;
    }
    if (quantity <= 0) {
      setState(() => _error = GochanoLanguage.text(
            'Quantity must be greater than zero.',
            'পরিমাণ শূন্যের বেশি হতে হবে।',
          ));
      return;
    }
    if (_purchased && unitPrice <= 0) {
      setState(() => _error = GochanoLanguage.text(
            'Add the price before marking it purchased.',
            'কেনা হয়েছে চিহ্নিত করার আগে দাম যোগ করুন।',
          ));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FinancialService.saveBazarItem(
        id: widget.existing?.id,
        sessionId: widget.sessionId,
        category: 'Grocery',
        title: title,
        quantity: quantity,
        unit: _unit,
        // The save contract stores the *total*; the ledger mirror uses the
        // same figure, so the expense equals what was actually paid.
        price: quantity * unitPrice,
        purchased: _purchased,
        date: DateTime.now(),
      );
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
                  ? GochanoLanguage.text('Edit item', 'আইটেম সম্পাদনা')
                  : GochanoLanguage.text('Add item', 'আইটেম যোগ'),
              style: type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.md),
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Item', 'আইটেম'),
                hintText: GochanoLanguage.text('Rice', 'চাল'),
              ),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text('Quantity', 'পরিমাণ'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text('Unit', 'একক'),
                    ),
                    items: [
                      for (final unit in _units)
                        DropdownMenuItem(value: unit, child: Text(unit)),
                    ],
                    onChanged: (value) =>
                        setState(() => _unit = value ?? _units.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            TextField(
              controller: _unitPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Unit price', 'একক দাম'),
                prefixText: '৳ ',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: GochanoSpacing.sm),

            // Live total, so the student can check the arithmetic before
            // committing it to their spending (spec §51).
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('Total', 'মোট'),
                      style: type.label,
                    ),
                  ),
                  Text(formatTaka(_total), style: type.statisticSmall),
                ],
              ),
            ),

            SwitchListTile.adaptive(
              value: _purchased,
              onChanged: (value) => setState(() => _purchased = value),
              contentPadding: EdgeInsets.zero,
              title: Text(
                GochanoLanguage.text('Already purchased', 'কেনা হয়ে গেছে'),
                style: type.body,
              ),
              subtitle: Text(
                GochanoLanguage.text(
                  'Records it as an expense in your monthly total.',
                  'এটি আপনার মাসিক মোটে খরচ হিসেবে যোগ হবে।',
                ),
                style: type.caption,
              ),
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
              label: GochanoLanguage.text('Save item', 'আইটেম সংরক্ষণ'),
              busy: _saving,
              busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a quantity without trailing ".0".
String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);