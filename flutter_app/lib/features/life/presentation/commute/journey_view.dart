// The multimodal journey planner UI (CommuteBD spec §17–§20, §32–§35, §45).
//
// Two complementary representations, as the spec requires. The map answers
// "where am I going?"; the timeline answers "what exactly should I do?".
//
// What this UI will not do
// ------------------------
// * No motion. Spec §35 rules out animated vehicles, moving route lines,
//   animated pins, Lottie and Rive. The map draws once and sits still.
// * No internal identifiers. Every step names a real place, because the
//   backend refuses to build a node without a human-readable name.
// * No fare laundering. Each leg keeps the provenance label the server gave
//   it, and a journey's headline certainty is its *weakest* leg, so one
//   official metro fare cannot make a negotiated rickshaw fare look official.
// * No invented geometry. Legs whose stops have no coordinates are listed in
//   the timeline but simply not drawn, and the map says so rather than
//   guessing a line.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../home/presentation/home_screen.dart' show formatTaka;
import 'journey_models.dart';

/// The whole planner block: strategy chooser, map, summary, timeline.
class JourneyPlanSection extends StatefulWidget {
  const JourneyPlanSection({super.key, required this.plan});

  final JourneyPlan plan;

  @override
  State<JourneyPlanSection> createState() => _JourneyPlanSectionState();
}

class _JourneyPlanSectionState extends State<JourneyPlanSection> {
  int _selected = 0;

  @override
  void didUpdateWidget(JourneyPlanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new search invalidates the previous selection.
    if (!identical(oldWidget.plan, widget.plan)) _selected = 0;
  }

  String get _sectionTitle =>
      GochanoLanguage.text('Your journey', 'আপনার যাত্রাপথ');

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;

