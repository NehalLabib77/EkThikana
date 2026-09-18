// Universal Quick Add bottom sheet (Phase 1).
//
// Single consistent launcher for the 6 core creation workflows in the student
// shell. Quick Add contains NO business logic, NO Firestore writes, and NO
// notification scheduling: it is strictly a UI coordinator delegating directly
// to the canonical creation sheets and screens.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../life/presentation/commute/plan_trip_sheet.dart';
import '../../life/presentation/expense/add_expense_sheet.dart';
import '../../life/presentation/medicine/medicine_form_screen.dart';
import '../../study/presentation/notes/note_editor_screen.dart';
import '../../tasks/presentation/add_task_sheet.dart';

/// The 6 canonical Quick Add actions.
enum QuickAddAction {
  task,
  assignment,
  expense,
  medicine,
  planTrip,
  note;

  /// Backward compatibility alias for older tests/references
  static const QuickAddAction trip = QuickAddAction.planTrip;
}

/// Backward compatibility alias for tests and existing references.
typedef QuickActionType = QuickAddAction;

/// Opens the Universal Quick Add bottom sheet.
///
/// Pops ONLY itself and returns the selected [QuickAddAction] (or null if
/// dismissed). Performs NO secondary navigation inside the sheet callback.
/// The parent shell/context MUST launch the selected canonical flow AFTER
/// this Future has fully completed.
Future<QuickAddAction?> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<QuickAddAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => QuickAddSheet(
      onSelectAction: (action) {
        Navigator.of(sheetContext).pop(action);
      },
    ),
  );
}

/// Dispatches a selected [QuickAddAction] to the canonical creation flow.
///
/// This MUST be called from the parent shell AFTER [showQuickAddSheet] has
/// fully closed. Never call this from inside the sheet callback.
Future<void> launchQuickAddAction(
  BuildContext context,
  QuickAddAction action,
) async {
  if (!context.mounted) return;
  switch (action) {
    case QuickAddAction.task:
      await showAddTaskSheet(context, type: 'task');
      break;
    case QuickAddAction.assignment:
      await showAddTaskSheet(context, type: 'assignment');
      break;
    case QuickAddAction.expense:
      await showAddExpenseSheet(context);
      break;
    case QuickAddAction.medicine:
      await Navigator.of(
        context,
      ).push(GochanoRoute.to(builder: (_) => const MedicineFormScreen()));
      break;
    case QuickAddAction.planTrip:
      await showPlanTripSheet(context);
      break;
    case QuickAddAction.note:
      await Navigator.of(
        context,
      ).push(GochanoRoute.to(builder: (_) => const NoteEditorScreen()));
      break;
  }
}

class QuickAddSheet extends StatelessWidget {
  const QuickAddSheet({super.key, required this.onSelectAction});

  final ValueChanged<QuickAddAction> onSelectAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.sm,
          GochanoSpacing.md,
          GochanoSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    GochanoLanguage.text('Quick Add', 'দ্রুত যোগ করুন'),
                    style: type.sectionHeading,
                  ),
                ),
                IconButton(
                  tooltip: GochanoLanguage.text('Close', 'বন্ধ করুন'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.md),

            // 2-Column Action Grid
            Row(
              children: [
                Expanded(
                  child: _QuickAddCard(
                    key: const ValueKey('quick_add_task'),
                    icon: Icons.check_circle_outline_rounded,
                    accentColor: colors.brand,
                    title: GochanoLanguage.text('Task', 'কাজ'),
                    subtitle: GochanoLanguage.text('To-do item', 'করার কাজ'),
                    onTap: () => onSelectAction(QuickAddAction.task),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: _QuickAddCard(
                    key: const ValueKey('quick_add_assignment'),
                    icon: Icons.assignment_outlined,
                    accentColor: colors.brand,
                    title: GochanoLanguage.text('Assignment', 'অ্যাসাইনমেন্ট'),
                    subtitle: GochanoLanguage.text(
                      'Course deadline',
                      'পড়াশোনার ডেডলাইন',
                    ),
                    onTap: () => onSelectAction(QuickAddAction.assignment),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),

            Row(
              children: [
                Expanded(
                  child: _QuickAddCard(
                    key: const ValueKey('quick_add_expense'),
                    icon: Icons.account_balance_wallet_outlined,
                    accentColor: colors.expense,
                    title: GochanoLanguage.text('Expense', 'খরচ'),
                    subtitle: GochanoLanguage.text(
                      'Daily spending',
                      'দৈনিক খরচ',
                    ),
                    onTap: () => onSelectAction(QuickAddAction.expense),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: _QuickAddCard(
                    key: const ValueKey('quick_add_medicine'),
                    icon: Icons.medication_outlined,
                    accentColor: colors.success,
                    title: GochanoLanguage.text('Medicine', 'ওষুধ'),
                    subtitle: GochanoLanguage.text(
                      'Dose & schedule',
                      'ডোজ ও সময়সূচি',
                    ),
                    onTap: () => onSelectAction(QuickAddAction.medicine),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),

            Row(
              children: [
                Expanded(
                  child: _QuickAddCard(
                    key: const ValueKey('quick_add_plan_trip'),
                    icon: Icons.departure_board_rounded,
                    accentColor: colors.commute,
                    title: GochanoLanguage.text(
                      'Plan Trip',
                      'যাত্রা পরিকল্পনা',
                    ),
                    subtitle: GochanoLanguage.text(
                      'Commute reminder',
                      'যাতায়াত রিমাইন্ডার',
                    ),
                    onTap: () => onSelectAction(QuickAddAction.planTrip),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: _QuickAddCard(
                    key: const ValueKey('quick_add_note'),
                    icon: Icons.edit_note_rounded,
                    accentColor: colors.brand,
                    title: GochanoLanguage.text('Note', 'নোট'),
                    subtitle: GochanoLanguage.text('Study notes', 'পড়ার নোট'),
                    onTap: () => onSelectAction(QuickAddAction.note),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddCard extends StatelessWidget {
  const _QuickAddCard({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: GochanoRadius.mdAll,
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: GochanoRadius.mdAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: GochanoSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.sm,
                vertical: GochanoSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: GochanoRadius.smAll,
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: type.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          softWrap: true,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                          softWrap: true,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
