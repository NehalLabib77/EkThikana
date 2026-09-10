// The Gochano application shell — five student destinations.
//
//   Today | Study | Money | Commute | Community
//
// Profile is accessible from the Today header avatar, NOT from the bottom bar.
// Screens and business logic are NOT deleted.
//
// State between destinations is preserved with an IndexedStack, so switching
// tabs does not reset a half-typed expense or a scrolled material list
// (spec §85).

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/navigation.dart';
import '../../community/presentation/community_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../life/presentation/commute/commute_screen.dart';
import '../../life/presentation/expense/expense_screen.dart';
import '../../study/presentation/ai/ai_assistant_screen.dart';
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
  int _studyTab = 0;

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
          onOpenStudyTab: _openStudyTab,
          onOpenAiAssistant: _openAiAssistant,
        ),
        StudyScreen(initialTab: _studyTab),
        const ExpenseScreen(),
        const CommuteScreen(),
        CommunityScreen(),
      ];
    }

    return [
      HomeScreen(
        role: widget.role,
        displayName: widget.displayName,
        onOpenDestination: _select,
        onOpenStudyTab: _openStudyTab,
        onOpenAiAssistant: _openAiAssistant,
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
          label: GochanoLanguage.text('Today', 'আজ'),
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Study', 'পড়াশোনা'),
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Money', 'টাকা'),
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Commute', 'যাতায়াত'),
          icon: Icons.directions_bus_outlined,
          selectedIcon: Icons.directions_bus_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Community', 'কমিউনিটি'),
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups_rounded,
        ),
      ];
    }

    return [
      _Destination(
        label: GochanoLanguage.text('Today', 'আজ'),
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      _Destination(
        label: GochanoLanguage.text('Money', 'টাকা'),
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

  void _openStudyTab(int tab) {
    setState(() {
      _studyTab = tab;
      _index = StudentArea.study.tabIndex;
    });
  }

  void _openAiAssistant() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
    );
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
