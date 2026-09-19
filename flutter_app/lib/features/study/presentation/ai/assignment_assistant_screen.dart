// Assignment Assistant — AI-powered help for understanding assignments.
//
// Provides three modes:
// 1. Explain — what the assignment requires
// 2. Breakdown — structured outline of sections/concepts
// 3. Plan — deadline-aware study plan
//
// Learning assistance only — never generates cheating answers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

enum _AssignmentMode { explain, breakdown, plan }

class AssignmentAssistantScreen extends StatefulWidget {
  const AssignmentAssistantScreen({
    super.key,
    this.initialTitle,
    this.initialDescription,
    this.initialDeadline,
  });

  final String? initialTitle;
  final String? initialDescription;
  final String? initialDeadline;

  @override
  State<AssignmentAssistantScreen> createState() =>
      _AssignmentAssistantScreenState();
}

class _AssignmentAssistantScreenState extends State<AssignmentAssistantScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _deadlineCtrl = TextEditingController();

  _AssignmentMode _mode = _AssignmentMode.explain;
  bool _busy = false;
  String _result = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialTitle != null) _titleCtrl.text = widget.initialTitle!;
    if (widget.initialDescription != null) {
      _descCtrl.text = widget.initialDescription!;
    }
    if (widget.initialDeadline != null) {
      _deadlineCtrl.text = widget.initialDeadline!;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _instructionsCtrl.dispose();
    _deadlineCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = GochanoLanguage.text(
        'Please enter an assignment title.',
        'অনুগ্রহ করে একটি এসাইনমেন্টের শিরোনাম লিখুন।',
      ));
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
      _result = '';
    });

    try {
      String result;
      switch (_mode) {
        case _AssignmentMode.explain:
          result = await ApiService.assignmentExplain(
            title: title,
            description: _descCtrl.text.trim(),
            instructions: _instructionsCtrl.text.trim(),
          );
        case _AssignmentMode.breakdown:
          result = await ApiService.assignmentBreakdown(
            title: title,
            description: _descCtrl.text.trim(),
            instructions: _instructionsCtrl.text.trim(),
            deadline: _deadlineCtrl.text.trim().isEmpty
                ? null
                : _deadlineCtrl.text.trim(),
          );
        case _AssignmentMode.plan:
          final deadline = _deadlineCtrl.text.trim();
          if (deadline.isEmpty) {
            setState(() {
              _busy = false;
              _error = GochanoLanguage.text(
                'Please enter a deadline for the study plan.',
                'পড়ার পরিকল্পনার জন্য অনুগ্রহ করে একটি সময়সীমা লিখুন।',
              );
            });
            return;
          }
          result = await ApiService.assignmentPlan(
            title: title,
            description: _descCtrl.text.trim(),
            instructions: _instructionsCtrl.text.trim(),
            deadline: deadline,
          );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          'Assignment Assistant',
          'এসাইনমেন্ট সহকারী',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.sm,
          GochanoSpacing.md,
          120,
        ),
        children: [
          // Mode selector
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GochanoLanguage.text('What do you need help with?', 'আপনার কী সাহায্য দরকার?'),
                  style: context.type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                _ModeChip(
                  label: GochanoLanguage.text('Explain', 'ব্যাখ্যা'),
                  icon: Icons.lightbulb_outline_rounded,
                  selected: _mode == _AssignmentMode.explain,
                  onTap: () => setState(() => _mode = _AssignmentMode.explain),
                ),
                _ModeChip(
                  label: GochanoLanguage.text('Breakdown', 'বিশ্লেষণ'),
                  icon: Icons.list_alt_rounded,
                  selected: _mode == _AssignmentMode.breakdown,
                  onTap: () => setState(() => _mode = _AssignmentMode.breakdown),
                ),
                _ModeChip(
                  label: GochanoLanguage.text('Study Plan', 'পড়ার পরিকল্পনা'),
                  icon: Icons.calendar_today_rounded,
                  selected: _mode == _AssignmentMode.plan,
                  onTap: () => setState(() => _mode = _AssignmentMode.plan),
                ),
              ],
            ),
          ),

          const SizedBox(height: GochanoSpacing.sm),

          // Input fields
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GochanoLanguage.text('Assignment Details', 'এসাইনমেন্টের বিবরণ'),
                  style: context.type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Title *', 'শিরোনাম *'),
                    hintText: GochanoLanguage.text(
                      'e.g., Database Normalization Report',
                      'যেমন, ডাটাবেজ নরমালাইজেশন রিপোর্ট',
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Description', 'বিবরণ'),
                    hintText: GochanoLanguage.text(
                      'What the assignment is about…',
                      'এসাইনমেন্টটি কী নিয়ে…',
                    ),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _instructionsCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Instructions', 'নির্দেশনা'),
                    hintText: GochanoLanguage.text(
                      'Any specific requirements…',
                      'যেকোনো নির্দিষ্ট প্রয়োজনীয়তা…',
                    ),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
                if (_mode == _AssignmentMode.plan) ...[
                  const SizedBox(height: GochanoSpacing.sm),
                  TextField(
                    controller: _deadlineCtrl,
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text('Deadline *', 'সময়সীমা *'),
                      hintText: GochanoLanguage.text(
                        'e.g., 2026-09-25',
                        'যেমন, ২০২৬-০৯-২৫',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: GochanoSpacing.md),

          // Run button
          PrimaryButton(
            label: GochanoLanguage.text('Get Help', 'সাহায্য নিন'),
            icon: Icons.auto_awesome_rounded,
            busy: _busy,
            busyLabel: GochanoLanguage.text(
              'Thinking…',
              'ভাবছে…',
            ),
            onPressed: _run,
          ),

          // Error
          if (_error.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(_error, style: context.type.bodySecondary.copyWith(color: colors.error)),
                  ),
                ],
              ),
            ),
          ],

          // Result
          if (_result.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            AppCard(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 18, color: colors.ai),
                      const SizedBox(width: GochanoSpacing.xs),
                      Expanded(
                        child: Text(
                          GochanoLanguage.text('AI Response', 'এআই উত্তর'),
                          style: context.type.cardHeading.copyWith(color: colors.ai),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _result));
                          showGochanoMessage(context, GochanoLanguage.text('Copied', 'কপি হয়েছে'));
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 14, color: colors.textTertiary),
                            const SizedBox(width: 4),
                            Text(
                              GochanoLanguage.text('Copy', 'কপি'),
                              style: context.type.caption.copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  SelectableText(_result, style: context.type.body),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: GochanoSpacing.sm,
            vertical: GochanoSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.ai.withValues(alpha: 0.12) : colors.surfaceVariant,
            borderRadius: GochanoRadius.mdAll,
            border: Border.all(
              color: selected ? colors.ai : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? colors.ai : colors.textSecondary),
              const SizedBox(width: GochanoSpacing.xs),
              Text(
                label,
                style: context.type.body.copyWith(
                  color: selected ? colors.ai : colors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
