import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import 'material_reader_screen.dart';
import 'note_editor_screen.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community Library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Materials'),
              Tab(text: 'Notes'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PublicMaterials(),
            _PublicNotes(),
          ],
        ),
      ),
    );
  }
}

class _PublicMaterials extends StatefulWidget {
  const _PublicMaterials();

  @override
  State<_PublicMaterials> createState() => _PublicMaterialsState();
}

class _PublicMaterialsState extends State<_PublicMaterials> {
  final search = TextEditingController();

  String university = '';
  String department = '';
  String semester = '';
  String subject = '';
  String type = '';
  String sort = 'newest';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<String> _values(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String field,
  ) {
    final values = docs
        .map((d) => d.data()[field]?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  bool _matches(Map<String, dynamic> d) {
    final q = search.text.trim().toLowerCase();
    final haystack = [
      d['title'],
      d['fileName'],
      d['ownerName'],
      d['university'],
      d['department'],
      d['semester'],
      d['subject'],
    ].whereType<Object>().map((e) => e.toString()).join(' ').toLowerCase();

    if (q.isNotEmpty && !haystack.contains(q)) return false;
    if (university.isNotEmpty && d['university']?.toString() != university) {
      return false;
    }
    if (department.isNotEmpty && d['department']?.toString() != department) {
      return false;
    }
    if (semester.isNotEmpty && d['semester']?.toString() != semester) {
      return false;
    }
    if (subject.isNotEmpty && d['subject']?.toString() != subject) {
      return false;
    }

    final mime = d['mimeType']?.toString().toLowerCase() ?? '';
    if (type == 'pdf' && !mime.contains('pdf')) return false;
    if (type == 'image' && !mime.startsWith('image/')) return false;

    return true;
  }

  void _openFilters(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var localUniversity = university;
    var localDepartment = department;
    var localSemester = semester;
    var localSubject = subject;
    var localType = type;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Widget dropdown(
            String label,
            String value,
            List<String> values,
            ValueChanged<String?> onChanged,
          ) {
            return DropdownButtonFormField<String>(
              initialValue: values.contains(value) ? value : '',
              decoration: InputDecoration(labelText: label),
              items: [
                const DropdownMenuItem(value: '', child: Text('All')),
                for (final v in values)
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: onChanged,
            );
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text(
                      'Community filters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    dropdown(
                      'University',
                      localUniversity,
                      _values(docs, 'university'),
                      (v) => setSheetState(() => localUniversity = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    dropdown(
                      'Department',
                      localDepartment,
                      _values(docs, 'department'),
                      (v) => setSheetState(() => localDepartment = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    dropdown(
                      'Semester',
                      localSemester,
                      _values(docs, 'semester'),
                      (v) => setSheetState(() => localSemester = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    dropdown(
                      'Subject',
                      localSubject,
                      _values(docs, 'subject'),
                      (v) => setSheetState(() => localSubject = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: localType,
                      decoration: const InputDecoration(
                        labelText: 'Material type',
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All')),
                        DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                        DropdownMenuItem(value: 'image', child: Text('Image')),
                      ],
                      onChanged: (v) =>
                          setSheetState(() => localType = v ?? ''),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                university = '';
                                department = '';
                                semester = '';
                                subject = '';
                                type = '';
                              });
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                university = localUniversity;
                                department = localDepartment;
                                semester = localSemester;
                                subject = localSubject;
                                type = localType;
                              });
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.publicMaterials(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snap.data!.docs;
        final docs = allDocs.where((d) => _matches(d.data())).toList();

        docs.sort((a, b) {
          if (sort == 'saved') {
            final av = int.tryParse(a.data()['saveCount']?.toString() ?? '') ?? 0;
            final bv = int.tryParse(b.data()['saveCount']?.toString() ?? '') ?? 0;
            return bv.compareTo(av);
          }

          final at = a.data()['createdAt'] as Timestamp?;
          final bt = b.data()['createdAt'] as Timestamp?;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText:
                            'Search title, university, department, semester or subject',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Filters',
                    onPressed: () => _openFilters(context, allDocs),
                    icon: const Icon(Icons.tune),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Sort',
                    onSelected: (v) => setState(() => sort = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'newest', child: Text('Newest')),
                      PopupMenuItem(value: 'saved', child: Text('Most saved')),
                    ],
                    icon: const Icon(Icons.sort),
                  ),
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const Center(
                      child: Text('No public materials match these filters.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.public),
                            title: Text(d['title']?.toString() ?? ''),
                            subtitle: Text(
                              [
                                d['university']?.toString() ?? '',
                                d['department']?.toString() ?? '',
                                d['semester']?.toString() ?? '',
                                d['subject']?.toString() ?? '',
                                '${d['saveCount'] ?? 0} saves',
                              ]
                                  .where((e) => e.trim().isNotEmpty)
                                  .join(' • '),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MaterialReaderScreen(
                                  materialId: doc.id,
                                  material: d,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PublicNotes extends StatefulWidget {
  const _PublicNotes();

  @override
  State<_PublicNotes> createState() => _PublicNotesState();
}

class _PublicNotesState extends State<_PublicNotes> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.publicNotes(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final q = search.text.trim().toLowerCase();
        final docs = snap.data!.docs.where((doc) {
          if (q.isEmpty) return true;
          final d = doc.data();
          final haystack = [
            d['title'],
            d['content'],
            d['ownerName'],
            d['university'],
            d['department'],
            d['semester'],
          ]
              .whereType<Object>()
              .map((e) => e.toString())
              .join(' ')
              .toLowerCase();
          return haystack.contains(q);
        }).toList();

        docs.sort((a, b) {
          final at = a.data()['createdAt'] as Timestamp?;
          final bt = b.data()['createdAt'] as Timestamp?;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search public notes',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const Center(child: Text('No public notes found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.note_alt_outlined),
                            title: Text(d['title']?.toString() ?? ''),
                            subtitle: Text(
                              [
                                d['ownerName']?.toString() ?? '',
                                d['university']?.toString() ?? '',
                                d['department']?.toString() ?? '',
                                d['content']?.toString() ?? '',
                              ]
                                  .where((e) => e.trim().isNotEmpty)
                                  .join(' • '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NoteEditorScreen(
                                  noteId: doc.id,
                                  initialData: d,
                                  readOnly: true,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
