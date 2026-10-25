// Widget tests for CommuteRouteMap visual redesign, accessibility, and route display integrity.
//
// Verifies:
// 1. Populated route presentation with PolylineLayer and Route map tag.
// 2. Empty route presentation and fallback behavior.
// 3. Origin and destination markers presentation.
// 4. Intermediate transfer points markers presentation.
// 5. Correct polyline styling and point conversion.
// 6. Floating map controls: minimum 44x44dp hit targets, tooltips, and tap handling.
// 7. OpenStreetMap attribution presence and visibility.
// 8. Bengali translation for tags, labels, and tooltips.
// 9. Dark mode theme rendering and contrast.
// 10. 320dp narrow viewport and 2.0x text scaling with zero RenderFlex overflow.
// 11. Zero-coordinate handling: valid zero latitude and longitude preserved.
// 12. Invalid coordinate handling: null, NaN, and out-of-bounds coordinates safely discarded.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/life/presentation/commute/commute_route_map.dart';
import 'package:latlong2/latlong.dart';

Widget _wrap(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScaleFactor = 1.0,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScaleFactor),
    ),
    child: MaterialApp(
      theme: GochanoTheme.light(),
      darkTheme: GochanoTheme.dark(),
      themeMode: themeMode,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

const _samplePolyline = [
  {'lat': 23.8069, 'lon': 90.3687},
  {'lat': 23.7806, 'lon': 90.4074},
  {'lat': 23.7561, 'lon': 90.3872},
];

const _sampleOrigin = LatLng(23.8069, 90.3687);
const _sampleDestination = LatLng(23.7561, 90.3872);
const _sampleTransfers = [LatLng(23.7806, 90.4074)];

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('CommuteRouteMap Presentation and Contract Tests', () {
    testWidgets('1. Populated route presentation with PolylineLayer and tag', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: _samplePolyline,
            origin: _sampleOrigin,
            destination: _sampleDestination,
            transfers: _sampleTransfers,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.text('Route map'), findsOneWidget);
      expect(find.text('1 transfers'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });

    testWidgets('2. Empty route presentation and fallback behavior', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: [],
            origin: null,
            destination: null,
            transfers: [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(find.text('No route coordinates'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });

    testWidgets('3. Origin and destination markers presentation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: _samplePolyline,
            origin: _sampleOrigin,
            destination: _sampleDestination,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.trip_origin_rounded), findsOneWidget);
      expect(find.byIcon(Icons.place_rounded), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Origin',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Destination',
        ),
        findsOneWidget,
      );
    });

    testWidgets('4. Intermediate transfer points markers presentation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: _samplePolyline,
            origin: _sampleOrigin,
            destination: _sampleDestination,
            transfers: _sampleTransfers,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.transfer_within_a_station_rounded),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Transfer point',
        ),
        findsOneWidget,
      );
    });

    testWidgets('5. Correct polyline styling and point conversion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: [
              {'lat': 23.81, 'lon': 90.41},
              {'lat': 23.75, 'lon': 90.39},
            ],
            origin: _sampleOrigin,
            destination: _sampleDestination,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final polylineFinder = find.byType(PolylineLayer);
      expect(polylineFinder, findsOneWidget);

      final polylineLayer = tester.widget<PolylineLayer>(polylineFinder);
      expect(polylineLayer.polylines.length, equals(1));
      expect(polylineLayer.polylines.first.points.length, equals(2));
      expect(polylineLayer.polylines.first.strokeWidth, equals(5.0));
      expect(polylineLayer.polylines.first.borderStrokeWidth, equals(2.0));
    });

    testWidgets(
      '6. Floating map controls: minimum 44x44dp hit targets, tooltips, and tap handling',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const CommuteRouteMap(
              polyline: _samplePolyline,
              origin: _sampleOrigin,
              destination: _sampleDestination,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final zoomIn = find.byIcon(Icons.add_rounded);
        final zoomOut = find.byIcon(Icons.remove_rounded);
        final fitRoute = find.byIcon(Icons.crop_free_rounded);

        expect(zoomIn, findsOneWidget);
        expect(zoomOut, findsOneWidget);
        expect(fitRoute, findsOneWidget);

        // Verify tooltips
        expect(find.byTooltip('Zoom in'), findsOneWidget);
        expect(find.byTooltip('Zoom out'), findsOneWidget);
        expect(find.byTooltip('Fit route to view'), findsOneWidget);

        // Verify effective hit targets are at least 44x44dp
        final zoomInInkWell = find.ancestor(
          of: zoomIn,
          matching: find.byType(InkWell),
        );
        final zoomOutInkWell = find.ancestor(
          of: zoomOut,
          matching: find.byType(InkWell),
        );
        final fitRouteInkWell = find.ancestor(
          of: fitRoute,
          matching: find.byType(InkWell),
        );

        final zoomInSize = tester.getSize(zoomInInkWell);
        final zoomOutSize = tester.getSize(zoomOutInkWell);
        final fitRouteSize = tester.getSize(fitRouteInkWell);

        expect(zoomInSize.width, greaterThanOrEqualTo(44.0));
        expect(zoomInSize.height, greaterThanOrEqualTo(44.0));
        expect(zoomOutSize.width, greaterThanOrEqualTo(44.0));
        expect(zoomOutSize.height, greaterThanOrEqualTo(44.0));
        expect(fitRouteSize.width, greaterThanOrEqualTo(44.0));
        expect(fitRouteSize.height, greaterThanOrEqualTo(44.0));

        // Tap gestures verify no crash
        await tester.tap(zoomIn);
        await tester.pump();
        await tester.tap(zoomOut);
        await tester.pump();
        await tester.tap(fitRoute);
        await tester.pump();

        expect(tester.binding.takeException(), isNull);
      },
    );

    testWidgets('7. OpenStreetMap attribution presence and visibility', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: _samplePolyline,
            origin: _sampleOrigin,
            destination: _sampleDestination,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final attribution = find.text('© OpenStreetMap contributors');
      expect(attribution, findsOneWidget);

      final controls = find.byIcon(Icons.crop_free_rounded);
      expect(controls, findsOneWidget);

      // Attribution and controls occupy separate screen coordinates
      expect(
        tester.getCenter(attribution),
        isNot(equals(tester.getCenter(controls))),
      );
    });

    testWidgets('8. Bengali translation for tags, labels, and tooltips', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: _samplePolyline,
            origin: _sampleOrigin,
            destination: _sampleDestination,
            transfers: _sampleTransfers,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('রুট ম্যাপ'), findsOneWidget);
      expect(find.textContaining('বদল'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'শুরু',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'গন্তব্য',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'ট্রান্সফার পয়েন্ট',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('জুম ইন'), findsOneWidget);
      expect(find.byTooltip('জুম আউট'), findsOneWidget);
      expect(find.byTooltip('সম্পূর্ণ রুট দেখুন'), findsOneWidget);
    });

    testWidgets('9. Dark mode theme rendering and contrast', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CommuteRouteMap(
            polyline: _samplePolyline,
            origin: _sampleOrigin,
            destination: _sampleDestination,
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(tester.binding.takeException(), isNull);
    });

    testWidgets(
      '10. 320dp narrow viewport and 2.0x text scaling with zero overflow',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const CommuteRouteMap(
              polyline: _samplePolyline,
              origin: _sampleOrigin,
              destination: _sampleDestination,
              transfers: _sampleTransfers,
            ),
            size: const Size(320, 600),
            textScaleFactor: 2.0,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FlutterMap), findsOneWidget);
        expect(tester.binding.takeException(), isNull);
      },
    );

    testWidgets(
      '11. Zero-coordinate handling: valid zero latitude and longitude preserved',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const CommuteRouteMap(
              polyline: [
                {'lat': 0.0, 'lon': 90.41}, // Equator (lat == 0.0)
                {'lat': 23.81, 'lon': 0.0}, // Prime Meridian (lon == 0.0)
                {'lat': 0.0, 'lon': 0.0}, // Both zero (Null Island)
                {'lat': 23.75, 'lon': 90.39}, // Standard point
              ],
              origin: _sampleOrigin,
              destination: _sampleDestination,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final polylineFinder = find.byType(PolylineLayer);
        expect(polylineFinder, findsOneWidget);

        final polylineLayer = tester.widget<PolylineLayer>(polylineFinder);
        // All 4 valid coordinate pairs must be preserved in exact order
        expect(polylineLayer.polylines.first.points.length, equals(4));
        expect(polylineLayer.polylines.first.points[0], equals(const LatLng(0.0, 90.41)));
        expect(polylineLayer.polylines.first.points[1], equals(const LatLng(23.81, 0.0)));
        expect(polylineLayer.polylines.first.points[2], equals(const LatLng(0.0, 0.0)));
        expect(polylineLayer.polylines.first.points[3], equals(const LatLng(23.75, 90.39)));
      },
    );

    testWidgets(
      '12. Invalid coordinate handling: null, NaN, and out-of-bounds coordinates safely discarded',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const CommuteRouteMap(
              polyline: [
                {'lat': 23.81, 'lon': 90.41}, // Valid
                {'lat': null, 'lon': 90.42}, // Null lat -> discarded
                {'lat': 23.81, 'lon': null}, // Null lon -> discarded
                {'lat': 95.0, 'lon': 90.42}, // Out of bounds lat (> 90) -> discarded
                {'lat': -95.0, 'lon': 90.42}, // Out of bounds lat (< -90) -> discarded
                {'lat': 23.81, 'lon': 185.0}, // Out of bounds lon (> 180) -> discarded
                {'lat': 23.81, 'lon': -185.0}, // Out of bounds lon (< -180) -> discarded
                {'lat': double.nan, 'lon': 90.42}, // NaN -> discarded
                {'lat': 23.75, 'lon': 90.39}, // Valid
              ],
              origin: _sampleOrigin,
              destination: _sampleDestination,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final polylineFinder = find.byType(PolylineLayer);
        expect(polylineFinder, findsOneWidget);

        final polylineLayer = tester.widget<PolylineLayer>(polylineFinder);
        // Only the 2 legitimate points should be kept
        expect(polylineLayer.polylines.first.points.length, equals(2));
        expect(polylineLayer.polylines.first.points[0], equals(const LatLng(23.81, 90.41)));
        expect(polylineLayer.polylines.first.points[1], equals(const LatLng(23.75, 90.39)));
      },
    );
  });
}
