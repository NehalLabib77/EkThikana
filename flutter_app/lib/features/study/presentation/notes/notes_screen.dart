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
import '../../../../services/connectivity_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'note_editor_screen.dart';
import 'note_reader_screen.dart';

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
        heroTag: 'notes-fab',
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
class NotesList extends StatefulWidget {
  const NotesList({super.key, this.limit});

  /// Caps how many notes are shown, for the workspace preview.
  final int? limit;

  @override
  State<NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  @override
  Widget build(BuildContext context) {
    // When offline, try to show cached notes
    if (!ConnectivityService.instance.online.value) {
      return FutureBuilder<dynamic>(
        future: ConnectivityService.instance.getCachedData(
          OfflineFeature.notes,
          'all',
        ),
        builder: (context, snapshot) {
          final cached = snapshot.data;
          if (cached != null && cached is List && cached.isNotEmpty) {
            return _buildNoteList(cached.cast<Map<String, dynamic>>());
          }
          return EmptyState(
            compact: widget.limit != null,
            illustration: GochanoArt.fileNote,
            title: GochanoLanguage.text(
              'Offline',
              'অফলাইন',
            ),
            message: GochanoLanguage.text(
              'No cached notes available. Connect to the internet to load notes.',
              'কোনো ক্যাশ করা নোট নেই। নোট লোড করতে ইন্টারনেট সংযোগ করুন।',
            ),
          );
        },
      );
    }

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

        // Cache notes for offline use
        if (docs.isNotEmpty) {
          final cacheData = docs.map((d) => {
            'id': d.id,
            ...d.data(),
          }).toList();
          ConnectivityService.instance.cacheData(
            OfflineFeature.notes,
            'all',
            cacheData,
          );
        }

        if (docs.isEmpty) {
          return EmptyState(
            compact: widget.limit != null,
            illustration: GochanoArt.fileNote,
            title: GochanoLanguage.text('No notes yet', 'এখনো কোনো নোট নেই'),
            message: GochanoLanguage.text(
              'Tap the + button to write your first note.',
              '+ বোতামে ট্যাপ করে আপনার প্রথম নোট লিখুন।',
            ),
          );
        }

        final shown = widget.limit == null ? docs : docs.take(widget.limit!).toList();

        if (widget.limit != null) {
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

  Widget _buildNoteList(List<Map<String, dynamic>> notes) {
    if (widget.limit != null) {
      return CardGroup(
        children: [
          for (final note in notes.take(widget.limit!))
            _CachedNoteRow(note: note),
        ],
      );
    }

    return ListView.builder(
      padding: GochanoSpacing.scrollBody,
      itemCount: notes.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: _CachedNoteRow(note: notes[i]),
        ),
      ),
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

    void openReadOnly() => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => NoteReaderScreen(
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
      onTap: openReadOnly,
      menuItems: [
        GochanoMenuAction(
          label: GochanoLanguage.text('View', 'দেখুন'),
          icon: Icons.visibility_outlined,
          onSelected: openReadOnly,
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Edit', 'সম্পাদনা'),
          icon: Icons.edit_outlined,
          onSelected: open,
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Delete', 'মুছুন'),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () async {
            final deleted = await deleteNote(context, doc);
            if (deleted && context.mounted) {
              showGochanoMessage(
                context,
                GochanoLanguage.text('Note deleted.', 'নোট মুছে ফেলা হয়েছে।'),
              );
            }
          },
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

/// Note row for cached (offline) notes. Read-only, taps open the reader.
class _CachedNoteRow extends StatelessWidget {
  const _CachedNoteRow({required this.note});

  final Map<String, dynamic> note;

  @override
  Widget build(BuildContext context) {
    final title = note['title']?.toString() ?? '';
    final content = note['content']?.toString() ?? '';
    final noteId = note['id']?.toString() ?? '';

    return GochanoListRow(
      illustration: GochanoArt.fileNote,
      accent: context.colors.study,
      title: title.isEmpty
          ? GochanoLanguage.text('Untitled note', 'শিরোনামহীন নোট')
          : title,
      subtitle: content.replaceAll('\n', ' ').trim(),
      badge: GochanoBadge(
        label: GochanoLanguage.text('Cached', 'ক্যাশড'),
        tone: GochanoBadgeTone.neutral,
        icon: Icons.offline_bolt_outlined,
      ),
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(
          builder: (_) => NoteReaderScreen(
            noteId: noteId,
            initialData: note,
          ),
        ),
      ),
    );
  }
}
