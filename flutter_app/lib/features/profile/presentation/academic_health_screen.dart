// Phase 2 — My Academic Health (score, breakdown, weak areas, advice).
//
// One screen that answers three questions in order:
//   * how am I doing?      → the 0-100 score, grade and sentence
//   * what is it made of?  → the four weighted metrics and today's numbers
//   * what do I do next?   → weak topics plus the merged health + Ziku advice
//
// The score is computed on the backend from quiz mastery, recorded mistakes,
// deep-work sessions, the study plan and AI usage — nothing here re-derives it.
// Every reader is injectable so tests never open a socket.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/ai_widgets.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../study/presentation/ai/ai_assistant_screen.dart';

/// The question the screen hands to Ziku on "Open Ziku".
///
/// The weakest topic beats the generic advice: a student who has just read
/// "Networking at 44%" should not have to retype it.
String academicHealthZikuQuestion({
  String? weakTopic,
  String? recommendation,
}) {
  final topic = (weakTopic ?? '').trim();
  if (topic.isNotEmpty) {
    return GochanoLanguage.text(
      'How should I revise $topic before my next quiz?',
      '$topic কীভাবে রিভাইজ করব?',
    );
  }
  final title = (recommendation ?? '').trim();
  if (title.isNotEmpty) return title;
  return GochanoLanguage.text('What should I study today?', 'আজ কী পড়ব?');
}

class AcademicHealthScreen extends StatefulWidget {
  const AcademicHealthScreen({
    super.key,
    this.healthFn,
    this.recommendationsFn,
    this.historyFn,
  });

  final Future<Map<String, dynamic>> Function()? healthFn;
  final Future<Map<String, dynamic>> Function()? recommendationsFn;
  final Future<Map<String, dynamic>> Function()? historyFn;

  @override
  State<AcademicHealthScreen> createState() => _AcademicHealthScreenState();
}

class _AcademicHealthScreenState extends State<AcademicHealthScreen> {
  Map<String, dynamic>? _health;
  List<Map<String, dynamic>> _recommendations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _adviceLoading = false;
  String _error = '';

  Future<Map<String, dynamic>> Function() get _read =>
      widget.healthFn ?? ApiService.getAcademicHealth;

  Future<Map<String, dynamic>> Function() get _readAdvice =>
      widget.recommendationsFn ?? ApiService.getAcademicHealthRecommendations;

