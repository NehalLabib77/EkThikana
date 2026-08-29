import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/gochano_primitives.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  int tab = 0;

  Future<void> _addTask(BuildContext context) async {
    final title = TextEditingController();
    DateTime? due;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(EkLanguage.text('New task', 'নতুন কাজ')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: EkLanguage.text('Task', 'কাজ'))),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule, color: EkColors.purple),
                title: Text(
                  due == null
                      ? EkLanguage.text('No reminder time', 'রিমাইন্ডারের সময় নেই')
                      : DateFormat('dd MMM yyyy, h:mm a').format(due!),
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
                  setDialogState(() => due = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(EkLanguage.text('Cancel', 'বাতিল'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(EkLanguage.text('Save', 'সংরক্ষণ'))),
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
        await NotificationService.scheduleTask(taskId: ref.id, title: title.text.trim(), when: due!);
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      title.dispose();
    }
  }

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    return value.year == now.year && value.month == now.month && value.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(EkLanguage.text('My Tasks', 'আমার কাজ')),
              Text(EkLanguage.text('Stay organized, get more done', 'গুছিয়ে থাকুন, কাজ এগিয়ে নিন'), style: const TextStyle(fontSize: 11, color: EkColors.muted, fontWeight: FontWeight.w500)),
            ],
          ),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        floatingActionButton: FloatingActionButton(onPressed: () => _addTask(context), child: const Icon(Icons.add)),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('tasks'),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final all = [...snap.data!.docs];
            all.sort((a, b) {
              final ad = a.data()['dueAt'] as Timestamp?;
              final bd = b.data()['dueAt'] as Timestamp?;
              if (ad == null && bd == null) return 0;
              if (ad == null) return 1;
              if (bd == null) return -1;
              return ad.compareTo(bd);
            });

            final filtered = all.where((doc) {
              if (tab == 0) return true;
              final ts = doc.data()['dueAt'] as Timestamp?;
              if (ts == null) return false;
              if (tab == 1) return _isToday(ts.toDate());
              final tomorrow = DateTime.now().add(const Duration(days: 1));
              return ts.toDate().isAfter(DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xFFF0F1F7), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        _tabButton(0, EkLanguage.text('All', 'সব')),
                        _tabButton(1, EkLanguage.text('Today', 'আজ')),
                        _tabButton(2, EkLanguage.text('Upcoming', 'আসছে')),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyState(
                          module: 'tasks',
                          title: EkLanguage.text(
                            'No tasks here yet.',
                            'এখানে এখনও কোনো কাজ নেই।',
                          ),
                          message: EkLanguage.text(
                            'Tap the + button below to add your first task.',
                            'নিচের + বোতামে চাপ দিয়ে প্রথম কাজ যোগ করুন।',
                          ),
                          compact: true,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                          children: [
                            for (final doc in filtered) ...[
                              _taskCard(context, doc),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tabButton(int value, String label) {
    final selected = tab == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => tab = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? EkColors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : EkColors.muted, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _taskCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final done = data['done'] == true;
    final due = data['dueAt'] as Timestamp?;
    final dueDate = due?.toDate();
    final time = dueDate == null ? '' : DateFormat('hh:mm a').format(dueDate);
    final late = dueDate != null && dueDate.isBefore(DateTime.now()) && !done;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: done,
              activeColor: EkColors.green,
              onChanged: (value) async {
                await doc.reference.update({'done': value ?? false, 'updatedAt': FieldValue.serverTimestamp()});
                if (value == true) await NotificationService.cancelTask(doc.id);
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['title']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.w700, decoration: done ? TextDecoration.lineThrough : null)),
                  if (dueDate != null)
                    Text(DateFormat('dd MMM yyyy').format(dueDate), style: const TextStyle(color: EkColors.muted, fontSize: 10)),
                ],
              ),
            ),
            if (time.isNotEmpty)
              Text(time, style: TextStyle(color: late ? EkColors.red : EkColors.green, fontWeight: FontWeight.w700, fontSize: 11)),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value != 'delete') return;
                final ok = await confirmAction(context, title: EkLanguage.text('Delete task?', 'কাজ মুছবেন?'), message: EkLanguage.text('This task will be permanently removed.', 'এই কাজটি স্থায়ীভাবে মুছে যাবে।'), action: EkLanguage.text('Delete', 'মুছুন'));
                if (!ok) return;
                await NotificationService.cancelTask(doc.id);
                await doc.reference.delete();
              },
              itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(EkLanguage.text('Delete', 'মুছুন')))],
            ),
          ],
        ),
      ),
    );
  }
}
