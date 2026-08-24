import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';

class BazarBuddyScreen extends StatefulWidget {
  const BazarBuddyScreen({super.key});

  @override
  State<BazarBuddyScreen> createState() => _BazarBuddyScreenState();
}

class _BazarBuddyScreenState extends State<BazarBuddyScreen> {
  int tab = 0;

  Future<void> _add() async {
    final item = TextEditingController();
    final quantity = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(EkLanguage.text('Add bazar item', 'বাজারের আইটেম যোগ করুন')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: item, decoration: InputDecoration(labelText: EkLanguage.text('Item', 'আইটেম'))),
            const SizedBox(height: 10),
            TextField(controller: quantity, decoration: InputDecoration(labelText: EkLanguage.text('Quantity / note', 'পরিমাণ / নোট'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(EkLanguage.text('Cancel', 'বাতিল'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(EkLanguage.text('Add', 'যোগ করুন'))),
        ],
      ),
    );
    if (ok == true && item.text.trim().isNotEmpty) {
      await FirestoreService.addOwnerRecord('grocery_items', {
        'title': item.text.trim(),
        'details': quantity.text.trim(),
        'bought': false,
        'keywords': FirestoreService.keywords('${item.text} ${quantity.text}'),
      });
    }
    item.dispose();
    quantity.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('BazarBuddy', 'বাজারবাডি')),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('grocery_items'),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final all = snap.data!.docs;
            final filtered = all.where((d) {
              final bought = d.data()['bought'] == true;
              if (tab == 0) return true;
              if (tab == 1) return !bought;
              return bought;
            }).toList();
            final boughtCount = all.where((d) => d.data()['bought'] == true).length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFEAF9E9), Color(0xFFFFFFFF)]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDDF0DA)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 54, height: 54, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.shopping_cart_outlined, color: EkColors.green)),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(EkLanguage.text('My Bazar List', 'আমার বাজার তালিকা'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                            Text(EkLanguage.text('${all.length} items • $boughtCount bought', '${all.length} আইটেম • $boughtCount কেনা হয়েছে'), style: const TextStyle(color: EkColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add), label: Text(EkLanguage.text('Add', 'যোগ'))),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: const Color(0xFFF0F1F7), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      _tab(0, EkLanguage.text('All (${all.length})', 'সব (${all.length})')),
                      _tab(1, EkLanguage.text('To Buy', 'কিনতে হবে')),
                      _tab(2, EkLanguage.text('Bought ($boughtCount)', 'কেনা ($boughtCount)')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(EkLanguage.text('No items here.', 'এখানে কোনো আইটেম নেই।')))))
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < filtered.length; i++) ...[
                          _row(filtered[i]),
                          if (i != filtered.length - 1) const Divider(height: 1, indent: 56),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tab(int value, String label) {
    final selected = tab == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => tab = value),
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(color: selected ? EkColors.purple : Colors.transparent, borderRadius: BorderRadius.circular(11)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: selected ? Colors.white : EkColors.muted, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _row(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final bought = data['bought'] == true;
    return ListTile(
      leading: Checkbox(
        value: bought,
        activeColor: EkColors.green,
        onChanged: (v) => doc.reference.update({'bought': v ?? false, 'updatedAt': FieldValue.serverTimestamp()}),
      ),
      title: Text(data['title']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.w700, decoration: bought ? TextDecoration.lineThrough : null)),
      subtitle: (data['details']?.toString() ?? '').isEmpty ? null : Text(data['details'].toString()),
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => doc.reference.delete()),
    );
  }
}
