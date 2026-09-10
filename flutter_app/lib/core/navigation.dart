import 'package:flutter/material.dart';

/// Canonical student-life areas mapped to the bottom navigation bar.
///
/// The enum order defines the tab order: Today → Study → Money → Commute → Community.
/// Use [tabIndex] for `IndexedStack` / `NavigationBar.selectedIndex`.
enum StudentArea {
  today(0),
  study(1),
  money(2),
  commute(3),
  community(4);

  const StudentArea(this.tabIndex);
  final int tabIndex;

  /// The total number of student bottom-nav destinations.
  static const int count = 5;
}

/// Study sub-tab indices.
///
/// 0 = Workspace (AI, Notes, PDFs, materials)
/// 1 = Plan (Tasks, Assignments, deadlines)
enum StudyTab {
  workspace(0),
  plan(1);

  const StudyTab(this.tabIndex);
  final int tabIndex;
}

/// Typed cross-module navigation destinations.
///
/// Each value maps to exactly one canonical screen or tab.
/// Use [navigate] with a BuildContext and shell callbacks to perform the
/// actual navigation — this avoids magic tab numbers scattered across
/// feature widgets.
enum StudentDestination {
  today,
  studyPlan,
  studyWorkspace,
  money,
  medicine,
  commute,
  community,
  profile,
}

/// Extension that maps destinations to navigation actions.
extension StudentDestinationX on StudentDestination {
  /// Whether this destination is a bottom-tab (vs. a pushed screen).
  bool get isTab {
    switch (this) {
      case StudentDestination.today:
      case StudentDestination.studyPlan:
      case StudentDestination.studyWorkspace:
      case StudentDestination.money:
      case StudentDestination.medicine:
      case StudentDestination.commute:
      case StudentDestination.community:
        return true;
      case StudentDestination.profile:
        return false;
    }
  }

  /// The bottom-nav index for tab destinations.
  int get tabIndex {
    switch (this) {
      case StudentDestination.today:
        return StudentArea.today.tabIndex;
      case StudentDestination.studyPlan:
      case StudentDestination.studyWorkspace:
        return StudentArea.study.tabIndex;
      case StudentDestination.money:
        return StudentArea.money.tabIndex;
      case StudentDestination.medicine:
        return StudentArea.money.tabIndex;
      case StudentDestination.commute:
        return StudentArea.commute.tabIndex;
      case StudentDestination.community:
        return StudentArea.community.tabIndex;
      case StudentDestination.profile:
        return -1;
    }
  }

  /// The Study sub-tab for study destinations, or null.
  int? get studySubTab {
    switch (this) {
      case StudentDestination.studyPlan:
        return StudyTab.plan.tabIndex;
      case StudentDestination.studyWorkspace:
        return StudyTab.workspace.tabIndex;
      default:
        return null;
    }
  }
}

/// Centralised accessor for the single app-wide Navigator key.
///
/// Why this is a function + reset hook instead of a `static final`:
/// a `static final GlobalKey` is allocated **once per process lifetime**.
/// On Flutter hot-restart the old widget tree (and the Navigator it
/// mounted with the static key) is torn down lazily while the new tree
/// is rebuilt against the *same* `GlobalKey` instance. While both
/// trees coexist for a few frames, two `Navigator` widgets are
/// simultaneously associated with the same key, and Flutter throws:
///
///   "Duplicate `GlobalKey<NavigatorState>` detected in widget tree."
///
/// To eliminate that race we:
///   1. Hold the key in a *per cold start* late field ([_navigatorKey]).
///   2. Expose it via [navigatorKey], which allocates the field the
///      first time it is read and returns the same instance thereafter
///      for the rest of that cold start.
///   3. Reset it from `main()` via [resetForColdStart] before the first
///      `runApp` so hot-restart cannot reuse a stale instance.
///
/// This keeps:
///   - exactly one `MaterialApp` / one root `Navigator` (no architectural
///     change),
///   - the same `navigatorKey:` call site in `app.dart`,
///   - the same `AppNavigation.navigatorKey.currentContext` /
///     `.currentState` access pattern used by
///     `NotificationActionHost`,
///   - Firebase auth routing untouched (AuthGate stays inside the same
///     MaterialApp -> Navigator).
class AppNavigation {
  AppNavigation._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// The single Navigator key for the current cold start.
  ///
  /// Allocated lazily on first read so callers that import this file
  /// don't accidentally trigger a key allocation before `main()` has
  /// finished initialising Firebase / notifications.
  static GlobalKey<NavigatorState> get navigatorKey {
    return _navigatorKey ??= GlobalKey<NavigatorState>();
  }

  /// Drop the cached key so the next cold start gets a fresh
  /// `GlobalKey` instance.
  ///
  /// Called from `main()` *before* the first `runApp`. Without this,
  /// a hot-restart on a developer build would reuse the same static
  /// key and trip Flutter's "Duplicate GlobalKey" assertion.
  static void resetForColdStart() {
    _navigatorKey = null;
  }
}
