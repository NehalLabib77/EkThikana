import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../widgets/bento/bento_bar.dart';
import '../../widgets/gochano_loading.dart';
import '../../widgets/gochano_primitives.dart';
import '../../services/financial_service.dart';
import 'expense_tracker_screen.dart';

import '../../core/page_route.dart';
class BazarBuddyScreen extends StatefulWidget {
  const BazarBuddyScreen({super.key});

  @override
  State<BazarBuddyScreen> createState() => _BazarBuddyScreenState();
}

class _BazarBuddyScreenState extends State<BazarBuddyScreen> {
  DateTime selectedDate = DateTime.now();
  String search = '';

  /// Optimistic override for `purchased` while a toggle is in flight.
  /// Keyed by document id. Reconciled on the next stream emission; if
  /// the server value disagrees, the stream's `data['purchased']` wins.
  final Map<String, bool> _optimisticPurchased = <String, bool>{};

  static const categories = <_BazarCategory>[
    _BazarCategory('Fish', 'মাছ', '🐟', Color(0xFFE7F6FF)),
    _BazarCategory('Meat', 'মাংস', '🥩', Color(0xFFFFEAE5)),
    _BazarCategory('Vegetables', 'সবজি', '🥬', Color(0xFFEAF7E6)),
    _BazarCategory('Fruits', 'ফল', '🍎', Color(0xFFFFF3D9)),
    _BazarCategory('Rice', 'চাল', '🍚', Color(0xFFF9F2E7)),
    _BazarCategory('Eggs', 'ডিম', '🥚', Color(0xFFFFF7EA)),
    _BazarCategory('Milk', 'দুধ', '🥛', Color(0xFFF0EEFF)),
    _BazarCategory('Spices', 'মসলা', '🌶️', Color(0xFFFFE8DB)),
    _BazarCategory('Household', 'গৃহস্থালি', '🧺', Color(0xFFEAF4FF)),
    _BazarCategory('Other', 'অন্যান্য', '🛍️', Color(0xFFF2F2F2)),
  ];

  String get sessionId => FinancialService.bazarSessionId(selectedDate);

  // No persistent controller field. The freeform-unit controller is owned
  // by `editItem` and tied to the lifetime of the bottom sheet, so it was
  // leaking (and racing) when held as a field. Now it is created lazily
  // inside the sheet's first build and disposed when the sheet closes.

  /// Cache of the latest custom-unit text from the bottom sheet. We only
  /// read this from outside the sheet at save-time, so it is a String,
  /// never a controller. The controller itself lives entirely inside the
  /// `StatefulBuilder` scope of `editItem`.
  String? _lastCustomUnitText;

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: selectedDate,
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  /// Returns a small set of commonly-purchased items for a category.
  /// Long-press on the carousel opens these as one-tap presets that
  /// jump straight into the add sheet with the title pre-filled.
  static List<String> quickPicksFor(String category) {
    switch (category) {
      case 'Fish':
        return const ['Rui', 'Hilsa', 'Katla', 'Tilapia', 'Prawn'];
      case 'Meat':
        return const ['Chicken', 'Beef', 'Mutton', 'Liver'];
      case 'Vegetables':
        return const ['Potato', 'Onion', 'Tomato', 'Brinjal', 'Okra'];
      case 'Fruits':
        return const ['Banana', 'Apple', 'Mango', 'Orange'];
      case 'Rice':
        return const ['Miniket', 'Nazirshail', 'Atop'];
      case 'Eggs':
        return const ['Chicken egg', 'Duck egg'];
      case 'Milk':
        return const ['Liquid milk', 'Powder milk', 'Yogurt'];
      case 'Spices':
        return const ['Onion paste', 'Ginger paste', 'Turmeric', 'Chili'];
      case 'Household':
        return const ['Detergent', 'Soap', 'Toilet paper'];
      case 'Other':
      default:
        return const [];
    }
  }

