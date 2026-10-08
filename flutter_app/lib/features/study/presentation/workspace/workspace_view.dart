// Study workspace — launcher for study tools and recent materials (spec §29).
//
// Modern, premium, utility-first study hub featuring:
// 1. Pinned Study Header (logo only, language toggle, search, notification)
// 2. Page introduction & subtitle
// 3. Workspace search bar with instant tool & material filtering
// 4. Horizontal category filter chips
// 5. Cohesive Study Tools 2-column responsive grid with semantic gradients
// 6. Active Exam Rescue discovery tile
// 7. Quick Shortcuts expandable drawer
// 8. Recently Opened section with live Firestore streaming, skeleton loading, and empty state

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../community/presentation/shared_box_screen.dart';
import '../../../search/presentation/universal_search_screen.dart';
import '../ai/ai_assistant_screen.dart';
import '../ai/assignment_assistant_screen.dart';
import '../ai/learning_insights_screen.dart';
import '../ai/quiz_generator_screen.dart';
import '../ai/smart_planner_screen.dart';
import '../content/flashcard_screen.dart';
import '../exam_ecosystem/exam_hub_screen.dart';
import '../exam_ecosystem/past_paper_screen.dart';
import '../materials/material_reader_screen.dart';
import '../materials/materials_screen.dart';
import '../materials/saved_materials_screen.dart';
import '../notes/notes_screen.dart';
import '../rescue/exam_rescue_models.dart';
import '../rescue/exam_rescue_session_service.dart';
import 'semester_list_screen.dart';

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    super.key,
    this.onOpenPlan,
    this.examRescueSessionService,
    this.mockRecentMaterials,
  });

  /// Jumps to the Plan tab (index 2) where the Exam Rescue banner lives.
  final VoidCallback? onOpenPlan;
  final ExamRescueSessionService? examRescueSessionService;
  final List<Map<String, dynamic>>? mockRecentMaterials;

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    GochanoLanguage.current.addListener(_onLanguageChange);
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageChange);
    _searchController.dispose();
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  List<String> get _filterCategories => [
        GochanoLanguage.text('All', 'সব'),
        GochanoLanguage.text('Notes', 'নোট'),
        GochanoLanguage.text('Flashcards', 'ফ্ল্যাশকার্ড'),
        GochanoLanguage.text('Past Papers', 'বিগত প্রশ্ন'),
        GochanoLanguage.text('Materials', 'উপকরণ'),
        GochanoLanguage.text('Practice', 'অনুশীলন'),
        GochanoLanguage.text('Saved', 'সংরক্ষিত'),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // -------------------------------------------------------------
              // PINNED STUDY HEADER (Identical to approved Today header)
              // -------------------------------------------------------------
              const AppStudyHeader(),

              // -------------------------------------------------------------
              // SCROLLABLE WORKSPACE CONTENT
              // -------------------------------------------------------------
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(
                        child: SizedBox(height: GochanoSpacing.xs),
                      ),

                      // Intro + Search + Filters
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildIntro(context),
                              const SizedBox(height: GochanoSpacing.sm),
                              AppWorkspaceSearchField(
                                controller: _searchController,
                                onChanged: (q) => setState(() => _searchQuery = q.trim()),
                                onSubmitted: (q) {
                                  if (q.trim().isNotEmpty) {
                                    Navigator.of(context).push(
                                      GochanoRoute.to(
                                        builder: (_) => UniversalSearchScreen(
                                          initialQuery: q.trim(),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: GochanoSpacing.sm),
                              AppWorkspaceFilterChips(
                                categories: _filterCategories,
                                selectedCategory: _selectedCategory == 'All'
                                    ? _filterCategories[0]
                                    : _selectedCategory,
                                onSelect: (cat) {
                                  setState(() {
                                    if (cat == _filterCategories[0]) {
                                      _selectedCategory = 'All';
                                    } else {
                                      _selectedCategory = cat;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: GochanoSpacing.md),
                            ],
                          ),
                        ),
                      ),

                      // Exam Rescue Tile (when active or prompt)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
                            child: ExamRescueTile(
                              onOpenPlan: widget.onOpenPlan,
                              examRescueSessionService:
                                  widget.examRescueSessionService,
                            ),
                          ),
                        ),
                      ),

                      // Study Tools Grid Section
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _buildStudyToolsSection(context),
                        ),
                      ),

                      // Quick Shortcuts (Expandable 4-column panel)
                      const SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                          vertical: GochanoSpacing.sm,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _QuickAccess(),
                        ),
                      ),

                      // Recently Opened Materials Section
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: widget.mockRecentMaterials != null
                              ? _RecentMaterials(
                                  searchQuery: _searchQuery,
                                  mockRecentMaterials: widget.mockRecentMaterials,
                                )
                              : (_searchQuery.isEmpty
                                  ? const _RecentMaterials()
                                  : _RecentMaterials(searchQuery: _searchQuery)),
                        ),
                      ),

                      // Bottom spacing for navigation bar
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 80),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Workspace', 'ওয়ার্কস্পেস'),
          style: context.type.pageTitle.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          GochanoLanguage.text(
            'Tools to help you study better.',
            'আপনার পড়াশোনা আরও সহজ করার টুলস।',
          ),
          style: context.type.bodySecondary.copyWith(
            color: colors.textSecondary,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStudyToolsSection(BuildContext context) {
    final colors = context.colors;
    final allTools = _getToolsList(context);

    // Apply category filter and search query filter
    final filteredTools = allTools.where((tool) {
      if (_selectedCategory != 'All') {
        if (!tool.matchesCategory(_selectedCategory, _filterCategories)) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matches = tool.title.toLowerCase().contains(q) ||
            tool.subtitle.toLowerCase().contains(q);
        if (!matches) return false;
      }
      return true;
    }).toList();

    return AppSectionContainer(
      title: GochanoLanguage.text('Study Tools', 'স্টাডি টুলস'),
      icon: Icons.grid_view_rounded,
      iconColor: colors.brand,
      child: filteredTools.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  GochanoLanguage.text(
                    'No tools match your filter.',
                    'কোনো টুলস খুঁজে পাওয়া যায়নি।',
                  ),
                  style: context.type.bodySecondary,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 340;
                final crossAxisCount = 2;
                final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                final double baseExtent = isNarrow ? 128.0 : 124.0;
                final double dynamicExtent =
                    textScale > 1.0 ? baseExtent + (textScale - 1.0) * 44.0 : baseExtent;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: filteredTools.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: dynamicExtent,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final tool = filteredTools[index];
                    return AppWorkspaceToolCard(
                      icon: tool.icon,
                      title: tool.title,
                      subtitle: tool.subtitle,
                      accent: tool.accent,
                      gradient: tool.gradient,
                      onTap: tool.onTap,
                    );
                  },
                );
              },
            ),
    );
  }

  List<_ToolItem> _getToolsList(BuildContext context) {
    return [
      _ToolItem(
        icon: Icons.description_rounded,
        title: GochanoLanguage.text('My Notes', 'আমার নোট'),
        subtitle: GochanoLanguage.text('Create & organize lecture notes', 'লেকচার নোট তৈরি ও সাজান'),
        accent: const Color(0xFF2563EB),
        gradient: AppGradients.toolNotes,
        categoryTag: 'Notes',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const NotesScreen()),
        ),
      ),
      _ToolItem(
        icon: Icons.style_rounded,
        title: GochanoLanguage.text('Flashcards', 'ফ্ল্যাশকার্ড'),
        subtitle: GochanoLanguage.text('Active recall & quick revision', 'দ্রুত রিভিশন ও মনে রাখার জন্য'),
        accent: const Color(0xFF8B5CF6),
        gradient: AppGradients.toolFlashcards,
        categoryTag: 'Flashcards',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const FlashcardScreen()),
        ),
      ),
      _ToolItem(
        icon: Icons.assignment_rounded,
        title: GochanoLanguage.text('Past Papers', 'বিগত প্রশ্ন'),
        subtitle: GochanoLanguage.text('Exam trends & past questions', 'বোর্ড ও পরীক্ষার প্রশ্ন বিশ্লেষণ'),
        accent: const Color(0xFFD97706),
        gradient: AppGradients.toolPastPapers,
        categoryTag: 'Past Papers',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const PastPaperScreen()),
        ),
      ),
      _ToolItem(
        icon: Icons.quiz_rounded,
        title: GochanoLanguage.text('Mock Tests', 'মক টেস্ট'),
        subtitle: GochanoLanguage.text('Simulator & score tracking', 'পরীক্ষা প্রস্তুতি ও স্কোর যাচাই'),
        accent: const Color(0xFFE11D48),
        gradient: AppGradients.toolMockTests,
        categoryTag: 'Practice',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const ExamHubScreen()),
        ),
      ),
      _ToolItem(
        icon: Icons.library_books_rounded,
        title: GochanoLanguage.text('Study Materials', 'পড়ার উপকরণ'),
        subtitle: GochanoLanguage.text('PDFs, slides & document library', 'পিডিএফ, লেকচার স্লাইড ও বই'),
        accent: const Color(0xFF059669),
        gradient: AppGradients.toolMaterials,
        categoryTag: 'Materials',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const MaterialsScreen()),
        ),
      ),
      _ToolItem(
        icon: Icons.psychology_rounded,
        title: GochanoLanguage.text('Question Bank', 'প্রশ্ন ব্যাংক'),
        subtitle: GochanoLanguage.text('AI quiz generator from topics', 'বিষয়ভিত্তিক কুইজ ও প্রশ্ন তৈরি'),
        accent: const Color(0xFF4F46E5),
        gradient: AppGradients.toolQuestionBank,
        categoryTag: 'Practice',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const QuizGeneratorScreen()),
        ),
      ),
      _ToolItem(
        icon: Icons.bookmark_rounded,
        title: GochanoLanguage.text('Saved Items', 'সংরক্ষিত আইটেম'),
        subtitle: GochanoLanguage.text('Quick access to starred files', 'পছন্দের সংরক্ষিত উপকরণ'),
        accent: const Color(0xFFCA8A04),
        gradient: AppGradients.toolBookmarks,
        categoryTag: 'Saved',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const SavedMaterialsScreen()),
        ),
      ),
      _ToolItem(
        icon: Icons.folder_shared_rounded,
        title: GochanoLanguage.text('Shared Box', 'শেয়ার্ড বক্স'),
        subtitle: GochanoLanguage.text('Peer batch notes & shared files', 'সহপাঠীদের সাথে শেয়ার করা ফাইল'),
        accent: const Color(0xFF0D9488),
        gradient: AppGradients.toolDownloads,
        categoryTag: 'Materials',
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const SharedBoxScreen()),
        ),
      ),
    ];
  }
}

