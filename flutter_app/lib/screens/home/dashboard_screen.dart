import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../search/universal_search_screen.dart';
import '../tasks/tasks_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final student = role == 'student';
    final firstName = displayName.trim().isEmpty ? 'there' : displayName.trim().split(' ').first;

    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(EkLanguage.text('Good morning, $firstName 👋', 'শুভ সকাল, $firstName 👋')),
              Text(
                EkLanguage.text('One place for everything', 'আপনার সবকিছুর এক ঠিকানা'),
                style: const TextStyle(fontSize: 11, color: EkColors.muted, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          children: [
            TextField(
              readOnly: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UniversalSearchScreen(student: student)),
              ),
              decoration: InputDecoration(
                hintText: EkLanguage.text('Search notes, tasks, materials…', 'নোট, কাজ, উপকরণ খুঁজুন…'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 14),
            if (student) _studyProgress(context),
            if (student) const SizedBox(height: 16),
            _todayPlan(context),
            const SizedBox(height: 16),
            _lifeOverview(context),
          ],
        ),
      ),
    );
  }

  Widget _studyProgress(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('subjects'),
      builder: (context, subjectsSnap) {
        final subjects = subjectsSnap.data?.docs.length ?? 0;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('tasks'),
          builder: (context, taskSnap) {
            final tasks = taskSnap.data?.docs ?? const [];
            final studyTasks = tasks.where((d) {
              final data = d.data();
              return data['subjectId'] != null || data['semesterId'] != null;
            }).toList();
            final completed = studyTasks.where((d) => d.data()['done'] == true).length;
            final total = studyTasks.length;
            final progress = total == 0 ? 0.0 : completed / total;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: Text(EkLanguage.text('Study Progress', 'পড়াশোনার অগ্রগতি')),
                      subtitle: Text(EkLanguage.text('This semester', 'এই সেমিস্টার')),
                      action: const Icon(Icons.chevron_right, color: EkColors.muted),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        SizedBox(
                          width: 62,
                          height: 62,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 6,
                                backgroundColor: EkColors.lavender,
                                color: EkColors.purple,
                              ),
                              Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            total == 0
                                ? EkLanguage.text('Add study tasks to track your progress.', 'অগ্রগতি দেখতে পড়াশোনার কাজ যোগ করুন।')
                                : EkLanguage.text('Keep going! You completed $completed of $total study tasks.', 'চালিয়ে যান! $total টি কাজের মধ্যে $completed টি শেষ করেছেন।'),
                            style: const TextStyle(fontSize: 12, height: 1.35),
                          ),
                        ),
                        _miniStat('$subjects', EkLanguage.text('Subjects', 'বিষয়')),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniStat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(color: EkColors.lavender, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: EkColors.purple, fontWeight: FontWeight.w800, fontSize: 17)),
          Text(label, style: const TextStyle(color: EkColors.muted, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _todayPlan(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('tasks'),
      builder: (context, snap) {
        final now = DateTime.now();
        final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .where((d) {
              if (d.data()['done'] == true) return false;
              final ts = d.data()['dueAt'] as Timestamp?;
              if (ts == null) return true;
              final due = ts.toDate();
              return due.year == now.year && due.month == now.month && due.day == now.day;
            })
            .take(4)
            .toList();

        return Column(
          children: [
            SectionHeader(
              title: Text(EkLanguage.text("Today's Plan", 'আজকের পরিকল্পনা')),
              action: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen())),
                child: Text(EkLanguage.text('See all', 'সব দেখুন')),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: docs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: EkColors.green),
                          const SizedBox(width: 12),
                          Expanded(child: Text(EkLanguage.text('No urgent tasks for today.', 'আজ কোনো জরুরি কাজ নেই।'))),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < docs.length; i++) ...[
                          _taskRow(docs[i]),
                          if (i != docs.length - 1) const Divider(height: 1, indent: 72),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _taskRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final due = data['dueAt'] as Timestamp?;
    final time = due == null ? '--:--' : DateFormat('hh:mm a').format(due.toDate());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 58, child: Text(time, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: EkColors.muted))),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: EkColors.lavender, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.assignment_outlined, color: EkColors.purple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(data['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _lifeOverview(BuildContext context) {
    return Column(
      children: [
        SectionHeader(title: Text(EkLanguage.text('Life Overview', 'জীবনের সারাংশ'))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _countCard('tasks', Icons.task_alt, EkLanguage.text('Tasks', 'কাজ'), EkColors.purple)),
            const SizedBox(width: 8),
            Expanded(child: _countCard('medicines', Icons.medication_outlined, EkLanguage.text('Medicine', 'ওষুধ'), EkColors.green)),
            const SizedBox(width: 8),
            Expanded(child: _countCard('rent_records', Icons.home_outlined, EkLanguage.text('Rent', 'ভাড়া'), EkColors.red)),
          ],
        ),
      ],
    );
  }

  Widget _countCard(String collection, IconData icon, String label, Color color) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream(collection, limit: 50),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 7),
                Text('$count', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: EkColors.muted, fontSize: 9)),
              ],
            ),
          ),
        );
      },
    );
  }
}
