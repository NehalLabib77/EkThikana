import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design_tokens.dart';
import '../../core/language.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../../services/financial_service.dart';
import '../../widgets/empty_illustrations.dart';
import '../../widgets/gochano_app_bar.dart';
import '../../widgets/gochano_primitives.dart';
import '../search/universal_search_screen.dart';
import '../tasks/tasks_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.role, required this.displayName});

  final String role;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final student = role == 'student';
    final firstName = displayName.trim().isEmpty
        ? 'there'
        : displayName.trim().split(' ').first;
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: GochanoAppBar(
          titleEn: 'Hi, $firstName \u{1F44B}',
          titleBn: 'শুভ সকাল, $firstName \u{1F44B}',
          subtitleEn: 'One place for everything',
          subtitleBn: 'আপনার সবকিছুর এক ঠিকানা',
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('tasks'),
          builder: (context, taskSnap) {
            final tasks = taskSnap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                EkSpace.lg,
                EkSpace.xs,
                EkSpace.lg,
                90,
              ),
              children: [
                GochanoSearchField(
                  hintEn: 'Search notes, tasks, materials\u2026',
                  hintBn: 'নোট, কাজ, উপকরণ খুঁজুন\u2026',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UniversalSearchScreen(student: student),
                    ),
                  ),
                ),
                const SizedBox(height: EkSpace.lg),
                AnimatedFadeIn(
                  child: _greetingHero(context, firstName: firstName),
                ),
                const SizedBox(height: EkSpace.lg),
                if (student) ...[
                  AnimatedFadeIn(
                    delay: const Duration(milliseconds: 80),
                    child: _studyProgress(context, tasks: tasks),
                  ),
                  const SizedBox(height: EkSpace.lg),
                ],
                AnimatedFadeIn(
                  delay: Duration(milliseconds: student ? 160 : 80),
                  child: _todayPlan(context, tasks: tasks),
                ),
                const SizedBox(height: EkSpace.lg),
                AnimatedFadeIn(
                  delay: Duration(milliseconds: student ? 240 : 160),
                  child: _lifeOverview(context, taskCount: tasks.length),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _greetingHero(BuildContext context, {required String firstName}) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? EkLanguage.text('Good morning', 'শুভ সকাল')
        : now.hour < 17
            ? EkLanguage.text('Good afternoon', 'শুভ দুপুর')
            : EkLanguage.text('Good evening', 'শুভ সন্ধ্যা');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: EkGradients.greeting,
        borderRadius: BorderRadius.circular(EkRadius.xl),
      ),
      padding: const EdgeInsets.all(EkSpace.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  firstName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  EkLanguage.text(
                    "Here's what's on your plate today.",
                    'আজ আপনার জন্য কী কী আছে একনজরে।',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: EkSpace.lg),
          SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(
              painter: EmptyIllustrationPainter(
                module: 'ai',
                accent: Colors.white,
                muted: Colors.white.withValues(alpha: .25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studyProgress(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('subjects'),
      builder: (context, subjectsSnap) {
        final subjects = subjectsSnap.data?.docs.length ?? 0;
        final studyTasks = tasks.where((d) {
          final data = d.data();
          return data['subjectId'] != null || data['semesterId'] != null;
        }).toList();
        final completed = studyTasks.where((d) => d.data()['done'] == true).length;
        final total = studyTasks.length;
        final progress = total == 0 ? 0.0 : completed / total;
        final accent = EkGradients.module('study').colors.last;

        return SoftTile(
          module: 'study',
          radius: EkRadius.xl,
          padding: const EdgeInsets.all(EkSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: EkGradients.study,
                      borderRadius: BorderRadius.circular(EkRadius.sm),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: EkIcon.sm,
                    ),
                  ),
                  const SizedBox(width: EkSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          EkLanguage.text('Study Progress', 'পড়াশোনার অগ্রগতি'),
                          style: EkText.title(context),
                        ),
                        Text(
                          EkLanguage.text('This semester', 'এই সেমিস্টার'),
                          style: TextStyle(
                            fontSize: 11,
                            color: EkSurfaces.muted(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GochanoChip(
                    label: '${(progress * 100).round()}%',
                    tone: GochanoChipTone.info,
                  ),
                ],
              ),
              const SizedBox(height: EkSpace.lg),
              Row(
                children: [
                  SizedBox(
                    width: 62,
                    height: 62,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 62,
                          height: 62,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 6,
                            backgroundColor: EkSoft.module(context, 'study'),
                            color: accent,
                          ),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: EkSurfaces.text(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: EkSpace.lg),
                  Expanded(
                    child: Text(
                      total == 0
                          ? EkLanguage.text(
                              'Add study tasks to track your progress.',
                              'অগ্রগতি দেখতে পড়াশোনার কাজ যোগ করুন।',
                            )
                          : EkLanguage.text(
                              'Keep going! You completed $completed of $total study tasks.',
                              'চালিয়ে যান! $total টি কাজের মধ্যে $completed টি শেষ করেছেন।',
                            ),
                      style: TextStyle(
                        fontSize: 12,
                        color: EkSurfaces.text(context),
                        height: 1.35,
                      ),
                    ),
                  ),
                  _miniStat(
                    context,
                    '$subjects',
                    EkLanguage.text('Subjects', 'বিষয়'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniStat(BuildContext context, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: EkSoft.module(context, 'study'),
        borderRadius: BorderRadius.circular(EkRadius.sm),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: EkGradients.study.colors.first,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: EkSurfaces.muted(context),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayPlan(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks,
  }) {
    final now = DateTime.now();
    final docs = tasks
        .where((d) {
          if (d.data()['done'] == true) return false;
          final ts = d.data()['dueAt'] as Timestamp?;
          if (ts == null) return true;
          final due = ts.toDate();
          return due.year == now.year &&
              due.month == now.month &&
              due.day == now.day;
        })
        .take(4)
        .toList();
    return Column(
      children: [
        SectionHeader(
          title: Text(
            EkLanguage.text("Today's Plan", 'আজকের পরিকল্পনা'),
            style: EkText.title(context),
          ),
          action: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TasksScreen()),
            ),
            child: Text(EkLanguage.text('See all', 'সব দেখুন')),
          ),
        ),
        const SizedBox(height: EkSpace.sm),
        if (docs.isEmpty)
          SoftTile(
            module: 'tasks',
            radius: EkRadius.xl,
            padding: const EdgeInsets.all(EkSpace.lg),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: EkGradients.module('tasks').colors.first,
                    borderRadius: BorderRadius.circular(EkRadius.sm),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: EkIcon.sm,
                  ),
                ),
                const SizedBox(width: EkSpace.md),
                Expanded(
                  child: Text(
                    EkLanguage.text(
                      'No urgent tasks for today.',
                      'আজ কোনো জরুরি কাজ নেই।',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EkSurfaces.text(context),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          StaggeredList(
            spacing: EkSpace.sm,
            baseDelay: const Duration(milliseconds: 60),
            step: const Duration(milliseconds: 60),
            children: docs.map((d) => _taskRow(context, d)).toList(),
          ),
      ],
    );
  }

  Widget _taskRow(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final due = data['dueAt'] as Timestamp?;
    final time =
        due == null ? '--:--' : DateFormat('hh:mm a').format(due.toDate());
    return SoftTile(
      module: 'tasks',
      radius: EkRadius.lg,
      padding: const EdgeInsets.symmetric(
        horizontal: EkSpace.md,
        vertical: EkSpace.sm + 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              time,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: EkSurfaces.muted(context),
              ),
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: EkSoft.module(context, 'tasks'),
              borderRadius: BorderRadius.circular(EkRadius.sm),
            ),
            child: Icon(
              Icons.assignment_outlined,
              color: EkGradients.module('tasks').colors.first,
              size: 18,
            ),
          ),
          const SizedBox(width: EkSpace.sm + 2),
          Expanded(
            child: Text(
              data['title']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: EkSurfaces.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lifeOverview(BuildContext context, {required int taskCount}) {
    return Column(
      children: [
        SectionHeader(
          title: Text(
            EkLanguage.text('Life Overview', 'জীবনের সারাংশ'),
            style: EkText.title(context),
          ),
        ),
        const SizedBox(height: EkSpace.sm),
        Row(
          children: [
            Expanded(
              child: _staticCountCard(
                context,
                taskCount,
                Icons.task_alt,
                EkLanguage.text('Tasks', 'কাজ'),
                'tasks',
              ),
            ),
            const SizedBox(width: EkSpace.sm),
            Expanded(
              child: _countCard(
                context,
                'medicines',
                Icons.medication_outlined,
                EkLanguage.text('Medicine', 'ওষুধ'),
                'medicine',
              ),
            ),
            const SizedBox(width: EkSpace.sm),
            Expanded(child: _monthlySpendingCard(context)),
          ],
        ),
      ],
    );
  }

  Widget _staticCountCard(
    BuildContext context,
    int count,
    IconData icon,
    String label,
    String module,
  ) {
    return GradientStatCard(
      module: module,
      compact: true,
      icon: icon,
      title: label,
      value: '$count',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TasksScreen()),
      ),
    );
  }

  Widget _monthlySpendingCard(BuildContext context) {
    return StreamBuilder(
      stream: FinancialService.monthStream(DateTime.now()),
      builder: (context, snap) {
        final transactions = snap.data ?? const [];
        final summary = FinancialService.summary(transactions);
        return GradientStatCard(
          module: 'expense',
          compact: true,
          icon: Icons.account_balance_wallet_outlined,
          title: EkLanguage.text('This month', 'এই মাস'),
          value: '\u09F3${summary.totalSpending.toStringAsFixed(0)}',
        );
      },
    );
  }

  Widget _countCard(
    BuildContext context,
    String collection,
    IconData icon,
    String label,
    String module,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream(collection, limit: 50),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return GradientStatCard(
          module: module,
          compact: true,
          icon: icon,
          title: label,
          value: '$count',
        );
      },
    );
  }
}
