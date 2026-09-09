// Focus Hub — internal sub-tab container for the Focus top-level tab.
//
// Contains:
//   Timer     — the existing FocusView (distraction-free timer)
//   Distraction — the existing DistractionView (screen-time tracking)
//   History   — the existing RewardHistoryView (focus session / reward history)
//
// All three sub-tabs use isScrollable: false for equal-width layout.
// FocusView uses AutomaticKeepAliveClientMixin so the active timer is
// preserved when switching between sub-tabs.

import 'package:flutter/material.dart';

import '../../../../core/localization/gochano_language.dart';
import '../../../focus_rewards/presentation/reward_history_view.dart';
import '../distraction/distraction_view.dart';
import 'focus_view.dart';

class FocusHubView extends StatefulWidget {
  const FocusHubView({super.key});

  @override
  State<FocusHubView> createState() => _FocusHubViewState();
}

class _FocusHubViewState extends State<FocusHubView>
    with SingleTickerProviderStateMixin {
  late final TabController _subTabs;

  @override
  void initState() {
    super.initState();
    _subTabs = TabController(length: 3, vsync: this);
    GochanoLanguage.current.addListener(_onLanguageChange);
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageChange);
    _subTabs.dispose();
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subTabs,
          isScrollable: false,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  GochanoLanguage.text('Timer', 'টাইমার'),
                ),
              ),
            ),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  GochanoLanguage.text('Distraction', 'বিচ্ছিন্নতা'),
                ),
              ),
            ),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  GochanoLanguage.text('History', 'ইতিহাস'),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabs,
            children: const [
              FocusView(),
              DistractionView(),
              RewardHistoryView(),
            ],
          ),
        ),
      ],
    );
  }
}
