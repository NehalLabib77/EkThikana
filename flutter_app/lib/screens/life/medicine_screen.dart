import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import 'medicine_ocr_screen.dart';

class MedicineScreen extends StatelessWidget {
  const MedicineScreen({super.key});

  Future<void> _manualAdd(BuildContext context) async {
    final name = TextEditingController();
    final dose = TextEditingController();
    final instruction = TextEditingController();
    final times = <String>[];

    final save = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(EkLanguage.text('Add medicine', 'ওষুধ যোগ করুন')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: InputDecoration(labelText: EkLanguage.text('Medicine name', 'ওষুধের নাম'))),
                const SizedBox(height: 10),
                TextField(controller: dose, decoration: InputDecoration(labelText: EkLanguage.text('Dose as prescribed', 'প্রেসক্রিপশনের ডোজ'))),
                const SizedBox(height: 10),
                TextField(
                  controller: instruction,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: EkLanguage.text('Instruction', 'নির্দেশনা')),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(EkLanguage.text('Reminder times', 'রিমাইন্ডারের সময়'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final time in times)
                      InputChip(label: Text(time), onDeleted: () => setLocal(() => times.remove(time))),
                    ActionChip(
                      avatar: const Icon(Icons.add_alarm, size: 18),
                      label: Text(EkLanguage.text('Add time', 'সময় যোগ করুন')),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                        if (picked == null) return;
                        final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                        if (!times.contains(value)) setLocal(() => times.add(value));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(EkLanguage.text('Cancel', 'বাতিল'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(EkLanguage.text('Save', 'সংরক্ষণ'))),
          ],
        ),
      ),
    );

    try {
      if (save == true) {
        if (name.text.trim().isEmpty || times.isEmpty) {
          throw Exception(EkLanguage.text('Medicine name and at least one confirmed reminder time are required.', 'ওষুধের নাম ও অন্তত একটি নিশ্চিত সময় প্রয়োজন।'));
        }
        final sorted = [...times]..sort();
        final ref = await FirestoreService.addOwnerRecord('medicines', {
          'name': name.text.trim(),
          'dose': dose.text.trim(),
          'instruction': instruction.text.trim(),
          'times': sorted,
          'schedule': sorted.join(', '),
          'confirmedByUser': true,
          'ocrConfirmed': false,
          'active': true,
        });
        for (final time in sorted) {
          await NotificationService.scheduleDailyMedicine(
            medicineId: ref.id,
            medicineName: name.text.trim(),
            hhmm: time,
            instruction: [dose.text.trim(), instruction.text.trim()].where((e) => e.isNotEmpty).join(' • '),
          );
        }
        if (context.mounted) showSuccess(context, EkLanguage.text('Medicine reminder saved.', 'ওষুধের রিমাইন্ডার সংরক্ষিত হয়েছে।'));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      name.dispose();
      dose.dispose();
      instruction.dispose();
    }
  }

  List<_ScheduleItem> _items(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final result = <_ScheduleItem>[];
    for (final doc in docs) {
      final data = doc.data();
      final times = ((data['times'] as List?)?.map((e) => e.toString()).toList() ??
          data['schedule']?.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ??
          const <String>[]);
      for (final time in times) {
        result.add(_ScheduleItem(doc.id, data, time));
      }
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('Medicine', 'ওষুধ')),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _manualAdd(context),
          child: const Icon(Icons.add),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('medicines'),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            final items = _items(docs);
            final now = TimeOfDay.now();
            final nowKey = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
            _ScheduleItem? next;
            for (final item in items) {
              if (item.time.compareTo(nowKey) >= 0) {
                next = item;
                break;
              }
            }
            next ??= items.isEmpty ? null : items.first;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicineOcrScreen())),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(color: const Color(0xFFE9FBF7), borderRadius: BorderRadius.circular(16)),
                            child: const Icon(Icons.document_scanner_outlined, color: EkColors.teal, size: 29),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(EkLanguage.text('Upload Prescription', 'প্রেসক্রিপশন আপলোড করুন'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text(EkLanguage.text('Take a photo or choose a file for OCR', 'OCR-এর জন্য ছবি তুলুন বা ফাইল নির্বাচন করুন'), style: const TextStyle(color: EkColors.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 16, color: EkColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SectionHeader(
                  title: Text(EkLanguage.text("Today's Schedule", 'আজকের সময়সূচী')),
                  subtitle: Text(EkLanguage.text('Only user-confirmed times are shown', 'শুধু আপনার নিশ্চিত করা সময় দেখানো হচ্ছে')),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(EkLanguage.text('No medicine records yet.', 'এখনও কোনো ওষুধের রেকর্ড নেই।'))),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          _scheduleRow(context, items[i]),
                          if (i != items.length - 1) const Divider(height: 1, indent: 78),
                        ],
                      ],
                    ),
                  ),
                if (next != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAFBF1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFD1F1DC)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined, color: EkColors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(EkLanguage.text('Next Medicine', 'পরবর্তী ওষুধ'), style: const TextStyle(color: EkColors.green, fontWeight: FontWeight.w700, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(next.data['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${next.data['dose'] ?? ''}${(next.data['dose']?.toString() ?? '').isEmpty ? '' : ' • '}${next.time}', style: const TextStyle(color: EkColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _scheduleRow(BuildContext context, _ScheduleItem item) {
    final data = item.data;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 58, child: Text(item.time, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: EkColors.green, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text([data['name']?.toString() ?? '', data['dose']?.toString() ?? ''].where((e) => e.isNotEmpty).join(' '), style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((data['instruction']?.toString() ?? '').isNotEmpty)
                  Text(data['instruction'].toString(), style: const TextStyle(color: EkColors.muted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            tooltip: EkLanguage.text('Delete', 'মুছুন'),
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () async {
              final ok = await confirmAction(context, title: EkLanguage.text('Delete medicine?', 'ওষুধ মুছবেন?'), message: EkLanguage.text('This will also cancel its confirmed reminder times.', 'এটি নিশ্চিত রিমাইন্ডারের সময়গুলোও বাতিল করবে।'), action: EkLanguage.text('Delete', 'মুছুন'));
              if (!ok) return;
              final times = ((data['times'] as List?) ?? const []).map((e) => e.toString());
              await NotificationService.cancelMedicineTimes(item.id, times);
              await FirestoreService.db.collection('medicines').doc(item.id).delete();
            },
          ),
        ],
      ),
    );
  }
}

class _ScheduleItem {
  _ScheduleItem(this.id, this.data, this.time);
  final String id;
  final Map<String, dynamic> data;
  final String time;
}
