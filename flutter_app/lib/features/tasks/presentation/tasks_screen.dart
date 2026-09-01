// Tasks as a top-level destination.
//
// General accounts do not get the Study hub (Study, Groups, AI and Materials
// are all behind `require_student` on the backend), so Tasks is promoted to
// its own destination for them. It hosts exactly the same [TasksView] the
// Study hub uses, so there is one task implementation, not two.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import 'tasks_view.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Tasks', 'কাজ'),
        automaticallyImplyLeading: false,
        actions: const [LanguageToggle(), SizedBox(width: GochanoSpacing.xs)],
      ),
      body: const TasksView(),
    );
  }
}
