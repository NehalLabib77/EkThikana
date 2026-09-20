// Phase 3C — Learning Insights Screen
//
// Displays weak topics, strong topics, overall learning summary,
// and AI-powered daily study recommendations.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class LearningInsightsScreen extends StatefulWidget {
  const LearningInsightsScreen({super.key});

  @override
  State<LearningInsightsScreen> createState() => _LearningInsightsScreenState();
}

class _LearningInsightsScreenState extends State<LearningInsightsScreen> {
  bool _loading = true;
  String _error = '';

  int _totalQuizzes = 0;
  int _averageScore = 0;
  int _totalTopics = 0;
  List<Map<String, dynamic>> _weakTopics = [];
  List<Map<String, dynamic>> _strongTopics = [];

  // Phase 3C-3: AI Recommendations
  List<Map<String, dynamic>> _recommendations = [];
  bool _loadingRecommendations = false;
  String _recommendationsError = '';

  // Phase 4-1: Feedback tracking (recommendation index -> feedback state)
  final Map<int, String> _feedbackState = {}; // index -> 'helpful' | 'not_helpful' | 'submitting'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final summary = await ApiService.getLearningSummary();
      if (mounted) {
        setState(() {
          _loading = false;
          _totalQuizzes = summary['total_quizzes'] as int? ?? 0;
          _averageScore = summary['average_score'] as int? ?? 0;
          _totalTopics = summary['total_topics'] as int? ?? 0;
          _weakTopics = (summary['weak_topics'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((t) => t.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
          _strongTopics = (summary['strong_topics'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((t) => t.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        });
      }
      // Load recommendations after summary
      _loadRecommendations();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _loadingRecommendations = true;
      _recommendationsError = '';
    });

    try {
      final result = await ApiService.getStudyRecommendations();
      if (mounted) {
        setState(() {
          _loadingRecommendations = false;
          _recommendations = (result['recommendations'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((r) => r.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRecommendations = false;
          _recommendationsError = friendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _submitFeedback(int index, String feedback) async {
    if (_feedbackState[index] != null) return; // Already submitted

    setState(() => _feedbackState[index] = 'submitting');

    try {
      final rec = index < _recommendations.length ? _recommendations[index] : {};
      final title = rec['title']?.toString() ?? '';

      await ApiService.submitAiFeedback(
        feature: 'study_recommendation',
        feedback: feedback,
        recommendationId: title,
      );

      if (mounted) {
        setState(() => _feedbackState[index] = feedback);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _feedbackState.remove(index));
      }
    }
  }

  Color _scoreColor(BuildContext context, int score) {
    final colors = context.colors;
    if (score >= 70) return colors.success;
    if (score >= 50) return colors.ai;
    return colors.error;
  }

  Color _priorityColor(BuildContext context, String priority) {
    final colors = context.colors;
    switch (priority) {
      case 'high':
        return colors.error;
      case 'medium':
        return colors.ai;
      default:
        return colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Learning Insights', 'লার্নিং ইনসাইটস'),
      ),
      body: _loading
          ? const AiLoadingState()
          : _error.isNotEmpty
              ? ErrorState(
                  message: _error,
                  onRetry: _loadData,
                )
              : _totalQuizzes == 0
                  ? AiEmptyState(
                      icon: Icons.insights_rounded,
                      title: GochanoLanguage.text(
                        'No quiz data yet',
                        'এখনো কুইজের ডেটা নেই',
                      ),
                      message: GochanoLanguage.text(
                        'Complete a few quizzes to see your learning insights, weak topic analysis, and AI recommendations.',
                        'আপনার লার্নিং ইনসাইটস, দুর্বল বিষয় বিশ্লেষণ এবং এআই সুপারিশ দেখতে কয়েকটি কুইজ সম্পন্ন করুন।',
                      ),
                    )
                  : _buildContent(colors),
    );
  }

  Widget _buildContent(GochanoColors colors) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        children: [
          // Overall stats
          _buildOverallStats(colors),
          const SizedBox(height: GochanoSpacing.md),

          // AI Study Recommendations
          _buildRecommendationsSection(colors),

          // Weak topics
          if (_weakTopics.isNotEmpty) ...[
            _buildSectionHeader(
              icon: Icons.warning_amber_rounded,
              title: GochanoLanguage.text('Weak Topics', 'দুর্বল বিষয়'),
              color: colors.error,
              count: _weakTopics.length,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            for (final topic in _weakTopics)
              _buildTopicCard(topic, colors, isWeak: true),
            const SizedBox(height: GochanoSpacing.md),
          ],

          // Strong topics
          if (_strongTopics.isNotEmpty) ...[
            _buildSectionHeader(
              icon: Icons.star_rounded,
              title: GochanoLanguage.text('Strong Topics', 'শক্তিশালী বিষয়'),
              color: colors.success,
              count: _strongTopics.length,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            for (final topic in _strongTopics)
              _buildTopicCard(topic, colors, isWeak: false),
            const SizedBox(height: GochanoSpacing.md),
          ],

          // No weak topics message
          if (_weakTopics.isEmpty && _totalQuizzes > 0) ...[
            _buildNoWeakTopicsCard(colors),
            const SizedBox(height: GochanoSpacing.md),
          ],

          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildOverallStats(GochanoColors colors) {
    return AppCard(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text('Overall Performance', 'সামগ্রিক পারফরম্যান্স'),
            style: context.type.cardHeading,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Row(
            children: [
              _StatBox(
                value: '$_totalQuizzes',
                label: GochanoLanguage.text('Quizzes', 'কুইজ'),
                color: colors.ai,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              _StatBox(
                value: '$_averageScore%',
                label: GochanoLanguage.text('Avg Score', 'গড় স্কোর'),
                color: _scoreColor(context, _averageScore),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              _StatBox(
                value: '$_totalTopics',
                label: GochanoLanguage.text('Topics', 'বিষয়'),
                color: colors.textPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Phase 3C-3: AI Recommendations Section
  Widget _buildRecommendationsSection(GochanoColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.auto_awesome_rounded,
            title: GochanoLanguage.text('AI Study Recommendations', 'এআই অধ্যয়ন সুপারিশ'),
            color: colors.ai,
            count: _recommendations.length,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          if (_loadingRecommendations)
            AppCard(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: const AiLoadingState(
                message: 'Loading recommendations…',
              ),
            )
          else if (_recommendationsError.isNotEmpty)
            AppCard(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: colors.textTertiary),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        'Could not load recommendations. Pull to refresh.',
                        'সুপারিশ লোড করা যায়নি। রিফ্রেশ করুন।',
                      ),
                      style: context.type.caption.copyWith(color: colors.textTertiary),
                    ),
                  ),
                ],
              ),
            )
          else if (_recommendations.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 20, color: colors.ai),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        'Take a quiz to get personalized study recommendations.',
                        'ব্যক্তিগতকৃত অধ্যয়ন সুপারিশ পেতে একটি কুইজ দিন।',
                      ),
                      style: context.type.bodySecondary.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < _recommendations.length; i++)
              _buildRecommendationCard(i, _recommendations[i], colors),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(int index, Map<String, dynamic> rec, GochanoColors colors) {
    final title = rec['title']?.toString() ?? '';
    final reason = rec['reason']?.toString() ?? '';
    final priority = rec['priority']?.toString() ?? 'medium';
    final priColor = _priorityColor(context, priority);

    // Phase 4-1: Feedback state
    final feedbackState = _feedbackState[index];
    final hasFeedback = feedbackState != null && feedbackState != 'submitting';
    final isSubmitting = feedbackState == 'submitting';

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Priority indicator
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: priColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: context.type.body.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: priColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              priority.toUpperCase(),
                              style: context.type.caption.copyWith(
                                color: priColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          reason,
                          style: context.type.bodySecondary.copyWith(
                            color: colors.textSecondary,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Phase 4-1: Feedback buttons
            const SizedBox(height: GochanoSpacing.xs),
            if (hasFeedback)
              Row(
                children: [
                  Icon(
                    feedbackState == 'helpful'
                        ? Icons.thumb_up_rounded
                        : Icons.thumb_down_rounded,
                    size: 14,
                    color: feedbackState == 'helpful' ? colors.success : colors.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    feedbackState == 'helpful'
                        ? GochanoLanguage.text('Helpful', 'সাহায্যকর')
                        : GochanoLanguage.text('Not helpful', 'সাহায্যকর নয়'),
                    style: context.type.caption.copyWith(
                      color: feedbackState == 'helpful' ? colors.success : colors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Text(
                    GochanoLanguage.text('Was this helpful?', 'এটি কি সাহায্যকর ছিল?'),
                    style: context.type.caption.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  _FeedbackButton(
                    icon: Icons.thumb_up_outlined,
                    label: GochanoLanguage.text('Helpful', 'সাহায্যকর'),
                    color: colors.success,
                    enabled: !isSubmitting,
                    onTap: () => _submitFeedback(index, 'helpful'),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  _FeedbackButton(
                    icon: Icons.thumb_down_outlined,
                    label: GochanoLanguage.text('Not helpful', 'সাহায্যকর নয়'),
                    color: colors.error,
                    enabled: !isSubmitting,
                    onTap: () => _submitFeedback(index, 'not_helpful'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
    required int count,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: GochanoSpacing.xs),
        Expanded(
          child: Text(title, style: context.type.sectionHeading),
        ),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: context.type.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopicCard(Map<String, dynamic> topic, GochanoColors colors, {required bool isWeak}) {
    final topicName = topic['topic']?.toString() ?? '';
    final avgScore = topic['average_score'] as int? ?? 0;
    final attempts = topic['attempts'] as int? ?? 0;
    final recommendation = topic['recommendation']?.toString() ?? '';

    final scoreColor = _scoreColor(context, avgScore);

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scoreColor.withValues(alpha: 0.12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$avgScore%',
                    style: context.type.body.copyWith(
                      color: scoreColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topicName,
                        style: context.type.body.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$attempts ${GochanoLanguage.text('attempts', 'চেষ্টা')}',
                        style: context.type.caption.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (recommendation.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Container(
                padding: const EdgeInsets.all(GochanoSpacing.xs),
                decoration: BoxDecoration(
                  color: isWeak
                      ? colors.error.withValues(alpha: 0.06)
                      : colors.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isWeak ? Icons.lightbulb_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: isWeak ? colors.error : colors.success,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        recommendation,
                        style: context.type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoWeakTopicsCard(GochanoColors colors) {
    return AppCard(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.success.withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.check_circle_rounded, size: 24, color: colors.success),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GochanoLanguage.text(
                    'Great job!',
                    'সুন্দর কাজ!',
                  ),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  GochanoLanguage.text(
                    'No weak topics detected. Keep up the good work!',
                    'কোনো দুর্বল বিষয় পাওয়া যায়নি। ভালো কাজ চালিয়ে যান!',
                  ),
                  style: context.type.bodySecondary.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: GochanoRadius.mdAll,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: context.type.cardHeading.copyWith(color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: context.type.caption.copyWith(
                color: context.colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Phase 4-1: Feedback button widget
class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.08)
              : context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.3)
                : context.colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: enabled ? color : context.colors.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.type.caption.copyWith(
                color: enabled ? color : context.colors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
