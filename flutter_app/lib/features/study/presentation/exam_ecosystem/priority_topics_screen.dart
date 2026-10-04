/// Phase 15.2 — Priority Topics Screen.
///
/// Displays prioritized topics based on the deterministic priority formula:
/// 30% Historical Frequency + 25% Mastery Gap + 20% Mistake Pressure +
/// 15% Revision Urgency + 10% Recent Performance Gap.
library;

import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Priority Topics'),
        actions: [
          IconButton(
            icon: _recalculating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _recalculating ? null : _recalculate,
            tooltip: 'Recalculate Priorities',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(theme),
          _buildFormulaExplainer(theme),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            FilledButton(
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
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
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
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
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

  Widget _buildFormulaExplainer(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Scores combine past paper frequency (30%), mastery gap (25%), mistake pressure (20%), revision urgency (15%), and recent performance (10%).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
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

  Color _badgeColor() {
    switch (topic.priority) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      case 'medium':
        return Colors.amber.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
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
                    color: _badgeColor(),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    topic.priorityLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    topic.topic,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${topic.priorityScore.toInt()}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _badgeColor(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildComponentBreakdown(theme),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.bolt, size: 16),
                label: const Text('Start Practice Drill'),
                onPressed: onDrill,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComponentBreakdown(ThemeData theme) {
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '$label ($weight)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '${value.toInt()}',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
