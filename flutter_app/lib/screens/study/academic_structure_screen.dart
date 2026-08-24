import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/firestore_service.dart';

class AcademicStructureScreen extends StatelessWidget {
  const AcademicStructureScreen({super.key});

  Future<void> _addSemester(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('New semester'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Semester name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await FirestoreService.addOwnerRecord('semesters', {'name': c.text.trim()});
    }
    c.dispose();
  }

  Future<void> _addSubject(BuildContext context, String semesterId) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('New subject'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Subject name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await FirestoreService.addOwnerRecord('subjects', {
        'name': c.text.trim(),
        'semesterId': semesterId,
      });
    }
    c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Semesters & subjects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSemester(context),
        icon: const Icon(Icons.add),
        label: const Text('Semester'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('semesters'),
        builder: (context, semestersSnap) {
          if (!semestersSnap.hasData) return const Center(child: CircularProgressIndicator());

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirestoreService.ownerStream('subjects'),
            builder: (context, subjectsSnap) {
              if (!subjectsSnap.hasData) return const Center(child: CircularProgressIndicator());
              final semesters = semestersSnap.data!.docs;
              final subjects = subjectsSnap.data!.docs;

              if (semesters.isEmpty) return const Center(child: Text('Create your first semester.'));

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: semesters.length,
                itemBuilder: (context, i) {
                  final sem = semesters[i];
                  final semSubjects = subjects.where((s) => s.data()['semesterId'] == sem.id).toList();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      title: Text(
                        sem.data()['name']?.toString() ?? 'Semester',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${semSubjects.length} subjects'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'add') {
                            await _addSubject(context, sem.id);
                          } else if (value == 'delete') {
                            final ok = await confirmAction(
                              context,
                              title: 'Delete semester?',
                              message: 'Delete its subjects first if you no longer need them.',
                              action: 'Delete',
                            );
                            if (ok) await sem.reference.delete();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'add', child: Text('Add subject')),
                          PopupMenuItem(value: 'delete', child: Text('Delete semester')),
                        ],
                      ),
                      children: [
                        for (final subject in semSubjects)
                          ListTile(
                            leading: const Icon(Icons.menu_book_outlined),
                            title: Text(subject.data()['name']?.toString() ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => subject.reference.delete(),
                            ),
                          ),
                        ListTile(
                          leading: const Icon(Icons.add),
                          title: const Text('Add subject'),
                          onTap: () => _addSubject(context, sem.id),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
