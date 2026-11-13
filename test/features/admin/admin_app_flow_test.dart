import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';

import '../../support/harness.dart';

/// Whole app (router guard + `adminProviders` + callable repository) over the
/// fake callable client.
void main() {
  Harness adminHarness({String role = 'admin'}) {
    final h = Harness.create(signedIn: true, withProfile: true, role: role);
    h.functions
      ..on('adminStats', (_) => {
            'users': 42,
            'activeUsers': 40,
            'deletionRequests': 0,
            'activeChallenges': 2,
            'openReports': 3,
            'openRiskEvents': 1,
            'activeBets': 0,
          })
      ..on('adminListStudents', (p) => {
            'students': [
              {
                'uid': 'u1',
                'displayName': 'Aarav Sharma',
                'email': 'aarav@thapar.edu',
                'hostelId': 'agira',
                'status': 'ACTIVE',
                'role': 'student',
                'pointsBalance': 5,
              },
            ],
            'nextCursor': null,
          })
      ..on('adminSuspendUser', (_) => {'ok': true});
    return h;
  }

  testWidgets('an admin reaches /admin and sees the stats from adminStats', (tester) async {
    useTallView(tester);
    final h = adminHarness();
    await h.pumpApp(tester, initialLocation: '/admin');
    await tester.pumpAndSettle();
    expect(find.text('Registered students'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Open reports'), findsOneWidget);
    expect(h.functions.callsTo('adminStats'), hasLength(1));
  });

  testWidgets('students screen suspends through the callable with the reason', (tester) async {
    useTallView(tester);
    final h = adminHarness();
    await h.pumpApp(tester, initialLocation: '/admin/students');
    await tester.pumpAndSettle();
    expect(find.text('Aarav Sharma'), findsOneWidget);
    await tester.tap(find.text('Aarav Sharma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend student'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Fake steps');
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();
    final call = h.functions.callsTo('adminSuspendUser').single;
    expect(call.params, {'uid': 'u1', 'suspend': true, 'reason': 'Fake steps'});
    expect(find.text('Aarav Sharma suspended.'), findsOneWidget);
  });

  testWidgets('a student who is not an admin is bounced from /admin to Home (no admin call is made)', (tester) async {
    useTallView(tester);
    final h = adminHarness(role: 'student');
    await h.pumpApp(tester, initialLocation: '/admin');
    await tester.pumpAndSettle();
    expect(find.text('Registered students'), findsNothing);
    expect(find.text('Welcome to StepUp'), findsOneWidget);
    expect(h.functions.callsTo('adminStats'), isEmpty);
  });

  testWidgets('if the server rejects a non-admin token anyway, the UI shows the denied state', (tester) async {
    // e.g. the profile says admin but the custom claim was revoked.
    useTallView(tester);
    final h = adminHarness();
    h.functions.failNext(
      'adminStats',
      AppException.fromCallable(code: 'permission-denied', message: 'admin only', details: {'reason': 'ADMIN_REQUIRED'}),
    );
    await h.pumpApp(tester, initialLocation: '/admin');
    await tester.pumpAndSettle();
    expect(find.text('Admins only'), findsOneWidget);
    expect(find.textContaining('Admin access required'), findsOneWidget);
  });
}
