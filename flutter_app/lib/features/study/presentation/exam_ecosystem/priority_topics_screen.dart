/// Phase 15.2 — Priority Topics Screen.
///
/// Displays prioritized topics based on the deterministic priority formula:
/// 30% Historical Frequency + 25% Mastery Gap + 20% Mistake Pressure +
/// 15% Revision Urgency + 10% Recent Performance Gap.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../services/api_service.dart';
import 'exam_ecosystem_models.dart';

class PriorityTopicsScreen extends StatefulWidget {
  const PriorityTopicsScreen({super.key});

  static const routeName = '/priority-topics';

  @override
  State<PriorityTopicsScreen> createState() => _PriorityTopicsScreenState();
}

class _PriorityTopicsScreenState extends State<PriorityTopicsScreen> {
  bool _loading = true;
  bool _recalculating = false;
  String? _error;
  List<PriorityTopic> _topics = [];
  String _selectedFilter = 'all'; // all | critical | high | medium | low

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final filter = _selectedFilter == 'all' ? null : _selectedFilter;
      final res = await ApiService.getPriorityTopics(
        priority: filter,
        limit: 50,
      );
      final list = res['priorities'] as List<dynamic>? ?? [];
      _topics = list
          .map((e) => PriorityTopic.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load priority topics.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recalculate() async {
    setState(() => _recalculating = true);
    try {
      final res = await ApiService.recalculatePriorities();
      final count = (res['topicsScored'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recalculated priority for $count topic(s)')),
      );
      await _loadTopics();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
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
          'Exam Priority Topics',
          style: type.cardHeading.copyWith(fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: _recalculating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh_rounded, color: colors.brand),
            onPressed: _recalculating ? null : _recalculate,
            tooltip: 'Recalculate Priorities',
          ),
        ],
      ),
      body: AppPageBackground(
        height: 240,
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.error.withValues(alpha: 0.12),
                  colors.background,
                ],
              )
            : AppGradients.toolMockTests,
        child: Column(
          children: [
            _buildFilterChips(context),
            _buildFormulaExplainer(context),
            Expanded(
              child: _loading
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
                                onPressed: _loadTopics,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _topics.isEmpty
                          ? Center(
                              child: Text(
                                'No ${_selectedFilter == 'all' ? '' : '$_selectedFilter '}priority topics found.',
                                style: type.bodySecondary,
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _topics.length,
                              itemBuilder: (context, i) => _TopicCard(
                                topic: _topics[i],
                                onDrill: () => _startDrill(_topics[i].topic),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final colors = context.colors;
    const filters = ['all', 'critical', 'high', 'medium', 'low'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Text(f.toUpperCase()),
              labelStyle: TextStyle(
                color: isSelected ? colors.onBrand : colors.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              selectedColor: colors.brand,
              backgroundColor: colors.surface,
              side: BorderSide(
                color: isSelected ? colors.brand : colors.border,
              ),
              shape: RoundedRectangleBorder(borderRadius: GochanoRadius.smAll),
              onSelected: (val) {
                if (val) {
                  setState(() => _selectedFilter = f);
                  _loadTopics();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFormulaExplainer(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Scores combine past paper frequency (30%), mastery gap (25%), mistake pressure (20%), revision urgency (15%), and recent performance (10%).',
              style: type.caption,
            ),
          ),
        ],
      ),
    );
  }

  void _startDrill(String topic) async {
    try {
      await ApiService.startPractice(
        mode: 'topic_drill',
        topic: topic,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Drill ready for $topic'),
          action: SnackBarAction(
            label: 'Start Quiz',
            onPressed: () {
              Navigator.pushNamed(context, '/quiz-generate');
            },
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start drill for $topic')),
      );
    }
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onDrill});

  final PriorityTopic topic;
  final VoidCallback onDrill;

  Color _badgeColor(GochanoColors colors) {
    switch (topic.priority) {
      case 'critical':
        return colors.error;
      case 'high':
        return colors.warning;
      case 'medium':
        return AppGradients.amberOrange;
      default:
        return colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final bColor = _badgeColor(colors);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: bColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  topic.priorityLabel,
                  style: TextStyle(
                    color: bColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  topic.topic,
                  style: type.cardHeading,
                ),
              ),
              Text(
                '${topic.priorityScore.toInt()}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: bColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildComponentBreakdown(context),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: GochanoRadius.smAll),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 16),
              label: const Text('Start Practice Drill', style: TextStyle(fontSize: 13)),
              onPressed: onDrill,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentBreakdown(BuildContext context) {
    return Column(
      children: [
        if (topic.historicalFrequency != null)
          _ComponentRow(
            label: 'Past Paper Frequency',
            value: topic.historicalFrequency!,
            weight: '30%',
          ),
        if (topic.masteryGap != null)
          _ComponentRow(
            label: 'Mastery Gap',
            value: topic.masteryGap!,
            weight: '25%',
          ),
        if (topic.mistakePressure != null)
          _ComponentRow(
            label: 'Mistake Pressure',
            value: topic.mistakePressure!,
            weight: '20%',
          ),
        if (topic.revisionUrgency != null)
          _ComponentRow(
            label: 'Revision Urgency',
            value: topic.revisionUrgency!,
            weight: '15%',
          ),
        if (topic.recentPerformanceGap != null)
          _ComponentRow(
            label: 'Recent Performance Gap',
            value: topic.recentPerformanceGap!,
            weight: '10%',
          ),
      ],
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.label,
    required this.value,
    required this.weight,
  });

  final String label;
  final double value;
  final String weight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '$label ($weight)',
              style: type.caption,
            ),
          ),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (value / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: colors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '${value.toInt()}',
              textAlign: TextAlign.end,
              style: type.caption.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
