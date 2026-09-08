// Home — "what matters to me right now?" (spec §27).
//
// Bento grid layout with accent-rail cards. Each section owns its own stream
// for independent rebuilds (spec §83).
//
// Structure (spec §27):
//   Header → Your Day / Smart Summary → Quick Actions → Today → Upcoming →
//   Study Progress → Money: Remaining + Spent → Recent

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../models/financial_transaction.dart';
import '../../../services/api_service.dart';
import '../../../services/financial_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../life/presentation/expense/add_expense_sheet.dart';
import '../../life/presentation/commute/commute_screen.dart';
import '../../../core/localization/gochano_dates.dart';
import '../../../services/notification_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../life/domain/medicine_schedule.dart';
import '../../life/presentation/medicine/medicine_screen.dart';
import '../../life/presentation/medicine/prescription_scan_screen.dart';
import '../../study/presentation/ai/ai_assistant_screen.dart';
import '../../study/presentation/materials/material_reader_screen.dart';
import '../../tasks/presentation/add_task_sheet.dart';
import '../../../widgets/language_toggle.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.role,
    required this.displayName,
    required this.onOpenDestination,
  });

  final String role;
  final String displayName;
  final ValueChanged<int> onOpenDestination;

  bool get _isStudent => role == 'student';

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: _HomeAppBar(
        actions: const [
          LanguageToggle(),
          SizedBox(width: GochanoSpacing.xs),
        ],
      ),
      body: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _SmartSummaryCard(isStudent: _isStudent),
          const SizedBox(height: GochanoSpacing.sm),
          _QuickActions(isStudent: _isStudent),
          const SizedBox(height: GochanoSpacing.sm),
          _TodaysTasksCard(
            onSeeAll: () => onOpenDestination(_isStudent ? 1 : 2),
          ),
          if (_isStudent) ...[
            const SizedBox(height: GochanoSpacing.sm),
            const _BentoRow(
              left: _StudyProgressCard(),
              right: _MedicineScheduleCard(),
            ),
          ] else ...[
            const SizedBox(height: GochanoSpacing.sm),
            const _MedicineScheduleCard(),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          _RecentMaterialsCard(onOpenStudy: () => onOpenDestination(0)),
        ],
      ),
    );
  }
}

/// Custom AppBar for Home screen showing [circular avatar] DisplayName.
class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBar({this.actions});

  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return AppBar(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: GochanoSpacing.md,
      title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.profileStream(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final photoURL = data?['photoURL'] as String?;
          final displayName = (data?['displayName'] as String?)?.trim() ?? '';

          return Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: colors.brand,
                backgroundImage: photoURL != null && photoURL.isNotEmpty
                    ? NetworkImage(photoURL)
                    : null,
                child: photoURL == null || photoURL.isEmpty
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: type.pageTitle.copyWith(
                          color: colors.onBrand,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Text(
                  displayName.isNotEmpty ? displayName : displayName,
                  style: type.pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
      actions: actions,
    );
  }
}

// ---------------------------------------------------------------------------
// Bento grid helpers
// ---------------------------------------------------------------------------

class _BentoRow extends StatelessWidget {
  const _BentoRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  static const double _minCardHeight = 120;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minCardHeight),
            child: left,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minCardHeight),
            child: right,
          ),
        ),
      ],
    );
  }
}

/// Accent-rail card: a thin coloured strip on the leading edge of a bordered
/// card, following the Gochano flat-surface spec (border, no shadow).
class _AccentRailCard extends StatelessWidget {
  const _AccentRailCard({
    required this.accent,
    required this.child,
    this.onTap,
    this.padding,
  });

