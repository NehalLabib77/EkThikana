// Pick a trip straight off the map.
//
// Typing a place name is fine when you know what it is called. Often you do
// not — you know roughly where you are going. This puts the map where the
// empty state used to be so a trip can be chosen by looking at it.
//
// Two ways to choose, and the difference matters:
//
//   * **Tap a labelled pin.** These are CommuteBD places, so the choice
//     carries a `placeId` — which is what unlocks official BRTA and metro
//     fares for the trip.
//   * **Tap anywhere else.** That drops a plain point. It routes perfectly
//     well, but with no place id there is no official fare table to look up,
//     so fares fall back to distance-based estimates. The sheet says so
//     rather than letting the two look identical.
//
// Only places CommuteBD actually has coordinates for are drawn. The shipped
// dataset marks every place `geocode_status: pending`, so those coordinates
// are derived from the OpenStreetMap master and cover 154 of them. The rest
// are still findable by name through the search picker; they simply cannot be
// drawn, and the caption says that instead of implying the map is complete.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import 'commute_place_picker.dart';

/// Which end of the trip a tapped point should fill.
enum CommuteEndpoint { origin, destination }

class CommuteMapPicker extends StatefulWidget {
  const CommuteMapPicker({
    super.key,
    required this.origin,
    required this.destination,
    required this.onPicked,
    this.height = 380,
  });

  final CommutePlace? origin;
  final CommutePlace? destination;

  /// Called with the chosen place and which end it should fill.
  final void Function(CommutePlace place, CommuteEndpoint end) onPicked;

  final double height;

  @override
  State<CommuteMapPicker> createState() => _CommuteMapPickerState();
}

class _CommuteMapPickerState extends State<CommuteMapPicker> {
  /// Central Dhaka. Only the opening view; the map is fitted to the chosen
  /// places as soon as there are any.
  static const _dhaka = LatLng(23.7806, 90.4074);

  final MapController _map = MapController();

  List<_MapPlace> _places = const [];
  bool _loading = true;
  String _error = '';

