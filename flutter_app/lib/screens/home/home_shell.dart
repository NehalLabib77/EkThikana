import 'package:flutter/material.dart';

import '../groups/groups_screen.dart';
import '../life/life_screen.dart';
import '../profile/profile_screen.dart';
import '../study/study_screen.dart';
import '../tasks/tasks_screen.dart';
import 'dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.role,
    required this.displayName,
  });

  final String role;
  final String displayName;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final student = widget.role == 'student';

    final pages = student
        ? <Widget>[
            DashboardScreen(role: widget.role, displayName: widget.displayName),
            const StudyScreen(),
            const GroupsScreen(),
            const LifeScreen(),
            const ProfileScreen(),
          ]
        : <Widget>[
            DashboardScreen(role: widget.role, displayName: widget.displayName),
            const LifeScreen(),
            const TasksScreen(),
            const ProfileScreen(),
          ];

    final items = student
        ? const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Study'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Groups'),
            NavigationDestination(icon: Icon(Icons.widgets_outlined), selectedIcon: Icon(Icons.widgets), label: 'Life'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ]
        : const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.widgets_outlined), selectedIcon: Icon(Icons.widgets), label: 'Life'),
            NavigationDestination(icon: Icon(Icons.task_alt_outlined), selectedIcon: Icon(Icons.task_alt), label: 'Tasks'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ];

    if (index >= pages.length) index = 0;

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: items,
      ),
    );
  }
}