class _ToolItem {
  const _ToolItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.gradient,
    required this.categoryTag,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Gradient gradient;
  final String categoryTag;
  final VoidCallback onTap;

  bool matchesCategory(String selected, List<String> allCats) {
    if (selected == allCats[0]) return true; // All
    if (categoryTag == 'Notes' && selected == allCats[1]) return true;
    if (categoryTag == 'Flashcards' && selected == allCats[2]) return true;
    if (categoryTag == 'Past Papers' && selected == allCats[3]) return true;
    if (categoryTag == 'Materials' && selected == allCats[4]) return true;
    if (categoryTag == 'Practice' && selected == allCats[5]) return true;
    if (categoryTag == 'Saved' && selected == allCats[6]) return true;
    return false;
  }
}

// ---------------------------------------------------------------------------
// Exam Rescue discovery tile
// ---------------------------------------------------------------------------

/// Discovery entry point for the active Exam Rescue plan.
///
/// Shows the nearest active session (days remaining) and jumps to the Plan
/// tab; falls back to a generic prompt when no session is active.
class ExamRescueTile extends StatelessWidget {
  const ExamRescueTile({
    super.key,
    this.onOpenPlan,
    this.examRescueSessionService,
  });

  final VoidCallback? onOpenPlan;
  final ExamRescueSessionService? examRescueSessionService;

