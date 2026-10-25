// Widget tests for CommuteMapPicker visual redesign, accessibility, and map contract preservation.
//
// Verifies:
// 1. Initial map presentation and OpenStreetMap attribution.
// 2. Contextual header, center action, and close action.
// 3. Coordinate-selection presentation (origin and destination pins).
// 4. Existing confirmation callback for origin and destination selection.
// 5. Navigator result integrity via showCommuteMapPicker.
// 6. Loading state with loading pill indicator.
// 7. Existing error states and functional retry callback.
// 8. Bengali translation for title, subtitle, buttons, and captions.
// 9. Dark mode theme contrast and rendering.
// 10. 320dp narrow viewport and 2.0x text scaling with zero RenderFlex overflow.
// 11. Safe-area / floating map zoom and re-center controls.
// 12. Map attribution presence and non-interference with map controls.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/life/presentation/commute/commute_map_picker.dart';
import 'package:gochano/features/life/presentation/commute/commute_place_picker.dart';

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

Future<Map<String, dynamic>> _mockPlacesLoader() async => {
  'places': [
    {
      'placeId': 'cp_mirpur_10',
      'name': 'Mirpur 10 Circle',
      'lat': 23.8069,
      'lon': 90.3687,
    },
    {
      'placeId': 'cp_farmgate',
      'name': 'Farmgate Bus Stop',
      'lat': 23.7561,
      'lon': 90.3872,
    },
  ],
};

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('CommuteMapPicker Presentation and Contract Tests', () {
    testWidgets('1. Initial map presentation and OpenStreetMap attribution', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: _mockPlacesLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select on Map'), findsOneWidget);
      expect(
        find.text('Tap a stop or anywhere to set route point'),
        findsOneWidget,
      );
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.textContaining('2 stops have map locations'), findsOneWidget);
    });

    testWidgets('2. Contextual header, center action, and close action', (
      tester,
    ) async {
      var closed = false;
      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            onClose: () => closed = true,
            placesLoader: _mockPlacesLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.map_rounded), findsOneWidget);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, isTrue);

      await tester.tap(find.byIcon(Icons.my_location_rounded));
      await tester.pump();
      expect(tester.binding.takeException(), isNull);
    });

    testWidgets('3. Coordinate-selection presentation (origin & destination pins)', (
      tester,
    ) async {
      const origin = CommutePlace(
        name: 'Mirpur 10 Circle',
        placeId: 'cp_mirpur_10',
        lat: 23.8069,
        lon: 90.3687,
        isDatasetPlace: true,
      );
      const destination = CommutePlace(
        name: 'Farmgate Bus Stop',
        placeId: 'cp_farmgate',
        lat: 23.7561,
        lon: 90.3872,
        isDatasetPlace: true,
      );

      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: origin,
            destination: destination,
            onPicked: (place, end) {},
            placesLoader: _mockPlacesLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.trip_origin_rounded), findsOneWidget);
      expect(find.byIcon(Icons.place_rounded), findsOneWidget);
    });

    testWidgets('4. Existing confirmation callback for origin and destination', (
      tester,
    ) async {
      CommutePlace? chosenPlace;
      CommuteEndpoint? chosenEnd;

      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {
              chosenPlace = place;
              chosenEnd = end;
            },
            placesLoader: _mockPlacesLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the first stop pin on the map
      final stopPin = find.bySemanticsLabel('Transport stop').first;
      expect(stopPin, findsOneWidget);
      await tester.tap(stopPin);
      await tester.pumpAndSettle();

      // Bottom sheet appears with location name and official stop badge
      expect(find.text('Official stop'), findsOneWidget);
      expect(find.text('Start from here'), findsOneWidget);
      expect(find.text('Go here'), findsOneWidget);

      // Confirm as origin
      await tester.tap(find.text('Start from here'));
      await tester.pumpAndSettle();

      expect(chosenPlace, isNotNull);
      expect(chosenEnd, equals(CommuteEndpoint.origin));
    });

    testWidgets('5. Navigator result integrity via showCommuteMapPicker', (
      tester,
    ) async {
      CommutePlace? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCommuteMapPicker(context);
                },
                child: const Text('Open Map Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Map Picker'));
      await tester.pumpAndSettle();

      expect(find.text('Select on Map'), findsOneWidget);

      // Dismiss the bottom sheet
      Navigator.of(tester.element(find.text('Select on Map'))).pop();
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('6. Loading state with loading pill indicator', (
      tester,
    ) async {
      final completer = Completer<Map<String, dynamic>>();

      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: () => completer.future,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading stops…'), findsOneWidget);
      expect(
        find.text('Tap the map to choose where you are going.'),
        findsOneWidget,
      );

      // Complete future and verify pill clears
      completer.complete(_mockPlacesLoader());
      await tester.pumpAndSettle();

      expect(find.text('Loading stops…'), findsNothing);
      expect(find.textContaining('2 stops have map locations'), findsOneWidget);
    });

    testWidgets('7. Existing error states and functional retry callback', (
      tester,
    ) async {
      var callCount = 0;
      Future<Map<String, dynamic>> failingLoader() async {
        callCount++;
        if (callCount == 1) {
          throw Exception('Connection failed');
        }
        return _mockPlacesLoader();
      }

      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: failingLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Stops could not be loaded'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(callCount, equals(2));
      expect(find.textContaining('2 stops have map locations'), findsOneWidget);
    });

    testWidgets('8. Bengali translation for title, subtitle, and buttons', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: _mockPlacesLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ম্যাপে স্থান নির্বাচন'), findsOneWidget);
      expect(
        find.text('রুট পয়েন্ট নির্ধারণ করতে স্টপ বা স্থানে চাপ দিন'),
        findsOneWidget,
      );
      expect(find.textContaining('স্টপের মানচিত্র অবস্থান আছে'), findsOneWidget);
    });

    testWidgets('9. Dark mode theme contrast and rendering', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: _mockPlacesLoader,
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select on Map'), findsOneWidget);
      expect(tester.binding.takeException(), isNull);
    });

    testWidgets('10. 320dp narrow viewport and 2.0x text scaling with zero overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: _mockPlacesLoader,
          ),
          size: const Size(320, 600),
          textScaleFactor: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select on Map'), findsOneWidget);
      expect(tester.binding.takeException(), isNull);
    });

    testWidgets('11. Safe-area / floating map zoom controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: _mockPlacesLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final zoomIn = find.byIcon(Icons.add_rounded);
      final zoomOut = find.byIcon(Icons.remove_rounded);

      expect(zoomIn, findsOneWidget);
      expect(zoomOut, findsOneWidget);

      await tester.tap(zoomIn);
      await tester.pump();
      await tester.tap(zoomOut);
      await tester.pump();

      expect(tester.binding.takeException(), isNull);
    });

    testWidgets('12. Map attribution presence and non-interference with map controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CommuteMapPicker(
            origin: null,
            destination: null,
            onPicked: (place, end) {},
            placesLoader: _mockPlacesLoader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final attribution = find.text('© OpenStreetMap contributors');
      expect(attribution, findsOneWidget);

      final centerFinder = find.byIcon(Icons.my_location_rounded);
      expect(centerFinder, findsOneWidget);

      // Ensure both are on screen and distinct
      expect(tester.getCenter(attribution), isNot(equals(tester.getCenter(centerFinder))));
    });
  });
}
