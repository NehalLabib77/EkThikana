// Lightweight cross-module relationship chips (Phase 5).
//
// Displays optional related-note / related-material / related-task metadata
// as compact chips. Handles broken references gracefully — if the target
// document is deleted, the chip shows an unavailable state without crashing.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/gochano_colors.dart';
import '../../core/design_system/gochano_typography.dart';
import '../../core/localization/gochano_language.dart';
import '../../core/page_route.dart';
import '../../features/study/presentation/materials/material_reader_screen.dart';
import '../../features/study/presentation/notes/note_editor_screen.dart';

/// A compact chip that shows a related Note reference.
///
/// Taps open the NoteEditorScreen. If the note has been deleted, shows an
/// unavailable state that does not crash.
class RelatedNoteChip extends StatelessWidget {
  const RelatedNoteChip({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) {
    return _RelatedChip(
      collection: 'notes',
      documentId: noteId,
      icon: Icons.notes_rounded,
      labelBuilder: (data) => data['title']?.toString() ?? 'Note',
      unavailableLabel: GochanoLanguage.text(
        'Deleted note',
        'মুছে ফেলা নোট',
      ),
      onTap: (data) {
        Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => NoteEditorScreen(
              noteId: noteId,
              initialData: data,
            ),
          ),
        );
      },
    );
  }
}

/// A compact chip that shows a related Material reference.
///
/// Taps open the MaterialReaderScreen. If the material has been deleted,
/// shows an unavailable state that does not crash.
class RelatedMaterialChip extends StatelessWidget {
  const RelatedMaterialChip({super.key, required this.materialId});

  final String materialId;

  @override
  Widget build(BuildContext context) {
    return _RelatedChip(
      collection: 'materials',
      documentId: materialId,
      icon: Icons.description_rounded,
      labelBuilder: (data) => data['title']?.toString() ?? 'Material',
      unavailableLabel: GochanoLanguage.text(
        'Deleted material',
        'ম৛ে ফেলা উপকরণ',
      ),
      onTap: (data) {
        Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => MaterialReaderScreen(
              materialId: materialId,
              title: data['title']?.toString() ?? '',
              mimeType: data['mimeType']?.toString() ?? '',
              fileName: data['fileName']?.toString() ?? '',
            ),
          ),
        );
      },
    );
  }
}

/// Internal chip that streams a single Firestore document and renders
/// a compact tappable chip. Handles missing/deleted documents gracefully.
class _RelatedChip extends StatelessWidget {
  const _RelatedChip({
    required this.collection,
    required this.documentId,
    required this.icon,
    required this.labelBuilder,
    required this.unavailableLabel,
    this.onTap,
  });

  final String collection;
  final String documentId;
  final IconData icon;
  final String Function(Map<String, dynamic> data) labelBuilder;
  final String unavailableLabel;
  final ValueChanged<Map<String, dynamic>>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .doc(documentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          // Broken reference — show unavailable chip.
          return Chip(
            avatar: Icon(icon, size: 14, color: colors.textTertiary),
            label: Text(
              unavailableLabel,
              style: context.type.caption.copyWith(
                color: colors.textTertiary,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }

        final data = doc.data()!;
        final label = labelBuilder(data);

        return ActionChip(
          avatar: Icon(icon, size: 14, color: colors.study),
          label: Text(
            label,
            style: context.type.caption.copyWith(color: colors.study),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: onTap != null ? () => onTap!(data) : null,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      },
    );
  }
}
