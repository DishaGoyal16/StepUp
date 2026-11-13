import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for a defect found by the on-device E2E run.
///
/// FlutterFire's `useAuthEmulator` / `useFirestoreEmulator` / `useFunctionsEmulator` / `useStorageEmulator`
/// rewrite `localhost` and `127.0.0.1` to `10.0.2.2` on Android unless `automaticHostMapping: false`.
/// A physical phone that reaches the PC through `adb reverse` (documented in FIREBASE_SETUP.md with
/// `EMULATOR_HOST=127.0.0.1`) then talked to an address that does not exist for it, and every Auth call failed with
/// `network-request-failed`. The bootstrap must hand the configured host through unchanged for all four services.
void main() {
  test('every emulator hook in initializeFirebase disables automatic host mapping', () {
    final src = File('lib/data/firebase_bootstrap.dart').readAsStringSync();
    for (final call in ['useAuthEmulator', 'useFirestoreEmulator', 'useFunctionsEmulator', 'useStorageEmulator']) {
      final i = src.indexOf(call);
      expect(i, greaterThanOrEqualTo(0), reason: '$call is called');
      final end = src.indexOf(');', i);
      expect(src.substring(i, end), contains('automaticHostMapping: false'), reason: '$call must not remap the host');
    }
  });
}
