// Phase 8 — Achievements.
//
// Sixteen milestones across the four kinds the spec asks for: MCQ volume,
// consistency, improvement and contribution. Progress is recomputed on every
// read by the backend, so this screen never guesses at a bar: it shows the
// numbers it is given and the stamp the service has already written.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

/// The read hook, injected in tests so the screen never opens a socket.
typedef AchievementsFn = Future<Map<String, dynamic>> Function();

class ZikuAchievementsScreen extends StatefulWidget {
  const ZikuAchievementsScreen({super.key, this.achievementsFn});

  final AchievementsFn? achievementsFn;

  @override
  State<ZikuAchievementsScreen> createState() => _ZikuAchievementsScreenState();
}

class _ZikuAchievementsScreenState extends State<ZikuAchievementsScreen> {
  Map<String, dynamic>? _payload;
  String _error = '';
  bool _loading = true;

  AchievementsFn get _read =>
      widget.achievementsFn ?? ApiService.zikuAchievements;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final body = await _read();
      if (!mounted) return;
      setState(() {
        _payload = body;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  String _categoryLabel(String key) => switch (key) {
        'mcq' => GochanoLanguage.text('MCQ milestones', 'এমসিকু মাইলফলক'),
        'consistency' => GochanoLanguage.text('Consistency', 'ধারাবাহিকতা'),
        'improvement' => GochanoLanguage.text('Improvement', 'উন্নতি'),
        'contribution' => GochanoLanguage.text('Contribution', 'অবদান'),
        _ => key,
      };

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Achievements', 'অর্জন'),
        subtitle: GochanoLanguage.text(
          'Sixteen milestones across four kinds',
          'চার ধরনে ষোলোটি মাইলফলক',
        ),
        actions: [
          IconActionButton(
            icon: Icons.refresh_rounded,
            label: GochanoLanguage.text('Refresh', 'রিফ্রেশ'),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_payload == null) {
      if (_loading) {
        return AiLoadingState(
          message: GochanoLanguage.text(
            'Counting your milestones…',
            'আপনার মাইলফলক গোনা হচ্ছে…',
          ),
        );
      }
      return Center(
        child: Padding(
          padding: GochanoSpacing.scrollBody,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiErrorBanner(message: _error),
              const SizedBox(height: GochanoSpacing.sm),
              SecondaryButton(
                label: GochanoLanguage.text('Try again', 'আবার চেষ্টা করুন'),
                icon: Icons.refresh_rounded,
                onPressed: _refresh,
              ),
            ],
          ),
        ),
      );
    }

    final payload = _payload!;
    if (payload['hasData'] != true) {
      return AiEmptyState(
        icon: Icons.emoji_events_outlined,
        accent: context.colors.brand,
        title: GochanoLanguage.text(
          'Your first milestone is one quiz away',
          'প্রথম মাইলফলক একটি কুইজ দূরে',
        ),
        message: GochanoLanguage.text(
          'Take a quiz, finish a focus block or help once in the group and '
          'this board starts filling itself in.',
          'একটি কুইজ দিন, একটি ফোকাস ব্লক শেষ করুন বা গ্রুপে একবার সাহায্য করুন — '
          'এই বোর্ড ভরতে শুরু করবে।',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _countsCard(context, payload),
          const SizedBox(height: GochanoSpacing.sm),
          _nextCard(context, payload),
          const SizedBox(height: GochanoSpacing.md),
          ..._categorySections(context, payload),
          const SizedBox(height: GochanoSpacing.lg),
        ],
      ),
    );
  }

