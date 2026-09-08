// Read-only reward history view.
//
// Shows recent reward transactions. Accessible from Focus or Profile.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../data/reward_service.dart';
import '../domain/reward_model.dart';

class RewardHistoryView extends StatefulWidget {
  const RewardHistoryView({super.key});

  @override
  State<RewardHistoryView> createState() => _RewardHistoryViewState();
}

class _RewardHistoryViewState extends State<RewardHistoryView> {
  List<RewardTransaction>? _transactions;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = '';
    });
    try {
      final txs = await RewardService.readRecentTransactions(limit: 20);
      if (!mounted) return;
      setState(() => _transactions = txs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty && _transactions == null) {
      return ErrorState(compact: true, message: _error, onRetry: _load);
    }
    if (_transactions == null) {
      return StaticLoadingState(
        compact: true,
        message: GochanoLanguage.text(
          'Loading reward history…',
          'রেনার্দ ইতিহাস লোড হচ্ছে…',
        ),
      );
    }

    if (_transactions!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(GochanoSpacing.xl),
          child: Text(
            GochanoLanguage.text(
              'Complete Focus sessions to earn rewards.',
              'রেনার্দ পেতে ফোকাস সেশন সম্পন্ন করুন।',
            ),
            style: context.type.bodySecondary,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return CardGroup(
      children: [
        for (final tx in _transactions!)
          _RewardHistoryRow(transaction: tx),
      ],
    );
  }
}

class _RewardHistoryRow extends StatelessWidget {
  const _RewardHistoryRow({required this.transaction});

  final RewardTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Format the timestamp.
    String timeLabel = '';
    if (transaction.createdAt is DateTime) {
      final dt = transaction.createdAt as DateTime;
      timeLabel = '${dt.day}/${dt.month}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } else if (transaction.createdAt != null) {
      // Firestore Timestamp — convert.
      try {
        final ts = transaction.createdAt;
        final dt = ts.toDate();
        timeLabel = '${dt.day}/${dt.month}/${dt.year} '
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        timeLabel = '';
      }
    }

    final label = transaction.plannedMinutes != null
        ? GochanoLanguage.text(
            '${transaction.plannedMinutes} min Focus',
            '${transaction.plannedMinutes} মিনিট ফোকাস',
          )
        : GochanoLanguage.text('Focus reward', 'ফোকাস রেনার্দ');

    return GochanoListRow(
      illustration: GochanoArt.featureFocus,
      accent: colors.info,
      title: label,
      metadata: [
        if (transaction.xpDelta > 0) '+${transaction.xpDelta} XP',
        if (transaction.gemDelta > 0) '+${transaction.gemDelta} জেম',
        if (timeLabel.isNotEmpty) timeLabel,
      ],
    );
  }
}
