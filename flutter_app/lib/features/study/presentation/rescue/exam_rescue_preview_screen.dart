// Exam Rescue Preview Screen — Phase T3
// Interactive in-memory plan preview screen.
//
// NOTE: T3 DOES NOT persist the plan to Firestore or create tasks.
// Edits and item deletions are strictly in-memory.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'exam_rescue_models.dart';

class ExamRescuePreviewScreen extends StatefulWidget {
  final ExamRescuePlan plan;
  final String initialTitle;
  final DateTime initialDate;
  final int initialDailyMinutes;
  final List<Map<String, String>> initialMaterials;
  final String? initialExtraTopics;

  const ExamRescuePreviewScreen({
    super.key,
    required this.plan,
    required this.initialTitle,
    required this.initialDate,
    required this.initialDailyMinutes,
    this.initialMaterials = const [],
    this.initialExtraTopics,
  });

  @override
  State<ExamRescuePreviewScreen> createState() => _ExamRescuePreviewScreenState();
}

class _ExamRescuePreviewScreenState extends State<ExamRescuePreviewScreen> {
  late ExamRescuePlan _currentPlan;
  bool _isRegenerating = false;

  @override
  void initState() {
    super.initState();
    _currentPlan = widget.plan;
  }

  void _removeItem(int dayIndex, int itemIndex) {
    setState(() {
      final day = _currentPlan.days[dayIndex];
      final newItems = List<ExamRescueItem>.from(day.items)..removeAt(itemIndex);
      final newDay = day.copyWith(items: newItems);
      final newDays = List<ExamRescueDay>.from(_currentPlan.days)..[dayIndex] = newDay;
      final newTotalMinutes = newDays.fold<int>(
        0,
        (sum, d) => sum + d.items.fold<int>(0, (s, it) => s + it.estimatedMinutes),
      );
      _currentPlan = _currentPlan.copyWith(
        days: newDays,
        totalEstimatedMinutes: newTotalMinutes,
      );
    });
  }

  Future<void> _regeneratePlan() async {
    setState(() => _isRegenerating = true);
    try {
      final newPlan = await ApiService.generateExamRescuePlan(
        examTitle: widget.initialTitle,
        examDate: widget.initialDate,
        dailyMinutes: widget.initialDailyMinutes,
        materialIds: widget.initialMaterials
            .map((m) => m['id'] ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
        extraTopics: widget.initialExtraTopics,
      );
      if (mounted) {
        setState(() {
          _currentPlan = newPlan;
          _isRegenerating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isRegenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              GochanoLanguage.text(
                'Failed to regenerate plan. Please try again.',
                'প্ল্যান পুনরায় তৈরি করতে ব্যর্থ হয়েছে।',
              ),
            ),
          ),
        );
      }
    }
  }

  String _formatDaysRemaining(int days) {
    if (GochanoLanguage.current.value == GochanoLocale.bangla) {
      if (days <= 0) return 'পরীক্ষা আজকেই';
      if (days == 1) return '১ দিন বাকি';
      return '${GochanoLanguage.formatNumber(days)} দিন বাকি';
    }
    if (days <= 0) return 'Exam is today';
    if (days == 1) return '1 day remaining';
    return '$days days remaining';
  }

  String _formatDailyBudget(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (GochanoLanguage.current.value == GochanoLocale.bangla) {
      if (m == 0) return '${GochanoLanguage.formatNumber(h)} ঘণ্টা / দিন';
      return '${GochanoLanguage.formatNumber(h)} ঘণ্টা ${GochanoLanguage.formatNumber(m)} মি / দিন';
    }
    if (m == 0) return '${h}h / day';
    return '${h}h ${m}m / day';
  }

  String _formatTotalHours(int minutes) {
    final hours = (minutes / 60).round();
    if (GochanoLanguage.current.value == GochanoLocale.bangla) {
      return 'মোট: ${GochanoLanguage.formatNumber(hours)} ঘণ্টা';
    }
    return 'Total: ${hours}h';
  }

  Color _badgeColorForType(String type, BuildContext context) {
    final colors = context.colors;
    switch (type.toLowerCase()) {
      case 'study':
        return colors.brand;
      case 'practice':
        return colors.info;
      case 'quiz':
        return colors.ai;
      case 'revision':
        return colors.warning;
      default:
        return colors.brand;
    }
  }

