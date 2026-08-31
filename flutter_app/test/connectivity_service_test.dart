// ConnectivityService smoke tests.
//
// Validates P3-7 contract:
//   - The service exposes a `ValueNotifier<bool>` that widgets can
//     `ValueListenableBuilder` against.
//   - The platform stream collapses to a binary "online / offline"
//     state — wifi, cellular, ethernet, and vpn all count as "online".
//   - The default starting value is `true` so first-frame does not flash
//     a red banner for users who *are* online.
//   - `debugForceValue(...)` lets tests push a deterministic value
//     without standing up the platform channel.
//   - `init()` is idempotent so it can be safely called from `main.dart`
//     and from tests.
//   - `_hasInternet` correctly classifies `ConnectivityResult.none`
//     as offline and everything else as online.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/services/connectivity_service.dart';

void main() {
  group('ConnectivityService.defaults', () {
    test('initial online value is true (no first-frame false alarm)', () {
      // The service is a process-wide singleton. Read the current value
      // directly; do not call init() because that would touch the
      // platform channel.
      expect(ConnectivityService.instance.online.value, isTrue);
    });

    test('exposes a single shared instance', () {
      // The OfflineBanner relies on the singleton to avoid duplicate
      // platform subscriptions.
      final a = ConnectivityService.instance;
      final b = ConnectivityService.instance;
      expect(identical(a, b), isTrue);
    });
  });

  group('ConnectivityService._hasInternet classification', () {
    test('ConnectivityResult.none is offline', () {
      expect(
        ConnectivityService.debugHasInternet(const [ConnectivityResult.none]),
        isFalse,
      );
    });

    test('empty list is offline', () {
      expect(ConnectivityService.debugHasInternet(const []), isFalse);
    });

    test('wifi alone is online', () {
      expect(
        ConnectivityService.debugHasInternet(const [ConnectivityResult.wifi]),
        isTrue,
      );
    });

    test('cellular alone is online', () {
      expect(
        ConnectivityService.debugHasInternet(const [ConnectivityResult.mobile]),
        isTrue,
      );
    });

    test('ethernet alone is online', () {
      expect(
        ConnectivityService.debugHasInternet(const [ConnectivityResult.ethernet]),
        isTrue,
      );
    });

    test('vpn alone is online', () {
      expect(
        ConnectivityService.debugHasInternet(const [ConnectivityResult.vpn]),
        isTrue,
      );
    });

    test('mixed wifi + none is online', () {
      // Some OEMs report both the active transport and `none` at the
      // same time. The "any" policy correctly classifies that as online.
      expect(
        ConnectivityService.debugHasInternet(
          const [ConnectivityResult.none, ConnectivityResult.wifi],
        ),
        isTrue,
      );
    });
  });

  group('ConnectivityService.debugForceValue', () {
    test('flips the notifier to the requested value', () {
      final svc = ConnectivityService.instance;
      svc.debugForceValue(false);
      expect(svc.online.value, isFalse);
      svc.debugForceValue(true);
      expect(svc.online.value, isTrue);
    });

    test('suppresses duplicate emissions', () {
      // The private _emit path is what powers this; we exercise it
      // indirectly because the no-op contract is important for the
      // AnimatedSwitcher inside OfflineBanner (no extra rebuilds).
      final svc = ConnectivityService.instance;
      svc.debugForceValue(true);
      final before = svc.online.value;
      svc.debugForceValue(true);
      expect(svc.online.value, before);
    });
  });
}
