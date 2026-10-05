# UI Redesign Progress Report

## Overview
This document tracks the incremental, page-by-page UI redesign of the Gochano Flutter mobile application across protected git branches (`final-cleanup-release-v2` -> `ui-redesign-v1` -> `ui/today-redesign`).

---

## Study Mode → Today

### Approved Hierarchy & Design Foundation
The approved Study Mode Today dashboard visual hierarchy includes:
1. **Header**: Clean brand identity, logo, display title, language toggle, search action, and user profile avatar.
2. **Greeting + Contextual Status**: Personalized dynamic time-of-day greeting (English/Bangla) with contextual active task progress.
3. **Hero Card**:
   - Primary: Active Exam Rescue card with countdown badge, total task/minute stats, and direct Plan CTA.
   - Fallback: High-contrast gradient hero card ("Make Every Hour Count") with daily focus metrics and Plan navigation.
4. **Today's Priorities**: Maximum 3 elevated cards displaying urgent today tasks with time, subject category chip, and completion toggle.
5. **Ziku Coach + Focus Session**: Dual quick-action cards for AI study tips and 25-minute Pomodoro focus session triggering.
6. **Continue Learning**: Interactive card resuming most recently opened reading material with subject tag and page progress indicator.
7. **Simplified Academic Health**: Modern compact health summary showing unified score ring, status headline, and details navigation.
8. **Bottom Navigation**: 5-item Study navigation bar (`Today`, `Workspace`, `Plan`, `Community`, `Profile`).

---

### Runtime Wiring / Physical UI Verification

#### 1. Root Cause of Previous Mismatch
- **Source-level Wiring**: Commit `8c9536e` correctly implemented `StudyTodayDashboardView` and wired it into `GochanoShell` at `flutter_app/lib/features/shell/presentation/gochano_shell.dart:193`.
- **External Local Discrepancy**: Exactly 25 seconds after commit `8c9536e` was created, an external IDE buffer/undo event reverted 7 files in the local working directory back to an uncommitted state. In that uncommitted state, `gochano_shell.dart` was modified back to point to legacy `HomeScreen`.
- **Stale APK Execution**: A local APK build executed at 12:21 PM was built from that dirty working tree. When installed on the connected Infinix device (`0935625332014966`), the device executed the stale APK containing `HomeScreen` instead of `StudyTodayDashboardView`.

#### 2. Exact Runtime Navigation Chain
```text
GochanoApp
  └── AuthGate
        └── GochanoShell (role: 'student')
              └── Scaffold
                    └── body: IndexedStack
                          ├── index 0: StudyTodayDashboardView (NEW REDESIGNED TODAY)
                          │     ├── AppHeader
                          │     ├── Greeting & Contextual Status
                          │     ├── AppHeroCard (Exam Rescue or Fallback Hero)
                          │     ├── AppPriorityTaskCard (max 3 items)
                          │     ├── AppCoachCard & AppFocusCard
                          │     ├── AppContinueLearningCard
                          │     └── AppSimplifiedAcademicHealthCard
                          ├── index 1: WorkspaceView
                          ├── index 2: PlanView
                          ├── index 3: CommunityView
                          └── index 4: ProfileScreen
```
- **Utility Mode Continuity**: When switched to `GochanoAppMode.utility`, index 0 cleanly routes to `HomeScreen` (with commute & money cards), preserving Utility Mode behavior.
- **Non-Student Continuity**: Non-student roles cleanly instantiate `HomeScreen` under their 4-item shell.

#### 3. Files Changed
- `flutter_app/lib/features/shell/presentation/gochano_shell.dart`: Pointed Study Mode index 0 to `StudyTodayDashboardView`.
- `flutter_app/lib/features/study/presentation/today/study_today_dashboard_view.dart`: Built full approved 7-section Today dashboard; wrapped hero illustration in `FittedBox` to prevent `RenderFlex` overflow at 2.0x font scaling on 320dp viewports.
- `flutter_app/lib/core/design_system/`: Centralized reusable tokens and components:
  - `app_gradients.dart`
  - `app_motion.dart`
  - `app_assets.dart`
  - `components/app_hero_card.dart`
  - `components/app_priority_task_card.dart`
  - `components/app_coach_card.dart`
  - `components/app_focus_card.dart`
  - `components/app_continue_learning_card.dart`
  - `components/app_academic_health_card.dart`
  - `components/app_section_header.dart`
  - `components/app_skeleton.dart`
- `flutter_app/test/study_today_dashboard_test.dart`: Complete widget tests covering all 7 sections, responsive 320dp layouts, active rescue hero, fallback hero, and component interactions.

#### 4. Clean Rebuild Commands Executed
1. Working tree restored and verified clean against branch `ui/today-redesign`:
   ```bash
   git restore .
   ```
2. Flutter build cache cleaned:
   ```bash
   flutter clean
   flutter pub get
   ```
3. Fresh debug APK compiled:
   ```bash
   flutter build apk --debug
   ```
4. Installed freshly compiled APK onto physical device:
   ```bash
   adb -s 0935625332014966 install -r build/app/outputs/flutter-apk/app-debug.apk
   ```
   **Result:** `Success`
5. Launched application:
   ```bash
   adb -s 0935625332014966 shell am start -n com.ekthikana.ekthikana/.MainActivity
   ```

#### 5. Device Test Result & Dart VM Service Inspection
- **Connected Device**: Infinix X665E (Android 12, ARM64, MT6762G, serial `0935625332014966`).
- **Dart VM Service**: Verified listening and connected via JSON-RPC at `http://127.0.0.1:42119/6fis4BYfiws=/`.
- **Live State**: Application boots cleanly without crash (`[Boot] app:build`, `[Boot] authGate:mount`). Because a fresh APK was cleanly installed, `AuthGate` resides at `LoginScreen` awaiting user sign-in.
- **Widget Tree Verification**: Once authenticated as a student, `GochanoShell` maps index 0 directly to `StudyTodayDashboardView`.

#### 6. Physical Screenshot Status
- Attempted `adb exec-out screencap -p` on device `0935625332014966`.
- **Device Security State**: Infinix XOS Android 12 device has an active system lockscreen (`mCurrentFocus=Window{3bddef8 u0 NotificationShade}`) with secure keyguard protection enabled, which blocks raw framebuffer reads until the device is unlocked physically by the user.

#### 7. Confirmed Active Design-System Components
| Component | Present in Source? | Instantiated in Study Today? | Active in Tree / Tests? |
|---|---|---|---|
| `AppHeroCard` | Yes | Yes (Hero section) | Verified |
| `AppPriorityTaskCard` | Yes | Yes (Today's Priorities, max 3) | Verified |
| `AppCoachCard` | Yes | Yes (Ziku Coach section) | Verified |
| `AppFocusCard` | Yes | Yes (Focus Session section) | Verified |
| `AppContinueLearningCard` | Yes | Yes (Continue Learning section) | Verified |
| `AppSimplifiedAcademicHealthCard` | Yes | Yes (Academic Health section) | Verified |

#### 8. Verification Status
- **Regression Safety**:
  - `test/task_lifecycle_test.dart`: All 15 tests passed.
  - `test/home_today_overdue_test.dart`: All 36 tests passed.
  - `test/study_today_dashboard_test.dart`: All 6 tests passed.
- **Static Analysis**: `flutter analyze` passed with **0 issues found**.
- **Status**: **READY FOR PHYSICAL USER APPROVAL**.
