// Saved materials (spec §32 — "saved state").
//
// `POST /api/materials/{id}/save` writes a lightweight bookmark into
// `users/{uid}/saved_materials/{materialId}`. That bookmark carries a title
// snapshot, so this list renders immediately from the bookmark itself and
// only reaches for the full material document when opening one.
//
// A bookmark can outlive the material it points at — the owner may have
// deleted it. That case is shown as an unavailable row the student can
// clear, rather than as a row that errors when tapped.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'material_reader_screen.dart';

class SavedMaterialsScreen extends StatelessWidget {
  const SavedMaterialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Saved', 'সংরক্ষিত'),
        subtitle: GochanoLanguage.text(
          'Materials you bookmarked',
          'আপনার বুকমার্ক করা উপকরণ',
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.db
            .collection('users')
            .doc(FirestoreService.uid)
            .collection('saved_materials')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text(
                'Loading saved materials…',
                'সংরক্ষিত উপকরণ লোড হচ্ছে…',
              ),
            );
          }
          if (snapshot.hasError) {
            return ErrorState(message: friendlyErrorMessage(snapshot.error));
          }

          final saved = [...?snapshot.data?.docs]
            ..sort((a, b) {
              final at = a.data()['savedAt'];
              final bt = b.data()['savedAt'];
              if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
              return 0;
            });

          if (saved.isEmpty) {
            return EmptyState(
              illustration: GochanoArt.emptyMaterials,
              title: GochanoLanguage.text(
                'Nothing saved yet',
                'এখনো কিছু সংরক্ষিত নেই',
              ),
              message: GochanoLanguage.text(
                'Open a material and use "Save to library" to keep it here.',
                'কোনো উপকরণ খুলে "লাইব্রেরিতে সংরক্ষণ" চাপলে সেটি এখানে থাকবে।',
              ),
            );
          }

          return ListView.builder(
            padding: GochanoSpacing.scrollBody,
            itemCount: saved.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: _SavedRow(bookmark: saved[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({required this.bookmark});

  final QueryDocumentSnapshot<Map<String, dynamic>> bookmark;

  @override
  Widget build(BuildContext context) {
    final data = bookmark.data();
    final materialId = data['materialId']?.toString() ?? bookmark.id;
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString()
        : data['fileName']?.toString() ?? '';
    final fileName = data['fileName']?.toString() ?? '';

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirestoreService.db.collection('materials').doc(materialId).get(),
      builder: (context, snapshot) {
        final material = snapshot.data?.data();
        final resolved = snapshot.connectionState == ConnectionState.done;
        final missing = resolved && material == null;
        final mimeType = material?['mimeType']?.toString() ?? '';

        return GochanoListRow(
          illustration: GochanoArt.fileIdFor(
            fileName: fileName,
            mimeType: mimeType,
          ),
          accent: missing
              ? context.colors.textTertiary
              : context.colors.study,
          title: title,
          subtitle: material?['subject']?.toString(),
          badge: missing
              ? GochanoBadge(
                  label: GochanoLanguage.text('Unavailable', 'অনুপলব্ধ'),
                  tone: GochanoBadgeTone.warning,
                  icon: Icons.link_off_rounded,
                )
              : null,
          onTap: missing
              ? null
              : () => Navigator.of(context).push(
                    GochanoRoute.to(
                      builder: (_) => MaterialReaderScreen(
                        materialId: materialId,
                        title: title,
                        mimeType: mimeType,
                        fileName: fileName,
                      ),
                    ),
                  ),
          menuItems: [
            GochanoMenuAction(
              label: GochanoLanguage.text('Remove from saved', 'সংরক্ষিত থেকে সরান'),
              icon: Icons.bookmark_remove_outlined,
              destructive: true,
              onSelected: () async {
                try {
                  await bookmark.reference.delete();
                } catch (error) {
                  if (context.mounted) {
                    showGochanoMessage(
                      context,
                      friendlyErrorMessage(error),
                      isError: true,
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
}
