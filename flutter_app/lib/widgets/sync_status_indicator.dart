import 'package:flutter/material.dart';

import '../core/design_system/gochano_colors.dart';
import '../core/design_system/gochano_spacing.dart';
import '../core/design_system/gochano_typography.dart';
import '../core/localization/gochano_language.dart';
import '../services/sync_coordinator.dart';
import 'sync_status_sheet.dart';

/// Lightweight, compact offline and sync status indicator.
///
/// Designed to live in the Home top area or app header without visually
/// overwhelming the student. Tapping opens the [SyncStatusSheet].
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GochanoLocale>(
      valueListenable: GochanoLanguage.current,
      builder: (context, _, _) {
        return ValueListenableBuilder<SyncState>(
          valueListenable: SyncCoordinator.instance.syncState,
          builder: (context, state, _) {
            final colors = context.colors;
            final type = context.type;

            Color bg;
            Color border;
            Color fg;
            IconData icon;
            String text;

            switch (state.status) {
              case SyncStatus.synced:
                bg = colors.success.withValues(alpha: 0.08);
                border = colors.success.withValues(alpha: 0.25);
                fg = colors.success;
                icon = Icons.cloud_done_rounded;
                text = GochanoLanguage.text('Synced', 'সিঙ্ক সম্পন্ন');
                break;
              case SyncStatus.offline:
                bg = colors.warning.withValues(alpha: 0.12);
                border = colors.warning.withValues(alpha: 0.3);
                fg = colors.warning;
                icon = Icons.cloud_off_rounded;
                text = GochanoLanguage.text('Offline mode', 'অফলাইন মোড');
                break;
              case SyncStatus.pending:
                bg = colors.warning.withValues(alpha: 0.14);
                border = colors.warning.withValues(alpha: 0.35);
                fg = colors.warning;
                icon = Icons.sync_problem_rounded;
                final count = state.pendingCount;
                final bnCount = GochanoLanguage.toBanglaDigits(count);
                text = GochanoLanguage.text(
                  '$count ${count == 1 ? "item" : "items"} waiting to sync',
                  '$bnCountটি পরিবর্তন সিঙ্ক অপেক্ষায়',
                );
                break;
              case SyncStatus.syncing:
                bg = colors.brand.withValues(alpha: 0.1);
                border = colors.brand.withValues(alpha: 0.25);
                fg = colors.brand;
                icon = Icons.sync_rounded;
                text = GochanoLanguage.text('Syncing…', 'সিঙ্ক হচ্ছে…');
                break;
              case SyncStatus.error:
                bg = colors.error.withValues(alpha: 0.1);
                border = colors.error.withValues(alpha: 0.25);
                fg = colors.error;
                icon = Icons.error_outline_rounded;
                text = GochanoLanguage.text('Sync paused', 'সিঙ্ক স্থগিত');
                break;
            }

            return Semantics(
              button: true,
              label: GochanoLanguage.text(
                'Sync status: $text. Tap to view sync details.',
                'সিঙ্ক অবস্থা: $text। বিস্তারিত দেখতে ট্যাপ করুন।',
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('sync_status_indicator_chip'),
                  onTap: () => showSyncStatusSheet(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: GochanoSpacing.sm,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: fg),
                        const SizedBox(width: GochanoSpacing.xs),
                        Flexible(
                          child: Text(
                            text,
                            style: type.bodySecondary.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: fg.withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
