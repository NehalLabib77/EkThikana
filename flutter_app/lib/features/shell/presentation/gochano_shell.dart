// The Gochano application shell — five primary destinations (spec §26).
//
//   Home | Study | Life | Community | Profile
//
// Role note
// ---------
// Gochano has two account roles. `student` gets all five destinations.
// `general` gets four: Study, Study Groups, AI and Materials are all gated
// behind `require_student` on the backend (see `app/core/auth.py`), so a
// general account tapping Study or Community would meet a 403 on every
// action. Showing a destination that can only fail is worse than not showing
// it — spec §90 forbids hiding *broken* features, but this is a working
// feature correctly scoped to an account type, which is different.
//
// State between destinations is preserved with an IndexedStack, so switching
// tabs does not reset a half-typed expense or a scrolled material list
// (spec §85).

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/localization/gochano_language.dart';
import '../../community/presentation/community_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../life/presentation/life_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../study/presentation/study_screen.dart';
import '../../tasks/presentation/tasks_screen.dart';

class GochanoShell extends StatefulWidget {
  const GochanoShell({
    super.key,
    required this.role,
    required this.displayName,
  });

  final String role;
  final String displayName;

  @override
  State<GochanoShell> createState() => _GochanoShellState();
}

class _GochanoShellState extends State<GochanoShell> {
  int _index = 0;

  bool get _isStudent => widget.role == 'student';

  List<_Destination> get _destinations {
    if (_isStudent) {
      return [
        _Destination(
          label: GochanoLanguage.text('Home', 'হোম'),
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          builder: () => HomeScreen(
            role: widget.role,
            displayName: widget.displayName,
            onOpenDestination: _select,
          ),
        ),
        _Destination(
          label: GochanoLanguage.text('Study', 'পড়াশোনা'),
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book_rounded,
          builder: () => const StudyScreen(),
        ),
        _Destination(
          label: GochanoLanguage.text('Life', 'জীবন'),
          icon: Icons.favorite_outline_rounded,
          selectedIcon: Icons.favorite_rounded,
          builder: () => const LifeScreen(),
        ),
        _Destination(
          label: GochanoLanguage.text('Community', 'কমিউনিটি'),
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
          builder: () => const CommunityScreen(),
        ),
        _Destination(
          label: GochanoLanguage.text('Profile', 'প্রোফাইল'),
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          builder: () => ProfileScreen(role: widget.role),
        ),
      ];
    }

    return [
      _Destination(
        label: GochanoLanguage.text('Home', 'হোম'),
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        builder: () => HomeScreen(
          role: widget.role,
          displayName: widget.displayName,
          onOpenDestination: _select,
        ),
      ),
      _Destination(
        label: GochanoLanguage.text('Life', 'জীবন'),
        icon: Icons.favorite_outline_rounded,
        selectedIcon: Icons.favorite_rounded,
        builder: () => const LifeScreen(),
      ),
      _Destination(
        label: GochanoLanguage.text('Tasks', 'কাজ'),
        icon: Icons.check_circle_outline_rounded,
        selectedIcon: Icons.check_circle_rounded,
        builder: () => const TasksScreen(),
      ),
      _Destination(
        label: GochanoLanguage.text('Profile', 'প্রোফাইল'),
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        builder: () => ProfileScreen(role: widget.role),
      ),
    ];
  }

  void _select(int index) {
    final count = _destinations.length;
    if (index < 0 || index >= count || index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    final index = _index.clamp(0, destinations.length - 1);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: IndexedStack(
        index: index,
        children: [for (final d in destinations) d.builder()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
              tooltip: d.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}
