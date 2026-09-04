// CommuteBD (spec §60–§69).
//
// Flow: From → To → Find routes → User selects transport mode → fare for
// selected mode only.
//
// What this screen is honest about
// --------------------------------
// Every fare card states where its number came from and how much to trust it.
// The backend labels each option `official` / `crowdsourced` / `historical` /
// `estimated`, and that label is surfaced verbatim rather than flattened into
// one confident-looking price (spec §68: "Never label estimated values as
// official").
//
// Changing transport mode does NOT rerun the OSRM route calculation. The
// route (distance, duration, polyline) is preserved from the initial
// "Find routes" call. Only the fare section is updated via
// `POST /api/commute/single-fare`.
//
// This screen calls `POST /api/commute/routes` — the PostgreSQL/PostGIS-backed
// endpoint that resolves canonical CommuteBD places, ranks options, and
// returns real bus services connecting the two stops.

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
  String _errorTitle = '';
  Map<String, dynamic>? _result;
  String? _selectedTransportMode;
  Map<String, dynamic>? _singleFareResult;
  bool _fetchingFare = false;
  String _singleFareError = '';

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
      _selectedTransportMode = null;
      _singleFareResult = null;
      _singleFareError = '';
      _error = '';
      _errorTitle = '';
    });
  }

  void _swap() {
    setState(() {
      final from = _origin;
      _origin = _destination;
      _destination = from;
      _result = null;
      _selectedTransportMode = null;
      _singleFareResult = null;
      _singleFareError = '';
      _error = '';
      _errorTitle = '';
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
      _selectedTransportMode = null;
      _singleFareResult = null;
      _singleFareError = '';
      _error = '';
      _errorTitle = '';
    });
  }

  Future<void> _findRoutes() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;

    setState(() {
      _searching = true;
      _error = '';
      _errorTitle = '';
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
      final msg = friendlyErrorMessage(error);
      String title;
      if (msg.contains('Could not find')) {
        title = GochanoLanguage.text(
          'Location not found',
          'লোকেশন পাওয়া যায়নি',
        );
      } else if (msg.contains('temporarily unavailable') ||
          msg.contains('route calculation')) {
        title = GochanoLanguage.text(
          'Routing unavailable',
          'রুট ব্যবস্থা অনুপলব্ধ',
        );
      } else {
        title = GochanoLanguage.text(
          'Could not find routes',
          'রুট খুঁজে পাওয়া যায়নি',
        );
      }
      setState(() {
        _searching = false;
        _error = msg;
        _errorTitle = title;
      });
    }
  }

  void _onModeSelected(String mode) {
    setState(() {
      _selectedTransportMode = mode;
      _singleFareResult = null;
      _singleFareError = '';
    });
    _fetchModeFare(mode);
  }

  Future<void> _fetchModeFare(String mode) async {
    final origin = _origin;
    final destination = _destination;
    final result = _result;
    if (origin == null || destination == null || result == null) {
      return;
    }
    if (origin.lat == null ||
        origin.lon == null ||
        destination.lat == null ||
        destination.lon == null) {
      return;
    }

    final distanceKm = (result['distanceKm'] as num?)?.toDouble();
    final drivingMinutes = (result['estimatedDurationMin'] as num?)?.toInt();
    if (distanceKm == null || drivingMinutes == null) {
      return;
    }

    setState(() {
      _fetchingFare = true;
      _singleFareError = '';
      _singleFareResult = null;
    });

    try {
      final body = await ApiService.commuteSingleFare(
        originPlaceId: origin.placeId ?? '',
        originName: origin.name,
        originLat: origin.lat!,
        originLon: origin.lon!,
        destinationPlaceId: destination.placeId ?? '',
        destinationName: destination.name,
        destinationLat: destination.lat!,
        destinationLon: destination.lon!,
        mode: mode,
        distanceKm: distanceKm,
        drivingMinutes: drivingMinutes,
      );
      if (!mounted) return;
      setState(() {
        _fetchingFare = false;
        _singleFareResult = body;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _fetchingFare = false;
        _singleFareError = friendlyErrorMessage(error);
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
              title: _errorTitle.isNotEmpty ? _errorTitle : null,
              message: _error,
              onRetry: _canSearch ? _findRoutes : null,
            ),
          ],

          if (_result != null)
            _Results(
              result: _result!,
              selectedMode: _selectedTransportMode,
              singleFareResult: _singleFareResult,
              fetchingFare: _fetchingFare,
              singleFareError: _singleFareError,
              onModeSelected: _onModeSelected,
            ),
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
  const _Results({
    required this.result,
    this.selectedMode,
    this.singleFareResult,
    this.fetchingFare = false,
    this.singleFareError = '',
    this.onModeSelected,
  });

  final Map<String, dynamic> result;
  final String? selectedMode;
  final Map<String, dynamic>? singleFareResult;
  final bool fetchingFare;
  final String singleFareError;
  final ValueChanged<String>? onModeSelected;

  @override
  Widget build(BuildContext context) {
    final distanceKm = (result['distanceKm'] as num?)?.toDouble() ?? 0;
    final minutes = (result['estimatedDurationMin'] as num?)?.toInt() ?? 0;
    final provider = result['routingProvider']?.toString() ?? '';
    final disclaimer = result['disclaimer']?.toString() ?? '';

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

        // The multimodal planner: the actual journey, step by step.
        JourneyPlanSection(plan: JourneyPlan.fromResponse(result)),

        // Transport mode selector
        SectionHeader(
          title: GochanoLanguage.text(
            'Choose transport',
            'যানবাহন বাছুন',
          ),
        ),
        _TransportModeSelector(
          selectedMode: selectedMode,
          onModeSelected: onModeSelected,
        ),

        // Single fare result area
        if (selectedMode != null) ...[
          const SizedBox(height: GochanoSpacing.sm),
          if (fetchingFare)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(GochanoSpacing.md),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (singleFareError.isNotEmpty)
            AppCard(
              child: Text(
                singleFareError,
                style: context.type.bodySecondary.copyWith(
                  color: context.colors.error,
                ),
              ),
            )
          else if (singleFareResult != null)
            _SingleFareResultCard(
              result: singleFareResult!,
              originName: originName,
              destinationName: destinationName,
              distanceKm: distanceKm,
            ),
        ],

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

/// Compact transport mode selector shown after route calculation.
///
/// Renders a horizontal row of mode chips. Only one can be active at a time.
/// Modes are not automatically labeled Recommended / Cheapest / Fastest.
class _TransportModeSelector extends StatelessWidget {
  const _TransportModeSelector({
    this.selectedMode,
    this.onModeSelected,
  });

  final String? selectedMode;
  final ValueChanged<String>? onModeSelected;

  static const _modes = [
    ('bus', 'Bus', 'বাস'),
    ('cng', 'CNG', 'সিএনজি'),
    ('rickshaw', 'Rickshaw', 'রিকশা'),
    ('auto', 'Auto', 'অটো'),
    ('metro', 'Metro', 'মেট্রো'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: GochanoSpacing.sm,
      runSpacing: GochanoSpacing.xs,
      children: [
        for (final (mode, label, labelBn) in _modes)
          GestureDetector(
            onTap: onModeSelected != null ? () => onModeSelected!(mode) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.md,
                vertical: GochanoSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: selectedMode == mode
                    ? colors.commute.withValues(alpha: 0.12)
                    : colors.surface,
                borderRadius: GochanoRadius.smAll,
                border: Border.all(
                  color: selectedMode == mode
                      ? colors.commute
                      : colors.divider,
                  width: selectedMode == mode ? 2 : 1,
                ),
              ),
              child: Text(
                GochanoLanguage.text(label, labelBn),
                style: context.type.body.copyWith(
                  color: selectedMode == mode
                      ? colors.commute
                      : colors.textPrimary,
                  fontWeight: selectedMode == mode
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Single fare result card for the user-selected transport mode.
///
/// Shows fare estimate, source, and warning. No badges (no Recommended /
/// Cheapest / Fastest labels).
class _SingleFareResultCard extends StatelessWidget {
  const _SingleFareResultCard({
    required this.result,
    required this.originName,
    required this.destinationName,
    required this.distanceKm,
  });

  final Map<String, dynamic> result;
  final String originName;
  final String destinationName;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final supported = result['supported'] as bool? ?? false;
    if (!supported) {
      final reason = result['reason']?.toString() ?? '';
      final mode = result['mode']?.toString() ?? '';
      return AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GochanoIllustrationTile(
              GochanoArt.transportIdFor(mode),
              accent: colors.textTertiary,
              plateSize: 44,
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    GochanoLanguage.text(
                      'Not available',
                      'অনুপলব্ধ',
                    ),
                    style: context.type.sectionHeading,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reason.isNotEmpty
                        ? reason
                        : GochanoLanguage.text(
                            'No supported fare data was found for this transport on this route.',
                            'এই রুটে এই যানবাহনের জন্য কোনো সমর্থিত ভাড়ার তথ্য পাওয়া যায়নি।',
                          ),
                    style: context.type.bodySecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final fare = result['fare'] as Map<String, dynamic>? ?? {};
    final mode = fare['mode']?.toString() ?? result['mode']?.toString() ?? '';
    final label = fare['label']?.toString() ?? mode;
    final minutes = (fare['minutes'] as num?)?.toInt() ??
        (result['drivingMinutes'] as num?)?.toInt() ??
        0;
    final fareLow = (fare['fareLow'] as num?)?.toDouble() ?? 0;
    final fareHigh = (fare['fareHigh'] as num?)?.toDouble() ?? 0;
    final fareType = fare['fareType']?.toString() ?? '';
    final source = fare['source']?.toString() ?? '';
    final warning = fare['warning']?.toString() ?? '';

    return AppCard(
      accent: colors.commute,
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
                      _duration(minutes),
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
