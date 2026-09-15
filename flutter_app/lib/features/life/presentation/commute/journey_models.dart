// The journey shapes returned by POST /api/commute/routes.
//
// The backend already does the hard part — it resolves every step to a real
// place name and labels every fare with its provenance — so these models
// stay deliberately thin. Their job is to parse defensively and to never
// invent a value the server did not send.

import 'package:flutter/foundation.dart';

/// One continuous stretch of a journey on a single mode.
@immutable
class JourneyLeg {
  const JourneyLeg({
    required this.mode,
    required this.modeLabel,
    required this.from,
    required this.to,
    required this.distanceKm,
    required this.durationMinutes,
    required this.fareTk,
    required this.fareType,
    required this.fareLabel,
    required this.fareSource,
    required this.instruction,
    required this.isTransfer,
    required this.transferMinutes,
    this.serviceName,
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
    this.fareAvailable = true,
    this.fareLow = 0,
    this.fareHigh = 0,
  });

  /// Backend mode id: walk, rickshaw, cng, bus, metro, train, boat.
  final String mode;

  /// Already-localised-for-English label from the backend.
  final String modeLabel;

  final String from;
  final String to;
  final double distanceKm;
  final int durationMinutes;
  final double fareTk;

  /// official | calculated | crowdsourced | historical | estimated | none.
  final String fareType;

  /// The word shown on the fare badge.
  final String fareLabel;

  /// Where the number came from, e.g. "Official MRT6 fare table".
  final String fareSource;

  /// A sentence the student can act on.
  final String instruction;

  final bool isTransfer;
  final int transferMinutes;

  /// "MRT Line 6", "Bikalpa Paribahan" — null when the dataset has no name,
  /// in which case nothing is invented.
  final String? serviceName;

  /// Endpoint coordinates. Null when the dataset has no coordinates for that
  /// stop — the step still shows in the timeline, it just is not drawn on the
  /// map. Nothing is interpolated to cover the gap.
  final double? fromLat;
  final double? fromLon;
  final double? toLat;
  final double? toLon;

  /// Whether fare data is available for this leg. When `false`, the UI
  /// should show "Fare unavailable" instead of "Free" or ৳0.
  final bool fareAvailable;

  /// Fare range low/high from the canonical single-fare API. When both are
  /// > 0, the UI shows the range (e.g. ৳280–320). When only `fareTk` is
  /// set, the UI shows a single value.
  final double fareLow;
  final double fareHigh;

  bool get isFree => fareTk <= 0 && fareAvailable;

  bool get isMappable =>
      fromLat != null && fromLon != null && toLat != null && toLon != null;

