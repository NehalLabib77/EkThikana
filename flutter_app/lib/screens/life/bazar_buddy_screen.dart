import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/financial_service.dart';
import 'expense_tracker_screen.dart';

class BazarBuddyScreen extends StatefulWidget {
  const BazarBuddyScreen({super.key});

  @override
  State<BazarBuddyScreen> createState() => _BazarBuddyScreenState();
}

class _BazarBuddyScreenState extends State<BazarBuddyScreen> {
  DateTime selectedDate = DateTime.now();
  String search = '';

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

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: selectedDate,
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> editItem({
    _BazarCategory? presetCategory,
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final data = doc?.data() ?? const <String, dynamic>{};
    var category = data['category']?.toString() ?? presetCategory?.en ?? 'Other';
    final title = TextEditingController(text: data['title']?.toString() ?? '');
    final quantity = TextEditingController(
      text: ((data['quantity'] as num?)?.toDouble() ?? 1).toString(),
    );
    var unit = data['unit']?.toString() ?? 'kg';
    final price = TextEditingController(
      text: (data['price'] as num?)?.toString() ?? '',
    );
    var purchased = data['purchased'] == true;

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
                  const SizedBox(height: 12),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: EkLanguage.text('Total price (৳)', 'মোট দাম (৳)'),
                    ),
                  ),
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
        final p = double.tryParse(price.text.trim()) ?? 0;
        if (title.text.trim().isEmpty) throw Exception('Item name is required.');
        await FinancialService.saveBazarItem(
          id: doc?.id,
          sessionId: sessionId,
          category: category,
          title: title.text.trim(),
          quantity: q,
          unit: unit,
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
    price.dispose();
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
                return const Center(child: CircularProgressIndicator());
              }
              final all = [...snap.data!.docs];
              all.sort((a, b) {
                final ac = a.data()['createdAt'] as Timestamp?;
                final bc = b.data()['createdAt'] as Timestamp?;
                return (ac?.millisecondsSinceEpoch ?? 0)
                    .compareTo(bc?.millisecondsSinceEpoch ?? 0);
              });
              final filtered = all.where((doc) {
                if (search.trim().isEmpty) return true;
                final d = doc.data();
                final hay = '${d['title']} ${d['category']}'.toLowerCase();
                return hay.contains(search.toLowerCase());
              }).toList();

              final planned = all.fold<double>(
                0,
                (sum, doc) => sum + ((doc.data()['price'] as num?)?.toDouble() ?? 0),
              );
              final purchased = all.where((doc) => doc.data()['purchased'] == true).fold<double>(
                0,
                (sum, doc) => sum + ((doc.data()['price'] as num?)?.toDouble() ?? 0),
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                children: [
                  _dateHeader(context),
                  const SizedBox(height: 14),
                  Text(
                    EkLanguage.text('🛍️  Choose Items', '🛍️  আইটেম বাছাই করুন'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 116,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (context, index) {
                        final c = categories[index];
                        return InkWell(
                          onTap: () => editItem(presetCategory: c),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 94,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.color,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.black.withValues(alpha: .05)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(c.emoji, style: const TextStyle(fontSize: 39)),
                                const SizedBox(height: 6),
                                Text(
                                  EkLanguage.text(c.en, c.bn),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                ),
                              ],
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
                      children: [
                        Text(
                          EkLanguage.text('Current Bazar Total', 'বর্তমান বাজারের মোট'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '৳${planned.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0D6E2A),
                          ),
                        ),
                        Text(
                          '${EkLanguage.text('Purchased so far', 'এখন পর্যন্ত কেনা')}: ৳${purchased.toStringAsFixed(0)}',
                          style: const TextStyle(color: EkColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpenseTrackerScreen(initialMonth: selectedDate),
                      ),
                    ),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      EkLanguage.text(
                        'View daily & monthly spending',
                        'দৈনিক ও মাসিক খরচ দেখুন',
                      ),
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
    final category = categories.firstWhere(
      (c) => c.en == data['category']?.toString(),
      orElse: () => categories.last,
    );
    final bought = data['purchased'] == true;
    final quantity = (data['quantity'] as num?)?.toDouble() ?? 1;
    final unit = data['unit']?.toString() ?? 'pcs';
    final price = (data['price'] as num?)?.toDouble() ?? 0;

    return ListTile(
      leading: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: category.color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(category.emoji, style: const TextStyle(fontSize: 25)),
      ),
      title: Text(
        data['title']?.toString() ?? '',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          decoration: bought ? TextDecoration.none : null,
        ),
      ),
      subtitle: Text('${_formatQty(quantity)} $unit • ৳${price.toStringAsFixed(0)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: bought,
            activeColor: const Color(0xFF2EAD46),
            onChanged: (value) async {
              try {
                await FinancialService.toggleBazarPurchased(doc.reference, value == true);
              } catch (e) {
                if (mounted) showError(context, e);
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
                if (ok) await FinancialService.deleteBazarItem(doc.id);
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Text('🛒', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
            Text(
              EkLanguage.text(
                'No items for this bazar yet.',
                'এই বাজারে এখনও কোনো আইটেম নেই।',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