  Future<void> _showQuickPicks(
    BuildContext context,
    _BazarCategory c,
    List<String> picks,
  ) async {
    // Capture the messenger BEFORE the async gap so we never touch
    // `context` after an await — this avoids `use_build_context_synchronously`.
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(
                    '${EkLanguage.text('Quick add', 'দ্রুত যোগ')} · ${EkLanguage.text(c.en, c.bn)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: picks.length,
                itemBuilder: (_, i) {
                  final p = picks[i];
                  return ListTile(
                    leading: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF2EAD46)),
                    title: Text(p),
                    onTap: () => Navigator.pop(sheetContext, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      try {
        // One-tap add: write a sensible default row directly through the       
        // service. Marked NOT purchased so it does not yet become an
        // expense — the user can adjust quantity/price from the sheet or     
        // via Edit. This honours the `purchased && price > 0` mirror gate.     
        await FinancialService.saveBazarItem(
          sessionId: sessionId,
          category: c.en,
          title: chosen,
          quantity: 1,
          unit: 'pcs',
          price: 0,
          purchased: false,
          date: DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            DateTime.now().hour,
            DateTime.now().minute,
          ),
        );
      } catch (e) {
        if (context.mounted) {
          showError(context, e);
        }
      }
    }
  }

  Future<void> editItem({
    _BazarCategory? presetCategory,
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final data = doc?.data() ?? const <String, dynamic>{};
    // Saved 'unit' may be a freeform string (when user picked 'other' before)
    // or one of the fixed dropdown values. Show freeform input only if it's not
    // one of the known options.
    const fixedUnits = <String>{'kg', 'g', 'L', 'ml', 'pcs', 'pack'};
    final savedUnit = data['unit']?.toString() ?? 'kg';
    // Defensive lookup: legacy data may have a category that doesn't
    // exist in the current `categories` list (renamed categories, typos,
    // or case differences). Map anything unknown to the preset, or the
    // last category ('Other') as the safe fallback. This prevents the
    // DropdownButton 'initialValue not in items' assertion when the
    // dropdown is built below.
    final knownCategoryValues = {for (final c in categories) c.en};
    var category = data['category']?.toString() ?? presetCategory?.en ?? 'Other';
    if (!knownCategoryValues.contains(category)) {
      category = presetCategory?.en ?? categories.last.en;
    }
    final title = TextEditingController(text: data['title']?.toString() ?? '');
    final quantity = TextEditingController(
      text: ((data['quantity'] as num?)?.toDouble() ?? 1).toString(),
    );
    var unit = fixedUnits.contains(savedUnit) ? savedUnit : 'other';
    var customUnit = fixedUnits.contains(savedUnit) ? '' : savedUnit;
    // The persisted `price` field stores the TOTAL price (per the existing
    // FinancialService / financial_transactions contract). When opening an
    // existing row we therefore back-derive the unit price by dividing
    // `price / quantity` so the edit sheet shows what the user originally
    // typed. For new rows we default to empty so the user enters a unit
    // price from scratch.
    final savedTotal = (data['price'] as num?)?.toDouble();
    final savedQuantity =
        ((data['quantity'] as num?)?.toDouble() ?? 1);
    final initialUnitPrice = (savedTotal == null)
        ? ''
        : (savedTotal / (savedQuantity == 0 ? 1 : savedQuantity))
            .toStringAsFixed(2);
    final unitPrice = TextEditingController(text: initialUnitPrice);
    var purchased = data['purchased'] == true;
    // Local-only controller for the 'other' unit field. The very first
    // build of the bottom sheet creates it inside the StatefulBuilder's
    // Builder (see below) and the very last line of editItem disposes it.
    // It is intentionally NOT a class field — re-assigning a controller
    // during a builder is what caused the original leak/assert.
    TextEditingController? customController;
    // Reset the cached typed text so a fresh sheet doesn't inherit text
    // from the previous sheet's `customUnit`.
    _lastCustomUnitText = null;

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              18 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc == null
                        ? EkLanguage.text('Add Bazar Item', 'বাজারের আইটেম যোগ করুন')
                        : EkLanguage.text('Edit Bazar Item', 'বাজারের আইটেম সম্পাদনা'),
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
                          value: c.en,
                          child: Text('${c.emoji} ${EkLanguage.text(c.en, c.bn)}'),
                        ),
                    ],
                    onChanged: (value) => setSheet(() => category = value ?? 'Other'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: InputDecoration(
                      labelText: EkLanguage.text('Item name', 'আইটেমের নাম'),
                      hintText: EkLanguage.text('e.g. Rui Fish', 'যেমন: রুই মাছ'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: quantity,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: EkLanguage.text('Quantity', 'পরিমাণ'),
                          ),
                          onChanged: (_) => setSheet(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unit,
                          decoration: InputDecoration(
                            labelText: EkLanguage.text('Unit', 'একক'),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'kg', child: Text('kg')),
                            DropdownMenuItem(value: 'g', child: Text('g')),
                            DropdownMenuItem(value: 'L', child: Text('L')),
                            DropdownMenuItem(value: 'ml', child: Text('ml')),
                            DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                            DropdownMenuItem(value: 'pack', child: Text('pack')),
                            DropdownMenuItem(value: 'other', child: Text('other')),
                          ],
                          onChanged: (value) => setSheet(() => unit = value ?? 'pcs'),
                        ),
                      ),
                    ],
                  ),
                  if (unit == 'other') ...[
                    const SizedBox(height: 12),
                    Builder(
                      builder: (_) {
                        // Local controller, scoped to this Builder so each
                        // rebuild of the StatefulBuilder gets a fresh
                        // controller while the sheet is open. The very first
                        // build seeds it from the saved value (`customUnit`).
                        // We keep a tiny text cache on the State so the
                        // suffix hint and the save handler can read the
                        // latest value without holding the controller.
                        customController = TextEditingController(
                          text: _lastCustomUnitText ?? customUnit,
                        );
                        return TextField(
                          controller: customController,
                          decoration: InputDecoration(
                            labelText: EkLanguage.text('Custom unit', 'কাস্টম একক'),
                            hintText: EkLanguage.text('e.g. dozen, bundle', 'যেমন: ডজন, আঁটি'),
                          ),
                          // Rebuild so the unit-price suffix hint (e.g. ৳/dozen)
                          // tracks the freshly typed custom unit. Capture
                          // the text in a plain String — never re-assign a
                          // controller from the build path.
                          onChanged: (value) {
                            _lastCustomUnitText = value;
                            setSheet(() {});
                          },
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: unitPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: EkLanguage.text('Unit price (৳)', 'একক মূল্য (৳)'),
                      // Helper hint shows which unit the price is per.
                      // Mirrors the unit actually being saved (dropdown OR
                      // custom text), so the user can never confuse themselves
                      // about whether they're entering per-kg or per-piece.
                      suffixText: () {
                        String resolved;
                        if (unit == 'other') {
                          final typed = _lastCustomUnitText?.trim() ?? '';
                          if (typed.isNotEmpty) {
                            resolved = typed;
                          } else if (customUnit.trim().isNotEmpty) {
                            resolved = customUnit.trim();
                          } else {
                            resolved = 'unit';
                          }
                        } else {
                          resolved = unit;
                        }
                        return '৳/$resolved';
                      }(),
                    ),
                    onChanged: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: 10),
                  // Live calculated total = unit price × quantity. Shown
                  // while the user types so they can sanity-check before save.
                  Builder(builder: (_) {
                    final q = double.tryParse(quantity.text.trim()) ?? 0;
                    final up = double.tryParse(unitPrice.text.trim()) ?? 0;
                    final total = q > 0 && up > 0 ? (up * q) : 0.0;
                    final hasInput = quantity.text.trim().isNotEmpty &&
                        unitPrice.text.trim().isNotEmpty;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1FBE9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDCECCB)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calculate_outlined,
                              size: 18, color: Color(0xFF0D6E2A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              EkLanguage.text(
                                'Calculated total',
                                'হিসাব করা মোট',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D6E2A),
                              ),
                            ),
                          ),
                          Text(
                            hasInput ? '৳${total.toStringAsFixed(2)}' : '৳0',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: Color(0xFF0D6E2A),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: purchased,
                    onChanged: (value) => setSheet(() => purchased = value),
                    title: Text(EkLanguage.text('Purchased', 'কেনা হয়েছে')),
                    subtitle: Text(
                      EkLanguage.text(
                        'Only purchased items become an expense.',
                        'শুধু কেনা আইটেম খরচ হিসেবে যোগ হবে।',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(EkLanguage.text('Save Item', 'আইটেম সংরক্ষণ')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: const Color(0xFF2EAD46),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (save == true) {
      try {
        final q = double.tryParse(quantity.text.trim()) ?? 0;
        final up = double.tryParse(unitPrice.text.trim()) ?? 0;
        // Save contract is unchanged: FinancialService.saveBazarItem(price: ...)
        // expects the TOTAL, not the unit price. Compute it here from
        // unitPrice × quantity so the mirror (financial_transactions.amount)
        // still receives the correct total.
        final p = up * q;
        final cleanTitle = title.text.trim();
        if (cleanTitle.isEmpty) throw Exception('Item name is required.');
        if (cleanTitle.length > 60) throw Exception('Item name is too long.');
        if (q <= 0) throw Exception('Quantity must be greater than zero.');
        if (up < 0) throw Exception('Unit price cannot be negative.');
        // If the user picked 'other' and typed a custom unit, persist the
        // freeform text. Otherwise keep the chosen dropdown value. Fall back
        // to 'pcs' (matches the dropdown default) when 'other' is left blank.
        String resolvedUnit = unit;
        if (unit == 'other') {
          // Prefer the typed value captured during the sheet's rebuilds,
          // then fall back to whatever the saved document had.
          final typed = _lastCustomUnitText?.trim() ?? '';
          final custom = typed.isNotEmpty ? typed : customUnit.trim();
          resolvedUnit = custom.isEmpty ? 'pcs' : custom;
        }
        await FinancialService.saveBazarItem(
          id: doc?.id,
          sessionId: sessionId,
          category: category,
          title: cleanTitle,
          quantity: q,
          unit: resolvedUnit,
          price: p,
          purchased: purchased,
          date: DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            DateTime.now().hour,
            DateTime.now().minute,
          ),
        );
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    title.dispose();
    quantity.dispose();
    unitPrice.dispose();
    // Always dispose the per-sheet custom unit controller, even if the
    // sheet was never opened with `unit == 'other'`.
    customController?.dispose();
    customController = null;
    _lastCustomUnitText = null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    children: [
                      TextSpan(text: 'Bazar', style: TextStyle(color: Color(0xFF08752D))),
                      TextSpan(text: 'Buddy', style: TextStyle(color: Color(0xFFFF6A00))),
                    ],
                  ),
                ),
                Text(
                  EkLanguage.text('Smart Bazar List', 'স্মার্ট বাজার তালিকা'),
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
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FinancialService.bazarItemsForSession(sessionId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return GochanoLoading(
                  message: EkLanguage.text('Loading…', 'লোড হচ্ছে…'),
                );
              }
              final all = [...snap.data!.docs];
              all.sort((a, b) {
                final ac = a.data()['createdAt'] as Timestamp?;
                final bc = b.data()['createdAt'] as Timestamp?;
                return (ac?.millisecondsSinceEpoch ?? 0)
                    .compareTo(bc?.millisecondsSinceEpoch ?? 0);
              });
              // Reconcile optimistic toggles with server state once the
              // round-trip completes: clear optimistic entries whose
              // server value matches, and drop entries for docs that
              // are no longer in the snapshot.
              if (_optimisticPurchased.isNotEmpty) {
                final liveIds = {for (final d in all) d.id};
                _optimisticPurchased.removeWhere((id, value) {
                  if (!liveIds.contains(id)) return true;
                  final server = all
                      .firstWhere((d) => d.id == id)
                      .data()['purchased'] == true;
                  return server == value;
                });
              }
              final filtered = all.where((doc) {
                if (search.trim().isEmpty) return true;
                final d = doc.data();
                final hay = '${d['title']} ${d['category']}'.toLowerCase();
                return hay.contains(search.toLowerCase());
              }).toList();

              final planned = all.fold<double>(
                0,
                (runningTotal, doc) =>
                    runningTotal +
                    ((doc.data()['price'] as num?)?.toDouble() ?? 0),
              );
              final purchased = all
                  .where((doc) => doc.data()['purchased'] == true)
                  .fold<double>(
                    0,
                    (runningTotal, doc) =>
                        runningTotal +
                        ((doc.data()['price'] as num?)?.toDouble() ?? 0),
                  );

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  _dateHeader(context),
                  const SizedBox(height: 14),
                  BentoLargeCard(
                    moduleId: 'bazar',
                    icon: Icons.shopping_basket_rounded,
                    title: EkLanguage.text(
                      'BazarBuddy',
                      'বাজারবন্ধু',
                    ),
                    subtitle: EkLanguage.text(
                      '${all.length} items · ${planned.toStringAsFixed(0)} ৳ planned',
                      '${all.length}টি আইটেম · ${planned.toStringAsFixed(0)} ৳ পরিকল্পিত',
                    ),
                    trailing: const BentoIllustration(module: 'bazar', size: 56),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    EkLanguage.text('🛍️  Choose Items', '🛍️  আইটেম বাছাই করুন'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: BentoColors.onTint(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 122,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (context, index) {
                        final c = categories[index];
                        final picks = quickPicksFor(c.en);
                        // Per-category count so the user sees what's
                        // already on the list before tapping. Matches
                        // case-insensitively against `data['category']`
                        // so legacy rows still count.
                        final count = all
                            .where((doc) =>
                                (doc.data()['category']?.toString() ?? '')
                                    .trim()
                                    .toLowerCase() ==
                                c.en.toLowerCase())
                            .length;
                        return SizedBox(
                          width: 110,
                          child: GestureDetector(
                            onLongPress: picks.isEmpty
                                ? null
                                : () => _showQuickPicks(context, c, picks),
                            child: BentoCard(
                            padding: const EdgeInsets.all(14),
                            background: BentoColors.module(context, 'bazar').tint,
                            onTap: () {
                              // Tap → open add sheet with this category
                              // pre-selected (existing behaviour).
                              editItem(presetCategory: c);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const BentoIllustration(
                                      module: 'bazar',
                                      size: 44,
                                    ),
                                    // Optional count badge in the top-right
                                    // corner. Hidden when 0 so the row
                                    // doesn't feel cluttered for empty
                                    // categories.
                                    if (count > 0)
                                      Positioned(
                                        right: -6,
                                        top: -6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: BentoColors.onTint(context),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '$count',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                              color: BentoColors.module(context, 'bazar').accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  EkLanguage.text(c.en, c.bn),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: BentoColors.onTint(context),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                if (picks.isNotEmpty)
                                  Text(
                                    EkLanguage.text(
                                      'Long-press for quick picks',
                                      'কুইক পিকের জন্য চেপে ধরুন',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: BentoColors.onTintMuted(context),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (value) => setState(() => search = value),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: EkLanguage.text(
                        'Search your bazar list…',
                        'বাজার তালিকায় খুঁজুন…',
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Add new item',
                        onPressed: () => editItem(),
                        icon: const Icon(Icons.add_circle, color: Color(0xFF2EAD46)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          EkLanguage.text('Bazar List', 'বাজার তালিকা'),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${all.length} ${EkLanguage.text('items', 'আইটেম')}',
                        style: const TextStyle(color: EkColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    _emptyCard()
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            _itemTile(filtered[i]),
                            if (i != filtered.length - 1) const Divider(height: 1, indent: 64),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF1FBE9), Color(0xFFFFFBE7)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFDCECCB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Text(
                            EkLanguage.text(
                              'Current Bazar Total',
                              'বর্তমান বাজারের মোট',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0D6E2A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            '৳${planned.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0D6E2A),
                              letterSpacing: -.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${EkLanguage.text('Purchased so far', 'এখন পর্যন্ত কেনা')}: ৳${purchased.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: EkColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      GochanoRoute.to(
                        builder: (_) =>
                            ExpenseTrackerScreen(initialMonth: selectedDate),
                      ),
                    ),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      EkLanguage.text(
                        'View daily & monthly spending',
                        'দৈনিক ও মাসিক খরচ দেখুন',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      alignment: Alignment.center,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _dateHeader(BuildContext context) {
    return InkWell(
      onTap: pickDate,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, color: Color(0xFF08752D)),
            const SizedBox(width: 9),
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
    );
  }

  Widget _itemTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    // Case-insensitive category lookup so that legacy docs with a
    // slightly different category string (e.g. 'fish' vs 'Fish', or
    // 'Vegetables ' with a trailing space) still render the right icon
    // instead of silently falling back to the 'Other' emoji.
    final rawCategory = data['category']?.toString().trim() ?? '';
    final category = categories.firstWhere(
      (c) => c.en.toLowerCase() == rawCategory.toLowerCase(),
      orElse: () => categories.last,
    );
    final serverBought = data['purchased'] == true;
    final optimistic = _optimisticPurchased[doc.id];
    final bought = optimistic ?? serverBought;
    final quantity = (data['quantity'] as num?)?.toDouble() ?? 1;
    final unit = data['unit']?.toString() ?? 'pcs';
    final price = (data['price'] as num?)?.toDouble() ?? 0;

    // Unit-price label is what the user originally typed in the add sheet
    // (per-kg, per-pc, per-dozen, …). It is derived by reversing the
    // `price / quantity` save contract so the user can sanity-check that
    // the row reflects what they entered — even when the unit is a
    // freeform string from the 'other' dropdown.
    final unitPriceLabel = quantity > 0 ? (price / quantity) : 0.0;

    return ListTile(
      leading: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: category.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: .05)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 30)),
            if (bought)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2EAD46),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        data['title']?.toString() ?? '',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          decoration: bought ? TextDecoration.lineThrough : TextDecoration.none,
          color: bought ? EkColors.muted : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_formatQty(quantity)} $unit  •  ৳${price.toStringAsFixed(0)} total',
          ),
          if (quantity > 0 && price > 0)
            Text(
              '৳${unitPriceLabel.toStringAsFixed(2)} / $unit',
              style: const TextStyle(
                color: EkColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: bought,
            activeColor: const Color(0xFF2EAD46),
            onChanged: (value) async {
              final next = value == true;
              // Optimistic local update so the UI feels instant.
              // Guarded: the user could have navigated away during the
              // toggle, which would otherwise throw the
              // "setState() called after dispose()" assertion.
              if (!mounted) return;
              setState(() => _optimisticPurchased[doc.id] = next);
              try {
                await FinancialService.toggleBazarPurchased(
                    doc.reference, next);
              } catch (e) {
                // Roll back optimistic state on failure.
                if (mounted) {
                  setState(() => _optimisticPurchased.remove(doc.id));
                  showError(context, e);
                }
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                await editItem(doc: doc);
              } else if (value == 'delete') {
                final ok = await confirmAction(
                  context,
                  title: EkLanguage.text('Delete item?', 'আইটেম মুছবেন?'),
                  message: EkLanguage.text(
                    'Its linked expense will also be removed.',
                    'এর সাথে যুক্ত খরচও মুছে যাবে।',
                  ),
                  action: EkLanguage.text('Delete', 'মুছুন'),
                );
                if (ok) {
                  if (!mounted) return;
                  setState(() => _optimisticPurchased.remove(doc.id));
                  await FinancialService.deleteBazarItem(doc.id);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(EkLanguage.text('Edit', 'সম্পাদনা'))),
              PopupMenuItem(value: 'delete', child: Text(EkLanguage.text('Delete', 'মুছুন'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return EmptyState(
      module: 'bazar',
      title: EkLanguage.text(
        'Start your bazar list',
        'বাজার তালিকা শুরু করুন',
      ),
      message: EkLanguage.text(
        'Tap a category above or use the button below to add your first item.',
        'উপরে একটি ক্যাটাগরিতে ট্যাপ করুন অথবা নিচের বোতাম থেকে প্রথম আইটেম যোগ করুন।',
      ),
      primaryActionLabel: EkLanguage.text(
        'Add your first item',
        'প্রথম আইটেম যোগ করুন',
      ),
      onPrimaryAction: () => editItem(),
    );
  }

  static String _formatQty(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
}

class _BazarCategory {
  const _BazarCategory(this.en, this.bn, this.emoji, this.color);
  final String en;
  final String bn;
  final String emoji;
  final Color color;
}
