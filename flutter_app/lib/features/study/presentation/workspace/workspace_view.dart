// Study workspace — shortcut-first screen (spec §29).
//
// Quick Access at the top provides fast entry to Notes, PDFs, Saved Images,
// Semester, and Shared Box. Recent Materials sits below it.
//
// Semester and Notes full sections have been extracted to their own screens
// (SemesterListScreen, NotesScreen) to keep Workspace as a launcher.

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
import '../../../community/presentation/shared_box_screen.dart';
import '../ai/ai_assistant_screen.dart';
import '../materials/material_reader_screen.dart';
import '../materials/materials_screen.dart';
import '../materials/saved_materials_screen.dart';
import '../notes/notes_screen.dart';
import 'semester_list_screen.dart';

class WorkspaceView extends StatelessWidget {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: const [
        _QuickAccess(),
        _RecentMaterials(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quick access
// ---------------------------------------------------------------------------

const _kCollapsedCount = 3;

class _QuickAccess extends StatefulWidget {
  const _QuickAccess();

  @override
  State<_QuickAccess> createState() => _QuickAccessState();
}

class _QuickAccessState extends State<_QuickAccess> {
  bool _expanded = false;

  List<_QuickAccessTile> _tiles(BuildContext context) {
    final colors = context.colors;
    return [
      _QuickAccessTile(
        label: GochanoLanguage.text('AI Assistant', 'এআই সহকারী'),
        assetImage: 'assets/Ziku.png',
        accent: colors.ai,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
        ),
      ),
      _QuickAccessTile(
        label: GochanoLanguage.text('Notes', 'নোট'),
        illustration: GochanoArt.fileNote,
        accent: colors.study,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const NotesScreen()),
        ),
      ),
      _QuickAccessTile(
        label: GochanoLanguage.text('PDFs', 'পিডিএফ'),
        illustration: GochanoArt.filePdf,
        accent: colors.brand,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) =>
                const MaterialsScreen(mimeFilter: 'application/pdf'),
          ),
        ),
      ),
      _QuickAccessTile(
        label: GochanoLanguage.text('Saved Images', 'সংরক্ষিত ছবি'),
        illustration: GochanoArt.fileImage,
        accent: colors.ai,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => const MaterialsScreen(mimeFilter: 'image/'),
          ),
        ),
      ),
      _QuickAccessTile(
        label: GochanoLanguage.text('Semester', 'সেমিস্টার'),
        illustration: GochanoArt.featureStudy,
        accent: colors.study,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const SemesterListScreen()),
        ),
      ),
      _QuickAccessTile(
        label: GochanoLanguage.text('Shared Box', 'শেয়ার্ড বক্স'),
        illustration: GochanoArt.featureGroups,
        accent: colors.community,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const SharedBoxScreen()),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles(context);
    final hasMore = tiles.length > _kCollapsedCount;
    final visible = (_expanded || !hasMore)
        ? tiles
        : tiles.take(_kCollapsedCount).toList();

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 380 ? 4 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: visible.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 88,
                  crossAxisSpacing: GochanoSpacing.xxs,
                  mainAxisSpacing: GochanoSpacing.xs,
                ),
                itemBuilder: (context, i) => visible[i],
              );
            },
          ),
          if (hasMore)
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: GochanoSizes.iconSm,
              ),
              label: Text(
                _expanded
                    ? GochanoLanguage.text('See less', 'কম দেখুন')
                    : GochanoLanguage.text('See more', 'আরো দেখুন'),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.label,
    required this.accent,
    required this.onTap,
    this.illustration,
    this.assetImage,
  });

  final String label;
  final String? illustration;
  final String? assetImage;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: GochanoSpacing.xxs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: assetImage != null
                      ? ClipOval(
                          child: Image.asset(
                            assetImage!,
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                            semanticLabel: label,
                          ),
                        )
                      : GochanoIllustration(
                          illustration!,
                          size: 28,
                          accent: accent,
                        ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              Expanded(
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
        if (snapshot.hasError) return const SizedBox.shrink();
        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) {
            final at = a.data()['createdAt'];
            final bt = b.data()['createdAt'];
            if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
            return 0;
          });
        if (docs.isEmpty) return const SizedBox.shrink();

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
