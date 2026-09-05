// Medicine (spec §52, §53, §58, §59).
//
// Priority order on this screen is fixed by spec §52: today's doses first,
// then the next reminder, then taken/skipped, then history and the two ways
// to add a medicine.
//
// Two safety rules are structural, not cosmetic:
//   * **Manual entry is always available** and is the primary action. Scanning
//     is the secondary one. A student must never be forced through OCR to
//     record a medicine (spec §52).
//   * **Gochano never decides anything medical.** It shows the times the
//     student saved and records what they say they did. There is no inferred
//     dose, no inferred schedule and no medical advice anywhere in this
//     feature (spec §57, §58).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_dates.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/financial_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../domain/medicine_schedule.dart';
import 'medicine_form_screen.dart';
import 'medicine_history_screen.dart';
import 'prescription_scan_screen.dart';

class MedicineScreen extends StatelessWidget {
  const MedicineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Medicine', 'ওষুধ'),
        actions: [
          IconActionButton(
            icon: Icons.history_rounded,
            label: GochanoLanguage.text('History', 'ইতিহাস'),
            onPressed: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const MedicineHistoryScreen()),
            ),
          ),
        ],
      ),
      body: const _MedicineBody(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'medicine-scan-prescription',
            tooltip: GochanoLanguage.text(
              'Scan prescription',
              'প্রেসক্রিপশন স্ক্যান',
            ),
            onPressed: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const PrescriptionScanScreen()),
            ),
            child: const Icon(Icons.document_scanner_outlined),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          FloatingActionButton.extended(
            heroTag: 'medicine-add',
            onPressed: () => Navigator.of(
              context,
            ).push(GochanoRoute.to(builder: (_) => const MedicineFormScreen())),
            icon: const Icon(Icons.add_rounded),
            label: Text(GochanoLanguage.text('Add medicine', 'ওষুধ যোগ')),
          ),
        ],
      ),
    );
  }
}

class _MedicineBody extends StatelessWidget {
  const _MedicineBody();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('medicines', limit: 200),
      builder: (context, medSnapshot) {
        if (medSnapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading your medicines…',
              'আপনার ওষুধ লোড হচ্ছে…',
            ),
          );
        }
        if (medSnapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(medSnapshot.error));
        }

        final medicines = [...?medSnapshot.data?.docs];
        if (medicines.isEmpty) {
          return EmptyState(
            illustration: GochanoArt.emptyMedicines,
            title: GochanoLanguage.text(
              'No medicines yet',
              'এখনো কোনো ওষুধ নেই',
            ),
            message: GochanoLanguage.text(
              'Add a medicine to get reminders at the times you choose.',
              'রিমাইন্ডার পেতে একটি ওষুধ যোগ করুন এবং সময় নির্ধারণ করুন।',
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('medicine_doses', limit: 500),
          builder: (context, doseSnapshot) {
            final doses = [...?doseSnapshot.data?.docs];
            final schedule = MedicineSchedule.forDay(medicines, doses);
            final actionableDoses = MedicineSchedule.actionable(schedule);
            final counts = MedicineSchedule.counts(schedule);
            final next = MedicineSchedule.next(schedule);

            return ListView(
              padding: GochanoSpacing.scrollBody,
              children: [
                if (next != null) _NextReminderCard(dose: next),
                if (next != null) const SizedBox(height: GochanoSpacing.md),

                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        compact: true,
                        label: GochanoLanguage.text('Taken', 'নেওয়া হয়েছে'),
                        value: '${counts.taken}',
                        accent: context.colors.success,
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: StatCard(
                        compact: true,
                        label: GochanoLanguage.text('Skipped', 'বাদ'),
                        value: '${counts.skipped}',
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: StatCard(
                        compact: true,
                        label: GochanoLanguage.text('Missed', 'মিস'),
                        value: '${counts.missed}',
                        accent: counts.missed > 0
                            ? context.colors.warning
                            : null,
                      ),
                    ),
                  ],
                ),

                SectionHeader(
                  title: GochanoLanguage.text("Today's doses", 'আজকের ডোজ'),
                ),
                if (actionableDoses.isEmpty)
                  AppCard(
                    child: Text(
                      GochanoLanguage.text(
                        'None of your medicines are scheduled for today.',
                        'আজ আপনার কোনো ওষুধের সময় নির্ধারিত নেই।',
                      ),
                      style: context.type.bodySecondary,
                    ),
                  )
                else
                  CardGroup(
                    children: [
                      for (final dose in actionableDoses) _DoseRow(dose: dose),
                    ],
                  ),

                SectionHeader(
                  title: GochanoLanguage.text('Your medicines', 'আপনার ওষুধ'),
                ),
                CardGroup(
                  children: [
                    for (final med in medicines) _MedicineRow(doc: med),
                  ],
                ),

                const SizedBox(height: GochanoSpacing.md),
                const _MedicalDisclaimer(),
              ],
            );
          },
        );
      },
    );
  }
}