  Future<Map<String, dynamic>> Function() get _readHistory =>
      widget.historyFn ?? ApiService.getAcademicHealthHistory;

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
        _health = body;
        _recommendations = _asList(body['recommendations']);
        _history = <Map<String, dynamic>>[];
        _loading = false;
      });
      unawaited(_loadHistory());
      unawaited(_loadAdvice());
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  /// History and the AI-authored list are decorations: if either fails the
  /// deterministic health payload still renders.
  Future<void> _loadHistory() async {
    try {
      final body = await _readHistory();
      if (!mounted) return;
      setState(() => _history = _asList(body['history']));
    } catch (_) {
      // A missing chart is not worth an error banner.
    }
  }

  Future<void> _loadAdvice() async {
    if (_adviceLoading) return;
    setState(() => _adviceLoading = true);
    try {
      final body = await _readAdvice();
      if (!mounted) return;
      final merged = _asList(body['recommendations']);
      setState(() {
        if (merged.isNotEmpty) _recommendations = merged;
        _adviceLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _adviceLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          'My Academic Health',
          'আমার একাডেমিক হেলথ',
        ),
        subtitle: GochanoLanguage.text(
          'How your studies are doing',
          'পড়াশোনার অবস্থা',
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_health == null) {
      if (_loading) {
        return AiLoadingState(
          message: GochanoLanguage.text(
            'Measuring your academic health…',
            'একাডেমিক হেলথ মাপা হচ্ছে…',
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

    final health = _health!;
    if (health['hasData'] != true) {
      return ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          if (_error.isNotEmpty) ...[
            AiErrorBanner(message: _error),
            const SizedBox(height: GochanoSpacing.sm),
          ],
          AiEmptyState(
            icon: Icons.monitor_heart_rounded,
            title: GochanoLanguage.text(
              'Not enough data yet',
              'এখনো যথেষ্ট তথ্য নেই',
            ),
            message: GochanoLanguage.text(
              'Take a quiz or start a deep-work session — the score needs '
              'one signal before it means anything.',
              'একটি কুইজ দিন বা একটি গভীর পড়ার সেশন শুরু করুন।',
            ),
          ),
        ],
      );
    }

    final metrics = _asList(health['metrics']);
    final weakAreas = _asList(health['weakAreas']);
    final signals = _asMapOrNull(health['signals']) ?? <String, dynamic>{};
    final trend = _asMapOrNull(health['trend']);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          if (_error.isNotEmpty) ...[
            AiErrorBanner(message: _error),
            const SizedBox(height: GochanoSpacing.sm),
          ],
          _scoreCard(context, health, trend),
          const SizedBox(height: GochanoSpacing.md),
          SectionHeader(
            title: GochanoLanguage.text(
              'What the score is made of',
              'স্কোর যেভাবে গোনা হয়েছে',
            ),
            subtitle: GochanoLanguage.text(
              'Four weighted parts — only the ones with data count',
              'চারটি অংশ — যেগুলোর তথ্য আছে সেগুলোই গোনা হয়েছে',
            ),
          ),
          CardGroup(
            children: [for (final item in metrics) _metricRow(context, item)],
          ),
          const SizedBox(height: GochanoSpacing.md),
          SectionHeader(
            title: GochanoLanguage.text('Today', 'আজ'),
          ),
          _todayStats(context, signals),
          if (weakAreas.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            SectionHeader(
              title: GochanoLanguage.text(
                'Topics to strengthen',
                'শক্তিশালী করার টপিক',
              ),
              subtitle: GochanoLanguage.text(
                'From quiz mastery and recorded mistakes',
                'কুইজ দক্ষতা ও সংরক্ষিত ভুল থেকে',
              ),
            ),
            CardGroup(
              children: [
                for (final item in weakAreas) _weakAreaRow(context, item),
              ],
            ),
          ],
          if (_recommendations.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            SectionHeader(
              title: GochanoLanguage.text('Recommended next', 'পরবর্তী পদক্ষেপ'),
              subtitle: GochanoLanguage.text(
                'Health rules first, then Ziku',
                'আগে নিয়ম, তারপর জিকু',
              ),
              action: _adviceLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            CardGroup(
              children: [
                for (final item in _recommendations)
                  _recommendationRow(context, item),
              ],
            ),
          ],
          const SizedBox(height: GochanoSpacing.md),
          _askZikuCard(context),
          if (_history.length >= 2) ...[
            const SizedBox(height: GochanoSpacing.md),
            SectionHeader(
              title: GochanoLanguage.text('Recent scores', 'সাম্প্রতিক স্কোর'),
              subtitle: GochanoLanguage.text(
                'One bar per day, left to right',
                'প্রতিদিনের স্কোর',
              ),
            ),
            _historyChart(context, _history),
          ],
          const SizedBox(height: GochanoSpacing.lg),
        ],
      ),
    );
  }

  Widget _scoreCard(
    BuildContext context,
    Map<String, dynamic> health,
    Map<String, dynamic>? trend,
  ) {
    final score = _asInt(health['score']);
    final rawCoverage = health['coverage'];
    final coverageCount = rawCoverage is List ? rawCoverage.length : 0;
    final tone = _toneFor(context, score);

    final String? deltaLabel;
    if (trend == null || trend['direction'] == 'new') {
      deltaLabel = null;
    } else {
      final delta = _asInt(trend['delta']);
      if (delta > 0) {
        deltaLabel = GochanoLanguage.text('+$delta since yesterday', 'গতকালের চেয়ে +$delta');
      } else if (delta < 0) {
        deltaLabel = GochanoLanguage.text('$delta since yesterday', 'গতকালের চেয়ে $delta');
      } else {
        deltaLabel = GochanoLanguage.text('Same as yesterday', 'গতকালের মতোই');
      }
    }

    return AppCard(
      accent: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$score',
                style: context.type.display.copyWith(color: tone),
                semanticsLabel:
                    GochanoLanguage.text('Score $score out of 100', 'স্কোর $score / ১০০'),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Text('/ 100', style: context.type.bodySecondary),
              const Spacer(),
              if (deltaLabel != null)
                GochanoBadge(
                  label: deltaLabel,
                  tone: _asInt(trend?['delta']) >= 0
                      ? GochanoBadgeTone.success
                      : GochanoBadgeTone.warning,
                  icon: _asInt(trend?['delta']) >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Text('${health['headline'] ?? ''}', style: context.type.body),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              '$coverageCount of 4 signals measured',
              '$coverageCountটি তথ্য পাওয়া গেছে',
            ),
            style: context.type.caption,
          ),
        ],
      ),
    );
  }

  Widget _metricRow(BuildContext context, Map<String, dynamic> item) {
    final colors = context.colors;
    final available = item['available'] == true;
    final score = item['score'] is num ? (item['score'] as num).toDouble() : null;
    final weight = item['weight'] is num ? (item['weight'] as num).toDouble() : 0.0;

    final Widget trailing;
    if (!available || score == null) {
      trailing = Text(
        GochanoLanguage.text('No data', 'তথ্য নেই'),
        style: context.type.caption.copyWith(color: colors.textTertiary),
      );
    } else {
      trailing = Text(
        score.round().toString(),
        style: context.type.statisticSmall.copyWith(
          color: _toneFor(context, score.round()),
        ),
      );
    }

    return GochanoListRow(
      illustration: GochanoArt.featurePlanner,
      accent: available ? _toneFor(context, score?.round() ?? 0) : colors.textTertiary,
      title: '${item['label'] ?? item['key'] ?? ''}',
      subtitle: '${item['detail'] ?? ''}',
      metadata: [
        GochanoLanguage.text(
          'Weight ${(weight * 100).round()}%',
          'ওজন ${(weight * 100).round()}%',
        ),
      ],
      trailing: trailing,
    );
  }

  Widget _todayStats(BuildContext context, Map<String, dynamic> signals) {
    final colors = context.colors;
    final study = _asMapOrNull(signals['study']) ?? <String, dynamic>{};
    final mistakes = _asMapOrNull(signals['mistakes']) ?? <String, dynamic>{};
    final averageFocus = study['averageFocusScore'];

    return Row(
      children: [
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Deep work', 'গভীর পড়া'),
            value: '${_asInt(study['todayMinutes'])}m',
            caption: GochanoLanguage.text(
              '${_asInt(study['todaySessions'])} sessions',
              '${_asInt(study['todaySessions'])} সেশন',
            ),
            icon: Icon(Icons.timer_outlined, size: 16, color: colors.study),
            accent: colors.study,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Focus score', 'ফোকাস স্কোর'),
            value: averageFocus is num ? '${averageFocus.round()}' : '—',
            caption: GochanoLanguage.text(
              '${_asInt(study['weekMinutes'])}m this week',
              'সপ্তাহে ${_asInt(study['weekMinutes'])}মিনিট',
            ),
            icon: Icon(Icons.my_location_rounded, size: 16, color: colors.ai),
            accent: colors.ai,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Mistakes due', 'রিভিশন বাকি'),
            value: '${_asInt(mistakes['due'])}',
            caption: GochanoLanguage.text(
              '${_asInt(mistakes['repeated'])} repeated',
              '${_asInt(mistakes['repeated'])} পুনরাবৃত্ত',
            ),
            icon: Icon(Icons.error_outline_rounded, size: 16, color: colors.error),
            accent: colors.error,
          ),
        ),
      ],
    );
  }

  Widget _weakAreaRow(BuildContext context, Map<String, dynamic> item) {
    final priority = '${item['priority'] ?? 'medium'}';
    final quizAverage = item['quizAverage'];
    final metadata = <String>[
      if (quizAverage is num)
        GochanoLanguage.text('Quiz average ${quizAverage.round()}%', 'গড় ${quizAverage.round()}%'),
      if (_asInt(item['mistakes']) > 0)
        GochanoLanguage.text('${_asInt(item['mistakes'])} mistakes', '${_asInt(item['mistakes'])} ভুল'),
      if (_asInt(item['due']) > 0)
        GochanoLanguage.text('${_asInt(item['due'])} due', '${_asInt(item['due'])} বাকি'),
    ];

    return GochanoListRow(
      illustration: GochanoArt.subjectGeneric,
      accent: priority == 'high' ? context.colors.error : context.colors.warning,
      title: '${item['topic'] ?? ''}',
      subtitle: '${item['action'] ?? ''}',
      metadata: metadata,
      badge: priority == 'high'
          ? GochanoBadge(
              label: GochanoLanguage.text('High priority', 'জরুরি'),
              tone: GochanoBadgeTone.error,
              icon: Icons.priority_high_rounded,
            )
          : null,
    );
  }

  Widget _recommendationRow(BuildContext context, Map<String, dynamic> item) {
    final source = '${item['source'] ?? 'health'}';
    final priority = '${item['priority'] ?? 'medium'}';
    final colors = context.colors;

    return GochanoListRow(
      illustration: source == 'ai' ? GochanoArt.featureAi : GochanoArt.featureTasks,
      accent: source == 'ai' ? colors.ai : colors.brand,
      title: '${item['title'] ?? ''}',
      subtitle: '${item['reason'] ?? ''}',
      badge: GochanoBadge(
        label: source == 'ai'
            ? GochanoLanguage.text('Ziku', 'জিকু')
            : GochanoLanguage.text('Health', 'হেলথ'),
        tone: source == 'ai' ? GochanoBadgeTone.brand : GochanoBadgeTone.neutral,
        icon: source == 'ai' ? Icons.auto_awesome_rounded : Icons.health_and_safety_rounded,
      ),
      trailing: priority == 'high'
          ? Icon(Icons.bolt_rounded, size: 20, color: colors.warning)
          : null,
    );
  }

  /// The hand-off to Ziku: one tap that opens the assistant with a question
  /// built from the weakest topic, so the student never has to retype what
  /// this screen just told them.
  Widget _askZikuCard(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      accent: colors.ai,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text('Ask Ziku', 'জিকুকে জিজ্ঞেস করুন'),
            style: context.type.cardHeading,
          ),
          const SizedBox(height: 2),
          Text(
            GochanoLanguage.text(
              'Ziku reads this same score, so the advice starts where the '
              'numbers left off.',
              'জিকু একই স্কোর দেখে — পরামর্শ এখান থেকেই শুরু হবে।',
            ),
            style: context.type.caption,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          SecondaryButton(
            label: GochanoLanguage.text('Open Ziku', 'জিকু খুলুন'),
            icon: Icons.auto_awesome_rounded,
            expand: false,
            onPressed: () => Navigator.of(context).push(
              GochanoRoute.to(
                builder: (_) =>
                    AiAssistantScreen(prefilledQuestion: _zikuQuestion()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _zikuQuestion() => academicHealthZikuQuestion(
    weakTopic: _asList(_health?['weakAreas']).isEmpty
        ? null
        : '${_asList(_health?['weakAreas']).first['topic'] ?? ''}',
    recommendation: _recommendations.isEmpty
        ? null
        : '${_recommendations.first['title'] ?? ''}',
  );

  Widget _historyChart(BuildContext context, List<Map<String, dynamic>> history) {
    final entries = [...history]..sort((a, b) {
        final left = '${a['dayKey'] ?? ''}';
        final right = '${b['dayKey'] ?? ''}';
        return left.compareTo(right);
      });
    final first = _asInt(entries.first['score']);
    final last = _asInt(entries.last['score']);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  GochanoLanguage.text(
                    '$first → $last over ${entries.length} days',
                    '$first → $last, ${entries.length} দিন',
                  ),
                  style: context.type.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final entry in entries)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.xs,
                      ),
                      child: Semantics(
                        label: '${entry['dayKey'] ?? ''}: ${_asInt(entry['score'])}',
                        child: Container(
                          height: 8 + (_asInt(entry['score']) / 100) * 64,
                          decoration: BoxDecoration(
                            color: _toneFor(context, _asInt(entry['score'])),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _toneFor(BuildContext context, int score) {
    final colors = context.colors;
    if (score >= 85) return colors.success;
    if (score >= 70) return colors.info;
    if (score >= 55) return colors.warning;
    return colors.error;
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  static Map<String, dynamic>? _asMapOrNull(dynamic value) {
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
