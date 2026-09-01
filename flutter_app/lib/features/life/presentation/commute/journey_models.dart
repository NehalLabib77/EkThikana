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

  bool get isFree => fareTk <= 0;

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
          .map((e) => JourneyLeg.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
          .toList(),
      fareDeltaTk: asDouble(json['fareDeltaTk']),
      durationDeltaMinutes: asInt(json['durationDeltaMinutes']),
      whyRecommended: (json['whyRecommended']?.toString().trim().isEmpty ?? true)
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
    final envelope = (body['journeyPlanning'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v)) ??
        const <String, dynamic>{};

    final journeys = ((body['journeys'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Journey.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
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
}