  String _labelForType(String type) {
    switch (type.toLowerCase()) {
      case 'study':
        return GochanoLanguage.text('Study', 'পড়ুন');
      case 'practice':
        return GochanoLanguage.text('Practice', 'অনুশীলন');
      case 'quiz':
        return GochanoLanguage.text('Quiz', 'কুইজ');
      case 'revision':
        return GochanoLanguage.text('Revision', 'রিভিশন');
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GochanoLanguage.text('Exam Rescue', 'এক্সাম রেসকিউ'),
              style: type.caption.copyWith(
                color: colors.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              GochanoLanguage.text('Rescue Plan Preview', 'রেসকিউ প্ল্যান প্রিভিউ'),
              style: type.body.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fallback transparency banner
            if (_currentPlan.generationMode == 'fallback')
              Container(
                margin: const EdgeInsets.only(bottom: GochanoSpacing.md),
                padding: const EdgeInsets.all(GochanoSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.warningSoft,
                  borderRadius: GochanoRadius.mdAll,
                  border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: colors.warning),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          "Quick recovery plan created using Gochano's fallback planner.",
                          "গচানোর ব্যাকআপ প্ল্যানার দিয়ে দ্রুত উদ্ধার প্ল্যান তৈরি করা হয়েছে।",
                        ),
                        style: type.caption.copyWith(color: colors.warning),
                      ),
                    ),
                  ],
                ),
              ),

            // Hero stats card
            AppCard(
              accent: colors.brand,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentPlan.examTitle.toUpperCase(),
                    style: type.sectionHeading.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  Wrap(
                    spacing: GochanoSpacing.sm,
                    runSpacing: GochanoSpacing.xs,
                    children: [
                      _buildHeroStatChip(
                        Icons.calendar_today_outlined,
                        _formatDaysRemaining(_currentPlan.daysRemaining),
                        colors.brand,
                        colors.brandSoft,
                      ),
                      _buildHeroStatChip(
                        Icons.schedule_outlined,
                        _formatDailyBudget(widget.initialDailyMinutes),
                        colors.info,
                        colors.infoSoft,
                      ),
                      _buildHeroStatChip(
                        Icons.hourglass_bottom_outlined,
                        _formatTotalHours(_currentPlan.totalEstimatedMinutes),
                        colors.study,
                        colors.study.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.md),
                  // Source mode badge
                  if (_currentPlan.sourceMode == 'materials') ...[
                    Row(
                      children: [
                        Icon(Icons.folder_outlined, size: 16, color: colors.brand),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              'Based on your selected materials',
                              'আপনার নির্বাচিত মেটেরিয়াল অনুযায়ী',
                            ),
                            style: type.bodySecondary.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.brand,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.initialMaterials.isNotEmpty) ...[
                      const SizedBox(height: GochanoSpacing.xs),
                      Wrap(
                        spacing: GochanoSpacing.xs,
                        runSpacing: GochanoSpacing.xxs,
                        children: widget.initialMaterials.map((m) {
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              m['title'] ?? 'Material',
                              style: type.caption,
                            ),
                            backgroundColor: colors.surfaceVariant,
                          );
                        }).toList(),
                      ),
                    ],
                  ] else ...[
                    Row(
                      children: [
                        Icon(Icons.auto_stories_outlined, size: 16, color: colors.textSecondary),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              'General subject-based plan',
                              'সাধারণ বিষয়-ভিত্তিক প্ল্যান',
                            ),
                            style: type.bodySecondary.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),

            // AI Rescue Strategy Summary
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.psychology_outlined, size: 20, color: colors.brand),
                      const SizedBox(width: GochanoSpacing.xs),
                      Text(
                        GochanoLanguage.text('AI Rescue Strategy', 'এআই রেসকিউ কৌশল'),
                        style: type.sectionHeading.copyWith(color: colors.brand),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    _currentPlan.strategySummary,
                    style: type.body,
                  ),
                ],
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),

            // Day Cards
            ..._currentPlan.days.asMap().entries.map((dayEntry) {
              final dayIdx = dayEntry.key;
              final day = dayEntry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: GochanoSpacing.md),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: GochanoSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.brandSoft,
                              borderRadius: GochanoRadius.smAll,
                            ),
                            child: Text(
                              GochanoLanguage.text(
                                'DAY ${day.dayNumber}',
                                'দিন ${GochanoLanguage.formatNumber(day.dayNumber)}',
                              ),
                              style: type.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.brand,
                              ),
                            ),
                          ),
                          const SizedBox(width: GochanoSpacing.xs),
                          Expanded(
                            child: Text(
                              day.theme,
                              style: type.body.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${day.targetMinutes}m',
                            style: type.caption.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                      const Divider(height: GochanoSpacing.md),
                      ...day.items.asMap().entries.map((itemEntry) {
                        final itemIdx = itemEntry.key;
                        final item = itemEntry.value;
                        return _buildItemRow(dayIdx, itemIdx, item);
                      }),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: GochanoSpacing.xl),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: GochanoLanguage.text('Edit / Back', 'এডিট / ফিরে যান'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: PrimaryButton(
                  label: GochanoLanguage.text('Regenerate', 'আবার তৈরি করুন'),
                  busy: _isRegenerating,
                  busyLabel: GochanoLanguage.text('Regenerating…', 'পুনরায় তৈরি হচ্ছে…'),
                  onPressed: _regeneratePlan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStatChip(IconData icon, String text, Color color, Color bg) {
    final type = context.type;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.sm,
        vertical: GochanoSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: GochanoRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: type.caption.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(int dayIdx, int itemIdx, ExamRescueItem item) {
    final colors = context.colors;
    final type = context.type;
    final badgeColor = _badgeColorForType(item.type, context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.xs,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: GochanoRadius.smAll,
            ),
            child: Text(
              _labelForType(item.type),
              style: type.caption.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: type.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.actionNote.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.actionNote,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (item.hasMaterial) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file_rounded, size: 12, color: colors.brand),
                      const SizedBox(width: 2),
                      Text(
                        GochanoLanguage.text('Linked material', 'সংযুক্ত মেটেরিয়াল'),
                        style: type.caption.copyWith(
                          fontSize: 10,
                          color: colors.brand,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Text(
            '${item.estimatedMinutes}m',
            style: type.caption.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Remove item',
            onPressed: () => _removeItem(dayIdx, itemIdx),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
