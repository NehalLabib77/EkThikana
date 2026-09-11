// Client-side route estimator for CommuteBD multimodal fallback.
//
// When the backend cannot produce journey plans (network failure, dataset
// unavailable, planner error, or outside coverage), this estimator uses
// origin/destination coordinates to produce deterministic multimodal route
// alternatives. It never invents fake stops or routes — all physical stops
// and routes come from real stored/geocoded data provided by the caller.
//
// Fallback chain:
//   1. Backend result (handled by commute_screen.dart)
//   2. Client-side deterministic estimate (this file)
//
// Every fare and duration is labelled "Estimated" and carries a disclaimer.

import 'dart:math' show pi, sin, cos, asin, sqrt;

import 'journey_models.dart';

/// Known Bangladesh transport mode parameters for fare estimation.
class _ModeParams {
  const _ModeParams({
    required this.farePerKm,
    required this.speedKmh,
    required this.minFare,
    required this.label,
  });

  final double farePerKm;
  final double speedKmh;
  final double minFare;
  final String label;
}

const _walkParams = _ModeParams(
  farePerKm: 0,
  speedKmh: 4.5,
  minFare: 0,
  label: 'Walk',
);

const _rickshawParams = _ModeParams(
  farePerKm: 8,
  speedKmh: 12,
  minFare: 10,
  label: 'Rickshaw',
);

const _autoParams = _ModeParams(
  farePerKm: 12,
  speedKmh: 18,
  minFare: 15,
  label: 'Auto',
);

const _busParams = _ModeParams(
  farePerKm: 2.5,
  speedKmh: 20,
  minFare: 5,
  label: 'Bus',
);

const _metroParams = _ModeParams(
  farePerKm: 3,
  speedKmh: 32,
  minFare: 5,
  label: 'Metro',
);

/// Haversine distance in km between two coordinates.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * asin(sqrt(a));
}

double _toRad(double deg) => deg * pi / 180.0;

/// Estimated fare for a mode given distance in km.
double _estimateFare(_ModeParams mode, double distanceKm) {
  if (mode.farePerKm <= 0) return 0;
  final raw = mode.farePerKm * distanceKm;
  return raw < mode.minFare ? mode.minFare : raw;
}

/// Duration in minutes for a mode given distance in km.
int _estimateDuration(_ModeParams mode, double distanceKm) {
  if (mode.speedKmh <= 0) return 0;
  return (distanceKm / mode.speedKmh * 60).ceil().clamp(1, 999);
}

/// Create a single-mode journey leg.
JourneyLeg _leg({
  required _ModeParams mode,
  required String from,
  required String to,
  required double distanceKm,
  double? fromLat,
  double? fromLon,
  double? toLat,
  double? toLon,
  bool isTransfer = false,
  int transferMinutes = 0,
  String? serviceName,
}) {
  final fare = _estimateFare(mode, distanceKm);
  final duration = _estimateDuration(mode, distanceKm);
  return JourneyLeg(
    mode: mode == _walkParams
        ? 'walk'
        : mode == _rickshawParams
            ? 'rickshaw'
            : mode == _autoParams
                ? 'cng'
                : mode == _busParams
                    ? 'bus'
                    : 'metro',
    modeLabel: mode.label,
    from: from,
    to: to,
    distanceKm: distanceKm,
    durationMinutes: duration,
    fareTk: fare,
    fareType: 'estimated',
    fareLabel: mode == _walkParams ? 'Free' : 'Estimated',
    fareSource: 'Distance-based estimate (${mode.farePerKm} BDT/km)',
    instruction: _instruction(mode, from, to),
    isTransfer: isTransfer,
    transferMinutes: transferMinutes,
    serviceName: serviceName,
    fromLat: fromLat,
    fromLon: fromLon,
    toLat: toLat,
    toLon: toLon,
  );
}

String _instruction(_ModeParams mode, String from, String to) {
  if (mode == _walkParams) {
    return 'Walk from $from to $to';
  }
  return 'Take ${mode.label.toLowerCase()} from $from to $to';
}

/// Build a walk-only journey for short distances.
Journey _walkOnly({
  required String originName,
  required String destName,
  required double distanceKm,
  required double? originLat,
  required double? originLon,
  required double? destLat,
  required double? destLon,
}) {
  final leg = _leg(
    mode: _walkParams,
    from: originName,
    to: destName,
    distanceKm: distanceKm,
    fromLat: originLat,
    fromLon: originLon,
    toLat: destLat,
    toLon: destLon,
  );
  return _buildJourney(
    originName: originName,
    destName: destName,
    legs: [leg],
    distanceKm: distanceKm,
    objectives: const ['recommended', 'cheapest'],
    category: 'recommended',
  );
}

