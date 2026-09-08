// The Gochano application shell — four primary destinations.
//
//   Home | Study | Community | Expense
//
// Life and Profile are removed from the bottom navigation bar. Their
// features are now surfaced via Home shortcuts (Medicine, CommuteBD, Profile).
// Screens and business logic are NOT deleted.
//
// State between destinations is preserved with an IndexedStack, so switching
// tabs does not reset a half-typed expense or a scrolled material list
// (spec §85).

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/localization/gochano_language.dart';
import '../../community/presentation/community_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../life/presentation/expense/expense_screen.dart';
import '../../study/presentation/study_screen.dart';

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

  @override
  void initState() {
    super.initState();
    GochanoLanguage.current.addListener(_onLanguageChange);
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageChange);
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  List<Widget> _buildPages() {
    if (_isStudent) {
      return [
        HomeScreen(
          role: widget.role,
          displayName: widget.displayName,
          onOpenDestination: _select,
        ),
        StudyScreen(),
        CommunityScreen(),
        const ExpenseScreen(),
      ];
    }

    return [
      HomeScreen(
        role: widget.role,
        displayName: widget.displayName,
        onOpenDestination: _select,
      ),
      const ExpenseScreen(),
    ];
  }

  /// Destinations are rebuilt on every [build] call so that navigation
  /// labels pick up the current language.
  List<_Destination> _buildDestinations() {
    if (_isStudent) {
      return [
        _Destination(
          label: GochanoLanguage.text('Home', 'হোম'),
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Study', 'পড়াশোনা'),
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Community', 'কমিউনিটি'),
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Expense', 'খরচ'),
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
        ),
      ];
    }

    return [
      _Destination(
        label: GochanoLanguage.text('Home', 'হোম'),
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      _Destination(
        label: GochanoLanguage.text('Expense', 'খরচ'),
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
      ),
    ];
  }

  void _select(int index) {
    final count = _buildDestinations().length;
    if (index < 0 || index >= count || index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _buildDestinations();
    final index = _index.clamp(0, destinations.length - 1);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: IndexedStack(index: index, children: _buildPages()),
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
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