  static JourneyLeg fromJson(Map<String, dynamic> json) {
    double asDouble(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    int asInt(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;

    return JourneyLeg(
      mode: json['mode']?.toString() ?? '',
      modeLabel: json['modeLabel']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      distanceKm: asDouble(json['distanceKm']),
      durationMinutes: asInt(json['durationMinutes']),
      fareTk: asDouble(json['fareTk']),
      fareType: json['fareType']?.toString() ?? 'estimated',
      fareLabel: json['fareLabel']?.toString() ?? '',
      fareSource: json['fareSource']?.toString() ?? '',
      instruction: json['instruction']?.toString() ?? '',
      isTransfer: json['isTransfer'] == true,
      transferMinutes: asInt(json['transferMinutes']),
      serviceName: (json['serviceName']?.toString().trim().isEmpty ?? true)
          ? null
          : json['serviceName'].toString(),
      fromLat: (json['fromLat'] as num?)?.toDouble(),
      fromLon: (json['fromLon'] as num?)?.toDouble(),
      toLat: (json['toLat'] as num?)?.toDouble(),
      toLon: (json['toLon'] as num?)?.toDouble(),
      fareAvailable: json['fareAvailable'] != false,
      fareLow: asDouble(json['fareLow']),
      fareHigh: asDouble(json['fareHigh']),
    );
  }
}

/// A complete origin-to-destination journey.
@immutable
class Journey {
  const Journey({
    required this.objectives,
    required this.category,
    required this.origin,
    required this.destination,
    required this.totalFareTk,
    required this.totalDurationMinutes,
    required this.totalDistanceKm,
    required this.totalWalkKm,
    required this.transfers,
    required this.modeSummary,
    required this.fareCertainty,
    required this.fareCertaintyLabel,
    required this.legs,
    required this.fareDeltaTk,
    required this.durationDeltaMinutes,
    this.whyRecommended,
  });

  /// Which strategies produced this journey. More than one means the search
  /// found the same journey for both — the UI says so rather than showing a
  /// duplicate card.
  final List<String> objectives;

  /// The primary label: recommended | cheapest | fastest.
  final String category;

  final String origin;
  final String destination;
  final double totalFareTk;
  final int totalDurationMinutes;
  final double totalDistanceKm;
  final double totalWalkKm;
  final int transfers;

  /// "Rickshaw", "Metro", "Walk" — the at-a-glance sequence.
  final List<String> modeSummary;

  /// The provenance of the *weakest* fare in the journey.
  final String fareCertainty;
  final String fareCertaintyLabel;

  final List<JourneyLeg> legs;

  /// Difference against the recommended journey. Zero for the baseline.
  final double fareDeltaTk;
  final int durationDeltaMinutes;

  /// A sentence explaining why this is recommended, derived from real
  /// measured differences. Null when there is nothing meaningful to say.
  final String? whyRecommended;

  bool get isRecommended => objectives.contains('recommended');
  bool get isCheapest => objectives.contains('cheapest');
  bool get isFastest => objectives.contains('fastest');

  /// Whether any leg in this journey has fare data available.
  bool get hasFareData => legs.any((l) => l.fareAvailable);

  static Journey fromJson(Map<String, dynamic> json) {
    double asDouble(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    int asInt(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;

    return Journey(
      objectives: ((json['objectives'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      category: json['category']?.toString() ?? 'alternative',
      origin: json['origin']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      totalFareTk: asDouble(json['totalFareTk']),
      totalDurationMinutes: asInt(json['totalDurationMinutes']),
      totalDistanceKm: asDouble(json['totalDistanceKm']),
      totalWalkKm: asDouble(json['totalWalkKm']),
      transfers: asInt(json['transfers']),
      modeSummary: ((json['modeSummary'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      fareCertainty: json['fareCertainty']?.toString() ?? 'estimated',
      fareCertaintyLabel: json['fareCertaintyLabel']?.toString() ?? '',
      legs: ((json['legs'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (e) =>
                JourneyLeg.fromJson(e.map((k, v) => MapEntry(k.toString(), v))),
          )
          .toList(),
      fareDeltaTk: asDouble(json['fareDeltaTk']),
      durationDeltaMinutes: asInt(json['durationDeltaMinutes']),
      whyRecommended:
          (json['whyRecommended']?.toString().trim().isEmpty ?? true)
          ? null
          : json['whyRecommended'].toString(),
    );
  }
}

/// Why journey planning could not run, when it could not.
enum JourneyPlanningStatus {
  /// Journeys were planned (the list may still be empty — no route exists).
  available,

  /// The CommuteBD dataset is not loaded on the server.
  datasetUnavailable,

  /// One or both endpoints are too far from any known transport.
  outsideCoverage,

  /// The planner itself failed. Fare options may still be usable.
  plannerError,
}

/// The `journeyPlanning` envelope plus the journeys themselves.
@immutable
class JourneyPlan {
  const JourneyPlan({
    required this.status,
    required this.journeys,
    this.outsideCoverage = const [],
    this.coverageRadiusKm,
  });

  final JourneyPlanningStatus status;
  final List<Journey> journeys;

  /// Which endpoints were off-network: 'origin', 'destination', or both.
  final List<String> outsideCoverage;

  final double? coverageRadiusKm;

  bool get hasJourneys => journeys.isNotEmpty;

  /// Planning ran successfully but found nothing.
  bool get isNoRoute =>
      status == JourneyPlanningStatus.available && journeys.isEmpty;

  static JourneyPlan fromResponse(Map<String, dynamic> body) {
    final envelope =
        (body['journeyPlanning'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v),
        ) ??
        const <String, dynamic>{};

    final journeys = ((body['journeys'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (e) => Journey.fromJson(e.map((k, v) => MapEntry(k.toString(), v))),
        )
        .toList();

    final available = envelope['available'] == true;
    final reason = envelope['reason']?.toString();

    final status = available
        ? JourneyPlanningStatus.available
        : switch (reason) {
            'dataset_unavailable' => JourneyPlanningStatus.datasetUnavailable,
            'outside_network_coverage' => JourneyPlanningStatus.outsideCoverage,
            _ => JourneyPlanningStatus.plannerError,
          };

    return JourneyPlan(
      status: status,
      journeys: journeys,
      outsideCoverage: ((envelope['outsideCoverage'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      coverageRadiusKm: (envelope['coverageRadiusKm'] as num?)?.toDouble(),
    );
  }

  /// Build an estimated fallback plan from road route data when the public-
  /// transit planner is unavailable but a road route exists.
  ///
  /// Returns `null` when there is not enough road data to construct even a
  /// single honest estimated journey.
  ///
  /// [selectedMode] is the user-selected transport mode from the Choose
  /// transport chips (bus, cng, rickshaw, auto, metro). When provided, the
  /// fallback journey uses that mode; otherwise a neutral "road" label is used.
  ///
  /// [singleFareResult] is the canonical fare result from
  /// `POST /api/commute/single-fare`. When provided and `supported == true`,
  /// the fallback leg reuses that fare (fareLow, fareHigh, fareType, source)
  /// instead of discarding it.
  static JourneyPlan? roadFallback(
    Map<String, dynamic> body, {
    String? selectedMode,
    Map<String, dynamic>? singleFareResult,
  }) {
    final distanceKm = (body['distanceKm'] as num?)?.toDouble() ?? 0;
    final drivingMinutes = (body['estimatedDurationMin'] as num?)?.toInt() ?? 0;
    if (distanceKm <= 0 && drivingMinutes <= 0) return null;

    final originMap = body['origin'] as Map?;
    final destMap = body['destination'] as Map?;
    final originName = originMap?['name']?.toString() ?? '';
    final destName = destMap?['name']?.toString() ?? '';
    if (originName.isEmpty && destName.isEmpty) return null;

    final originLat = (originMap?['lat'] as num?)?.toDouble();
    final originLon = (originMap?['lon'] as num?)?.toDouble();
    final destLat = (destMap?['lat'] as num?)?.toDouble();
    final destLon = (destMap?['lon'] as num?)?.toDouble();

    final mode = selectedMode ?? 'road';
    final modeLabel = _modeLabel(mode);
    final isWalk = mode == 'walk' || mode == 'walking' || mode == 'foot';

    // Use raw OSRM road duration — no unjustified multiplier.
    // The UI labels this as "minimum road time" / "without traffic" so
    // the user understands it is not a real-world traffic-aware ETA.
    final durationMinutes = drivingMinutes;

    // Propagate fare from the canonical single-fare API when available.
    final fareSupported =
        singleFareResult != null &&
        (singleFareResult['supported'] as bool? ?? false);
    final fare = fareSupported
        ? (singleFareResult['fare'] as Map<String, dynamic>? ?? {})
        : <String, dynamic>{};

    final fareLow = (fare['fareLow'] as num?)?.toDouble() ?? 0;
    final fareHigh = (fare['fareHigh'] as num?)?.toDouble() ?? 0;
    final fareType = isWalk
        ? 'none'
        : (fare['fareType']?.toString() ?? 'estimated');
    final fareSource = isWalk ? '' : (fare['source']?.toString() ?? '');
    final hasFare = !isWalk && fareLow > 0 && fareHigh > 0;

    final leg = JourneyLeg(
      mode: mode,
      modeLabel: modeLabel,
      from: originName,
      to: destName,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      fareTk: hasFare ? fareLow : 0,
      fareType: fareType,
      fareLabel: hasFare ? 'Estimated' : (isWalk ? 'Free' : 'Estimated'),
      fareSource: fareSource,
      instruction: '',
      isTransfer: false,
      transferMinutes: 0,
      fareAvailable: isWalk || hasFare,
      fareLow: hasFare ? fareLow : 0,
      fareHigh: hasFare ? fareHigh : 0,
      fromLat: originLat,
      fromLon: originLon,
      toLat: destLat,
      toLon: destLon,
    );

    final journey = Journey(
      objectives: const ['estimated'],
      category: 'estimated',
      origin: originName,
      destination: destName,
      totalFareTk: hasFare ? fareLow : 0,
      totalDurationMinutes: durationMinutes,
      totalDistanceKm: distanceKm,
      totalWalkKm: 0,
      transfers: 0,
      modeSummary: [modeLabel],
      fareCertainty: isWalk ? 'none' : (fareType),
      fareCertaintyLabel: isWalk ? '' : 'Estimated',
      legs: [leg],
      fareDeltaTk: 0,
      durationDeltaMinutes: 0,
    );

    return JourneyPlan(
      status: JourneyPlanningStatus.available,
      journeys: [journey],
    );
  }

  static String _modeLabel(String mode) {
    return switch (mode) {
      'walk' || 'walking' || 'foot' => 'Walk',
      'bus' || 'brta' || 'minibus' => 'Bus',
      'metro' || 'mrt' || 'metrorail' => 'Metro',
      'rickshaw' => 'Rickshaw',
      'cng' || 'auto' || 'autorickshaw' || 'auto_rickshaw' => 'CNG',
      'car' || 'taxi' || 'ride' || 'rideshare' => 'Car',
      'train' || 'rail' => 'Train',
      'boat' || 'launch' || 'ferry' => 'Boat',
      _ => 'By road',
    };
  }
}

// ---------------------------------------------------------------------------
// Smart Journey Guide — structured verified facts
// ---------------------------------------------------------------------------

/// Lightweight value object that collects all verified journey facts needed
/// by the Smart Journey Guide. Built from existing authoritative objects;
/// never invents data.
@immutable
class JourneyGuideFacts {
  const JourneyGuideFacts({
    required this.originName,
    required this.destinationName,
    this.distanceKm,
    this.durationMinutes,
    this.durationProvenance = 'osrm',
    this.selectedMode,
    this.modeLabel,
    this.fareLow,
    this.fareHigh,
    this.fareType,
    this.fareSource,
    this.fareAvailable = true,
    this.verifiedWaypoints = const [],
    this.isMultimodal = false,
    this.transfers = 0,
    this.selectedBusOperator,
    this.selectedBusBoardStop,
    this.selectedBusExitStop,
    this.selectedBusStopCount,
  });

  final String originName;
  final String destinationName;
  final double? distanceKm;
  final int? durationMinutes;

  /// 'osrm' (without live traffic), 'multimodal' (real backend journey time),
  /// 'single_fare' (from fare API).
  final String durationProvenance;

  final String? selectedMode;
  final String? modeLabel;
  final double? fareLow;
  final double? fareHigh;
  final String? fareType;
  final String? fareSource;
  final bool fareAvailable;

  /// Only named waypoints confirmed by the backend or route data.
  final List<String> verifiedWaypoints;
  final bool isMultimodal;
  final int transfers;
  final String? selectedBusOperator;
  final String? selectedBusBoardStop;
  final String? selectedBusExitStop;
  final int? selectedBusStopCount;

  bool get hasDistance => distanceKm != null && distanceKm! > 0;
  bool get hasDuration => durationMinutes != null && durationMinutes! > 0;
  bool get hasFare => fareAvailable && fareLow != null && fareHigh != null;
  bool get isFree => !fareAvailable && selectedMode == 'walk';
  bool get hasWaypoints => verifiedWaypoints.isNotEmpty;

  /// Build from the currently selected journey (real multimodal data).
  factory JourneyGuideFacts.fromJourney(
    Journey journey, {
    required String? selectedMode,
    Map<String, dynamic>? singleFareResult,
    String? selectedBusOperator,
    String? selectedBusBoardStop,
    String? selectedBusExitStop,
    int? selectedBusStopCount,
  }) {
    final mode = selectedMode ?? journey.modeSummary.firstOrNull?.toLowerCase();
    final modeLabel = selectedMode != null ? _modeLabel(selectedMode) : null;

    // Collect verified waypoint names from non-first legs' from-fields
    // and the last leg's to-field, filtering duplicates.
    final waypoints = <String>[];
    for (final leg in journey.legs) {
      if (leg != journey.legs.first && leg.from.isNotEmpty) {
        if (!waypoints.contains(leg.from)) waypoints.add(leg.from);
      }
    }
    if (journey.legs.isNotEmpty) {
      final lastTo = journey.legs.last.to;
      if (lastTo.isNotEmpty && !waypoints.contains(lastTo)) {
        waypoints.add(lastTo);
      }
    }

    // Use single-fare result when available and supported.
    final fareSupported =
        singleFareResult != null &&
        (singleFareResult['supported'] as bool? ?? false);
    final fare = fareSupported
        ? (singleFareResult['fare'] as Map<String, dynamic>? ?? {})
        : <String, dynamic>{};

    final fareLow = (fare['fareLow'] as num?)?.toDouble();
    final fareHigh = (fare['fareHigh'] as num?)?.toDouble();
    final fareType = fare['fareType']?.toString();
    final fareSource = fare['source']?.toString();

    return JourneyGuideFacts(
      originName: journey.origin,
      destinationName: journey.destination,
      distanceKm: journey.totalDistanceKm > 0 ? journey.totalDistanceKm : null,
      durationMinutes: journey.totalDurationMinutes > 0
          ? journey.totalDurationMinutes
          : null,
      durationProvenance: 'multimodal',
      selectedMode: mode,
      modeLabel: modeLabel,
      fareLow: fareLow,
      fareHigh: fareHigh,
      fareType: fareType,
      fareSource: fareSource,
      fareAvailable: journey.hasFareData,
      verifiedWaypoints: waypoints,
      isMultimodal: journey.legs.length > 1,
      transfers: journey.transfers,
      selectedBusOperator: selectedBusOperator,
      selectedBusBoardStop: selectedBusBoardStop,
      selectedBusExitStop: selectedBusExitStop,
      selectedBusStopCount: selectedBusStopCount,
    );
  }

  /// Build from road-route data when no real multimodal journey exists.
  factory JourneyGuideFacts.fromRoadRoute({
    required Map<String, dynamic> result,
    String? selectedMode,
    Map<String, dynamic>? singleFareResult,
    String? selectedBusOperator,
    String? selectedBusBoardStop,
    String? selectedBusExitStop,
    int? selectedBusStopCount,
  }) {
    final originMap = result['origin'] as Map?;
    final destMap = result['destination'] as Map?;
    final originName = originMap?['name']?.toString() ?? '';
    final destName = destMap?['name']?.toString() ?? '';
    final distanceKm = (result['distanceKm'] as num?)?.toDouble();
    final drivingMinutes = (result['estimatedDurationMin'] as num?)?.toInt();

    final mode = selectedMode;
    final modeLabel = mode != null ? _modeLabel(mode) : null;

    final fareSupported =
        singleFareResult != null &&
        (singleFareResult['supported'] as bool? ?? false);
    final fare = fareSupported
        ? (singleFareResult['fare'] as Map<String, dynamic>? ?? {})
        : <String, dynamic>{};

    return JourneyGuideFacts(
      originName: originName,
      destinationName: destName,
      distanceKm: distanceKm,
      durationMinutes: drivingMinutes,
      durationProvenance: 'osrm',
      selectedMode: mode,
      modeLabel: modeLabel,
      fareLow: (fare['fareLow'] as num?)?.toDouble(),
      fareHigh: (fare['fareHigh'] as num?)?.toDouble(),
      fareType: fare['fareType']?.toString(),
      fareSource: fare['source']?.toString(),
      fareAvailable: fareSupported,
      selectedBusOperator: selectedBusOperator,
      selectedBusBoardStop: selectedBusBoardStop,
      selectedBusExitStop: selectedBusExitStop,
      selectedBusStopCount: selectedBusStopCount,
    );
  }

  static String _modeLabel(String mode) {
    return switch (mode) {
      'walk' || 'walking' || 'foot' => 'Walk',
      'bus' || 'brta' || 'minibus' => 'Bus',
      'metro' || 'mrt' || 'metrorail' => 'Metro',
      'rickshaw' => 'Rickshaw',
      'cng' || 'auto' || 'autorickshaw' || 'auto_rickshaw' => 'CNG',
      'car' || 'taxi' || 'ride' || 'rideshare' => 'Car',
      'train' || 'rail' => 'Train',
      'boat' || 'launch' || 'ferry' => 'Boat',
      _ => 'By road',
    };
  }

  /// Serialise to a JSON map suitable for the AI backend.
  Map<String, dynamic> toJson() {
    return {
      'origin': originName,
      'destination': destinationName,
      if (hasDistance) 'distance_km': distanceKm!.toStringAsFixed(1),
      if (hasDuration) 'duration_minutes': durationMinutes,
      'duration_provenance': durationProvenance,
      if (selectedMode != null) 'selected_mode': selectedMode,
      if (modeLabel != null) 'mode_label': modeLabel,
      'fare': {
        if (hasFare) ...{
          'low': fareLow!.toInt(),
          'high': fareHigh!.toInt(),
          'type': fareType ?? 'estimated',
          'source': fareSource ?? '',
        },
        'available': fareAvailable,
      },
      if (verifiedWaypoints.isNotEmpty) 'verified_waypoints': verifiedWaypoints,
      'is_multimodal': isMultimodal,
      'transfers': transfers,
      if (selectedBusOperator != null)
        'selected_bus_operator': selectedBusOperator,
      if (selectedBusBoardStop != null)
        'selected_bus_board_stop': selectedBusBoardStop,
      if (selectedBusExitStop != null)
        'selected_bus_exit_stop': selectedBusExitStop,
      if (selectedBusStopCount != null)
        'selected_bus_stop_count': selectedBusStopCount,
    };
  }
}

/// A verified direct bus service matching an origin-destination stop pair.
@immutable
class DirectBusCandidate {
  const DirectBusCandidate({
    required this.serviceId,
    required this.operatorName,
    this.operatorNameBn,
    this.serviceType = 'regular',
    required this.originStopName,
    required this.destinationStopName,
    required this.originSequence,
    required this.destinationSequence,
    this.verified = true,
    this.confidence = 'High',
    this.source = '',
    this.crowdFare,
  });

  final String serviceId;
  final String operatorName;
  final String? operatorNameBn;
  final String serviceType;
  final String originStopName;
  final String destinationStopName;
  final int originSequence;
  final int destinationSequence;
  final bool verified;
  final String confidence;
  final String source;
  final Map<String, dynamic>? crowdFare;

  /// Number of stops traveled between boarding and exit stops.
  int get stopCount => (destinationSequence - originSequence).abs();

  /// Whether there is a qualified crowd fare from real community reports.
  bool get hasQualifiedCrowdFare =>
      crowdFare != null &&
      (crowdFare!['hasQualifiedFare'] == true ||
          (crowdFare!['sampleCount'] is num &&
              (crowdFare!['sampleCount'] as num) >= 3));

  double? get crowdFareLow => (crowdFare?['fareLow'] as num?)?.toDouble();
  double? get crowdFareHigh => (crowdFare?['fareHigh'] as num?)?.toDouble();
  double? get crowdFareRecommended =>
      (crowdFare?['recommendedFare'] as num?)?.toDouble();
  int get crowdSampleCount =>
      (crowdFare?['sampleCount'] as num?)?.toInt() ?? 0;
  String? get crowdFareLabel => crowdFare?['label']?.toString();
  String? get crowdFareLabelBn => crowdFare?['labelBn']?.toString();

  static DirectBusCandidate fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;

    return DirectBusCandidate(
      serviceId: json['serviceId']?.toString() ?? '',
      operatorName: json['operatorName']?.toString() ?? '',
      operatorNameBn: json['operatorNameBn']?.toString(),
      serviceType: json['serviceType']?.toString() ?? 'regular',
      originStopName: json['originStopName']?.toString() ?? '',
      destinationStopName: json['destinationStopName']?.toString() ?? '',
      originSequence: asInt(json['originSequence']),
      destinationSequence: asInt(json['destinationSequence']),
      verified: json['verified'] != false,
      confidence: json['confidence']?.toString() ?? 'High',
      source: json['source']?.toString() ?? '',
      crowdFare: json['crowdFare'] as Map<String, dynamic>?,
    );
  }
}
