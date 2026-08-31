import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../services/firestore_service.dart';
import '../../widgets/gochano_primitives.dart';
import 'note_editor_screen.dart';

import '../../core/page_route.dart';
class NotesScreen extends StatelessWidget {
  const NotesScreen({
    super.key,
    this.groupId,
    this.groupName,
  });

  final String? groupId;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final stream = groupId == null
        ? FirestoreService.ownerStream('notes')
        : FirestoreService.groupNotes(groupId!);

    return Scaffold(
      appBar: AppBar(title: Text(groupId == null ? 'My notes' : '$groupName — Notes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          GochanoRoute.to(
            builder: (_) => NoteEditorScreen(
              initialVisibility: groupId == null ? 'private' : 'group',
              initialGroupId: groupId,
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Note'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return EmptyState(
              module: 'study',
              title: EkLanguage.text(
                'No notes yet.',
                'এখনও কোনো নোট নেই।',
              ),
              message: EkLanguage.text(
                'Tap the Note button below to capture your first idea.',
                'নিচের Note বোতামে চাপ দিয়ে প্রথম নোটটি তৈরি করুন।',
              ),
              compact: true,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final own = data['ownerId'] == FirestoreService.uid;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.note_alt_outlined),
                  title: Text(data['title']?.toString() ?? 'Untitled'),
                  subtitle: Text(
                    data['content']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(data['visibility']?.toString() ?? 'private'),
                  onTap: () => Navigator.push(
                    context,
                    GochanoRoute.to(
                      builder: (_) => NoteEditorScreen(
                        noteId: doc.id,
                        initialData: data,
                        readOnly: !own,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
