// Pick a trip straight off the map (spec §60).
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

import 'dart:async';

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

/// Opens the map picker in a bottom sheet. Returns the chosen place, or null if dismissed.
Future<CommutePlace?> showCommuteMapPicker(
  BuildContext context, {
  CommutePlace? initialOrigin,
  CommutePlace? initialDestination,
  String? title,
}) {
  return showModalBottomSheet<CommutePlace>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ModalMapPickerSheet(
      initialOrigin: initialOrigin,
      initialDestination: initialDestination,
      title: title,
    ),
  );
}

class CommuteMapPicker extends StatefulWidget {
  const CommuteMapPicker({
    super.key,
    required this.origin,
    required this.destination,
    required this.onPicked,
    this.height = 380,
    this.showHeader = true,
    this.onClose,
    this.placesLoader,
  });

  final CommutePlace? origin;
  final CommutePlace? destination;

  /// Called with the chosen place and which end it should fill.
  final void Function(CommutePlace place, CommuteEndpoint end) onPicked;

  final double height;
  final bool showHeader;
  final VoidCallback? onClose;

  /// Optional loader for testing without live network calls.
  final Future<Map<String, dynamic>> Function()? placesLoader;

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
      final loader = widget.placesLoader ?? ApiService.commuteMapPlaces;
      final body = await loader();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _places = ((body['places'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (e) => _MapPlace.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
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

  void _resetCamera() {
    final origin = _pointFor(widget.origin);
    final destination = _pointFor(widget.destination);
    final chosen = <LatLng>[?origin, ?destination];
    if (chosen.length >= 2) {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: chosen,
          padding: const EdgeInsets.all(GochanoSpacing.xl),
        ),
      );
    } else {
      final center = chosen.isEmpty ? _dhaka : chosen.first;
      _map.move(center, chosen.isEmpty ? 11.5 : 12.5);
    }
  }

  Future<void> _askWhichEnd(CommutePlace place) async {
    final end = await showModalBottomSheet<CommuteEndpoint>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _SelectedPlaceSheet(place: place),
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

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GochanoSpacing.md,
                GochanoSpacing.sm,
                GochanoSpacing.sm,
                GochanoSpacing.xs,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.commute.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.map_rounded,
                      size: 18,
                      color: colors.commute,
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          GochanoLanguage.text('Select on Map', 'ম্যাপে স্থান নির্বাচন'),
                          style: context.type.sectionHeading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          GochanoLanguage.text(
                            'Tap a stop or anywhere to set route point',
                            'রুট পয়েন্ট নির্ধারণ করতে স্টপ বা স্থানে চাপ দিন',
                          ),
                          style: context.type.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_pending != null)
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      tooltip: GochanoLanguage.text(
                        'Clear pin',
                        'পিন বাতিল করুন',
                      ),
                      onPressed: () => setState(() => _pending = null),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.my_location_rounded,
                      size: 20,
                      color: colors.commute,
                    ),
                    tooltip: GochanoLanguage.text(
                      'Center map',
                      'ম্যাপের কেন্দ্র',
                    ),
                    onPressed: _resetCamera,
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      tooltip: GochanoLanguage.text(
                        'Close',
                        'বন্ধ করুন',
                      ),
                      onPressed: widget.onClose,
                    ),
                ],
              ),
            ),
          ],
          ClipRRect(
            borderRadius: widget.showHeader
                ? BorderRadius.zero
                : GochanoRadius.lgAll,
            child: SizedBox(
              height: widget.height,
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
                                padding: const EdgeInsets.all(
                                  GochanoSpacing.xl,
                                ),
                              ),
                        onTap: _onMapTap,
                        interactionOptions: const InteractionOptions(
                          flags:
                              InteractiveFlag.pinchZoom |
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
                                width: 38,
                                height: 38,
                                child: _EndPin(
                                  icon: Icons.add_location_alt_rounded,
                                  color: colors.warning,
                                ),
                              ),
                            if (origin != null)
                              Marker(
                                point: origin,
                                width: 40,
                                height: 40,
                                child: _EndPin(
                                  icon: Icons.trip_origin_rounded,
                                  color: colors.commute,
                                ),
                              ),
                            if (destination != null)
                              Marker(
                                point: destination,
                                width: 40,
                                height: 40,
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
                        left: GochanoSpacing.xs,
                        child: _LoadingPill(
                          label: GochanoLanguage.text(
                            'Loading stops…',
                            'স্টপ লোড হচ্ছে…',
                          ),
                        ),
                      ),
                    Positioned(
                      top: GochanoSpacing.xs,
                      right: GochanoSpacing.xs,
                      child: _MapZoomControls(
                        onZoomIn: () {
                          final center = _map.camera.center;
                          final zoom = _map.camera.zoom;
                          _map.move(center, (zoom + 1).clamp(3.0, 18.0));
                        },
                        onZoomOut: () {
                          final center = _map.camera.center;
                          final zoom = _map.camera.zoom;
                          _map.move(center, (zoom - 1).clamp(3.0, 18.0));
                        },
                      ),
                    ),
                    Positioned(
                      left: GochanoSpacing.xs,
                      bottom: GochanoSpacing.xs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          '© OpenStreetMap contributors',
                          style: context.type.caption.copyWith(
                            fontSize: 10,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(GochanoSpacing.sm),
            child: _captionWidget(context),
          ),
        ],
      ),
    );
  }

  Widget _captionWidget(BuildContext context) {
    final colors = context.colors;

    if (_loading) {
      return Text(
        GochanoLanguage.text(
          'Tap the map to choose where you are going.',
          'কোথায় যাবেন তা বেছে নিতে মানচিত্রে চাপ দিন।',
        ),
        style: context.type.caption,
      );
    }

    if (_error.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(GochanoSpacing.xs),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: GochanoRadius.smAll,
          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: colors.error),
            const SizedBox(width: GochanoSpacing.xxs),
            Expanded(
              child: Text(
                GochanoLanguage.text(
                  'Stops could not be loaded, but you can still tap anywhere on the map to pick a point. ($_error)',
                  'স্টপ লোড করা যায়নি, তবে মানচিত্রের যেকোনো জায়গায় চাপ দিয়ে বিন্দু বেছে নিতে পারেন। ($_error)',
                ),
                style: context.type.caption.copyWith(color: colors.error),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = '';
                });
                _load();
              },
              borderRadius: GochanoRadius.smAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GochanoSpacing.xxs,
                  vertical: 2,
                ),
                child: Text(
                  GochanoLanguage.text('Retry', 'পুনরায় চেষ্টা'),
                  style: context.type.caption.copyWith(
                    color: colors.commute,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_places.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(GochanoSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: GochanoRadius.smAll,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: colors.textSecondary,
            ),
            const SizedBox(width: GochanoSpacing.xxs),
            Expanded(
              child: Text(
                GochanoLanguage.text(
                  'No stops can be drawn yet. Tap anywhere to pick a point, or use the From and To fields to search by name.',
                  'এখনো কোনো স্টপ আঁকা যাচ্ছে না। বিন্দু বাছতে যেকোনো জায়গায় চাপ দিন, অথবা নাম দিয়ে খুঁজতে "থেকে"/"পর্যন্ত" ব্যবহার করুন।',
                ),
                style: context.type.caption,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: GochanoRadius.smAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 16,
            color: colors.commute,
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          Expanded(
            child: Text(
              GochanoLanguage.text(
                'Tap a stop for official fares, or anywhere else to drop a point. ${_places.length} stops have map locations; the rest are searchable by name.',
                'সরকারি ভাড়ার জন্য কোনো স্টপে চাপ দিন, নয়তো অন্য যেকোনো জায়গায় চাপ দিয়ে বিন্দু বসান। ${_places.length}টি স্টপের মানচিত্র অবস্থান আছে; বাকিগুলো নাম দিয়ে খোঁজা যায়।',
              ),
              style: context.type.caption,
            ),
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          GochanoBadge(
            label: '${_places.length}',
            tone: GochanoBadgeTone.brand,
          ),
        ],
      ),
    );
  }
}

