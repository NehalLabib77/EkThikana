import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/financial_service.dart';

/// Lightweight recent-destinations store backed by [SharedPreferences].
/// Phase 2 UI/UX additive feature: keeps the last 6 destinations the user
/// has chosen so the home screen can show them as tap-to-fill chips.
class CommuteRecents {
  CommuteRecents._();

  static const _key = 'commute_recents_v1';
  static const _max = 6;

  static Future<List<RecentPlace>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(RecentPlace.fromJson)
          .where((p) => p.lat != 0 && p.lon != 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<RecentPlace>> add(RecentPlace place) async {
    final current = await load();
    final filtered = current
        .where((p) => !(p.lat == place.lat && p.lon == place.lon))
        .toList();
    final next = <RecentPlace>[place, ...filtered];
    if (next.length > _max) next.removeRange(_max, next.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(next.map((p) => p.toJson()).toList()),
    );
    return next;
  }
}

class RecentPlace {
  const RecentPlace({
    required this.name,
    required this.lat,
    required this.lon,
    required this.savedAt,
  });

  final String name;
  final double lat;
  final double lon;
  final DateTime savedAt;

  factory RecentPlace.fromJson(Map json) {
    return RecentPlace(
      name: json['name']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
      savedAt: DateTime.tryParse(json['savedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lon': lon,
        'savedAt': savedAt.toIso8601String(),
      };
}

/// Friendly mapping for the backend `source` string used by the fare
/// transparency block in the option details modal.
String _friendlySource(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'official':
    case 'official_rule_calculation':
    case 'official_rule':
      return EkLanguage.text(
        'BRTA official fare',
        'BRTA অনুমোদিত ভাড়া',
      );
    case 'crowdsourced':
    case 'crowd_reports':
      return EkLanguage.text(
        'Recent fare reports',
        'সাম্প্রতিক ভাড়ার রিপোর্�',
      );
    case 'estimated':
    case 'ml_estimate':
      return EkLanguage.text(
        'ML estimate from approved reports',
        'অনুমোদিত রিপোর্� থেকে ML অনুমান',
      );
    case 'historical':
    case 'meter_rule':
      return EkLanguage.text(
        'Legal meter rule',
        'বৈধ মিটার নিয়ম',
      );
    case 'unverified':
      return EkLanguage.text(
        'Reference only',
        'শুধুমাত্র রেফারেন্স',
      );
    case 'none':
    case '':
    case null:
      return EkLanguage.text('No fare', 'কোনো ভাড়া নে�');
    default:
      return raw ?? EkLanguage.text('Reference', 'রেফারেন্স');
  }
}

/// Friendly mapping for the backend `confidence` string used by the fare
/// transparency block. Values come verbatim from the backend, so we only
/// normalize casing/formatting for display.
String _friendlyConfidence(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'high':
    case 'authoritative':
      return EkLanguage.text('Authoritative', 'নির্ভরযোগ্য');
    case 'medium':
    case 'moderate':
      return EkLanguage.text('Moderate', 'মাঝারি');
    case 'low':
    case 'unverified':
      return EkLanguage.text('Low', 'কম');
    case '':
    case null:
      return EkLanguage.text('Unknown', 'অজানা');
    default:
      return raw ?? EkLanguage.text('Unknown', 'অজানা');
  }
}

/// Friendly mapping for the backend `fareType` string used by the option card
/// subtitle. This is purely a display transform — backend strings are not
/// rewritten for any downstream logic.
String _friendlyFareType(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'official':
      return EkLanguage.text('Official fare', 'অনুমোদিত ভাড়া');
    case 'crowdsourced':
      return EkLanguage.text('Crowdsourced', 'জনসম্পৃক্ত');
    case 'estimated':
      return EkLanguage.text('Estimated', 'আনুমানিক');
    case 'historical':
      return EkLanguage.text('Historical', 'ঐতিহাসিক');
    case 'unverified':
      return EkLanguage.text('Unverified', 'যাচাই নয়');
    case '':
    case null:
      return EkLanguage.text('Estimated', 'আনুমানিক');
    default:
      return raw ?? EkLanguage.text('Estimated', 'আনুমানিক');
  }
}

class CommuteBDScreen extends StatefulWidget {
  const CommuteBDScreen({super.key});

