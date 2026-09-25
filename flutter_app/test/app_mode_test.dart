import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
  });

  group('GochanoAppMode Enum & String Parsing', () {
    test('default mode is Study', () {
      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.study),
      );
      expect(GochanoAppModePreferences.isStudy, isTrue);
      expect(GochanoAppModePreferences.isUtility, isFalse);
    });

    test('"study" parses to Study', () {
      final mode = GochanoAppMode.fromString('study');
      expect(mode, equals(GochanoAppMode.study));
    });

    test('"utility" parses to Utility', () {
      final mode = GochanoAppMode.fromString('utility');
      expect(mode, equals(GochanoAppMode.utility));
    });

    test('null value defaults to Study', () {
      final mode = GochanoAppMode.fromString(null);
      expect(mode, equals(GochanoAppMode.study));
    });

    test('invalid/corrupted value defaults to Study', () {
      expect(GochanoAppMode.fromString(''), equals(GochanoAppMode.study));
      expect(
        GochanoAppMode.fromString('unknown_mode'),
        equals(GochanoAppMode.study),
      );
      expect(GochanoAppMode.fromString('STUDY'), equals(GochanoAppMode.study));
      expect(
        GochanoAppMode.fromString('{corrupted_json}'),
        equals(GochanoAppMode.study),
      );
    });
  });

  group('GochanoAppModePreferences Persistence & Notifier', () {
    test('notifier changes after select()', () async {
      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.study),
      );
      expect(GochanoAppModePreferences.isStudy, isTrue);

      await GochanoAppModePreferences.select(GochanoAppMode.utility);

      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.utility),
      );
      expect(GochanoAppModePreferences.isStudy, isFalse);
      expect(GochanoAppModePreferences.isUtility, isTrue);
    });

    test('select Study persists correctly', () async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'utility',
      });
      GochanoAppModePreferences.current.value = GochanoAppMode.utility;

      await GochanoAppModePreferences.select(GochanoAppMode.study);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(GochanoAppModePreferences.prefsKey),
        equals('study'),
      );
      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.study),
      );
    });

    test('select Utility persists correctly', () async {
      await GochanoAppModePreferences.select(GochanoAppMode.utility);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(GochanoAppModePreferences.prefsKey),
        equals('utility'),
      );
      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.utility),
      );
    });

    test(
      'restore round-trip works with mocked SharedPreferences for utility',
      () async {
        SharedPreferences.setMockInitialValues({
          GochanoAppModePreferences.prefsKey: 'utility',
        });

        await GochanoAppModePreferences.restore();

        expect(
          GochanoAppModePreferences.current.value,
          equals(GochanoAppMode.utility),
        );
        expect(GochanoAppModePreferences.isUtility, isTrue);
      },
    );

    test(
      'restore round-trip works with mocked SharedPreferences for study',
      () async {
        SharedPreferences.setMockInitialValues({
          GochanoAppModePreferences.prefsKey: 'study',
        });
        GochanoAppModePreferences.current.value = GochanoAppMode.utility;

        await GochanoAppModePreferences.restore();

        expect(
          GochanoAppModePreferences.current.value,
          equals(GochanoAppMode.study),
        );
        expect(GochanoAppModePreferences.isStudy, isTrue);
      },
    );

    test('restore with missing key defaults to Study', () async {
      SharedPreferences.setMockInitialValues({});
      GochanoAppModePreferences.current.value = GochanoAppMode.utility;

      await GochanoAppModePreferences.restore();

      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.study),
      );
    });

    test('restore with corrupted key defaults to Study', () async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'random_garbage_123',
      });
      GochanoAppModePreferences.current.value = GochanoAppMode.utility;

      await GochanoAppModePreferences.restore();

      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.study),
      );
    });
  });
}
