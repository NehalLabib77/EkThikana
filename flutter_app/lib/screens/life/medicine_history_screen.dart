import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../services/firestore_service.dart';

class MedicineHistoryScreen extends StatelessWidget {
  const MedicineHistoryScreen({
    super.key,
    required this.medicineId,
    required this.medicine,
  });

  final String medicineId;
  final Map<String, dynamic> medicine;

  @override
  Widget build(BuildContext context) {
    final stream = FirestoreService.ownerStream('medicine_doses', limit: 1000);
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Text(
            medicineId.isEmpty
                ? EkLanguage.text('Medicine History', 'ওষুধের ইতিহাস')
                : medicine['name']?.toString() ?? 'Medicine History',
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var docs = snap.data!.docs;
            if (medicineId.isNotEmpty) {
              docs = docs.where((d) => d.data()['medicineId'] == medicineId).toList();
            }
            docs.sort((a, b) {
              final ad = a.data()['date'] as Timestamp?;
              final bd = b.data()['date'] as Timestamp?;
              return (bd?.millisecondsSinceEpoch ?? 0)
                  .compareTo(ad?.millisecondsSinceEpoch ?? 0);
            });

            final taken = docs.where((d) => d.data()['status'] == 'taken').length;
            final skipped = docs.where((d) => d.data()['status'] == 'skipped').length;
            final missed = docs.where((d) => d.data()['status'] == 'missed').length;
            final cost = docs.fold<double>(
              0,
              (sum, d) => sum + ((d.data()['cost'] as num?)?.toDouble() ?? 0),
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBF4),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _stat(EkLanguage.text('Taken', 'খেয়েছি'), '$taken')),
                      Expanded(child: _stat(EkLanguage.text('Skipped', 'স্কিপ'), '$skipped')),
                      Expanded(child: _stat(EkLanguage.text('Missed', 'মিসড'), '$missed')),
                      Expanded(child: _stat(EkLanguage.text('Cost', 'খরচ'), '৳${cost.toStringAsFixed(0)}')),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (docs.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(EkLanguage.text('No dose history yet.', 'এখনও কোনো ডোজের ইতিহাস নেই।')),
                    ),
                  )
                else
                  for (final doc in docs)
                    _historyCard(doc.data()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: EkColors.muted)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ],
      );

  Widget _historyCard(Map<String, dynamic> d) {
    final date = d['date'] is Timestamp
        ? (d['date'] as Timestamp).toDate()
        : DateTime.now();
    final status = d['status']?.toString() ?? 'pending';
    Color statusColor;
    switch (status) {
      case 'taken':
        statusColor = const Color(0xFF1F9A50);
        break;
      case 'skipped':
        statusColor = const Color(0xFFE19B22);
        break;
      case 'missed':
        statusColor = const Color(0xFFD84A4A);
        break;
      default:
        statusColor = EkColors.muted;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: .10),
          child: const Text('💊'),
        ),
        title: Text(
          d['medicineName']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            '${DateFormat('dd MMM yyyy').format(date)} • ${d['scheduledTime'] ?? ''}',
            if (status == 'taken')
              '${d['actualQuantityTaken'] ?? 0} ${d['unit'] ?? ''} • ৳${((d['cost'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
          ].join('\n'),
        ),
        trailing: Chip(
          label: Text(
            status.toUpperCase(),
            style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w800),
          ),
          backgroundColor: statusColor.withValues(alpha: .08),
          side: BorderSide(color: statusColor.withValues(alpha: .18)),
        ),
      ),
    );
  }
}
