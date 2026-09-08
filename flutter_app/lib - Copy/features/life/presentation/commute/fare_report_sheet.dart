// Post-trip actual fare (spec §69).
//
// Two separate things happen when a student reports a fare, and keeping them
// separate is the point of this sheet:
//
//   1. **Their own expense.** The amount they actually paid is written to
//      their private ledger through `FinancialService.recordCommuteTrip`,
//      which uses a deterministic transaction id so a retry cannot create a
//      duplicate expense.
//
//   2. **A crowd fare report.** Optionally, the same figure is submitted to
//      `POST /api/commute/fare-report`, where it is stored *pending
//      moderation* — the backend explicitly does not publish it as truth.
//
// The second is opt-in and is worded as such. An estimated fare never enters
// the expense ledger on its own; only a number the student typed does.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../services/financial_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';

Future<bool> showFareReportSheet(
  BuildContext context, {
  required String mode,
  required String modeLabel,
  required String originName,
  required String destinationName,
  required double distanceKm,
  required int tripMinutes,
  double? suggestedFare,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _FareReportForm(
        mode: mode,
        modeLabel: modeLabel,
        originName: originName,
        destinationName: destinationName,
        distanceKm: distanceKm,
        tripMinutes: tripMinutes,
        suggestedFare: suggestedFare,
      ),
    ),
  );
  return saved ?? false;
}

class _FareReportForm extends StatefulWidget {
  const _FareReportForm({
    required this.mode,
    required this.modeLabel,
    required this.originName,
    required this.destinationName,
    required this.distanceKm,
    required this.tripMinutes,
    this.suggestedFare,
  });

  final String mode;
  final String modeLabel;
  final String originName;
  final String destinationName;
  final double distanceKm;
  final int tripMinutes;
  final double? suggestedFare;

  @override
  State<_FareReportForm> createState() => _FareReportFormState();
}

class _FareReportFormState extends State<_FareReportForm> {
  late final TextEditingController _fare;

  /// Whether to also submit the figure to the shared crowd dataset.
  bool _shareWithOthers = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the estimate as a starting point the student edits.
    // It is never saved without them looking at it, because Save is a
    // deliberate tap on a sheet titled "what you actually paid".
    final suggested = widget.suggestedFare;
    _fare = TextEditingController(
      text: suggested == null || suggested <= 0
          ? ''
          : suggested.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _fare.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fare = double.tryParse(_fare.text.trim().replaceAll(',', ''));
    if (fare == null || fare <= 0) {
      setState(() {
        _error = GochanoLanguage.text(
          'Enter what you actually paid.',
          'আপনি আসলে কত দিয়েছেন তা লিখুন।',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // 1. The student's own expense. Deterministic id, so a retry after a
      //    flaky network overwrites rather than double-charging them
      //    (spec §69 — check deduplication).
      await FinancialService.recordCommuteTrip(
        mode: widget.mode,
        origin: widget.originName,
        destination: widget.destinationName,
        distanceKm: widget.distanceKm,
        estimatedMinutes: widget.tripMinutes,
        actualFare: fare,
        date: DateTime.now(),
      );

      // 2. Optional contribution to the shared dataset. A failure here must
      //    not lose the expense that already succeeded, so it is caught
      //    separately and reported as a partial result.
      var sharedOk = true;
      if (_shareWithOthers) {
        try {
          await ApiService.reportCommuteFare(
            originText: widget.originName,
            destinationText: widget.destinationName,
            mode: widget.mode,
            farePaid: fare,
            tripMinutes: widget.tripMinutes,
            routeDistanceKm: widget.distanceKm,
          );
        } catch (_) {
          sharedOk = false;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      showGochanoMessage(
        context,
        sharedOk
            ? GochanoLanguage.text(
                'Fare recorded in your expenses.',
                'ভাড়া আপনার খরচে যোগ হয়েছে।',
              )
            : GochanoLanguage.text(
                'Fare recorded in your expenses. It could not be shared with '
                'other riders right now.',
                'ভাড়া আপনার খরচে যোগ হয়েছে। এখন অন্য যাত্রীদের সাথে শেয়ার করা যায়নি।',
              ),
        isError: !sharedOk,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.lg,
          GochanoSpacing.xs,
          GochanoSpacing.lg,
          GochanoSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              GochanoLanguage.text('What did you pay?', 'আপনি কত দিয়েছেন?'),
              style: type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.xxs),
            Text(
              '${widget.modeLabel} · ${widget.originName} → ${widget.destinationName}',
              style: type.bodySecondary,
            ),
            const SizedBox(height: GochanoSpacing.md),
            TextField(
              controller: _fare,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: type.statistic,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Actual fare', 'আসল ভাড়া'),
                prefixText: '৳ ',
                prefixStyle: type.statistic.copyWith(color: colors.textSecondary),
                helperText: GochanoLanguage.text(
                  'This is added to your monthly spending.',
                  'এটি আপনার মাসিক খরচে যোগ হবে।',
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: GochanoSpacing.xs),
            SwitchListTile.adaptive(
              value: _shareWithOthers,
              onChanged: (value) => setState(() => _shareWithOthers = value),
              contentPadding: EdgeInsets.zero,
              title: Text(
                GochanoLanguage.text(
                  'Help other riders',
                  'অন্য যাত্রীদের সাহায্য করুন',
                ),
                style: type.body,
              ),
              subtitle: Text(
                GochanoLanguage.text(
                  'Share this fare anonymously. It is reviewed before it is '
                  'used in anyone else’s estimate.',
                  'ভাড়াটি নাম ছাড়া শেয়ার করুন। অন্য কারও হিসাবে ব্যবহারের আগে এটি যাচাই করা হয়।',
                ),
                style: type.caption,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                _error!,
                style: type.bodySecondary.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              label: GochanoLanguage.text('Save fare', 'ভাড়া সংরক্ষণ'),
              busy: _saving,
              busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