  /// Where the student last tapped, before they say which end it is.
  LatLng? _pending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final body = await ApiService.commuteMapPlaces();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _places = ((body['places'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => _MapPlace.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
            .whereType<_MapPlace>()
            .toList();
        // An empty list is not an error: it means the derived coordinate
        // asset is missing on the server. The caption below explains that a
        // place can still be chosen by name.
        _error = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // The map still works for dropping a point, so this is a note rather
        // than a failure state.
        _error = friendlyErrorMessage(error);
      });
    }
  }

  LatLng? _pointFor(CommutePlace? place) {
    final lat = place?.lat;
    final lon = place?.lon;
    return (lat == null || lon == null) ? null : LatLng(lat, lon);
  }

  Future<void> _askWhichEnd(CommutePlace place) async {
    final end = await showModalBottomSheet<CommuteEndpoint>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.md,
            0,
            GochanoSpacing.md,
            GochanoSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(place.name, style: sheetContext.type.sectionHeading),
              if (!place.isDatasetPlace) ...[
                const SizedBox(height: GochanoSpacing.xxs),
                Text(
                  GochanoLanguage.text(
                    'A point on the map, not a CommuteBD stop. Routing works, '
                    'but fares will be distance estimates rather than official '
                    'bus or metro fares.',
                    'মানচিত্রের একটি বিন্দু, কমিউটবিডির কোনো স্টপ নয়। রুট বের '
                    'হবে, তবে ভাড়া সরকারি বাস/মেট্রো ভাড়া নয় — দূরত্বভিত্তিক '
                    'আনুমানিক হবে।',
                  ),
                  style: sheetContext.type.caption,
                ),
              ],
              const SizedBox(height: GochanoSpacing.md),
              PrimaryButton(
                label: GochanoLanguage.text('Start from here', 'এখান থেকে শুরু'),
                icon: Icons.trip_origin_rounded,
                onPressed: () =>
                    Navigator.of(sheetContext).pop(CommuteEndpoint.origin),
              ),
              const SizedBox(height: GochanoSpacing.xs),
              SecondaryButton(
                label: GochanoLanguage.text('Go here', 'এখানে যাব'),
                icon: Icons.place_rounded,
                onPressed: () =>
                    Navigator.of(sheetContext).pop(CommuteEndpoint.destination),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _pending = null);
    if (end != null) widget.onPicked(place, end);
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() => _pending = point);
    _askWhichEnd(
      CommutePlace(
        // Named by coordinate, honestly. Reverse-geocoding every tap would
        // hammer the public geocoder that already rate-limits this feature.
        name: GochanoLanguage.text(
          'Point at ${point.latitude.toStringAsFixed(4)}, '
          '${point.longitude.toStringAsFixed(4)}',
          '${point.latitude.toStringAsFixed(4)}, '
          '${point.longitude.toStringAsFixed(4)} বিন্দু',
        ),
        lat: point.latitude,
        lon: point.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final origin = _pointFor(widget.origin);
    final destination = _pointFor(widget.destination);
    final chosen = <LatLng>[?origin, ?destination];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: GochanoRadius.lgAll,
          child: SizedBox(
            height: widget.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: GochanoRadius.lgAll,
              ),
              child: RepaintBoundary(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: chosen.isEmpty ? _dhaka : chosen.first,
                        initialZoom: chosen.isEmpty ? 11.5 : 12.5,
                        initialCameraFit: chosen.length < 2
                            ? null
                            : CameraFit.coordinates(
                                coordinates: chosen,
                                padding:
                                    const EdgeInsets.all(GochanoSpacing.xl),
                              ),
                        onTap: _onMapTap,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom |
                              InteractiveFlag.drag |
                              InteractiveFlag.doubleTapZoom,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.ekthikana.ekthikana',
                          retinaMode: false,
                        ),
                        MarkerLayer(
                          markers: [
                            for (final place in _places)
                              Marker(
                                point: place.point,
                                width: 34,
                                height: 34,
                                child: _StopPin(
                                  onTap: () => _askWhichEnd(place.asPlace()),
                                ),
                              ),
                            if (_pending != null)
                              Marker(
                                point: _pending!,
                                width: 34,
                                height: 34,
                                child: _EndPin(
                                  icon: Icons.add_location_alt_rounded,
                                  color: colors.textSecondary,
                                ),
                              ),
                            if (origin != null)
                              Marker(
                                point: origin,
                                width: 38,
                                height: 38,
                                child: _EndPin(
                                  icon: Icons.trip_origin_rounded,
                                  color: colors.commute,
                                ),
                              ),
                            if (destination != null)
                              Marker(
                                point: destination,
                                width: 38,
                                height: 38,
                                child: _EndPin(
                                  icon: Icons.place_rounded,
                                  color: colors.error,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (_loading)
                      Positioned(
                        top: GochanoSpacing.xs,
                        right: GochanoSpacing.xs,
                        child: _Pill(
                          label: GochanoLanguage.text(
                            'Loading stops…',
                            'স্টপ লোড হচ্ছে…',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: GochanoSpacing.xxs),
        Text(_caption(), style: context.type.caption),
      ],
    );
  }

  String _caption() {
    if (_loading) {
      return GochanoLanguage.text(
        'Tap the map to choose where you are going.',
        'কোথায় যাবেন তা বেছে নিতে মানচিত্রে চাপ দিন।',
      );
    }
    if (_error.isNotEmpty) {
      return GochanoLanguage.text(
        'Stops could not be loaded, but you can still tap anywhere on the map '
        'to pick a point. ($_error)',
        'স্টপ লোড করা যায়নি, তবে মানচিত্রের যেকোনো জায়গায় চাপ দিয়ে বিন্দু '
        'বেছে নিতে পারেন। ($_error)',
      );
    }
    if (_places.isEmpty) {
      return GochanoLanguage.text(
        'No stops can be drawn yet. Tap anywhere to pick a point, or use the '
        'From and To fields to search by name.',
        'এখনো কোনো স্টপ আঁকা যাচ্ছে না। বিন্দু বাছতে যেকোনো জায়গায় চাপ দিন, '
        'অথবা নাম দিয়ে খুঁজতে "থেকে"/"পর্যন্ত" ব্যবহার করুন।',
      );
    }
    return GochanoLanguage.text(
      'Tap a stop for official fares, or anywhere else to drop a point. '
      '${_places.length} stops have map locations; the rest are searchable by '
      'name.',
      'সরকারি ভাড়ার জন্য কোনো স্টপে চাপ দিন, নয়তো অন্য যেকোনো জায়গায় চাপ '
      'দিয়ে বিন্দু বসান। ${_places.length}টি স্টপের মানচিত্র অবস্থান আছে; '
      'বাকিগুলো নাম দিয়ে খোঁজা যায়।',
    );
  }
}

/// A CommuteBD place that has a map location.
class _MapPlace {
  const _MapPlace({
    required this.placeId,
    required this.name,
    required this.point,
  });

  final String placeId;
  final String name;
  final LatLng point;

  CommutePlace asPlace() => CommutePlace(
        name: name,
        placeId: placeId,
        lat: point.latitude,
        lon: point.longitude,
        isDatasetPlace: true,
      );

  static _MapPlace? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final id = json['placeId']?.toString().trim() ?? '';
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    // A pin with no name is an internal id on a map, and a pin with no id
    // cannot buy official fares. Neither is worth drawing.
    if (name.isEmpty || id.isEmpty || lat == null || lon == null) return null;
    return _MapPlace(placeId: id, name: name, point: LatLng(lat, lon));
  }
}

/// A tappable CommuteBD stop. Small on purpose — there can be a hundred of
/// them on screen and they must not bury the map.
class _StopPin extends StatelessWidget {
  const _StopPin({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: GochanoLanguage.text('Transport stop', 'যানবাহন স্টপ'),
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Center(
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface,
              border: Border.all(color: colors.commute, width: 3),
            ),
          ),
        ),
      ),
    );
  }
}

class _EndPin extends StatelessWidget {
  const _EndPin({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Center(child: Icon(icon, size: 19, color: color)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.smAll,
        border: Border.all(color: colors.border),
      ),
      child: Text(label, style: context.type.caption),
    );
  }
}
