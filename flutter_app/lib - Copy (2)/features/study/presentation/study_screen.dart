// Study — the academic centre of Gochano (spec §29).
//
//   Workspace  Semester → Subject → Materials, plus recent materials surfaced
//              at the top so the common case is one tap, not three (spec §29).
//   Plan       Combined dashboard: schedule, deadlines, tasks, reminders,
//              and study goal — the single screen for "what now?"
//   Focus      A distraction-free timer.
//
// Groups are not a fifth tab here. They are the Community destination in the
// bottom bar; putting them in both places would be the duplication spec §86
// asks to remove.
//
// AI is an app-bar action rather than a tab, because it is contextual: the
// useful entry points are "ask about *this* material" from the reader and a
// general question from here (spec §34).

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import '../../search/presentation/universal_search_screen.dart';
import 'ai/ai_assistant_screen.dart';
import 'distraction/distraction_view.dart';
import 'focus/focus_view.dart';
import 'planner/plan_view.dart';
import 'workspace/workspace_view.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, this.initialTab = 0});

  /// Initial tab index. Tab 1 = Plan.
  final int initialTab;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    GochanoLanguage.current.addListener(_onLanguageChange);
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageChange);
    _tabs.dispose();
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Study', 'পড়াশোনা'),
        automaticallyImplyLeading: false,
        actions: [
          IconActionButton(
            icon: Icons.search_rounded,
            label: GochanoLanguage.text('Search', 'অনুসন্ধান'),
            onPressed: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const UniversalSearchScreen()),
            ),
          ),
          IconActionButton(
            icon: Icons.auto_awesome_outlined,
            label: GochanoLanguage.text('Ask AI', 'এআই কে জিজ্ঞাসা'),
            onPressed: () => Navigator.of(
              context,
            ).push(GochanoRoute.to(builder: (_) => const AiAssistantScreen())),
          ),
          const LanguageToggle(),
          const SizedBox(width: GochanoSpacing.xs),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          tabs: [
            Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(GochanoLanguage.text('Workspace', 'ওয়ার্কস্পেস')))),
            Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(GochanoLanguage.text('Plan', 'পরিকল্পনা')))),
            Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(GochanoLanguage.text('Focus', 'ফোকাস')))),
            Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(GochanoLanguage.text('Distraction', 'বিচ্ছিন্নতা')))),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [WorkspaceView(), PlanView(), FocusView(), DistractionView()],
      ),
    );
  }
}
