// Study Workspace — Final IA Refinement Pass.
//
// Pure study tool hub answering: "Where are my study tools and study resources?"
// Implements the Final 6+2 model:
//   Primary: 6 Study Tools in 2×3 grid
//   Secondary: 2 Resource Vaults (Saved Items, Shared Box)
//   Recent: compact horizontal carousel
//
// Header: showSearch=false (body search is the single search entry point)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../community/presentation/shared_box_screen.dart';
import '../../../search/presentation/universal_search_screen.dart';
import '../content/flashcard_screen.dart';
import '../exam_ecosystem/exam_hub_screen.dart';
import '../exam_ecosystem/past_paper_screen.dart';
import '../materials/material_reader_screen.dart';
import '../materials/materials_screen.dart';
import '../materials/saved_materials_screen.dart';
import '../notes/notes_screen.dart';
import '../ai/quiz_generator_screen.dart';

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key, this.mockRecentMaterials});

  /// Injected materials for testing — bypasses Firestore stream.
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

  bool get _isSavedFilter {
    final cats = _filterCategories;
    return _selectedCategory == cats[6] || _selectedCategory == 'Saved';
  }

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
        backgroundColor:
            isDark ? colors.background : const Color(0xFFF7F8FA),
        body: Stack(
          children: [
            // ---------------------------------------------------------------
            // Colorful top gradient wash (light mode only)
            // ---------------------------------------------------------------
            if (!isDark)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 280,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFEEF2FF), Color(0xFFF7F8FA)],
                      stops: [0.0, 1.0],
                    ),
                  ),
                ),
              ),

            // ---------------------------------------------------------------
            // Main scrollable content with entrance animation
            // ---------------------------------------------------------------
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                      // -----------------------------------------------------------
                      // PINNED CONTEXTUAL STUDY HEADER — search HIDDEN (body has search)
                      // -----------------------------------------------------------
                      const AppStudyHeader(showSearch: false),

                      // -----------------------------------------------------------
                      // SCROLLABLE WORKSPACE CONTENT
                      // -----------------------------------------------------------
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => setState(() {}),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildIntro(context),
                                      const SizedBox(height: GochanoSpacing.sm),
                                      AppWorkspaceSearchField(
                                        controller: _searchController,
                                        onChanged: (q) => setState(
                                          () => _searchQuery = q.trim(),
                                        ),
                                        onSubmitted: (q) {
                                          if (q.trim().isNotEmpty) {
                                            Navigator.of(context).push(
                                              GochanoRoute.to(
                                                builder: (_) =>
                                                    UniversalSearchScreen(
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
                                        selectedCategory:
                                            _selectedCategory == 'All'
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

                              // Study Tools Grid — hidden when Saved filter is active
                              if (!_isSavedFilter)
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: GochanoSpacing.md,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: _buildStudyToolsSection(context),
                                  ),
                                ),

                              // Resource Vaults
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: GochanoSpacing.md,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: GochanoSpacing.sm,
                                    ),
                                    child: _buildResourceVaults(context),
                                  ),
                                ),
                              ),

                              // Recently Opened — compact horizontal carousel
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: GochanoSpacing.md,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: GochanoSpacing.sm,
                                    ),
                                    child: widget.mockRecentMaterials != null
                                        ? _RecentMaterialsCarousel(
                                            searchQuery: _searchQuery,
                                            mockRecentMaterials:
                                                widget.mockRecentMaterials,
                                          )
                                        : _RecentMaterialsCarousel(
                                            searchQuery: _searchQuery,
                                          ),
                                  ),
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
            ],
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
    final allTools = _getPrimaryToolsList(context);

    final filteredTools = allTools.where((tool) {
      if (_selectedCategory != 'All') {
        if (!tool.matchesCategory(_selectedCategory, _filterCategories)) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matches =
            tool.title.toLowerCase().contains(q) ||
            tool.subtitle.toLowerCase().contains(q);
        if (!matches) return false;
      }
      return true;
    }).toList();

    final transitionDuration = context.motionDuration(AppMotion.selectionTransition);
    final motionCurve = context.motionCurve(AppMotion.easeInOut);

    return AppSectionContainer(
      title: GochanoLanguage.text('Study Tools', 'স্টাডি টুলস'),
      icon: Icons.grid_view_rounded,
      iconColor: colors.brand,
      child: AnimatedSwitcher(
        duration: transitionDuration,
        switchInCurve: motionCurve,
        switchOutCurve: motionCurve,
        child: filteredTools.isEmpty
            ? Padding(
                key: const ValueKey('tools_empty'),
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
                key: ValueKey('tools_grid_${_selectedCategory}_${_searchQuery.isNotEmpty}'),
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                  final isNarrow = constraints.maxWidth < 340;
                  final double baseExtent = isNarrow ? 128.0 : 124.0;
                  final double dynamicExtent = textScale > 1.0
                      ? baseExtent + (textScale - 1.0) * 44.0
                      : baseExtent;
                  final int crossAxisCount = constraints.maxWidth >= 600 ? 3 : 2;

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
      ),
    );
  }

  Widget _buildResourceVaults(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return AppSectionContainer(
      title: GochanoLanguage.text('Resource Vaults', 'রিসোর্স ভল্ট'),
      icon: Icons.folder_special_rounded,
      iconColor: colors.study,
      child: Row(
        children: [
          Expanded(
            child: _VaultButton(
              icon: Icons.bookmark_rounded,
              label: GochanoLanguage.text('Saved Items', 'সংরক্ষিত'),
              accent: const Color(0xFFCA8A04),
              isDark: isDark,
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(builder: (_) => const SavedMaterialsScreen()),
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: _VaultButton(
              icon: Icons.folder_shared_rounded,
              label: GochanoLanguage.text('Shared Box', 'শেয়ার্ড বক্স'),
              accent: const Color(0xFF0D9488),
              isDark: isDark,
              onTap: () => Navigator.of(
                context,
              ).push(GochanoRoute.to(builder: (_) => const SharedBoxScreen())),
            ),
          ),
        ],
      ),
    );
  }

  List<_ToolItem> _getPrimaryToolsList(BuildContext context) {
    return [
      _ToolItem(
        icon: Icons.description_rounded,
        title: GochanoLanguage.text('My Notes', 'আমার নোট'),
        subtitle: GochanoLanguage.text(
          'Create & organize lecture notes',
          'লেকচার নোট তৈরি ও সাজান',
        ),
        accent: const Color(0xFF2563EB),
        gradient: AppGradients.toolNotes,
        categoryTag: 'Notes',
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const NotesScreen())),
      ),
      _ToolItem(
        icon: Icons.style_rounded,
        title: GochanoLanguage.text('Flashcards', 'ফ্ল্যাশকার্ড'),
        subtitle: GochanoLanguage.text(
          'Active recall & quick revision',
          'দ্রুত রিভিশন ও মনে রাখার জন্য',
        ),
        accent: const Color(0xFF8B5CF6),
        gradient: AppGradients.toolFlashcards,
        categoryTag: 'Flashcards',
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const FlashcardScreen())),
      ),
      _ToolItem(
        icon: Icons.assignment_rounded,
        title: GochanoLanguage.text('Past Papers', 'বিগত প্রশ্ন'),
        subtitle: GochanoLanguage.text(
          'Exam trends & past questions',
          'বোর্ড ও পরীক্ষার প্রশ্ন বিশ্লেষণ',
        ),
        accent: AppGradients.emeraldDark,
        gradient: AppGradients.toolPastPapers,
        categoryTag: 'Past Papers',
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const PastPaperScreen())),
      ),
      _ToolItem(
        icon: Icons.quiz_rounded,
        title: GochanoLanguage.text('Mock Tests', 'মক টেস্ট'),
        subtitle: GochanoLanguage.text(
          'Simulator & score tracking',
          'পরীক্ষা প্রস্তুতি ও স্কোর যাচাই',
        ),
        accent: const Color(0xFFE11D48),
        gradient: AppGradients.toolMockTests,
        categoryTag: 'Practice',
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const ExamHubScreen())),
      ),
      _ToolItem(
        icon: Icons.library_books_rounded,
        title: GochanoLanguage.text('Study Materials', 'পড়ার উপকরণ'),
        subtitle: GochanoLanguage.text(
          'PDFs, slides & document library',
          'পিডিএফ, লেকচার স্লাইড ও বই',
        ),
        accent: AppGradients.skyAccent,
        gradient: AppGradients.toolMaterials,
        categoryTag: 'Materials',
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const MaterialsScreen())),
      ),
      _ToolItem(
        icon: Icons.psychology_rounded,
        title: GochanoLanguage.text('Question Bank', 'প্রশ্ন ব্যাংক'),
        subtitle: GochanoLanguage.text(
          'AI quiz generator from topics',
          'বিষয়ভিত্তিক কুইজ ও প্রশ্ন তৈরি',
        ),
        accent: const Color(0xFF4F46E5),
        gradient: AppGradients.toolQuestionBank,
        categoryTag: 'Practice',
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const QuizGeneratorScreen())),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Tool item data class
// ---------------------------------------------------------------------------

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
    return false;
  }
}