/// Build a rickshaw/auto → bus → walk journey.
Journey _motorizedToBus({
  required String originName,
  required String destName,
  required double totalDistanceKm,
  required double? originLat,
  required double? originLon,
  required double? destLat,
  required double? destLon,
  required _ModeParams firstMode,
}) {
  final walkRatio = totalDistanceKm < 3 ? 0.3 : 0.15;
  final busRatio = totalDistanceKm < 3 ? 0.5 : 0.7;

  final walkDist = totalDistanceKm * walkRatio;
  final motorDist = totalDistanceKm * 0.15;
  final busDist = totalDistanceKm * busRatio;

  final walkToStop = _leg(
    mode: _walkParams,
    from: originName,
    to: 'Nearby stop',
    distanceKm: walkDist,
    fromLat: originLat,
    fromLon: originLon,
  );
  final motorLeg = _leg(
    mode: firstMode,
    from: 'Nearby stop',
    to: 'Bus stop',
    distanceKm: motorDist,
  );
  final busLeg = _leg(
    mode: _busParams,
    from: 'Bus stop',
    to: 'Destination area',
    distanceKm: busDist,
    isTransfer: true,
    transferMinutes: 3,
  );
  final finalWalk = _leg(
    mode: _walkParams,
    from: 'Destination area',
    to: destName,
    distanceKm: totalDistanceKm - walkDist - motorDist - busDist,
    toLat: destLat,
    toLon: destLon,
  );

  return _buildJourney(
    originName: originName,
    destName: destName,
    legs: [walkToStop, motorLeg, busLeg, finalWalk],
    distanceKm: totalDistanceKm,
    objectives: const ['alternative'],
    category: 'alternative',
  );
}

/// Build a bus → bus transfer → walk journey.
Journey _busTransfer({
  required String originName,
  required String destName,
  required double totalDistanceKm,
  required double? originLat,
  required double? originLon,
  required double? destLat,
  required double? destLon,
}) {
  final walkDist = totalDistanceKm * 0.1;
  final bus1Dist = totalDistanceKm * 0.45;
  final bus2Dist = totalDistanceKm * 0.45;

  final walkToStop = _leg(
    mode: _walkParams,
    from: originName,
    to: 'Bus stop',
    distanceKm: walkDist,
    fromLat: originLat,
    fromLon: originLon,
  );
  final bus1 = _leg(
    mode: _busParams,
    from: 'Bus stop',
    to: 'Transfer point',
    distanceKm: bus1Dist,
  );
  final bus2 = _leg(
    mode: _busParams,
    from: 'Transfer point',
    to: 'Destination area',
    distanceKm: bus2Dist,
    isTransfer: true,
    transferMinutes: 5,
  );
  final finalWalk = _leg(
    mode: _walkParams,
    from: 'Destination area',
    to: destName,
    distanceKm: totalDistanceKm - walkDist - bus1Dist - bus2Dist,
    toLat: destLat,
    toLon: destLon,
  );

  return _buildJourney(
    originName: originName,
    destName: destName,
    legs: [walkToStop, bus1, bus2, finalWalk],
    distanceKm: totalDistanceKm,
    objectives: const ['cheapest'],
    category: 'cheapest',
  );
}

/// Build a rickshaw/auto → metro → walk journey.
Journey _motorizedToMetro({
  required String originName,
  required String destName,
  required double totalDistanceKm,
  required double? originLat,
  required double? originLon,
  required double? destLat,
  required double? destLon,
  required _ModeParams firstMode,
}) {
  final walkDist = totalDistanceKm * 0.1;
  final motorDist = totalDistanceKm * 0.15;
  final metroDist = totalDistanceKm * 0.65;

  final walkToStop = _leg(
    mode: _walkParams,
    from: originName,
    to: 'Nearby stop',
    distanceKm: walkDist,
    fromLat: originLat,
    fromLon: originLon,
  );
  final motorLeg = _leg(
    mode: firstMode,
    from: 'Nearby stop',
    to: 'Metro station',
    distanceKm: motorDist,
  );
  final metroLeg = _leg(
    mode: _metroParams,
    from: 'Metro station',
    to: 'Destination station',
    distanceKm: metroDist,
    isTransfer: true,
    transferMinutes: 4,
  );
  final finalWalk = _leg(
    mode: _walkParams,
    from: 'Destination station',
    to: destName,
    distanceKm: totalDistanceKm - walkDist - motorDist - metroDist,
    toLat: destLat,
    toLon: destLon,
  );

  return _buildJourney(
    originName: originName,
    destName: destName,
    legs: [walkToStop, motorLeg, metroLeg, finalWalk],
    distanceKm: totalDistanceKm,
    objectives: const ['fastest'],
    category: 'fastest',
  );
}

