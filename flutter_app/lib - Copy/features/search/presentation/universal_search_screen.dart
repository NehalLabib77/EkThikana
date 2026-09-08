// Search across everything the student owns (spec §31, §85).
//
// One field, results grouped by what they are: materials, notes and tasks.
// Search runs client-side over the documents already streamed for this user —
// which is the right trade-off here because the collections are per-owner and
// bounded, and it means search works on partial words and on Bangla text
// without needing a search index.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../study/presentation/materials/material_reader_screen.dart';
import '../../study/presentation/notes/note_editor_screen.dart';
import '../../tasks/presentation/add_task_sheet.dart';

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Search', 'অনুসন্ধান'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GochanoSpacing.md,
              GochanoSpacing.xs,
              GochanoSpacing.md,
              GochanoSpacing.sm,
            ),
            child: SearchField(
              controller: _controller,
              autofocus: true,
              hint: GochanoLanguage.text(
                'Search materials, notes and tasks',
                'উপকরণ, নোট ও কাজ খুঁজুন',
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
              trailing: _query.isEmpty
                  ? null
                  : IconActionButton(
                      icon: Icons.close_rounded,
                      label: GochanoLanguage.text('Clear', 'মুছুন'),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          Expanded(
            child: _query.length < 2
                ? EmptyState(
                    illustration: GochanoArt.emptySearch,
                    title: GochanoLanguage.text(
                      'Search your work',
                      'আপনার কাজ খুঁজুন',
                    ),
                    message: GochanoLanguage.text(
                      'Type at least two letters to search across materials, '
                      'notes and tasks.',
                      'উপকরণ, নোট ও কাজে খুঁজতে অন্তত দুটি অক্ষর লিখুন।',
                    ),
                  )
                : _Results(query: _query.toLowerCase()),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('materials', limit: 300),
      builder: (context, materialSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('notes', limit: 300),
          builder: (context, noteSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.ownerStream('tasks', limit: 300),
              builder: (context, taskSnapshot) {
                final loading = [materialSnapshot, noteSnapshot, taskSnapshot]
                    .any((s) => s.connectionState == ConnectionState.waiting);
                if (loading) {
                  return StaticLoadingState(
                    message: GochanoLanguage.text(
                      'Searching…',
                      'খোঁজা হচ্ছে…',
                    ),
                  );
                }

                final materials = _filter(
                  materialSnapshot.data?.docs,
                  const ['title', 'fileName', 'subject'],
                );
                final notes = _filter(
                  noteSnapshot.data?.docs,
                  const ['title', 'content'],
                );
                final tasks = _filter(
                  taskSnapshot.data?.docs,
                  const ['title'],
                );

                if (materials.isEmpty && notes.isEmpty && tasks.isEmpty) {
                  return EmptyState(
                    illustration: GochanoArt.emptySearch,
                    title: GochanoLanguage.text(
                      'Nothing found',
                      'কিছু পাওয়া যায়নি',
                    ),
                    message: GochanoLanguage.text(
                      'Try a different word.',
                      'অন্য একটি শব্দ চেষ্টা করুন।',
                    ),
                  );
                }

                return ListView(
                  padding: GochanoSpacing.scrollBody,
                  children: [
                    if (materials.isNotEmpty) ...[
                      SectionHeader(
                        title: GochanoLanguage.text('Materials', 'উপকরণ'),
                        padding: const EdgeInsets.only(
                          bottom: GochanoSpacing.xs,
                        ),
                      ),
                      CardGroup(
                        children: [
                          for (final doc in materials)
                            _MaterialResult(doc: doc),
                        ],
                      ),
                    ],
                    if (notes.isNotEmpty) ...[
                      SectionHeader(
                        title: GochanoLanguage.text('Notes', 'নোট'),
                      ),
                      CardGroup(
                        children: [
                          for (final doc in notes) _NoteResult(doc: doc),
                        ],
                      ),
                    ],
                    if (tasks.isNotEmpty) ...[
                      SectionHeader(
                        title: GochanoLanguage.text('Tasks', 'কাজ'),
                      ),
                      CardGroup(
                        children: [
                          for (final doc in tasks) _TaskResult(doc: doc),
                        ],
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Case-insensitive substring match over the named fields.
  ///
  /// Substring rather than token-prefix so a Bangla query, or a partial word
  /// like "normal" inside "Normalization", still matches.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
    List<String> fields,
  ) {
    if (docs == null) return const [];
    return docs.where((doc) {
      final data = doc.data();
      return fields.any(
        (field) => (data[field]?.toString().toLowerCase() ?? '').contains(query),
      );
    }).take(20).toList();
  }
}

class _MaterialResult extends StatelessWidget {
  const _MaterialResult({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString()
        : data['fileName']?.toString() ?? '';
    final fileName = data['fileName']?.toString() ?? '';
    final mimeType = data['mimeType']?.toString() ?? '';

    return GochanoListRow(
      illustration: GochanoArt.fileIdFor(fileName: fileName, mimeType: mimeType),
      accent: context.colors.study,
      title: title,
      subtitle: data['subject']?.toString(),
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

class _NoteResult extends StatelessWidget {
  const _NoteResult({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    return GochanoListRow(
      illustration: GochanoArt.fileNote,
      accent: context.colors.study,
      title: data['title']?.toString() ?? '',
      subtitle: data['content']?.toString().replaceAll('\n', ' ').trim(),
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(
          builder: (_) => NoteEditorScreen(noteId: doc.id, initialData: data),
        ),
      ),
    );
  }
}

class _TaskResult extends StatelessWidget {
  const _TaskResult({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final done = data['done'] == true;

    return GochanoListRow(
      illustration: done ? GochanoArt.stateTaken : GochanoArt.featureTasks,
      accent: done ? context.colors.success : context.colors.brand,
      title: data['title']?.toString() ?? '',
      badge: done
          ? GochanoBadge(
              label: GochanoLanguage.text('Done', 'সম্পন্ন'),
              tone: GochanoBadgeTone.success,
              icon: Icons.check_rounded,
            )
          : null,
      onTap: () => showAddTaskSheet(context, existing: doc),
    );
  }
}
