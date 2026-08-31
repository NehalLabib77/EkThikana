import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../services/firestore_service.dart';
import '../../widgets/bento/bento_bar.dart';
import 'dashboard/bento_dashboard_view.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final student = role == 'student';
    final firstName = displayName.trim().isEmpty
        ? 'there'
        : displayName.trim().split(' ').first;

    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        backgroundColor: BentoColors.scaffold(context),
        appBar: _bentoAppBar(context, firstName: firstName),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.ownerStream('tasks'),
          builder: (context, taskSnap) {
            final tasks = taskSnap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            return BentoDashboardView(
              firstName: firstName,
              role: role,
              student: student,
              tasks: tasks,
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _bentoAppBar(
    BuildContext context, {
    required String firstName,
  }) {
    final title = EkLanguage.text('Hi, $firstName', 'হাই, $firstName');
    final subtitle = EkLanguage.text(
      'Your day, in one glance',
      'আপনার দিন, এক নজরে',
    );

    return AppBar(
      backgroundColor: BentoColors.scaffold(context),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      toolbarHeight: 64,
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BentoColors.onTint(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BentoColors.onTintMuted(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ],
      ),
      actions: const [_LanguageToggle(), SizedBox(width: 12)],
    );
  }
}

/// Lightweight language toggle (EN | বাংলা) styled for the bento theme.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final ink = BentoColors.onTint(context);

    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, isBn, _) {
        return Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _choice(context, 'EN', !isBn, () => EkLanguage.bangla.value = false, ink),
              _choice(context, 'বাংলা', isBn, () => EkLanguage.bangla.value = true, ink),
            ],
          ),
        );
      },
    );
  }

  Widget _choice(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
    Color ink,
  ) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? BentoColors.studyAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : ink,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
