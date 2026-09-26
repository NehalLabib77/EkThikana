// The Gochano application shell — dynamic primary destinations based on App Mode.
//
// In Study Mode (Student):
//   Today | Workspace | Plan | Community | Profile
//
// In Utility Mode (Student):
//   Today | Commute | Money | Profile
//
// General account:
//   Home | Life | Tasks | Profile
//
// State between destinations is preserved with an IndexedStack, so switching
// tabs does not reset user progress. Switching modes safely resets to index 0 (Today).

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../core/settings/gochano_app_mode.dart';
import '../../home/presentation/home_screen.dart';
import '../../life/presentation/life_screen.dart';
import '../../life/presentation/commute/commute_screen.dart';
import '../../life/presentation/expense/expense_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../profile/presentation/app_mode_selector_sheet.dart';
import '../../study/presentation/workspace/workspace_view.dart';
import '../../study/presentation/planner/plan_view.dart';
import '../../community/presentation/community_view.dart';
import '../../tasks/presentation/tasks_screen.dart';
import '../../../services/notification_service.dart';
import 'quick_add_sheet.dart';

class GochanoShell extends StatefulWidget {
  const GochanoShell({
    super.key,
    required this.role,
    required this.displayName,
    this.pagesBuilder,
    this.pagesWithNavigationBuilder,
  });

  final String role;
  final String displayName;

  /// Optional factory callback for injecting test stub pages in widget tests.
  final List<Widget> Function(BuildContext context, GochanoAppMode mode)?
  pagesBuilder;

  /// Optional factory callback for injecting test stub pages with navigation callback.
  final List<Widget> Function(
    BuildContext context,
    GochanoAppMode mode,
    ValueChanged<int> onOpenDestination,
  )?
  pagesWithNavigationBuilder;

  @override
  State<GochanoShell> createState() => _GochanoShellState();
}

class _GochanoShellState extends State<GochanoShell> {
  int _index = 0;

  bool get _isStudent => widget.role == 'student';

