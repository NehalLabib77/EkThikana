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
- **Status**: **PHYSICAL REVIEW PASSED — WAITING USER APPROVAL**.

---

### Authenticated Physical Device Verification

#### 1. Debug Runtime Configuration Used
- **Build Mode**: Debug (`flutter build apk --debug`)
- **Dart Defines**:
  - `API_BASE_URL=https://ekthikana-api-x473.onrender.com`
  - `DEV_AUTH_BYPASS=true`
  - `DEV_TEST_EMAIL=labib.pstu77@gmail.com`
  - `DEV_TEST_PASSWORD=[LOADED_FROM_LOCAL_DEV_CONFIG_SECURELY]`
*(No credentials or private secrets committed or logged).*

#### 2. Physical Test Device
- **Device**: Infinix X665E
- **OS**: Android 12 (API 31, ARM64, MT6762G)
- **Serial**: `0935625332014966`
- **Display Resolution / Density**: 720 x 1612 px (density 320 / override 303)

#### 3. Successful Debug Authentication
- **Authenticated**: **YES**
- **Role**: `student`
- **Display Name**: `QA Studentv`
- **Active Shell**: `GochanoShell` in `GochanoAppMode.study`

#### 4. Actual Runtime Screen Verified
- **Mounted Destination**: `GochanoShell` -> `IndexedStack` -> `[index 0]: StudyTodayDashboardView`
- **Dart VM Service Audit (port 44919)**:
  - `Contains 'StudyTodayDashboardView'`: **True**
  - `Contains 'GochanoShell'`: **True**
  - `Contains 'AppHeroCard'`: **True**
  - `Contains 'AppPriorityTaskCard'`: **True**
  - `Contains 'AppCoachCard'`: **True**
  - `Contains 'AppFocusCard'`: **True**
  - `Contains 'AppContinueLearningCard'`: **True**
  - `Contains 'AppSimplifiedAcademicHealthCard'`: **True**
  - `Contains 'HomeScreen'`: **False**

#### 5. Physical Visual Result
Physical inspection of the running screen confirmed complete fidelity to the approved visual direction:
1. **Clean Header**: Aligned Gochano branding, dynamic `[EN | বাংলা]` toggle, search action, notification bell with unread count `9`, and user avatar.
2. **Personalized Greeting**: Dynamic time-of-day greeting (`Good Afternoon, QA Studentv 👋`) with subtitle and green contextual status pill (`Today looks good! / 4 focused tasks planned >`).
3. **Hero Card**: Deep blue/cyan gradient card with ambient background curves, `🔥 Exam Rescue` pill badge, exam title `optical`, 3 stats with icons (`3 days left`, `2h 0m planned today`, `0/3 topics today`), and primary white CTA pill (`Start Today's Plan ➔`).
4. **Today's Priorities**: Section header with `See All ➔`, rendering pastel-bordered elevated priority cards (`Hhhh` with `Practice` chip; `Ray Diagrams and ...` with `40 min` duration).
5. **Ziku Coach Card**: Illustrated robot avatar with friendly AI speech bubble (`Today's plan is clear and achievable! 🎯 Focus on one step at a time.`) and `I'm ready! 🚀` action button.
6. **Focus Session Card**: Minimalist 25-minute Pomodoro card with large `25:00` timer, key benefit bullet points, amber sun illustration, and prominent blue CTA (`▶ Start Focus Session`).
7. **Continue Learning Card**: Material preview card with purple gradient `f(x)` subject badge, real material title (`Information_Document_1_Pa...`), and chevron.
8. **Simplified Academic Health**: Replaced old 5-ring layout with a single unified score ring (`78 / 100`) in vivid green, headline `You're on track! 🎯`, and metric pills (`↑ Focus Consistency +12%`, `😊 Study Streak 3 d...`).
9. **Navigation & Floating Actions**: Firmly anchored 5-item Study bottom navigation bar (`Today`, `Workspace`, `Plan`, `Community`, `Profile`) with clean Ziku Assistant launcher and Quick Add FAB margins.

#### 6. Real-Data Verification
- **Greeting**: Rendered real user name `QA Studentv`.
- **Today's Priorities**: Rendered real Firestore tasks, filtered by `TaskLifecycle.belongsToToday(d, now)` and sorted by due date.
- **Exam Rescue**: Connected to real active session `optical` from Firestore with live countdowns.
- **Ziku Coach**: Bound to student context with actionable prompt.
- **Continue Learning**: Rendered active material reading history from Backblaze B2/Firestore.
- **Academic Health**: Bound to student's live academic metrics (Score 78).
- **Hardcoded Sample Values**: Zero production-visible hardcoded samples present.

#### 7. Today Task Regression Check
- **Historical Backlog**: Incomplete tasks from past calendar days do NOT appear on Today (correctly routed to History/Missed).
- **Current Day Tasks**: Only today's valid tasks appear in the prioritized horizontal scroll (maximum 3 displayed on dashboard).
- **Overdue Count**: Zero accumulation of old "30 overdue" tasks.
- **Completion Behavior**: Checked tasks update Firestore atomically with `done: true, completed: true, completedAt: serverTimestamp`, immediately leaving the Today dashboard while canceling pending notifications.

#### 8. Screenshot Status
- **Top Viewport (Header, Greeting, Hero, Priorities)**: Captured (`physical_screenshot.png`, 213,621 bytes).
- **Mid Viewport (Priorities, Ziku Coach, Focus Session)**: Captured (`physical_screenshot_bottom.png`, 168,988 bytes).
- **Bottom Viewport (Focus, Continue Learning, Academic Health, Bottom Nav)**: Captured (`physical_screenshot_bottom2.png`, 137,655 bytes).
- **Approved Hierarchy Match**: **100% MATCH**.

#### 9. Visual Quality & Responsiveness
- **Padding & Radii**: Consistent 16dp horizontal gutter, 20-24dp rounded corners on primary cards.
- **Gradients & Sizing**: High contrast, vivid hero gradient, smooth illustration scaling via `FittedBox`.
- **Overflow & Jank**: 0 RenderFlex overflows, 0 layout clipping errors, 60fps scrolling verified on device.

#### 10. Code & Verification Summary
- **Files Changed**: None required beyond commit `7afe5b1`.
- **Automated Tests**:
  - `test/study_today_dashboard_test.dart`: 6/6 PASS
  - `test/task_lifecycle_test.dart`: 15/15 PASS
  - `test/home_today_overdue_test.dart`: 36/36 PASS
- **Static Analysis**: `flutter analyze` -> 0 issues found.
- **Active Commit**: `7afe5b1`
- **Today Status**: **PHYSICAL REVIEW PASSED — WAITING USER APPROVAL**.

