// Today / Student Command Center — "What needs my attention today?"
//
// Uses StudentContext as the primary normalised data source (Phase 3).
// No duplicate normalisation logic inside widgets.
//
// Structure:
//   Header → Daily Priority → Now/Next → Today's Schedule →
//   Study + Medicine (bento) → Money → Quick Actions

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_dates.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/navigation.dart';
import '../../../core/page_route.dart';
import '../../../core/student/student.dart';
import '../../../models/financial_transaction.dart';
import '../../../services/api_service.dart';
import '../../../services/financial_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../life/presentation/commute/commute_screen.dart';
import '../../life/presentation/expense/add_expense_sheet.dart';
import '../../life/presentation/medicine/medicine_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../study/presentation/ai/ai_assistant_screen.dart';
import '../../../widgets/language_toggle.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  HomeScreen — Today / Student Command Center
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.role,
    required this.displayName,
    required this.onOpenDestination,
    required this.onOpenStudyTab,
    required this.onOpenAiAssistant,
  });

  final String role;
  final String displayName;
  final ValueChanged<int> onOpenDestination;
  final ValueChanged<int> onOpenStudyTab;
  final VoidCallback onOpenAiAssistant;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── Stream subscriptions ──────────────────────────────────────────────
  final _subs = <StreamSubscription<dynamic>>[];

  // ── Current raw data from each source ─────────────────────────────────
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _taskDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _medicineDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _doseDocs = [];
  FinancialSummary? _financialSummary;
  MoneyRawFields? _moneyRawFields;
  int? _communityGroupCount;
  Map<String, double> _settlements = const {};

  // ── Built context ─────────────────────────────────────────────────────
  StudentContext _ctx = StudentContext(generatedAt: DateTime(2000));
  bool _loaded = false;

  bool get _isStudent => widget.role == 'student';

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _subscribe();
    FinancialService.budgetRefreshKey.addListener(_onBudgetRefresh);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    FinancialService.budgetRefreshKey.removeListener(_onBudgetRefresh);
    super.dispose();
  }

  // ── Stream wiring ─────────────────────────────────────────────────────

  void _subscribe() {
    _subs.add(
      FirestoreService.ownerStream('tasks', limit: 100).listen(
        (snap) {
          _taskDocs = [...snap.docs];
          _rebuild();
        },
        onError: (_) {
          _taskDocs = [];
          _rebuild();
        },
      ),
    );

    _subs.add(
      FirestoreService.ownerStream('medicines', limit: 50).listen(
        (snap) {
          _medicineDocs = [...snap.docs];
          _rebuild();
        },
        onError: (_) {
          _medicineDocs = [];
          _rebuild();
        },
      ),
    );

    _subs.add(
      FirestoreService.ownerStream('medicine_doses', limit: 100).listen(
        (snap) {
          _doseDocs = [...snap.docs];
          _rebuild();
        },
        onError: (_) {
          _doseDocs = [];
          _rebuild();
        },
      ),
    );

    _subs.add(
      FinancialService.monthStream(DateTime.now()).listen(
        (items) {
          _financialSummary = FinancialSummary.fromTransactions(items);
          _rebuild();
        },
        onError: (_) {
          _financialSummary = null;
          _rebuild();
        },
      ),
    );

    _subs.add(
      FinancialService.denaPawnaSettlementTotalsStream(DateTime.now()).listen(
        (s) {
          _settlements = s;
          _loadBudget();
        },
        onError: (_) {
          _moneyRawFields = null;
          _rebuild();
        },
      ),
    );

    _subs.add(
      FirestoreService.myGroups().listen(
        (snap) {
          _communityGroupCount = snap.docs.length;
          _rebuild();
        },
        onError: (_) {
          _communityGroupCount = null;
          _rebuild();
        },
      ),
    );

    // Initial budget load
    _loadBudget();
  }

  void _onBudgetRefresh() => _loadBudget();

  Future<void> _loadBudget() async {
    try {
      final body = await ApiService.getRemaining(DateTime.now());
      if (!mounted) return;
      _moneyRawFields = MoneyRawFields(
        backendRemaining: (body['remaining'] as num?)?.toDouble() ?? 0,
        pawnaReceived: _settlements['pawnaReceived'] ?? 0,
        denaPaid: _settlements['denaPaid'] ?? 0,
      );
    } catch (_) {
      _moneyRawFields = null;
    }
    _rebuild();
  }

  void _rebuild() {
    if (!mounted) return;
    StudentContextService.build(
      day: DateTime.now(),
      taskDocs: _taskDocs,
      medicineDocs: _medicineDocs,
      doseDocs: _doseDocs,
      financialSummary: _financialSummary,
      moneyRawFields: _moneyRawFields,
      communityGroupCount: _communityGroupCount,
    ).then((ctx) {
      if (mounted) {
        setState(() {
          _ctx = ctx;
          _loaded = true;
        });
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: _HomeAppBar(
        role: widget.role,
        actions: const [
          LanguageToggle(),
          SizedBox(width: GochanoSpacing.xs),
        ],
      ),
      body: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _DailyPrioritySummary(ctx: _ctx, loaded: _loaded),
          const SizedBox(height: GochanoSpacing.sm),
          _SmartAttentionSection(
            ctx: _ctx,
            loaded: _loaded,
            onOpenStudyTab: widget.onOpenStudyTab,
            onOpenDestination: widget.onOpenDestination,
            onOpenAiAssistant: widget.onOpenAiAssistant,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          _NowNextCard(ctx: _ctx, loaded: _loaded, onOpenStudyTab: widget.onOpenStudyTab),
          const SizedBox(height: GochanoSpacing.sm),
          _TodaySchedule(
            ctx: _ctx,
            loaded: _loaded,
            onSeeAll: () => widget.onOpenStudyTab(StudyTab.plan.tabIndex),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          _QuickActions(isStudent: _isStudent),
          if (_isStudent) ...[
            const SizedBox(height: GochanoSpacing.sm),
            _BentoRow(
              left: _StudySnapshot(
                ctx: _ctx,
                loaded: _loaded,
                onOpenStudyTab: widget.onOpenStudyTab,
              ),
              right: _MedicineSnapshot(ctx: _ctx, loaded: _loaded),
            ),
          ] else ...[
            const SizedBox(height: GochanoSpacing.sm),
            _MedicineSnapshot(ctx: _ctx, loaded: _loaded),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          _MoneySnapshot(
            ctx: _ctx,
            loaded: _loaded,
            onOpenDestination: widget.onOpenDestination,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  A. Header
// ══════════════════════════════════════════════════════════════════════════════

class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBar({required this.role, this.actions});

  final String role;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final now = DateTime.now();
    final dateLabel = formatShortDate(now);

    return AppBar(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: GochanoSpacing.md,
      title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.profileStream(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final photoURL = data?['photoURL'] as String?;
          final name =
              (data?['displayName'] as String?)?.trim() ?? '';

          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => ProfileScreen(role: role)),
            ),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colors.brand,
                  child: _ProfileAvatarSmall(
                    photoURL: photoURL,
                    displayName: name,
                    colors: colors,
                    type: type,
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        GochanoLanguage.text('Today', 'আজ'),
                        style: type.pageTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        dateLabel,
                        style: type.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ],
            ),
          );
        },
      ),
      actions: actions,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  B. Daily Priority Summary
// ══════════════════════════════════════════════════════════════════════════════

class _DailyPrioritySummary extends StatelessWidget {
  const _DailyPrioritySummary({required this.ctx, required this.loaded});

  final StudentContext ctx;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (!loaded) return const _SectionSkeleton();

    final todayCount = ctx.todayEvents.length;
    final overdueCount = ctx.overdueEvents.length;
    final pendingMed = ctx.pendingMedicine.length;

    // Compose summary pills
    final pills = <Widget>[];

    if (todayCount > 0) {
      pills.add(_SummaryPill(
        icon: Icons.today_rounded,
        label: GochanoLanguage.text(
          '$todayCount today',
          '$todayCount টি আজ',
        ),
        color: colors.brand,
      ));
    }

    if (overdueCount > 0) {
      pills.add(_SummaryPill(
        icon: Icons.warning_amber_rounded,
        label: GochanoLanguage.text(
          '$overdueCount overdue',
          '$overdueCount টি বাকি',
        ),
        color: colors.warning,
      ));
    }

    if (pendingMed > 0) {
      pills.add(_SummaryPill(
        icon: Icons.medication_rounded,
        label: GochanoLanguage.text(
          '$pendingMed medicine',
          '$pendingMed টি ওষুধ',
        ),
        color: colors.medicine,
      ));
    }

    if (pills.isEmpty) {
      return _AccentRailCard(
        accent: colors.brand,
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.md,
          vertical: GochanoSpacing.sm,
        ),
        child: Row(
          children: [
            GochanoIllustration(
              GochanoArt.emptyTasks,
              size: 28,
              accent: colors.textTertiary,
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(
              child: Text(
                GochanoLanguage.text(
                  'Nothing urgent today.',
                  'আজ কিছু জরুরি নেই।',
                ),
                style: context.type.bodySecondary,
              ),
            ),
          ],
        ),
      );
    }

    return _AccentRailCard(
      accent: colors.brand,
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            GochanoLanguage.text('Your Day', 'আপনার দিন'),
            style: context.type.sectionHeading,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xxs,
            children: pills,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  C. Smart Attention Section
// ══════════════════════════════════════════════════════════════════════════════

class _SmartAttentionSection extends StatelessWidget {
  const _SmartAttentionSection({
    required this.ctx,
    required this.loaded,
    required this.onOpenStudyTab,
    required this.onOpenDestination,
    required this.onOpenAiAssistant,
  });

  final StudentContext ctx;
  final bool loaded;
  final ValueChanged<int> onOpenStudyTab;
  final ValueChanged<int> onOpenDestination;
  final VoidCallback onOpenAiAssistant;

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const _SectionSkeleton();

    final signals = StudentSignalService.topSignals(ctx, maxSignals: 3)
        .where((s) => s.type != SignalType.clearDay)
        .toList();

    if (signals.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final primary = signals.first;
    final secondary = signals.length > 1 ? signals.sublist(1) : <StudentSignal>[];

    return _AccentRailCard(
      accent: _signalColor(primary, colors),
      padding: GochanoSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: colors.ai),
              const SizedBox(width: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text('Smart attention', 'গুরুত্বপূর্ণ'),
                style: context.type.caption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          _SignalCard(
            signal: primary,
            colors: colors,
            onTap: () => _navigateToSignal(primary, context),
          ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Wrap(
              spacing: GochanoSpacing.xs,
              runSpacing: GochanoSpacing.xs,
              children: [
                for (final s in secondary)
                  _SignalChip(
                    signal: s,
                    colors: colors,
                    onTap: () => _navigateToSignal(s, context),
                  ),
              ],
            ),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          _SmartAttentionActions(
            signals: signals,
            onOpenAiAssistant: onOpenAiAssistant,
            onOpenStudyTab: onOpenStudyTab,
          ),
        ],
      ),
    );
  }

  void _navigateToSignal(StudentSignal signal, BuildContext context) {
    if (signal.type == SignalType.missedMedicine) {
      Navigator.of(context).push(GochanoRoute.to(builder: (_) => const MedicineScreen()));
    } else if (signal.type == SignalType.budgetAttention) {
      onOpenDestination(StudentArea.money.tabIndex);
    } else {
      onOpenStudyTab(StudyTab.plan.tabIndex);
    }
  }

  Color _signalColor(StudentSignal signal, GochanoColors colors) {
    switch (signal.type) {
      case SignalType.overdueWork:
      case SignalType.dueSoon:
      case SignalType.upcomingAssignment:
        return colors.warning;
      case SignalType.missedMedicine:
        return colors.medicine;
      case SignalType.heavyDay:
        return colors.study;
      case SignalType.budgetAttention:
        return colors.expense;
      case SignalType.clearDay:
        return colors.success;
    }
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.signal,
    required this.colors,
    required this.onTap,
  });

  final StudentSignal signal;
  final GochanoColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        decoration: BoxDecoration(
          color: _signalColor(signal, colors).withValues(alpha: 0.08),
          borderRadius: GochanoRadius.mdAll,
          border: Border.all(
            color: _signalColor(signal, colors).withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _signalIcon(signal),
              size: 20,
              color: _signalColor(signal, colors),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signal.title,
                    style: context.type.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    signal.subtitle,
                    style: context.type.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Color _signalColor(StudentSignal signal, GochanoColors colors) {
    switch (signal.type) {
      case SignalType.overdueWork:
      case SignalType.dueSoon:
      case SignalType.upcomingAssignment:
        return colors.warning;
      case SignalType.missedMedicine:
        return colors.medicine;
      case SignalType.heavyDay:
        return colors.study;
      case SignalType.budgetAttention:
        return colors.expense;
      case SignalType.clearDay:
        return colors.success;
    }
  }

  IconData _signalIcon(StudentSignal signal) {
    switch (signal.type) {
      case SignalType.overdueWork:
        return Icons.warning_rounded;
      case SignalType.dueSoon:
        return Icons.schedule_rounded;
      case SignalType.heavyDay:
        return Icons.today_rounded;
      case SignalType.upcomingAssignment:
        return Icons.assignment_rounded;
      case SignalType.missedMedicine:
        return Icons.medication_rounded;
      case SignalType.budgetAttention:
        return Icons.account_balance_wallet_rounded;
      case SignalType.clearDay:
        return Icons.check_circle_rounded;
    }
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.signal,
    required this.colors,
    required this.onTap,
  });

  final StudentSignal signal;
  final GochanoColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.sm,
          vertical: GochanoSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: GochanoRadius.smAll,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _signalIcon(signal),
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Text(
              signal.title,
              style: context.type.caption.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _signalIcon(StudentSignal signal) {
    switch (signal.type) {
      case SignalType.overdueWork:
        return Icons.warning_rounded;
      case SignalType.dueSoon:
        return Icons.schedule_rounded;
      case SignalType.heavyDay:
        return Icons.today_rounded;
      case SignalType.upcomingAssignment:
        return Icons.assignment_rounded;
      case SignalType.missedMedicine:
        return Icons.medication_rounded;
      case SignalType.budgetAttention:
        return Icons.account_balance_wallet_rounded;
      case SignalType.clearDay:
        return Icons.check_circle_rounded;
    }
  }
}

class _SmartAttentionActions extends StatelessWidget {
  const _SmartAttentionActions({
    required this.signals,
    required this.onOpenAiAssistant,
    required this.onOpenStudyTab,
  });

  final List<StudentSignal> signals;
  final VoidCallback onOpenAiAssistant;
  final ValueChanged<int> onOpenStudyTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasOverdue = signals.any((s) => s.type == SignalType.overdueWork);

    return Row(
      children: [
        Expanded(
          child: _SmartActionChip(
            label: GochanoLanguage.text('Plan my day', 'আজকের পরিকল্পনা'),
            icon: Icons.calendar_today_rounded,
            color: colors.study,
            onTap: onOpenAiAssistant,
          ),
        ),
        if (hasOverdue) ...[
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: _SmartActionChip(
              label: GochanoLanguage.text('Rescue my day', 'আজকের কাজ গুছিয়ে দিন'),
              icon: Icons.handshake_rounded,
              color: colors.warning,
              onTap: onOpenAiAssistant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SmartActionChip extends StatelessWidget {
  const _SmartActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.sm,
          vertical: GochanoSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: GochanoRadius.smAll,
          border: Border.all(
            color: color.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: GochanoSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: context.type.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  D. Now / Next Card
// ══════════════════════════════════════════════════════════════════════════════

class _NowNextCard extends StatelessWidget {
  const _NowNextCard({
    required this.ctx,
    required this.loaded,
    required this.onOpenStudyTab,
  });

  final StudentContext ctx;
  final bool loaded;
  final ValueChanged<int> onOpenStudyTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (!loaded) return const _SectionSkeleton();

    final event = _pickPriorityEvent(ctx);
    if (event == null) {
      return const SizedBox.shrink();
    }

    return _AccentRailCard(
      accent: _accentForEvent(event, colors),
      onTap: () => _navigateToEvent(context, event, onOpenStudyTab),
      child: Row(
        children: [
          Icon(
            _iconForEvent(event),
            size: 20,
            color: _accentForEvent(event, colors),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  GochanoLanguage.text('Now / Next', 'এখন / পরবর্তী'),
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.title.isNotEmpty
                      ? event.title
                      : GochanoLanguage.text('Untitled', 'শিরোনামহীন'),
                  style: context.type.cardHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusBadge(status: event.status),
              if (event.scheduledAt != null) ...[
                const SizedBox(height: 2),
                Text(
                  _timeLabel(event.scheduledAt!),
                  style: context.type.caption.copyWith(
                    color: event.status == StudentEventStatus.overdue
                        ? colors.warning
                        : colors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Deterministic priority: overdue task → overdue medicine → nearest
  /// pending today → next upcoming.
  static StudentEvent? _pickPriorityEvent(StudentContext ctx) {
    // 1. Overdue task/assignment
    for (final e in ctx.overdueEvents) {
      if (e.type == StudentEventType.task ||
          e.type == StudentEventType.assignment) {
        return e;
      }
    }
    // 2. Overdue/missed medicine
    for (final e in ctx.overdueEvents) {
      if (e.type == StudentEventType.medicine) return e;
    }
    for (final e in ctx.todayEvents) {
      if (e.type == StudentEventType.medicine &&
          (e.status == StudentEventStatus.missed ||
              e.status == StudentEventStatus.overdue)) {
        return e;
      }
    }
    // 3. Nearest pending event today
    for (final e in ctx.todayEvents) {
      if (e.status == StudentEventStatus.pending) return e;
    }
    // 4. Next upcoming
    if (ctx.upcomingEvents.isNotEmpty) return ctx.upcomingEvents.first;
    return null;
  }

  static IconData _iconForEvent(StudentEvent e) {
    switch (e.type) {
      case StudentEventType.task:
        return Icons.task_alt_rounded;
      case StudentEventType.assignment:
        return Icons.assignment_rounded;
      case StudentEventType.medicine:
        return Icons.medication_rounded;
    }
  }

  static Color _accentForEvent(StudentEvent e, GochanoColors colors) {
    if (e.status == StudentEventStatus.overdue ||
        e.status == StudentEventStatus.missed) {
      return colors.warning;
    }
    switch (e.type) {
      case StudentEventType.task:
      case StudentEventType.assignment:
        return colors.study;
      case StudentEventType.medicine:
        return colors.medicine;
    }
  }

  static void _navigateToEvent(
    BuildContext context,
    StudentEvent event,
    ValueChanged<int> onOpenStudyTab,
  ) {
    if (event.type == StudentEventType.medicine) {
      Navigator.of(context).push(
        GochanoRoute.to(builder: (_) => const MedicineScreen()),
      );
    } else {
      onOpenStudyTab(StudyTab.plan.tabIndex);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  D. Today's Schedule
// ══════════════════════════════════════════════════════════════════════════════

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({
    required this.ctx,
    required this.loaded,
    required this.onSeeAll,
  });

  final StudentContext ctx;
  final bool loaded;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (!loaded) return const _SectionSkeleton();

    final events = ctx.todayEvents;

    return _AccentRailCard(
      accent: colors.brand,
      onTap: onSeeAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.today_rounded, size: 18, color: colors.brand),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text("Today", 'আজ'),
                  style: context.type.sectionHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (ctx.overdueEvents.isNotEmpty) ...[
                const SizedBox(width: GochanoSpacing.xs),
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '${ctx.overdueEvents.length} overdue',
                    '${ctx.overdueEvents.length} টি বাকি',
                  ),
                  tone: GochanoBadgeTone.warning,
                  icon: Icons.schedule_rounded,
                ),
              ],
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if (events.isEmpty)
            Row(
              children: [
                GochanoIllustration(
                  GochanoArt.emptyTasks,
                  size: 28,
                  accent: colors.textTertiary,
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'All clear today.',
                      'আজ ফাঁকা।',
                    ),
                    style: context.type.bodySecondary,
                  ),
                ),
              ],
            )
          else
            for (var i = 0; i < events.length && i < 5; i++)
              _EventRow(
                event: events[i],
                isLast: i == events.length - 1 || i == 4,
              ),
          if (events.length > 5) ...[
            const SizedBox(height: GochanoSpacing.xxs),
            Text(
              GochanoLanguage.text(
                '+${events.length - 5} more',
                'আরও ${events.length - 5} টি',
              ),
              style: context.type.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// A single event row in Today's schedule.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.isLast});

  final StudentEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOverdue = event.status == StudentEventStatus.overdue;
    final isDone = event.status == StudentEventStatus.completed;
    final isMissed = event.status == StudentEventStatus.missed;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : GochanoSpacing.xxs),
      child: Row(
        children: [
          Icon(
            _iconForType(event.type),
            size: 16,
            color: isDone
                ? colors.success
                : isOverdue || isMissed
                    ? colors.warning
                    : colors.textSecondary,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Text(
              event.title.isNotEmpty
                  ? event.title
                  : GochanoLanguage.text('Untitled', 'শিরোনামহীন'),
              style: context.type.body.copyWith(
                decoration: isDone ? TextDecoration.lineThrough : null,
                color: isDone ? colors.textTertiary : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (event.scheduledAt != null) ...[
            const SizedBox(width: GochanoSpacing.xs),
            Flexible(
              child: Text(
                _timeLabel(event.scheduledAt!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.caption.copyWith(
                  color: isOverdue || isMissed
                      ? colors.warning
                      : isDone
                          ? colors.textTertiary
                          : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconForType(StudentEventType type) {
    switch (type) {
      case StudentEventType.task:
        return Icons.circle_outlined;
      case StudentEventType.assignment:
        return Icons.assignment_outlined;
      case StudentEventType.medicine:
        return Icons.medication_outlined;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  E. Study Snapshot
// ══════════════════════════════════════════════════════════════════════════════

class _StudySnapshot extends StatelessWidget {
  const _StudySnapshot({
    required this.ctx,
    required this.loaded,
    required this.onOpenStudyTab,
  });

  final StudentContext ctx;
  final bool loaded;
  final ValueChanged<int> onOpenStudyTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final summary = ctx.studySummary;

    return _AccentRailCard(
      accent: colors.study,
      onTap: () => onOpenStudyTab(StudyTab.plan.tabIndex),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.school_rounded, size: 18, color: colors.study),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Study', 'পড়াশোনা'),
                  style: context.type.sectionHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if (!loaded)
            Text(
              GochanoLanguage.text('Loading…', 'লোড হচ্ছে…'),
              style: context.type.bodySecondary,
            )
          else if (summary == null)
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Text(
                    GochanoLanguage.text('Unavailable', 'তথ্য পাওয়া যায়নি'),
                    style: context.type.bodySecondary,
                  ),
                ),
              ],
            )
          else ...[
            _StatPill(
              label: GochanoLanguage.text('Tasks', 'কাজ'),
              value: '${summary.totalTasks}',
              color: colors.study,
            ),
            if (summary.overdueCount > 0) ...[
              const SizedBox(height: GochanoSpacing.xxs),
              _StatPill(
                label: GochanoLanguage.text('Overdue', 'বাকি'),
                value: '${summary.overdueCount}',
                color: colors.warning,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  F. Medicine Snapshot (read-only)
// ══════════════════════════════════════════════════════════════════════════════

class _MedicineSnapshot extends StatelessWidget {
  const _MedicineSnapshot({required this.ctx, required this.loaded});

  final StudentContext ctx;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return _AccentRailCard(
      accent: colors.medicine,
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(builder: (_) => const MedicineScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.medication_rounded, size: 18, color: colors.medicine),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Medicine', 'ওষুধ'),
                  style: context.type.sectionHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if (!loaded)
            Text(
              GochanoLanguage.text('Loading…', 'লোড হচ্ছে…'),
              style: context.type.bodySecondary,
            )
          else if (ctx.pendingMedicine.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: colors.success,
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'All done for today',
                      'আজকের সব হয়েছে',
                    ),
                    style: context.type.bodySecondary,
                  ),
                ),
              ],
            )
          else ...[
            _StatPill(
              label: GochanoLanguage.text('Pending', 'বাকি'),
              value: '${ctx.pendingMedicine.length}',
              color: colors.medicine,
            ),
            const SizedBox(height: GochanoSpacing.xxs),
            Text(
              GochanoLanguage.text('Tap to open', 'খুলতে ট্যাপ করুন'),
              style: context.type.caption.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  G. Money Snapshot
// ══════════════════════════════════════════════════════════════════════════════

class _MoneySnapshot extends StatelessWidget {
  const _MoneySnapshot({
    required this.ctx,
    required this.loaded,
    required this.onOpenDestination,
  });

  final StudentContext ctx;
  final bool loaded;
  final ValueChanged<int> onOpenDestination;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final money = ctx.moneySummary;

    return _AccentRailCard(
      accent: colors.expense,
      onTap: () => onOpenDestination(StudentArea.money.tabIndex),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 18,
                color: colors.expense,
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Money', 'টাকা'),
                  style: context.type.sectionHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if (!loaded)
            Text(
              GochanoLanguage.text('Loading…', 'লোড হচ্ছে…'),
              style: context.type.bodySecondary,
            )
          else if (money == null)
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 14, color: colors.textTertiary),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'Unable to load budget',
                      'বাজেট লোড হয়নি',
                    ),
                    style: context.type.bodySecondary,
                  ),
                ),
              ],
            )
          else ...[
            _MoneyRow(
              label: GochanoLanguage.text('Spent', 'খরচ'),
              amount: money.totalSpent,
              color: colors.expense,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            _MoneyRow(
              label: GochanoLanguage.text('Remaining', 'অবশিষ্ট'),
              amount: money.adjustedRemaining,
              color: money.adjustedRemaining > 0
                  ? colors.success
                  : colors.error,
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  H. Quick Actions (preserved exactly)
// ══════════════════════════════════════════════════════════════════════════════

class _QuickActions extends StatefulWidget {
  const _QuickActions({required this.isStudent});

  final bool isStudent;

  @override
  State<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<_QuickActions> {
  static const _dragThreshold = 50.0;
  static const _flingThreshold = 450.0;

  bool _expanded = true;

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? 0;
    if (dy > _dragThreshold && !_expanded) {
      setState(() => _expanded = true);
    } else if (dy < -_dragThreshold && _expanded) {
      setState(() => _expanded = false);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > _flingThreshold) {
      setState(() => _expanded = true);
    } else if (velocity < -_flingThreshold) {
      setState(() => _expanded = false);
    }
  }

  List<_QuickAction> _actions(BuildContext context) {
    final colors = context.colors;
    return <_QuickAction>[
      if (widget.isStudent)
        _QuickAction(
          label: GochanoLanguage.text('Ask AI', 'AI-কে জিজ্ঞাসা'),
          icon: Icons.auto_awesome_rounded,
          accent: colors.ai,
          onTap: () => Navigator.of(context).push(
            GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
          ),
        ),
      _QuickAction(
        label: GochanoLanguage.text('Add Expense', 'খরচ যোগ করুন'),
        icon: Icons.receipt_long_rounded,
        accent: colors.expense,
        onTap: () => showAddExpenseSheet(context),
      ),
      _QuickAction(
        label: GochanoLanguage.text('Medicine', 'ওষুধ'),
        icon: Icons.medication_rounded,
        accent: colors.medicine,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const MedicineScreen()),
        ),
      ),
      _QuickAction(
        label: GochanoLanguage.text('CommuteBD', 'কমিউটবিডি'),
        icon: Icons.directions_bus_rounded,
        accent: colors.commute,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => const CommuteScreen()),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context);
    final colors = context.colors;
    return _AccentRailCard(
      accent: colors.brand,
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: GridView.builder(
              key: ValueKey(_expanded),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: _expanded
                  ? const EdgeInsets.symmetric(vertical: GochanoSpacing.xs)
                  : EdgeInsets.zero,
              itemCount: actions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 88,
                crossAxisSpacing: GochanoSpacing.xxs,
                mainAxisSpacing: GochanoSpacing.xs,
              ),
              itemBuilder: (context, i) => actions[i],
            ),
          ),
          _DragExpandHandle(
            expanded: _expanded,
            onToggle: _toggle,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shared helper widgets
// ══════════════════════════════════════════════════════════════════════════════

class _BentoRow extends StatelessWidget {
  const _BentoRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  static const double _minCardHeight = 120;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minCardHeight),
            child: left,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minCardHeight),
            child: right,
          ),
        ),
      ],
    );
  }
}

class _AccentRailCard extends StatelessWidget {
  const _AccentRailCard({
    required this.accent,
    required this.child,
    this.onTap,
    this.padding,
  });

  final Color accent;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: GochanoRadius.lgAll,
          border: Border.all(
            color: colors.border,
            width: GochanoBorders.hairline,
          ),
        ),
        child: ClipRRect(
          borderRadius: GochanoRadius.lgAll,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 3, child: ColoredBox(color: accent)),
              Expanded(
                child: Padding(
                  padding: padding ?? GochanoSpacing.card,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: GochanoRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: GochanoSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: GochanoRadius.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.type.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.type.cardHeading.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final StudentEventStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, color, icon) = switch (status) {
      StudentEventStatus.pending => (
        GochanoLanguage.text('Pending', 'বাকি'),
        colors.textSecondary,
        Icons.schedule_rounded,
      ),
      StudentEventStatus.completed => (
        GochanoLanguage.text('Done', 'হয়েছে'),
        colors.success,
        Icons.check_circle_rounded,
      ),
      StudentEventStatus.overdue => (
        GochanoLanguage.text('Overdue', 'বাকি'),
        colors.warning,
        Icons.warning_amber_rounded,
      ),
      StudentEventStatus.skipped => (
        GochanoLanguage.text('Skipped', 'বাদ'),
        colors.textTertiary,
        Icons.skip_next_rounded,
      ),
      StudentEventStatus.missed => (
        GochanoLanguage.text('Missed', 'মিস'),
        colors.error,
        Icons.cancel_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xxs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: GochanoRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: context.type.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          amount >= 0
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: GochanoSpacing.xs),
        Text(
          label,
          style: context.type.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            formatTaka(amount),
            style: context.type.cardHeading.copyWith(
              color: color,
              fontFamily: '.SF Pro Text',
              fontFamilyFallback: const ['Roboto', 'sans-serif'],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: GochanoSpacing.xxs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: accent),
              ),
              const SizedBox(height: GochanoSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.type.caption.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragExpandHandle extends StatelessWidget {
  const _DragExpandHandle({
    required this.expanded,
    required this.onToggle,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onToggle,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          width: 36,
          height: 24,
          margin: const EdgeInsets.only(top: GochanoSpacing.xxs),
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: GochanoRadius.lgAll,
          border: Border.all(color: context.colors.border),
        ),
      ),
    );
  }
}

class _ProfileAvatarSmall extends StatelessWidget {
  const _ProfileAvatarSmall({
    required this.photoURL,
    required this.displayName,
    required this.colors,
    required this.type,
  });

  final String? photoURL;
  final String displayName;
  final GochanoColors colors;
  final GochanoTypography type;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoURL != null && photoURL!.isNotEmpty;
    final initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';
    final initialText = Text(
      initial,
      style: type.pageTitle.copyWith(
        color: colors.onBrand,
        fontSize: 14,
      ),
    );

    if (!hasPhoto) return initialText;

    return Image.network(
      photoURL!,
      fit: BoxFit.cover,
      width: 32,
      height: 32,
      semanticLabel: GochanoLanguage.text('Profile photo', 'প্রোফাইল ছবি'),
      errorBuilder: (_, _, _) => initialText,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Helper functions
// ══════════════════════════════════════════════════════════════════════════════

String _timeLabel(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final suffix = GochanoLanguage.text(
    when.hour < 12 ? 'am' : 'pm',
    when.hour < 12 ? 'পূর্বাহ্ণ' : 'অপরাহ্ণ',
  );
  return '$hour:$minute $suffix';
}

/// Formats an amount in Bangladeshi taka.
String formatTaka(double amount) {
  final rounded = amount.roundToDouble();
  final text = (amount - rounded).abs() < 0.005
      ? rounded.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  final parts = text.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '৳${buffer.toString()}${parts.length > 1 ? '.${parts[1]}' : ''}';
}
