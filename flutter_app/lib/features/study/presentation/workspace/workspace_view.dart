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
      children: const [
        _QuickAccess(),
        SizedBox(height: GochanoSpacing.sm),
        _RecentMaterials(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Access
// ---------------------------------------------------------------------------

class _QuickAccess extends StatelessWidget {
  const _QuickAccess();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: GochanoLanguage.text(
              'Quick Access',
              'দ্রুত অ্যাক্সেস',
            ),
            padding: const EdgeInsets.only(
              top: GochanoSpacing.xs,
              bottom: GochanoSpacing.xs,
            ),
          ),
          _QuickAccessTile(
            icon: Icons.auto_awesome_rounded,
            label: GochanoLanguage.text('AI Assistant', 'এআই সহকারী'),
            accent: colors.ai,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
            ),
          ),
          _QuickAccessTile(
            icon: Icons.notes_rounded,
            label: GochanoLanguage.text('Notes', 'নোট'),
            accent: colors.study,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const NotesScreen()),
            ),
          ),
          _QuickAccessTile(
            icon: Icons.picture_as_pdf_rounded,
            label: GochanoLanguage.text('PDFs', 'পিডিএফ'),
            accent: colors.error,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(
                builder: (_) => const MaterialsScreen(mimeFilter: 'application/pdf'),
              ),
            ),
          ),
          _QuickAccessTile(
            icon: Icons.photo_library_rounded,
            label: GochanoLanguage.text('Saved Images', 'সংরক্ষিত ছবি'),
            accent: colors.commute,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(
                builder: (_) => const MaterialsScreen(mimeFilter: 'image/'),
              ),
            ),
          ),
          _QuickAccessTile(
            icon: Icons.school_rounded,
            label: GochanoLanguage.text('Semester', 'সেমিস্টার'),
            accent: colors.expense,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const SemesterListScreen()),
            ),
          ),
          _QuickAccessTile(
            icon: Icons.folder_shared_rounded,
            label: GochanoLanguage.text('Shared Box', 'শেয়ার্ড বক্স'),
            accent: colors.community,
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const SharedBoxScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xxs),
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GochanoSpacing.xs,
            vertical: GochanoSpacing.xxs,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: GochanoRadius.smAll,
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.colors.textTertiary,
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
                          mimeType:
                              doc.data()['mimeType']?.toString() ?? '',
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