  final Color accent;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: GochanoRadius.lgAll,
          border: Border.all(
            color: colors.border,
            width: GochanoBorders.hairline,
          ),
        ),
        child: ClipRRect(
          borderRadius: GochanoRadius.lgAll,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 3, child: ColoredBox(color: accent)),
              Expanded(
                child: Padding(
                  padding: padding ?? GochanoSpacing.card,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Smart summary
// ---------------------------------------------------------------------------

class _SmartSummaryCard extends StatelessWidget {
  const _SmartSummaryCard({required this.isStudent});

  final bool isStudent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 100),
      builder: (context, taskSnap) {
        if (taskSnap.connectionState == ConnectionState.waiting) {
          return const _SectionSkeleton();
        }
        if (taskSnap.hasError) {
          return _AccentRailCard(
            accent: colors.brand,
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.md,
              vertical: GochanoSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  GochanoLanguage.text('Your Day', 'আপনার দিন'),
                  style: context.type.sectionHeading,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          'Unable to load summary',
                          'সারসংক্ষেপ লোড হয়নি',
                        ),
                        style: context.type.bodySecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        final taskDocs = [...?taskSnap.data?.docs];
        final now = DateTime.now();
        final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
        var todayCount = 0;
        var overdueCount = 0;
        for (final doc in taskDocs) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          if (due.isBefore(now)) overdueCount++;
          if (due.isBefore(endOfToday)) todayCount++;
        }

        return StreamBuilder<List<FinancialTransactionModel>>(
          stream: FinancialService.monthStream(now),
          builder: (context, moneySnap) {
            if (moneySnap.connectionState == ConnectionState.waiting) {
              return const _SectionSkeleton();
            }
            if (moneySnap.hasError) {
              return _AccentRailCard(
                accent: colors.brand,
                padding: const EdgeInsets.symmetric(
                  horizontal: GochanoSpacing.md,
                  vertical: GochanoSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      GochanoLanguage.text('Your Day', 'আপনার দিন'),
                      style: context.type.sectionHeading,
                    ),
                    const SizedBox(height: GochanoSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              'Unable to load spending',
                              'খরচ লোড হয়নি',
                            ),
                            style: context.type.bodySecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
            final items = moneySnap.data ?? const <FinancialTransactionModel>[];
            final today = FinancialService.dateKey(now);
            final todaySpent = items
                .where((e) => FinancialService.dateKey(e.date) == today)
                .fold<double>(0, (running, e) => running + e.amount);

            return _AccentRailCard(
              accent: colors.brand,
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.md,
                vertical: GochanoSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    GochanoLanguage.text('Your Day', 'আপনার দিন'),
                    style: context.type.sectionHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Wrap(
                    spacing: GochanoSpacing.xs,
                    runSpacing: GochanoSpacing.xs,
                    children: [
                      _SummaryPill(
                        icon: Icons.task_alt_rounded,
                        label: GochanoLanguage.text(
                          '$todayCount tasks',
                          '$todayCount টি কাজ',
                        ),
                        color: todayCount > 0 ? colors.brand : colors.success,
                      ),
                      _SummaryPill(
                        icon: Icons.receipt_long_rounded,
                        label: formatTaka(todaySpent),
                        color: colors.expense,
                      ),
                      if (overdueCount > 0)
                        _SummaryPill(
                          icon: Icons.warning_amber_rounded,
                          label: GochanoLanguage.text(
                            '$overdueCount overdue',
                            '$overdueCount টি বাকি',
                          ),
                          color: colors.warning,
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: GochanoRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today's tasks
// ---------------------------------------------------------------------------

class _TodaysTasksCard extends StatelessWidget {
  const _TodaysTasksCard({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 100),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AccentRailCard(
            accent: colors.brand,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.today_rounded, size: 18, color: colors.brand),
                    const SizedBox(width: GochanoSpacing.xs),
                    Text(
                      GochanoLanguage.text("Today", 'আজ'),
                      style: context.type.sectionHeading,
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          'Unable to load tasks',
                          'কাজ লোড হয়নি',
                        ),
                        style: context.type.bodySecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SectionSkeleton();
        }

        final now = DateTime.now();
        final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
        final open = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        var overdue = 0;

        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          if (due.isBefore(now)) overdue++;
          if (due.isBefore(endOfToday)) open.add(doc);
        }
        open.sort(_byDueAtAsc);

        return _AccentRailCard(
          accent: colors.brand,
          onTap: onSeeAll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.today_rounded, size: 18, color: colors.brand),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text("Today", 'আজ'),
                      style: context.type.sectionHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (overdue > 0) ...[
                    const SizedBox(width: GochanoSpacing.xs),
                    GochanoBadge(
                      label: GochanoLanguage.text(
                        '$overdue overdue',
                        '$overdue টি বাকি',
                      ),
                      tone: GochanoBadgeTone.warning,
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              if (open.isEmpty)
                Row(
                  children: [
                    GochanoIllustration(
                      GochanoArt.emptyTasks,
                      size: 28,
                      accent: colors.textTertiary,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text('All clear today.', 'আজ ফাঁকা।'),
                        style: context.type.bodySecondary,
                      ),
                    ),
                  ],
                )
              else
                for (final doc in open.take(3))
                  _TaskLine(doc: doc, isLast: doc == open.take(3).last),
              if (open.length > 3) ...[
                const SizedBox(height: GochanoSpacing.xxs),
                Text(
                  GochanoLanguage.text(
                    '+${open.length - 3} more',
                    'আরও ${open.length - 3} টি',
                  ),
                  style: context.type.caption,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming tasks (removed — Home now shows a single full-width Today card)
// ---------------------------------------------------------------------------

/// A single task row with a working checkbox.
class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.doc, required this.isLast});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = data['title']?.toString() ?? '';
    final due = (data['dueAt'] as Timestamp?)?.toDate();
    final isOverdue = due != null && due.isBefore(DateTime.now());

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : GochanoSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: false,
              onChanged: (_) => doc.reference.update({
                'done': true,
                'updatedAt': FieldValue.serverTimestamp(),
              }),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          Expanded(
            child: Text(
              title,
              style: context.type.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (due != null)
            Flexible(
              child: Text(
                _timeLabel(due),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.caption.copyWith(
                  color: isOverdue ? context.colors.warning : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Study progress (student only)
// ---------------------------------------------------------------------------

class _StudyProgressCard extends StatefulWidget {
  const _StudyProgressCard();

  @override
  State<_StudyProgressCard> createState() => _StudyProgressCardState();
}

class _StudyProgressCardState extends State<_StudyProgressCard> {
  Map<String, dynamic>? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await ApiService.getStudyStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = GochanoLanguage.text(
            'Unable to load study stats',
            'পড়ার পরিসংখ্যান লোড হয়নি',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    int read(String camel, String snake) {
      if (_stats == null) return 0;
      final raw = _stats![camel] ?? _stats![snake];
      return raw is num ? raw.toInt() : 0;
    }

    final todayMinutes = (read('todaySeconds', 'today_seconds') / 60).round();
    final streak = read('streakDays', 'streak_days');

    return _AccentRailCard(
      accent: colors.study,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.school_rounded, size: 18, color: colors.study),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Study Progress', 'পড়ার অগ্রগতি'),
                  style: context.type.sectionHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if (_error != null)
            Row(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Text(_error!, style: context.type.bodySecondary),
                ),
              ],
            )
          else if (_stats == null)
            Text(
              GochanoLanguage.text('Loading…', 'লোড হচ্ছে…'),
              style: context.type.bodySecondary,
            )
          else
            Row(
              children: [
                Expanded(
                  child: _StatPill(
                    label: GochanoLanguage.text('Today', 'আজ'),
                    value: GochanoLanguage.text(
                      '$todayMinutes min',
                      '$todayMinutes মি',
                    ),
                    color: colors.study,
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: _StatPill(
                    label: GochanoLanguage.text('Streak', 'ধারা'),
                    value: GochanoLanguage.text('$streak d', '$streak দি'),
                    color: colors.ai,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: GochanoRadius.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.type.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.type.cardHeading.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Medicine Schedule Bento Card
// ---------------------------------------------------------------------------

class _MedicineScheduleCard extends StatefulWidget {
  const _MedicineScheduleCard();

  @override
  State<_MedicineScheduleCard> createState() => _MedicineScheduleCardState();
}

class _MedicineScheduleCardState extends State<_MedicineScheduleCard> {
  final Set<String> _processingDoses = <String>{};

  Future<void> _onMarkTaken(ScheduledDose dose) async {
    final doseKey = '${dose.medicineId}_${dose.time}';
    if (_processingDoses.contains(doseKey)) return;
    setState(() => _processingDoses.add(doseKey));

    try {
      final quantity =
          (dose.medicine['quantityPerDose'] as num?)?.toDouble() ?? 1.0;
      await FinancialService.recordMedicineDose(
        medicineId: dose.medicineId,
        medicineName: dose.medicineName,
        scheduledTime: dose.time,
        date: DateTime.now(),
        status: DoseStatus.taken.id,
        actualQuantityTaken: quantity,
        unitPriceSnapshot: dose.unitPrice,
        unit: dose.unit,
      );
    } catch (error) {
      if (mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _processingDoses.remove(doseKey));
      }
    }
  }

  Future<void> _onChangeTime(BuildContext context, ScheduledDose dose) async {
    final parts = dose.time.split(':');
    final initialHour = int.tryParse(parts.first) ?? 0;
    final initialMinute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      builder: (pickerContext, child) {
        final colors = pickerContext.colors;
        return Theme(
          data: Theme.of(pickerContext).copyWith(
            colorScheme: Theme.of(
              pickerContext,
            ).colorScheme.copyWith(primary: colors.medicine),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked == null || !context.mounted) return;

    final newHhmm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (newHhmm == dose.time) return;

    final doseKey = '${dose.medicineId}_${dose.time}';
    if (_processingDoses.contains(doseKey)) return;
    setState(() => _processingDoses.add(doseKey));

    try {
      // 1. Reschedule notification: cancel old reminder first to avoid duplicates
      await NotificationService.cancelMedicineTimes(dose.medicineId, [
        dose.time,
      ]);

      final quantity =
          (dose.medicine['quantityPerDose'] as num?)?.toDouble() ?? 1.0;

      // 2. Schedule new notification at the updated time
      await NotificationService.scheduleDailyMedicine(
        medicineId: dose.medicineId,
        medicineName: dose.medicineName,
        hhmm: newHhmm,
        instruction: dose.instruction,
        quantityPerDose: quantity,
        unitPrice: dose.unitPrice,
        unit: dose.unit,
      );

      // 3. Update medicine times in Firestore
      final rawTimes = dose.medicine['times'];
      final times = (rawTimes is List
          ? rawTimes.map((e) => e.toString()).toList()
          : <String>[]);
      final index = times.indexOf(dose.time);
      if (index != -1) {
        times[index] = newHhmm;
      } else {
        times.add(newHhmm);
      }
      times.sort();

      await FirestoreService.db
          .collection('medicines')
          .doc(dose.medicineId)
          .update({
            'times': times,
            'schedule': times.join(', '),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // 4. Clean up any stale un-taken dose record for the old time today
      final oldDoseId = FinancialService.doseId(
        dose.medicineId,
        DateTime.now(),
        dose.time,
      );
      await FirestoreService.db
          .collection('medicine_doses')
          .doc(oldDoseId)
          .delete()
          .catchError((_) {});

      if (context.mounted) {
        showGochanoMessage(
          context,
          GochanoLanguage.text(
            'Time updated to ${formatTime12(newHhmm)}',
            'সময় পরিবর্তন করা হয়েছে: ${formatTime12(newHhmm)}',
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _processingDoses.remove(doseKey));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('medicines', limit: 50),
      builder: (context, medSnap) {
        if (medSnap.hasError) {
          return _AccentRailCard(
            accent: colors.medicine,
            onTap: () => Navigator.of(
              context,
            ).push(GochanoRoute.to(builder: (_) => const MedicineScreen())),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          'Unable to load medicine',
                          'ওষুধের তথ্য লোড হয়নি',
                        ),
                        style: context.type.bodySecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        if (medSnap.connectionState == ConnectionState.waiting) {
          return _AccentRailCard(
            accent: colors.medicine,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  GochanoLanguage.text('Loading…', 'লোড হচ্ছে…'),
                  style: context.type.bodySecondary,
                ),
              ],
            ),
          );
        }

        final medicines = [...?medSnap.data?.docs];

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('medicine_doses', limit: 100),
          builder: (context, doseSnap) {
            final doses = [...?doseSnap.data?.docs];
            final now = DateTime.now();
            final schedule = MedicineSchedule.forDay(
              medicines,
              doses,
              now: now,
            );
            final actionable = schedule.where((d) => d.needsAction).toList();
            final overdue = actionable
                .where((d) => d.scheduledAt(now).isBefore(now))
                .toList();
            final upcoming = actionable
                .where((d) => !d.scheduledAt(now).isBefore(now))
                .toList();
            final prioritized = [...overdue, ...upcoming];
            final displayItems = prioritized.take(2).toList();

            return _AccentRailCard(
              accent: colors.medicine,
              onTap: () => Navigator.of(
                context,
              ).push(GochanoRoute.to(builder: (_) => const MedicineScreen())),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: GochanoSpacing.xs),
                  if (schedule.isEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              'No medicine scheduled today',
                              'আজ কোনো ওষুধের সময় নির্ধারিত নেই',
                            ),
                            style: context.type.bodySecondary,
                          ),
                        ),
                      ],
                    )
                  else if (displayItems.isEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: colors.success,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              'All medicines taken for today',
                              'আজকের সব ওষুধ নেওয়া হয়েছে',
                            ),
                            style: context.type.bodySecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    for (var i = 0; i < displayItems.length; i++) ...[
                      if (i > 0) const SizedBox(height: GochanoSpacing.xxs),
                      _MedicineDoseRow(
                        dose: displayItems[i],
                        isProcessing: _processingDoses.contains(
                          '${displayItems[i].medicineId}_${displayItems[i].time}',
                        ),
                        onTaken: () => _onMarkTaken(displayItems[i]),
                        onChangeTime: () =>
                            _onChangeTime(context, displayItems[i]),
                      ),
                    ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(Icons.medication_rounded, size: 18, color: colors.medicine),
        const SizedBox(width: GochanoSpacing.xs),
        Expanded(
          child: Text(
            GochanoLanguage.text('Medicine', 'ওষুধ'),
            style: context.type.sectionHeading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MedicineDoseRow extends StatelessWidget {
  const _MedicineDoseRow({
    required this.dose,
    required this.isProcessing,
    required this.onTaken,
    required this.onChangeTime,
  });

  final ScheduledDose dose;
  final bool isProcessing;
  final VoidCallback onTaken;
  final VoidCallback onChangeTime;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final isOverdue = dose.scheduledAt(now).isBefore(now);

    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: false,
            onChanged: isProcessing ? null : (_) => onTaken(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: GochanoSpacing.xxs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dose.medicineName,
                style: context.type.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                formatTime12(dose.time),
                style: context.type.caption.copyWith(
                  color: isOverdue ? colors.warning : colors.textSecondary,
                  fontWeight: isOverdue ? FontWeight.w600 : null,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.notifications_outlined,
            size: 16,
            color: colors.textSecondary,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          tooltip: GochanoLanguage.text('Change time', 'সময় পরিবর্তন'),
          onPressed: isProcessing ? null : onChangeTime,
        ),
      ],
    );
  }
}

/// Money row for Money card — full-width, non-truncating currency display.
/// Shows icon + label + amount with responsive layout.
// ignore: unused_element
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.amount,
    required this.color,
    this.showDash = false,
  });

  final String label;
  final double? amount;
  final Color color;
  final bool showDash;

  @override
  Widget build(BuildContext context) {
    final valueText = showDash ? '—' : formatTaka(amount ?? 0);
    return Row(
      children: [
        Icon(
          showDash
              ? Icons.remove_circle_outline
              : amount != null && amount! >= 0
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: GochanoSpacing.xs),
        Text(
          label,
          style: context.type.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            valueText,
            style: context.type.cardHeading.copyWith(
              color: color,
              fontFamily: '.SF Pro Text',
              fontFamilyFallback: const ['Roboto', 'sans-serif'],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Money: Remaining + Spent
// ---------------------------------------------------------------------------

// ignore: unused_element
class _MoneyCard extends StatefulWidget {
  const _MoneyCard({required this.onOpenExpense});

  final VoidCallback onOpenExpense;

  @override
  State<_MoneyCard> createState() => _MoneyCardState();
}

class _MoneyCardState extends State<_MoneyCard> {
  // Monthly money and remaining as returned by the backend for this month.
  // Used by Money card on Home screen.
  double? _available;
  double? _backendRemaining;
  String? _budgetError;

  @override
  void initState() {
    super.initState();
    _loadBudget();
    FinancialService.budgetRefreshKey.addListener(_onBudgetChanged);
  }

  @override
  void dispose() {
    FinancialService.budgetRefreshKey.removeListener(_onBudgetChanged);
    super.dispose();
  }

  void _onBudgetChanged() {
    _loadBudget();
  }

  Future<void> _loadBudget() async {
    try {
      // Use getRemaining() — the same endpoint as overview_tab — so that
      // Home Money card and Expense Overview always agree on Remaining.
      final body = await ApiService.getRemaining(DateTime.now());
      if (!mounted) return;
      setState(() {
        _available = (body['available'] as num?)?.toDouble();
        _backendRemaining = (body['remaining'] as num?)?.toDouble();
        _budgetError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _budgetError = GochanoLanguage.text(
            'Unable to load budget',
            'বাজেট লোড হয়নি',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();

    // Dena/Pawna settlement stream — adds pawna received, subtracts dena paid.
    // Mirrors the exact formula in overview_tab.dart's OverviewTabState.build.
    return StreamBuilder<Map<String, double>>(
      stream: FinancialService.denaPawnaSettlementTotalsStream(now),
      builder: (context, settlementSnap) {
        final settlements =
            settlementSnap.data ?? const {'pawnaReceived': 0, 'denaPaid': 0};
        final pawnaReceived = settlements['pawnaReceived'] ?? 0;
        final denaPaid = settlements['denaPaid'] ?? 0;

        return StreamBuilder<List<FinancialTransactionModel>>(
          stream: FinancialService.monthStream(now),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _AccentRailCard(
                accent: colors.expense,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 18,
                          color: colors.expense,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Text(
                          GochanoLanguage.text('Money', 'টাকা'),
                          style: context.type.sectionHeading,
                        ),
                      ],
                    ),
                    const SizedBox(height: GochanoSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              'Unable to load spending data',
                              'খরচের তথ্য লোড হয়নি',
                            ),
                            style: context.type.bodySecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _SectionSkeleton();
            }

            final items = snapshot.data ?? const <FinancialTransactionModel>[];
            final summary = FinancialSummary.fromTransactions(items);

            // Authoritative remaining formula — identical to overview_tab:
            //   Remaining = backendRemaining + pawnaReceived - denaPaid
            // backendRemaining already equals (monthlyMoney - confirmedExpenses)
            // on the backend. If budget is not set, fall back to showing
            // spent only.
            final hasBudget = _available != null && _available! > 0;
            final adjustedRemaining = hasBudget
                ? ((_backendRemaining ?? _available!) +
                      pawnaReceived -
                      denaPaid)
                : null;

            return _AccentRailCard(
              accent: colors.expense,
              onTap: widget.onOpenExpense,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 18,
                        color: colors.expense,
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Expanded(
                        child: Text(
                          GochanoLanguage.text('Money', 'টাকা'),
                          style: context.type.sectionHeading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  if (_budgetError != null)
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Text(
                            _budgetError!,
                            style: context.type.bodySecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MoneyRow(
                          label: GochanoLanguage.text('Spent', 'খরচ'),
                          amount: summary.totalSpending,
                          color: colors.expense,
                        ),
                        const SizedBox(height: GochanoSpacing.xs),
                        _MoneyRow(
                          label: GochanoLanguage.text('Rem', 'অবশিষ্ট'),
                          amount: adjustedRemaining,
                          color:
                              adjustedRemaining != null && adjustedRemaining > 0
                              ? colors.success
                              : colors.error,
                          showDash: adjustedRemaining == null,
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Recent materials
// ---------------------------------------------------------------------------

class _RecentMaterialsCard extends StatelessWidget {
  const _RecentMaterialsCard({required this.onOpenStudy});

  final VoidCallback onOpenStudy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('materials', limit: 5),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AccentRailCard(
            accent: colors.study,
            onTap: onOpenStudy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 18, color: colors.study),
                    const SizedBox(width: GochanoSpacing.xs),
                    Text(
                      GochanoLanguage.text('Recent', 'সাম্প্রতিক'),
                      style: context.type.sectionHeading,
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          'Unable to load materials',
                          'উপকরণ লোড হয়নি',
                        ),
                        style: context.type.bodySecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        final docs = [...?snapshot.data?.docs]..sort(_byCreatedAtDesc);
        if (docs.isEmpty) {
          return _AccentRailCard(
            accent: colors.study,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 18, color: colors.study),
                    const SizedBox(width: GochanoSpacing.xs),
                    Text(
                      GochanoLanguage.text('Recent', 'সাম্প্রতিক'),
                      style: context.type.sectionHeading,
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  GochanoLanguage.text(
                    'No materials yet.',
                    'এখনো কোনো উপকরণ নেই।',
                  ),
                  style: context.type.bodySecondary,
                ),
              ],
            ),
          );
        }

        return _AccentRailCard(
          accent: colors.study,
          onTap: onOpenStudy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 18, color: colors.study),
                  const SizedBox(width: GochanoSpacing.xs),
                  Text(
                    GochanoLanguage.text('Recent', 'সাম্প্রতিক'),
                    style: context.type.sectionHeading,
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              for (final doc in docs.take(3)) _RecentRow(doc: doc),
            ],
          ),
        );
      },
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = (data['title']?.toString().trim().isNotEmpty ?? false)
        ? data['title'].toString()
        : data['fileName']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xxs),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => MaterialReaderScreen(
              materialId: doc.id,
              title: title,
              mimeType: data['mimeType']?.toString() ?? '',
            ),
          ),
        ),
        borderRadius: GochanoRadius.smAll,
        child: Row(
          children: [
            GochanoIllustrationTile(
              GochanoArt.fileIdFor(
                fileName: data['fileName']?.toString(),
                mimeType: data['mimeType']?.toString(),
              ),
              accent: context.colors.study,
              plateSize: 32,
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(
              child: Text(
                title,
                style: context.type.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActions extends StatefulWidget {
  const _QuickActions({required this.isStudent});

  final bool isStudent;

  @override
  State<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<_QuickActions> {
  static const _collapsedCount = 3;

  bool _expanded = false;

  List<_QuickAction> _actions(BuildContext context) {
    final colors = context.colors;
    return <_QuickAction>[
      if (widget.isStudent)
        _QuickAction(
          label: GochanoLanguage.text('Ask AI', 'AI-কে জিজ্ঞাসা'),
          icon: Icons.auto_awesome_rounded,
          accent: colors.ai,
          onTap: () => Navigator.of(
            context,
          ).push(GochanoRoute.to(builder: (_) => const AiAssistantScreen())),
        ),
      _QuickAction(
        label: GochanoLanguage.text('Add expense', 'খরচ যোগ করুন'),
        icon: Icons.receipt_long_rounded,
        accent: colors.expense,
        onTap: () => showAddExpenseSheet(context),
      ),
      _QuickAction(
        label: GochanoLanguage.text('Add task', 'কাজ যোগ করুন'),
        icon: Icons.task_alt_rounded,
        accent: colors.brand,
        onTap: () => showAddTaskSheet(context),
      ),
      _QuickAction(
        label: GochanoLanguage.text(
          'Scan prescription',
          'প্রেসক্রিপশন স্ক্যান',
        ),
        icon: Icons.document_scanner_rounded,
        accent: colors.medicine,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const PrescriptionScanScreen())),
      ),
      _QuickAction(
        label: GochanoLanguage.text('Find a route', 'রুট খুঁজুন'),
        icon: Icons.directions_bus_rounded,
        accent: colors.commute,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const CommuteScreen())),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context);
    final hasMore = actions.length > _collapsedCount;
    final visible = (_expanded || !hasMore)
        ? actions
        : actions.take(_collapsedCount).toList();

    final screenWidth = MediaQuery.of(context).size.width;
    final columns = screenWidth >= 380 ? 4 : 3;

    return _AccentRailCard(
      accent: context.colors.brand,
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 88,
              crossAxisSpacing: GochanoSpacing.xxs,
              mainAxisSpacing: GochanoSpacing.xs,
            ),
            itemBuilder: (context, i) => visible[i],
          ),
          if (hasMore)
            Center(
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: GochanoRadius.mdAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GochanoSpacing.md,
                    vertical: GochanoSpacing.xs,
                  ),
                  child: Tooltip(
                    message: _expanded
                        ? GochanoLanguage.text('See less', 'কম দেখুন')
                        : GochanoLanguage.text('See more', 'আরো দেখুন'),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: GochanoSizes.iconMd,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: GochanoSpacing.xxs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.type.caption.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: GochanoRadius.lgAll,
          border: Border.all(color: context.colors.border),
        ),
      ),
    );
  }
}

int _byCreatedAtDesc(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  final at = a.data()['createdAt'];
  final bt = b.data()['createdAt'];
  if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
  if (at is Timestamp) return -1;
  if (bt is Timestamp) return 1;
  return 0;
}

int _byDueAtAsc(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  final at = a.data()['dueAt'] as Timestamp?;
  final bt = b.data()['dueAt'] as Timestamp?;
  if (at == null || bt == null) return 0;
  return at.compareTo(bt);
}

String _timeLabel(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final suffix = GochanoLanguage.text(
    when.hour < 12 ? 'am' : 'pm',
    when.hour < 12 ? 'পূর্বাহ্ণ' : 'অপরাহ্ণ',
  );
  return '$hour:$minute $suffix';
}

/// Formats an amount in Bangladeshi taka.
String formatTaka(double amount) {
  final rounded = amount.roundToDouble();
  final text = (amount - rounded).abs() < 0.005
      ? rounded.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  final parts = text.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '৳${buffer.toString()}${parts.length > 1 ? '.${parts[1]}' : ''}';
}
