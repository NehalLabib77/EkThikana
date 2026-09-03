// CommuteBD (spec §60–§69).
//
// Flow: From → To → Find routes → Recommended / Cheapest / Fastest.
//
// What this screen is honest about
// --------------------------------
// Every fare card states where its number came from and how much to trust it.
// The backend labels each option `official` / `crowdsourced` / `historical` /
// `estimated`, and that label is surfaced verbatim rather than flattened into
// one confident-looking price (spec §68: "Never label estimated values as
// official").
//
// This screen calls `POST /api/commute/routes` — the PostgreSQL/PostGIS-backed
// endpoint that resolves canonical CommuteBD places, ranks options, and
// returns real bus services connecting the two stops. The app previously
// called only the older coordinates-only `/api/commute/route`, so the dataset
// lookup never reached a user (spec §64).

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../home/presentation/home_screen.dart' show formatTaka;
import 'commute_map_picker.dart';
import 'commute_place_picker.dart';
import 'commute_route_map.dart';
import 'fare_report_sheet.dart';
import 'journey_models.dart';
import 'journey_view.dart';

class CommuteScreen extends StatefulWidget {
  const CommuteScreen({super.key});

  @override
  State<CommuteScreen> createState() => _CommuteScreenState();
}

class _CommuteScreenState extends State<CommuteScreen> {
  CommutePlace? _origin;
  CommutePlace? _destination;

  bool _searching = false;
  String _error = '';
  Map<String, dynamic>? _result;

  bool get _canSearch =>
      _origin != null && _destination != null && !_searching;

  Future<void> _pick({required bool isOrigin}) async {
    final place = await showCommutePlacePicker(
      context,
      title: isOrigin
          ? GochanoLanguage.text('Where from?', 'কোথা থেকে?')
          : GochanoLanguage.text('Where to?', 'কোথায় যাবেন?'),
    );
    if (place == null || !mounted) return;
    setState(() {
      if (isOrigin) {
        _origin = place;
      } else {
        _destination = place;
      }
      // A new endpoint invalidates the previous answer.
      _result = null;
      _error = '';
    });
  }

  void _swap() {
    setState(() {
      final from = _origin;
      _origin = _destination;
      _destination = from;
      _result = null;
      _error = '';
    });
  }

  /// Fills one end of the trip from a place tapped on the map.
  void _pickFromMap(CommutePlace place, CommuteEndpoint end) {
    setState(() {
      if (end == CommuteEndpoint.origin) {
        _origin = place;
      } else {
        _destination = place;
      }
      // A new endpoint invalidates the previous answer.
      _result = null;
      _error = '';
    });
  }

  Future<void> _findRoutes() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;

    setState(() {
      _searching = true;
      _error = '';
      _result = null;
    });

    try {
      final body = await ApiService.commuteRoutes(
        originPlaceId: origin.placeId,
        originName: origin.name,
        originLat: origin.lat,
        originLon: origin.lon,
        destinationPlaceId: destination.placeId,
        destinationName: destination.name,
        destinationLat: destination.lat,
        destinationLon: destination.lon,
      );
      if (!mounted) return;
      setState(() {
        _searching = false;
        _result = body;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: 'CommuteBD',
        subtitle: GochanoLanguage.text(
          'Routes and fares across Bangladesh',
          'বাংলাদেশ জুড়ে রুট ও ভাড়া',
        ),
      ),
      body: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _TripPlanner(
            origin: _origin,
            destination: _destination,
            onPickOrigin: () => _pick(isOrigin: true),
            onPickDestination: () => _pick(isOrigin: false),
            onSwap: _swap,
          ),
          const SizedBox(height: GochanoSpacing.md),
          PrimaryButton(
            label: GochanoLanguage.text('Find routes', 'রুট খুঁজুন'),
            icon: Icons.search_rounded,
            busy: _searching,
            busyLabel: GochanoLanguage.text(
              'Checking route…',
              'রুট দেখা হচ্ছে…',
            ),
            onPressed: _canSearch ? _findRoutes : null,
          ),

          // The map *is* the picker: a trip can be chosen by looking at it
          // rather than by knowing what a place is called. It stays until
          // there are results, which bring their own journey map.
          if (_result == null) ...[
            const SizedBox(height: GochanoSpacing.md),
            CommuteMapPicker(
              origin: _origin,
              destination: _destination,
              onPicked: _pickFromMap,
            ),
          ],

          if (_error.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.lg),
            ErrorState(
              compact: true,
              message: _error,
              onRetry: _canSearch ? _findRoutes : null,
            ),
          ],

          if (_result != null) _Results(result: _result!),
        ],
      ),
    );
  }
}

