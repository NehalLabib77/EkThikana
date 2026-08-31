// Medicine history (spec §52, §59).
//
// A record of what the student marked, grouped by day. Nothing here is
// derived or inferred: every row is a `medicine_doses` document that exists
// because a dose was marked taken, skipped, or aged past its time.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../domain/medicine_schedule.dart';

class MedicineHistoryScreen extends StatelessWidget {
  const MedicineHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Medicine history', 'ওষুধের ইতিহাস'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('medicine_doses', limit: 500),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text(
                'Loading your history…',
                'আপনার ইতিহাস লোড হচ্ছে…',
              ),
            );
          }
          if (snapshot.hasError) {
            return ErrorState(message: friendlyErrorMessage(snapshot.error));
          }

          final docs = [...?snapshot.data?.docs];
          if (docs.isEmpty) {
            return EmptyState(
              illustration: GochanoArt.emptyMedicines,
              title: GochanoLanguage.text(
                'No doses recorded yet',
                'এখনো কোনো ডোজ রেকর্ড হয়নি',
              ),
              message: GochanoLanguage.text(
                'Doses you mark taken or skipped will appear here.',
                'আপনি যেসব ডোজ নেওয়া বা বাদ চিহ্নিত করবেন সেগুলো এখানে দেখা যাবে।',
              ),
            );
          }

          // Group by the date the dose was scheduled for.
          final byDay = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final doc in docs) {
            final day = doc.data()['scheduledDate']?.toString() ?? '';
            if (day.isEmpty) continue;
            byDay.putIfAbsent(day, () => []).add(doc);
          }
          final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: GochanoSpacing.scrollBody,
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final entries = byDay[day]!
                ..sort((a, b) => (a.data()['scheduledTime']?.toString() ?? '')
                    .compareTo(b.data()['scheduledTime']?.toString() ?? ''));
              final taken = entries
                  .where((d) => d.data()['status'] == 'taken')
                  .length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: _dayLabel(day),
                    action: Text(
                      GochanoLanguage.text(
                        '$taken of ${entries.length} taken',
                        '${entries.length} টির মধ্যে $taken টি নেওয়া',
                      ),
                      style: context.type.caption,
                    ),
                    padding: const EdgeInsets.only(
                      top: GochanoSpacing.md,
                      bottom: GochanoSpacing.xs,
                    ),
                  ),
                  CardGroup(
                    children: [for (final doc in entries) _HistoryRow(doc: doc)],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = doc.data();
    final status = DoseStatus.parse(data['status']?.toString());
    final time = data['scheduledTime']?.toString() ?? '';

    final (illustration, accent, badge) = switch (status) {
      DoseStatus.taken => (
          GochanoArt.stateTaken,
          colors.success,
          GochanoBadge(
            label: GochanoLanguage.text('Taken', 'নেওয়া হয়েছে'),
            tone: GochanoBadgeTone.success,
            icon: Icons.check_rounded,
          ),
        ),
      DoseStatus.skipped => (
          GochanoArt.stateSkipped,
          colors.textSecondary,
          GochanoBadge(
            label: GochanoLanguage.text('Skipped', 'বাদ দেওয়া'),
            icon: Icons.remove_rounded,
          ),
        ),
      _ => (
          GochanoArt.featureReminder,
          colors.warning,
          GochanoBadge(
            label: GochanoLanguage.text('Missed', 'মিস'),
            tone: GochanoBadgeTone.warning,
            icon: Icons.schedule_rounded,
          ),
        ),
    };

    return GochanoListRow(
      illustration: illustration,
      accent: accent,
      title: data['medicineName']?.toString() ?? '',
      metadata: [time],
      badge: badge,
    );
  }
}

/// Turns a `YYYY-MM-DD` key into a readable heading.
String _dayLabel(String dateKey) {
  final parsed = DateTime.tryParse(dateKey);
  if (parsed == null) return dateKey;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(parsed.year, parsed.month, parsed.day)).inDays;
  if (diff == 0) return GochanoLanguage.text('Today', 'আজ');
  if (diff == 1) return GochanoLanguage.text('Yesterday', 'গতকাল');

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}
