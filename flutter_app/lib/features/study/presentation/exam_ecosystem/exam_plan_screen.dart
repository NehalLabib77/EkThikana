/// Phase 15.3 — Exam Plan Screen.
///
/// Displays the personalized exam roadmap, daily study blocks,
/// phase timeline, and allows creating or recalculating plans.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../services/api_service.dart';
import 'exam_ecosystem_models.dart';

class ExamPlanScreen extends StatefulWidget {
  const ExamPlanScreen({super.key, this.plan});

  static const routeName = '/exam-plan';

  final ExamPlan? plan;

  @override
  State<ExamPlanScreen> createState() => _ExamPlanScreenState();
}

class _ExamPlanScreenState extends State<ExamPlanScreen> {
  bool _loading = true;
  bool _recalculating = false;
  String? _error;
  ExamPlan? _plan;
  List<StudyBlock> _todayBlocks = [];

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
    _loadPlanData();
  }

  Future<void> _loadPlanData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_plan == null) {
        final res = await ApiService.getActivePlan();
        final planJson = res['plan'] as Map<String, dynamic>?;
        if (planJson != null) {
          _plan = ExamPlan.fromJson(planJson);
        }
      }

      if (_plan != null) {
        final todayRes = await ApiService.getPlanToday(_plan!.planId);
        final list = todayRes['today'] as List<dynamic>? ?? [];
        _todayBlocks = list
            .map((e) => StudyBlock.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load exam plan.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recalculate() async {
    if (_plan == null) return;
    setState(() => _recalculating = true);
    try {
      final res = await ApiService.recalculatePlan(_plan!.planId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Study plan updated based on recent progress')),
      );
      _plan = ExamPlan.fromJson(res);
      await _loadPlanData();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  void _showCreatePlanDialog() {
    final nameCtrl = TextEditingController(text: 'Final Exam');
    final minutesCtrl = TextEditingController(text: '120');
    DateTime selectedDate = DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create Exam Study Plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Exam Name',
                    hintText: 'e.g. HSC Physics 2026',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exam Date'),
                  subtitle: Text(
                    '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} (${selectedDate.difference(DateTime.now()).inDays} days)',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Daily Study Minutes',
                    hintText: '120',
                    suffixText: 'mins',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final dateStr =
                    '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                final minutes = int.tryParse(minutesCtrl.text) ?? 120;
                try {
                  final res = await ApiService.createExamPlan(
                    examName: nameCtrl.text.trim(),
                    examDate: dateStr,
                    dailyMinutes: minutes,
                    forceNew: true,
                  );
                  _plan = ExamPlan.fromJson(res);
                  _loadPlanData();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to create plan: $e')),
                    );
                  }
                }
              },
              child: const Text('Create Plan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: colors.border, height: 0.5),
        ),
        title: Text(
          _plan != null ? _plan!.examName : 'Exam Study Plan',
          style: type.cardHeading.copyWith(fontSize: 17),
        ),
        actions: [
          if (_plan != null)
            IconButton(
              icon: _recalculating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.sync_rounded, color: colors.brand),
              onPressed: _recalculating ? null : _recalculate,
              tooltip: 'Recalculate Plan',
            ),
          IconButton(
            icon: Icon(Icons.add_rounded, color: colors.brand),
            onPressed: _showCreatePlanDialog,
            tooltip: 'New Plan',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: colors.brand),
                        onPressed: _loadPlanData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _plan == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.brand.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.event_note_rounded, size: 48, color: colors.brand),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Active Exam Plan',
                              style: type.cardHeading,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create a roadmap targeted at your upcoming exam date (3, 7, 14, 30, or 45 days).',
                              textAlign: TextAlign.center,
                              style: type.bodySecondary,
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: colors.brand),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Create Exam Plan'),
                              onPressed: _showCreatePlanDialog,
                            ),
                          ],
                        ),
                      ),
                    )
                  : AppPageBackground(
                      height: 240,
                      gradient: isDark
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                colors.brand.withValues(alpha: 0.12),
                                colors.background,
                              ],
                            )
                          : AppGradients.planPage,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildPlanOverview(context),
                          const SizedBox(height: 16),
                          _buildTodaySection(context),
                          const SizedBox(height: 16),
                          _buildGuidanceCard(context, isDark),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildPlanOverview(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final days = _plan!.daysRemaining;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.brand.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: colors.brand.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _plan!.examName,
                style: type.cardHeading,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.brand.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$days Days Left',
                  style: TextStyle(
                    color: colors.brand,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(
                label: 'Duration',
                value: '${_plan!.durationDays} days',
              ),
              _StatTile(
                label: 'Target Date',
                value: _plan!.examDate,
              ),
              _StatTile(
                label: 'Daily Target',
                value: '${_plan!.dailyMinutes} mins',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySection(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Today's Study Schedule",
              style: type.cardHeading,
            ),
            Text(
              'Max 4 blocks/day',
              style: type.caption,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_todayBlocks.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceVariant.withValues(alpha: 0.5),
              borderRadius: GochanoRadius.mdAll,
              border: Border.all(color: colors.border),
            ),
            child: Center(
              child: Text(
                'No blocks scheduled for today.',
                style: type.bodySecondary,
              ),
            ),
          )
        else
          ..._todayBlocks.map((b) => _PlanBlockTile(block: b)),
      ],
    );
  }

  Widget _buildGuidanceCard(BuildContext context, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: isDark ? null : AppGradients.zikuCoach,
        color: isDark ? colors.ai.withValues(alpha: 0.12) : null,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.ai.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.ai.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lightbulb_outline_rounded, size: 18, color: colors.ai),
              ),
              const SizedBox(width: 8),
              Text(
                'Adaptive Plan Rules',
                style: type.cardHeading,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Critical and High priority topics receive more study blocks.\n'
            '• Overdue spaced-repetition items are scheduled automatically.\n'
            '• Strong topics are included for maintenance revision.\n'
            '• Recalculate whenever you complete major practice sessions.',
            style: type.bodySecondary.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: type.caption,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: type.body.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _PlanBlockTile extends StatelessWidget {
  const _PlanBlockTile({required this.block});
  final StudyBlock block;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.brand.withValues(alpha: 0.25)),
            ),
            child: Text(
              block.blockTypeLabel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: colors.brand,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.topic,
                  style: type.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (block.reason.isNotEmpty)
                  Text(
                    block.reason,
                    style: type.caption,
                  ),
              ],
            ),
          ),
          Text(
            '${block.durationMinutes} min',
            style: type.caption,
          ),
        ],
      ),
    );
  }
}