class _SelectedPlaceSheet extends StatelessWidget {
  const _SelectedPlaceSheet({required this.place});

  final CommutePlace place;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDataset = place.isDatasetPlace;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.xs,
          GochanoSpacing.md,
          GochanoSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDataset
                        ? colors.commute.withValues(alpha: 0.12)
                        : colors.info.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDataset
                        ? Icons.directions_bus_rounded
                        : Icons.location_on_rounded,
                    color: isDataset ? colors.commute : colors.info,
                    size: 20,
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: context.type.sectionHeading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (place.lat != null && place.lon != null)
                        Text(
                          '${place.lat!.toStringAsFixed(4)}, ${place.lon!.toStringAsFixed(4)}',
                          style: context.type.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                GochanoBadge(
                  label: isDataset
                      ? GochanoLanguage.text('Official stop', 'অফিশিয়াল স্টপ')
                      : GochanoLanguage.text('Map point', 'ম্যাপ বিন্দু'),
                  tone: isDataset
                      ? GochanoBadgeTone.brand
                      : GochanoBadgeTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.xs),
            if (!isDataset) ...[
              Container(
                padding: const EdgeInsets.all(GochanoSpacing.xs),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: GochanoRadius.smAll,
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: GochanoSpacing.xxs),
                    Expanded(
                      child: Text(
                        GochanoLanguage.text(
                          'A point on the map, not a CommuteBD stop. Routing works, '
                              'but fares will be distance estimates rather than official '
                              'bus or metro fares.',
                          'মানচিত্রের একটি বিন্দু, কমিউটবিডির কোনো স্টপ নয়। রুট বের '
                              'হবে, তবে ভাড়া সরকারি বাস/মেট্রো ভাড়া নয় — দূরত্বভিত্তিক '
                              'আনুমানিক হবে।',
                        ),
                        style: context.type.caption,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),
            ] else ...[
              Text(
                GochanoLanguage.text(
                  'Official bus and metro fares are available for this stop.',
                  'এই স্টপের জন্য সরকারি বাস ও মেট্রো ভাড়া প্রযোজ্য।',
                ),
                style: context.type.caption,
              ),
              const SizedBox(height: GochanoSpacing.sm),
            ],
            PrimaryButton(
              label: GochanoLanguage.text(
                'Start from here',
                'এখান থেকে শুরু',
              ),
              icon: Icons.trip_origin_rounded,
              onPressed: () =>
                  Navigator.of(context).pop(CommuteEndpoint.origin),
            ),
            const SizedBox(height: GochanoSpacing.xs),
            SecondaryButton(
              label: GochanoLanguage.text('Go here', 'এখানে যাব'),
              icon: Icons.place_rounded,
              onPressed: () =>
                  Navigator.of(context).pop(CommuteEndpoint.destination),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalMapPickerSheet extends StatefulWidget {
  const _ModalMapPickerSheet({
    this.initialOrigin,
    this.initialDestination,
    this.title,
  });

  final CommutePlace? initialOrigin;
  final CommutePlace? initialDestination;
  final String? title;

  @override
  State<_ModalMapPickerSheet> createState() => _ModalMapPickerSheetState();
}

class _ModalMapPickerSheetState extends State<_ModalMapPickerSheet> {
  late final CommutePlace? _origin = widget.initialOrigin;
  late final CommutePlace? _destination = widget.initialDestination;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: GochanoSpacing.xs),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(GochanoSpacing.md),
                  child: CommuteMapPicker(
                    origin: _origin,
                    destination: _destination,
                    height: 450,
                    onClose: () => Navigator.of(context).pop(),
                    onPicked: (place, end) {
                      Navigator.of(context).pop(place);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        radius: 18,
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface,
              border: Border.all(color: colors.commute, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
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
        border: Border.all(color: color, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: Icon(icon, size: 20, color: color)),
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.smAll,
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: GochanoLanguage.text('Zoom in', 'জুম ইন'),
            child: InkWell(
              onTap: onZoomIn,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.add_rounded, size: 20),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          Semantics(
            button: true,
            label: GochanoLanguage.text('Zoom out', 'জুম আউট'),
            child: InkWell(
              onTap: onZoomOut,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.remove_rounded, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill({required this.label});

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.commute),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xxs),
          Text(label, style: context.type.caption),
        ],
      ),
    );
  }
}
