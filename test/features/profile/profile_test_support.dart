import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:stepup/app_dependencies.dart';
import 'package:stepup/core/router/app_routes.dart';
import 'package:stepup/core/theme/app_theme.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/notifications_center/notifications_reader.dart';
import 'package:stepup/data/profile_extras/campus_rank_reader.dart';
import 'package:stepup/data/profile_extras/profile_extras_reader.dart';
import 'package:stepup/domain/user_profile.dart';
import 'package:stepup/features/auth/session_controller.dart';
import 'package:stepup/features/notifications/notifications_routes.dart';
import 'package:stepup/features/profile/profile_providers.dart';
import 'package:stepup/features/profile/profile_routes.dart';

import '../../support/harness.dart';

/// Paths that other features own; here they are stubs showing `STUB <uri>`.
const List<String> kStubPaths = [
  AppRoutes.stepHistory,
  AppRoutes.leaderboard,
  AppRoutes.buddies,
  AppRoutes.buddyRequests,
  AppRoutes.challenges,
  '/challenges/:id',
  AppRoutes.bets,
  '/bets/ledger',
  '/bets/:id',
  AppRoutes.admin,
  AppRoutes.home,
];

/// A signed-in harness with a profile, plus the fakes the profile and
/// notification screens read from.
class ProfileEnv {
  ProfileEnv({
    String role = 'student',
    FakeProfileExtrasReader? extras,
    FakeBuddyDirectory? buddies,
    FakeNotificationsReader? notifications,
    FakeFunctionsClient? rankFunctions,
  })  : harness = Harness.create(signedIn: true, withProfile: true, role: role),
        extras = extras ?? FakeProfileExtrasReader(),
        buddies = buddies ?? FakeBuddyDirectory(),
        notifications = notifications ?? FakeNotificationsReader(),
        rankFunctions = rankFunctions ?? FakeFunctionsClient();

  final Harness harness;
  final FakeProfileExtrasReader extras;
  final FakeBuddyDirectory buddies;
  final FakeNotificationsReader notifications;

  /// Handles `getLeaderboard` (the rank reader); everything else goes to
  /// `harness.functions`.
  final FakeFunctionsClient rankFunctions;

  AppDependencies get deps => harness.deps;
  FakeFunctionsClient get functions => harness.functions;
  UserProfile get profile => deps.session.profile!;

  /// Replaces the live profile (what the real `users/{uid}` stream does).
  void setProfile(UserProfile Function(UserProfile p) change) {
    harness.profiles.setProfile(change(profile));
  }

  List<SingleChildWidget> get providers => [
        Provider<AppDependencies>.value(value: deps),
        ChangeNotifierProvider<SessionController>.value(value: deps.session),
        Provider<NotificationsReader>.value(value: notifications),
        Provider<ProfileDataSources>.value(
          value: ProfileDataSources(
            extras: extras,
            buddies: buddies,
            rank: CampusRankReader(rankFunctions),
          ),
        ),
      ];

  /// Pumps `profileRoutes` + `notificationsRoutes` + stub routes at [initial].
  Future<GoRouter> pump(WidgetTester tester, {String initial = AppRoutes.profile}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 4200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    deps.session.start();
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        ...profileRoutes,
        ...notificationsRoutes,
        for (final p in kStubPaths)
          GoRoute(
            path: p,
            builder: (c, s) => Scaffold(body: Center(child: Text('STUB ${s.uri.path}'))),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: providers,
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await settle(tester);
    return router;
  }
}

/// `UserProfile` has no `copyWith`; tests rebuild it with the few fields they vary.
UserProfile rebuildProfile(
  UserProfile p, {
  int? pointsBalance,
  int? pointsReserved,
  Map<String, bool>? privacy,
  Map<String, bool>? notificationPrefs,
  String? status,
  String? photoUrl,
}) =>
    UserProfile(
      uid: p.uid,
      displayName: p.displayName,
      email: p.email,
      hostelId: p.hostelId,
      fitnessLevel: p.fitnessLevel,
      sportsInterests: p.sportsInterests,
      preferredActivity: p.preferredActivity,
      preferredTime: p.preferredTime,
      goals: p.goals,
      availability: p.availability,
      buddyType: p.buddyType,
      bio: p.bio,
      photoUrl: photoUrl ?? p.photoUrl,
      dailyGoal: p.dailyGoal,
      privacy: privacy ?? p.privacy,
      notificationPrefs: notificationPrefs ?? p.notificationPrefs,
      pointsBalance: pointsBalance ?? p.pointsBalance,
      pointsReserved: pointsReserved ?? p.pointsReserved,
      lifetimeVerifiedSteps: p.lifetimeVerifiedSteps,
      currentStreak: p.currentStreak,
      bestStreak: p.bestStreak,
      status: status ?? p.status,
      role: p.role,
    );

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Scrolls the first scrollable until [finder] is visible, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}
