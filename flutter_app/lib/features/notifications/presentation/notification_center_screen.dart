import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_dates.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../models/local_reminder.dart';
import '../../../services/financial_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/local_reminder_store.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../life/presentation/commute/commute_screen.dart';
import '../../life/presentation/expense/expense_screen.dart';
import '../../life/presentation/medicine/medicine_screen.dart';
import '../../tasks/presentation/tasks_screen.dart';
import 'custom_reminder_sheet.dart';

enum _NotificationFilter { all, pending, completed }

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  _NotificationFilter _selectedFilter = _NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    LocalReminderStore.instance.init();
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

  List<LocalReminder> _filterReminders(List<LocalReminder> reminders) {
    switch (_selectedFilter) {
      case _NotificationFilter.all:
        return reminders;
      case _NotificationFilter.pending:
        return reminders.where((r) => r.isPending).toList();
      case _NotificationFilter.completed:
        return reminders.where((r) => !r.isPending).toList();
    }
  }

  Future<void> _handleAction(LocalReminder reminder, String action) async {
    if (reminder.type == LocalReminderType.task ||
        reminder.type == LocalReminderType.assignment ||
        reminder.type == LocalReminderType.custom) {
      if (action == 'done') {
        await LocalReminderStore.instance.updateStatus(
          reminder.id,
          LocalReminderStatus.completed,
          completedAt: DateTime.now(),
        );
        if (reminder.type == LocalReminderType.custom) {
          await NotificationService.cancelCustomReminder(reminder.id);
        } else {
          await NotificationService.cancelTask(reminder.ownerItemId);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                GochanoLanguage.text(
                  'Marked as done',
                  'সম্পন্ন হিসেবে চিহ্নিত করা হয়েছে',
                ),
              ),
            ),
          );
        }
      }
      return;
    }

    if (reminder.type == LocalReminderType.medicine) {
      final hhmm = reminder.payload['hhmm']?.toString() ?? '08:00';
      final medicineName = reminder.title;
      final quantity =
          (reminder.payload['quantityPerDose'] as num?)?.toDouble() ?? 1;
      final unit = reminder.payload['unit']?.toString() ?? 'tablet';
      final unitPrice =
          (reminder.payload['unitPrice'] as num?)?.toDouble() ?? 0;

      if (action == 'taken') {
        await FinancialService.recordMedicineDose(
          medicineId: reminder.ownerItemId,
          medicineName: medicineName,
          scheduledTime: hhmm,
          date: DateTime.now(),
          status: 'taken',
          actualQuantityTaken: quantity,
          unitPriceSnapshot: unitPrice,
          unit: unit,
        );
        await NotificationService.cancelSameDayMedicineDose(
          reminder.ownerItemId,
          hhmm,
        );
        await LocalReminderStore.instance.updateStatus(
          reminder.id,
          LocalReminderStatus.completed,
          completedAt: DateTime.now(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                GochanoLanguage.text(
                  'Medicine dose marked taken.',
                  'ওষুধ খাওয়া হয়েছে হিসেবে রেকর্ড করা হয়েছে।',
                ),
              ),
            ),
          );
        }
      } else if (action == 'skip') {
        await FinancialService.recordMedicineDose(
          medicineId: reminder.ownerItemId,
          medicineName: medicineName,
          scheduledTime: hhmm,
          date: DateTime.now(),
          status: 'skipped',
          unitPriceSnapshot: unitPrice,
          unit: unit,
        );
        await NotificationService.cancelSameDayMedicineDose(
          reminder.ownerItemId,
          hhmm,
        );
        await LocalReminderStore.instance.updateStatus(
          reminder.id,
          LocalReminderStatus.skipped,
          completedAt: DateTime.now(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                GochanoLanguage.text(
                  'Medicine dose skipped.',
                  'ওষুধটি স্কিপ করা হয়েছে।',
                ),
              ),
            ),
          );
        }
      }
    }
  }

  void _navigateToTarget(LocalReminder reminder) {
    LocalReminderStore.instance.markAsRead(reminder.id);
    switch (reminder.type) {
      case LocalReminderType.task:
      case LocalReminderType.assignment:
        Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const TasksScreen()));
        break;
      case LocalReminderType.medicine:
        Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const MedicineScreen()));
        break;
      case LocalReminderType.expenseDue:
        Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const ExpenseScreen()));
        break;
      case LocalReminderType.commuteTrip:
        Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const CommuteScreen()));
        break;
      case LocalReminderType.custom:
        // Already on notification center
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          'Notification Center',
          'নোটিফিকেশন সেন্টার',
        ),
        actions: [
          IconButton(
            tooltip: GochanoLanguage.text(
              'Add reminder',
              'রিমাইন্ডার যোগ করুন',
            ),
            icon: const Icon(Icons.add_alert_rounded),
            onPressed: () => showCustomReminderSheet(context),
          ),
          IconButton(
            tooltip: GochanoLanguage.text(
              'Mark all as read',
              'সব পঠিত হিসেবে চিহ্নিত করুন',
            ),
            icon: const Icon(Icons.done_all_rounded),
            onPressed: () => LocalReminderStore.instance.markAllAsRead(),
          ),
          const SizedBox(width: GochanoSpacing.xs),
        ],
      ),
      body: ValueListenableBuilder<List<LocalReminder>>(
        valueListenable: LocalReminderStore.instance.remindersNotifier,
        builder: (context, allReminders, _) {
          final filtered = _filterReminders(allReminders);

          return Column(
            children: [
              _buildFilterBar(colors, type),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: GochanoSpacing.scrollBody,
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: GochanoSpacing.xs),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _ReminderCard(
                            reminder: item,
                            onTap: () => _navigateToTarget(item),
                            onAction: (action) => _handleAction(item, action),
                            onDismiss: () =>
                                LocalReminderStore.instance.delete(item.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.xs,
      ),
      child: Row(
        children: [
          _filterChip(
            label: GochanoLanguage.text('All', 'সব'),
            filter: _NotificationFilter.all,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          _filterChip(
            label: GochanoLanguage.text('Upcoming', 'আসন্ন'),
            filter: _NotificationFilter.pending,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          _filterChip(
            label: GochanoLanguage.text('Completed', 'সম্পন্ন'),
            filter: _NotificationFilter.completed,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required _NotificationFilter filter,
  }) {
    final selected = _selectedFilter == filter;
    final colors = context.colors;

    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() => _selectedFilter = filter),
      selectedColor: colors.brand.withValues(alpha: 0.15),
      checkmarkColor: colors.brand,
      labelStyle: context.type.caption.copyWith(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? colors.brand : colors.textSecondary,
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      illustration: GochanoArt.featureProfile,
      title: _selectedFilter == _NotificationFilter.completed
          ? GochanoLanguage.text(
              'No completed reminders',
              'কোনো সম্পন্ন রিমাইন্ডার নেই',
            )
          : GochanoLanguage.text(
              'All caught up!',
              'সব নোটিফিকেশন দেখা হয়েছে!',
            ),
      message: _selectedFilter == _NotificationFilter.completed
          ? GochanoLanguage.text(
              'Reminders you complete or skip will appear here.',
              'যে রিমাইন্ডারগুলো সম্পন্ন বা স্কিপ করবেন তা এখানে দেখাবে।',
            )
          : GochanoLanguage.text(
              'Your scheduled offline reminders and alerts will appear here.',
              'আপনার নির্ধারিত অফলাইন রিমাইন্ডার ও অ্যালার্ট এখানে দেখা যাবে।',
            ),
      actionLabel: GochanoLanguage.text(
        'Create Reminder',
        'রিমাইন্ডার তৈরি করুন',
      ),
      onAction: () => showCustomReminderSheet(context),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onTap,
    required this.onAction,
    required this.onDismiss,
  });

  final LocalReminder reminder;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final (icon, badgeLabel, badgeColor) = _badgeInfo(reminder, colors);

    return Dismissible(
      key: ValueKey(reminder.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: GochanoSpacing.md),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.8),
          borderRadius: GochanoRadius.mdAll,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Container(
          decoration: BoxDecoration(
            color: reminder.isRead
                ? colors.surface
                : colors.brand.withValues(alpha: 0.04),
            borderRadius: GochanoRadius.mdAll,
            border: Border.all(
              color: reminder.isRead
                  ? colors.border
                  : colors.brand.withValues(alpha: 0.3),
              width: reminder.isRead ? 1 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(GochanoSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: GochanoRadius.smAll,
                    ),
                    child: Icon(icon, color: badgeColor, size: 20),
                  ),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.12),
                                borderRadius: GochanoRadius.smAll,
                              ),
                              child: Text(
                                badgeLabel,
                                style: type.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatReminderTimestamp(reminder.scheduledAt),
                              style: type.caption.copyWith(
                                fontSize: 11,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reminder.title,
                          style: type.body.copyWith(
                            fontWeight: reminder.isRead
                                ? FontWeight.w600
                                : FontWeight.bold,
                            color: colors.textPrimary,
                            decoration: reminder.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (reminder.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            reminder.body,
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (reminder.isPending) ...[
                const SizedBox(height: GochanoSpacing.xs),
                _buildActionButtons(context, colors),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, GochanoColors colors) {
    if (reminder.type == LocalReminderType.medicine) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => onAction('skip'),
            child: Text(
              GochanoLanguage.text('Skip', 'স্কিপ'),
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => onAction('taken'),
            child: Text(GochanoLanguage.text('Taken', 'খেয়েছি')),
          ),
        ],
      );
    }

    if (reminder.type == LocalReminderType.task ||
        reminder.type == LocalReminderType.assignment ||
        reminder.type == LocalReminderType.custom) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text(GochanoLanguage.text('Mark Done', 'সম্পন্ন করুন')),
            onPressed: () => onAction('done'),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  static (IconData, String, Color) _badgeInfo(
    LocalReminder reminder,
    GochanoColors colors,
  ) {
    switch (reminder.type) {
      case LocalReminderType.task:
        return (
          Icons.task_alt_rounded,
          GochanoLanguage.text('Task', 'কাজ'),
          colors.study,
        );
      case LocalReminderType.assignment:
        return (
          Icons.assignment_rounded,
          GochanoLanguage.text('Assignment', 'অ্যাসাইনমেন্ট'),
          colors.brand,
        );
      case LocalReminderType.medicine:
        return (
          Icons.medication_rounded,
          GochanoLanguage.text('Medicine', 'ওষুধ'),
          colors.warning,
        );
      case LocalReminderType.expenseDue:
        return (
          Icons.attach_money_rounded,
          GochanoLanguage.text('Due Payment', 'বাকি টাকা'),
          colors.error,
        );
      case LocalReminderType.commuteTrip:
        return (
          Icons.directions_bus_rounded,
          GochanoLanguage.text('Trip', 'ভ্রমণ'),
          colors.success,
        );
      case LocalReminderType.custom:
        return (
          Icons.notifications_active_rounded,
          GochanoLanguage.text('Reminder', 'রিমাইন্ডার'),
          colors.brand,
        );
    }
  }

  static String _formatReminderTimestamp(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${GochanoLanguage.text("Today", "আজ")} • ${formatClock12(dt)}';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day) {
      return '${GochanoLanguage.text("Tomorrow", "আগামীকাল")} • ${formatClock12(dt)}';
    }
    return '${formatShortDate(dt)} • ${formatClock12(dt)}';
  }
}