    if (plan.status != JourneyPlanningStatus.available) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: _sectionTitle),
          _PlanningUnavailable(plan: plan),
        ],
      );
    }

    if (plan.isNoRoute) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: _sectionTitle),
          EmptyState(
            compact: true,
            illustration: GochanoArt.emptyCommute,
            title: GochanoLanguage.text(
              'No complete journey found',
              'কোনো সম্পূর্ণ যাত্রাপথ পাওয়া যায়নি',
            ),
            message: GochanoLanguage.text(
              'CommuteBD could not connect these two places with the transport '
              'it currently knows about. The fare estimates below are still '
              'based on the distance between them.',
              'কমিউটবিডি এখন যে যানবাহনের তথ্য জানে তা দিয়ে এই দুই স্থান যুক্ত করা '
              'যায়নি। নিচের ভাড়ার হিসাব এখনো দূরত্বের ভিত্তিতে দেওয়া।',
            ),
          ),
        ],
      );
    }

    final journeys = plan.journeys;
    final index = _selected.clamp(0, journeys.length - 1);
    final journey = journeys[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: _sectionTitle,
          subtitle: GochanoLanguage.text(
            journeys.length == 1
                ? 'One route found'
                : '${journeys.length} routes found',
            journeys.length == 1
                ? 'একটি রুট পাওয়া গেছে'
                : '${journeys.length}টি রুট পাওয়া গেছে',
          ),
        ),

        if (journeys.length > 1) ...[
          _StrategyChooser(
            journeys: journeys,
            selected: index,
            onSelected: (i) => setState(() => _selected = i),
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],

        JourneyMap(journey: journey),
        const SizedBox(height: GochanoSpacing.sm),

        JourneySummaryCard(journey: journey),
        const SizedBox(height: GochanoSpacing.md),

        Text(
          GochanoLanguage.text('Step by step', 'ধাপে ধাপে'),
          style: context.type.sectionHeading,
        ),
        const SizedBox(height: GochanoSpacing.sm),
        JourneyTimeline(journey: journey),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Strategy chooser
// ---------------------------------------------------------------------------

/// Recommended / Cheapest / Fastest, each shown with the numbers that
/// distinguish it, so the choice is made on evidence rather than on the label.
class _StrategyChooser extends StatelessWidget {
  const _StrategyChooser({
    required this.journeys,
    required this.selected,
    required this.onSelected,
  });

  final List<Journey> journeys;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < journeys.length; i++) ...[
          if (i > 0) const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Semantics(
              selected: i == selected,
              button: true,
              child: InkWell(
                onTap: () => onSelected(i),
                borderRadius: GochanoRadius.mdAll,
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: GochanoSizes.minTouchTarget,
                  ),
                  padding: const EdgeInsets.all(GochanoSpacing.xs),
                  decoration: BoxDecoration(
                    color: i == selected ? colors.brandSoft : colors.surface,
                    borderRadius: GochanoRadius.mdAll,
                    border: Border.all(
                      color: i == selected ? colors.commute : colors.border,
                      width: i == selected ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        journeyStrategyLabel(journeys[i]),
                        style: type.label.copyWith(
                          color: i == selected ? colors.commute : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        journeys[i].totalFareTk <= 0
                            ? GochanoLanguage.text('Free', 'ফ্রি')
                            : formatTaka(journeys[i].totalFareTk),
                        style: type.cardHeading,
                      ),
                      Text(
                        formatJourneyDuration(journeys[i].totalDurationMinutes),
                        style: type.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The label for a journey's strategy. A journey found by two objectives
/// carries both labels rather than being listed twice (spec §8).
String journeyStrategyLabel(Journey journey) {
  final parts = <String>[
    if (journey.isRecommended) GochanoLanguage.text('Recommended', 'প্রস্তাবিত'),
    if (journey.isCheapest) GochanoLanguage.text('Cheapest', 'সস্তা'),
    if (journey.isFastest) GochanoLanguage.text('Fastest', 'দ্রুততম'),
  ];
  if (parts.isEmpty) return GochanoLanguage.text('Alternative', 'বিকল্প');
  return parts.join(' · ');
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

/// Totals, the mode sequence, why it is recommended, and how it compares.
class JourneySummaryCard extends StatelessWidget {
  const JourneySummaryCard({super.key, required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final comparison = _comparison(journey);

    return AppCard(
      accent: journey.isRecommended ? colors.commute : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: GochanoSpacing.xxs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              if (journey.isRecommended)
                GochanoBadge(
                  label: GochanoLanguage.text('Recommended', 'প্রস্তাবিত'),
                  tone: GochanoBadgeTone.brand,
                  icon: Icons.star_rounded,
                ),
              if (journey.isCheapest)
                GochanoBadge(
                  label: GochanoLanguage.text('Cheapest', 'সবচেয়ে সস্তা'),
                  tone: GochanoBadgeTone.neutral,
                  icon: Icons.savings_outlined,
                ),
              if (journey.isFastest)
                GochanoBadge(
                  label: GochanoLanguage.text('Fastest', 'দ্রুততম'),
                  tone: GochanoBadgeTone.neutral,
                  icon: Icons.bolt_rounded,
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),

          // The at-a-glance mode sequence: Rickshaw › Metro › Walk.
          _ModeSequence(modes: journey.modeSummary),
          const SizedBox(height: GochanoSpacing.sm),

          Row(
            children: [
              Expanded(
                child: _Total(
                  label: GochanoLanguage.text('Fare', 'ভাড়া'),
                  value: journey.totalFareTk <= 0
                      ? GochanoLanguage.text('Free', 'ফ্রি')
                      : formatTaka(journey.totalFareTk),
                ),
              ),
              Expanded(
                child: _Total(
                  label: GochanoLanguage.text('Time', 'সময়'),
                  value: formatJourneyDuration(journey.totalDurationMinutes),
                ),
              ),
              Expanded(
                child: _Total(
                  label: GochanoLanguage.text('Changes', 'পরিবর্তন'),
                  value: '${journey.transfers}',
                ),
              ),
            ],
          ),

          const SizedBox(height: GochanoSpacing.xs),
          Text(
            [
              GochanoLanguage.text(
                '${journey.totalDistanceKm.toStringAsFixed(1)} km total',
                'মোট ${journey.totalDistanceKm.toStringAsFixed(1)} কিমি',
              ),
              if (journey.totalWalkKm > 0.05)
                GochanoLanguage.text(
                  '${journey.totalWalkKm.toStringAsFixed(1)} km walking',
                  '${journey.totalWalkKm.toStringAsFixed(1)} কিমি হাঁটা',
                ),
            ].join(' · '),
            style: type.caption,
          ),

          if (journey.whyRecommended != null) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: GochanoSizes.iconSm,
                  color: colors.commute,
                ),
                const SizedBox(width: GochanoSpacing.xxs),
                Expanded(
                  child: Text(
                    journey.whyRecommended!,
                    style: type.bodySecondary,
                  ),
                ),
              ],
            ),
          ],

          if (comparison != null) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(comparison, style: type.caption),
          ],

          // The headline fare is only as trustworthy as its weakest leg.
          const SizedBox(height: GochanoSpacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: GochanoSpacing.xxs,
            children: [
              Text(
                GochanoLanguage.text(
                  'Fare certainty',
                  'ভাড়ার নির্ভরযোগ্যতা',
                ),
                style: type.caption,
              ),
              JourneyFareBadge(fareType: journey.fareCertainty),
            ],
          ),
        ],
      ),
    );
  }

  /// "৳16 more, 26 min faster" against the recommended journey. Built only
  /// from the deltas the backend measured; nothing is recomputed here.
  static String? _comparison(Journey journey) {
    final fare = journey.fareDeltaTk;
    final minutes = journey.durationDeltaMinutes;
    if (fare.abs() < 0.5 && minutes.abs() < 1) return null;

    final parts = <String>[];
    if (fare.abs() >= 0.5) {
      final amount = formatTaka(fare.abs());
      parts.add(
        fare > 0
            ? GochanoLanguage.text('$amount more', '$amount বেশি')
            : GochanoLanguage.text('$amount cheaper', '$amount সস্তা'),
      );
    }
    if (minutes.abs() >= 1) {
      final abs = minutes.abs();
      parts.add(
        minutes > 0
            ? GochanoLanguage.text('$abs min slower', '$abs মিনিট বেশি')
            : GochanoLanguage.text('$abs min faster', '$abs মিনিট কম'),
      );
    }
    final joined = parts.join(', ');
    return GochanoLanguage.text(
      '$joined than the recommended route.',
      'প্রস্তাবিত রুটের তুলনায় $joined।',
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.type.caption),
        Text(value, style: context.type.statisticSmall),
      ],
    );
  }
}

