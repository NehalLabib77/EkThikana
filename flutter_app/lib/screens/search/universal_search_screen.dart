import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../study/material_reader_screen.dart';
import '../study/note_editor_screen.dart';

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({
    super.key,
    required this.student,
  });

  final bool student;

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final query = TextEditingController();
  bool busy = false;
  List<_SearchResult> results = [];

  static const dailyCollections = <String, String>{
    'tasks': 'Task',
    'medicines': 'Medicine',
    'grocery_items': 'BazarBuddy',
    'family_records': 'FamilyHub',
    'rent_records': 'RentMate',
    'saved_locations': 'CommuteBD',
    'wellness_records': 'Wellness',
  };

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  String _haystack(Map<String, dynamic> data) {
    return [
      data['title'],
      data['content'],
      data['details'],
      data['name'],
      data['instruction'],
      data['schedule'],
      data['subject'],
      data['fileName'],
    ].whereType<Object>().map((e) => e.toString()).join(' ').toLowerCase();
  }

  Future<void> search() async {
    final q = query.text.trim().toLowerCase();
    if (q.length < 2) {
      setState(() => results = []);
      return;
    }

    setState(() => busy = true);
    try {
      final next = <_SearchResult>[];
      final db = FirebaseFirestore.instance;
      final uid = FirestoreService.uid;

      for (final entry in dailyCollections.entries) {
        final snap = await db
            .collection(entry.key)
            .where('ownerId', isEqualTo: uid)
            .limit(100)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          if (_haystack(data).contains(q)) {
            next.add(
              _SearchResult(
                type: entry.value,
                id: doc.id,
                title: data['title']?.toString() ??
                    data['name']?.toString() ??
                    entry.value,
                subtitle: data['details']?.toString() ??
                    data['instruction']?.toString() ??
                    '',
                data: data,
              ),
            );
          }
        }
      }

      if (widget.student) {
        final notes = await db
            .collection('notes')
            .where('ownerId', isEqualTo: uid)
            .limit(100)
            .get();
        for (final doc in notes.docs) {
          final data = doc.data();
          if (_haystack(data).contains(q)) {
            next.add(
              _SearchResult(
                type: 'Note',
                id: doc.id,
                title: data['title']?.toString() ?? 'Note',
                subtitle: data['content']?.toString() ?? '',
                data: data,
              ),
            );
          }
        }

        final materials = await db
            .collection('materials')
            .where('ownerId', isEqualTo: uid)
            .limit(100)
            .get();
        for (final doc in materials.docs) {
          final data = doc.data();
          if (_haystack(data).contains(q)) {
            next.add(
              _SearchResult(
                type: 'Material',
                id: doc.id,
                title: data['title']?.toString() ??
                    data['fileName']?.toString() ??
                    'Material',
                subtitle: data['subject']?.toString() ?? '',
                data: data,
              ),
            );
          }
        }
      }

      if (mounted) setState(() => results = next);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void open(_SearchResult result) {
    if (result.type == 'Note') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorScreen(
            noteId: result.id,
            initialData: result.data,
          ),
        ),
      );
      return;
    }

    if (result.type == 'Material') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(
            materialId: result.id,
            material: result.data,
          ),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(result.title),
        content: SelectableText(
          result.subtitle.trim().isEmpty
              ? result.type
              : '${result.type}\n\n${result.subtitle}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search EkThikana')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: widget.student
                    ? 'Search notes, materials, tasks and daily life'
                    : 'Search tasks and daily life',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: busy ? null : search,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
          Expanded(
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : results.isEmpty
                    ? const Center(
                        child: Text(
                          'Type at least 2 characters and search.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final r = results[i];
                          return Card(
                            child: ListTile(
                              title: Text(r.title),
                              subtitle: Text(
                                '${r.type}${r.subtitle.trim().isEmpty ? '' : ' • ${r.subtitle}'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => open(r),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SearchResult {
  _SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.data,
  });

  final String type;
  final String id;
  final String title;
  final String subtitle;
  final Map<String, dynamic> data;
}