// ---------------------------------------------------------------------------
// Resource Vault compact button
// ---------------------------------------------------------------------------

class _VaultButton extends StatelessWidget {
  const _VaultButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark
                ? accent.withValues(alpha: 0.12)
                : accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? accent.withValues(alpha: 0.25)
                  : accent.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: context.type.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.0,
                        color: isDark ? Colors.white70 : colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact horizontal Recently Opened carousel
// ---------------------------------------------------------------------------

class _RecentMaterialsCarousel extends StatelessWidget {
  const _RecentMaterialsCarousel({
    this.searchQuery = '',
    this.mockRecentMaterials,
  });

  final String searchQuery;
  final List<Map<String, dynamic>>? mockRecentMaterials;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (mockRecentMaterials != null) {
      return _buildCarousel(context, mockRecentMaterials!, colors);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('materials', limit: 5),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoadingSkeleton(context, colors);
        }

        if (snapshot.hasError) {
          return _buildError(context, colors);
        }

        var docsData = <Map<String, dynamic>>[];
        for (final doc
            in snapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
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

        return _buildCarousel(context, docsData, colors);
      },
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context, dynamic colors) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double skeletonHeight = textScale > 1.0
        ? 116.0 + (textScale - 1.0) * 36.0
        : 116.0;

