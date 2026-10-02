// Phase 10.6 — Ziku Platform Admin Analytics Dashboard.
//
// Displays aggregate platform-wide educational metrics for administrators:
//   * Platform Overview (active students, AI requests, quiz attempts, exam attempts, content generated)
//   * Subject Demand
//   * Topic Difficulty (deterministic scoring with supporting metrics)
//   * Feature Usage
//   * Time-range filters (7d, 30d, 90d)
//
// Privacy guarantee: No individual student personal details, transcripts,
// raw answers, or notes are surfaced. Only aggregate counters and statistics.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/gochano_surfaces.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({
    super.key,
    this.initialDays = 30,
    this.userRole,
  });

  final int initialDays;
  final String? userRole;

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  late int _selectedDays;
  bool _loading = true;
  String? _errorMessage;

  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  List<Map<String, dynamic>> _features = [];

  @override
  void initState() {
    super.initState();
    _selectedDays = widget.initialDays;
    _fetchData();
  }

  bool get _isAuthorized => widget.userRole == null || widget.userRole == 'admin';

  Future<void> _fetchData() async {
    if (!_isAuthorized) {
      setState(() {
        _loading = false;
        _errorMessage = 'unauthorized';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        ApiService.adminAnalyticsOverview(days: _selectedDays),
        ApiService.adminAnalyticsSubjects(days: _selectedDays),
        ApiService.adminAnalyticsTopics(days: _selectedDays),
        ApiService.adminAnalyticsFeatures(days: _selectedDays),
      ]);

      if (!mounted) return;

      final overviewData = results[0];
      final subjectsData = (results[1]['subjects'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final topicsData = (results[2]['topics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final featuresData = (results[3]['features'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      setState(() {
        _overview = overviewData;
        _subjects = subjectsData;
        _topics = topicsData;
        _features = featuresData;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _onDaysChanged(int days) {
    if (_selectedDays == days) return;
    setState(() => _selectedDays = days);
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Platform Analytics', 'প্ল্যাটফর্ম অ্যানালিটিক্স'),
        subtitle: GochanoLanguage.text('Admin Intelligence', 'অ্যাডমিন ইনটেলিজেন্স'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: GochanoLanguage.text('Refresh', 'রিফ্রেশ'),
            onPressed: _loading ? null : _fetchData,
          ),
        ],
      ),
      body: _buildBody(colors, type),
    );
  }

  Widget _buildBody(GochanoColors colors, GochanoTypography type) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      if (_errorMessage == 'unauthorized' || _errorMessage!.contains('403') || _errorMessage!.contains('Forbidden')) {
        return _buildAccessDenied(colors, type);
      }
      return _buildErrorState(colors, type);
    }

    final hasData = (_overview != null && (_overview!['eventCount'] ?? 0) > 0) ||
        _subjects.isNotEmpty ||
        _topics.isNotEmpty ||
        _features.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _buildTimeFilter(colors, type),
          const SizedBox(height: GochanoSpacing.md),
          if (!hasData) ...[
            _buildEmptyState(colors, type),
          ] else ...[
            _buildOverviewSection(colors, type),
            const SizedBox(height: GochanoSpacing.lg),
            _buildSubjectDemandSection(colors, type),
            const SizedBox(height: GochanoSpacing.lg),
            _buildTopicDifficultySection(colors, type),
            const SizedBox(height: GochanoSpacing.lg),
            _buildFeatureUsageSection(colors, type),
            const SizedBox(height: GochanoSpacing.lg),
            _buildPrivacyNotice(colors, type),
          ],
          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildTimeFilter(GochanoColors colors, GochanoTypography type) {
    return Row(
      children: [
        Text(
          GochanoLanguage.text('Range:', 'সময়সীমা:'),
          style: type.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        for (final days in [7, 30, 90]) ...[
          Padding(
            padding: const EdgeInsets.only(right: GochanoSpacing.xs),
            child: ChoiceChip(
              label: Text(
                days == 7
                    ? GochanoLanguage.text('7 Days', '৭ দিন')
                    : days == 30
                        ? GochanoLanguage.text('30 Days', '৩০ দিন')
                        : GochanoLanguage.text('90 Days', '৯০ দিন'),
                style: type.caption.copyWith(
                  color: _selectedDays == days ? colors.onBrand : colors.textPrimary,
                  fontWeight: _selectedDays == days ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              selected: _selectedDays == days,
              selectedColor: colors.brand,
              backgroundColor: colors.surfaceVariant,
              showCheckmark: false,
              onSelected: (_) => _onDaysChanged(days),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOverviewSection(GochanoColors colors, GochanoTypography type) {
    final activeStudents = _overview?['activeStudents'] ?? 0;
    final aiRequests = _overview?['aiRequests'] ?? 0;
    final quizAttempts = _overview?['quizAttempts'] ?? 0;
    final examAttempts = _overview?['examAttempts'] ?? 0;
    final contentGenerated = _overview?['contentGenerated'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Platform Overview', 'প্ল্যাটফর্ম ওভারভিউ'),
          style: type.sectionHeading,
        ),
        const SizedBox(height: GochanoSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: GochanoLanguage.text('Active Students', 'সক্রিয় শিক্ষার্থী'),
                value: '$activeStudents',
                icon: Icons.people_outline_rounded,
                color: colors.brand,
                colors: colors,
                type: type,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: _buildMetricTile(
                title: GochanoLanguage.text('AI Requests', 'এআই অনুরোধ'),
                value: '$aiRequests',
                icon: Icons.auto_awesome_outlined,
                color: colors.ai,
                colors: colors,
                type: type,
              ),
            ),
          ],
        ),
        const SizedBox(height: GochanoSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: GochanoLanguage.text('Quiz Attempts', 'কুইজ সম্পন্ন'),
                value: '$quizAttempts',
                icon: Icons.quiz_outlined,
                color: colors.study,
                colors: colors,
                type: type,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: _buildMetricTile(
                title: GochanoLanguage.text('Exam Attempts', 'পরীক্ষা সম্পন্ন'),
                value: '$examAttempts',
                icon: Icons.timer_outlined,
                color: colors.warning,
                colors: colors,
                type: type,
              ),
            ),
          ],
        ),
        if (contentGenerated > 0) ...[
          const SizedBox(height: GochanoSpacing.sm),
          _buildMetricTile(
            title: GochanoLanguage.text('Content & Study Packs Generated', 'তৈরি কনটেন্ট ও স্টাডি প্যাক'),
            value: '$contentGenerated',
            icon: Icons.library_books_outlined,
            color: colors.info,
            colors: colors,
            type: type,
          ),
        ],
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required GochanoColors colors,
    required GochanoTypography type,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: type.caption.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            value,
            style: type.statisticSmall.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectDemandSection(GochanoColors colors, GochanoTypography type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Subject Demand', 'বিষয় চাহিদা'),
          style: type.sectionHeading,
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Text(
          GochanoLanguage.text(
            'Aggregated learning events by academic subject',
            'বিষয়ভিত্তিক শিক্ষামূলক ইভেন্টের সমষ্টি',
          ),
          style: type.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        if (_subjects.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Text(
                GochanoLanguage.text('No subject activity recorded yet.', 'এখনও কোনো বিষয় কার্যক্রম নেই।'),
                style: type.bodySecondary,
              ),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
            child: Column(
              children: [
                for (int i = 0; i < _subjects.length; i++) ...[
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: colors.brandSoft,
                      child: Text(
                        '${i + 1}',
                        style: type.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.brand,
                        ),
                      ),
                    ),
                    title: Text(
                      _subjects[i]['subject']?.toString() ?? 'General',
                      style: type.cardHeading,
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: GochanoRadius.smAll,
                      ),
                      child: Text(
                        '${_subjects[i]['eventCount'] ?? 0} events',
                        style: type.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (i < _subjects.length - 1)
                    Divider(height: 1, color: colors.divider),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTopicDifficultySection(GochanoColors colors, GochanoTypography type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Topic Difficulty', 'বিষয়ের কাঠিন্য বিশ্লেষণ'),
          style: type.sectionHeading,
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Text(
          GochanoLanguage.text(
            'Observed student struggle derived from wrong-answer rates & mistake frequency (min. 3 samples).',
            'ভুল উত্তরের হার ও পুনরাবৃত্তির ভিত্তিতে ছাত্রদের অনুভূত জটিলতা (ন্যূনতম ৩টি স্যাম্পল)।',
          ),
          style: type.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        if (_topics.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Text(
                GochanoLanguage.text(
                  'No topics meet the minimum sample size threshold (3 quizzes).',
                  'পর্যাপ্ত স্যাম্পলসহ কোনো জটিল বিষয় এখনও চিহ্নিত হয়নি।',
                ),
                style: type.bodySecondary,
              ),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
            child: Column(
              children: [
                for (int i = 0; i < _topics.length; i++) ...[
                  _buildTopicTile(_topics[i], colors, type),
                  if (i < _topics.length - 1)
                    Divider(height: 1, color: colors.divider),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTopicTile(Map<String, dynamic> topic, GochanoColors colors, GochanoTypography type) {
    final name = topic['topic']?.toString() ?? 'Unknown Topic';
    final score = (topic['difficultyScore'] as num?)?.toDouble() ?? 0.0;
    final metrics = (topic['supportingMetrics'] as Map<String, dynamic>?) ?? {};
    final samples = metrics['quizSamples'] ?? 0;
    final wrongRate = ((metrics['wrongAnswerRate'] as num?)?.toDouble() ?? 0.0) * 100;
    final repeatMistakes = metrics['repeatedMistakes'] ?? 0;

    Color badgeColor;
    if (score >= 60.0) {
      badgeColor = colors.error;
    } else if (score >= 35.0) {
      badgeColor = colors.warning;
    } else {
      badgeColor = colors.success;
    }

    return Padding(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: type.cardHeading,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: GochanoRadius.smAll,
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Score: ${score.toStringAsFixed(1)}',
                  style: type.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            'Samples: $samples | Wrong rate: ${wrongRate.toStringAsFixed(1)}% | Repeated mistakes: $repeatMistakes',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            topic['interpretation']?.toString() ??
                'Observed platform struggle, not an objective property of the topic.',
            style: type.caption.copyWith(
              fontStyle: FontStyle.italic,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureUsageSection(GochanoColors colors, GochanoTypography type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Feature Usage', 'ফিচার ব্যবহার পরিসংখ্যান'),
          style: type.sectionHeading,
        ),
        const SizedBox(height: GochanoSpacing.sm),
        if (_features.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Text(
                GochanoLanguage.text('No feature events recorded yet.', 'এখনও কোনো ফিচার ইভেন্ট নেই।'),
                style: type.bodySecondary,
              ),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.all(GochanoSpacing.md),
            child: Wrap(
              spacing: GochanoSpacing.sm,
              runSpacing: GochanoSpacing.sm,
              children: [
                for (final feat in _features) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: GochanoRadius.mdAll,
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          feat['eventName']?.toString() ?? '',
                          style: type.caption.copyWith(color: colors.textPrimary),
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.brandSoft,
                            borderRadius: GochanoRadius.smAll,
                          ),
                          child: Text(
                            '${feat['count'] ?? 0}',
                            style: type.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.brand,
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
      ],
    );
  }

  Widget _buildPrivacyNotice(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 20, color: colors.textSecondary),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Text(
              GochanoLanguage.text(
                'Privacy Notice: Platform analytics operate on aggregate counters and educational dimensions only. No student chat logs, notes, question text, or private profiles are stored or exposed.',
                'গোপনীয়তা বিজ্ঞপ্তি: প্ল্যাটফর্ম অ্যানালিটিক্স কেবল সমন্বিত কাউন্টার এবং শিক্ষাগত মাত্রায় কাজ করে। কোনো শিক্ষার্থীর চ্যাট, নোট, প্রশ্নের টেক্সট বা ব্যক্তিগত প্রোফাইল সংরক্ষিত বা প্রকাশিত হয় না।',
              ),
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(GochanoColors colors, GochanoTypography type) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xl),
        child: Column(
          children: [
            Icon(Icons.bar_chart_rounded, size: 48, color: colors.textTertiary),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('No Analytics Available', 'কোনো অ্যানালিটিক্স পাওয়া যায়নি'),
              style: type.cardHeading,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text(
                'No events have been recorded for the selected time range.',
                'নির্বাচিত সময়সীমার জন্য কোনো ইভেন্ট রেকর্ড করা হয়নি।',
              ),
              style: type.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(GochanoColors colors, GochanoTypography type) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colors.error),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('Failed to Load Analytics', 'অ্যানালিটিক্স লোড করতে ব্যর্থ'),
              style: type.cardHeading,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              _errorMessage ?? '',
              style: type.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.md),
            FilledButton.icon(
              onPressed: _fetchData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(GochanoLanguage.text('Retry', 'আবার চেষ্টা করুন')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessDenied(GochanoColors colors, GochanoTypography type) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 48, color: colors.warning),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('Access Restricted', 'প্রবেশাধিকার সংরক্ষিত'),
              style: type.cardHeading,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text(
                'Administrator privileges are required to view platform analytics.',
                'প্ল্যাটফর্ম অ্যানালিটিক্স দেখার জন্য অ্যাডমিনিস্ট্রেটর অ্যাকাউন্টের প্রয়োজন।',
              ),
              style: type.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

