// Home — "what matters to me right now?" (spec §27).
//
// Bento grid layout with accent-rail cards. Each section owns its own stream
// for independent rebuilds (spec §83).
//
// Structure (spec §27):
//   Header → Your Day / Smart Summary → Quick Actions → Today → Upcoming →
//   Study Progress → Life Snapshot: Remaining + Spent → Recent

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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

  String _firstName() {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return GochanoLanguage.text('Good morning', 'সুপ্রভাত');
    if (hour < 17) return GochanoLanguage.text('Good afternoon', 'শুভ অপরাহ্ন');
    return GochanoLanguage.text('Good evening', 'শুভ সন্ধ্যা');
  }

  @override
  Widget build(BuildContext context) {
    final name = _firstName();
    final title = name.isEmpty ? _greeting() : '${_greeting()}, $name';

    // DEBUG: Log HomeScreen build and auth state
    if (kDebugMode) {
      final uid = FirestoreService.uid;
      debugPrint('[HomeScreen] build called, role=$_isStudent, uid=$uid, displayName=$displayName');
    }

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: title,
        subtitle: GochanoLanguage.text(
          'Here is your day so far',
          'আপনার আজকের দিন এক নজরে',
        ),
        automaticallyImplyLeading: false,
        actions: const [LanguageToggle(), SizedBox(width: GochanoSpacing.xs)],
      ),
      body: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _SmartSummaryCard(isStudent: _isStudent),
          const SizedBox(height: GochanoSpacing.sm),
          _QuickActions(isStudent: _isStudent),
          const SizedBox(height: GochanoSpacing.sm),
          _BentoRow(
            left: _TodaysTasksCard(onSeeAll: () => onOpenDestination(_isStudent ? 1 : 2)),
            right: _UpcomingTasksCard(onSeeAll: () => onOpenDestination(_isStudent ? 1 : 2)),
          ),
          if (_isStudent) ...[
            const SizedBox(height: GochanoSpacing.sm),
            _BentoRow(
              left: _StudyProgressCard(),
              right: _LifeSnapshotCard(onOpenExpense: () => onOpenDestination(_isStudent ? 2 : 1)),
            ),
          ] else ...[
            const SizedBox(height: GochanoSpacing.sm),
            _LifeSnapshotCard(onOpenExpense: () => onOpenDestination(1)),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          _RecentMaterialsCard(onOpenStudy: () => onOpenDestination(0)),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(child: right),
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
          border: Border.all(color: colors.border, width: GochanoBorders.hairline),
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
        if (kDebugMode) {
          debugPrint('[HomeScreen._SmartSummaryCard] tasks stream: connectionState=${taskSnap.connectionState}, hasError=${taskSnap.hasError}, hasData=${taskSnap.hasData}, docCount=${taskSnap.data?.docs.length ?? 0}');
        }
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
                    Icon(Icons.cloud_off_rounded, size: 16, color: colors.textTertiary),
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
            if (kDebugMode) {
              debugPrint('[HomeScreen._SmartSummaryCard] financial stream: connectionState=${moneySnap.connectionState}, hasError=${moneySnap.hasError}, hasData=${moneySnap.hasData}, itemCount=${moneySnap.data?.length ?? 0}');
            }
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
                        Icon(Icons.cloud_off_rounded, size: 16, color: colors.textTertiary),
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
                  Row(
                    children: [
                      _SummaryPill(
                        icon: Icons.task_alt_rounded,
                        label: GochanoLanguage.text('$todayCount tasks', '$todayCount টি কাজ'),
                        color: todayCount > 0 ? colors.brand : colors.success,
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      _SummaryPill(
                        icon: Icons.receipt_long_rounded,
                        label: formatTaka(todaySpent),
                        color: colors.expense,
                      ),
                      if (overdueCount > 0) ...[
                        const SizedBox(width: GochanoSpacing.xs),
                        _SummaryPill(
                          icon: Icons.warning_amber_rounded,
                          label: GochanoLanguage.text(
                            '$overdueCount overdue',
                            '$overdueCount টি বাকি',
                          ),
                          color: colors.warning,
                        ),
                      ],
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
        if (kDebugMode) {
          debugPrint('[HomeScreen._TodaysTasksCard] tasks stream: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, hasData=${snapshot.hasData}, docCount=${snapshot.data?.docs.length ?? 0}');
        }
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
                    Expanded(
                      child: Text(
                        GochanoLanguage.text("Today", 'আজ'),
                        style: context.type.sectionHeading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
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
                    ),
                  ),
                  if (overdue > 0)
                    GochanoBadge(
                      label: GochanoLanguage.text(
                        '$overdue overdue',
                        '$overdue টি বাকি',
                      ),
                      tone: GochanoBadgeTone.warning,
                      icon: Icons.schedule_rounded,
                    ),
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
                        GochanoLanguage.text(
                          'All clear today.',
                          'আজ ফাঁকা।',
                        ),
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
// Upcoming tasks
// ---------------------------------------------------------------------------

class _UpcomingTasksCard extends StatelessWidget {
  const _UpcomingTasksCard({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 100),
      builder: (context, snapshot) {
        if (kDebugMode) {
          debugPrint('[HomeScreen._UpcomingTasksCard] tasks stream: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, hasData=${snapshot.hasData}, docCount=${snapshot.data?.docs.length ?? 0}');
        }
        if (snapshot.hasError) {
          return _AccentRailCard(
            accent: colors.commute,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.upcoming_rounded, size: 18, color: colors.commute),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text('Upcoming', 'আসন্ন'),
                        style: context.type.sectionHeading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
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
        final endOfWeek = endOfToday.add(const Duration(days: 7));
        final upcoming = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          if (due.isAfter(endOfToday) && due.isBefore(endOfWeek)) {
            upcoming.add(doc);
          }
        }
        upcoming.sort(_byDueAtAsc);

        return _AccentRailCard(
          accent: colors.commute,
          onTap: onSeeAll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.upcoming_rounded, size: 18, color: colors.commute),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('Upcoming', 'আসন্ন'),
                      style: context.type.sectionHeading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              if (upcoming.isEmpty)
                Text(
                  GochanoLanguage.text(
                    'Nothing scheduled this week.',
                    'এই সপ্তাহে কিছু নেই।',
                  ),
                  style: context.type.bodySecondary,
                )
              else
                for (final doc in upcoming.take(3))
                  _TaskLine(doc: doc, isLast: doc == upcoming.take(3).last),
              if (upcoming.length > 3) ...[
                const SizedBox(height: GochanoSpacing.xxs),
                Text(
                  GochanoLanguage.text(
                    '+${upcoming.length - 3} more next week',
                    'আরও ${upcoming.length - 3} টি',
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
            Text(
              _timeLabel(due),
              style: context.type.caption.copyWith(
                color: isOverdue ? context.colors.warning : null,
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
        setState(() => _error = 'Unable to load study stats');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (kDebugMode) {
      debugPrint('[HomeScreen._StudyProgressCard] build: stats=$_stats, error=$_error');
    }

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
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if (_error != null)
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Text(
                    _error!,
                    style: context.type.bodySecondary,
                  ),
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
                    value: GochanoLanguage.text('$todayMinutes min', '$todayMinutes মি'),
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
          Text(label, style: context.type.caption),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.type.cardHeading.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Life Snapshot: Remaining + Spent
// ---------------------------------------------------------------------------

class _LifeSnapshotCard extends StatefulWidget {
  const _LifeSnapshotCard({required this.onOpenExpense});

  final VoidCallback onOpenExpense;

  @override
  State<_LifeSnapshotCard> createState() => _LifeSnapshotCardState();
}

class _LifeSnapshotCardState extends State<_LifeSnapshotCard> {
  double? _budget;
  String? _budgetError;

  @override
  void initState() {
    super.initState();
    _loadBudget();
  }

  Future<void> _loadBudget() async {
    try {
      final body = await ApiService.getMonthlyBudget(DateTime.now());
      if (!mounted) return;
      setState(() {
        _budget = (body['availableAmount'] as num?)?.toDouble() ?? 0;
        _budgetError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _budgetError = 'Unable to load budget');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();

    return StreamBuilder<List<FinancialTransactionModel>>(
      stream: FinancialService.monthStream(now),
      builder: (context, snapshot) {
        if (kDebugMode) {
          debugPrint('[HomeScreen._LifeSnapshotCard] financial stream: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, hasData=${snapshot.hasData}, itemCount=${snapshot.data?.length ?? 0}, budget=$_budget, budgetError=$_budgetError');
        }
        if (snapshot.hasError) {
          return _AccentRailCard(
            accent: colors.expense,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, size: 18, color: colors.expense),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text('Life Snapshot', 'জীবন পরিসংখ্যান'),
                        style: context.type.sectionHeading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
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
        final remaining = (_budget ?? 0) - summary.totalSpending;

        return _AccentRailCard(
          accent: colors.expense,
          onTap: widget.onOpenExpense,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, size: 18, color: colors.expense),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('Life Snapshot', 'জীবন পরিসংখ্যান'),
                      style: context.type.sectionHeading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              if (_budgetError != null)
                Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
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
                Row(
                  children: [
                    Expanded(
                      child: _StatPill(
                        label: GochanoLanguage.text('Spent', 'খরচ'),
                        value: formatTaka(summary.totalSpending),
                        color: colors.expense,
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: _StatPill(
                        label: GochanoLanguage.text('Remaining', 'বাকি'),
                        value: formatTaka(remaining),
                        color: remaining > 0 ? colors.success : colors.error,
                      ),
                    ),
                  ],
                ),
            ],
          ),
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
        if (kDebugMode) {
          debugPrint('[HomeScreen._RecentMaterialsCard] materials stream: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, hasData=${snapshot.hasData}, docCount=${snapshot.data?.docs.length ?? 0}');
        }
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
                    Expanded(
                      child: Text(
                        GochanoLanguage.text('Recent', 'সাম্প্রতিক'),
                        style: context.type.sectionHeading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
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
                    Expanded(
                      child: Text(
                        GochanoLanguage.text('Recent', 'সাম্প্রতিক'),
                        style: context.type.sectionHeading,
                      ),
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
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('Recent', 'সাম্প্রতিক'),
                      style: context.type.sectionHeading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              for (final doc in docs.take(3))
                _RecentRow(doc: doc),
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
            Icon(Icons.chevron_right_rounded, size: 18, color: context.colors.textTertiary),
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
          onTap: () => Navigator.of(context).push(
            GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
          ),
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
        label: GochanoLanguage.text('Scan prescription', 'প্রেসক্রিপশন স্ক্যান'),
        icon: Icons.document_scanner_rounded,
        accent: colors.medicine,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const PrescriptionScanScreen()),
        ),
      ),
      _QuickAction(
        label: GochanoLanguage.text('Find a route', 'রুট খুঁজুন'),
        icon: Icons.directions_bus_rounded,
        accent: colors.commute,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const CommuteScreen()),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context);
    final hasMore = actions.length > _collapsedCount;
    final visible =
        (_expanded || !hasMore) ? actions : actions.take(_collapsedCount).toList();

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
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: GochanoSizes.iconSm,
              ),
              label: Text(
                _expanded
                    ? GochanoLanguage.text('See less', 'কম দেখুন')
                    : GochanoLanguage.text('See more', 'আরো দেখুন'),
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
  final suffix = when.hour < 12 ? 'am' : 'pm';
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
