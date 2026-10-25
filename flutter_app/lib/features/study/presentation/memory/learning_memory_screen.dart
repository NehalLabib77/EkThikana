import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'learning_api_service.dart';

class LearningMemoryScreen extends StatelessWidget {
  const LearningMemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Your Learning Brain', 'আপনার লার্নিং ব্রেইন'),
      ),
      body: AppPageBackground(
        gradient: AppGradients.academicHealth,
        child: FutureBuilder<Map<String, dynamic>>(
          future: LearningApiService.memory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(GochanoSpacing.lg),
                  child: AiErrorBanner(message: snapshot.error.toString()),
                ),
              );
            }
            final data = snapshot.data ?? {};
            final profile = Map<String, dynamic>.from(
              data['profile'] as Map? ?? {},
            );
            final topics = (data['topics'] as List?) ?? const [];
            final improvements = (data['improvement'] as List?) ?? const [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                GochanoSpacing.md,
                GochanoSpacing.md,
                GochanoSpacing.md,
                120,
              ),
              children: [
                _ProfileCard(profile: profile),
                if (improvements.isNotEmpty) ...[
                  const SizedBox(height: GochanoSpacing.md),
                  Text(
                    GochanoLanguage.text(
                      'Progress Improvement',
                      'অগ্রগতির উন্নতি',
                    ),
                    style: context.type.sectionHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  for (final raw in improvements.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                      child: _ProgressRow(
                        data: Map<String, dynamic>.from(raw as Map),
                      ),
                    ),
                ],
                if (topics.isNotEmpty) ...[
                  const SizedBox(height: GochanoSpacing.md),
                  Text(
                    GochanoLanguage.text(
                      'Topics to Strengthen',
                      'যে বিষয়গুলো শক্তিশালী করতে হবে',
                    ),
                    style: context.type.sectionHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  for (final raw in topics.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                      child: _TopicTile(
                        data: Map<String, dynamic>.from(raw as Map),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strong = profile['strongestSubject'] ?? 'Building evidence';
    final style = profile['preferredLearningStyle'] ?? 'Not enough data';
    final content = profile['bestContentType'] ?? 'Not enough data';
    final pattern = profile['studyTimePattern'] ?? 'Not enough data';

    return AppCard(
      accent: colors.ai,
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.ai.withValues(alpha: 0.12),
                  borderRadius: GochanoRadius.smAll,
                ),
                child: Icon(
                  Icons.psychology_alt_rounded,
                  size: 20,
                  color: colors.ai,
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Text(
                  GochanoLanguage.text(
                    'Student Learning Profile',
                    'শিক্ষার্থীর লার্নিং প্রোফাইল',
                  ),
                  style: context.type.cardHeading,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.md),
          _ProfileRow(
            icon: Icons.star_rounded,
            color: AppGradients.amberOrange,
            label: GochanoLanguage.text('Strongest Subject', 'সবচেয়ে শক্তিশালী বিষয়'),
            value: '$strong',
          ),
          const SizedBox(height: GochanoSpacing.xs),
          _ProfileRow(
            icon: Icons.lightbulb_rounded,
            color: AppGradients.skyAccent,
            label: GochanoLanguage.text('Learning Style', 'শেখার ধরন'),
            value: '$style',
          ),
          const SizedBox(height: GochanoSpacing.xs),
          _ProfileRow(
            icon: Icons.video_library_rounded,
            color: AppGradients.violetLight,
            label: GochanoLanguage.text('Best Content', 'সেরা কন্টেন্ট ফরম্যাট'),
            value: '$content',
          ),
          const SizedBox(height: GochanoSpacing.xs),
          _ProfileRow(
            icon: Icons.access_time_filled_rounded,
            color: AppGradients.emeraldAccent,
            label: GochanoLanguage.text('Study Pattern', 'পড়ার সময় প্যাটার্ন'),
            value: '$pattern',
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: GochanoSpacing.xs),
        Text(
          '$label: ',
          style: context.type.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            value,
            style: context.type.caption.copyWith(
              color: context.colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final before = (data['before'] as num?)?.toDouble() ?? 0;
    final now = (data['now'] as num?)?.toDouble() ?? 0;
    final delta = (now - before).round();
    final topic = data['topic']?.toString() ?? 'Topic';

    return AppCard(
      accent: colors.success,
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  topic,
                  style: context.type.cardHeading.copyWith(fontSize: 14),
                ),
              ),
              if (delta > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.12),
                    borderRadius: GochanoRadius.smAll,
                  ),
                  child: Text(
                    '+$delta%',
                    style: context.type.caption.copyWith(
                      color: colors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Row(
            children: [
              Text(
                'Before: ${before.toInt()}%',
                style: context.type.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Text(
                'Now: ${now.toInt()}%',
                style: context.type.caption.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (now / 100).clamp(0, 1),
              backgroundColor: colors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(colors.success),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topic = data['topic']?.toString() ?? 'Topic';
    final mistakes = data['mistakes'] ?? 0;
    final revisions = data['revisions'] ?? 0;
    final accuracy = data['accuracy'] ?? '-';

    return AppCard(
      accent: colors.error,
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.1),
              borderRadius: GochanoRadius.smAll,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: colors.error,
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic,
                  style: context.type.cardHeading.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '$mistakes mistakes • $revisions revisions',
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: GochanoRadius.smAll,
            ),
            child: Text(
              '$accuracy%',
              style: context.type.caption.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
