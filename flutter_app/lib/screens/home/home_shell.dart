import 'package:flutter/material.dart';

import '../life/life_screen.dart';
import '../profile/profile_screen.dart';
import '../study/ai_assistant_screen.dart';
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

  // Pages and destinations are cached per (role, displayName) so we don't
  // reallocate the lists (or rebuild the same widgets) on every frame.
  // [DashboardScreen] is the only tab that depends on user-specific data
  // (role + displayName); the rest are const-friendly and reused as-is.
  late final List<Widget> _pages;
  late final List<NavigationDestination> _destinations;

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
            const AiAssistantScreen(),
            const LifeScreen(),
            const ProfileScreen(),
          ]
        : <Widget>[
            DashboardScreen(role: widget.role, displayName: widget.displayName),
            const LifeScreen(),
            const TasksScreen(),
            const ProfileScreen(),
          ];

    _destinations = student
        ? const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school_rounded), label: 'Study'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AI'),
            NavigationDestination(icon: Icon(Icons.event_available_outlined), selectedIcon: Icon(Icons.event_available), label: 'Life'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ]
        : const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.event_available_outlined), selectedIcon: Icon(Icons.event_available), label: 'Life'),
            NavigationDestination(icon: Icon(Icons.task_alt_outlined), selectedIcon: Icon(Icons.task_alt), label: 'Tasks'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ];

    if (index >= _pages.length) index = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: _destinations,
      ),
    );
  }
}
