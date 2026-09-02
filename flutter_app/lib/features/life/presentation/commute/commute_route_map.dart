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

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';

class CommuteRouteMap extends StatelessWidget {
  const CommuteRouteMap({
    super.key,
    required this.polyline,
    required this.origin,
    required this.destination,
    this.height = 220,
  });

  /// Route geometry from the backend, as `{lat, lon}` maps.
  final List<Map<String, dynamic>> polyline;

  final LatLng? origin;
  final LatLng? destination;
  final double height;

  /// Dhaka, used only when there is nothing to fit to.
  static const _fallbackCentre = LatLng(23.8103, 90.4125);

  List<LatLng> get _points => polyline
      .map((p) {
        final lat = (p['lat'] as num?)?.toDouble();
        final lon = (p['lon'] as num?)?.toDouble();
        return (lat == null || lon == null) ? null : LatLng(lat, lon);
      })
      .whereType<LatLng>()
      .toList();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final points = _points;

    final markers = <LatLng>[?origin, ?destination];
    final fitTargets = points.isNotEmpty ? points : markers;

    return ClipRRect(
      borderRadius: GochanoRadius.lgAll,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: GochanoRadius.lgAll,
          ),
          child: RepaintBoundary(
            child: FlutterMap(
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
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ekthikana.ekthikana',
                  // Tiles are the heaviest thing on this screen; keeping the
                  // retina override off avoids fetching 4x the bytes on a
                  // phone that will not resolve them anyway.
                  retinaMode: false,
                ),
                if (points.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        strokeWidth: 5,
                        color: colors.commute,
                        borderStrokeWidth: 1.5,
                        borderColor: colors.surface,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (origin != null)
                      Marker(
                        point: origin!,
                        width: 36,
                        height: 36,
                        child: _Pin(
                          icon: Icons.trip_origin_rounded,
                          color: colors.commute,
                        ),
                      ),
                    if (destination != null)
                      Marker(
                        point: destination!,
                        width: 36,
                        height: 36,
                        child: _Pin(
                          icon: Icons.place_rounded,
                          color: colors.error,
                        ),
                      ),
                  ],
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
class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color});

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
      child: Center(child: Icon(icon, size: 18, color: color)),
    );
  }
}
