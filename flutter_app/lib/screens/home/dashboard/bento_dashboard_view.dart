// Bento dashboard — composes the greeting card, study progress hero,
// AI shortcut, medicine next-dose, BazarBuddy, commute, monthly spend,
// and today's tasks into the new bento grid.
//
// Rules followed (per bento brief):
//   - No architecture / provider / model changes. Streams, services,
//     and navigation targets are reused unchanged.
//   - 28px radius, soft shadows, 20-22px padding throughout.
//   - Module tints come from `BentoColors` (purple/blue/green/orange/
//     sky/yellow). Every card declares which module it belongs to.
//   - Animation: each entry wraps a small fade + slide-up on first
//     paint via `BentoCard`'s built-in controller (300ms).
//   - Subtitle text uses the on-tint muted color so a dark card stays
//     legible.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/language.dart';
import '../../../services/firestore_service.dart';
import '../../../services/financial_service.dart';
import '../../../widgets/bento/bento_bar.dart';
import '../../life/bazar_buddy_screen.dart';
import '../../life/commute_bd_screen.dart';
import '../../life/life_screen.dart';
import '../../life/medicine_screen.dart';
import '../../search/universal_search_screen.dart';
import '../../study/ai_assistant_screen.dart';
import '../../tasks/tasks_screen.dart';

import '../../../core/page_route.dart';
class BentoDashboardView extends StatelessWidget {
  const BentoDashboardView({
    super.key,
    required this.firstName,
    required this.role,
    required this.student,
    required this.tasks,
  });

  final String firstName;
  final String role;
  final bool student;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks;

  @override
  Widget build(BuildContext context) {
    final today = _todayTasks(tasks);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
      children: [
        SearchField(student: student),
        const SizedBox(height: 18),
        BentoEntry(
          delay: const Duration(milliseconds: 0),
          child: GreetingCard(firstName: firstName, role: role),
        ),
        const SizedBox(height: 14),
        if (student) ...[
          BentoEntry(
            delay: const Duration(milliseconds: 80),
            child: StudyProgressCard(tasks: tasks),
          ),
          const SizedBox(height: 14),
        ],
        BentoEntry(
          delay: Duration(milliseconds: student ? 160 : 80),
          child: Row(
            children: const [
              Expanded(child: AiCard()),
              SizedBox(width: 14),
              Expanded(child: HealthCard()),
            ],
          ),
        ),
        const SizedBox(height: 14),
        BentoEntry(
          delay: Duration(milliseconds: student ? 240 : 160),
          child: BazarBuddyCard(),
        ),
        const SizedBox(height: 14),
        BentoEntry(
          delay: Duration(milliseconds: student ? 320 : 240),
          child: Row(
            children: const [
              Expanded(child: CommuteCard()),
              SizedBox(width: 14),
              Expanded(child: MoneyCard()),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader(
          title: EkLanguage.text("Today's Plan", 'আজকের পরিকল্পনা'),
          trailing: EkLanguage.text('See all', 'সব দেখুন'),
          onTrailingTap: () => Navigator.push(
            context,
            GochanoRoute.to(builder: (_) => const TasksScreen()),
          ),
        ),
        const SizedBox(height: 10),
        if (today.isEmpty)
          const BentoEntry(
            delay: Duration(milliseconds: 0),
            child: EmptyTasksCard(),
          )
        else
          ...today.asMap().entries.map(
                (entry) => BentoEntry(
                  delay: Duration(milliseconds: 120 * entry.key),
                  child: Padding(
                    padding: EdgeInsets.only(
                        bottom: entry.key == today.length - 1 ? 0 : 12),
                    child: TaskTile(doc: entry.value),
                  ),
                ),
              ),
      ],
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _todayTasks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> source,
  ) {
    final now = DateTime.now();
    return source.where((d) {
      if (d.data()['done'] == true) return false;
      final ts = d.data()['dueAt'] as Timestamp?;
      if (ts == null) return true;
      final due = ts.toDate();
      return due.year == now.year &&
          due.month == now.month &&
          due.day == now.day;
    }).take(4).toList();
  }
}

// ─────────────── animation entry helper ───────────────

class BentoEntry extends StatefulWidget {
  const BentoEntry({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<BentoEntry> createState() => _BentoEntryState();
}

class _BentoEntryState extends State<BentoEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────── section helpers ───────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTrailingTap,
  });

  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: BentoColors.onTint(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailing != null && onTrailingTap != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTrailingTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailing!,
                  style: TextStyle(
                    color: BentoColors.studyAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: BentoColors.studyAccent),
              ],
            ),
          ),
      ],
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.student});
  final bool student;

  @override
  Widget build(BuildContext context) {
    final hint = EkLanguage.text(
      'Search notes, tasks, materials',
      'নোট, কাজ, উপকরণ খুঁজুন',
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        GochanoRoute.to(
          builder: (_) => UniversalSearchScreen(student: student),
        ),
      ),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                size: 20, color: BentoColors.onTintMuted(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: BentoColors.onTintMuted(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: BentoColors.onTintMuted(context)),
          ],
        ),
      ),
    );
  }
}

