// Text notes (spec §21, §32).
//
// Notes are the "Text Note" resource type spec §21 names, and they are a
// distinct thing from an uploaded material: written in the app, editable, and
// the one type `POST /api/ai/note` operates on directly.

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
import 'note_editor_screen.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Notes', 'নোট'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const NoteEditorScreen()),
        ),
        icon: const Icon(Icons.edit_note_rounded),
        label: Text(GochanoLanguage.text('New note', 'নতুন নোট')),
      ),
      body: const NotesList(),
    );
  }
}

/// The note list, reusable inside the Study workspace as well as on its own
/// screen.
class NotesList extends StatelessWidget {
  const NotesList({super.key, this.limit});

  /// Caps how many notes are shown, for the workspace preview.
  final int? limit;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('notes', limit: 200),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text('Loading notes…', 'নোট লোড হচ্ছে…'),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        final docs = [...?snapshot.data?.docs]
          ..sort((a, b) {
            final at = a.data()['updatedAt'];
            final bt = b.data()['updatedAt'];
            if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
            return 0;
          });

        if (docs.isEmpty) {
          return EmptyState(
            compact: limit != null,
            illustration: GochanoArt.fileNote,
            title: GochanoLanguage.text('No notes yet', 'এখনো কোনো নোট নেই'),
            message: GochanoLanguage.text(
              'Write your first note. You can ask AI to clean it up or '
              'summarise it later.',
              'আপনার প্রথম নোট লিখুন। পরে এআই দিয়ে গুছিয়ে বা সারাংশ করে নিতে পারবেন।',
            ),
            actionLabel: GochanoLanguage.text('Write a note', 'নোট লিখুন'),
            onAction: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const NoteEditorScreen()),
            ),
          );
        }

        final shown = limit == null ? docs : docs.take(limit!).toList();

        if (limit != null) {
          return CardGroup(
            children: [for (final doc in shown) _NoteRow(doc: doc)],
          );
        }

        return ListView.builder(
          padding: GochanoSpacing.scrollBody,
          itemCount: shown.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: _NoteRow(doc: shown[i]),
            ),
          ),
        );
      },
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = data['title']?.toString() ?? '';
    final content = data['content']?.toString() ?? '';
    final isShared = data['visibility']?.toString() == 'group';

    void open() => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => NoteEditorScreen(
              noteId: doc.id,
              initialData: data,
            ),
          ),
        );

    return GochanoListRow(
      illustration: GochanoArt.fileNote,
      accent: context.colors.study,
      title: title.isEmpty
          ? GochanoLanguage.text('Untitled note', 'শিরোনামহীন নোট')
          : title,
      // One line of the body, so the list is scannable without opening
      // every note.
      subtitle: content.replaceAll('\n', ' ').trim(),
      metadata: [_updatedAt(data['updatedAt'])],
      badge: isShared
          ? GochanoBadge(
              label: GochanoLanguage.text('Shared', 'শেয়ার করা'),
              tone: GochanoBadgeTone.info,
              icon: Icons.groups_rounded,
            )
          : null,
      onTap: open,
      menuItems: [
        GochanoMenuAction(
          label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
          icon: Icons.edit_outlined,
          onSelected: open,
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Delete', 'মুছুন'),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => deleteNote(context, doc),
        ),
      ],
    );
  }
}

String _updatedAt(Object? value) {
  if (value is! Timestamp) return '';
  final when = value.toDate();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