/// From / To with a swap control.
class _TripPlanner extends StatelessWidget {
  const _TripPlanner({
    required this.origin,
    required this.destination,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.onSwap,
  });

  final CommutePlace? origin;
  final CommutePlace? destination;
  final VoidCallback onPickOrigin;
  final VoidCallback onPickDestination;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _PlaceField(
                  illustration: GochanoArt.pinOrigin,
                  accent: colors.commute,
                  label: GochanoLanguage.text('From', 'থেকে'),
                  value: origin?.name,
                  onTap: onPickOrigin,
                ),
                Divider(height: GochanoSpacing.md, color: colors.divider),
                _PlaceField(
                  illustration: GochanoArt.pinDestination,
                  accent: colors.commute,
                  label: GochanoLanguage.text('To', 'পর্যন্ত'),
                  value: destination?.name,
                  onTap: onPickDestination,
                ),
              ],
            ),
          ),
          IconActionButton(
            icon: Icons.swap_vert_rounded,
            label: GochanoLanguage.text('Swap', 'অদলবদল'),
            onPressed: origin == null && destination == null ? null : onSwap,
          ),
        ],
      ),
    );
  }
}

class _PlaceField extends StatelessWidget {
  const _PlaceField({
    required this.illustration,
    required this.accent,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String illustration;
  final Color accent;
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filled = value != null && value!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: GochanoRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
        child: Row(
          children: [
            GochanoIllustration(illustration, size: 26, accent: accent),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: context.type.caption),
                  Text(
                    filled
                        ? value!
                        : GochanoLanguage.text('Choose a place', 'একটি স্থান বাছুন'),
                    style: context.type.cardHeading.copyWith(
                      color: filled ? null : colors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

class _Results extends StatelessWidget {
  const _Results({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final distanceKm = (result['distanceKm'] as num?)?.toDouble() ?? 0;
    final minutes = (result['estimatedDurationMin'] as num?)?.toInt() ?? 0;
    final provider = result['routingProvider']?.toString() ?? '';
    final disclaimer = result['disclaimer']?.toString() ?? '';

    final options = ((result['recommendations'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    final transit = ((result['transitCandidates'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    final originMap = result['origin'] as Map?;
    final destinationMap = result['destination'] as Map?;
    final originName = originMap?['name']?.toString() ?? '';
    final destinationName = destinationMap?['name']?.toString() ?? '';

    LatLng? point(Map? place) {
      final lat = (place?['lat'] as num?)?.toDouble();
      final lon = (place?['lon'] as num?)?.toDouble();
      return (lat == null || lon == null) ? null : LatLng(lat, lon);
    }

    final geometry = ((result['polyline'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Your trip', 'আপনার যাত্রা'),
        ),
        CommuteRouteMap(
          polyline: geometry,
          origin: point(originMap),
          destination: point(destinationMap),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        Row(
          children: [
            Expanded(
              child: StatCard(
                compact: true,
                label: GochanoLanguage.text('Distance', 'দূরত্ব'),
                value: '${distanceKm.toStringAsFixed(1)} km',
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: StatCard(
                compact: true,
                label: GochanoLanguage.text('By road', 'সড়কপথে'),
                value: _duration(minutes),
                caption: provider.isEmpty ? null : provider,
              ),
            ),
          ],
        ),

        // The multimodal planner: the actual journey, step by step. Shown
        // above the per-mode fare estimates because "how do I get there"
        // comes before "what would each mode cost".
        JourneyPlanSection(plan: JourneyPlan.fromResponse(result)),

        SectionHeader(
          title: GochanoLanguage.text(
            'Fare estimates by mode',
            'যানবাহনভেদে আনুমানিক ভাড়া',
          ),
          subtitle: GochanoLanguage.text(
            'A single-mode trip end to end, for comparison',
            'তুলনার জন্য শুরু থেকে শেষ পর্যন্ত এক যানবাহনে',
          ),
        ),
        if (options.isEmpty)
          EmptyState(
            compact: true,
            illustration: GochanoArt.emptyCommute,
            title: GochanoLanguage.text(
              'No fare options for this trip',
              'এই যাত্রার জন্য কোনো ভাড়ার তথ্য নেই',
            ),
            message: GochanoLanguage.text(
              'The route was found, but CommuteBD has no fare data covering '
              'these two places yet.',
              'রুট পাওয়া গেছে, তবে এই দুই স্থানের জন্য কমিউটবিডিতে এখনো ভাড়ার তথ্য নেই।',
            ),
          )
        else
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
              child: _FareCard(
                option: option,
                originName: originName,
                destinationName: destinationName,
                distanceKm: distanceKm,
              ),
            ),

        if (transit.isNotEmpty) ...[
          SectionHeader(
            title: GochanoLanguage.text('Buses on this route', 'এই রুটের বাস'),
            subtitle: GochanoLanguage.text(
              'From the CommuteBD service dataset',
              'কমিউটবিডি সার্ভিস ডেটাসেট থেকে',
            ),
          ),
          CardGroup(
            children: [
              for (final service in transit) _TransitRow(service: service),
            ],
          ),
        ],

        if (disclaimer.isNotEmpty) ...[
          const SizedBox(height: GochanoSpacing.md),
          _Disclaimer(text: disclaimer),
        ],
      ],
    );
  }
}

/// One transport option with its fare and, crucially, the provenance of that
/// fare (spec §68).
class _FareCard extends StatelessWidget {
  const _FareCard({
    required this.option,
    required this.originName,
    required this.destinationName,
    required this.distanceKm,
  });

  final Map<String, dynamic> option;
  final String originName;
  final String destinationName;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mode = option['mode']?.toString() ?? '';
    final label = option['label']?.toString() ?? mode;
    final minutes = (option['minutes'] as num?)?.toInt() ?? 0;
    final fareLow = (option['fareLow'] as num?)?.toDouble() ?? 0;
    final fareHigh = (option['fareHigh'] as num?)?.toDouble() ?? 0;
    final fareType = option['fareType']?.toString() ?? '';
    final source = option['source']?.toString() ?? '';
    final warning = option['warning']?.toString() ?? '';
    final transfers = (option['transfers'] as num?)?.toInt() ?? 0;
    final badges = ((option['badges'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    return AppCard(
      accent: badges.contains('Recommended') ? colors.commute : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GochanoIllustrationTile(
                GochanoArt.transportIdFor(mode),
                accent: colors.commute,
                plateSize: 44,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: context.type.sectionHeading),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _duration(minutes),
                        if (transfers > 0)
                          GochanoLanguage.text(
                            transfers == 1 ? '1 transfer' : '$transfers transfers',
                            '$transfers বার পরিবর্তন',
                          ),
                      ].join(' · '),
                      style: context.type.bodySecondary,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fareRange(fareLow, fareHigh),
                    style: context.type.statisticSmall,
                  ),
                  JourneyFareBadge(fareType: fareType),
                ],
              ),
            ],
          ),

          if (badges.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Wrap(
              spacing: GochanoSpacing.xxs,
              children: [
                for (final badge in badges)
                  GochanoBadge(
                    label: _badgeLabel(badge),
                    tone: badge == 'Recommended'
                        ? GochanoBadgeTone.brand
                        : GochanoBadgeTone.neutral,
                    icon: switch (badge) {
                      'Recommended' => Icons.star_rounded,
                      'Cheapest' => Icons.savings_outlined,
                      'Fastest' => Icons.bolt_rounded,
                      _ => null,
                    },
                  ),
              ],
            ),
          ],

          // Where the number came from. This is the part that keeps an
          // estimate from reading like an official fare.
          //
          // The raw confidence word is deliberately not shown: the provenance
          // badge above already says how far to trust the number, and
          // "Confidence: Low" beside it read as a second, vaguer verdict on
          // the same thing. The server now sends the source as a sentence
          // rather than an id like USER_PROVIDED_ASSUMPTION.
          if (source.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(source, style: context.type.caption),
          ],

          if (warning.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: colors.warning,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    warning,
                    style: context.type.caption.copyWith(color: colors.warning),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: GochanoSpacing.xs),
          // Post-trip confirmation (spec §69). An estimate never enters the
          // expense ledger by itself — the student reports what they actually
          // paid, and only that becomes an expense.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showFareReportSheet(
                context,
                mode: mode,
                modeLabel: label,
                originName: originName,
                destinationName: destinationName,
                distanceKm: distanceKm,
                tripMinutes: minutes,
                suggestedFare: fareHigh,
              ),
              icon: const Icon(
                Icons.receipt_long_outlined,
                size: GochanoSizes.iconSm,
              ),
              label: Text(
                GochanoLanguage.text(
                  'I took this — record actual fare',
                  'আমি এটি নিয়েছি — আসল ভাড়া দিন',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _badgeLabel(String badge) => switch (badge) {
        'Recommended' => GochanoLanguage.text('Recommended', 'প্রস্তাবিত'),
        'Cheapest' => GochanoLanguage.text('Cheapest', 'সবচেয়ে সস্তা'),
        'Fastest' => GochanoLanguage.text('Fastest', 'দ্রুততম'),
        _ => badge,
      };
}

class _TransitRow extends StatelessWidget {
  const _TransitRow({required this.service});

  final Map<String, dynamic> service;

  @override
  Widget build(BuildContext context) {
    final name = service['serviceName']?.toString() ??
        service['name']?.toString() ??
        service['busName']?.toString() ??
        '';
    final from = service['fromStop']?.toString() ?? '';
    final to = service['toStop']?.toString() ?? '';
    final stops = service['stopCount'];

    return GochanoListRow(
      illustration: GochanoArt.modeBus,
      accent: context.colors.commute,
      title: name.isEmpty
          ? GochanoLanguage.text('Bus service', 'বাস সার্ভিস')
          : name,
      subtitle: from.isEmpty && to.isEmpty ? null : '$from → $to',
      metadata: [
        if (stops is num)
          GochanoLanguage.text('${stops.toInt()} stops', '${stops.toInt()} স্টপ'),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: GochanoSizes.iconSm,
            color: colors.textSecondary,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(child: Text(text, style: context.type.caption)),
        ],
      ),
    );
  }
}

String _duration(int minutes) {
  if (minutes < 60) {
    return GochanoLanguage.text('$minutes min', '$minutes মিনিট');
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return GochanoLanguage.text('$hours h', '$hours ঘণ্টা');
  return GochanoLanguage.text('$hours h $rest min', '$hours ঘণ্টা $rest মিনিট');
}

String _fareRange(double low, double high) {
  if (low <= 0 && high <= 0) return GochanoLanguage.text('Free', 'ফ্রি');
  if ((high - low).abs() < 0.5) return formatTaka(high);
  return '${formatTaka(low)}–${formatTaka(high)}';
}