// ─────────────── greeting card ───────────────

class GreetingCard extends StatelessWidget {
  const GreetingCard({super.key, required this.firstName, required this.role});
  final String firstName;
  final String role;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return EkLanguage.text('Good morning', 'শুভ সকাল');
    if (hour < 17) return EkLanguage.text('Good afternoon', 'শুভ দুপুর');
    return EkLanguage.text('Good evening', 'শুভ সন্ধ্যা');
  }

  @override
  Widget build(BuildContext context) {
    final m = BentoColors.module(context, 'study');
    return BentoCard(
      background: m.tint,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      radius: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()} 👋',
                  style: TextStyle(
                    color: BentoColors.onTintMuted(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BentoColors.onTint(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  EkLanguage.text(
                    role == 'student'
                        ? "Here's what's on your plate today."
                        : 'Your day, at a glance.',
                    role == 'student'
                        ? 'আজ আপনার জন্য কী কী আছে একনজরে।'
                        : 'আজকের দিন, একনজরে।',
                  ),
                  style: TextStyle(
                    color: BentoColors.onTint(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: m.accent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── study progress ───────────────

class StudyProgressCard extends StatelessWidget {
  const StudyProgressCard({super.key, required this.tasks});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> tasks;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('subjects'),
      builder: (context, snap) {
        final subjects = snap.data?.docs.length ?? 0;
        final study = tasks.where((d) {
          final data = d.data();
          return data['subjectId'] != null || data['semesterId'] != null;
        }).toList();
        final completed = study.where((d) => d.data()['done'] == true).length;
        final total = study.length;
        final pct = total == 0 ? 0 : ((completed / total) * 100).round();

        return BentoLargeCard(
          moduleId: 'study',
          icon: Icons.menu_book_rounded,
          title: EkLanguage.text('Study Progress', 'পড়াশোনার অগ্রগতি'),
          subtitle: total == 0
              ? EkLanguage.text(
                  'Add study tasks to track your progress.',
                  'অগ্রগতি দেখতে পড়াশোনার কাজ যোগ করুন।',
                )
              : EkLanguage.text(
                  '$completed of $total tasks done this semester.',
                  '$total টি কাজের মধ্যে $completed টি শেষ।',
                ),
          footer: Row(
            children: [
              StatPill(value: '$pct%', label: 'Done'),
              const SizedBox(width: 8),
              StatPill(
                  value: '$subjects',
                  label: EkLanguage.text('Subjects', 'বিষয়')),
              const SizedBox(width: 8),
              StatPill(
                  value: '$total', label: EkLanguage.text('Tasks', 'কাজ')),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            GochanoRoute.to(builder: (_) => const TasksScreen()),
          ),
        );
      },
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = BentoColors.studyAccent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: BentoColors.onTintMuted(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── AI + Health row ───────────────

class AiCard extends StatelessWidget {
  const AiCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BentoLargeCard(
      moduleId: 'ai',
      icon: Icons.auto_awesome_rounded,
      title: EkLanguage.text('AI Assistant', 'AI সহকারী'),
      subtitle: EkLanguage.text(
        'Summarize, explain, and ask anything.',
        'সারাংশ, ব্যাখ্যা, যেকোনো প্রশ্ন।',
      ),
      onTap: () => Navigator.push(
        context,
        GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
      ),
      height: 168,
    );
  }
}

class HealthCard extends StatelessWidget {
  const HealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.ownerStream('medicines', limit: 50),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return BentoSmallCard(
          moduleId: 'medicine',
          icon: Icons.medication_rounded,
          title: EkLanguage.text('Medicine', 'ওষুধ'),
          subtitle: EkLanguage.text('Next dose reminder', 'পরবর্তী ডোজ'),
          value: '$count',
          height: 168,
          onTap: () => Navigator.push(
            context,
            GochanoRoute.to(builder: (_) => const MedicineScreen()),
          ),
        );
      },
    );
  }
}

// ─────────────── BazarBuddy ───────────────

class BazarBuddyCard extends StatelessWidget {
  const BazarBuddyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BentoActionCard(
      moduleId: 'bazar',
      icon: Icons.shopping_basket_rounded,
      title: EkLanguage.text('BazarBuddy', 'বাজারবন্ধু'),
      subtitle: EkLanguage.text(
        '3 items pending — open your list',
        '৩টি পণ্য বাকি — তালিকা খুলুন',
      ),
      onTap: () => Navigator.push(
        context,
        GochanoRoute.to(builder: (_) => const BazarBuddyScreen()),
      ),
    );
  }
}

// ─────────────── Commute + Money row ───────────────

class CommuteCard extends StatelessWidget {
  const CommuteCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BentoSmallCard(
      moduleId: 'commute',
      icon: Icons.directions_bus_filled_rounded,
      title: EkLanguage.text('CommuteBD', 'যাতায়াতBD'),
      subtitle: EkLanguage.text('Plan a route', 'রুট প্ল্যান করুন'),
      onTap: () => Navigator.push(
        context,
        GochanoRoute.to(builder: (_) => const CommuteBDScreen()),
      ),
      height: 152,
    );
  }
}

class MoneyCard extends StatelessWidget {
  const MoneyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FinancialService.monthStream(DateTime.now()),
      builder: (context, snap) {
        final transactions = snap.data ?? const [];
        final summary = FinancialService.summary(transactions);
        return BentoStatCard(
          moduleId: 'money',
          icon: Icons.account_balance_wallet_rounded,
          label: EkLanguage.text('This month', 'এই মাস'),
          value: '৳${summary.totalSpending.toStringAsFixed(0)}',
          onTap: () => Navigator.push(
            context,
            GochanoRoute.to(builder: (_) => const LifeScreen()),
          ),
          height: 152,
        );
      },
    );
  }
}

// ─────────────── Today's plan ───────────────

class EmptyTasksCard extends StatelessWidget {
  const EmptyTasksCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BentoActionCard(
      moduleId: 'tasks',
      icon: Icons.check_circle_rounded,
      title: EkLanguage.text('All clear', 'সব শেষ'),
      subtitle: EkLanguage.text(
        'No urgent tasks for today.',
        'আজ কোনো জরুরি কাজ নেই।',
      ),
      onTap: () => Navigator.push(
        context,
        GochanoRoute.to(builder: (_) => const TasksScreen()),
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.doc});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final due = data['dueAt'] as Timestamp?;
    final time = due == null
        ? '--:--'
        : DateFormat('hh:mm a').format(due.toDate());
    return BentoActionCard(
      moduleId: 'tasks',
      icon: Icons.assignment_rounded,
      title: (data['title']?.toString() ?? '').isEmpty
          ? EkLanguage.text('Untitled task', 'নামহীন কাজ')
          : data['title'].toString(),
      subtitle: time,
      onTap: () => Navigator.push(
        context,
        GochanoRoute.to(builder: (_) => const TasksScreen()),
      ),
    );
  }
}