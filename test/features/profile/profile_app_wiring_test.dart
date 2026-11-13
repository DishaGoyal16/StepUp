import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/router/app_routes.dart';

import '../../support/harness.dart';
import 'profile_test_support.dart';

/// Goes through the real `StepUpApp` (real router, shell and
/// `appProviders`), i.e. the wiring done in `profileProviders` /
/// `notificationsProviders` with `AppDependencies.fake()`.
void main() {
  testWidgets('the Profile tab renders from the real providers', (tester) async {
    useTallView(tester);
    final h = Harness.create(signedIn: true, withProfile: true);
    await h.pumpApp(tester, initialLocation: AppRoutes.profile);
    await settle(tester);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Agira Hall'), findsOneWidget);
    expect(find.text('Verified steps'), findsOneWidget);
    expect(find.text('Achievements'), findsOneWidget);
    expect(find.text('0 of 6 earned'), findsOneWidget);
    expect(find.text('Virtual points'), findsOneWidget);
    // getLeaderboard has no fake handler here: the rank failure is tolerated.
    expect(find.text('Rank unavailable right now.'), findsOneWidget);
  });

  testWidgets('Edit profile and Settings open inside the app router', (tester) async {
    useTallView(tester);
    final h = Harness.create(signedIn: true, withProfile: true);
    await h.pumpApp(tester, initialLocation: AppRoutes.profile);
    await settle(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Open admin tools'), findsNothing);
  });

  testWidgets('/notifications opens full-screen from the real router', (tester) async {
    useTallView(tester);
    final h = Harness.create(signedIn: true, withProfile: true);
    await h.pumpApp(tester, initialLocation: AppRoutes.notifications);
    await settle(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
