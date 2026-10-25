// The route drawn on an OpenStreetMap tile layer (spec §62).
//
// The line is **static**. Spec §62 is explicit — "Do NOT animate the route
// line" — so there is no progressive draw, no camera fly-to and no pulsing
// marker. The map is fitted to the route once, when the route arrives, and
// then it simply sits there and can be panned.
//
// Wrapped in a RepaintBoundary because tile layers repaint independently of
// the surrounding list; without it, scrolling the results re-rasterises the
// whole map (spec §83).

import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';

class CommuteRouteMap extends StatefulWidget {
  const CommuteRouteMap({
    super.key,
    required this.polyline,
    required this.origin,
    required this.destination,
    this.transfers = const [],
    this.height = 240,
  });

  /// Route geometry from the backend, as `{lat, lon}` maps.
  final List<Map<String, dynamic>> polyline;

  final LatLng? origin;
  final LatLng? destination;

  /// Optional transfer points between legs
  final List<LatLng> transfers;
  final double height;

  @override
  State<CommuteRouteMap> createState() => _CommuteRouteMapState();
}

class _CommuteRouteMapState extends State<CommuteRouteMap> {
  /// Dhaka, used only when there is nothing to fit to.
  static const _fallbackCentre = LatLng(23.8103, 90.4125);

  final MapController _mapController = MapController();

  List<LatLng> get _points {
    final pts = <LatLng>[];
    for (final p in widget.polyline) {
      final lat = (p['lat'] as num?)?.toDouble();
      final lon = (p['lon'] as num?)?.toDouble();
      if (lat != null &&
          lon != null &&
          !lat.isNaN &&
          !lon.isNaN &&
          lat >= -90.0 &&
          lat <= 90.0 &&
          lon >= -180.0 &&
          lon <= 180.0) {
        pts.add(LatLng(lat, lon));
      }
    }
    return pts;
  }

  List<LatLng> get _fitTargets {
    final points = _points;
    if (points.isNotEmpty) return points;
    return <LatLng>[
      if (widget.origin != null) widget.origin!,
      if (widget.destination != null) widget.destination!,
      ...widget.transfers,
    ];
  }

