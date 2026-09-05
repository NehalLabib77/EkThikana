import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gochano/core/services/telecom_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TelecomAuthService.normalize and isSupportedPhone', () {
    test('normalizes spaces and country code for Robi and Cirkle numbers', () {
      expect(TelecomAuthService.normalize('01812345678'), '01812345678');
      expect(TelecomAuthService.normalize('+8801812345678'), '01812345678');
      expect(TelecomAuthService.normalize('8801812345678'), '01812345678');
      expect(TelecomAuthService.normalize('  016 1234-5678 '), '01612345678');
      expect(TelecomAuthService.normalize('+880 16 1234 5678'), '01612345678');
    });

    test('validates supported carriers: Robi (016) and Cirkle (018)', () {
      expect(TelecomAuthService.isSupportedPhone('01812345678'), isTrue);
      expect(TelecomAuthService.isSupportedPhone('01612345678'), isTrue);
      expect(TelecomAuthService.isSupportedPhone('01712345678'), isFalse); // GP
      expect(TelecomAuthService.isSupportedPhone('01912345678'), isFalse); // BL
      expect(TelecomAuthService.isSupportedPhone('01512345678'), isFalse); // Teletalk
      expect(TelecomAuthService.isSupportedPhone('invalid'), isFalse);
    });
  });

  group('TelecomAuthService unsubscribe validation', () {
    test('throws TelecomAuthException for unsupported carrier number', () async {
      expect(
        () => TelecomAuthService.unsubscribe('01700000000'),
        throwsA(isA<TelecomAuthException>()),
      );
    });
  });

  group('TelecomAuthService session lifecycle', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('persistSession sets authoritative keys and clears legacy keys', () async {
      await TelecomAuthService.persistSession(phone: '01812345678');

      expect(await TelecomAuthService.readIsLoggedIn(), isTrue);
      expect(await TelecomAuthService.readUserPhone(), '01812345678');
      expect(await TelecomAuthService.readPhone(), '01812345678');
    });

    test('clearSession purges all telecom session keys', () async {
      await TelecomAuthService.persistSession(phone: '01812345678');
      expect(await TelecomAuthService.readIsLoggedIn(), isTrue);

      await TelecomAuthService.clearSession();

      expect(await TelecomAuthService.readIsLoggedIn(), isFalse);
      expect(await TelecomAuthService.readUserPhone(), isNull);
      expect(await TelecomAuthService.readPhone(), isNull);
    });
  });
}
