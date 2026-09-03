// Shared Box — Community Group Resources only.
//
// Shows resources shared across the user's study groups, grouped by group.
// Does NOT open the full Community screen (no chat, members, overview).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../study/presentation/materials/material_reader_screen.dart';
import '../../study/presentation/notes/note_editor_screen.dart';

class SharedBoxScreen extends StatelessWidget {
  const SharedBoxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Shared Box', 'শেয়ার্ড বক্স'),
        subtitle: GochanoLanguage.text(
          'Resources shared in your study groups',
          'আপনার স্টাডি গ্রুপে শেয়ার করা উপকরণ',
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.myGroups(),
        builder: (context, groupsSnapshot) {
          if (groupsSnapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text(
                'Loading shared resources…',
                'শেয়ার করা উপকরণ লোড হচ্ছে…',
              ),
            );
          }
          if (groupsSnapshot.hasError) {
            return ErrorState(
              message: friendlyErrorMessage(groupsSnapshot.error),
            );
          }

          final groups = [...?groupsSnapshot.data?.docs]
            ..sort((a, b) => (a.data()['name']?.toString() ?? '')
                .compareTo(b.data()['name']?.toString() ?? ''));

          if (groups.isEmpty) {
            return EmptyState(
              illustration: GochanoArt.featureGroups,
              title: GochanoLanguage.text(
                'No study groups yet',
                'এখনো কোনো স্টাডি গ্রুপ নেই',
              ),
              message: GochanoLanguage.text(
                'Join or create a study group to share resources with '
                'classmates.',
                'সহপাঠীদের সাথে উপকরণ শেয়ার করতে একটি স্টাডি গ্রুপে যোগ '
                'দিন বা তৈরি করুন।',
              ),
              actionLabel: GochanoLanguage.text(
                'Go to Community',
                'কমিউনিটিতে যান',
              ),
              onAction: () => Navigator.of(context).pop(),
            );
          }

          return ListView.builder(
            padding: GochanoSpacing.scrollBody,
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              final groupName = group.data()['name']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
                child: _GroupResourcesSection(
                  groupId: group.id,
                  groupName: groupName,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-group resources section — reuses existing Firestore queries
// ---------------------------------------------------------------------------

class _GroupResourcesSection extends StatelessWidget {
  const _GroupResourcesSection({
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Group header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
          child: Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureGroups,
                accent: colors.community,
                plateSize: 36,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Text(
                  groupName,
                  style: context.type.sectionHeading.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Materials
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.groupMaterials(groupId),
          builder: (context, materialsSnapshot) {
            if (materialsSnapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            final materials = [...?materialsSnapshot.data?.docs]
              ..sort((a, b) {
                final at = a.data()['createdAt'];
                final bt = b.data()['createdAt'];
                if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
                return 0;
              });

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.groupNotes(groupId),
              builder: (context, notesSnapshot) {
                final notes = [...?notesSnapshot.data?.docs];
                final hasResources =
                    materials.isNotEmpty || notes.isNotEmpty;

                if (!hasResources) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
                    child: AppCard(
                      child: Text(
                        GochanoLanguage.text(
                          'No shared resources yet.',
                          'এখনো কোনো শেয়ার করা উপকরণ নেই।',
                        ),
                        style: context.type.bodySecondary,
                      ),
                    ),
                  );
                }

                return CardGroup(
                  children: [
                    for (final doc in materials)
                      _ResourceRow(doc: doc),
                    for (final doc in notes)
                      _NoteRow(doc: doc),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Resource row — reuses MaterialReaderScreen (same as _ResourcesTab)
// ---------------------------------------------------------------------------

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString()
        : data['fileName']?.toString() ?? '';
    final fileName = data['fileName']?.toString() ?? '';
    final mimeType = data['mimeType']?.toString() ?? '';
    final ownerName = data['ownerName']?.toString();

    final sizeBytes = (data['sizeBytes'] as num?)?.toInt() ?? 0;
    final meta = <String>[];
    if (sizeBytes > 0) {
      if (sizeBytes < 1024) {
        meta.add('$sizeBytes B');
      } else if (sizeBytes < 1024 * 1024) {
        meta.add('${(sizeBytes / 1024).toStringAsFixed(0)} KB');
      } else {
        meta.add('${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB');
      }
    }

    return GochanoListRow(
      illustration: GochanoArt.fileIdFor(fileName: fileName, mimeType: mimeType),
      accent: context.colors.community,
      title: title,
      subtitle: ownerName,
      metadata: meta,
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(
          builder: (_) => MaterialReaderScreen(
            materialId: doc.id,
            title: title,
            mimeType: mimeType,
            fileName: fileName,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note row — reuses NoteEditorScreen (same as _GroupNotes)
// ---------------------------------------------------------------------------

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = data['title']?.toString() ?? '';
    final ownerName = data['ownerName']?.toString();

    return GochanoListRow(
      illustration: GochanoArt.fileNote,
      accent: context.colors.community,
      title: title,
      subtitle: ownerName,
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(
          builder: (_) => NoteEditorScreen(
            noteId: doc.id,
            initialData: data,
          ),
        ),
      ),
    );
  }
}