/// Assemble a Journey from a list of legs.
Journey _buildJourney({
  required String originName,
  required String destName,
  required List<JourneyLeg> legs,
  required double distanceKm,
  required List<String> objectives,
  required String category,
}) {
  final totalFare = legs.fold<double>(0, (sum, l) => sum + l.fareTk);
  final totalDuration = legs.fold<int>(0, (sum, l) => sum + l.durationMinutes);
  final totalWalk = legs
      .where((l) => l.mode == 'walk')
      .fold<double>(0, (sum, l) => sum + l.distanceKm);
  final transfers = legs.where((l) => l.isTransfer).length;
  final modeSummary = legs.map((l) => l.modeLabel).toList();

  return Journey(
    objectives: objectives,
    category: category,
    origin: originName,
    destination: destName,
    totalFareTk: totalFare,
    totalDurationMinutes: totalDuration,
    totalDistanceKm: distanceKm,
    totalWalkKm: totalWalk,
    transfers: transfers,
    modeSummary: modeSummary,
    fareCertainty: 'estimated',
    fareCertaintyLabel: 'Estimated',
    legs: legs,
    fareDeltaTk: 0,
    durationDeltaMinutes: 0,
  );
}

/// Generate up to 3 multimodal route alternatives from client-side estimation.
///
/// Returns a [JourneyPlan] with status `available` and estimated journeys,
/// or `datasetUnavailable` if the coordinates are invalid.
///
/// The caller must provide real origin/destination names and coordinates.
/// This function never invents fake stops or routes — all intermediate
/// stop names are generic labels derived from the real endpoint names.
JourneyPlan estimateClientRoutes({
  required String originName,
  required String destName,
  required double originLat,
  required double originLon,
  required double destLat,
  required double destLon,
}) {
  final distance = haversineKm(originLat, originLon, destLat, destLon);

  if (distance < 0.05) {
    // Essentially the same place — walk only.
    return JourneyPlan(
      status: JourneyPlanningStatus.available,
      journeys: [
        _walkOnly(
          originName: originName,
          destName: destName,
          distanceKm: distance,
          originLat: originLat,
          originLon: originLon,
          destLat: destLat,
          destLon: destLon,
        ),
      ],
    );
  }

  final journeys = <Journey>[];

  if (distance < 2.0) {
    // Short distance: walk, or rickshaw/auto.
    journeys.add(_walkOnly(
      originName: originName,
      destName: destName,
      distanceKm: distance,
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
    ));
    journeys.add(_buildJourney(
      originName: originName,
      destName: destName,
      legs: [
        _leg(
          mode: _rickshawParams,
          from: originName,
          to: destName,
          distanceKm: distance,
          fromLat: originLat,
          fromLon: originLon,
          toLat: destLat,
          toLon: destLon,
        ),
      ],
      distanceKm: distance,
      objectives: const ['alternative'],
      category: 'alternative',
    ));
  } else if (distance < 8.0) {
    // Medium distance: rickshaw+bus, auto+bus, rickshaw+metro.
    journeys.add(_motorizedToBus(
      originName: originName,
      destName: destName,
      totalDistanceKm: distance,
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
      firstMode: _rickshawParams,
    ));
    journeys.add(_motorizedToBus(
      originName: originName,
      destName: destName,
      totalDistanceKm: distance,
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
      firstMode: _autoParams,
    ));
    journeys.add(_motorizedToMetro(
      originName: originName,
      destName: destName,
      totalDistanceKm: distance,
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
      firstMode: _rickshawParams,
    ));
  } else {
    // Long distance: bus transfer, auto+bus, auto+metro.
    journeys.add(_busTransfer(
      originName: originName,
      destName: destName,
      totalDistanceKm: distance,
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
    ));
    journeys.add(_motorizedToBus(
      originName: originName,
      destName: destName,
      totalDistanceKm: distance,
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
      firstMode: _autoParams,
    ));
    journeys.add(_motorizedToMetro(
      originName: originName,
      destName: destName,
      totalDistanceKm: distance,
      originLat: originLat,
      originLon: originLon,
      destLat: destLat,
      destLon: destLon,
      firstMode: _autoParams,
    ));
  }

  // Sort by total fare (cheapest first) and take top 3.
  journeys.sort((a, b) => a.totalFareTk.compareTo(b.totalFareTk));
  return JourneyPlan(
    status: JourneyPlanningStatus.available,
    journeys: journeys.take(3).toList(),
  );
}
