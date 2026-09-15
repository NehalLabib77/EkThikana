// Smart Journey Guide — Phase 2 of the Commute feature.
//
// Provides a Google-like human-readable explanation of the current journey,
// grounded ONLY in verified facts already computed by the route engine and
// fare engine. AI is used solely for wording enhancement; it never becomes
// a single point of failure.
//
// Architecture:
//   Route Data → JourneyGuideFacts → Local deterministic guide (always) →
//   AI explanation (optional enrichment)
//
// The AI must NEVER invent route, stop, bus, fare, or time data.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../home/presentation/home_screen.dart' show formatTaka;
import 'journey_models.dart';
import 'journey_view.dart' show formatJourneyDuration;

/// Smart Journey Guide card.
///
/// Renders a deterministic local guide immediately, then optionally enhances
/// the explanation wording via AI when the backend responds.
class SmartJourneyGuide extends StatefulWidget {
  const SmartJourneyGuide({super.key, required this.facts, this.onAskTrip});

  final JourneyGuideFacts facts;

  /// Called when the user taps "Ask about this trip".
  final VoidCallback? onAskTrip;

  @override
  State<SmartJourneyGuide> createState() => _SmartJourneyGuideState();
}

class _SmartJourneyGuideState extends State<SmartJourneyGuide> {
  String _aiExplanation = '';
  bool _aiLoading = false;
  bool _aiRequested = false;

  @override
  void initState() {
    super.initState();
    _requestAiExplanation();
  }

