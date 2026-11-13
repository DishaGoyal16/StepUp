import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the app binds the native ledger to the user before any summary, sync or tracking',
      (tester) async {
    useTallView(tester);
    final h = Harness.create(signedIn: true, withProfile: true);
    await h.pumpApp(tester);
    await settle(tester);

    final calls = h.engine.calls;
    expect(h.engine.bindCalls, [h.user!.uid]);
    final bind = calls.indexOf('bindUser');
    expect(bind, 0, reason: 'bindUser is the very first engine call');
    for (final m in ['getTodaySummary', 'getBucketsForSync', 'getDeviceId']) {
      expect(calls, contains(m), reason: m);
      expect(calls.indexOf(m), greaterThan(bind), reason: '$m after bindUser');
    }
  });

  testWidgets('nothing is bound or read while signed out or unverified', (tester) async {
    useTallView(tester);
    final out = Harness.create();
    await out.pumpApp(tester);
    await settle(tester);
    expect(out.engine.calls, isEmpty);

    final unverified = Harness.create(signedIn: true, verified: false);
    await unverified.pumpApp(tester);
    await settle(tester);
    expect(unverified.engine.calls, isEmpty);
  });

  testWidgets('sign-out then another user signs in: the second user is bound before any sync',
      (tester) async {
    useTallView(tester);
    final h = Harness.create(signedIn: true, withProfile: true);
    await h.pumpApp(tester);
    await settle(tester);
    final a = h.user!;

    await h.auth.signOut();
    await settle(tester);
    expect(h.deps.stepBinding.isReady, isFalse, reason: 'signed out: unbound');
    h.engine.calls.clear();

    final b = h.auth.seedAccount(email: 'second@thapar.edu', displayName: 'Second Student');
    h.profiles.setProfile(makeProfile(b.uid, name: 'Second Student'));
    await settle(tester);

    expect(h.engine.bindCalls, [a.uid, b.uid]);
    expect(h.deps.stepBinding.uid, b.uid);
    expect(h.deps.stepBinding.isReady, isTrue);
    expect(h.engine.calls.first, 'bindUser');
    final bind = h.engine.calls.indexOf('bindUser');
    expect(h.engine.calls.indexOf('getBucketsForSync'), greaterThan(bind));
    expect(h.engine.calls.indexOf('getTodaySummary'), greaterThan(bind));
  });
}
