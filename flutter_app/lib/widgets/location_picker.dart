import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/language.dart';

/// Result returned by [LocationPickerScreen] when the user confirms.
class PickedLocation {
  const PickedLocation({
    required this.name,
    required this.point,
  });

  /// Freeform name the user typed (or a derived label like "Pinned: 23.75, 90.39"
  /// if the user didn't override it).
  final String name;

  /// The picked coordinates.
  final LatLng point;
}

/// Full-screen map picker. The user can:
///   1. Pan the map and tap anywhere to drop a pin (the pin is always
///      centered under the user's tap, then snapped to the centre of
///      the visible map).
///   2. Type a custom label for the pin (defaults to a coordinates
///      label so the user can never accidentally submit an empty name).
///   3. Confirm or cancel.
///
/// The picker does NOT call reverse-geocoding on its own — keeping it
/// route-free so it works fully offline against the public OSM tile
/// server and doesn't introduce new backend endpoints. The caller is
/// expected to either use the typed name as-is or pipe it through the
/// existing commute search to refine it.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.title,
    this.initial,
    this.initialName,
    this.allowGps = true,
  });

  /// Header text shown in the AppBar (already localised by caller).
  final String? title;

  /// Optional starting point shown on the map. When null we centre on
  /// Dhaka, Bangladesh — the default for CommuteBD.
  final LatLng? initial;

  /// Optional starting name shown in the label field.
  final String? initialName;

  /// When true (default) a "Use my GPS" floating action appears so the
  /// user can jump to their current location without typing.
  final bool allowGps;

  static const _defaultCenter = LatLng(23.8103, 90.4125);
  static const _defaultZoom = 13.0;

  /// Shows the picker as a full-screen route and returns the user's
  /// picked location, or null if the user cancels.
  static Future<PickedLocation?> show(
    BuildContext context, {
    String? title,
    LatLng? initial,
    String? initialName,
    bool allowGps = true,
  }) {
    return Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(
          title: title,
          initial: initial,
          initialName: initialName,
          allowGps: allowGps,
        ),
      ),
    );
  }

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapController _mapController = MapController();
  late LatLng _center =
      widget.initial ?? LocationPickerScreen._defaultCenter;
  late double _zoom = widget.initial == null
      ? LocationPickerScreen._defaultZoom
      : 15.0;
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onMapReady() {
    // No-op: we keep initial centre / zoom from the constructor. Hook
    // reserved so callers don't depend on internal MapController state.
  }

  /// Recenter the map on the user's current GPS location. The reverse
  /// step here is intentionally minimal — we do not call reverse-geocode
  /// (the backend has no such route and we promised no new routes).
  Future<void> _useGps() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
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
            'Location permission denied.',
            'লোকেশন অনুমতি দেওয়া হয়নি।',
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
        _center = point;
        _zoom = 15.5;
      });
      _mapController.move(point, _zoom);
      // Default the label to a coordinates string so the user can
      // either keep it or type something more meaningful.
      if (_nameController.text.trim().isEmpty) {
        _nameController.text =
            'Pinned ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onTapMap(LatLng tapped) {
    setState(() {
      _center = tapped;
    });
    // Mirror what the user sees: the pin sits at the centre, so after
    // a tap we move the camera so the pin is centred too. This avoids
    // the confusing "I tapped here but the pin is over there" issue.
    _mapController.move(tapped, _zoom);
    if (_nameController.text.trim().isEmpty) {
      _nameController.text =
          'Pinned ${tapped.latitude.toStringAsFixed(4)}, ${tapped.longitude.toStringAsFixed(4)}';
    }
  }

  void _confirm() {
    final typed = _nameController.text.trim();
    final label = typed.isEmpty
        ? 'Pinned ${_center.latitude.toStringAsFixed(4)}, ${_center.longitude.toStringAsFixed(4)}'
        : typed;
    Navigator.of(context).pop(
      PickedLocation(name: label, point: _center),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ??
        EkLanguage.text('Pick a location', '�কটি লোকেশন নির্বাচন করুন');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: EkLanguage.text('Cancel', 'বাতিল'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check_circle, color: Color(0xFF2EAD46)),
              label: Text(
                EkLanguage.text('Confirm', 'নিশ্চিত করুন'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2EAD46),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: _zoom,
                    onTap: (_, point) => _onTapMap(point),
                    onMapReady: _onMapReady,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ekthikana.ekthikana',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _center,
                          width: 56,
                          height: 56,
                          child: const Icon(
                            Icons.location_on,
                            size: 48,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    color: Colors.white.withValues(alpha: .84),
                    child: const Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                if (_busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66FFFFFF),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDEDEE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF3C7CA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFD84A4A),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: EkLanguage.text(
                        'Label for this place',
                        '�ই জায়গার নাম',
                      ),
                      hintText: EkLanguage.text(
                        'e.g. Home, Office, Farmgate',
                        'যেমন: বাসা, অফিস, ফার্মগেট',
                      ),
                      prefixIcon: const Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (widget.allowGps)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _useGps,
                            icon: const Icon(Icons.my_location, size: 18),
                            label: Text(
                              EkLanguage.text(
                                'Use my GPS',
                                'আমার GPS ব্যবহার করুন',
                              ),
                            ),
                          ),
                        ),
                      if (widget.allowGps) const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _confirm,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            EkLanguage.text(
                              'Use this point',
                              'এই পয়েন্টটি ব্যবহার করুন',
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2EAD46),
                          ),
                        ),
                      ),
                    ],
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


