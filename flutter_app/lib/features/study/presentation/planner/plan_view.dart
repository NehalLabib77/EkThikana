// Combined Plan dashboard (spec §40).
//
// Merges the former Tasks and Planner tabs into a single "Plan" view that
// answers the question "what should I work on today?" in one scroll.
//
// Sections:
//   1. Date / week strip — 7-day selector with a "Today" shortcut.
//   2. Today's Schedule — tasks due on the selected day.
//   3+4. Assignments & Tasks — single combined card with two sections.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_dates.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/notification_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../../shared/widgets/related_chips.dart';
import '../../../tasks/presentation/add_task_sheet.dart';
import '../ai/ai_assistant_screen.dart';

class PlanView extends StatefulWidget {
  const PlanView({super.key});

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    GochanoLanguage.current.addListener(_onLanguageChange);
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageChange);
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _DateStrip(
            selectedDay: _selectedDay,
            onDaySelected: (day) => setState(() => _selectedDay = day),
          ),
          const SizedBox(height: GochanoSpacing.md),
          _CombinedPlannerList(selectedDay: _selectedDay),
          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Date / Week strip
// ---------------------------------------------------------------------------

class _DateStrip extends StatefulWidget {
  const _DateStrip({required this.selectedDay, required this.onDaySelected});

  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  late final ScrollController _scrollController;
  static const _cellWidth = 44.0 + 8.0; // cell width + right margin
  static const _visibleBeforeToday = 2;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToToday() {
    if (!_scrollController.hasClients) return;
    final totalDays = _totalDays;
    final todayIndex = totalDays - 15; // today is 15 days from start
    final targetOffset = (todayIndex - _visibleBeforeToday) * _cellWidth;
    _scrollController.jumpTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  static const _totalDays = 31; // ~1 month of scrollable dates

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(const Duration(days: 15));
    final days = List.generate(
      _totalDays,
      (i) => startDate.add(Duration(days: i)),
    );

    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const banglaMonths = [
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];
    final currentMonth =
        '${months[widget.selectedDay.month - 1]} ${widget.selectedDay.year}';
    final currentMonthBn =
        '${banglaMonths[widget.selectedDay.month - 1]} ${widget.selectedDay.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                GochanoLanguage.text(currentMonth, currentMonthBn),
                style: context.type.sectionHeading,
              ),
            ),
            TextButton(
              onPressed: () {
                widget.onDaySelected(today);
                _scrollToToday();
              },
              child: Text(GochanoLanguage.text('Today', 'আজ')),
            ),
          ],
        ),
        const SizedBox(height: GochanoSpacing.xs),
        SizedBox(
          height: 56,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final isSelected =
                  DateTime(day.year, day.month, day.day) ==
                  DateTime(
                    widget.selectedDay.year,
                    widget.selectedDay.month,
                    widget.selectedDay.day,
                  );
              final isToday = day == today;
              final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

              return GestureDetector(
                onTap: () => widget.onDaySelected(day),
                child: Container(
                  width: 44,
                  margin: const EdgeInsets.only(right: GochanoSpacing.xs),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.brand
                        : isToday
                        ? colors.brandSoft
                        : colors.surface,
                    borderRadius: GochanoRadius.mdAll,
                    border: isToday && !isSelected
                        ? Border.all(color: colors.brand, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dayNames[day.weekday % 7],
                        style: context.type.caption.copyWith(
                          color: isSelected
                              ? Colors.white
                              : colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: context.type.cardHeading.copyWith(
                          color: isSelected ? Colors.white : colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Combined Tasks & Assignments — single chronological list with category badges
// ---------------------------------------------------------------------------

class _CombinedPlannerList extends StatelessWidget {
  const _CombinedPlannerList({required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) return const SizedBox.shrink();

        final dayKey = DateTime(
          selectedDay.year,
          selectedDay.month,
          selectedDay.day,
        );
        final endOfDay = dayKey.add(const Duration(days: 1));

        final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) continue;
          final due = (data['dueAt'] as Timestamp?)?.toDate();
          if (due == null) continue;
          if (!due.isBefore(dayKey) && due.isBefore(endOfDay)) {
            docs.add(doc);
          }
        }

        // Sort by dueAt ascending (items with no due go last).
        docs.sort((a, b) {
          final ad = (a.data()['dueAt'] as Timestamp?)?.toDate();
          final bd = (b.data()['dueAt'] as Timestamp?)?.toDate();
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });

        if (docs.isEmpty) {
          return AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GochanoIllustration(
                  GochanoArt.emptyTasks,
                  size: GochanoSizes.illustrationEmpty,
                  accent: context.colors.textTertiary,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text(
                    'Nothing due on this day.',
                    'এই দিনে কিছু নেই।',
                  ),
                  style: context.type.sectionHeading,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          showAddTaskSheet(context, initialDate: selectedDay),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        GochanoLanguage.text('Add task', 'কাজ যোগ করুন'),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => showAddTaskSheet(
                        context,
                        type: 'assignment',
                        initialDate: selectedDay,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        GochanoLanguage.text(
                          'Add assignment',
                          'অ্যাসাইনমেন্ট যোগ করুন',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return AppCard(
          padding: const EdgeInsets.all(GochanoSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_rounded,
                    size: 14,
                    color: context.colors.brand,
                  ),
                  const SizedBox(width: GochanoSpacing.xxs),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('Due this day', 'এই দিনের কাজ'),
                      style: context.type.label.copyWith(
                        fontSize: 13,
                        color: context.colors.brand,
                      ),
                    ),
                  ),
                  GochanoBadge(
                    label: '${docs.length}',
                    tone: GochanoBadgeTone.brand,
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  _HistoryButton(),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              for (final doc in docs) ...[
                _PlannerItemRow(doc: doc),
                if (doc != docs.last)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Divider(height: 1, color: context.colors.border),
                  ),
              ],
              const SizedBox(height: GochanoSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showAddTaskSheet(
                        context,
                        type: 'task',
                        initialDate: selectedDay,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(GochanoLanguage.text('Task', 'কাজ')),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showAddTaskSheet(
                        context,
                        type: 'assignment',
                        initialDate: selectedDay,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(
                        GochanoLanguage.text('Assignment', 'অ্যাসাইনমেন্ট'),
                      ),
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
// 3+4. Single planner row — shows category badge, title, due, and actions
// ---------------------------------------------------------------------------

class _PlannerItemRow extends StatefulWidget {
  const _PlannerItemRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  State<_PlannerItemRow> createState() => _PlannerItemRowState();
}

class _PlannerItemRowState extends State<_PlannerItemRow> {
  bool? _materialExists; // null = unknown, true = exists, false = deleted

  @override
  void initState() {
    super.initState();
    _checkMaterial();
  }

  Future<void> _checkMaterial() async {
    final materialId = widget.doc.data()['relatedMaterialId']?.toString();
    if (materialId == null || materialId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('materials')
          .doc(materialId)
          .get();
      if (mounted) {
        setState(() {
          _materialExists = snap.exists;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _materialExists = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final done = data['done'] == true;
    final title = data['title']?.toString() ?? '';
    final due = (data['dueAt'] as Timestamp?)?.toDate();
    final overdue = !done && due != null && due.isBefore(DateTime.now());
    final isAssignment = data['type']?.toString() == 'assignment';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: done,
              onChanged: (value) => _setDone(context, widget.doc, value ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isAssignment
                  ? context.colors.brand.withValues(alpha: 0.10)
                  : context.colors.study.withValues(alpha: 0.10),
              borderRadius: GochanoRadius.smAll,
            ),
            child: Text(
              isAssignment
                  ? GochanoLanguage.text('Asm', 'অ্যাস')
                  : GochanoLanguage.text('Task', 'কাজ'),
              style: context.type.caption.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isAssignment
                    ? context.colors.brand
                    : context.colors.study,
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          Expanded(
            child: InkWell(
              onTap: () => showAddTaskSheet(context, existing: widget.doc),
              borderRadius: GochanoRadius.smAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: context.type.body.copyWith(
                        fontSize: 13,
                        color: done ? context.colors.textSecondary : null,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (due != null)
                      Text(
                        '${formatShortDate(due)} ${formatClock12(due)}',
                        style: context.type.caption.copyWith(
                          fontSize: 10,
                          color: overdue
                              ? context.colors.warning
                              : context.colors.textTertiary,
                        ),
                      ),
                    // Phase 5: optional cross-module relationship chips.
                    if (data['relatedNoteId'] != null ||
                        data['relatedMaterialId'] != null) ...[
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          if (data['relatedNoteId'] != null)
                            RelatedNoteChip(
                              noteId: data['relatedNoteId'].toString(),
                            ),
                          if (data['relatedMaterialId'] != null)
                            RelatedMaterialChip(
                              materialId:
                                  data['relatedMaterialId'].toString(),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          GochanoOverflowMenu(
            items: [
              GochanoMenuAction(
                label: GochanoLanguage.text('Ask AI about this', 'এই বিষয়ে জিজ্ঞাসা করুন'),
                icon: Icons.psychology_rounded,
                onSelected: () {
                  Navigator.of(context).push(
                    GochanoRoute.to(
                      builder: (_) => AiAssistantScreen(
                        prefilledQuestion: 'Help me understand how to approach: ${widget.doc['title'] ?? ''}',
                        enableContext: true,
                      ),
                    ),
                  );
                },
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
                icon: Icons.edit_outlined,
                onSelected: () => showAddTaskSheet(context, existing: widget.doc),
              ),
              GochanoMenuAction(
                label: done
                    ? GochanoLanguage.text('Mark not done', 'অসম্পন্ন করুন')
                    : GochanoLanguage.text('Mark done', 'সম্পন্ন করুন'),
                icon: done ? Icons.undo_rounded : Icons.check_rounded,
                onSelected: () => _setDone(context, widget.doc, !done),
              ),
              if ((data['relatedMaterialId'] as String?)?.isNotEmpty ==
                      true &&
                  _materialExists == true)
                GochanoMenuAction(
                  label: GochanoLanguage.text(
                    'Plan with this material',
                    'এই উপকরণ দিয়ে পরিকল্পনা',
                  ),
                  icon: Icons.menu_book_rounded,
                  onSelected: () async {
                    final materialId =
                        data['relatedMaterialId'] as String;
                    final materialSnap = await FirebaseFirestore
                        .instance
                        .collection('materials')
                        .doc(materialId)
                        .get();
                    if (!context.mounted) return;
                    final mData = materialSnap.data();
                    if (mData == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(GochanoLanguage.text(
                            'This material is no longer available.',
                            'এই উপকরণ আর পাওয়া যাচ্ছে না।',
                          )),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      GochanoRoute.to(
                        builder: (_) => AiAssistantScreen(
                          contextMaterialId: materialId,
                          contextMaterialTitle:
                              mData['title']?.toString() ??
                                  title,
                          contextMimeType:
                              mData['mimeType']?.toString(),
                          contextFileName:
                              mData['fileName']?.toString(),
                          enableContext: true,
                          prefilledQuestion:
                              'Using this assignment and the linked material, help me decide what to study first: $title',
                        ),
                      ),
                    );
                  },
                ),
              if ((data['relatedMaterialId'] as String?)?.isNotEmpty ==
                      true &&
                  _materialExists == null)
                GochanoMenuAction(
                  label: GochanoLanguage.text(
                    'Plan with this material',
                    'এই উপকরণ দিয়ে পরিকল্পনা',
                  ),
                  icon: Icons.menu_book_rounded,
                  enabled: false,
                  onSelected: () {},
                ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Delete', 'মুছুন'),
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onSelected: () => _delete(context, widget.doc, title),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Completed History button + sheet
// ---------------------------------------------------------------------------

class _HistoryButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(
          Icons.history_rounded,
          size: 20,
          color: colors.textSecondary,
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: GochanoLanguage.text(
          'Completed history',
          'সম্পন্ন ইতিহাস',
        ),
        onPressed: () => _showCompletedHistory(context),
      ),
    );
  }
}

void _showCompletedHistory(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CompletedHistorySheet(),
  );
}

class _CompletedHistorySheet extends StatelessWidget {
  const _CompletedHistorySheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: GochanoRadius.sheet,
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: GochanoSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GochanoSpacing.md,
                  vertical: GochanoSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 20,
                      color: colors.brand,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          'Completed',
                          'সম্পন্ন',
                        ),
                        style: context.type.sectionHeading,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      tooltip: GochanoLanguage.text('Close', 'বন্ধ'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _CompletedHistoryList(scrollController: scrollController),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CompletedHistoryList extends StatelessWidget {
  const _CompletedHistoryList({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks', limit: 500),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Text(
              GochanoLanguage.text('Loading…', 'লোড হচ্ছে…'),
              style: context.type.bodySecondary,
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              GochanoLanguage.text(
                'Unable to load history',
                'ইতিহাস লোড হয়নি',
              ),
              style: context.type.bodySecondary,
            ),
          );
        }

        final completedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in [...?snapshot.data?.docs]) {
          final data = doc.data();
          if (data['done'] == true) {
            completedDocs.add(doc);
          }
        }

        completedDocs.sort((a, b) {
          final aUpdated = a.data()['updatedAt'] as Timestamp?;
          final bUpdated = b.data()['updatedAt'] as Timestamp?;
          if (aUpdated == null && bUpdated == null) return 0;
          if (aUpdated == null) return 1;
          if (bUpdated == null) return -1;
          return bUpdated.compareTo(aUpdated);
        });

        if (completedDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GochanoIllustration(
                  GochanoArt.emptyTasks,
                  size: GochanoSizes.illustrationEmpty,
                  accent: colors.textTertiary,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text(
                    'No completed items yet.',
                    'এখনো কিছু সম্পন্ন হয়নি।',
                  ),
                  style: context.type.sectionHeading,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: GochanoSpacing.md,
            vertical: GochanoSpacing.xs,
          ),
          itemCount: completedDocs.length,
          itemBuilder: (context, index) {
            final doc = completedDocs[index];
            final data = doc.data();
            final title = data['title']?.toString() ?? '';
            final due = (data['dueAt'] as Timestamp?)?.toDate();
            final completedAt = (data['updatedAt'] as Timestamp?)?.toDate();
            final isAssignment = data['type']?.toString() == 'assignment';

            return Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: colors.success,
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isAssignment
                          ? colors.brand.withValues(alpha: 0.10)
                          : colors.study.withValues(alpha: 0.10),
                      borderRadius: GochanoRadius.smAll,
                    ),
                    child: Text(
                      isAssignment
                          ? GochanoLanguage.text('Asm', 'অ্যাস')
                          : GochanoLanguage.text('Task', 'কাজ'),
                      style: context.type.caption.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isAssignment ? colors.brand : colors.study,
                      ),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: context.type.body.copyWith(
                            fontSize: 13,
                            color: colors.textSecondary,
                            decoration: TextDecoration.lineThrough,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (due != null)
                          Text(
                            GochanoLanguage.text(
                              'Due: ${formatShortDate(due)}',
                              'বাকি: ${formatShortDate(due)}',
                            ),
                            style: context.type.caption.copyWith(
                              fontSize: 10,
                              color: colors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (completedAt != null)
                    Text(
                      _formatCompletedDate(completedAt),
                      style: context.type.caption.copyWith(
                        fontSize: 10,
                        color: colors.textTertiary,
                      ),
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

String _formatCompletedDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dateOnly = DateTime(date.year, date.month, date.day);
  final diff = today.difference(dateOnly).inDays;

  if (diff == 0) {
    return GochanoLanguage.text('Today', 'আজ');
  } else if (diff == 1) {
    return GochanoLanguage.text('Yesterday', 'গতকাল');
  } else if (diff < 7) {
    return GochanoLanguage.text(
      // ignore: unnecessary_brace_in_string_interps
      '${diff}d ago',
      // ignore: unnecessary_brace_in_string_interps
      '${diff}দি আগে',
    );
  } else {
    return formatShortDate(date);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _setDone(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  bool done,
) async {
  final data = doc.data();
  final title = data['title']?.toString() ?? '';
  final remindAt = (data['remindAt'] as Timestamp?)?.toDate();

  try {
    await doc.reference.update({
      'done': done,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await NotificationService.rescheduleTask(
      taskId: doc.id,
      title: title,
      when: done ? null : remindAt,
    );
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _delete(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  String title,
) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Delete this task?', 'কাজটি মুছবেন?'),
    message: title,
    confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
  );
  if (!confirmed || !context.mounted) return;
  try {
    await NotificationService.cancelTask(doc.id);
    await doc.reference.delete();
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}
