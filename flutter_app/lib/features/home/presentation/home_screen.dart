// Home — "what matters to me right now?" (spec §27).
//
// Home is not a directory of features. It surfaces the handful of things a
// student needs on opening the app, in priority order, and gets out of the
// way. There is deliberately no 15-icon feature grid: the five destinations
// in the bottom bar are the map, and Home is the briefing.
//
// Order (spec §27): greeting → continue studying → today's tasks → next
// medicine → money → recent materials → group activity → quick actions.
//
// Each section owns its own stream. That is a performance decision as much as
// a structural one: adding a task rebuilds the tasks card, not the whole
// dashboard (spec §83).

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
import '../../../services/financial_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../life/domain/medicine_schedule.dart';
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

  /// Switches the shell to another primary destination, so a Home card can
  /// say "See all" without pushing a duplicate copy of the Study or Life
  /// screen onto the navigator (spec §85).
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
          if (_isStudent) ...[
            const _ContinueStudyingCard(),
            const SizedBox(height: GochanoSpacing.sm),
          ],
          _TodaysTasksCard(onSeeAll: () => onOpenDestination(_isStudent ? 1 : 2)),
          const SizedBox(height: GochanoSpacing.sm),
          _NextMedicineCard(
            onOpenMedicine: () => onOpenDestination(_isStudent ? 2 : 1),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          _MoneyCard(onOpenExpense: () => onOpenDestination(_isStudent ? 2 : 1)),
          if (_isStudent) ...[
            const SizedBox(height: GochanoSpacing.sm),
            _GroupActivityCard(onOpenCommunity: () => onOpenDestination(3)),
          ],
          SectionHeader(
            title: GochanoLanguage.text('Quick actions', 'দ্রুত কাজ'),
          ),
          _QuickActions(isStudent: _isStudent),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue studying
// ---------------------------------------------------------------------------

/// The most recently added material, offered as a single resume action.
///
/// This is what removes the Semester → Subject → Materials walk from the most
/// common case (spec §29: "Surface Recent Materials to reduce navigation
/// depth").
class _ContinueStudyingCard extends StatelessWidget {
  const _ContinueStudyingCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('materials', limit: 20),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SectionSkeleton();
        }

        final docs = [...?snapshot.data?.docs]..sort(_byCreatedAtDesc);
        if (docs.isEmpty) return const SizedBox.shrink();

        final doc = docs.first;
        final data = doc.data();
        final title = (data['title']?.toString().trim().isNotEmpty ?? false)
            ? data['title'].toString()
            : data['fileName']?.toString() ?? '';
        final subject = data['subject']?.toString().trim() ?? '';

        return AppCard(
          accent: colors.study,
          onTap: () => Navigator.of(context).push(
            GochanoRoute.to(
              builder: (_) => MaterialReaderScreen(
                materialId: doc.id,
                title: title,
                mimeType: data['mimeType']?.toString() ?? '',
              ),
            ),
          ),
          child: Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.fileIdFor(
                  fileName: data['fileName']?.toString(),
                  mimeType: data['mimeType']?.toString(),
                ),
                accent: colors.study,
                plateSize: 48,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      GochanoLanguage.text('Continue studying', 'পড়া চালিয়ে যান'),
                      style: context.type.label,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: context.type.cardHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subject.isNotEmpty)
                      Text(
                        subject,
                        style: context.type.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
            ],
          ),
        );
      },
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
        if (snapshot.hasError) return const SizedBox.shrink();
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

        return AppCard(
          accent: colors.brand,
          onTap: onSeeAll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      GochanoLanguage.text("Today's tasks", 'আজকের কাজ'),
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
                      size: 36,
                      accent: colors.textTertiary,
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          'No tasks due today. Your schedule is clear.',
                          'আজ কোনো কাজ নেই। আপনার দিন ফাঁকা।',
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
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  GochanoLanguage.text(
                    '+${open.length - 3} more today',
                    'আজ আরও ${open.length - 3} টি',
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
///
/// Completing from Home writes straight to Firestore — Home is not a
/// read-only summary (spec §105).
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
            width: 32,
            height: 32,
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
// Next medicine
// ---------------------------------------------------------------------------

class _NextMedicineCard extends StatelessWidget {
  const _NextMedicineCard({required this.onOpenMedicine});

  final VoidCallback onOpenMedicine;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('medicines', limit: 200),
      builder: (context, medSnapshot) {
        if (medSnapshot.hasError) return const SizedBox.shrink();
        final medicines = [...?medSnapshot.data?.docs];
        if (medicines.isEmpty) return const SizedBox.shrink();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('medicine_doses', limit: 500),
          builder: (context, doseSnapshot) {
            final schedule = MedicineSchedule.forDay(
              medicines,
              [...?doseSnapshot.data?.docs],
            );
            final next = MedicineSchedule.next(schedule);
            if (next == null) return const SizedBox.shrink();

            final overdue = next.status == DoseStatus.missed;

            return AppCard(
              accent: colors.medicine,
              onTap: onOpenMedicine,
              child: Row(
                children: [
                  GochanoIllustrationTile(
                    GochanoArt.featureReminder,
                    accent: colors.medicine,
                    plateSize: 48,
                  ),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          GochanoLanguage.text('Next medicine', 'পরবর্তী ওষুধ'),
                          style: context.type.label,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${next.medicineName}'
                          '${next.strength.isEmpty ? '' : ' · ${next.strength}'}',
                          style: context.type.cardHeading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          next.time,
                          style: context.type.caption,
                        ),
                      ],
                    ),
                  ),
                  if (overdue)
                    GochanoBadge(
                      label: GochanoLanguage.text('Overdue', 'সময় পেরিয়েছে'),
                      tone: GochanoBadgeTone.warning,
                      icon: Icons.schedule_rounded,
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
// Money
// ---------------------------------------------------------------------------

/// This month's spending, split by where it came from.
///
/// Reads the same central ledger the Expense hub reads, so Home and Expense
/// can never disagree about a total (spec §36).
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.onOpenExpense});

  final VoidCallback onOpenExpense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();

    return StreamBuilder<List<FinancialTransactionModel>>(
      stream: FinancialService.monthStream(now),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SectionSkeleton();
        }

        final items = snapshot.data ?? const <FinancialTransactionModel>[];
        final summary = FinancialSummary.fromTransactions(items);
        final today = FinancialService.dateKey(now);
        final todayTotal = items
            .where((e) => FinancialService.dateKey(e.date) == today)
            .fold<double>(0, (running, e) => running + e.amount);

        return AppCard(
          accent: colors.expense,
          onTap: onOpenExpense,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                GochanoLanguage.text('This month', 'এই মাস'),
                style: context.type.label,
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatTaka(summary.totalSpending),
                        style: context.type.statistic,
                      ),
                    ),
                  ),
                  Text(
                    GochanoLanguage.text(
                      'Today ${formatTaka(todayTotal)}',
                      'আজ ${formatTaka(todayTotal)}',
                    ),
                    style: context.type.caption,
                  ),
                ],
              ),
              if (summary.bySource.isNotEmpty) ...[
                const SizedBox(height: GochanoSpacing.xs),
                Wrap(
                  spacing: GochanoSpacing.xs,
                  runSpacing: GochanoSpacing.xxs,
                  children: [
                    for (final entry in _sortedSources(summary.bySource))
                      GochanoBadge(
                        label: '${_sourceLabel(entry.key)} '
                            '${formatTaka(entry.value)}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static List<MapEntry<String, double>> _sortedSources(Map<String, double> m) {
    final entries = m.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(4).toList();
  }

  static String _sourceLabel(String source) => switch (source) {
        'daily' => GochanoLanguage.text('Daily', 'দৈনিক'),
        'bazar' => GochanoLanguage.text('Grocery', 'বাজার'),
        'medicine' => GochanoLanguage.text('Medicine', 'ওষুধ'),
        'commute' => GochanoLanguage.text('Commute', 'যাতায়াত'),
        _ => GochanoLanguage.text('Other', 'অন্যান্য'),
      };
}

// ---------------------------------------------------------------------------
// Group activity
// ---------------------------------------------------------------------------

class _GroupActivityCard extends StatelessWidget {
  const _GroupActivityCard({required this.onOpenCommunity});

  final VoidCallback onOpenCommunity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.myGroups(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final groups = [...?snapshot.data?.docs];
        if (groups.isEmpty) return const SizedBox.shrink();

        return AppCard(
          accent: colors.community,
          onTap: onOpenCommunity,
          child: Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureGroups,
                accent: colors.community,
                plateSize: 48,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      GochanoLanguage.text('Your study groups', 'আপনার স্টাডি গ্রুপ'),
                      style: context.type.label,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      groups
                          .take(2)
                          .map((g) => g.data()['name']?.toString() ?? '')
                          .where((n) => n.isNotEmpty)
                          .join(', '),
                      style: context.type.cardHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      GochanoLanguage.text(
                        groups.length == 1
                            ? '1 group'
                            : '${groups.length} groups',
                        '${groups.length} টি গ্রুপ',
                      ),
                      style: context.type.caption,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

/// The actions worth one tap from Home (spec §27).
///
/// One compact card in four columns, not five large tiles. The tiles took a
/// third of the first screen for five shortcuts, which pushed the actual
/// briefing — today's tasks, the money left — below the fold.
///
/// Four are shown; the rest sit behind "See more", because four covers the
/// daily habits and the fifth is a trip you plan occasionally.
class _QuickActions extends StatefulWidget {
  const _QuickActions({required this.isStudent});

  final bool isStudent;

  @override
  State<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<_QuickActions> {
  /// How many fit before "See more".
  static const _collapsedCount = 3;

  bool _expanded = false;

  List<_QuickAction> _actions(BuildContext context) {
    final colors = context.colors;
    return <_QuickAction>[
      if (widget.isStudent)
        _QuickAction(
          label: GochanoLanguage.text('Ask AI', 'AI-কে জিজ্ঞাসা'),
          illustration: GochanoArt.featureAi,
          accent: colors.ai,
          onTap: () => Navigator.of(context).push(
            GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
          ),
        ),
      _QuickAction(
        label: GochanoLanguage.text('Add expense', 'খরচ যোগ করুন'),
        illustration: GochanoArt.featureExpense,
        accent: colors.expense,
        onTap: () => showAddExpenseSheet(context),
      ),
      _QuickAction(
        label: GochanoLanguage.text('Add task', 'কাজ যোগ করুন'),
        illustration: GochanoArt.featureTasks,
        accent: colors.brand,
        onTap: () => showAddTaskSheet(context),
      ),
      _QuickAction(
        label: GochanoLanguage.text('Scan prescription', 'প্রেসক্রিপশন স্ক্যান'),
        illustration: GochanoArt.featurePrescription,
        accent: colors.medicine,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const PrescriptionScanScreen()),
        ),
      ),
      _QuickAction(
        label: GochanoLanguage.text('Find a route', 'রুট খুঁজুন'),
        illustration: GochanoArt.featureCommute,
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

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Four across normally. A very narrow phone drops to three so a
              // Bangla label keeps two comfortable lines instead of being
              // clipped.
                final columns = constraints.maxWidth >= 380 ? 4 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: visible.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  // Tall enough for a 52 px icon plate and two lines of label
                  // at the largest text scale this design supports.
                  mainAxisExtent: 88,
                  crossAxisSpacing: GochanoSpacing.xxs,
                  mainAxisSpacing: GochanoSpacing.xs,
                ),
                itemBuilder: (context, i) => visible[i],
              );
            },
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
                // Show less (legacy alias for older clients)
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

/// One shortcut: a tinted circular icon area over a centred label.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.illustration,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String illustration;
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
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  // The accent at low opacity, so five shortcuts read as one
                  // set rather than five competing colours.
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: GochanoIllustration(
                    illustration,
                    size: 28,
                    accent: accent,
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              Expanded(
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

/// A static placeholder with the height of the card it stands in for, so the
/// dashboard does not jump as each section resolves (spec §12 — no animated
/// shimmer, just a stable box).
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
///
/// Whole numbers drop the decimals — "৳120" reads better than "৳120.00" for
/// the amounts a student actually enters.
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

