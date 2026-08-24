import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';

class RecordModuleScreen extends StatelessWidget {
  const RecordModuleScreen({
    super.key,
    required this.title,
    required this.collection,
    required this.itemLabel,
    required this.detailsLabel,
  });

  final String title;
  final String collection;
  final String itemLabel;
  final String detailsLabel;

  Color get accent {
    switch (collection) {
      case 'family_records':
        return EkColors.red;
      case 'rent_records':
        return const Color(0xFFF04D5B);
      case 'saved_locations':
        return EkColors.orange;
      case 'wellness_records':
        return const Color(0xFF5369E8);
      default:
        return EkColors.purple;
    }
  }

  IconData get icon {
    switch (collection) {
      case 'family_records':
        return Icons.groups_2_outlined;
      case 'rent_records':
        return Icons.home_outlined;
      case 'saved_locations':
        return Icons.location_on_outlined;
      case 'wellness_records':
        return Icons.favorite_outline;
      default:
        return Icons.notes_outlined;
    }
  }

  String get bnTitle {
    switch (collection) {
      case 'family_records':
        return 'ফ্যামিলিহাব';
      case 'rent_records':
        return 'রেন্টমেট';
      case 'saved_locations':
        return 'যাতায়াত';
      case 'wellness_records':
        return 'সুস্থতা';
      default:
        return title;
    }
  }

  Future<void> _add(BuildContext context) async {
    final item = TextEditingController();
    final details = TextEditingController();

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${EkLanguage.text('Add', 'যোগ করুন')} ${EkLanguage.bangla.value ? bnTitle : itemLabel}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: item, decoration: InputDecoration(labelText: itemLabel)),
            const SizedBox(height: 10),
            TextField(controller: details, maxLines: 3, decoration: InputDecoration(labelText: detailsLabel)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(EkLanguage.text('Cancel', 'বাতিল'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(EkLanguage.text('Save', 'সংরক্ষণ'))),
        ],
      ),
    );

    if (save != true || item.text.trim().isEmpty) {
      item.dispose();
      details.dispose();
      return;
    }

    try {
      await FirestoreService.addOwnerRecord(collection, {
        'title': item.text.trim(),
        'details': details.text.trim(),
        'keywords': FirestoreService.keywords('${item.text} ${details.text}'),
      });
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      item.dispose();
      details.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text(title, bnTitle)),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        floatingActionButton: FloatingActionButton(onPressed: () => _add(context), child: const Icon(Icons.add)),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream(collection),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: .12)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 52, height: 52, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(icon, color: accent)),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(EkLanguage.text(title, bnTitle), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            Text(EkLanguage.text('${docs.length} saved records', '${docs.length} টি সংরক্ষিত রেকর্ড'), style: const TextStyle(color: EkColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: Text(EkLanguage.text('Add', 'যোগ'))),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (docs.isEmpty)
                  Card(child: Padding(padding: const EdgeInsets.all(28), child: Center(child: Text(EkLanguage.text('No records yet.', 'এখনও কোনো রেকর্ড নেই।')))))
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < docs.length; i++) ...[
                          ListTile(
                            leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: accent, size: 20)),
                            title: Text(docs[i].data()['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(docs[i].data()['details']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v != 'delete') return;
                                final ok = await confirmAction(context, title: EkLanguage.text('Delete record?', 'রেকর্ড মুছবেন?'), message: EkLanguage.text('This record will be removed.', 'রেকর্ডটি মুছে যাবে।'), action: EkLanguage.text('Delete', 'মুছুন'));
                                if (ok) await docs[i].reference.delete();
                              },
                              itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(EkLanguage.text('Delete', 'মুছুন')))],
                            ),
                          ),
                          if (i != docs.length - 1) const Divider(height: 1, indent: 62),
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
}
