// Smart Study Planner AI — AI-powered daily study recommendations.
//
// Uses the user's tasks, assignments, and deadlines to generate
// personalized study recommendations for today.
// Does NOT replace the existing deterministic planner.

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

class SmartPlannerScreen extends StatefulWidget {
  const SmartPlannerScreen({super.key});

  @override
  State<SmartPlannerScreen> createState() => _SmartPlannerScreenState();
}

class _SmartPlannerScreenState extends State<SmartPlannerScreen> {
  int _availableHours = 4;
  final _subjectsCtrl = TextEditingController();

  bool _busy = false;
  String _recommendation = '';
  String _error = '';

  @override
  void dispose() {
    _subjectsCtrl.dispose();
    super.dispose();
  }

  Future<void> _getRecommendation() async {
    setState(() {
      _busy = true;
      _error = '';
      _recommendation = '';
    });

    try {
      final subjects = _subjectsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final result = await ApiService.smartPlannerRecommend(
        availableHours: _availableHours,
        preferredSubjects: subjects,
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        _recommendation = result;
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
        title: GochanoLanguage.text('Smart Planner', 'স্মার্ট প্ল্যানার'),
        subtitle: GochanoLanguage.text(
          'AI-powered daily recommendations',
          'এআই-চালিত দৈনিক সুপারিশ',
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
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GochanoLanguage.text('Today\'s Settings', 'আজকের সেটিংস'),
                  style: context.type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text(
                    'How many hours can you study today?',
                    'আজ আপনি কত ঘণ্টা পড়তে পারবেন?',
                  ),
                  style: context.type.bodySecondary,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Row(
                  children: [
                    for (final h in [2, 4, 6, 8]) ...[
                      if (h != 2) const SizedBox(width: GochanoSpacing.xs),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _availableHours = h),
                          borderRadius: GochanoRadius.mdAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.sm),
                            decoration: BoxDecoration(
                              color: _availableHours == h
                                  ? colors.ai.withValues(alpha: 0.12)
                                  : colors.surfaceVariant,
                              borderRadius: GochanoRadius.mdAll,
                              border: Border.all(
                                color: _availableHours == h ? colors.ai : Colors.transparent,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${h}h',
                              style: context.type.body.copyWith(
                                color: _availableHours == h ? colors.ai : colors.textPrimary,
                                fontWeight: _availableHours == h ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _subjectsCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Preferred subjects (comma-separated)',
                      'পছন্দের বিষয় (কমা দ্বারা আলাদা)',
                    ),
                    hintText: GochanoLanguage.text(
                      'e.g., Database, OS, Programming',
                      'যেমন, ডাটাবেজ, OS, প্রোগ্রামিং',
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),

          const SizedBox(height: GochanoSpacing.md),

          PrimaryButton(
            label: GochanoLanguage.text('Get Recommendation', 'সুপারিশ পান'),
            icon: Icons.auto_awesome_rounded,
            busy: _busy,
            busyLabel: GochanoLanguage.text('Planning…', 'পরিকল্পনা হচ্ছে…'),
            onPressed: _getRecommendation,
          ),

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

          if (_recommendation.isNotEmpty) ...[
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
                          GochanoLanguage.text('Today\'s Plan', 'আজকের পরিকল্পনা'),
                          style: context.type.cardHeading.copyWith(color: colors.ai),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _recommendation));
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
                  SelectableText(_recommendation, style: context.type.body),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