  String _subtitle(ExamRescueSession? session, DateTime now) {
    if (session == null) {
      return GochanoLanguage.text(
        'Exam close? Build a quick rescue plan.',
        'পরীক্ষা কাছে? দ্রুত একটি রেসকিউ প্ল্যান বানান।',
      );
    }
    final days = session.localDaysRemaining(now);
    if (days <= 0) {
      return GochanoLanguage.text(
        'Exam today · View plan',
        'পরীক্ষা আজ · প্ল্যান দেখুন',
      );
    }
    if (days == 1) {
      return GochanoLanguage.text(
        'Exam in 1 day · View plan',
        'আগামীকাল পরীক্ষা · প্ল্যান দেখুন',
      );
    }
    final banglaDays = GochanoLanguage.formatNumber(days);
    return GochanoLanguage.text(
      'Exam in $days days · View plan',
      '$banglaDays দিন পরে পরীক্ষা · প্ল্যান দেখুন',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service =
        examRescueSessionService ?? ExamRescueSessionService.instance;

    return StreamBuilder<ExamRescueSession?>(
      stream: service.streamNearestActiveSession(),
      builder: (context, snapshot) {
        final session = snapshot.data;
        return AppCard(
          child: InkWell(
            onTap: onOpenPlan,
            borderRadius: GochanoRadius.mdAll,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    size: 24,
                    color: colors.brand,
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        GochanoLanguage.text('Exam Rescue', 'এক্সাম রেসকিউ'),
                        style: context.type.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(session, service.now),
                        style: context.type.caption.copyWith(
                          color: session != null
                              ? colors.brand
                              : colors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Access (Expandable Quick Shortcuts Panel)
// ---------------------------------------------------------------------------

class _QuickAccess extends StatefulWidget {
  const _QuickAccess();

  @override
  State<_QuickAccess> createState() => _QuickAccessState();
}

class _QuickAccessState extends State<_QuickAccess> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    GochanoLanguage.current.addListener(_onLanguageChange);
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageChange);
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final primaryItems = <_QuickAccessItem>[
      _QuickAccessItem(
        icon: Icons.auto_awesome_rounded,
        label: GochanoLanguage.text('AI Assistant', 'এআই সহকারী'),
        accent: colors.ai,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const AiAssistantScreen())),
      ),
      _QuickAccessItem(
        icon: Icons.edit_note_rounded,
        label: GochanoLanguage.text('Notes', 'নোট'),
        accent: colors.brand,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const NotesScreen())),
      ),
      _QuickAccessItem(
        icon: Icons.assignment_rounded,
        label: GochanoLanguage.text('Assignment AI', 'এসাইনমেন্ট এআই'),
        accent: colors.ai,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const AssignmentAssistantScreen()),
        ),
      ),
      _QuickAccessItem(
        icon: Icons.insights_rounded,
        label: GochanoLanguage.text('Insights', 'ইনসাইটস'),
        accent: colors.study,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const LearningInsightsScreen())),
      ),
    ];

    final secondaryItems = <_QuickAccessItem>[
      _QuickAccessItem(
        icon: Icons.picture_as_pdf_rounded,
        label: GochanoLanguage.text('PDFs', 'পিডিএফ'),
        accent: colors.brand,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => const MaterialsScreen(mimeFilter: 'application/pdf'),
          ),
        ),
      ),
      _QuickAccessItem(
        icon: Icons.description_rounded,
        label: GochanoLanguage.text('Docs', 'ডকুমেন্ট'),
        accent: colors.brand,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => const MaterialsScreen(documentFilter: true),
          ),
        ),
      ),
      _QuickAccessItem(
        icon: Icons.photo_library_rounded,
        label: GochanoLanguage.text('Saved Images', 'সংরক্ষিত ছবি'),
        accent: colors.commute,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => const MaterialsScreen(mimeFilter: 'image/'),
          ),
        ),
      ),
      _QuickAccessItem(
        icon: Icons.psychology_rounded,
        label: GochanoLanguage.text('Smart Plan', 'স্মার্ট প্ল্যান'),
        accent: colors.ai,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const SmartPlannerScreen())),
      ),
      _QuickAccessItem(
        icon: Icons.school_rounded,
        label: GochanoLanguage.text('Semester', 'সেমিস্টার'),
        accent: colors.expense,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const SemesterListScreen())),
      ),
      _QuickAccessItem(
        icon: Icons.folder_shared_rounded,
        label: GochanoLanguage.text('Shared Box', 'শেয়ার্ড বক্স'),
        accent: colors.community,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const SharedBoxScreen())),
      ),
      _QuickAccessItem(
        icon: Icons.fact_check_rounded,
        label: GochanoLanguage.text('Exam Prep', 'পরীক্ষা প্রস্তুতি'),
        accent: colors.study,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const ExamHubScreen())),
      ),
    ];

    return AppSectionContainer(
      title: GochanoLanguage.text('Quick Shortcuts', 'শর্টকাট টুলস'),
      icon: Icons.touch_app_rounded,
      iconColor: colors.ai,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: primaryItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth < 360 ? 3 : 4, // crossAxisCount: 4
                mainAxisExtent: 84,
                crossAxisSpacing: GochanoSpacing.xs,
                mainAxisSpacing: GochanoSpacing.xs,
              ),
              itemBuilder: (context, i) => _QuickAccessCell(
                icon: primaryItems[i].icon,
                label: primaryItems[i].label,
                accent: primaryItems[i].accent,
                onTap: primaryItems[i].onTap,
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            child: _expanded
                ? Column(
                    children: [
                      const SizedBox(height: GochanoSpacing.xs),
                      LayoutBuilder(
                        builder: (context, constraints) => GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: secondaryItems.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: constraints.maxWidth < 360 ? 3 : 4, // crossAxisCount: 4
                            mainAxisExtent: 84,
                            crossAxisSpacing: GochanoSpacing.xs,
                            mainAxisSpacing: GochanoSpacing.xs,
                          ),
                          itemBuilder: (context, i) => _QuickAccessCell(
                            icon: secondaryItems[i].icon,
                            label: secondaryItems[i].label,
                            accent: secondaryItems[i].accent,
                            onTap: secondaryItems[i].onTap,
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            onVerticalDragEnd: (details) {
              final vy = details.primaryVelocity ?? 0;
              if (vy > 100 && !_expanded) {
                setState(() => _expanded = true);
              } else if (vy < -100 && _expanded) {
                setState(() => _expanded = false);
              }
            },
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null) {
                if (details.primaryDelta! > 8 && !_expanded) {
                  setState(() => _expanded = true);
                } else if (details.primaryDelta! < -8 && _expanded) {
                  setState(() => _expanded = false);
                }
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: GochanoSpacing.xs,
                  horizontal: GochanoSpacing.md,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded
                          ? GochanoLanguage.text('See less', 'কম দেখুন')
                          : GochanoLanguage.text('See more', 'আরও দেখুন'),
                      style: context.type.caption.copyWith(
                        color: colors.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.xxs),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: colors.brand,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessItem {
  const _QuickAccessItem({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
}

class _QuickAccessCell extends StatelessWidget {
  const _QuickAccessCell({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: GochanoSpacing.xxs,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: accent),
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.type.caption.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent materials section
// ---------------------------------------------------------------------------

class _RecentMaterials extends StatelessWidget {
  const _RecentMaterials({
    this.searchQuery = '',
    this.mockRecentMaterials,
  });

  final String searchQuery;
  final List<Map<String, dynamic>>? mockRecentMaterials;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (mockRecentMaterials != null) {
      return _buildMaterialsList(context, mockRecentMaterials!, colors);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('materials', limit: 30),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return AppSectionContainer(
            title: GochanoLanguage.text('Recently Opened', 'সাম্প্রতিক খোলা হয়েছে'),
            icon: Icons.history_rounded,
            iconColor: colors.study,
            child: const Column(
              children: [
                AppSkeleton(height: 48, borderRadius: 12),
                SizedBox(height: 8),
                AppSkeleton(height: 48, borderRadius: 12),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return AppSectionContainer(
            title: GochanoLanguage.text('Recently Opened', 'সাম্প্রতিক খোলা হয়েছে'),
            icon: Icons.history_rounded,
            iconColor: colors.study,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: colors.error, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        "Couldn't load recent items.",
                        'সাম্প্রতিক উপকরণ লোড করা যায়নি।',
                      ),
                      style: context.type.bodySecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        var docsData = <Map<String, dynamic>>[];
        for (final doc in snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          final data = Map<String, dynamic>.from(doc.data());
          data['__docId'] = doc.id;
          docsData.add(data);
        }

        docsData.sort((a, b) {
          final at = a['createdAt'];
          final bt = b['createdAt'];
          if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
          return 0;
        });

        return _buildMaterialsList(context, docsData, colors);
      },
    );
  }

  Widget _buildMaterialsList(
    BuildContext context,
    List<Map<String, dynamic>> rawDocs,
    dynamic colors,
  ) {
    var docs = List<Map<String, dynamic>>.from(rawDocs);

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      docs = docs.where((d) {
        final title = _materialTitle(d).toLowerCase();
        final subject = (d['subject'] ?? '').toString().toLowerCase();
        return title.contains(q) || subject.contains(q);
      }).toList();
    }

    if (docs.isEmpty) {
      return AppSectionContainer(
        title: GochanoLanguage.text('Recently Opened', 'সাম্প্রতিক খোলা হয়েছে'),
        icon: Icons.history_rounded,
        iconColor: colors.study,
        actionLabel: GochanoLanguage.text('All', 'সব'),
        onAction: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const MaterialsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Column(
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 36,
                color: colors.textTertiary,
              ),
              const SizedBox(height: 8),
              Text(
                GochanoLanguage.text(
                  'No recent study items yet.',
                  'এখনো কোনো সাম্প্রতিক উপকরণ নেই।',
                ),
                style: context.type.body.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                GochanoLanguage.text(
                  'Open notes or materials and they’ll appear here.',
                  'নোট বা উপকরণ ওপেন করলে তা এখানে প্রদর্শিত হবে।',
                ),
                style: context.type.caption.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return AppSectionContainer(
      title: GochanoLanguage.text('Recently Opened', 'সাম্প্রতিক খোলা হয়েছে'),
      icon: Icons.history_rounded,
      iconColor: colors.study,
      actionLabel: GochanoLanguage.text('See All →', 'সব দেখুন →'),
      onAction: () => Navigator.of(context).push(
        GochanoRoute.to(builder: (_) => const MaterialsScreen()),
      ),
      child: Column(
        children: [
          for (final doc in docs.take(4))
            AppRecentWorkspaceItem(
              title: _materialTitle(doc),
              subtitle: doc['subject']?.toString(),
              metadata: _fileSize(doc['sizeBytes']),
              icon: _fileIcon(
                doc['fileName']?.toString(),
                doc['mimeType']?.toString(),
              ),
              accent: colors.study,
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(
                  builder: (_) => MaterialReaderScreen(
                    materialId: (doc['__docId'] ?? doc['id'] ?? '').toString(),
                    title: _materialTitle(doc),
                    mimeType: doc['mimeType']?.toString() ?? '',
                    fileName: doc['fileName']?.toString() ?? '',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData _fileIcon(String? fileName, String? mimeType) {
  final name = (fileName ?? '').toLowerCase();
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.contains('pdf') || name.endsWith('.pdf')) {
    return Icons.picture_as_pdf_rounded;
  }
  if (mime.contains('image') || name.endsWith('.png') || name.endsWith('.jpg')) {
    return Icons.image_rounded;
  }
  if (name.endsWith('.doc') || name.endsWith('.docx')) {
    return Icons.article_rounded;
  }
  return Icons.description_rounded;
}

String _materialTitle(Map<String, dynamic> data) {
  final title = data['title']?.toString().trim() ?? '';
  if (title.isNotEmpty) return title;
  return data['fileName']?.toString() ?? '';
}

String _fileSize(Object? sizeBytes) {
  final bytes = (sizeBytes as num?)?.toInt() ?? 0;
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
