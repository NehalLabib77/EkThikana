// Phase 14 — Document Intelligence Screen.
//
// Entry point: MaterialReaderScreen shows an "Analyze" button that navigates
// here. Provides tabs: Overview, Summary, Concept Map, Study Tools, Tutor.
//
// Architecture:
//   - Single screen with DefaultTabController
//   - All API calls go through canonical ApiService
//   - Processing states: uploaded → extracting → processing → ready / failed
//   - Cache-first: re-opening after "ready" makes 0 AI calls
//   - No duplicate HTTP client; no second AI service

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../tutor/ziku_tutor_screen.dart';

class DocumentIntelligenceScreen extends StatefulWidget {
  const DocumentIntelligenceScreen({
    super.key,
    required this.materialId,
    required this.materialTitle,
    this.mimeType = '',
    this.subject = '',
  });

  final String materialId;
  final String materialTitle;
  final String mimeType;
  final String subject;

  static Route<void> route({
    required String materialId,
    required String materialTitle,
    String mimeType = '',
    String subject = '',
  }) =>
      GochanoRoute.to<void>(
        builder: (_) => DocumentIntelligenceScreen(
          materialId: materialId,
          materialTitle: materialTitle,
          mimeType: mimeType,
          subject: subject,
        ),
      );

  @override
  State<DocumentIntelligenceScreen> createState() =>
      _DocumentIntelligenceScreenState();
}

// ---------------------------------------------------------------------------
// Processing status
// ---------------------------------------------------------------------------

enum _DocStatus { unknown, uploaded, extracting, processing, ready, failed }

