import 'package:flutter/material.dart';

import '../core/design_system/gochano_colors.dart';
import '../core/design_system/gochano_spacing.dart';
import '../core/design_system/gochano_typography.dart';
import '../core/localization/gochano_dates.dart';
import '../core/localization/gochano_language.dart';
import '../services/sync_coordinator.dart';
import '../shared/widgets/gochano_controls.dart';

/// Opens the Sync & Offline Status modal bottom sheet.
Future<void> showSyncStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => const SyncStatusSheet(),
  );
}

class SyncStatusSheet extends StatefulWidget {
  const SyncStatusSheet({super.key});

  @override
  State<SyncStatusSheet> createState() => _SyncStatusSheetState();
}

class _SyncStatusSheetState extends State<SyncStatusSheet> {
  bool _syncing = false;
  String? _syncMessage;

  Future<void> _handleSyncNow() async {
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });

    final success = await SyncCoordinator.instance.syncNow();
    if (!mounted) return;

    setState(() {
      _syncing = false;
      if (success) {
        _syncMessage = GochanoLanguage.text(
          'All changes synchronized successfully.',
          'সব পরিবর্তন সফলভাবে সিঙ্ক হয়েছে।',
        );
      } else {
        _syncMessage =
            SyncCoordinator.instance.syncState.value.errorMessage ??
            GochanoLanguage.text(
              'Could not sync. Check internet connection.',
              'সিঙ্ক করা যায়নি। ইন্টারনেট সংযোগ পরীক্ষা করুন।',
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return ValueListenableBuilder<SyncState>(
      valueListenable: SyncCoordinator.instance.syncState,
      builder: (context, state, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GochanoSpacing.lg,
              0,
              GochanoSpacing.lg,
              GochanoSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & status badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          GochanoLanguage.text(
                            'Sync & Offline',
                            'সিঙ্ক ও অফলাইন',
                          ),
                          style: type.pageTitle,
                        ),
                      ),
                      _StatusBadge(state: state),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    state.isOnline
                        ? GochanoLanguage.text(
                            'Connected. Local changes sync automatically.',
                            'সংযুক্ত আছেন। লোকাল পরিবর্তন স্বয়ংক্রিয়ভাবে সিঙ্ক হবে।',
                          )
                        : GochanoLanguage.text(
                            'Offline. You can keep creating tasks, expenses, and reminders.',
                            'অফলাইনে আছেন। আপনি কাজ, খরচ ও রিমাইন্ডার তৈরি চালিয়ে যেতে পারেন।',
                          ),
                    style: type.bodySecondary,
                  ),
                  if (state.lastSyncTime != null) ...[
                    const SizedBox(height: GochanoSpacing.xxs),
                    Text(
                      GochanoLanguage.text(
                        'Last synced: ${formatClock12(state.lastSyncTime!)}',
                        'সর্বশেষ সিঙ্ক: ${formatClock12(state.lastSyncTime!)}',
                      ),
                      style: type.caption.copyWith(color: colors.textTertiary),
                    ),
                  ],
                  const SizedBox(height: GochanoSpacing.md),

                  // Pending Queue section
                  if (state.pendingItems.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: colors.warning,
                        ),
                        const SizedBox(width: GochanoSpacing.xxs),
                        Text(
                          GochanoLanguage.text(
                            'Waiting to sync (${state.pendingCount})',
                            'সিঙ্ক অপেক্ষায় (${GochanoLanguage.toBanglaDigits(state.pendingCount)})',
                          ),
                          style: type.sectionHeading.copyWith(
                            color: colors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: GochanoSpacing.xs),
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: state.pendingItems.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          thickness: 1,
                          color: colors.border,
                        ),
                        itemBuilder: (context, index) {
                          final item = state.pendingItems[index];
                          return _PendingItemTile(item: item);
                        },
                      ),
                    ),
                    const SizedBox(height: GochanoSpacing.md),
                  ],

                  // Offline capabilities breakdown
                  _OfflineCapabilitiesCard(),
                  const SizedBox(height: GochanoSpacing.md),

                  // Sync feedback message if any
                  if (_syncMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(GochanoSpacing.xs),
                      margin: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: colors.brand,
                          ),
                          const SizedBox(width: GochanoSpacing.xs),
                          Expanded(
                            child: Text(
                              _syncMessage!,
                              style: type.bodySecondary.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Action button: Sync now
                  PrimaryButton(
                    key: const ValueKey('sync_now_button'),
                    label: GochanoLanguage.text('Sync now', 'সিঙ্ক করুন'),
                    icon: Icons.sync_rounded,
                    busy: _syncing,
                    busyLabel: GochanoLanguage.text('Syncing…', 'সিঙ্ক হচ্ছে…'),
                    onPressed: (!state.isOnline || _syncing)
                        ? null
                        : _handleSyncNow,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (state.status) {
      case SyncStatus.synced:
        bg = colors.success.withValues(alpha: 0.12);
        fg = colors.success;
        label = GochanoLanguage.text('Synced', 'সিঙ্ক সম্পন্ন');
        icon = Icons.cloud_done_rounded;
        break;
      case SyncStatus.offline:
        bg = colors.warning.withValues(alpha: 0.15);
        fg = colors.warning;
        label = GochanoLanguage.text('Offline', 'অফলাইন');
        icon = Icons.cloud_off_rounded;
        break;
      case SyncStatus.pending:
        bg = colors.warning.withValues(alpha: 0.15);
        fg = colors.warning;
        final bnCount = GochanoLanguage.toBanglaDigits(state.pendingCount);
        label = GochanoLanguage.text(
          '${state.pendingCount} pending',
          '$bnCountটি অপেক্ষায়',
        );
        icon = Icons.sync_problem_rounded;
        break;
      case SyncStatus.syncing:
        bg = colors.brand.withValues(alpha: 0.12);
        fg = colors.brand;
        label = GochanoLanguage.text('Syncing…', 'সিঙ্ক হচ্ছে…');
        icon = Icons.sync_rounded;
        break;
      case SyncStatus.error:
        bg = colors.error.withValues(alpha: 0.12);
        fg = colors.error;
        label = GochanoLanguage.text('Paused', 'স্থগিত');
        icon = Icons.error_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: type.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingItemTile extends StatelessWidget {
  const _PendingItemTile({required this.item});

  final SyncPendingItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    IconData icon;
    String categoryLabel;
    switch (item.type) {
      case 'task':
        icon = Icons.check_circle_outline_rounded;
        categoryLabel = GochanoLanguage.text('Task', 'কাজ');
        break;
      case 'medicine':
        icon = Icons.medication_outlined;
        categoryLabel = GochanoLanguage.text('Medicine', 'ওষুধ');
        break;
      case 'expense':
        icon = Icons.receipt_long_rounded;
        categoryLabel = GochanoLanguage.text('Expense', 'খরচ');
        break;
      case 'trip':
        icon = Icons.directions_bus_outlined;
        categoryLabel = GochanoLanguage.text('Trip', 'যাত্রা');
        break;
      default:
        icon = Icons.edit_note_rounded;
        categoryLabel = GochanoLanguage.text('Item', 'আইটেম');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.sm,
        vertical: GochanoSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.textSecondary),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  style: type.body.copyWith(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  categoryLabel,
                  style: type.caption.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              GochanoLanguage.text('Local', 'লোকাল'),
              style: type.caption.copyWith(
                color: colors.warning,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineCapabilitiesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text('Feature Availability', 'সুবিধাসমূহের বিবরণ'),
            style: type.sectionHeading.copyWith(
              fontSize: 14,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          _CapabilityRow(
            icon: Icons.check_circle_rounded,
            color: colors.success,
            title: GochanoLanguage.text('Works offline', 'অফলাইনে কার্যকর'),
            subtitle: GochanoLanguage.text(
              'Tasks, Medicines, Expenses, Saved Trips, Local Reminders',
              'কাজ, ওষুধ, খরচ, সংরক্ষিত যাত্রা, লোকাল রিমাইন্ডার',
            ),
          ),
          const SizedBox(height: GochanoSpacing.xs),
          _CapabilityRow(
            icon: Icons.wifi_rounded,
            color: colors.brand,
            title: GochanoLanguage.text(
              'Requires internet',
              'ইন্টারনেট প্রয়োজন',
            ),
            subtitle: GochanoLanguage.text(
              'Live Commute routes, Cloud sync, Community messaging',
              'লাইভ যাতায়াত রুট, ক্লাউড সিঙ্ক, কমিউনিটি মেসেজ',
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: GochanoSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: type.bodySecondary.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Text(subtitle, style: type.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}
