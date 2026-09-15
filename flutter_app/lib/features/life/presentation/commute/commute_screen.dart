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
import 'plan_trip_sheet.dart';
import 'smart_journey_guide.dart';

class CommuteScreen extends StatefulWidget {
  const CommuteScreen({super.key, this.initialOrigin, this.initialDestination});

  final CommutePlace? initialOrigin;
  final CommutePlace? initialDestination;

  @override
  State<CommuteScreen> createState() => _CommuteScreenState();
}

class _CommuteScreenState extends State<CommuteScreen> {
  late CommutePlace? _origin = widget.initialOrigin;
  late CommutePlace? _destination = widget.initialDestination;
  int _selectedJourneyIndex = 0;

  bool _searching = false;
  String _error = '';
  String _errorTitle = '';
  Map<String, dynamic>? _result;
  String? _selectedTransportMode;
  Map<String, dynamic>? _singleFareResult;
  bool _fetchingFare = false;
  String _singleFareError = '';

  List<DirectBusCandidate> _directBuses = [];
  bool _fetchingDirectBuses = false;
  String _directBusesError = '';
  String? _selectedBusServiceId;
  String? _selectedBusName;
  DirectBusCandidate? _selectedBusCandidate;

  bool get _canSearch => _origin != null && _destination != null && !_searching;

  void _clearPreviousResult() {
    _result = null;
    _selectedTransportMode = null;
    _singleFareResult = null;
    _singleFareError = '';
    _error = '';
    _errorTitle = '';
    _directBuses = [];
    _fetchingDirectBuses = false;
    _directBusesError = '';
    _selectedBusServiceId = null;
    _selectedBusName = null;
    _selectedBusCandidate = null;
  }

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
      _clearPreviousResult();
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
      _clearPreviousResult();
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
      _clearPreviousResult();
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
      _directBuses = [];
      _directBusesError = '';
      _selectedBusServiceId = null;
      _selectedBusName = null;
      _selectedBusCandidate = null;
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
      if (origin.placeId != null &&
          origin.placeId!.isNotEmpty &&
          destination.placeId != null &&
          destination.placeId!.isNotEmpty) {
        _fetchDirectBuses(origin.placeId!, destination.placeId!);
      }
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

  Future<void> _fetchDirectBuses(
    String originPlaceId,
    String destinationPlaceId,
  ) async {
    setState(() {
      _fetchingDirectBuses = true;
      _directBusesError = '';
      _directBuses = [];
    });

    try {
      final res = await ApiService.directBusMatch(
        originPlaceId: originPlaceId,
        destinationPlaceId: destinationPlaceId,
      );
      if (!mounted) return;
      final rawList = (res['results'] as List?) ?? const [];
      final candidates = rawList
          .whereType<Map<String, dynamic>>()
          .map(DirectBusCandidate.fromJson)
          .toList();
      setState(() {
        _fetchingDirectBuses = false;
        _directBuses = candidates;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchingDirectBuses = false;
        _directBusesError = GochanoLanguage.text(
          'Could not load direct buses for this stop pair.',
          'এই স্টপ জুটির জন্য সরাসরি বাসের তথ্য লোড করা যায়নি।',
        );
      });
    }
  }

  void _onBusSelected(DirectBusCandidate bus) {
    setState(() {
      _selectedBusServiceId = bus.serviceId;
      _selectedBusName = bus.operatorName;
      _selectedBusCandidate = bus;
    });
    _fetchModeFare('bus', busServiceId: bus.serviceId);
  }

  void _onModeSelected(String mode) {
    setState(() {
      _selectedTransportMode = mode;
      if (mode != 'bus') {
        _selectedBusServiceId = null;
        _selectedBusName = null;
        _selectedBusCandidate = null;
      }
      _singleFareResult = null;
      _singleFareError = '';
    });
    _fetchModeFare(mode);
    _fetchModeFare(
      mode,
      busServiceId: mode == 'bus' ? _selectedBusServiceId : null,
    );
  }

