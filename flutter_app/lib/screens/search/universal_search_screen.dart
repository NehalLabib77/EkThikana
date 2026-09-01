import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../services/firestore_service.dart';
import '../study/material_reader_screen.dart';
import '../study/note_editor_screen.dart';

import '../../core/page_route.dart';
class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key, required this.student});

  final bool student;

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final query = TextEditingController();
  bool busy = false;
  List<_SearchResult> results = [];

  static const personalCollections = <String, String>{
    'tasks': 'Task',
    'medicines': 'Medicine',
    'bazar_items': 'BazarBuddy',
    'daily_expenses': 'Daily Expense',
    'commute_trips': 'CommuteBD',
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
      data['medicineName'],
      data['instruction'],
      data['schedule'],
      data['subject'],
      data['fileName'],
      data['category'],
      data['origin'],
      data['destination'],
      data['mode'],
      data['note'],
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

      for (final entry in personalCollections.entries) {
        final snap = await db
            .collection(entry.key)
            .where('ownerId', isEqualTo: uid)
            .limit(100)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          if (!_haystack(data).contains(q)) continue;
          next.add(
            _SearchResult(
              type: entry.value,
              id: doc.id,
              title: data['title']?.toString() ??
                  data['name']?.toString() ??
                  data['medicineName']?.toString() ??
                  (entry.key == 'commute_trips'
                      ? '${data['origin'] ?? ''} → ${data['destination'] ?? ''}'
                      : entry.value),
              subtitle: data['details']?.toString() ??
                  data['instruction']?.toString() ??
                  data['category']?.toString() ??
                  data['note']?.toString() ??
                  '',
              data: data,
            ),
          );
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(EkLanguage.text('Search failed. Please try again.', 'সার্চ করা যায়নি। আবার চেষ্টা করুন।'))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void open(_SearchResult result) {
    if (result.type == 'Note') {
      Navigator.push(
        context,
        GochanoRoute.to(
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
        GochanoRoute.to(
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
            child: Text(EkLanguage.text('Close', 'বন্ধ করুন')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('Search Gochano', 'গোছানোতে খুঁজুন')),
        ),
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
                      ? EkLanguage.text(
                          'Search notes, materials, tasks and daily life',
                          'নোট, উপকরণ, কাজ ও দৈনন্দিন তথ্য খুঁজুন',
                        )
                      : EkLanguage.text(
                          'Search tasks and daily life',
                          'কাজ ও দৈনন্দিন তথ্য খুঁজুন',
                        ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
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
                      ? Center(
                          child: Text(
                            EkLanguage.text(
                              'Type at least 2 characters and search.',
                              'কমপক্ষে ২টি অক্ষর লিখে সার্চ করুন।',
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: results.length,
                          separatorBuilder: (_, _) =>
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
