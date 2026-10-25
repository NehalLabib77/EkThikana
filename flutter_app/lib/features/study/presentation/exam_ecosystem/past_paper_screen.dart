/// Phase 15.1 — Past Papers Intelligence Screen.
///
/// Allows students to view analyzed past papers, historical insights,
/// and analyze materials from Workspace as past papers.
/// Strictly historical language: "Frequently Tested", "High Historical Coverage".
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'exam_ecosystem_models.dart';

class PastPaperScreen extends StatefulWidget {
  const PastPaperScreen({
    super.key,
    this.initialPapers,
    this.initialInsights,
    this.initialError,
    this.loadDataOverride,
    this.analyzePaperOverride,
  });

  static const routeName = '/past-papers';

  final List<Map<String, dynamic>>? initialPapers;
  final PastPaperInsight? initialInsights;
  final String? initialError;
  final Future<void> Function()? loadDataOverride;
  final Future<void> Function({
    required String materialId,
    String? examName,
    String? subject,
    String? board,
    int? year,
  })? analyzePaperOverride;

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
    if (widget.initialPapers != null ||
        widget.initialInsights != null ||
        widget.initialError != null) {
      _loading = false;
      _papers = widget.initialPapers ?? [];
      _insights = widget.initialInsights;
      _error = widget.initialError;
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final isBengali = GochanoLanguage.isBangla;

    if (widget.loadDataOverride != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        await widget.loadDataOverride!();
      } catch (e) {
        _error = e.toString();
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

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
      _error = isBengali
          ? 'বিগত প্রশ্নের তথ্য লোড করতে ব্যর্থ হয়েছে।'
          : 'Failed to load past papers data.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAnalyzeDialog() {
    final isBengali = GochanoLanguage.isBangla ||
        Localizations.maybeLocaleOf(context)?.languageCode == 'bn';
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final matCtrl = TextEditingController();
    final examCtrl = TextEditingController(
      text: isBengali ? 'ফাইনাল পরীক্ষা' : 'Final Exam',
    );
    final boardCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: '${DateTime.now().year - 1}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: GochanoRadius.lgAll),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? AppGradients.emeraldDark.withValues(alpha: 0.2)
                    : AppGradients.emeraldSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assignment_turned_in_rounded,
                size: 20,
                color: AppGradients.emeraldDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isBengali
                    ? 'বিগত প্রশ্নপত্র বিশ্লেষণ করুন'
                    : 'Analyze Workspace Past Paper',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: matCtrl,
                decoration: InputDecoration(
                  labelText: isBengali
                      ? 'ম্যাটেরিয়াল আইডি (Material ID)'
                      : 'Material ID',
                  hintText: isBengali
                      ? 'ওয়ার্কস্পেসের ম্যাটেরিয়াল আইডি লিখুন'
                      : 'Enter material ID from Workspace',
                  filled: true,
                  fillColor: colors.surfaceVariant.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: GochanoRadius.mdAll,
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: examCtrl,
                decoration: InputDecoration(
                  labelText: isBengali ? 'পরীক্ষার নাম' : 'Exam Name',
                  filled: true,
                  fillColor: colors.surfaceVariant.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: GochanoRadius.mdAll,
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subjectCtrl,
                decoration: InputDecoration(
                  labelText: isBengali ? 'বিষয়' : 'Subject',
                  filled: true,
                  fillColor: colors.surfaceVariant.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: GochanoRadius.mdAll,
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: boardCtrl,
                decoration: InputDecoration(
                  labelText: isBengali ? 'বোর্ড / কর্তৃপক্ষ' : 'Board / Authority',
                  hintText: isBengali
                      ? 'যেমন: ঢাকা, ক্যামব্রিজ (ঐচ্ছিক)'
                      : 'e.g. Dhaka, Cambridge (optional)',
                  filled: true,
                  fillColor: colors.surfaceVariant.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: GochanoRadius.mdAll,
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: yearCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isBengali ? 'বছর' : 'Year',
                  filled: true,
                  fillColor: colors.surfaceVariant.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: GochanoRadius.mdAll,
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isBengali ? 'বাতিল' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.brand,
              shape: RoundedRectangleBorder(borderRadius: GochanoRadius.smAll),
            ),
            onPressed: () async {
              final matId = matCtrl.text.trim();
              if (matId.isEmpty) return;
              Navigator.pop(ctx);
              try {
                if (widget.analyzePaperOverride != null) {
                  await widget.analyzePaperOverride!(
                    materialId: matId,
                    examName: examCtrl.text.trim().isEmpty
                        ? null
                        : examCtrl.text.trim(),
                    subject: subjectCtrl.text.trim().isEmpty
                        ? null
                        : subjectCtrl.text.trim(),
                    board: boardCtrl.text.trim().isEmpty
                        ? null
                        : boardCtrl.text.trim(),
                    year: int.tryParse(yearCtrl.text.trim()),
                  );
                } else {
                  await ApiService.analyzePastPaper(
                    materialId: matId,
                    examName: examCtrl.text.trim().isEmpty
                        ? null
                        : examCtrl.text.trim(),
                    subject: subjectCtrl.text.trim().isEmpty
                        ? null
                        : subjectCtrl.text.trim(),
                    board: boardCtrl.text.trim().isEmpty
                        ? null
                        : boardCtrl.text.trim(),
                    year: int.tryParse(yearCtrl.text.trim()),
                  );
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isBengali
                            ? 'প্রশ্নপত্র সফলভাবে বিশ্লেষণ করা হয়েছে!'
                            : 'Paper analyzed successfully!',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isBengali
                            ? 'বিশ্লেষণ ব্যর্থ হয়েছে: $e'
                            : 'Failed to analyze: $e',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Text(isBengali ? 'বিশ্লেষণ করুন' : 'Analyze'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBengali = GochanoLanguage.isBangla ||
        Localizations.maybeLocaleOf(context)?.languageCode == 'bn';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: GochanoAppBar(
        title: isBengali ? 'বিগত প্রশ্ন' : 'Past Papers',
        subtitle: isBengali
            ? 'বিগত পরীক্ষার প্রশ্ন ও ট্রেন্ড বিশ্লেষণ'
            : 'Exam trends & historical question coverage',
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppGradients.emeraldDark),
            onPressed: _showAnalyzeDialog,
            tooltip: isBengali ? 'প্রশ্ন বিশ্লেষণ যোগ করুন' : 'Analyze Paper',
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colors.textSecondary),
            onPressed: _loadData,
            tooltip: isBengali ? 'রিফ্রেশ করুন' : 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isBengali
                        ? 'বিগত প্রশ্নের তথ্য লোড হচ্ছে…'
                        : 'Loading past papers data…',
                    style: type.bodySecondary,
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 36,
                          color: colors.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: colors.error, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.brand,
                            shape: RoundedRectangleBorder(
                              borderRadius: GochanoRadius.smAll,
                            ),
                          ),
                          onPressed: _loadData,
                          child: Text(
                            isBengali ? 'পুনরায় চেষ্টা করুন' : 'Retry',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : AppPageBackground(
                  height: 240,
                  gradient: isDark
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppGradients.emeraldDark.withValues(alpha: 0.15),
                            colors.background,
                          ],
                        )
                      : AppGradients.toolPastPapers,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    children: [
                      if (_insights != null)
                        _buildInsightsOverview(context, isBengali, isDark),
                      const SizedBox(height: 16),
                      _buildPapersList(context, isBengali),
                      const SizedBox(height: 16),
                      if (_insights != null && _insights!.topicStats.isNotEmpty)
                        _buildTopicStatsList(context, isBengali),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInsightsOverview(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(
          color: AppGradients.emeraldDark.withValues(alpha: isDark ? 0.35 : 0.25),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppGradients.emeraldDark.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppGradients.emeraldDark.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.history_edu_rounded,
                  size: 20,
                  color: AppGradients.emeraldDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBengali
                          ? 'ঐতিহাসিক কভারেজ সারসংক্ষেপ'
                          : 'Historical Coverage',
                      style: type.cardHeading.copyWith(fontSize: 16),
                    ),
                    Text(
                      isBengali
                          ? 'বিশ্লেষিত পরীক্ষার তথ্যের উপর ভিত্তি করে'
                          : 'Based on analyzed past examination papers',
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatBlock(
                label: isBengali ? 'বিশ্লেষিত প্রশ্নপত্র' : 'Papers Analyzed',
                value: isBengali
                    ? GochanoLanguage.toBanglaDigits(_insights!.papersAnalyzed)
                    : '${_insights!.papersAnalyzed}',
              ),
              _StatBlock(
                label: isBengali ? 'মোট প্রশ্ন' : 'Questions',
                value: isBengali
                    ? GochanoLanguage.toBanglaDigits(_insights!.totalQuestions)
                    : '${_insights!.totalQuestions}',
              ),
              _StatBlock(
                label: isBengali ? 'কভার করা বছর' : 'Years Covered',
                value: _insights!.yearsCovered.isNotEmpty
                    ? (isBengali
                        ? GochanoLanguage.toBanglaDigits(
                            _insights!.yearsCovered.length,
                          )
                        : '${_insights!.yearsCovered.length}')
                    : (isBengali ? '০' : '0'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPapersList(BuildContext context, bool isBengali) {
    final colors = context.colors;
    final type = context.type;
    final countText = isBengali
        ? GochanoLanguage.toBanglaDigits(_papers.length)
        : '${_papers.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  size: 18,
                  color: AppGradients.emeraldDark,
                ),
                const SizedBox(width: 8),
                Text(
                  isBengali
                      ? 'বিশ্লেষিত প্রশ্নপত্র ($countText)'
                      : 'Analyzed Papers ($countText)',
                  style: type.cardHeading.copyWith(fontSize: 16),
                ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16, color: AppGradients.emeraldDark),
              label: Text(
                isBengali ? 'নতুন যোগ করুন' : 'Add Paper',
                style: const TextStyle(
                  color: AppGradients.emeraldDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _showAnalyzeDialog,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_papers.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: GochanoRadius.mdAll,
              border: Border.all(color: colors.border),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 32,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isBengali
                        ? 'এখনো কোনো বিগত প্রশ্নপত্র বিশ্লেষণ করা হয়নি। "নতুন যোগ করুন" এ চাপুন।'
                        : 'No past papers analyzed yet. Tap "Add Paper" to begin.',
                    style: type.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ..._papers.map((p) => _PaperCard(paper: p, isBengali: isBengali)),
      ],
    );
  }

  Widget _buildTopicStatsList(BuildContext context, bool isBengali) {
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isBengali
              ? 'ঘন ঘন আসা বিষয়সমূহ (ঐতিহাসিক তথ্য)'
              : 'Frequently Tested Topics (Historical Data)',
          style: type.cardHeading.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          isBengali
              ? 'বিগত পরীক্ষার প্রশ্নপত্রের পুনরাবৃত্তির উপর ভিত্তি করে সাজানো। ভবিষ্যৎ পরীক্ষার পূর্বাভাস নয়।'
              : 'Ranked by frequency in analyzed past papers. Not a prediction of future exam content.',
          style: type.caption,
        ),
        const SizedBox(height: 12),
        ..._insights!.topicStats.take(15).map(
              (ts) => _TopicStatRow(stat: ts, isBengali: isBengali),
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
    final type = context.type;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: type.caption,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: type.sectionHeading.copyWith(
              color: AppGradients.emeraldDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({required this.paper, this.isBengali = false});
  final Map<String, dynamic> paper;
  final bool isBengali;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = paper['examName'] as String? ??
        (isBengali ? 'বিগত প্রশ্ন' : 'Past Paper');
    final subject = paper['subject'] as String? ??
        (isBengali ? 'সাধারণ' : 'General');
    final year = paper['year'] != null
        ? (isBengali
            ? GochanoLanguage.toBanglaDigits(paper['year'])
            : '${paper['year']}')
        : '';
    final count = paper['questionCount'] as int? ?? 0;
    final countFormatted = isBengali
        ? '${GochanoLanguage.toBanglaDigits(count)} টি প্রশ্ন'
        : '$count questions';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark
                ? AppGradients.emeraldDark.withValues(alpha: 0.18)
                : AppGradients.emeraldSoft,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppGradients.emeraldAccent.withValues(alpha: isDark ? 0.35 : 0.25),
            ),
          ),
          child: const Icon(
            Icons.description_outlined,
            color: AppGradients.emeraldDark,
            size: 20,
          ),
        ),
        title: Text(title, style: type.cardHeading),
        subtitle: Text(
          [subject, if (year.isNotEmpty) year, countFormatted]
              .where((s) => s.isNotEmpty)
              .join(' · '),
          style: type.caption,
        ),
      ),
    );
  }
}

class _TopicStatRow extends StatelessWidget {
  const _TopicStatRow({required this.stat, this.isBengali = false});
  final Map<String, dynamic> stat;
  final bool isBengali;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topic =
        stat['displayTopic'] as String? ?? stat['topic'] as String? ?? '';
    final label = stat['frequencyLabel'] as String? ??
        (isBengali ? 'ঘন ঘন পরীক্ষিত' : 'Frequently Tested');
    final qCount = stat['questionCount'] as int? ?? 0;
    final pFreq = (stat['historicalFrequencyScore'] as num?)?.toInt() ?? 0;

    final qCountText = isBengali
        ? '${GochanoLanguage.toBanglaDigits(qCount)} টি প্রশ্ন'
        : '$qCount question(s)';
    final pFreqText = isBengali
        ? '${GochanoLanguage.toBanglaDigits(pFreq)}%'
        : '$pFreq%';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic,
                  style: type.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '$label · $qCountText',
                  style: type.caption,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? AppGradients.emeraldDark.withValues(alpha: 0.18)
                  : AppGradients.emeraldSoft,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AppGradients.emeraldAccent.withValues(alpha: isDark ? 0.35 : 0.25),
              ),
            ),
            child: Text(
              pFreqText,
              style: const TextStyle(
                color: AppGradients.emeraldDark,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
