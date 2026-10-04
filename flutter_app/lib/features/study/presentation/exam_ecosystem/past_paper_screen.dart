/// Phase 15.1 — Past Papers Intelligence Screen.
///
/// Allows students to view analyzed past papers, historical insights,
/// and analyze materials from Workspace as past papers.
/// Strictly historical language: "Frequently Tested", "High Historical Coverage".
library;

import 'package:flutter/material.dart';

import '../../../../services/api_service.dart';
import 'exam_ecosystem_models.dart';

class PastPaperScreen extends StatefulWidget {
  const PastPaperScreen({super.key});

  static const routeName = '/past-papers';

  @override
  State<PastPaperScreen> createState() => _PastPaperScreenState();
}

class _PastPaperScreenState extends State<PastPaperScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _papers = [];
  PastPaperInsight? _insights;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final papersRes = await ApiService.listPastPapers();
      final pList = papersRes['papers'] as List<dynamic>? ?? [];
      _papers = pList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final insightsRes = await ApiService.historicalInsights();
      _insights = PastPaperInsight.fromJson(insightsRes);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load past papers data.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAnalyzeDialog() {
    final matCtrl = TextEditingController();
    final examCtrl = TextEditingController(text: 'Final Exam');
    final boardCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: '${DateTime.now().year - 1}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Analyze Workspace Past Paper'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: matCtrl,
                decoration: const InputDecoration(
                  labelText: 'Material ID',
                  hintText: 'Enter material ID from Workspace',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: examCtrl,
                decoration: const InputDecoration(labelText: 'Exam Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: subjectCtrl,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: boardCtrl,
                decoration: const InputDecoration(
                  labelText: 'Board / Authority',
                  hintText: 'e.g. Dhaka, Cambridge (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: yearCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Year'),
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
              final matId = matCtrl.text.trim();
              if (matId.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ApiService.analyzePastPaper(
                  materialId: matId,
                  examName: examCtrl.text.trim().isEmpty ? null : examCtrl.text.trim(),
                  subject: subjectCtrl.text.trim().isEmpty ? null : subjectCtrl.text.trim(),
                  board: boardCtrl.text.trim().isEmpty ? null : boardCtrl.text.trim(),
                  year: int.tryParse(yearCtrl.text.trim()),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Paper analyzed successfully!')),
                  );
                }
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to analyze: $e')),
                  );
                }
              }
            },
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Past Paper Intelligence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAnalyzeDialog,
            tooltip: 'Analyze Paper',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
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
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_insights != null) _buildInsightsOverview(theme),
                    const SizedBox(height: 16),
                    _buildPapersList(theme),
                    const SizedBox(height: 16),
                    if (_insights != null && _insights!.topicStats.isNotEmpty)
                      _buildTopicStatsList(theme),
                  ],
                ),
    );
  }

  Widget _buildInsightsOverview(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historical Coverage',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatBlock(
                  label: 'Papers Analyzed',
                  value: '${_insights!.papersAnalyzed}',
                ),
                _StatBlock(
                  label: 'Questions',
                  value: '${_insights!.totalQuestions}',
                ),
                _StatBlock(
                  label: 'Years Covered',
                  value: _insights!.yearsCovered.isNotEmpty
                      ? '${_insights!.yearsCovered.length}'
                      : '0',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPapersList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Analyzed Papers (${_papers.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Paper'),
              onPressed: _showAnalyzeDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_papers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text('No past papers analyzed yet. Tap "Add Paper" to begin.'),
            ),
          )
        else
          ..._papers.map((p) => _PaperCard(paper: p)),
      ],
    );
  }

  Widget _buildTopicStatsList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frequently Tested Topics (Historical Data)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ranked by frequency in analyzed past papers. Not a prediction of future exam content.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        ..._insights!.topicStats.take(15).map(
              (ts) => _TopicStatRow(stat: ts),
            ),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({required this.paper});
  final Map<String, dynamic> paper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = paper['examName'] as String? ?? 'Past Paper';
    final subject = paper['subject'] as String? ?? 'General';
    final year = paper['year'] != null ? '${paper['year']}' : '';
    final count = paper['questionCount'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.description, color: theme.colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          [subject, if (year.isNotEmpty) year, '$count questions']
              .where((s) => s.isNotEmpty)
              .join(' · '),
        ),
      ),
    );
  }
}

class _TopicStatRow extends StatelessWidget {
  const _TopicStatRow({required this.stat});
  final Map<String, dynamic> stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = stat['displayTopic'] as String? ?? stat['topic'] as String? ?? '';
    final label = stat['frequencyLabel'] as String? ?? 'Frequently Tested';
    final qCount = stat['questionCount'] as int? ?? 0;
    final pFreq = (stat['historicalFrequencyScore'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$label · $qCount question(s)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$pFreq%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