/// The next dose still needing action.
class _NextReminderCard extends StatelessWidget {
  const _NextReminderCard({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overdue = dose.status == DoseStatus.missed;

    return AppCard(
      accent: overdue ? colors.warning : colors.medicine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  overdue
                      ? GochanoLanguage.text('Overdue dose', 'সময় পেরোনো ডোজ')
                      : GochanoLanguage.text(
                          'Next reminder',
                          'পরবর্তী রিমাইন্ডার',
                        ),
                  style: context.type.label,
                ),
              ),
              Text(formatTime12(dose.time), style: context.type.statisticSmall),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          Text(
            '${dose.medicineName}'
            '${dose.strength.isEmpty ? '' : ' · ${dose.strength}'}',
            style: context.type.sectionHeading,
          ),
          if (dose.instruction.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(dose.instruction, style: context.type.bodySecondary),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: GochanoLanguage.text('Taken', 'নিয়েছি'),
                  icon: Icons.check_rounded,
                  onPressed: () => _recordDose(context, dose, DoseStatus.taken),
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: SecondaryButton(
                  label: GochanoLanguage.text('Skip', 'বাদ'),
                  onPressed: () =>
                      _recordDose(context, dose, DoseStatus.skipped),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (illustration, accent, badge) = switch (dose.status) {
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
      DoseStatus.missed => (
        GochanoArt.featureReminder,
        colors.warning,
        GochanoBadge(
          label: GochanoLanguage.text('Missed', 'মিস'),
          tone: GochanoBadgeTone.warning,
          icon: Icons.schedule_rounded,
        ),
      ),
      DoseStatus.pending => (
        GochanoArt.featureMedicine,
        colors.medicine,
        GochanoBadge(
          label: formatTime12(dose.time),
          tone: GochanoBadgeTone.info,
          icon: Icons.access_time_rounded,
        ),
      ),
    };

    return GochanoListRow(
      illustration: illustration,
      accent: accent,
      title: dose.medicineName,
      subtitle: dose.strength.isEmpty ? dose.instruction : dose.strength,
      metadata: [formatTime12(dose.time)],
      badge: badge,
      menuItems: dose.needsAction
          ? [
              GochanoMenuAction(
                label: GochanoLanguage.text('Mark taken', 'নেওয়া হয়েছে'),
                icon: Icons.check_rounded,
                onSelected: () => _recordDose(context, dose, DoseStatus.taken),
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Skip', 'বাদ দিন'),
                icon: Icons.remove_rounded,
                onSelected: () =>
                    _recordDose(context, dose, DoseStatus.skipped),
              ),
            ]
          : null,
    );
  }
}

class _MedicineRow extends StatelessWidget {
  const _MedicineRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final times =
        ((data['times'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    final paused = data['paused'] == true || data['active'] != true;

    return GochanoListRow(
      illustration: GochanoArt.featureMedicine,
      accent: paused ? context.colors.textTertiary : context.colors.medicine,
      title: data['name']?.toString() ?? '',
      subtitle: data['strength']?.toString(),
      metadata: [
        if (times.isNotEmpty) times.map(formatTime12).join(', '),
        if (data['instruction']?.toString().isNotEmpty ?? false)
          data['instruction'].toString(),
      ],
      badge: paused
          ? GochanoBadge(
              label: GochanoLanguage.text('Paused', 'বিরতি'),
              icon: Icons.pause_rounded,
            )
          : null,
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(builder: (_) => MedicineFormScreen(medicineId: doc.id)),
      ),
      menuItems: [
        GochanoMenuAction(
          label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
          icon: Icons.edit_outlined,
          onSelected: () => Navigator.of(context).push(
            GochanoRoute.to(
              builder: (_) => MedicineFormScreen(medicineId: doc.id),
            ),
          ),
        ),
        GochanoMenuAction(
          label: paused
              ? GochanoLanguage.text('Resume reminders', 'রিমাইন্ডার চালু')
              : GochanoLanguage.text('Pause reminders', 'রিমাইন্ডার বিরতি'),
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          onSelected: () => doc.reference.update({
            'paused': !paused,
            'active': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }),
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Delete medicine', 'ওষুধ মুছুন'),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => _confirmAndDeleteMedicine(
            context,
            medicineId: doc.id,
            medicineName: data['name']?.toString() ?? '',
            // Pass the times too so we can cancel any scheduled OS
            // notifications *before* the document goes — once the doc is
            // deleted those times are no longer in the DB to look up.
            times: times,
          ),
        ),
      ],
    );
  }
}

/// Records a dose.
///
/// The cost mirror is deliberate and narrow: only a **taken** dose creates a
/// ledger entry, priced from the medicine's own unit price. Skipping or
/// missing a dose costs nothing and writes nothing to the ledger (spec §36).
Future<void> _recordDose(
  BuildContext context,
  ScheduledDose dose,
  DoseStatus status,
) async {
  final quantity =
      (dose.medicine['quantityPerDose'] as num?)?.toDouble() ?? 1.0;
  try {
    await FinancialService.recordMedicineDose(
      medicineId: dose.medicineId,
      medicineName: dose.medicineName,
      scheduledTime: dose.time,
      date: DateTime.now(),
      status: status.id,
      actualQuantityTaken: status == DoseStatus.taken ? quantity : 0,
      unitPriceSnapshot: dose.unitPrice,
      unit: dose.unit,
    );
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

/// Confirm with the user, then cascade-delete a medicine.
///
/// The cascade is irreversible by design: deleting a medicine removes every
/// ``medicine_doses`` row whose ``medicineId`` matches, plus any
/// ``financial_transactions`` mirror rows that were created when those
/// doses were marked taken. The user must type "DELETE" so a stray tap on
/// the 3-dot menu does not erase a year of adherence history.
///
/// Cancellation runs **before** the cascade-delete, not after. The
/// notifications are scheduled in Android's AlarmManager and not tied to
/// Firestore, so removing the Firestore rows first would leave reminders
/// firing for a medicine that no longer exists.
Future<void> _confirmAndDeleteMedicine(
  BuildContext context, {
  required String medicineId,
  required String medicineName,
  required List<String> times,
}) async {
  if (medicineId.isEmpty) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final controller = TextEditingController();
      final colors = dialogContext.colors;
      return StatefulBuilder(
        builder: (innerContext, setLocal) {
          final canConfirm = controller.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            title: Text(
              GochanoLanguage.text(
                'Delete this medicine?',
                'এই ওষুধ মুছে ফেলবেন?',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicineName.isEmpty
                        ? GochanoLanguage.text(
                            'This will permanently remove the medicine, '
                                'every dose record, and any expense entry it '
                                'created.',
                            'এটি ওষুধটি, প্রতিটি ডোজের রেকর্ড এবং এটি থেকে '
                                'তৈরি হওয়া যেকোনো খরচের এন্ট্রি স্থায়ীভাবে '
                                'মুছে ফেলবে।',
                          )
                        : GochanoLanguage.text(
                            'This will permanently remove "$medicineName", '
                                'every dose record, and any expense entry it '
                                'created.',
                            '"$medicineName", প্রতিটি ডোজের রেকর্ড এবং '
                                'এটি থেকে তৈরি হওয়া যেকোনো খরচের এন্ট্রি '
                                'স্থায়ীভাবে মুছে যাবে।',
                          ),
                    style: innerContext.type.body,
                  ),
                  const SizedBox(height: GochanoSpacing.md),
                  Text(
                    GochanoLanguage.text(
                      'Type DELETE to confirm.',
                      'নিশ্চিত করতে DELETE লিখুন।',
                    ),
                    style: innerContext.type.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      hintText: 'DELETE',
                      hintStyle: TextStyle(color: colors.textTertiary),
                    ),
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  Text(
                    GochanoLanguage.text(
                      'Gochano does not recommend stopping prescribed '
                          'medicine. Follow professional medical advice.',
                      'গোছানো প্রেসক্রাইব করা ওষুধ বন্ধ করার পরামর্শ '
                          'দেয় না। পেশাদার চিকিৎসা পরামর্শ অনুসরণ করুন।',
                    ),
                    style: innerContext.type.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: colors.error),
                onPressed: canConfirm
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(GochanoLanguage.text('Delete', 'মুছুন')),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  // Cancel any OS-scheduled reminders first. Done before the cascade so the
  // phone cannot fire a stray notification between this call returning and
  // the dose rows going.
  if (times.isNotEmpty) {
    await NotificationService.cancelMedicineTimes(medicineId, times);
  }
  if (!context.mounted) return;

  try {
    await FinancialService.deleteMedicine(medicineId);
    if (!context.mounted) return;
    showGochanoMessage(
      context,
      GochanoLanguage.text('Medicine deleted.', 'ওষুধ মুছে ফেলা হয়েছে।'),
    );
  } catch (error) {
    if (!context.mounted) return;
    showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
  }
}

/// Spec §58 — the app must never look like it is giving medical advice.
class _MedicalDisclaimer extends StatelessWidget {
  const _MedicalDisclaimer();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: GochanoSizes.iconSm,
            color: colors.textSecondary,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Text(
              GochanoLanguage.text(
                'Gochano does not provide medical advice. It only reminds you '
                    'of the times you saved and records what you mark.',
                'গোছানো কোনো চিকিৎসা পরামর্শ দেয় না। এটি শুধু আপনার সংরক্ষণ করা সময়ে মনে করিয়ে দেয় এবং আপনি যা চিহ্নিত করেন তা রেকর্ড করে।',
              ),
              style: context.type.caption,
            ),
          ),
        ],
      ),
    );
  }
}
