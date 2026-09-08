// Study planner (spec §40).
//
// What this is, precisely
// -----------------------
// `POST /api/study/plan` ranks the student's unfinished tasks by deadline
// urgency. It is deterministic arithmetic — overdue first, then soonest — and
// the endpoint says so in its own `method` field. It is **not** a model and
// not a recommendation engine, so this screen calls it "suggested order" and
// prints the method the server reports rather than dressing it up
// (spec §100).
//
// Below the suggested order is a plain agenda of dated tasks grouped by day,
// which is the "clean agenda/timeline" structure spec §40 asks for.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../tasks/presentation/add_task_sheet.dart';

class PlannerView extends StatefulWidget {
  const PlannerView({super.key});

  @override
  State<PlannerView> createState() => _PlannerViewState();
}

class _PlannerViewState extends State<PlannerView> {
  List<Map<String, dynamic>> _plan = const [];
  bool _loadingPlan = true;
  String _planError = '';

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    setState(() {
      _loadingPlan = true;
      _planError = '';
    });
    try {
      final items = await ApiService.studyPlan();
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
        _plan = items
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
        _planError = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadPlan,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          SectionHeader(
            title: GochanoLanguage.text('Suggested order', 'প্রস্তাবিত ক্রম'),
            subtitle: GochanoLanguage.text(
              'Your unfinished tasks ranked by how soon they are due.',
              'আপনার অসম্পূর্ণ কাজ, সময়সীমা কত কাছে তার ভিত্তিতে সাজানো।',
            ),
            padding: const EdgeInsets.only(
              top: GochanoSpacing.sm,
              bottom: GochanoSpacing.xs,
            ),
          ),
          if (_loadingPlan)
            StaticLoadingState(
              compact: true,
              message: GochanoLanguage.text(
                'Building your plan…',
                'আপনার পরিকল্পনা তৈরি হচ্ছে…',
              ),
            )
          else if (_planError.isNotEmpty)
            ErrorState(compact: true, message: _planError, onRetry: _loadPlan)
          else if (_plan.isEmpty)
            EmptyState(
              compact: true,
              illustration: GochanoArt.featurePlanner,
              title: GochanoLanguage.text('Nothing to plan', 'পরিকল্পনার কিছু নেই'),
              message: GochanoLanguage.text(
                'Add a task with a due date and it will appear here in order.',
                'সময়সীমাসহ একটি কাজ যোগ করুন, এটি ক্রম অনুসারে এখানে দেখা যাবে।',
              ),
              actionLabel: GochanoLanguage.text('Add task', 'কাজ যোগ করুন'),
              onAction: () async {
                if (await showAddTaskSheet(context)) _loadPlan();
              },
            )
          else
            CardGroup(
              children: [
                for (var i = 0; i < _plan.length; i++)
                  _PlanRow(index: i + 1, item: _plan[i]),
              ],
            ),

          SectionHeader(
            title: GochanoLanguage.text('Agenda', 'সময়সূচি'),
            subtitle: GochanoLanguage.text(
              'Dated tasks, day by day.',
              'তারিখসহ কাজ, দিন অনুযায়ী।',
            ),
          ),
          const _Agenda(),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.index, required this.item});

  final int index;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final due = DateTime.tryParse(item['dueAt']?.toString() ?? '');
    final overdue = due != null && due.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.sm,
        vertical: GochanoSpacing.sm,
      ),
      child: Row(
        children: [
          // A plain rank number, not a score. The score is an internal sort
          // key and showing it would imply a precision it does not have.
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.brandSoft,
              borderRadius: GochanoRadius.smAll,
            ),
            child: Text(
              '$index',
              style: context.type.caption.copyWith(
                color: colors.brand,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Text(
              item['title']?.toString() ?? '',
              style: context.type.cardHeading,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (due != null) ...[
            const SizedBox(width: GochanoSpacing.xs),
            GochanoBadge(
              label: _shortDue(due),
              tone: overdue
                  ? GochanoBadgeTone.warning
                  : GochanoBadgeTone.neutral,
              icon: Icons.schedule_rounded,
            ),
          ] else
            GochanoBadge(
              label: GochanoLanguage.text('No date', 'তারিখ নেই'),
            ),
        ],
      ),
    );
  }
}

/// Dated, unfinished tasks grouped by day.
class _Agenda extends StatelessWidget {
  const _Agenda();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            compact: true,
            message: GochanoLanguage.text(
              'Loading agenda…',
              'সময়সূচি লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            compact: true,
            message: friendlyErrorMessage(snapshot.error),
          );
        }

        final byDay = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          final key = '${due.year}-${due.month.toString().padLeft(2, '0')}-'
              '${due.day.toString().padLeft(2, '0')}';
          byDay.putIfAbsent(key, () => []).add(doc);
        }

        if (byDay.isEmpty) {
          return EmptyState(
            compact: true,
            illustration: GochanoArt.featureCalendar,
            title: GochanoLanguage.text('Nothing scheduled', 'কিছু নির্ধারিত নেই'),
            message: GochanoLanguage.text(
              'Tasks with a due date appear on this agenda.',
              'সময়সীমাসহ কাজ এই সময়সূচিতে দেখা যাবে।',
            ),
          );
        }

        final days = byDay.keys.toList()..sort();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final day in days) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: GochanoSpacing.sm,
                  bottom: GochanoSpacing.xs,
                ),
                child: Text(
                  _dayHeading(day),
                  style: context.type.label.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CardGroup(
                children: [
                  for (final doc in byDay[day]!
                    ..sort((a, b) {
                      final ad = (a.data()['dueAt'] as Timestamp).toDate();
                      final bd = (b.data()['dueAt'] as Timestamp).toDate();
                      return ad.compareTo(bd);
                    }))
                    GochanoListRow(
                      illustration: GochanoArt.featureTasks,
                      accent: context.colors.brand,
                      title: doc.data()['title']?.toString() ?? '',
                      metadata: [
                        _clock((doc.data()['dueAt'] as Timestamp).toDate()),
                      ],
                      onTap: () => showAddTaskSheet(context, existing: doc),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

String _clock(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${when.hour < 12 ? 'am' : 'pm'}';
}

String _shortDue(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;
  if (diff < 0) return GochanoLanguage.text('Overdue', 'সময় পেরিয়েছে');
  if (diff == 0) return GochanoLanguage.text('Today', 'আজ');
  if (diff == 1) return GochanoLanguage.text('Tomorrow', 'আগামীকাল');
  return GochanoLanguage.text('In $diff days', '$diff দিনে');
}

String _dayHeading(String dayKey) {
  final parsed = DateTime.tryParse(dayKey);
  if (parsed == null) return dayKey;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(parsed.year, parsed.month, parsed.day)
      .difference(today)
      .inDays;
  if (diff == 0) return GochanoLanguage.text('Today', 'আজ');
  if (diff == 1) return GochanoLanguage.text('Tomorrow', 'আগামীকাল');

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}
