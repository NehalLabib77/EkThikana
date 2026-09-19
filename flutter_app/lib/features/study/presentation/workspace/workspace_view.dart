// Study workspace — launcher for recent materials (spec §29).
//
// Quick Access grid sits at the top of the body, followed by recent materials.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../ai/ai_assistant_screen.dart';
import '../ai/assignment_assistant_screen.dart';
import '../ai/quiz_generator_screen.dart';
import '../ai/smart_planner_screen.dart';
import '../materials/material_reader_screen.dart';
import '../materials/materials_screen.dart';
import '../materials/saved_materials_screen.dart';
import '../notes/notes_screen.dart';
import 'semester_list_screen.dart';
import '../../../../features/community/presentation/shared_box_screen.dart';

class WorkspaceView extends StatelessWidget {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        const _QuickAccess(),
        const SizedBox(height: GochanoSpacing.sm),
        _RecentMaterials(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Access
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
        icon: Icons.notes_rounded,
        label: GochanoLanguage.text('Notes', 'নোট'),
        accent: colors.study,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const NotesScreen())),
      ),
      _QuickAccessItem(
        icon: Icons.picture_as_pdf_rounded,
        label: GochanoLanguage.text('PDFs', 'পিডিএফ'),
        accent: colors.error,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) =>
                const MaterialsScreen(mimeFilter: 'application/pdf'),
          ),
        ),
      ),
      _QuickAccessItem(
        icon: Icons.photo_library_rounded,
        label: GochanoLanguage.text('Saved Images', 'সংরক্ষিত ছবি'),
        accent: colors.commute,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const SavedMaterialsScreen())),
      ),
    ];

    final secondaryItems = <_QuickAccessItem>[
      _QuickAccessItem(
        icon: Icons.assignment_rounded,
        label: GochanoLanguage.text('Assignment AI', 'এসাইনমেন্ট এআই'),
        accent: colors.ai,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const AssignmentAssistantScreen())),
      ),
      _QuickAccessItem(
        icon: Icons.quiz_rounded,
        label: GochanoLanguage.text('Quiz', 'কুইজ'),
        accent: colors.study,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const QuizGeneratorScreen())),
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
        icon: Icons.description_rounded,
        label: GochanoLanguage.text('Docs', 'ডকস'),
        accent: colors.brand,
        onTap: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const MaterialsScreen())),
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
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: GochanoLanguage.text('Quick Access', 'দ্রুত অ্যাক্সেস'),
            padding: const EdgeInsets.only(
              top: GochanoSpacing.xs,
              bottom: GochanoSpacing.xs,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: primaryItems.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth < 360 ? 3 : 4,
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
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOutCubic,
            child: _expanded
                ? Column(
                    children: [
                      const SizedBox(height: GochanoSpacing.xs),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: secondaryItems.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
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
                // Drag down to expand
                setState(() => _expanded = true);
              } else if (vy < -100 && _expanded) {
                // Drag up to collapse
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
// Recent materials
// ---------------------------------------------------------------------------

class _RecentMaterials extends StatelessWidget {
  const _RecentMaterials();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('materials', limit: 30),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppCard(
            child: Column(
              children: [
                GochanoIllustration(
                  GochanoArt.emptyMaterials,
                  size: GochanoSizes.illustrationEmpty,
                  accent: colors.textTertiary,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text(
                    'Unable to load materials',
                    'উপকরণ লোড হয়নি',
                  ),
                  style: context.type.sectionHeading,
                ),
              ],
            ),
          );
        }
        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) {
            final at = a.data()['createdAt'];
            final bt = b.data()['createdAt'];
            if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
            return 0;
          });
        if (docs.isEmpty) {
          return AppCard(
            child: Column(
              children: [
                GochanoIllustration(
                  GochanoArt.emptyMaterials,
                  size: GochanoSizes.illustrationEmpty,
                  accent: colors.study,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text(
                    'No recent materials yet',
                    'এখনো কোনো উপকরণ নেই',
                  ),
                  style: context.type.sectionHeading,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  GochanoLanguage.text(
                    'Use Quick Access to add study materials.',
                    'পড়ার উপকরণ যোগ করতে Quick Access ব্যবহার করুন।',
                  ),
                  style: context.type.bodySecondary,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: GochanoLanguage.text(
                'Recent materials',
                'সাম্প্রতিক উপকরণ',
              ),
              padding: const EdgeInsets.only(
                top: GochanoSpacing.sm,
                bottom: GochanoSpacing.xs,
              ),
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      GochanoRoute.to(
                        builder: (_) => const SavedMaterialsScreen(),
                      ),
                    ),
                    child: Text(GochanoLanguage.text('Saved', 'সংরক্ষিত')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      GochanoRoute.to(builder: (_) => const MaterialsScreen()),
                    ),
                    child: Text(GochanoLanguage.text('All', 'সব')),
                  ),
                ],
              ),
            ),
            CardGroup(
              children: [
                for (final doc in docs.take(3))
                  GochanoListRow(
                    illustration: GochanoArt.fileIdFor(
                      fileName: doc.data()['fileName']?.toString(),
                      mimeType: doc.data()['mimeType']?.toString(),
                    ),
                    accent: colors.study,
                    title: _materialTitle(doc.data()),
                    subtitle: doc.data()['subject']?.toString(),
                    metadata: [_fileSize(doc.data()['sizeBytes'])],
                    onTap: () => Navigator.of(context).push(
                      GochanoRoute.to(
                        builder: (_) => MaterialReaderScreen(
                          materialId: doc.id,
                          title: _materialTitle(doc.data()),
                          mimeType: doc.data()['mimeType']?.toString() ?? '',
                          fileName: doc.data()['fileName']?.toString() ?? '',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
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
