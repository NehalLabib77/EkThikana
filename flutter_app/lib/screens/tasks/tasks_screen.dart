import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  Future<void> _addTask(BuildContext context) async {
    final title = TextEditingController();
    DateTime? due;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Task')),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(
                  due == null ? 'No reminder time' : DateFormat('dd MMM yyyy, h:mm a').format(due!),
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                    initialDate: due ?? DateTime.now(),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(due ?? DateTime.now().add(const Duration(hours: 1))),
                  );
                  if (time == null) return;
                  setDialogState(() {
                    due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (result != true || title.text.trim().isEmpty) {
      title.dispose();
      return;
    }

    try {
      final ref = await FirestoreService.addOwnerRecord('tasks', {
        'title': title.text.trim(),
        'done': false,
        'dueAt': due == null ? null : Timestamp.fromDate(due!),
        'keywords': FirestoreService.keywords(title.text),
      });
      if (due != null) {
        await NotificationService.scheduleTask(
          taskId: ref.id,
          title: title.text.trim(),
          when: due!,
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      title.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks & reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTask(context),
        icon: const Icon(Icons.add),
        label: const Text('Task'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('tasks'),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = [...snap.data!.docs];
          docs.sort((a, b) {
            final ad = a.data()['dueAt'] as Timestamp?;
            final bd = b.data()['dueAt'] as Timestamp?;
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return ad.compareTo(bd);
          });

          if (docs.isEmpty) {
            return const Center(child: Text('No tasks yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final done = data['done'] == true;
              final due = data['dueAt'] as Timestamp?;
              return Card(
                child: CheckboxListTile(
                  value: done,
                  title: Text(
                    data['title']?.toString() ?? '',
                    style: TextStyle(decoration: done ? TextDecoration.lineThrough : null),
                  ),
                  subtitle: due == null
                      ? null
                      : Text(DateFormat('dd MMM yyyy, h:mm a').format(due.toDate())),
                  secondary: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirmAction(
                        context,
                        title: 'Delete task?',
                        message: 'This task will be permanently removed.',
                        action: 'Delete',
                      );
                      if (!ok) return;
                      await NotificationService.cancelTask(doc.id);
                      await doc.reference.delete();
                    },
                  ),
                  onChanged: (value) async {
                    await doc.reference.update({
                      'done': value ?? false,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (value == true) await NotificationService.cancelTask(doc.id);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
