import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/financial_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/gochano_primitives.dart';
import 'medicine_form_screen.dart';
import 'medicine_history_screen.dart';
import 'medicine_ocr_screen.dart';

import '../../core/page_route.dart';
class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  String todayKey() => FinancialService.dateKey(DateTime.now());

  List<_DoseRow> rows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> medicines,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> doseDocs,
  ) {
    final byId = {for (final d in doseDocs) d.id: d.data()};
    final now = DateTime.now();
    final result = <_DoseRow>[];

    for (final med in medicines) {
      final data = med.data();
      if (data['active'] != true || data['paused'] == true) continue;

      final start = data['startDate'] is Timestamp
          ? (data['startDate'] as Timestamp).toDate()
          : DateTime(2000);
      final end = data['endDate'] is Timestamp
          ? (data['endDate'] as Timestamp).toDate()
          : null;
      final today = DateTime(now.year, now.month, now.day);
      if (today.isBefore(DateTime(start.year, start.month, start.day))) continue;
      if (end != null &&
          today.isAfter(DateTime(end.year, end.month, end.day))) {
        continue;
      }

      final times = ((data['times'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList()
        ..sort();

      for (final hhmm in times) {
        final id = FinancialService.doseId(med.id, now, hhmm);
        final recorded = byId[id];
        String status = recorded?['status']?.toString() ?? 'pending';

        if (status == 'pending') {
          final parts = hhmm.split(':');
          final hour = int.tryParse(parts.first) ?? 0;
          final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          final scheduled = DateTime(now.year, now.month, now.day, hour, minute);
          if (scheduled.isBefore(now.subtract(const Duration(minutes: 60)))) {
            status = 'missed';
          }
        }
        result.add(_DoseRow(med.id, data, hhmm, status, recorded));
      }
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  Future<void> persistMissedDoses(List<_DoseRow> schedule) async {
    for (final row in schedule) {
      if (row.status != 'missed' || row.record != null) continue;
      try {
        await FinancialService.recordMedicineDose(
          medicineId: row.medicineId,
          medicineName: row.medicine['name']?.toString() ?? '',
          scheduledTime: row.time,
          date: DateTime.now(),
          status: 'missed',
          unitPriceSnapshot:
              (row.medicine['unitPrice'] as num?)?.toDouble() ?? 0,
          unit: row.medicine['unit']?.toString() ?? 'tablet',
        );
      } catch (_) {
        // The deterministic dose ID makes retries safe. A transient write
        // failure should not block the Medicine screen.
      }
    }
  }

  Future<void> markTaken(_DoseRow row) async {
    final scheduledQty =
        (row.medicine['quantityPerDose'] as num?)?.toDouble() ?? 1;
    final quantity = TextEditingController(text: _formatQty(scheduledQty));
    final note = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(EkLanguage.text('Dose Confirmation', 'ডোজ নিশ্চিত করুন')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.medicine['name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '${EkLanguage.text('Scheduled', 'নির্ধারিত')}: $scheduledQty ${row.medicine['unit'] ?? 'tablet'}',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: EkLanguage.text(
                  'How much did you actually take?',
                  'বাস্তবে কতটুকু নিয়েছেন?',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: InputDecoration(
                labelText: EkLanguage.text('Note (optional)', 'নোট (ঐচ্ছিক)'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(EkLanguage.text('Cancel', 'বাতিল')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(EkLanguage.text('Confirm Taken', 'খেয়েছি নিশ্চিত করুন')),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        final actual = double.tryParse(quantity.text.trim()) ?? 0;
        await FinancialService.recordMedicineDose(
          medicineId: row.medicineId,
          medicineName: row.medicine['name']?.toString() ?? '',
          scheduledTime: row.time,
          date: DateTime.now(),
          status: 'taken',
          actualQuantityTaken: actual,
          unitPriceSnapshot:
              (row.medicine['unitPrice'] as num?)?.toDouble() ?? 0,
          unit: row.medicine['unit']?.toString() ?? 'tablet',
          note: note.text.trim(),
        );
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    quantity.dispose();
    note.dispose();
  }

  Future<void> markSkipped(_DoseRow row) async {
    final ok = await confirmAction(
      context,
      title: EkLanguage.text('Skip this dose?', 'এই ডোজ স্কিপ করবেন?'),
      message: EkLanguage.text(
        'Skipped doses create no medicine expense.',
        'স্কিপ করা ডোজে কোনো ওষুধ খরচ যোগ হবে না।',
      ),
      action: EkLanguage.text('Skip', 'স্কিপ'),
    );
    if (!ok) return;
    try {
      await FinancialService.recordMedicineDose(
        medicineId: row.medicineId,
        medicineName: row.medicine['name']?.toString() ?? '',
        scheduledTime: row.time,
        date: DateTime.now(),
        status: 'skipped',
        unitPriceSnapshot:
            (row.medicine['unitPrice'] as num?)?.toDouble() ?? 0,
        unit: row.medicine['unit']?.toString() ?? 'tablet',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> openMedicineMenu(
    QueryDocumentSnapshot<Map<String, dynamic>> medicine,
  ) async {
    final data = medicine.data();
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(EkLanguage.text('Edit Medicine', 'ওষুধ সম্পাদনা')),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: Icon(
              data['paused'] == true
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline,
            ),
            title: Text(
              data['paused'] == true
                  ? EkLanguage.text('Resume Reminders', 'রিমাইন্ডার চালু করুন')
                  : EkLanguage.text('Pause Reminders', 'রিমাইন্ডার বিরতি দিন'),
            ),
            onTap: () => Navigator.pop(context, 'pause'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(EkLanguage.text('View History', 'ইতিহাস দেখুন')),
            onTap: () => Navigator.pop(context, 'history'),
          ),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined, color: Colors.red),
            title: Text(
              EkLanguage.text('Stop Medicine', 'ওষুধ বন্ধ করুন'),
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () => Navigator.pop(context, 'stop'),
          ),
        ],
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      await Navigator.push(
        context,
        GochanoRoute.to(
          builder: (_) => MedicineFormScreen(
            medicineId: medicine.id,
            initialData: data,
          ),
        ),
      );
    } else if (action == 'history') {
      await Navigator.push(
        context,
        GochanoRoute.to(
          builder: (_) => MedicineHistoryScreen(
            medicineId: medicine.id,
            medicine: data,
          ),
        ),
      );
    } else if (action == 'pause') {
      final paused = data['paused'] != true;
      final times = ((data['times'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      await medicine.reference.update({
        'paused': paused,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (paused) {
        await NotificationService.cancelMedicineTimes(medicine.id, times);
      } else {
        for (final time in times) {
          await NotificationService.scheduleDailyMedicine(
            medicineId: medicine.id,
            medicineName: data['name']?.toString() ?? '',
            hhmm: time,
            instruction: data['instruction']?.toString() ?? '',
            quantityPerDose:
                (data['quantityPerDose'] as num?)?.toDouble() ?? 1,
            unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
            unit: data['unit']?.toString() ?? 'tablet',
          );
        }
      }
    } else if (action == 'stop') {
      await stopMedicine(medicine);
    }
  }

  Future<void> stopMedicine(
    QueryDocumentSnapshot<Map<String, dynamic>> medicine,
  ) async {
    var reason = 'Course completed';
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(EkLanguage.text('Stop Medicine', 'ওষুধ বন্ধ করুন')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in [
                  'Course completed',
                  'Doctor advised me to stop',
                  'No longer taking',
                  'Side effect / concern',
                  'Other',
                ])
                  // RadioListTile still uses the legacy groupValue/onChanged
                  // API; ignore the deprecation until Flutter ships an updated
                  // list-tile that participates in RadioGroup.
                  RadioListTile<String>(
                    value: option,
                    // ignore: deprecated_member_use
                    groupValue: reason,
                    title: Text(option),
                    // ignore: deprecated_member_use
                    onChanged: (v) => setLocal(() => reason = v ?? reason),
                  ),
                TextField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: EkLanguage.text('Additional note (optional)', 'অতিরিক্ত নোট (ঐচ্ছিক)'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  EkLanguage.text(
                    'Gochano does not recommend stopping prescribed medicine. Follow professional medical advice.',
                    'Gochano প্রেসক্রাইব করা ওষুধ বন্ধ করার পরামর্শ দেয় না। পেশাদার চিকিৎসা পরামর্শ অনুসরণ করুন।',
                  ),
                  style: const TextStyle(fontSize: 11, color: EkColors.muted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(EkLanguage.text('Cancel', 'বাতিল')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(d, true),
              child: Text(EkLanguage.text('Stop Medicine', 'ওষুধ বন্ধ করুন')),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final data = medicine.data();
      final times = ((data['times'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      await medicine.reference.update({
        'active': false,
        'paused': false,
        'stoppedAt': FieldValue.serverTimestamp(),
        'stopReason': reason,
        'stopNote': note.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await NotificationService.cancelMedicineTimes(medicine.id, times);
    }
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('Medicine', 'ওষুধ')),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: LanguageToggle(),
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('medicines', limit: 200),
          builder: (context, medSnap) {
            if (!medSnap.hasData) return const _MedicineLoadingSkeleton();
            final medicines = medSnap.data!.docs;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.ownerStream('medicine_doses', limit: 500),
              builder: (context, doseSnap) {
                if (!doseSnap.hasData) return const _MedicineLoadingSkeleton();
                final doseDocs = doseSnap.data!.docs
                    .where((d) => d.data()['scheduledDate'] == todayKey())
                    .toList();
                final schedule = rows(medicines, doseDocs);
                if (schedule.any((r) => r.status == 'missed' && r.record == null)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    persistMissedDoses(schedule);
                  });
                }
                final taken = doseDocs.where((d) => d.data()['status'] == 'taken').length;
                final skipped = doseDocs.where((d) => d.data()['status'] == 'skipped').length;
                final cost = doseDocs.fold<double>(
                  0,
                  (acc, d) => acc + ((d.data()['cost'] as num?)?.toDouble() ?? 0),
                );
                final currentMonth = FinancialService.monthKey(DateTime.now());
                final monthlyCost = doseSnap.data!.docs.fold<double>(
                  0,
                  (acc, d) =>
                      d.data()['monthKey'] == currentMonth
                          ? acc +
                              ((d.data()['cost'] as num?)?.toDouble() ?? 0)
                          : acc,
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    _entryMethods(),
                    const SizedBox(height: 18),
                    _summary(
                      taken,
                      skipped,
                      schedule.where((e) => e.status == 'missed').length,
                      cost,
                      monthlyCost,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            EkLanguage.text("Today's Schedule", 'আজকের সময়সূচী'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: medicines.isEmpty
                              ? null
                              : () => Navigator.push(
                                    context,
                                    GochanoRoute.to(
                                      builder: (_) => MedicineHistoryScreen(
                                        medicineId: '',
                                        medicine: const {},
                                      ),
                                    ),
                                  ),
                          child: Text(EkLanguage.text('Full history', 'সম্পূর্ণ ইতিহাস')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (schedule.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              const Text('💊', style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 8),
                              Text(
                                EkLanguage.text(
                                  'No active medicine schedule today.',
                                  'আজ কোনো সক্রিয় ওষুধের সময়সূচী নেই।',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < schedule.length; i++) ...[
                              _doseTile(schedule[i]),
                              if (i != schedule.length - 1) const Divider(height: 1, indent: 72),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      EkLanguage.text('My Medicines', 'আমার ওষুধ'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    if (medicines.isEmpty)
                      _MedicineEmptyState(
                        onAddManual: () => Navigator.push(
                          context,
                          GochanoRoute.to(
                              builder: (_) => const MedicineFormScreen()),
                        ),
                        onScan: () => Navigator.push(
                          context,
                          GochanoRoute.to(
                              builder: (_) => const MedicineOcrScreen()),
                        ),
                      )
                    else
                      for (final med in medicines)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F8F3),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text('💊', style: TextStyle(fontSize: 25)),
                            ),
                            title: Text(
                              med.data()['name']?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              [
                                med.data()['instruction']?.toString() ?? '',
                                '${_formatQty((med.data()['quantityPerDose'] as num?)?.toDouble() ?? 1)} ${med.data()['unit'] ?? 'tablet'}',
                                med.data()['active'] == true
                                    ? (med.data()['paused'] == true ? 'Paused' : 'Active')
                                    : 'Stopped',
                              ].where((e) => e.isNotEmpty).join(' • '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => openMedicineMenu(med),
                          ),
                        ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _entryMethods() {
    return Row(
      children: [
        Expanded(
          child: _entryCard(
            icon: Icons.add,
            title: EkLanguage.text('Add Manually', 'ম্যানুয়ালি যোগ'),
            subtitle: EkLanguage.text('Add medicine yourself', 'নিজে ওষুধ যোগ করুন'),
            color: const Color(0xFFEAF3FF),
            onTap: () => Navigator.push(
              context,
              GochanoRoute.to(builder: (_) => const MedicineFormScreen()),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _entryCard(
            icon: Icons.document_scanner_outlined,
            title: EkLanguage.text('Scan Prescription', 'প্রেসক্রিপশন স্ক্যান'),
            subtitle: EkLanguage.text('OCR suggestions', 'OCR পরামর্শ'),
            color: const Color(0xFFF1ECFF),
            onTap: () => Navigator.push(
              context,
              GochanoRoute.to(builder: (_) => const MedicineOcrScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _entryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 116,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: EkColors.purple),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: EkColors.muted)),
          ],
        ),
      ),
    );
  }

Widget _summary(int taken, int skipped, int missed, double cost, double monthlyCost) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2EFE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _miniStat(EkLanguage.text('Taken', 'খেয়েছি'), taken.toString(), const Color(0xFF1F9A50))),
              Expanded(child: _miniStat(EkLanguage.text('Skipped', 'স্কিপ'), skipped.toString(), const Color(0xFFE19B22))),
              Expanded(child: _miniStat(EkLanguage.text('Missed', 'মিসড'), missed.toString(), const Color(0xFFD84A4A))),
              Expanded(child: _miniStat(EkLanguage.text('Cost', 'খরচ'), '৳${cost.toStringAsFixed(0)}', EkColors.purple)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE6FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: EkColors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    EkLanguage.text('This month', 'এই মাসে'),
                    style: const TextStyle(fontSize: 12, color: EkColors.muted, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '৳${monthlyCost.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: EkColors.purple),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: EkColors.muted)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        ],
      );

  Widget _doseTile(_DoseRow row) {
    Color color;
    switch (row.status) {
      case 'taken':
        color = const Color(0xFF1F9A50);
        break;
      case 'skipped':
        color = const Color(0xFFE19B22);
        break;
      case 'missed':
        color = const Color(0xFFD84A4A);
        break;
      default:
        color = EkColors.muted;
    }

    return ListTile(
      leading: SizedBox(
        width: 52,
        child: Text(
          _displayTime(row.time),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(
        row.medicine['name']?.toString() ?? '',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        [
          row.medicine['instruction']?.toString() ?? '',
          '${_formatQty((row.medicine['quantityPerDose'] as num?)?.toDouble() ?? 1)} ${row.medicine['unit'] ?? 'tablet'}',
        ].where((e) => e.isNotEmpty).join(' • '),
      ),
      trailing: row.status == 'pending' || row.status == 'missed'
          ? Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => markSkipped(row),
                  child: Text(EkLanguage.text('Skip', 'স্কিপ')),
                ),
                FilledButton(
                  onPressed: () => markTaken(row),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 38),
                    backgroundColor: const Color(0xFF1F9A50),
                  ),
                  child: Text(EkLanguage.text('Taken', 'খেয়েছি')),
                ),
              ],
            )
          : Chip(
              label: Text(
                row.status.toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10),
              ),
              backgroundColor: color.withValues(alpha: .08),
              side: BorderSide(color: color.withValues(alpha: .2)),
            ),
    );
  }

  String _displayTime(String hhmm) {
    try {
      final p = hhmm.split(':');
      final dt = DateTime(2020, 1, 1, int.parse(p[0]), int.parse(p[1]));
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return hhmm;
    }
  }

  static String _formatQty(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
}

class _DoseRow {
  const _DoseRow(
    this.medicineId,
    this.medicine,
    this.time,
    this.status,
    this.record,
  );

  final String medicineId;
  final Map<String, dynamic> medicine;
  final String time;
  final String status;
  final Map<String, dynamic>? record;
}

class _MedicineLoadingSkeleton extends StatelessWidget {
  const _MedicineLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
      children: [
        Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              Expanded(child: _skeletonBox(height: 116, radius: 18)),
              if (i == 0) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 18),
        _skeletonBox(height: 110, radius: 18),
        const SizedBox(height: 18),
        _skeletonBox(height: 22, width: 180),
        const SizedBox(height: 10),
        _skeletonBox(height: 130, radius: 18),
        const SizedBox(height: 18),
        _skeletonBox(height: 22, width: 140),
        const SizedBox(height: 10),
        for (var i = 0; i < 3; i++) ...[
          _skeletonBox(height: 78, radius: 16),
          if (i != 2) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _skeletonBox({required double height, double? width, double radius = 12}) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDF2),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _MedicineEmptyState extends StatelessWidget {
  const _MedicineEmptyState({
    required this.onAddManual,
    required this.onScan,
  });

  final VoidCallback onAddManual;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      module: 'medicine',
      title: EkLanguage.text(
        'No medicines yet.',
        'এখনও কোনো ওষুধ যোগ করা হয়নি।',
      ),
      message: EkLanguage.text(
        'Add medicine manually or scan a prescription to get started.',
        'ম্যানুয়ালি ওষুধ যোগ করুন অথবা প্রেসক্রিপশন স্ক্যান করে শুরু করুন।',
      ),
      primaryActionLabel: EkLanguage.text('Add manually', 'ম্যানুয়ালি যোগ করুন'),
      onPrimaryAction: onAddManual,
      secondaryActionLabel: EkLanguage.text('Scan prescription', 'প্রেসক্রিপশন স্ক্যান করুন'),
      onSecondaryAction: onScan,
    );
  }
}