_DocStatus _parseStatus(String? s) {
  switch (s) {
    case 'extracting':
      return _DocStatus.extracting;
    case 'processing':
      return _DocStatus.processing;
    case 'ready':
      return _DocStatus.ready;
    case 'failed':
      return _DocStatus.failed;
    default:
      return _DocStatus.uploaded;
  }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _DocumentIntelligenceScreenState
    extends State<DocumentIntelligenceScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;

  _DocStatus _status = _DocStatus.unknown;
  Map<String, dynamic>? _intelligence;
  String _error = '';
  bool _loading = true;
  bool _processing = false;

  // Content generation state
  bool _generatingFlashcards = false;
  bool _generatingRevision = false;
  bool _generatingStudyPack = false;
  bool _generatingQuiz = false;
  bool _generatingExam = false;

  static const _tabs = ['Overview', 'Summary', 'Concept Map', 'Study Tools', 'Tutor'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadIntelligence();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // ---------- Network ----------

  Future<void> _loadIntelligence() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await ApiService.getMaterialIntelligence(widget.materialId);
      final statusStr = data['status'] as String? ??
          (data['intelligenceStatus'] as String?);
      setState(() {
        _status = _parseStatus(statusStr);
        if (_status == _DocStatus.ready) {
          _intelligence = data;
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      // 409 means not processed yet — show process button
      if (e.statusCode == 409) {
        setState(() {
          _status = _DocStatus.uploaded;
          _loading = false;
        });
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = _DocStatus.uploaded;
        _loading = false;
      });
    }
  }

  Future<void> _processDocument() async {
    setState(() {
      _processing = true;
      _error = '';
      _status = _DocStatus.extracting;
    });
    try {
      await ApiService.processMaterial(widget.materialId);
      setState(() => _status = _DocStatus.processing);
      // Poll for ready
      await Future.delayed(const Duration(seconds: 3));
      await _loadIntelligence();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _status = _DocStatus.failed;
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _generateContent(String type) async {
    void setFlag(bool v) {
      if (!mounted) return;
      setState(() {
        switch (type) {
          case 'flashcards': _generatingFlashcards = v;
          case 'revision': _generatingRevision = v;
          case 'study_pack': _generatingStudyPack = v;
          case 'quiz': _generatingQuiz = v;
          case 'exam': _generatingExam = v;
        }
      });
    }

    setFlag(true);
    try {
      final title = widget.materialTitle;
      Map<String, dynamic> result;
      switch (type) {
        case 'flashcards':
          result = await ApiService.documentFlashcards(widget.materialId, topic: title);
        case 'revision':
          result = await ApiService.documentRevisionSheet(widget.materialId, topic: title);
        case 'study_pack':
          result = await ApiService.documentStudyPack(widget.materialId, topic: title);
        case 'quiz':
          result = await ApiService.documentQuiz(widget.materialId, topic: title);
        case 'exam':
          result = await ApiService.documentExam(widget.materialId, topic: title);
        default:
          return;
      }
      if (mounted) {
        _showContentResult(type, result);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      setFlag(false);
    }
  }

  void _showContentResult(String type, Map<String, dynamic> result) {
    final label = switch (type) {
      'flashcards' => 'Flashcards',
      'revision' => 'Revision Sheet',
      'study_pack' => 'Study Pack',
      'quiz' => 'Quiz',
      'exam' => 'Exam',
      _ => 'Content',
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: ctx.type.sectionHeading),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: sc,
                padding: const EdgeInsets.all(GochanoSpacing.md),
                child: Text(
                  result['content']?.toString() ??
                      result['questions']?.toString() ??
                      result.toString(),
                  style: ctx.type.body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _launchTutor() {
    final intel = _intelligence;
    final subject = intel?['overview']?['subject'] as String? ??
        (widget.subject.isNotEmpty ? widget.subject : 'General');
    final topic = widget.materialTitle;

    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => ZikuTutorScreen(
          subject: subject,
          topic: topic,
          materialId: widget.materialId,
        ),
      ),
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          GochanoLanguage.text('Document Intelligence', 'ডকুমেন্ট বিশ্লেষণ'),
          style: context.type.cardHeading,
        ),
        bottom: _status == _DocStatus.ready && _tabController != null
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: _tabs.map((t) => Tab(text: t)).toList(),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const StaticLoadingState(message: 'Loading intelligence…');
    }

    switch (_status) {
      case _DocStatus.unknown:
      case _DocStatus.uploaded:
        return _buildUploadedState();
      case _DocStatus.extracting:
      case _DocStatus.processing:
        return _buildProcessingState();
      case _DocStatus.ready:
        return _buildReadyState();
      case _DocStatus.failed:
        return _buildFailedState();
    }
  }

  // --- State UIs ---

  Widget _buildUploadedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 64, color: context.colors.study),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('Analyze Document', 'ডকুমেন্ট বিশ্লেষণ করুন'),
              style: context.type.sectionHeading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text(
                'Ziku will extract key concepts, generate a concept map, '
                'and prepare study tools from "${widget.materialTitle}".',
                '"${widget.materialTitle}" থেকে মূল ধারণা, concept map এবং '
                'study tools তৈরি করতে Analyze করুন।',
              ),
              style: context.type.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.lg),
            PrimaryButton(
              label: GochanoLanguage.text(
                'Analyze Document', 'বিশ্লেষণ শুরু করুন'),
              icon: Icons.auto_awesome,
              onPressed: _processing ? null : _processDocument,
              busy: _processing,
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Text(_error,
                  style: context.type.bodySecondary
                      .copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingState() {
    final msg = _status == _DocStatus.extracting
        ? GochanoLanguage.text('Extracting text…', 'টেক্সট বের করা হচ্ছে…')
        : GochanoLanguage.text('Analyzing document…', 'বিশ্লেষণ চলছে…');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: GochanoSpacing.md),
            Text(msg, style: context.type.body),
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text(
                'This may take up to 30 seconds.',
                'এটি ৩০ সেকেন্ড পর্যন্ত সময় নিতে পারে।',
              ),
              style: context.type.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: context.colors.error),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('Processing Failed', 'প্রক্রিয়া ব্যর্থ হয়েছে'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            if (_error.isNotEmpty)
              Text(_error,
                  style: context.type.bodySecondary, textAlign: TextAlign.center),
            const SizedBox(height: GochanoSpacing.lg),
            SecondaryButton(
              label: GochanoLanguage.text('Retry', 'আবার চেষ্টা করুন'),
              icon: Icons.refresh,
              onPressed: _processDocument,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyState() {
    final intel = _intelligence ?? {};
    return TabBarView(
      controller: _tabController,
      children: [
        _OverviewTab(intelligence: intel, truncated: intel['truncated'] == true),
        _SummaryTab(intelligence: intel),
        _ConceptMapTab(intelligence: intel),
        _StudyToolsTab(
          onFlashcards: _generatingFlashcards ? null : () => _generateContent('flashcards'),
          onRevision: _generatingRevision ? null : () => _generateContent('revision'),
          onStudyPack: _generatingStudyPack ? null : () => _generateContent('study_pack'),
          onQuiz: _generatingQuiz ? null : () => _generateContent('quiz'),
          onExam: _generatingExam ? null : () => _generateContent('exam'),
          generating: _generatingFlashcards || _generatingRevision ||
              _generatingStudyPack || _generatingQuiz || _generatingExam,
        ),
        _TutorTab(
          intelligence: intel,
          materialTitle: widget.materialTitle,
          onLaunch: _launchTutor,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Overview
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.intelligence, required this.truncated});

  final Map<String, dynamic> intelligence;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    final ov = (intelligence['overview'] as Map<String, dynamic>?) ?? {};
    final sections = (ov['detectedSections'] as List<dynamic>?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (truncated)
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.amber),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        'Document was truncated at processing limits.',
                        'ডকুমেন্ট সীমার কারণে কিছু অংশ বিশ্লেষণ করা হয়নি।',
                      ),
                      style: context.type.bodySecondary,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: GochanoSpacing.sm),
          _InfoRow(
            icon: Icons.book,
            label: GochanoLanguage.text('Title', 'শিরোনাম'),
            value: ov['title']?.toString() ?? '',
          ),
          _InfoRow(
            icon: Icons.subject,
            label: GochanoLanguage.text('Subject', 'বিষয়'),
            value: ov['subject']?.toString() ?? '',
          ),
          if ((ov['curriculumLevel'] ?? '').toString().isNotEmpty)
            _InfoRow(
              icon: Icons.school,
              label: GochanoLanguage.text('Level', 'স্তর'),
              value: ov['curriculumLevel']?.toString() ?? '',
            ),
          _InfoRow(
            icon: Icons.pages,
            label: GochanoLanguage.text('Pages', 'পৃষ্ঠা'),
            value: '${ov['pageCount'] ?? 0}',
          ),
          _InfoRow(
            icon: Icons.timer,
            label: GochanoLanguage.text('Read time', 'পড়ার সময়'),
            value: '${ov['estimatedReadMinutes'] ?? 0} min',
          ),
          if (sections.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('Detected Sections', 'পাওয়া অধ্যায়সমূহ'),
              style: context.type.label,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            ...sections.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(child: Text(s.toString(), style: context.type.body)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.colors.study),
          const SizedBox(width: GochanoSpacing.sm),
          Text('$label: ', style: context.type.label),
          Expanded(child: Text(value, style: context.type.body)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Summary
// ---------------------------------------------------------------------------

class _SummaryTab extends StatefulWidget {
  const _SummaryTab({required this.intelligence});
  final Map<String, dynamic> intelligence;

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final summary = (widget.intelligence['summary'] as Map<String, dynamic>?) ?? {};
    final labels = [
      GochanoLanguage.text('Short', 'সংক্ষিপ্ত'),
      GochanoLanguage.text('Detailed', 'বিস্তারিত'),
      GochanoLanguage.text('Exam Focus', 'পরীক্ষার জন্য'),
    ];
    final contents = [
      summary['short']?.toString() ?? '',
      summary['detailed']?.toString() ?? '',
      summary['examFocused']?.toString() ?? '',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: GochanoSpacing.sm,
            children: List.generate(labels.length, (i) {
              return ChoiceChip(
                label: Text(labels[i]),
                selected: _selected == i,
                onSelected: (_) => setState(() => _selected = i),
              );
            }),
          ),
          const SizedBox(height: GochanoSpacing.md),
          AppCard(
            child: Text(
              contents[_selected].isNotEmpty
                  ? contents[_selected]
                  : GochanoLanguage.text('No summary available.', 'সারসংক্ষেপ পাওয়া যায়নি।'),
              style: context.type.body,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Concept Map
// ---------------------------------------------------------------------------

class _ConceptMapTab extends StatelessWidget {
  const _ConceptMapTab({required this.intelligence});
  final Map<String, dynamic> intelligence;

  @override
  Widget build(BuildContext context) {
    final concepts =
        (intelligence['conceptMap'] as List<dynamic>?) ?? [];
    final topics = (intelligence['importantTopics'] as List<dynamic>?) ?? [];

    if (concepts.isEmpty && topics.isEmpty) {
      return const EmptyState(
        illustration: GochanoArt.featureStudy,
        title: 'No concept map',
        message: 'Concept data not yet available.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (concepts.isNotEmpty) ...[
            Text(
              GochanoLanguage.text('Key Concepts', 'মূল ধারণাসমূহ'),
              style: context.type.cardHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            ...concepts.map((c) {
              final m = (c as Map<String, dynamic>? ?? {});
              final prereqs = (m['prerequisites'] as List<dynamic>?) ?? [];
              final formulas = (m['formulas'] as List<dynamic>?) ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['name']?.toString() ?? '', style: context.type.label),
                      if ((m['description'] ?? '').toString().isNotEmpty)
                        Text(m['description'].toString(), style: context.type.bodySecondary),
                      if (prereqs.isNotEmpty) ...[
                        const SizedBox(height: GochanoSpacing.xs),
                        Wrap(
                          spacing: 4,
                          children: prereqs
                              .map((p) => Chip(label: Text(p.toString(), style: context.type.caption)))
                              .toList(),
                        ),
                      ],
                      if (formulas.isNotEmpty) ...[
                        const SizedBox(height: GochanoSpacing.xs),
                        ...formulas.map(
                          (f) => Text('📐 $f', style: context.type.bodySecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
          if (topics.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('Important Topics', 'গুরুত্বপূর্ণ বিষয়'),
              style: context.type.cardHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            ...topics.map((t) {
              final m = (t as Map<String, dynamic>? ?? {});
              final pages = (m['sourcePages'] as List<dynamic>?) ?? [];
              final score = ((m['importanceScore'] as num?) ?? 0.0).toDouble();
              return Padding(
                padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                child: AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['topic']?.toString() ?? '', style: context.type.label),
                            if ((m['keyInsight'] ?? '').toString().isNotEmpty)
                              Text(m['keyInsight'].toString(), style: context.type.bodySecondary),
                            if (pages.isNotEmpty)
                              Wrap(
                                spacing: 4,
                                children: pages
                                    .map((p) => _PageBadge(page: p.toString()))
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.sm),
                      _ImportanceBar(score: score),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _PageBadge extends StatelessWidget {
  const _PageBadge({required this.page});
  final String page;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.study.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('p.$page', style: context.type.caption),
    );
  }
}

class _ImportanceBar extends StatelessWidget {
  const _ImportanceBar({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${(score * 100).round()}%', style: context.type.caption),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          width: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score,
              minHeight: 48,
              backgroundColor: context.colors.surface,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Study Tools
// ---------------------------------------------------------------------------

class _StudyToolsTab extends StatelessWidget {
  const _StudyToolsTab({
    required this.onFlashcards,
    required this.onRevision,
    required this.onStudyPack,
    required this.onQuiz,
    required this.onExam,
    required this.generating,
  });

  final VoidCallback? onFlashcards;
  final VoidCallback? onRevision;
  final VoidCallback? onStudyPack;
  final VoidCallback? onQuiz;
  final VoidCallback? onExam;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (Icons.style, GochanoLanguage.text('Flashcards', 'ফ্ল্যাশকার্ড'), onFlashcards),
      (Icons.edit_note, GochanoLanguage.text('Revision Sheet', 'রিভিশন শিট'), onRevision),
      (Icons.menu_book, GochanoLanguage.text('Study Pack', 'স্টাডি প্যাক'), onStudyPack),
      (Icons.quiz, GochanoLanguage.text('Practice Quiz', 'কুইজ'), onQuiz),
      (Icons.assignment, GochanoLanguage.text('Mock Exam', 'মক পরীক্ষা'), onExam),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        children: [
          if (generating)
            const Padding(
              padding: EdgeInsets.only(bottom: GochanoSpacing.md),
              child: LinearProgressIndicator(),
            ),
          ...tools.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
              child: AppCard(
                child: ListTile(
                  leading: Icon(t.$1, color: context.colors.study),
                  title: Text(t.$2, style: context.type.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: t.$3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Tutor
// ---------------------------------------------------------------------------

class _TutorTab extends StatelessWidget {
  const _TutorTab({
    required this.intelligence,
    required this.materialTitle,
    required this.onLaunch,
  });

  final Map<String, dynamic> intelligence;
  final String materialTitle;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school, size: 72, color: context.colors.study),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text('Study with Ziku', 'Ziku-এর সাথে পড়ো'),
              style: context.type.sectionHeading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text(
                'Ziku will ask Socratic questions about "$materialTitle" '
                'and guide your understanding with document citations.',
                '"$materialTitle" থেকে Socratic প্রশ্ন করে Ziku তোমাকে '
                'বুঝতে সাহায্য করবে।',
              ),
              style: context.type.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.lg),
            PrimaryButton(
              label: GochanoLanguage.text('Start Tutor Session', 'Tutor শুরু করুন'),
              icon: Icons.chat,
              onPressed: onLaunch,
            ),
          ],
        ),
      ),
    );
  }
}