  @override
  State<CommuteBDScreen> createState() => _CommuteBDScreenState();
}

class _CommuteBDScreenState extends State<CommuteBDScreen> {
  final MapController mapController = MapController();

  LatLng? origin;
  LatLng? destination;
  String originName = 'Current location';
  String destinationName = '';
  bool locating = false;
  bool routing = false;
  bool _inFlightRoute = false;
  String? locationError;
  String? routeError;
  Map<String, dynamic>? route;
  List<LatLng> polyline = const [];
  List<RecentPlace> _recents = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_locate());
    unawaited(_loadRecents());
  }

  Future<void> _loadRecents() async {
    final loaded = await CommuteRecents.load();
    if (!mounted) return;
    setState(() => _recents = loaded);
  }

  Future<void> _rememberDestination({
    required String name,
    required double lat,
    required double lon,
  }) async {
    final next = await CommuteRecents.add(
      RecentPlace(
        name: name,
        lat: lat,
        lon: lon,
        savedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _recents = next);
  }

  Future<void> _locate() async {
    setState(() {
      locating = true;
      locationError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(
          EkLanguage.text(
            'Location services are turned off.',
            'লোকেশন সার্ভিস বন্ধ আছে।',
          ),
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          EkLanguage.text(
            'Location permission denied. You can enable it from Android settings.',
            'লোকেশন অনুমতি দেওয়া হয়নি। Android সেটিংস থেকে চালু করুন।',
          ),
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() {
        origin = point;
        originName = EkLanguage.text('Current location', 'বর্তমান লোকেশন');
      });
      mapController.move(point, 14);
    } catch (e) {
      if (mounted) setState(() => locationError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _searchDestination({RecentPlace? initial}) async {
    final selected = await showModalBottomSheet<_PlaceResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PlaceSearchSheet(initial: initial),
    );
    if (selected == null) return;

    setState(() {
      destination = LatLng(selected.lat, selected.lon);
      destinationName = selected.name;
      route = null;
      routeError = null;
      polyline = const [];
    });
    mapController.move(destination!, 13);
    await _rememberDestination(
      name: selected.name,
      lat: selected.lat,
      lon: selected.lon,
    );

    if (origin != null) {
      await _buildRoute();
    }
  }

  void _applyRecent(RecentPlace place) {
    setState(() {
      destination = LatLng(place.lat, place.lon);
      destinationName = place.name;
      route = null;
      routeError = null;
      polyline = const [];
    });
    mapController.move(destination!, 13);
    if (origin != null) {
      unawaited(_buildRoute());
    }
  }

  Future<void> _buildRoute() async {
    if (origin == null || destination == null) return;
    if (_inFlightRoute) return; // Phase 2 perf: dedupe duplicate route calls
    _inFlightRoute = true;
    setState(() {
      routing = true;
      routeError = null;
    });
    try {
      final result = await ApiService.commuteRoute(
        originName: originName,
        originLat: origin!.latitude,
        originLon: origin!.longitude,
        destinationName: destinationName,
        destinationLat: destination!.latitude,
        destinationLon: destination!.longitude,
      );

      final points = <LatLng>[];
      for (final raw in (result['polyline'] as List?) ?? const []) {
        if (raw is Map) {
          final lat = (raw['lat'] as num?)?.toDouble();
          final lon = (raw['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) points.add(LatLng(lat, lon));
        }
      }

      if (!mounted) return;
      setState(() {
        route = result;
        polyline = points;
      });
      if (points.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(points);
        mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(40),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => routeError = e.toString());
      }
    } finally {
      _inFlightRoute = false;
      if (mounted) setState(() => routing = false);
    }
  }

  Future<void> _fareDetails(Map<String, dynamic> option) async {
    final low = (option['fareLow'] as num?)?.toDouble() ?? 0;
    final high = (option['fareHigh'] as num?)?.toDouble() ?? low;
    final same = (low - high).abs() < .01;
    final actual = TextEditingController(
      text: same ? low.toStringAsFixed(0) : '',
    );
    var alsoReport = false;

    final record = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('${option['label'] ?? option['mode']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  same
                      ? '৳${low.toStringAsFixed(0)}'
                      : '৳${low.toStringAsFixed(0)}–${high.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                _detailLine(
                  EkLanguage.text('Fare type', 'ভাড়ার ধরন'),
                  _friendlyFareType(option['fareType']?.toString()),
                ),
                const SizedBox(height: 14),
                // Phase 2 — Fare transparency header.
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: .85),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Fare transparency / ভাড়ার স্বচ্ছতা',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: .85),
                        ),
                      ),
                    ],
                  ),
                ),
                _detailLine(
                  EkLanguage.text('Source', 'উৎস'),
                  _friendlySource(option['source']?.toString()),
                ),
                _detailLine(
                  EkLanguage.text('Confidence', 'নির্ভরযোগ্যতা'),
                  _friendlyConfidence(option['confidence']?.toString()),
                ),
                if ((option['warning']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF1D27A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Color(0xFFB36B00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            option['warning'].toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7A4A00),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 24),
                Text(
                  EkLanguage.text(
                    'Estimated fare is not an expense. Enter what you actually paid.',
                    'আনুমানিক ভাড়া খরচ হিসেবে যোগ হবে না। বাস্তবে কত দিয়েছেন তা লিখুন।',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: actual,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: EkLanguage.text('Actual Fare Paid (৳)', 'বাস্তব ভাড়া (৳)'),
                  ),
                ),
                _SurveyModerationTile(
                  value: alsoReport,
                  onChanged: (v) => setLocal(() => alsoReport = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(EkLanguage.text('Close', 'বন্ধ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(EkLanguage.text('Record Actual Fare', 'বাস্তব ভাড়া সংরক্ষণ')),
            ),
          ],
        ),
      ),
    );


    if (record == true) {
      try {
        final fare = double.tryParse(actual.text.trim()) ?? 0;
        if (fare <= 0) throw Exception('Actual fare must be greater than zero.');

        await FinancialService.recordCommuteTrip(
          origin: originName,
          destination: destinationName,
          mode: option['mode']?.toString() ?? 'other',
          distanceKm: (route?['distanceKm'] as num?)?.toDouble() ?? 0,
          estimatedMinutes: (route?['durationMinutes'] as num?)?.toInt() ?? 0,
          actualFare: fare,
          date: DateTime.now(),
          fareSource: option['source']?.toString() ?? '',
          fareConfidence: option['confidence']?.toString() ?? '',
        );

        if (alsoReport) {
          try {
            await ApiService.reportCommuteFare(
              originText: originName,
              destinationText: destinationName,
              mode: option['mode']?.toString() ?? 'other',
              farePaid: fare,
              originLat: origin?.latitude,
              originLon: origin?.longitude,
              destinationLat: destination?.latitude,
              destinationLon: destination?.longitude,
              tripMinutes: (route?['durationMinutes'] as num?)?.toInt(),
              routeDistanceKm: (route?['distanceKm'] as num?)?.toDouble(),
              routeId: option['routeId']?.toString(),
              locationVerified: origin != null,
            );
          } catch (e) {
            if (mounted) {
              showError(
                context,
                Exception(
                  'Trip expense was saved, but the optional crowd fare report could not be submitted: $e',
                ),
              );
            }
          }
        }

        if (mounted) {
          showSuccess(
            context,
            EkLanguage.text(
              'Actual commute fare saved to Expense Tracker.',
              'বাস্তব যাতায়াত ভাড়া Expense Tracker-এ যোগ হয়েছে।',
            ),
          );
        }
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    actual.dispose();
  }

  Widget _detailLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label, style: const TextStyle(color: EkColors.muted)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final defaultCenter = origin ?? const LatLng(23.8103, 90.4125);
    final options = ((route?['transportOptions'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                  children: [
                    TextSpan(text: 'Commute', style: TextStyle(color: Color(0xFF102044))),
                    TextSpan(text: 'BD', style: TextStyle(color: Color(0xFF109238))),
                  ],
                ),
              ),
              Text(
                EkLanguage.text('Smart Travel Guide', 'স্মার্ট ট্রাভেল গাইড'),
                style: const TextStyle(fontSize: 11, color: EkColors.muted),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: EkLanguage.text('Recenter', 'বর্তমান লোকেশন'),
              onPressed: origin == null ? _locate : () => mapController.move(origin!, 14),
              icon: locating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: LanguageToggle(),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
          children: [
            if (locationError != null)
              _warning(locationError!, const Color(0xFFFFF1E6)),
            _HomeHeaderCard(
              originName: originName,
              destinationName: destinationName,
              locating: locating,
              origin: origin,
              destination: destination,
              onLocate: _locate,
              onPickDestination: _searchDestination,
            ),
            const SizedBox(height: 12),
            if (_recents.isNotEmpty)
              _RecentDestinationsStrip(
                recents: _recents,
                onTap: _applyRecent,
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: defaultCenter,
                        initialZoom: 12.5,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.ekthikana.ekthikana',
                        ),
                        if (polyline.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: polyline,
                                strokeWidth: 5,
                                color: const Color(0xFF1976D2),
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            if (origin != null)
                              Marker(
                                point: origin!,
                                width: 48,
                                height: 48,
                                child: const Icon(
                                  Icons.my_location,
                                  size: 34,
                                  color: Color(0xFF1976D2),
                                ),
                              ),
                            if (destination != null)
                              Marker(
                                point: destination!,
                                width: 52,
                                height: 52,
                                child: const Icon(
                                  Icons.location_on,
                                  size: 44,
                                  color: Color(0xFFE5483D),
                                ),
                              ),
                          ],
                        ),
                      ],
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        color: Colors.white.withValues(alpha: .84),
                        child: const Text(
                          '© OpenStreetMap contributors',
                          style: TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    if (routing)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x66FFFFFF),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (routeError != null) ...[
              const SizedBox(height: 10),
              _warning(routeError!, const Color(0xFFFFECEC)),
            ],
            if (route != null) ...[
              const SizedBox(height: 12),
              _routeStats(),
              const SizedBox(height: 14),
              Text(
                EkLanguage.text('Transport Options', 'যাতায়াতের বিকল্প'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (options.isEmpty)
                _warning(
                  EkLanguage.text(
                    'No trustworthy fare option is available for this trip yet. The map route still works.',
                    'এই ট্রিপের জন্য এখনো নির্ভরযোগ্য ভাড়ার তথ্য নেই। ম্যাপ রুট ব্যবহার করা যাবে।',
                  ),
                  const Color(0xFFFFF8E5),
                )
              else
                for (final option in options) _optionCard(option),
              const SizedBox(height: 8),
              Text(
                route?['disclaimer']?.toString() ?? '',
                style: const TextStyle(fontSize: 10, color: EkColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _warning(String text, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  Widget _routeStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: _stat(
                Icons.route,
                '${route?['distanceKm'] ?? '-'} km',
                EkLanguage.text('Distance', 'দূরত্ব'),
                const Color(0xFF1F6DD8),
              ),
            ),
            Container(width: 1, height: 54, color: EkColors.line),
            Expanded(
              child: _stat(
                Icons.schedule,
                '${route?['durationMinutes'] ?? '-'} min',
                EkLanguage.text('Estimated time', 'আনুমানিক সময়'),
                const Color(0xFF168A32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .10),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(fontSize: 11, color: EkColors.muted)),
            ],
          ),
        ],
      );

  Widget _optionCard(Map<String, dynamic> option) {
    final low = (option['fareLow'] as num?)?.toDouble() ?? 0;
    final high = (option['fareHigh'] as num?)?.toDouble() ?? low;
    final fare = (low - high).abs() < .01
        ? '৳${low.toStringAsFixed(0)}'
        : '৳${low.toStringAsFixed(0)}–${high.toStringAsFixed(0)}';
    final mode = option['mode']?.toString() ?? '';
    final emoji = {
          'bus': '🚌',
          'metro': '🚇',
          'cng': '🛺',
          'rickshaw': '🛺',
          'walk': '🚶',
          'bike': '🏍️',
          'car': '🚗',
        }[mode] ??
        '🧭';
    final badges = ((option['badges'] as List?) ?? const []).map((e) => e.toString()).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: () => _fareDetails(option),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _modeColor(mode).withValues(alpha: .10),
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 31)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badges.isNotEmpty)
                      Wrap(
                        spacing: 5,
                        children: [
                          for (final badge in badges)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _badgeColor(badge).withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: _badgeColor(badge),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      option['label']?.toString() ?? mode,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${option['confidence'] ?? 'Low'} • ${option['fareType'] ?? 'estimated'}',
                      style: const TextStyle(fontSize: 10, color: EkColors.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${option['minutes'] ?? '-'} min',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    fare,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: _modeColor(mode),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: EkColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'bus':
        return const Color(0xFFE38B14);
      case 'metro':
        return const Color(0xFF168A32);
      case 'cng':
        return const Color(0xFF1B72CC);
      case 'rickshaw':
        return const Color(0xFF7B50C7);
      default:
        return const Color(0xFF1B72CC);
    }
  }

  Color _badgeColor(String badge) {
    if (badge == 'Cheapest') return const Color(0xFFE28300);
    if (badge == 'Fastest') return const Color(0xFF1B72CC);
    return const Color(0xFF168A32);
  }
}

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({this.initial});
  final RecentPlace? initial;

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  late final controller = TextEditingController(text: widget.initial?.name ?? '');
  Timer? debounce;
  bool busy = false;
  String? error;
  List<_PlaceResult> results = const [];

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void changed(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 450), () => search(value));
  }

  Future<void> search(String query) async {
    if (query.trim().length < 2) {
      setState(() => results = const []);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await ApiService.commuteSearch(query.trim());
      final next = <_PlaceResult>[];
      for (final item in (response['geocoded'] as List?) ?? const []) {
        if (item is! Map) continue;
        final lat = (item['lat'] as num?)?.toDouble();
        final lon = (item['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        next.add(
          _PlaceResult(
            item['displayName']?.toString() ?? query.trim(),
            lat,
            lon,
          ),
        );
      }
      if (mounted) setState(() => results = next);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .72,
        child: Column(
          children: [
            Text(
              EkLanguage.text('Search Destination', 'গন্তব্য খুঁজুন'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              onChanged: changed,
              onSubmitted: search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: EkLanguage.text(
                  'Search a place in Bangladesh…',
                  'বাংলাদেশের জায়গা খুঁজুন…',
                ),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        EkLanguage.text(
                          'Type a destination. Search uses the configured geocoding provider.',
                          'গন্তব্য লিখুন। কনফিগার করা জিওকোডিং প্রোভাইডার ব্যবহার হবে।',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: EkColors.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final place = results[i];
                        return ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            place.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, place),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceResult {
  const _PlaceResult(this.name, this.lat, this.lon);
  final String name;
  final double lat;
  final double lon;
}


class _SurveyModerationTile extends StatelessWidget {
  const _SurveyModerationTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  EkLanguage.text(
                    'Also send the fare report for moderation',
                    'মডারেশনের জন্য ভাড়ার রিপোর্টও পাঠান',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  EkLanguage.text(
                    'It remains pending until approved.',
                    'অনুমোদনের আগে এটি প্রকাশিত হবে না।',
                  ),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}


class _HomeHeaderCard extends StatelessWidget {
  const _HomeHeaderCard({
    required this.originName,
    required this.destinationName,
    required this.locating,
    required this.origin,
    required this.destination,
    required this.onLocate,
    required this.onPickDestination,
  });

  final String originName;
  final String destinationName;
  final bool locating;
  final LatLng? origin;
  final LatLng? destination;
  final VoidCallback onLocate;
  final VoidCallback onPickDestination;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.my_location, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      EkLanguage.text('From', 'থেকে'),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    Text(
                      origin == null
                          ? EkLanguage.text('Set current location', 'বর্তমান লোকেশন নিন')
                          : originName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: EkLanguage.text('Recenter', 'বর্তমান লোকেশন'),
                onPressed: locating ? null : onLocate,
                icon: locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPickDestination,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.place_outlined, color: cs.tertiary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          EkLanguage.text('To', 'পর্যন্ত'),
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                        Text(
                          destinationName.isEmpty
                              ? EkLanguage.text('Choose destination', 'গন্তব্য নির্বাচন করুন')
                              : destinationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: destinationName.isEmpty ? cs.onSurfaceVariant : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentDestinationsStrip extends StatelessWidget {
  const _RecentDestinationsStrip({required this.recents, required this.onTap});

  final List<RecentPlace> recents;
  final ValueChanged<RecentPlace> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            EkLanguage.text('Recent destinations', 'সাম্প্রতিক গন্তব্য'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final r = recents[i];
              return ActionChip(
                avatar: const Icon(Icons.history, size: 16),
                label: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => onTap(r),
              );
            },
          ),
        ),
      ],
    );
  }
}
