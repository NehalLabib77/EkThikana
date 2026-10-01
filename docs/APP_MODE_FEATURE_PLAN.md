# Gochano App Mode Switching - Approved Feature Plan

**Feature:** App Mode Switching (Study Mode & Utility Mode)
**Architecture Level:** Client-side presentation preference
**Status:** Approved & Implemented (Phases A through F)

---

## 1. Core Architecture Principles

1. **One Unified Application:**
   - NOT two separate applications.
   - NOT a new backend architecture or state-management overhaul.
   - Preserves all Firestore collections, documents, security rules, and schemas.
   - Preserves all API contracts, authentication flows, and business logic.
   - Zero user data deleted on mode switch.

2. **Client-Side Preference:**
   - Stored in local SharedPreferences under canonical key gochano.appMode.
   - Asynchronously loaded during bootstrap in lib/main.dart before
unApp().
   - Unknown, corrupted, or missing values safely default to GochanoAppMode.study.
   - Zero network, Firebase Auth, or Firestore dependencies to switch or restore modes.

---

## 2. Final Approved Navigation Structures

### Study Mode (5 destinations)
1. **Today:** Academic assignments, upcoming deadlines, academic progress, recent study materials.
2. **Workspace:** Study materials, notes, course resources.
3. **Plan:** Academic timeline, planner, calendar, and task lists.
4. **Community:** Classmates, study groups, discussions.
5. **Profile:** Account management, settings, App Mode selector.

### Utility Mode (4 destinations)
1. **Today:** Upcoming trips, commute quick actions, wallet balance, today expenses.
2. **Commute:** Route estimators, transit schedules, trip planning.
3. **Money:** Expense logs, budget summaries, financial ledgers.
4. **Profile:** Account management, settings, App Mode selector.

### Non-Student / General Role
- Unaffected: Invariant 4 destinations (Home, Life, Tasks, Profile).
- No universal quick-add FAB; no App Mode selector in profile settings.

---

## 3. Mode-Aware Today / Home Screen

- Single unified HomeScreen responding reactively via ValueListenableBuilder<GochanoAppMode>.
- **Study Mode Today:**
  - Tasks & assignments (_TodaysTasksCard)
  - Study progress (_StudyProgressCard)
  - Recent study materials (_RecentMaterialsCard)
  - No primary Commute or Money cards.
- **Utility Mode Today:**
  - Commute & trip info (_CommuteCard)
  - Expense summary & wallet (_MoneyCard)
  - No primary study, materials, or medicine cards.
  - Medicine remains accessible via canonical routes, notifications, and search.

---

## 4. Mode-Aware Quick Add Filtering

- **Study Mode Actions:**
  1. Task (quick_add_task)
  2. Assignment (quick_add_assignment)
  3. Note (quick_add_note)
- **Utility Mode Actions:**
  1. Expense (quick_add_expense)
  2. Plan Trip (quick_add_commute)
- **Integrity:**
  - All existing creation flows remain functional throughout the app.
  - Filtering applies exclusively to the surfaced actions in the universal Quick Add sheet.

---

## 5. Profile Settings Selector

- Located in Profile -> Settings -> App Mode.
- Staged selection pattern: selection updates radio button preview immediately; changes persist to SharedPreferences only upon tapping **Save Mode**.
- Dismissing without save discards staging.
- Save immediately updates active shell and returns to Today (index 0) safely avoiding any range errors.

---

## 6. One-Time Discovery Notice

- Displayed once on first launch after feature rollout for student accounts.
- Dismissal/action sets gochano.appMode.discovered: true in SharedPreferences.
- Never displays again after dismissal or restart.
- English: 'Gochano now has Study and Utility modes. Change anytime from Profile Settings.' (Action: 'Change')
- Bengali: 'গোছানো-তে এখন স্টাডি ও ইউটিলিটি মোড রয়েছে। প্রোফাইল সেটিংস থেকে যেকোনো সময় পরিবর্তন করতে পারবেন।' (Action: 'পরিবর্তন করুন')
