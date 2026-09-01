// Study — the academic centre of Gochano (spec §29).
//
//   Workspace  Semester → Subject → Materials, plus recent materials surfaced
//              at the top so the common case is one tap, not three (spec §29).
//   Tasks      Today / Upcoming / Completed.
//   Planner    Study sessions on an agenda.
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
import '../../tasks/presentation/tasks_view.dart';
import '../../search/presentation/universal_search_screen.dart';
import 'ai/ai_assistant_screen.dart';
import 'focus/focus_view.dart';
import 'planner/planner_view.dart';
import 'workspace/workspace_view.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
            onPressed: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
            ),
          ),
          const LanguageToggle(),
          const SizedBox(width: GochanoSpacing.xs),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: GochanoLanguage.text('Workspace', 'ওয়ার্কস্পেস')),
            Tab(text: GochanoLanguage.text('Tasks', 'কাজ')),
            Tab(text: GochanoLanguage.text('Planner', 'পরিকল্পনা')),
            Tab(text: GochanoLanguage.text('Focus', 'ফোকাস')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          WorkspaceView(),
          TasksView(),
          PlannerView(),
          FocusView(),
        ],
      ),
    );
  }
}
