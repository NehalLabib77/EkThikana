// HomeShell — role-aware tab host backed by Material 3 NavigationBar.
//
// P2-UX redesign:
//   * The frosted-glass `_BentoFloatingNav` pill is retired in favour of
//     Flutter's `NavigationBar` + `NavigationDestination`. The Material 3
//     surface is accessibility-friendly (Talk-back labels, real hit
//     areas), respects font scale, RTL, and dynamic theme, and uses
//     the app's `colorScheme` rather than bespoke chrome.
//
//   * Tab set is role-aware:
//       Student : Home / Study / Life / Community / Profile
//       General : Home / Life / Community / Profile
//
//   * AIAssistant is no longer a top-level tab — it remains a Study tab
//     tile (P1-3) and `GroupsScreen` (Community) is lifted to top level.
//
// Behavior unchanged:
//   * IndexedStack + setState for tab switching.
//   * Tab order + active index persisted within the widget lifetime.

import 'package:flutter/material.dart';

import '../../widgets/bento/bento_bar.dart';
import '../groups/groups_screen.dart';
import '../life/life_screen.dart';
import '../profile/profile_screen.dart';
import '../study/study_screen.dart';
import '../tasks/tasks_screen.dart';
import 'dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  late final List<Widget> _pages;
  late final List<_NavSpec> _nav;

  @override
  void initState() {
    super.initState();
    _rebuildTabs();
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role ||
        oldWidget.displayName != widget.displayName) {
      _rebuildTabs();
    }
  }

  void _rebuildTabs() {
    final student = widget.role == 'student';
    _pages = student
        ? <Widget>[
            DashboardScreen(role: widget.role, displayName: widget.displayName),
            const StudyScreen(),
            const LifeScreen(),
            const GroupsScreen(),
            const ProfileScreen(),
          ]
        : <Widget>[
            DashboardScreen(role: widget.role, displayName: widget.displayName),
            const LifeScreen(),
            const TasksScreen(),
            const GroupsScreen(),
            const ProfileScreen(),
          ];

    _nav = student
        ? const <_NavSpec>[
            _NavSpec(icon: Icons.home_rounded, label: 'Home', module: 'study', semanticsLabel: 'Home tab'),
            _NavSpec(icon: Icons.menu_book_rounded, label: 'Study', module: 'study', semanticsLabel: 'Study tab'),
            _NavSpec(icon: Icons.event_available_rounded, label: 'Life', module: 'tasks', semanticsLabel: 'Life tab'),
            _NavSpec(icon: Icons.groups_2_rounded, label: 'Community', module: 'social', semanticsLabel: 'Community tab'),
            _NavSpec(icon: Icons.person_rounded, label: 'Profile', module: 'study', semanticsLabel: 'Profile tab'),
          ]
        : const <_NavSpec>[
            _NavSpec(icon: Icons.home_rounded, label: 'Home', module: 'tasks', semanticsLabel: 'Home tab'),
            _NavSpec(icon: Icons.event_available_rounded, label: 'Life', module: 'tasks', semanticsLabel: 'Life tab'),
            _NavSpec(icon: Icons.task_alt_rounded, label: 'Tasks', module: 'tasks', semanticsLabel: 'Tasks tab'),
            _NavSpec(icon: Icons.groups_2_rounded, label: 'Community', module: 'social', semanticsLabel: 'Community tab'),
            _NavSpec(icon: Icons.person_rounded, label: 'Profile', module: 'tasks', semanticsLabel: 'Profile tab'),
          ];

    if (index >= _pages.length) {
      index = _pages.isEmpty ? 0 : _pages.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BentoColors.scaffold(context),
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: _Material3NavBar(
        items: _nav,
        activeIndex: index,
        onSelect: (i) => setState(() => index = i),
      ),
    );
  }
}

class _NavSpec {
  const _NavSpec({
    required this.icon,
    required this.label,
    required this.module,
    required this.semanticsLabel,
  });
  final IconData icon;
  final String label;
  final String module;

  /// Talk-back / a11y label surfaced through `NavigationDestination`.
  final String semanticsLabel;
}

/// Material 3 `NavigationBar` adapter — tints the active destination
/// indicator with the matching `BentoColors.module` accent so the bar
/// feels branded without bespoke chrome.
class _Material3NavBar extends StatelessWidget {
  const _Material3NavBar({
    required this.items,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<_NavSpec> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mod = BentoColors.module(context, 'social');
    final isDark = colorScheme.brightness == Brightness.dark;
    final indicator = isDark
        ? mod.accent.withValues(alpha: 0.22)
        : mod.tint;

    return NavigationBar(
      selectedIndex: activeIndex,
      onDestinationSelected: onSelect,
      backgroundColor: colorScheme.surface,
      indicatorColor: indicator,
      surfaceTintColor: colorScheme.surfaceTint,
      height: 72,
      destinations: [
        for (var i = 0; i < items.length; i++)
          NavigationDestination(
            icon: Icon(items[i].icon),
            selectedIcon: Icon(items[i].icon),
            label: items[i].label,
            tooltip: items[i].semanticsLabel,
          ),
      ],
    );
  }
}