  Widget _countsCard(BuildContext context, Map<String, dynamic> payload) {
    final colors = context.colors;
    final counts = _asMap(payload['counts']) ?? const <String, dynamic>{};
    final earned = _asInt(counts['earned']);
    final total = _asInt(counts['total']);
    final ratio = total == 0 ? 0.0 : earned / total;

    return AppCard(
      accent: colors.brand,
      semanticLabel: 'Achievement scoreboard',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text(
              '$earned of $total earned',
              '$earned / $total অর্জিত',
            ),
            style: context.type.cardHeading,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          ClipRRect(
            borderRadius: GochanoRadius.smAll,
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              color: colors.brand,
              semanticsLabel: GochanoLanguage.text(
                'Achievement progress: $earned of $total',
                'অর্জনের অগ্রগতি: $earned / $total',
              ),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              for (final category in _asList(payload['categories']))
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '${_categoryLabel('${category['key']}')} '
                    '${_asInt(category['earned'])}/${_asInt(category['total'])}',
                    '${_categoryLabel('${category['key']}')} '
                    '${_asInt(category['earned'])}/${_asInt(category['total'])}',
                  ),
                  tone: _asInt(category['earned']) > 0
                      ? GochanoBadgeTone.success
                      : GochanoBadgeTone.neutral,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nextCard(BuildContext context, Map<String, dynamic> payload) {
    final colors = context.colors;
    final next = _asMap(payload['next']);
    if (next == null) return const SizedBox.shrink();

    final progress = _progress(next['progress']);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: colors.brand),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Next up', 'পরবর্তী'),
                  style: context.type.label,
                ),
              ),
              GochanoBadge(
                label: GochanoLanguage.text(
                  '${(progress * 100).round()}%',
                  '${(progress * 100).round()}%',
                ),
                tone: GochanoBadgeTone.brand,
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text('${next['title'] ?? ''}', style: context.type.cardHeading),
          const SizedBox(height: GochanoSpacing.xxs),
          Text('${next['description'] ?? ''}', style: context.type.bodySecondary),
          const SizedBox(height: GochanoSpacing.sm),
          ClipRRect(
            borderRadius: GochanoRadius.smAll,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              color: colors.brand,
              semanticsLabel: '${next['title'] ?? ''} progress',
            ),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              '${_asInt(next['current'])} of ${_asInt(next['target'])}',
              '${_asInt(next['current'])} / ${_asInt(next['target'])}',
            ),
            style: context.type.caption,
          ),
        ],
      ),
    );
  }

  List<Widget> _categorySections(
    BuildContext context,
    Map<String, dynamic> payload,
  ) {
    final colors = context.colors;
    final achievements = _asList(payload['achievements']);
    final sections = <Widget>[];

    for (final category in _asList(payload['categories'])) {
      final key = '${category['key']}';
      final rows = achievements
          .where((row) => '${row['category']}' == key)
          .toList();
      if (rows.isEmpty) continue;

      sections.add(
        SectionHeader(
          title: _categoryLabel(key),
          subtitle: GochanoLanguage.text(
            '${_asInt(category['earned'])} of ${_asInt(category['total'])} in this group',
            '${_asInt(category['earned'])} / ${_asInt(category['total'])} এই দলে',
          ),
        ),
      );
      sections.add(
        CardGroup(
          children: [for (final row in rows) _achievementRow(context, row)],
        ),
      );
      sections.add(const SizedBox(height: GochanoSpacing.md));
    }

    if (sections.isEmpty) {
      sections.add(
        AiEmptyState(
          icon: Icons.emoji_events_outlined,
          accent: colors.brand,
          title: GochanoLanguage.text('Nothing here yet', 'এখনো কিছু নেই'),
          message: GochanoLanguage.text(
            'The scoreboard fills as you study.',
            'পড়াশোনার সাথে সাথে এই বোর্ড ভরবে।',
          ),
        ),
      );
    }

    return sections;
  }

  Widget _achievementRow(BuildContext context, Map<String, dynamic> row) {
    final colors = context.colors;
    final earned = row['earned'] == true;
    final progress = _progress(row['progress']);
    final tone = earned ? colors.success : colors.brand;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                earned ? Icons.emoji_events_rounded : Icons.emoji_events_outlined,
                size: 18,
                color: tone,
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  '${row['title'] ?? ''}',
                  style: context.type.cardHeading,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (earned)
                GochanoBadge(
                  label: GochanoLanguage.text('Earned', 'অর্জিত'),
                  tone: GochanoBadgeTone.success,
                  icon: Icons.check_rounded,
                )
              else
                GochanoBadge(
                  label: GochanoLanguage.text('Locked', 'বন্ধ'),
                  tone: GochanoBadgeTone.neutral,
                  icon: Icons.lock_outline_rounded,
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${row['description'] ?? ''}',
            style: context.type.bodySecondary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          ClipRRect(
            borderRadius: GochanoRadius.smAll,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              color: tone,
              semanticsLabel: '${row['title'] ?? ''} progress',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            GochanoLanguage.text(
              '${_asInt(row['current'])} of ${_asInt(row['target'])}'
              '${earned ? '' : ' · ${(progress * 100).round()}%'}',
              '${_asInt(row['current'])} / ${_asInt(row['target'])}'
              '${earned ? '' : ' · ${(progress * 100).round()}%'}',
            ),
            style: context.type.caption,
          ),
        ],
      ),
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  static double _progress(dynamic value) {
    if (value is! num) return 0;
    if (value <= 0) return 0;
    if (value >= 1) return 1;
    return value.toDouble();
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return [
      for (final entry in value)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }
}