    return AppSectionContainer(
      title: GochanoLanguage.text('Recently Opened', 'সাম্প্রতিক খোলা হয়েছে'),
      icon: Icons.history_rounded,
      iconColor: colors.study,
      child: SizedBox(
        height: skeletonHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: 3,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) =>
              AppSkeleton(width: 140, height: skeletonHeight, borderRadius: 12),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, dynamic colors) {
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
            TextButton(
              onPressed: () {},
              child: Text(GochanoLanguage.text('Retry', 'আবার চেষ্টা')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarousel(
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
        title: GochanoLanguage.text(
          'Recently Opened',
          'সাম্প্রতিক খোলা হয়েছে',
        ),
        icon: Icons.history_rounded,
        iconColor: colors.study,
        actionLabel: GochanoLanguage.text('All', 'সব'),
        onAction: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const MaterialsScreen())),
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
                  'Open notes or materials and they\u2019ll appear here.',
                  'নোট বা উপকরণ ওপেন করলে তা এখানে প্রদর্শিত হবে।',
                ),
                style: context.type.caption.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final preview = docs.take(5).toList();

    return AppSectionContainer(
      title: GochanoLanguage.text('Recently Opened', 'সাম্প্রতিক খোলা হয়েছে'),
      icon: Icons.history_rounded,
      iconColor: colors.study,
      actionLabel: GochanoLanguage.text('See All \u2192', 'সব দেখুন \u2192'),
      onAction: () => Navigator.of(
        context,
      ).push(GochanoRoute.to(builder: (_) => const MaterialsScreen())),
      child: Builder(
        builder: (context) {
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final double carouselHeight = textScale > 1.0
              ? 116.0 + (textScale - 1.0) * 36.0
              : 116.0;

          return SizedBox(
            height: carouselHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: preview.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final doc = preview[index];
                final icon = _fileIcon(
                  doc['fileName']?.toString(),
                  doc['mimeType']?.toString(),
                );
                return _RecentCarouselCard(
                  title: _materialTitle(doc),
                  subtitle: doc['subject']?.toString(),
                  icon: icon,
                  accent: colors.study,
                  isDark: context.isDark,
                  onTap: () => Navigator.of(context).push(
                    GochanoRoute.to(
                      builder: (_) => MaterialReaderScreen(
                        materialId: (doc['__docId'] ?? doc['id'] ?? '')
                            .toString(),
                        title: _materialTitle(doc),
                        mimeType: doc['mimeType']?.toString() ?? '',
                        fileName: doc['fileName']?.toString() ?? '',
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact horizontal card for recent carousel
// ---------------------------------------------------------------------------

class _RecentCarouselCard extends StatelessWidget {
  const _RecentCarouselCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '$title${subtitle != null ? ", $subtitle" : ""}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            width: 140,
            decoration: BoxDecoration(
              color: isDark ? colors.surface : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? colors.border.withValues(alpha: 0.3)
                    : const Color(0xFFE2E8F0),
                width: 1,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark
                          ? accent.withValues(alpha: 0.2)
                          : accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: context.type.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                      color: colors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: context.type.caption.copyWith(
                        color: colors.textTertiary,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File utilities
// ---------------------------------------------------------------------------

IconData _fileIcon(String? fileName, String? mimeType) {
  final name = (fileName ?? '').toLowerCase();
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.contains('pdf') || name.endsWith('.pdf')) {
    return Icons.picture_as_pdf_rounded;
  }
  if (mime.contains('image') ||
      name.endsWith('.png') ||
      name.endsWith('.jpg')) {
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