  void _fitRoute() {
    final targets = _fitTargets;
    if (targets.length >= 2) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: targets,
          padding: const EdgeInsets.all(GochanoSpacing.xl),
        ),
      );
    } else if (targets.isNotEmpty) {
      _mapController.move(targets.first, 13.0);
    } else {
      _mapController.move(_fallbackCentre, 12.0);
    }
  }

  @override
  void didUpdateWidget(CommuteRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.polyline, widget.polyline) ||
        oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination ||
        !listEquals(oldWidget.transfers, widget.transfers)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitRoute();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final points = _points;

    if (points.isEmpty) {
      if (kDebugMode) {
        dev.log(
          'CommuteRouteMap: empty polyline (${widget.polyline.length} raw entries)',
          name: 'CommuteBD',
        );
      }
    }

    final fitTargets = _fitTargets;

    return ClipRRect(
      borderRadius: GochanoRadius.lgAll,
      child: SizedBox(
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: GochanoRadius.lgAll,
          ),
          child: RepaintBoundary(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: fitTargets.isEmpty
                        ? _fallbackCentre
                        : fitTargets.first,
                    initialZoom: 12.5,
                    initialCameraFit: fitTargets.length < 2
                        ? null
                        : CameraFit.coordinates(
                            coordinates: fitTargets,
                            padding: const EdgeInsets.all(GochanoSpacing.xl),
                          ),
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
                    if (points.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: points,
                            strokeWidth: 5,
                            color: colors.commute,
                            borderStrokeWidth: 2.0,
                            borderColor: colors.surface,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (widget.origin != null)
                          Marker(
                            point: widget.origin!,
                            width: 38,
                            height: 38,
                            child: _RoutePin(
                              icon: Icons.trip_origin_rounded,
                              color: colors.commute,
                              label: GochanoLanguage.text('Origin', 'শুরু'),
                            ),
                          ),
                        for (final transfer in widget.transfers)
                          Marker(
                            point: transfer,
                            width: 30,
                            height: 30,
                            child: _TransferPin(
                              color: colors.borderStrong,
                            ),
                          ),
                        if (widget.destination != null)
                          Marker(
                            point: widget.destination!,
                            width: 38,
                            height: 38,
                            child: _RoutePin(
                              icon: Icons.place_rounded,
                              color: colors.error,
                              label: GochanoLanguage.text(
                                'Destination',
                                'গন্তব্য',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Floating map controls (zoom & fit route)
                Positioned(
                  top: GochanoSpacing.xs,
                  right: GochanoSpacing.xs,
                  child: _RouteMapControls(
                    onZoomIn: () {
                      final zoom = _mapController.camera.zoom;
                      _mapController.move(
                        _mapController.camera.center,
                        (zoom + 1).clamp(3.0, 18.0),
                      );
                    },
                    onZoomOut: () {
                      final zoom = _mapController.camera.zoom;
                      _mapController.move(
                        _mapController.camera.center,
                        (zoom - 1).clamp(3.0, 18.0),
                      );
                    },
                    onFitRoute: _fitRoute,
                  ),
                ),
                // Route Information Tag (Top-Left)
                if (points.isNotEmpty)
                  Positioned(
                    top: GochanoSpacing.xs,
                    left: GochanoSpacing.xs,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.xs,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.92),
                        borderRadius: GochanoRadius.smAll,
                        border: Border.all(color: colors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.route_rounded,
                            size: 14,
                            color: colors.commute,
                          ),
                          const SizedBox(width: GochanoSpacing.xxs),
                          Text(
                            GochanoLanguage.text('Route map', 'রুট ম্যাপ'),
                            style: context.type.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (widget.transfers.isNotEmpty) ...[
                            const SizedBox(width: GochanoSpacing.xxs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colors.brandSoft,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${widget.transfers.length} ${GochanoLanguage.text('transfers', 'বদল')}',
                                style: context.type.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: colors.brand,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else if (fitTargets.isEmpty)
                  Positioned(
                    top: GochanoSpacing.xs,
                    left: GochanoSpacing.xs,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.xs,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.92),
                        borderRadius: GochanoRadius.smAll,
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        GochanoLanguage.text(
                          'No route coordinates',
                          'রুটের স্থানাঙ্ক নেই',
                        ),
                        style: context.type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                // OpenStreetMap Attribution (Bottom-Left)
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
    );
  }
}

/// A map pin with a light halo so it stays visible over any tile colour.
class _RoutePin extends StatelessWidget {
  const _RoutePin({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
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
        child: Center(
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

/// A transfer point indicator on the route.
class _TransferPin extends StatelessWidget {
  const _TransferPin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: GochanoLanguage.text('Transfer point', 'ট্রান্সফার পয়েন্ট'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.transfer_within_a_station_rounded,
            size: 15,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Floating map zoom and re-center controls.
class _RouteMapControls extends StatelessWidget {
  const _RouteMapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitRoute,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitRoute;

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
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: GochanoLanguage.text('Zoom in', 'জুম ইন'),
            child: Semantics(
              button: true,
              label: GochanoLanguage.text('Zoom in', 'জুম ইন'),
              child: InkWell(
                onTap: onZoomIn,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(Icons.add_rounded, size: 20),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          Tooltip(
            message: GochanoLanguage.text('Zoom out', 'জুম আউট'),
            child: Semantics(
              button: true,
              label: GochanoLanguage.text('Zoom out', 'জুম আউট'),
              child: InkWell(
                onTap: onZoomOut,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(Icons.remove_rounded, size: 20),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          Tooltip(
            message: GochanoLanguage.text('Fit route to view', 'সম্পূর্ণ রুট দেখুন'),
            child: Semantics(
              button: true,
              label: GochanoLanguage.text('Fit route to view', 'সম্পূর্ণ রুট দেখুন'),
              child: InkWell(
                onTap: onFitRoute,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(
                      Icons.crop_free_rounded,
                      size: 18,
                      color: colors.commute,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
