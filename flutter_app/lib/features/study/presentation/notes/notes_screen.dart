// Text notes (spec §21, §32).
//
// Notes are the "Text Note" resource type spec §21 names, and they are a
// distinct thing from an uploaded material: written in the app, editable, and
// the one type `POST /api/ai/note` operates on directly.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'note_editor_screen.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key, this.notesStream});

  /// Optional stream override for tests or controlled previews.
  final Stream<QuerySnapshot<Map<String, dynamic>>>? notesStream;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('My Notes', 'আমার নোট'),
        subtitle: GochanoLanguage.text(
          'Create & organize lecture notes',
          'লেকচার নোট তৈরি ও সাজান',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: colors.brand,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const NoteEditorScreen())),
        icon: const Icon(Icons.edit_note_rounded),
        label: Text(
          GochanoLanguage.text('New note', 'নতুন নোট'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: AppPageBackground(
        height: 240,
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.surface, colors.background],
              )
            : AppGradients.notesPage,
        child: NotesList(notesStream: notesStream),
      ),
    );
  }
}

/// The note list, reusable inside the Study workspace as well as on its own
/// screen.
class NotesList extends StatelessWidget {
  const NotesList({super.key, this.limit, this.notesStream});

  /// Caps how many notes are shown, for the workspace preview.
  final int? limit;

  /// Optional stream override for testing or custom bindings.
  final Stream<QuerySnapshot<Map<String, dynamic>>>? notesStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: notesStream ?? FirestoreService.ownerStream('notes', limit: 200),
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
          final emptyWidget = EmptyState(
            key: const ValueKey('notes_empty'),
            compact: limit != null,
            illustration: GochanoArt.fileNote,
            title: GochanoLanguage.text('No notes yet', 'এখনো কোনো নোট নেই'),
            message: GochanoLanguage.text(
              'Tap the + button to write your first note.',
              '+ বোতামে ট্যাপ করে আপনার প্রথম নোট লিখুন।',
            ),
          );
          return AnimatedSwitcher(
            duration: AppMotion.duration(
              context,
              AppMotion.contentReveal,
            ),
            switchInCurve: AppMotion.standard,
            switchOutCurve: AppMotion.standard,
            child: emptyWidget,
          );
        }

        final shown = limit == null ? docs : docs.take(limit!).toList();

        final Widget contentWidget;
        if (limit != null) {
          contentWidget = CardGroup(
            key: const ValueKey('notes_card_group'),
            children: [for (final doc in shown) _NoteRow(doc: doc)],
          );
        } else {
          contentWidget = ListView.builder(
            key: const ValueKey('notes_list'),
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
        }

        return AnimatedSwitcher(
          duration: AppMotion.duration(
            context,
            AppMotion.contentReveal,
          ),
          switchInCurve: AppMotion.standard,
          switchOutCurve: AppMotion.standard,
          child: contentWidget,
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
        builder: (_) => NoteEditorScreen(noteId: doc.id, initialData: data),
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
  if (GochanoLanguage.isBangla) {
    const bnMonths = [
      'জানু',
      'ফেব',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টে',
      'অক্টো',
      'নভে',
      'ডিসে',
    ];
    return '${GochanoLanguage.toBanglaDigits(when.day)} ${bnMonths[when.month - 1]}, ${GochanoLanguage.toBanglaDigits(when.year)}';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