  Future<void> _fetchModeFare(String mode, {String? busServiceId}) async {
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
      final sId = busServiceId ?? _selectedBusServiceId;
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
        busServiceId: sId,
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
        _singleFareError = _fareErrorLabel(error);
      });
    }
  }

  void _openAskTrip(BuildContext context, JourneyGuideFacts facts) {
    // Build a context message summarising the trip for the AI assistant.
    final buffer = StringBuffer('Trip context:\n');
    buffer.writeln('${facts.originName} to ${facts.destinationName}');
    if (facts.hasDistance) {
      buffer.writeln('Distance: ${facts.distanceKm!.toStringAsFixed(1)} km');
    }
    if (facts.hasDuration) {
      buffer.writeln('Duration: ${facts.durationMinutes} min');
    }
    if (facts.modeLabel != null) buffer.writeln('Mode: ${facts.modeLabel}');
    if (facts.hasFare) {
      buffer.writeln(
        'Fare: ৳${facts.fareLow!.toInt()}-${facts.fareHigh!.toInt()}',
      );
    }
    buffer.writeln(
      '\nUse this trip context as authoritative. '
      'If the user asks about route facts not present here, '
      'say that information is not available.',
    );

    // Navigate to the AI assistant with the trip context pre-loaded.
    // For now, show a bottom sheet with the trip context as a starting point.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(GochanoSpacing.md),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text(
                'Ask about this trip',
                'এই যাত্রা সম্পর্কে জিজ্ঞাসা করুন',
              ),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text(buffer.toString(), style: context.type.bodySecondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final plan = result != null ? JourneyPlan.fromResponse(result) : null;
    final journeys = plan?.journeys ?? const [];
    final selectedJourney = journeys.isNotEmpty
        ? journeys[_selectedJourneyIndex.clamp(0, journeys.length - 1)]
        : null;

    // Build geometry and endpoints for route map
    final originMap = result?['origin'] as Map?;
    final destinationMap = result?['destination'] as Map?;
    LatLng? point(Map? place) {
      final lat = (place?['lat'] as num?)?.toDouble();
      final lon = (place?['lon'] as num?)?.toDouble();
      return (lat == null || lon == null) ? null : LatLng(lat, lon);
    }

    final rawPolyline = ((result?['polyline'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    // If a selected journey has mappable legs, construct polyline and transfers from it
    final List<Map<String, dynamic>> displayPolyline;
    final List<LatLng> transferPoints = [];
    if (selectedJourney != null) {
      final mappableLegs = selectedJourney.legs
          .where((l) => l.isMappable)
          .toList();
      if (mappableLegs.isNotEmpty) {
        displayPolyline = [
          for (final leg in mappableLegs) ...[
            {'lat': leg.fromLat, 'lon': leg.fromLon},
            {'lat': leg.toLat, 'lon': leg.toLon},
          ],
        ];
        for (var i = 0; i < mappableLegs.length - 1; i++) {
          final leg = mappableLegs[i];
          if (leg.toLat != null && leg.toLon != null) {
            transferPoints.add(LatLng(leg.toLat!, leg.toLon!));
          }
        }
      } else {
        displayPolyline = rawPolyline;
      }
    } else {
      displayPolyline = rawPolyline;
    }

    // Check if estimated fallback applies — either the backend flagged it,
    // or the transit planner produced no journeys but road data was available
    // (fallback was built from road data).
    final roadDataAvailable =
        ((result?['distanceKm'] as num?)?.toDouble() ?? 0) > 0 ||
        ((result?['estimatedDurationMin'] as num?)?.toInt() ?? 0) > 0;
    final isEstimatedFallback =
        result != null &&
        (result['isEstimated'] == true ||
            result['routingProvider'] == 'osrm_fallback' ||
            result['routingProvider'] == 'haversine' ||
            (plan != null &&
                (plan.status == JourneyPlanningStatus.datasetUnavailable ||
                    plan.status == JourneyPlanningStatus.outsideCoverage ||
                    plan.status == JourneyPlanningStatus.plannerError)) ||
            (plan != null && !plan.hasJourneys && roadDataAvailable));

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Commute', 'যাতায়াত'),
        subtitle: GochanoLanguage.text(
          'Plan your route and compare fares',
          'আপনার রুট পরিকল্পনা করুন এবং ভাড়া তুলনা করুন',
        ),
        actions: [
          IconButton(
            tooltip: GochanoLanguage.text(
              'Plan a trip',
              'ভবিষ্যৎ যাত্রা পরিকল্পনা',
            ),
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => showPlanTripSheet(
              context,
              initialOrigin: _origin,
              initialDestination: _destination,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          // 1. From / To Trip Planner
          _TripPlanner(
            origin: _origin,
            destination: _destination,
            onPickOrigin: () => _pick(isOrigin: true),
            onPickDestination: () => _pick(isOrigin: false),
            onSwap: _swap,
          ),
          const SizedBox(height: GochanoSpacing.md),

          // 2. Map (Picker when no result; route map when result present)
          if (result == null)
            CommuteMapPicker(
              origin: _origin,
              destination: _destination,
              onPicked: _pickFromMap,
            )
          else ...[
            CommuteRouteMap(
              polyline: displayPolyline,
              origin:
                  point(originMap) ??
                  (_origin?.lat != null && _origin?.lon != null
                      ? LatLng(_origin!.lat!, _origin!.lon!)
                      : null),
              destination:
                  point(destinationMap) ??
                  (_destination?.lat != null && _destination?.lon != null
                      ? LatLng(_destination!.lat!, _destination!.lon!)
                      : null),
              transfers: transferPoints,
            ),
          ],
          const SizedBox(height: GochanoSpacing.md),

          // 3. Find routes / Checking route button
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

          // 4. Optional estimated-details banner
          if (isEstimatedFallback) ...[
            const SizedBox(height: GochanoSpacing.md),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: context.colors.surfaceVariant,
                borderRadius: GochanoRadius.mdAll,
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: GochanoSizes.iconSm,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        'Some route details are estimated',
                        'কিছু রুটের বিবরণ আনুমানিক',
                      ),
                      style: context.type.bodySecondary,
                    ),
                  ),
                ],
              ),
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

          // 5-8. Results section (Distance / By road -> Your journey -> Multimodal alternatives -> Choose transport / fare)
          if (result != null) ...[
            // Build Smart Journey Guide facts from the authoritative data
            _SmartGuideFactsBuilder(
              result: result,
              selectedMode: _selectedTransportMode,
              singleFareResult: _singleFareResult,
              selectedJourneyIndex: _selectedJourneyIndex,
              selectedBusCandidate: _selectedBusCandidate,
              builder: (context, guideFacts) => _Results(
                result: result,
                selectedMode: _selectedTransportMode,
                singleFareResult: _singleFareResult,
                fetchingFare: _fetchingFare,
                singleFareError: _singleFareError,
                onModeSelected: _onModeSelected,
                selectedJourneyIndex: _selectedJourneyIndex,
                onJourneySelected: (idx) =>
                    setState(() => _selectedJourneyIndex = idx),
                onPlanTrip: () => showPlanTripSheet(
                  context,
                  initialOrigin: _origin,
                  initialDestination: _destination,
                ),
                guideFacts: guideFacts,
                onAskTrip: guideFacts != null
                    ? () => _openAskTrip(context, guideFacts)
                    : null,
                directBuses: _directBuses,
                fetchingDirectBuses: _fetchingDirectBuses,
                directBusesError: _directBusesError,
                selectedBusServiceId: _selectedBusServiceId,
                selectedBusName: _selectedBusName,
                onBusSelected: _onBusSelected,
                onRetryDirectBuses: (_origin?.placeId != null &&
                        _destination?.placeId != null)
                    ? () => _fetchDirectBuses(
                          _origin!.placeId!,
                          _destination!.placeId!,
                        )
                    : null,
                originPlaceId: _origin?.placeId,
                destinationPlaceId: _destination?.placeId,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Builds JourneyGuideFacts from the route result and passes them to the
/// builder. This is a pure derivation — no network calls, no AI.
class _SmartGuideFactsBuilder extends StatelessWidget {
  const _SmartGuideFactsBuilder({
    required this.result,
    required this.builder,
    this.selectedMode,
    this.singleFareResult,
    this.selectedJourneyIndex = 0,
    this.selectedBusCandidate,
  });

  final Map<String, dynamic> result;
  final Widget Function(BuildContext, JourneyGuideFacts?) builder;
  final String? selectedMode;
  final Map<String, dynamic>? singleFareResult;
  final int selectedJourneyIndex;
  final DirectBusCandidate? selectedBusCandidate;

  @override
  Widget build(BuildContext context) {
    final plan = JourneyPlan.fromResponse(result);
    final journeys = plan.journeys;

    JourneyGuideFacts? facts;

    if (journeys.isNotEmpty) {
      final journey =
          journeys[selectedJourneyIndex.clamp(0, journeys.length - 1)];
      facts = JourneyGuideFacts.fromJourney(
        journey,
        selectedMode: selectedMode,
        singleFareResult: singleFareResult,
        selectedBusOperator: selectedBusCandidate?.operatorName,
        selectedBusBoardStop: selectedBusCandidate?.originStopName,
        selectedBusExitStop: selectedBusCandidate?.destinationStopName,
        selectedBusStopCount: selectedBusCandidate?.stopCount,
      );
    } else {
      // Road-only fallback — no real multimodal journey
      facts = JourneyGuideFacts.fromRoadRoute(
        result: result,
        selectedMode: selectedMode,
        singleFareResult: singleFareResult,
        selectedBusOperator: selectedBusCandidate?.operatorName,
        selectedBusBoardStop: selectedBusCandidate?.originStopName,
        selectedBusExitStop: selectedBusCandidate?.destinationStopName,
        selectedBusStopCount: selectedBusCandidate?.stopCount,
      );
    }

    // Only render if we have minimum viable facts
    if (facts.originName.isEmpty && facts.destinationName.isEmpty) {
      facts = null;
    }

    return builder(context, facts);
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
                        : GochanoLanguage.text(
                            'Choose a place',
                            'একটি স্থান বাছুন',
                          ),
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
    this.selectedJourneyIndex = 0,
    this.onJourneySelected,
    this.onPlanTrip,
    this.guideFacts,
    this.onAskTrip,
    this.directBuses = const [],
    this.fetchingDirectBuses = false,
    this.directBusesError = '',
    this.selectedBusServiceId,
    this.selectedBusName,
    this.onBusSelected,
    this.onRetryDirectBuses,
    this.originPlaceId,
    this.destinationPlaceId,
  });

  final Map<String, dynamic> result;
  final String? selectedMode;
  final Map<String, dynamic>? singleFareResult;
  final bool fetchingFare;
  final String singleFareError;
  final ValueChanged<String>? onModeSelected;
  final int selectedJourneyIndex;
  final ValueChanged<int>? onJourneySelected;
  final VoidCallback? onPlanTrip;
  final JourneyGuideFacts? guideFacts;
  final VoidCallback? onAskTrip;
  final List<DirectBusCandidate> directBuses;
  final bool fetchingDirectBuses;
  final String directBusesError;
  final String? selectedBusServiceId;
  final String? selectedBusName;
  final ValueChanged<DirectBusCandidate>? onBusSelected;
  final VoidCallback? onRetryDirectBuses;
  final String? originPlaceId;
  final String? destinationPlaceId;

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

    // Build the journey plan, falling back to road-route estimation when
    // the public-transit planner is unavailable but road data exists.
    var plan = JourneyPlan.fromResponse(result);
    if (!plan.hasJourneys) {
      final fallback = JourneyPlan.roadFallback(
        result,
        selectedMode: selectedMode,
        singleFareResult: singleFareResult,
      );
      if (fallback != null) plan = fallback;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        JourneyPlanSection(
          plan: plan,
          selectedIndex: selectedJourneyIndex,
          onJourneySelected: onJourneySelected,
          hideMap: true,
        ),

        // Smart Journey Guide — verified facts + optional AI explanation
        if (guideFacts != null) ...[
          SmartJourneyGuide(facts: guideFacts!, onAskTrip: onAskTrip),
        ],

        // Transport mode selector
        SectionHeader(
          title: GochanoLanguage.text('Choose transport', 'যানবাহন বাছুন'),
        ),
        _TransportModeSelector(
          selectedMode: selectedMode,
          onModeSelected: onModeSelected,
        ),

        // Possible buses section when bus mode is active
        if (selectedMode == 'bus') ...[
          _PossibleBusesSection(
            buses: directBuses,
            loading: fetchingDirectBuses,
            error: directBusesError,
            selectedBusServiceId: selectedBusServiceId,
            onBusSelected: onBusSelected ?? (_) {},
            onRetry: onRetryDirectBuses,
          ),
        ],

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
              originPlaceId: originPlaceId,
              destinationPlaceId: destinationPlaceId,
              selectedBusServiceId: selectedBusServiceId,
              selectedBusName: selectedBusName,
              directBuses: directBuses,
            ),
        ],

        // Action to report fare when in bus mode if fare is not loaded yet
        if (selectedMode == 'bus' &&
            singleFareResult == null &&
            !fetchingFare &&
            singleFareError.isEmpty) ...[
          const SizedBox(height: GochanoSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showFareReportSheet(
                context,
                mode: 'bus',
                modeLabel: GochanoLanguage.text('Bus', 'বাস'),
                originName: originName,
                destinationName: destinationName,
                distanceKm: distanceKm,
                tripMinutes: minutes,
                suggestedFare: null,
                originPlaceId: originPlaceId,
                destinationPlaceId: destinationPlaceId,
                initialBusServiceId: selectedBusServiceId,
                initialBusName: selectedBusName,
                busCandidates: directBuses,
              ),
              icon: const Icon(
                Icons.receipt_long_outlined,
                size: GochanoSizes.iconSm,
              ),
              label: Text(
                GochanoLanguage.text(
                  'Report bus fare',
                  'বাসের ভাড়া জানান',
                ),
              ),
            ),
          ),
        ],

        if (transit.isNotEmpty && selectedMode != 'bus') ...[
          SectionHeader(
            title: GochanoLanguage.text('Buses on this route', 'এই রুটের বাস'),
            subtitle: GochanoLanguage.text(
              'From the Commute service dataset',
              'কমিউট সার্ভিস ডেটাসেট থেকে',
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

        if (onPlanTrip != null) ...[
          const SizedBox(height: GochanoSpacing.lg),
          SecondaryButton(
            label: GochanoLanguage.text(
              'Plan this trip',
              'এই যাত্রা পরিকল্পনা করুন',
            ),
            icon: Icons.calendar_month_outlined,
            onPressed: onPlanTrip,
          ),
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
  const _TransportModeSelector({this.selectedMode, this.onModeSelected});

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
                  color: selectedMode == mode ? colors.commute : colors.divider,
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

/// Possible buses section showing verified direct bus services on the route.
class _PossibleBusesSection extends StatelessWidget {
  const _PossibleBusesSection({
    required this.buses,
    required this.loading,
    required this.error,
    this.selectedBusServiceId,
    required this.onBusSelected,
    this.onRetry,
  });

  final List<DirectBusCandidate> buses;
  final bool loading;
  final String error;
  final String? selectedBusServiceId;
  final ValueChanged<DirectBusCandidate> onBusSelected;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: GochanoSpacing.md),
        SectionHeader(
          title: GochanoLanguage.text('Possible buses', 'সম্ভাব্য বাস'),
          subtitle: GochanoLanguage.text(
            'Direct bus services on this route',
            'এই রুটের সরাসরি বাস সেবা',
          ),
        ),
        if (loading) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(GochanoSpacing.md),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ] else if (error.isNotEmpty) ...[
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    error,
                    style: type.bodySecondary.copyWith(color: colors.warning),
                  ),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child:
                        Text(GochanoLanguage.text('Retry', 'পুনরায় চেষ্টা')),
                  ),
              ],
            ),
          ),
        ] else if (buses.isEmpty) ...[
          AppCard(
            child: Text(
              GochanoLanguage.text(
                'No direct bus services found for this stop pair.',
                'এই স্টপ জুটির জন্য কোনো সরাসরি বাস সেবা পাওয়া যায়নি।',
              ),
              style: type.bodySecondary,
            ),
          ),
        ] else ...[
          CardGroup(
            children: [
              for (final bus in buses)
                _DirectBusRow(
                  bus: bus,
                  isSelected: bus.serviceId == selectedBusServiceId,
                  onTap: () => onBusSelected(bus),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Single row representing a direct bus service option.
class _DirectBusRow extends StatelessWidget {
  const _DirectBusRow({
    required this.bus,
    required this.isSelected,
    required this.onTap,
  });

  final DirectBusCandidate bus;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final displayName = GochanoLanguage.text(
      bus.operatorName,
      bus.operatorNameBn ?? bus.operatorName,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        decoration: isSelected
            ? BoxDecoration(
                color: colors.commute.withValues(alpha: 0.08),
                borderRadius: GochanoRadius.smAll,
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? colors.commute
                    : colors.commute.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.directions_bus_rounded,
                size: 18,
                color: isSelected ? colors.surface : colors.commute,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: type.body.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isSelected
                                ? colors.commute
                                : colors.textPrimary,
                          ),
                        ),
                      ),
                      if (bus.serviceType.isNotEmpty &&
                          bus.serviceType != 'regular') ...[
                        const SizedBox(width: GochanoSpacing.xxs),
                        GochanoBadge(
                          label: bus.serviceType,
                          tone: GochanoBadgeTone.neutral,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${bus.originStopName} → ${bus.destinationStopName} · ${bus.stopCount} ${GochanoLanguage.text('stops', 'টি স্টপ')}',
                    style: type.caption,
                  ),
                  if (bus.hasQualifiedCrowdFare) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          bus.crowdFareLow != null && bus.crowdFareHigh != null
                              ? (bus.crowdFareLow == bus.crowdFareHigh
                                  ? formatTaka(bus.crowdFareLow!)
                                  : '${formatTaka(bus.crowdFareLow!)}–${formatTaka(bus.crowdFareHigh!)}')
                              : (bus.crowdFareRecommended != null
                                  ? formatTaka(bus.crowdFareRecommended!)
                                  : ''),
                          style: type.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.commute,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            GochanoLanguage.text(
                              bus.crowdFareLabel ?? 'Community estimate',
                              bus.crowdFareLabelBn ?? 'কমিউনিটি হিসাব',
                            ),
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: colors.commute,
              ),
          ],
        ),
      ),
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
    this.originPlaceId,
    this.destinationPlaceId,
    this.selectedBusServiceId,
    this.selectedBusName,
    this.directBuses = const [],
  });

  final Map<String, dynamic> result;
  final String originName;
  final String destinationName;
  final double distanceKm;
  final String? originPlaceId;
  final String? destinationPlaceId;
  final String? selectedBusServiceId;
  final String? selectedBusName;
  final List<DirectBusCandidate> directBuses;

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
                    GochanoLanguage.text('Not available', 'অনুপলব্ধ'),
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
    final minutes =
        (fare['minutes'] as num?)?.toInt() ??
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
                    Text(_duration(minutes), style: context.type.bodySecondary),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fareRange(fareLow, fareHigh, mode: mode),
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
                suggestedFare: fareHigh > 0 ? fareHigh : null,
                originPlaceId: originPlaceId,
                destinationPlaceId: destinationPlaceId,
                initialBusServiceId: selectedBusServiceId,
                initialBusName: selectedBusName,
                busCandidates: directBuses,
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
    final name =
        service['serviceName']?.toString() ??
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
          GochanoLanguage.text(
            '${stops.toInt()} stops',
            '${stops.toInt()} স্টপ',
          ),
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

String _fareRange(double low, double high, {String mode = ''}) {
  if (low <= 0 && high <= 0) {
    if (mode == 'walk') return GochanoLanguage.text('Free', 'ফ্রি');
    return GochanoLanguage.text('Fare unavailable', 'ভাড়া তথ্য নেই');
  }
  if ((high - low).abs() < 0.5) return formatTaka(high);
  return '${formatTaka(low)}–${formatTaka(high)}';
}

/// Commute-specific error label — never shows generic resource messages like
/// "This item is no longer available." which `friendlyErrorMessage` would
/// produce for a 404.
String _fareErrorLabel(Object error) {
  final raw = error.toString().toLowerCase();

  // Network / connectivity.
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network is unreachable') ||
      raw.contains('connection closed') ||
      raw.contains('connection refused') ||
      raw.contains('clientexception')) {
    return GochanoLanguage.text(
      'Could not load fare estimate. Check your connection and try again.',
      'ভাড়ার তথ্য লোড হয়নি। সংযোগ দেখে আবার চেষ্টা করুন।',
    );
  }

  // Timeout.
  if (raw.contains('timeoutexception') ||
      raw.contains('timed out') ||
      raw.contains('taking longer than expected')) {
    return GochanoLanguage.text(
      'Could not load fare estimate. The server took too long. Try again.',
      'ভাড়ার তথ্য লোড হয়নি। সার্ভার ধীরে সাড়া দিচ্ছে। আবার চেষ্টা করুন।',
    );
  }

  // Backend returned a readable detail string — surface it directly when it
  // looks like prose (short, no exception trace).  FastAPI validation errors
  // (422) and mode-not-supported messages arrive here.
  if (raw.isNotEmpty &&
      raw.length <= 200 &&
      !raw.contains('exception') &&
      !raw.contains('traceback') &&
      !raw.contains('{') &&
      !raw.contains('\n')) {
    return error.toString();
  }

  // Everything else — generic but honest.
  return GochanoLanguage.text(
    'Could not load fare estimate. Try again.',
    'ভাড়ার তথ্য লোড হয়নি। আবার চেষ্টা করুন।',
  );
}