  @override
  void initState() {
    super.initState();
    GochanoLanguage.current.addListener(_onLanguageOrModeChange);
    GochanoAppModePreferences.current.addListener(_onAppModeChange);

    NotificationService.reconcileFromFirestore().catchError((_) {
      return Future<void>.value();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDiscoveryNotice();
    });
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageOrModeChange);
    GochanoAppModePreferences.current.removeListener(_onAppModeChange);
    super.dispose();
  }

  void _onLanguageOrModeChange() {
    if (mounted) setState(() {});
  }

  void _onAppModeChange() {
    if (mounted) {
      setState(() {
        _index = 0; // Safely reset to Today/Home to prevent out-of-range errors
      });
    }
  }

  Future<void> _checkDiscoveryNotice() async {
    if (!mounted || !_isStudent) return;
    final isDiscovered = await GochanoAppModePreferences.isDiscovered();
    if (!isDiscovered && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          content: Text(
            GochanoLanguage.text(
              'Gochano now has Study and Utility modes. Change anytime from Profile Settings.',
              'গোছানো-তে এখন স্টাডি ও ইউটিলিটি মোড রয়েছে। প্রোফাইল সেটিংস থেকে যেকোনো সময় পরিবর্তন করতে পারবেন।',
            ),
          ),
          action: SnackBarAction(
            label: GochanoLanguage.text('Change', 'পরিবর্তন করুন'),
            onPressed: () {
              GochanoAppModePreferences.markDiscovered();
              showAppModeSelectorSheet(context);
            },
          ),
        ),
      );
      await GochanoAppModePreferences.markDiscovered();
    }
  }

  void _handleDestinationFromHome(int requestedIndex) {
    if (!_isStudent) {
      _select(requestedIndex);
      return;
    }

    final mode = GochanoAppModePreferences.current.value;
    if (mode == GochanoAppMode.study) {
      if (requestedIndex == 1) {
        _select(1); // Workspace tab
      } else if (requestedIndex == 2) {
        _select(2); // Plan tab
      } else {
        _select(requestedIndex);
      }
    } else {
      // Utility Mode: 0 -> Today, 1 -> Commute, 2 -> Money, 3 -> Profile
      if (requestedIndex == 1) {
        // Study requested from utility home
        Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const WorkspaceView()));
      } else if (requestedIndex == 2) {
        _select(1); // Commute tab
      } else if (requestedIndex == 3) {
        _select(2); // Money tab
      } else {
        _select(requestedIndex);
      }
    }
  }

  List<Widget> _buildPages(GochanoAppMode mode) {
    if (widget.pagesWithNavigationBuilder != null) {
      return widget.pagesWithNavigationBuilder!(
        context,
        mode,
        _handleDestinationFromHome,
      );
    }
    if (widget.pagesBuilder != null) {
      return widget.pagesBuilder!(context, mode);
    }

    if (!_isStudent) {
      return [
        HomeScreen(
          role: widget.role,
          displayName: widget.displayName,
          onOpenDestination: _handleDestinationFromHome,
          onOpenProfile: () => Navigator.of(context).push(
            GochanoRoute.to(builder: (_) => ProfileScreen(role: widget.role)),
          ),
        ),
        const LifeScreen(),
        const TasksScreen(),
        ProfileScreen(role: widget.role),
      ];
    }

    if (mode == GochanoAppMode.study) {
      return [
        HomeScreen(
          role: widget.role,
          displayName: widget.displayName,
          onOpenDestination: _handleDestinationFromHome,
          onOpenProfile: () => Navigator.of(context).push(
            GochanoRoute.to(builder: (_) => ProfileScreen(role: widget.role)),
          ),
        ),
        const WorkspaceView(),
        const PlanView(),
        const CommunityView(),
        ProfileScreen(role: widget.role),
      ];
    }

    // Utility Mode
    return [
      HomeScreen(
        role: widget.role,
        displayName: widget.displayName,
        onOpenDestination: _handleDestinationFromHome,
        onOpenProfile: () => Navigator.of(context).push(
          GochanoRoute.to(builder: (_) => ProfileScreen(role: widget.role)),
        ),
      ),
      const CommuteScreen(),
      const ExpenseScreen(),
      ProfileScreen(role: widget.role),
    ];
  }

  List<_Destination> _buildDestinations(GochanoAppMode mode) {
    if (!_isStudent) {
      return [
        _Destination(
          label: GochanoLanguage.text('Home', 'হোম'),
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Life', 'জীবন'),
          icon: Icons.favorite_outline_rounded,
          selectedIcon: Icons.favorite_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Tasks', 'কাজ'),
          icon: Icons.check_circle_outline_rounded,
          selectedIcon: Icons.check_circle_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Profile', 'প্রোফাইল'),
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
      ];
    }

    if (mode == GochanoAppMode.study) {
      return [
        _Destination(
          label: GochanoLanguage.text('Today', 'আজ'),
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Workspace', 'ওয়ার্কস্পেস'),
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Plan', 'পরিকল্পনা'),
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Community', 'কমিউনিটি'),
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
        ),
        _Destination(
          label: GochanoLanguage.text('Profile', 'প্রোফাইল'),
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
      ];
    }

    // Utility Mode
    return [
      _Destination(
        label: GochanoLanguage.text('Today', 'আজ'),
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      _Destination(
        label: GochanoLanguage.text('Commute', 'যাতায়াত'),
        icon: Icons.directions_transit_outlined,
        selectedIcon: Icons.directions_transit_rounded,
      ),
      _Destination(
        label: GochanoLanguage.text('Money', 'টাকা'),
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
      ),
      _Destination(
        label: GochanoLanguage.text('Profile', 'প্রোফাইল'),
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
      ),
    ];
  }

  void _select(int index) {
    final mode = GochanoAppModePreferences.current.value;
    final destinations = _buildDestinations(mode);
    if (index < 0 || index >= destinations.length || index == _index) return;
    setState(() => _index = index);
  }

  Future<void> _openQuickAdd() async {
    final action = await showQuickAddSheet(context);
    if (!mounted || action == null) return;
    await launchQuickAddAction(context, action);
  }

  @override
  Widget build(BuildContext context) {
    final mode = GochanoAppModePreferences.current.value;
    final destinations = _buildDestinations(mode);
    final pages = _buildPages(mode);
    final clampedIndex = _index.clamp(0, destinations.length - 1);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: IndexedStack(index: clampedIndex, children: pages),
      floatingActionButton: _isStudent
          ? FloatingActionButton(
              key: const ValueKey('universal_quick_add_fab'),
              heroTag: 'universal_quick_add_fab',
              tooltip: GochanoLanguage.text('Quick Add', 'দ্রুত যোগ করুন'),
              onPressed: _openQuickAdd,
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: clampedIndex,
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