/// Rickshaw › Metro › Walk, drawn with the same static transport drawings
/// used everywhere else in the app.
class _ModeSequence extends StatelessWidget {
  const _ModeSequence({required this.modes});

  final List<String> modes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (modes.isEmpty) return const SizedBox.shrink();

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: GochanoSpacing.xxs,
      runSpacing: GochanoSpacing.xxs,
      children: [
        for (var i = 0; i < modes.length; i++) ...[
          if (i > 0)
            Icon(
              Icons.chevron_right_rounded,
              size: GochanoSizes.iconSm,
              color: colors.textTertiary,
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GochanoIllustration(
                GochanoArt.transportIdFor(modes[i]),
                size: 20,
                accent: colors.commute,
              ),
              const SizedBox(width: 4),
              Text(modes[i], style: context.type.label),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

/// The vertical step-by-step timeline (spec §20).
///
/// Stops are dots on a rail; the instruction for getting from one stop to the
/// next sits on the rail between them. Every dot carries a real place name.
class JourneyTimeline extends StatelessWidget {
  const JourneyTimeline({super.key, required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final legs = journey.legs;
    if (legs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Stop(name: legs.first.from, isFirst: true, isLast: false),
        for (var i = 0; i < legs.length; i++) ...[
          _LegStep(leg: legs[i]),
          _Stop(name: legs[i].to, isFirst: false, isLast: i == legs.length - 1),
        ],
      ],
    );
  }
}

const double _railWidth = 20;

/// A place on the journey. The two ends are marked differently so the start
/// and the arrival are obvious at a glance.
class _Stop extends StatelessWidget {
  const _Stop({
    required this.name,
    required this.isFirst,
    required this.isLast,
  });

  final String name;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emphasised = isFirst || isLast;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: Column(
              children: [
                // The rail continues above unless this is the first stop.
                Expanded(child: _Rail(visible: !isFirst, color: colors.border)),
                _StopDot(
                  color: emphasised ? colors.commute : colors.borderStrong,
                  filled: emphasised,
                ),
                Expanded(child: _Rail(visible: !isLast, color: colors.border)),
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (emphasised)
                    Text(
                      isFirst
                          ? GochanoLanguage.text('Start', 'শুরু')
                          : GochanoLanguage.text('Arrive', 'পৌঁছান'),
                      style: context.type.caption,
                    ),
                  Text(
                    name,
                    style: emphasised
                        ? context.type.cardHeading
                        : context.type.body,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One leg: what to board, how far, how long, what it costs and how sure we
/// are of that cost.
class _LegStep extends StatelessWidget {
  const _LegStep({required this.leg});

  final JourneyLeg leg;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: _Rail(visible: true, color: colors.border),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.xxs),
              child: Container(
                padding: const EdgeInsets.all(GochanoSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: GochanoRadius.mdAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Spec §22: a change of transport is a step in its own
                    // right with its own time cost, not a hidden detail.
                    if (leg.isTransfer && leg.transferMinutes > 0) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: GochanoSizes.iconSm,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              GochanoLanguage.text(
                                'Change here — allow about '
                                '${leg.transferMinutes} min',
                                'এখানে পরিবর্তন — প্রায় '
                                '${leg.transferMinutes} মিনিট ধরুন',
                              ),
                              style: type.caption,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: GochanoSpacing.xs),
                    ],

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GochanoIllustration(
                          GochanoArt.transportIdFor(leg.mode),
                          size: 24,
                          accent: colors.commute,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                leg.serviceName == null
                                    ? leg.modeLabel
                                    : '${leg.modeLabel} · ${leg.serviceName}',
                                style: type.label,
                              ),
                              const SizedBox(height: 2),
                              Text(leg.instruction, style: type.body),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: GochanoSpacing.xs),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: GochanoSpacing.xs,
                      runSpacing: 4,
                      children: [
                        Text(
                          [
                            '${leg.distanceKm.toStringAsFixed(1)} km',
                            formatJourneyDuration(leg.durationMinutes),
                            if (leg.isFree)
                              GochanoLanguage.text('Free', 'ফ্রি')
                            else
                              formatTaka(leg.fareTk),
                          ].join(' · '),
                          style: type.caption,
                        ),
                        JourneyFareBadge(fareType: leg.fareType),
                      ],
                    ),

                    // Where the fare number actually came from.
                    if (leg.fareSource.isNotEmpty && !leg.isFree) ...[
                      const SizedBox(height: 2),
                      Text(leg.fareSource, style: type.caption),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.visible, required this.color});

  final bool visible;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Center(
      child: SizedBox(
        width: 2,
        child: DecoratedBox(decoration: BoxDecoration(color: color)),
      ),
    );
  }
}

class _StopDot extends StatelessWidget {
  const _StopDot({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final size = filled ? 12.0 : 9.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : context.colors.surface,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map
// ---------------------------------------------------------------------------

/// The journey drawn on a map: one static line per leg.
///
/// The lines connect stop coordinates, not road geometry — the dataset holds
/// stops, not street shapes — so the map is captioned as a schematic rather
/// than passed off as turn-by-turn navigation.
class JourneyMap extends StatelessWidget {
  const JourneyMap({super.key, required this.journey, this.height = 240});

  final Journey journey;
  final double height;

  /// Walking is dashed so a 15-minute walk is never mistaken for a ride.
  /// Not `const`: StrokePattern.dashed asserts on its segment list, which
  /// takes it out of constant evaluation.
  static final _walkPattern = StrokePattern.dashed(segments: const [6, 5]);
  static const _ridePattern = StrokePattern.solid();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mappable = journey.legs.where((leg) => leg.isMappable).toList();

    if (mappable.isEmpty) {
      return _MapUnavailable(
        message: GochanoLanguage.text(
          'This journey cannot be drawn — CommuteBD does not have map '
          'coordinates for these stops yet. The steps below are complete.',
          'এই যাত্রাপথ আঁকা যাচ্ছে না — এই স্টপগুলোর মানচিত্র স্থানাঙ্ক '
          'কমিউটবিডিতে এখনো নেই। নিচের ধাপগুলো সম্পূর্ণ।',
        ),
      );
    }

    final points = <LatLng>[];
    for (final leg in mappable) {
      points
        ..add(LatLng(leg.fromLat!, leg.fromLon!))
        ..add(LatLng(leg.toLat!, leg.toLon!));
    }
    final partial = mappable.length < journey.legs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: GochanoRadius.lgAll,
          child: SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: GochanoRadius.lgAll,
              ),
              // Tile layers repaint independently of the surrounding list;
              // without this the whole map re-rasterises on every scroll.
              child: RepaintBoundary(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: points.first,
                    initialZoom: 12.5,
                    initialCameraFit: points.length < 2
                        ? null
                        : CameraFit.coordinates(
                            coordinates: points,
                            padding: const EdgeInsets.all(GochanoSpacing.xl),
                          ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ekthikana.ekthikana',
                      retinaMode: false,
                    ),
                    PolylineLayer(
                      polylines: [
                        for (final leg in mappable)
                          Polyline(
                            points: [
                              LatLng(leg.fromLat!, leg.fromLon!),
                              LatLng(leg.toLat!, leg.toLon!),
                            ],
                            strokeWidth: leg.mode == 'walk' ? 3 : 5,
                            color: leg.mode == 'walk'
                                ? colors.textSecondary
                                : colors.commute,
                            pattern: leg.mode == 'walk'
                                ? _walkPattern
                                : _ridePattern,
                            borderStrokeWidth: 1.5,
                            borderColor: colors.surface,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        for (var i = 0; i < points.length; i++)
                          if (i.isEven || i == points.length - 1)
                            Marker(
                              point: points[i],
                              width: 28,
                              height: 28,
                              child: _MapDot(
                                isEnd: i == 0 || i == points.length - 1,
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: GochanoSpacing.xxs),
        Text(
          partial
              ? GochanoLanguage.text(
                  'Straight lines between stops, not the exact road path. '
                  'Some steps have no coordinates and are not drawn.',
                  'স্টপগুলোর মধ্যে সরলরেখা, সঠিক সড়কপথ নয়। কিছু ধাপের স্থানাঙ্ক '
                  'না থাকায় সেগুলো আঁকা হয়নি।',
                )
              : GochanoLanguage.text(
                  'Straight lines between stops, not the exact road path.',
                  'স্টপগুলোর মধ্যে সরলরেখা, সঠিক সড়কপথ নয়।',
                ),
          style: context.type.caption,
        ),
      ],
    );
  }
}

class _MapDot extends StatelessWidget {
  const _MapDot({required this.isEnd});

  final bool isEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = isEnd ? 16.0 : 10.0;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          border: Border.all(
            color: isEnd ? colors.commute : colors.borderStrong,
            width: isEnd ? 4 : 2.5,
          ),
        ),
      ),
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.map_outlined,
            size: GochanoSizes.iconMd,
            color: colors.textSecondary,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(child: Text(message, style: context.type.bodySecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// Names the provenance of a fare in one word (spec §24, §68).
///
/// An estimate must never be able to read as an official fare, so an
/// unrecognised provenance falls back to "Estimated" — the weakest claim —
/// rather than to a confident-looking label.
class JourneyFareBadge extends StatelessWidget {
  const JourneyFareBadge({super.key, required this.fareType});

  final String fareType;

  @override
  Widget build(BuildContext context) {
    if (fareType.isEmpty || fareType == 'none') return const SizedBox.shrink();

    final (label, tone) = switch (fareType) {
      'official' => (
          GochanoLanguage.text('Official', 'সরকারি'),
          GochanoBadgeTone.success,
        ),
      'calculated' => (
          GochanoLanguage.text('Calculated', 'হিসাবকৃত'),
          GochanoBadgeTone.info,
        ),
      'crowdsourced' => (
          GochanoLanguage.text('Reported by riders', 'যাত্রীদের তথ্য'),
          GochanoBadgeTone.info,
        ),
      'historical' => (
          GochanoLanguage.text('Historical rule', 'পুরোনো নিয়ম'),
          GochanoBadgeTone.warning,
        ),
      _ => (
          GochanoLanguage.text('Estimated', 'আনুমানিক'),
          GochanoBadgeTone.neutral,
        ),
    };

    return GochanoBadge(label: label, tone: tone);
  }
}

/// Why planning could not run — stated specifically, because "your starting
/// point is off the network" and "the dataset is not loaded" call for
/// different responses from the student (spec §30).
class _PlanningUnavailable extends StatelessWidget {
  const _PlanningUnavailable({required this.plan});

  final JourneyPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final message = switch (plan.status) {
      JourneyPlanningStatus.datasetUnavailable => GochanoLanguage.text(
          'Route planning is unavailable right now — the CommuteBD transport '
          'network could not be loaded. The fare estimates below still work.',
          'এখন রুট পরিকল্পনা করা যাচ্ছে না — কমিউটবিডির যানবাহন নেটওয়ার্ক লোড '
          'করা যায়নি। নিচের ভাড়ার হিসাব এখনো কাজ করছে।',
        ),
      JourneyPlanningStatus.outsideCoverage => _coverageMessage(),
      _ => GochanoLanguage.text(
          'Route planning could not finish for this trip. The fare estimates '
          'below are unaffected.',
          'এই যাত্রার রুট পরিকল্পনা শেষ করা যায়নি। নিচের ভাড়ার হিসাব '
          'অপরিবর্তিত আছে।',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: GochanoSizes.iconMd,
            color: colors.textSecondary,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(child: Text(message, style: context.type.bodySecondary)),
        ],
      ),
    );
  }

  String _coverageMessage() {
    final ends = plan.outsideCoverage;
    final radius = plan.coverageRadiusKm;
    final within = radius == null ? '' : ' (${radius.toStringAsFixed(0)} km)';

    if (ends.length >= 2) {
      return GochanoLanguage.text(
        'Neither place is close enough$within to transport CommuteBD knows '
        'about, so no journey could be planned. The fare estimates below are '
        'based on distance alone.',
        'কোনো স্থানই কমিউটবিডির জানা যানবাহনের যথেষ্ট কাছে$within নয়, তাই '
        'যাত্রাপথ পরিকল্পনা করা যায়নি। নিচের ভাড়া শুধু দূরত্বভিত্তিক।',
      );
    }
    if (ends.contains('origin')) {
      return GochanoLanguage.text(
        'Your starting point is not close enough$within to transport '
        'CommuteBD knows about. Try a nearby landmark instead.',
        'আপনার শুরুর স্থানটি কমিউটবিডির জানা যানবাহনের যথেষ্ট কাছে$within নয়। '
        'কাছাকাছি কোনো পরিচিত স্থান বেছে দেখুন।',
      );
    }
    if (ends.contains('destination')) {
      return GochanoLanguage.text(
        'Your destination is not close enough$within to transport CommuteBD '
        'knows about. Try a nearby landmark instead.',
        'আপনার গন্তব্যটি কমিউটবিডির জানা যানবাহনের যথেষ্ট কাছে$within নয়। '
        'কাছাকাছি কোনো পরিচিত স্থান বেছে দেখুন।',
      );
    }
    return GochanoLanguage.text(
      'These places are outside the transport network CommuteBD knows about.',
      'এই স্থানগুলো কমিউটবিডির জানা যানবাহন নেটওয়ার্কের বাইরে।',
    );
  }
}

/// "25 min", "1 h 20 min" — shared by the cards and the timeline.
String formatJourneyDuration(int minutes) {
  if (minutes < 60) {
    return GochanoLanguage.text('$minutes min', '$minutes মিনিট');
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return GochanoLanguage.text('$hours h', '$hours ঘণ্টা');
  return GochanoLanguage.text('$hours h $rest min', '$hours ঘণ্টা $rest মিনিট');
}