  @override
  void didUpdateWidget(SmartJourneyGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_factsEqual(oldWidget.facts, widget.facts)) {
      _aiExplanation = '';
      _aiLoading = false;
      _aiRequested = false;
      _requestAiExplanation();
    }
  }

  bool _factsEqual(JourneyGuideFacts a, JourneyGuideFacts b) {
    return a.originName == b.originName &&
        a.destinationName == b.destinationName &&
        a.selectedMode == b.selectedMode &&
        a.distanceKm == b.distanceKm &&
        a.durationMinutes == b.durationMinutes &&
        a.fareLow == b.fareLow &&
        a.fareHigh == b.fareHigh;
  }

  Future<void> _requestAiExplanation() async {
    if (_aiRequested) return;
    _aiRequested = true;
    if (!mounted) return;

    setState(() => _aiLoading = true);

    try {
      final explanation = await ApiService.commuteGuide(widget.facts.toJson());
      if (!mounted) return;
      setState(() {
        _aiExplanation = explanation;
        _aiLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facts = widget.facts;
    final colors = context.colors;

    // Guard: no usable journey data at all — but this should not be reached
    // because the parent only renders this widget when facts exist.
    if (facts.originName.isEmpty && facts.destinationName.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text(
            'Smart Journey Guide',
            'স্মার্ট যাত্রা নির্দেশিকা',
          ),
        ),
        AppCard(
          accent: colors.commute,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // AI explanation (when available) or deterministic summary
              if (_aiExplanation.isNotEmpty)
                Text(_aiExplanation, style: context.type.body)
              else ...[
                _DeterministicExplanation(facts: facts),
                if (_aiLoading) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Flexible(
                        child: Text(
                          GochanoLanguage.text(
                            'Enhancing explanation…',
                            'ব্যাখ্যা উন্নত করা হচ্ছে…',
                          ),
                          style: context.type.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],

              const SizedBox(height: GochanoSpacing.md),

              // Travel details heading
              Text(
                GochanoLanguage.text('Travel details', 'যাত্রার বিস্তারিত'),
                style: context.type.sectionHeading,
              ),
              const SizedBox(height: GochanoSpacing.sm),

              // Distance
              if (facts.hasDistance)
                _DetailRow(
                  label: GochanoLanguage.text('Distance', 'দূরত্ব'),
                  value: '${facts.distanceKm!.toStringAsFixed(1)} km',
                ),

              // Duration
              if (facts.hasDuration) ...[
                const SizedBox(height: GochanoSpacing.xs),
                _DetailRow(
                  label: GochanoLanguage.text('Time', 'সময়'),
                  value: _durationText(facts),
                ),
              ],

              // Fare
              const SizedBox(height: GochanoSpacing.xs),
              _FareRow(facts: facts),

              // Transport
              if (facts.modeLabel != null) ...[
                const SizedBox(height: GochanoSpacing.xs),
                _DetailRow(
                  label: GochanoLanguage.text('Transport', 'যাতায়াত'),
                  value: GochanoLanguage.text(
                    'By ${facts.modeLabel}',
                    '${facts.modeLabel} দিয়ে',
                  ),
                ),
              ],

              // Bus operator and stops if a bus is selected
              if (facts.selectedBusOperator != null) ...[
                const SizedBox(height: GochanoSpacing.xs),
                _DetailRow(
                  label: GochanoLanguage.text('Bus Service', 'বাস সেবা'),
                  value: facts.selectedBusOperator!,
                ),
                if (facts.selectedBusBoardStop != null &&
                    facts.selectedBusExitStop != null) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  _DetailRow(
                    label: GochanoLanguage.text('Board / Exit', 'উঠা / নামা'),
                    value:
                        '${facts.selectedBusBoardStop} → ${facts.selectedBusExitStop}',
                  ),
                ],
              ],

              // Route waypoints — only when verified
              if (facts.hasWaypoints) ...[
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text('Route', 'রুট'),
                  style: context.type.sectionHeading,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                _RouteWaypoints(
                  origin: facts.originName,
                  waypoints: facts.verifiedWaypoints,
                ),
              ],

              // Traffic disclaimer
              if (facts.durationProvenance == 'osrm') ...[
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  GochanoLanguage.text(
                    'Live traffic is not included.',
                    'লাইভ ট্রাফিক এই সময়ের হিসাবে অন্তর্ভুক্ত নয়।',
                  ),
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],

              // Ask about this trip
              if (widget.onAskTrip != null) ...[
                const SizedBox(height: GochanoSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onAskTrip,
                    icon: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: colors.commute,
                    ),
                    label: Text(
                      GochanoLanguage.text(
                        'Ask about this trip',
                        'এই যাত্রা সম্পর্কে জিজ্ঞাসা করুন',
                      ),
                      style: context.type.body.copyWith(color: colors.commute),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colors.commute.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: GochanoRadius.smAll,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.md,
                        vertical: GochanoSpacing.sm,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _durationText(JourneyGuideFacts facts) {
    final minutes = facts.durationMinutes!;
    final formatted = formatJourneyDuration(minutes);
    if (facts.durationProvenance == 'osrm') {
      return GochanoLanguage.text(
        '$formatted without traffic',
        '$formatted ট্রাফিক ছাড়া',
      );
    }
    return formatted;
  }
}

// ---------------------------------------------------------------------------
// Deterministic explanation (always available, no AI needed)
// ---------------------------------------------------------------------------

class _DeterministicExplanation extends StatelessWidget {
  const _DeterministicExplanation({required this.facts});

  final JourneyGuideFacts facts;

  @override
  Widget build(BuildContext context) {
    final modeLabel = facts.modeLabel ?? '';
    final origin = facts.originName;
    final dest = facts.destinationName;

    if (facts.selectedBusOperator != null &&
        facts.selectedBusOperator!.isNotEmpty) {
      final bus = facts.selectedBusOperator!;
      final board = facts.selectedBusBoardStop ?? origin;
      final exit = facts.selectedBusExitStop ?? dest;
      final stops = facts.selectedBusStopCount;
      final stopsEn = stops != null ? ' ($stops stops)' : '';
      final stopsBn = stops != null ? ' ($stops টি স্টপ)' : '';

      return Text(
        GochanoLanguage.text(
          'You can take $bus from $board to $exit$stopsEn along this route.',
          'আপনি এই রুটে $board থেকে $exit পর্যন্ত $bus$stopsBn ব্যবহার করতে পারেন।',
        ),
        style: context.type.body,
      );
    }

    if (modeLabel.isEmpty) {
      return Text(
        GochanoLanguage.text(
          'You can travel from $origin to $dest using the calculated road route.',
          '$origin থেকে $dest পর্যন্ত গণনাকৃত সড়কপথ ব্যবহার করে যেতে পারেন।',
        ),
        style: context.type.body,
      );
    }

    return Text(
      GochanoLanguage.text(
        'You can travel from $origin to $dest by $modeLabel using the '
            'calculated road route.',
        '$origin থেকে $dest পর্যন্ত $modeLabel দিয়ে গণনাকৃত সড়কপথ ব্যবহার '
            'করে যেতে পারেন।',
      ),
      style: context.type.body,
    );
  }
}

// ---------------------------------------------------------------------------
// Detail rows
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.type.caption),
          Text(
            value,
            style: context.type.body.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({required this.facts});

  final JourneyGuideFacts facts;

  @override
  Widget build(BuildContext context) {
    final label = GochanoLanguage.text('Fare', 'ভাড়া');

    if (!facts.fareAvailable && facts.selectedMode == 'walk') {
      return _DetailRow(
        label: label,
        value: GochanoLanguage.text('Free', 'ফ্রি'),
      );
    }

    if (!facts.fareAvailable || !facts.hasFare) {
      return _DetailRow(
        label: label,
        value: GochanoLanguage.text('Fare unavailable', 'ভাড়া তথ্য নেই'),
      );
    }

    final low = facts.fareLow!.toInt();
    final high = facts.fareHigh!.toInt();
    final fareText = low == high
        ? formatTaka(low.toDouble())
        : '${formatTaka(low.toDouble())}–${formatTaka(high.toDouble())}';

    final String fareTypeLabel;
    if (facts.fareType == 'official') {
      fareTypeLabel = GochanoLanguage.text('Official BRTA fare', 'অফিসিয়াল বিআরটিএ ভাড়া');
    } else if (facts.fareType == 'crowdsourced' || facts.fareType == 'crowd_sourced') {
      fareTypeLabel = GochanoLanguage.text('Community estimate', 'কমিউনিটি হিসাব');
    } else {
      fareTypeLabel = GochanoLanguage.text('Estimated', 'আনুমানিক');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.type.caption),
          Text(
            fareText,
            style: context.type.body.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            fareTypeLabel,
            style: context.type.caption,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route waypoints
// ---------------------------------------------------------------------------

class _RouteWaypoints extends StatelessWidget {
  const _RouteWaypoints({required this.origin, required this.waypoints});

  final String origin;
  final List<String> waypoints;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final allPoints = [origin, ...waypoints];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < allPoints.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? colors.commute : colors.borderStrong,
                    ),
                  ),
                  if (i < allPoints.length - 1)
                    Container(width: 1, height: 20, color: colors.border),
                ],
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Text(
                  allPoints[i],
                  style: i == 0
                      ? context.type.body
                      : context.type.bodySecondary,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
