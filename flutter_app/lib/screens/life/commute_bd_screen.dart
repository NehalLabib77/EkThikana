import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/financial_service.dart';

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
  String? locationError;
  String? routeError;
  Map<String, dynamic>? route;
  List<LatLng> polyline = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_locate());
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

  Future<void> _searchDestination() async {
    final selected = await showModalBottomSheet<_PlaceResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _PlaceSearchSheet(),
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

    if (origin != null) {
      await _buildRoute();
    }
  }

  Future<void> _buildRoute() async {
    if (origin == null || destination == null) return;
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
                  option['fareType']?.toString() ?? 'unknown',
                ),
                _detailLine(
                  EkLanguage.text('Source', 'উৎস'),
                  option['source']?.toString() ?? 'Unavailable',
                ),
                _detailLine(
                  EkLanguage.text('Confidence', 'নির্ভরযোগ্যতা'),
                  option['confidence']?.toString() ?? 'Low',
                ),
                if ((option['warning']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    option['warning'].toString(),
                    style: const TextStyle(fontSize: 11, color: Color(0xFFB36B00)),
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
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alsoReport,
                  onChanged: (v) => setLocal(() => alsoReport = v == true),
                  title: Text(
                    EkLanguage.text(
                      'Also submit fare report for moderation',
                      'মডারেশনের জন্য ভাড়ার রিপোর্টও পাঠান',
                    ),
                  ),
                  subtitle: Text(
                    EkLanguage.text(
                      'It remains pending until approved.',
                      'অনুমোদনের আগে এটি প্রকাশিত হবে না।',
                    ),
                  ),
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
              child: Text(EkLanguage.text('Record Actual Fare', 'বাস্তব ভাড়া সংরক্ষণ')),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _locate,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      origin == null
                          ? EkLanguage.text('Set current location', 'বর্তমান লোকেশন নিন')
                          : originName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, color: EkColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _searchDestination,
                    icon: const Icon(Icons.place_outlined),
                    label: Text(
                      destinationName.isEmpty
                          ? EkLanguage.text('Destination', 'গন্তব্য')
                          : destinationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    FlutterMap(
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
  const _PlaceSearchSheet();

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final controller = TextEditingController();
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
