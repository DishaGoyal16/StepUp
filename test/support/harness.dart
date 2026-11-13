import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/app.dart';
import 'package:stepup/app_dependencies.dart';
import 'package:stepup/core/config/app_config.dart';
import 'package:stepup/core/utils/clock.dart';
import 'package:stepup/data/auth/fake_auth_repository.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/profile/fake_profile_draft_store.dart';
import 'package:stepup/data/profile/fake_profile_repository.dart';
import 'package:stepup/data/steps/fake_permission_client.dart';
import 'package:stepup/data/steps/fake_step_engine_channel.dart';
import 'package:stepup/domain/auth_state.dart';
import 'package:stepup/domain/profile_enums.dart';
import 'package:stepup/domain/user_profile.dart';

const String kStudentEmail = 'student@thapar.edu';

UserProfile makeProfile(
  String uid, {
  String name = 'Aarav Sharma',
  String hostelId = 'agira',
  int dailyGoal = 10000,
  int streak = 4,
  String role = 'student',
}) =>
    UserProfile(
      uid: uid,
      displayName: name,
      email: kStudentEmail,
      hostelId: hostelId,
      fitnessLevel: FitnessLevel.intermediate,
      sportsInterests: const ['Running'],
      preferredActivity: 'Running',
      preferredTime: PreferredTime.morning,
      buddyType: BuddyType.both,
      dailyGoal: dailyGoal,
      currentStreak: streak,
      role: role,
    );

/// Everything a widget test needs, wired with fakes.
class Harness {
  Harness._({
    required this.auth,
    required this.profiles,
    required this.firestore,
    required this.functions,
    required this.engine,
    required this.permissions,
    required this.clock,
    required this.drafts,
    required this.deps,
    this.user,
  });

  factory Harness.create({
    bool signedIn = false,
    bool verified = true,
    bool withProfile = false,
    bool googleEnabled = false,
    String name = 'Aarav Sharma',
    FakeStepEngineChannel? engine,
    FakeFirestoreAccess? firestore,
    String role = 'student',
  }) {
    final auth = FakeAuthRepository();
    AuthUser? user;
    if (signedIn) {
      user = auth.seedAccount(email: kStudentEmail, verified: verified, displayName: name);
    }
    final profiles = FakeProfileRepository(
      auth: auth,
      initial: (user != null && withProfile) ? makeProfile(user.uid, name: name, role: role) : null,
    );
    final fs = firestore ?? FakeFirestoreAccess();
    final fn = FakeFunctionsClient()
      ..on('registerDevice', (_) => {'isRewardDevice': true})
      ..on('syncStepBuckets', (_) => {'accepted': 0, 'duplicates': 0, 'rejected': <Object>[]});
    final eng = engine ?? FakeStepEngineChannel();
    final perms = FakePermissionClient();
    final clock = FakeClock(DateTime.utc(2026, 11, 13, 6)); // 11:30 IST, 20261113
    final drafts = InMemoryProfileDraftStore();
    final deps = AppDependencies.fake(
      config: AppConfig(
        apiKey: 'fake',
        appId: 'fake',
        projectId: 'fake',
        googleSignInEnabled: googleEnabled,
      ),
      clock: clock,
      auth: auth,
      profiles: profiles,
      firestore: fs,
      functions: fn,
      stepEngine: eng,
      permissions: perms,
      draftStore: drafts,
    );
    return Harness._(
      auth: auth,
      profiles: profiles,
      firestore: fs,
      functions: fn,
      engine: eng,
      permissions: perms,
      clock: clock,
      drafts: drafts,
      deps: deps,
      user: user,
    );
  }

  final FakeAuthRepository auth;
  final FakeProfileRepository profiles;
  final FakeFirestoreAccess firestore;
  final FakeFunctionsClient functions;
  final FakeStepEngineChannel engine;
  final FakePermissionClient permissions;
  final FakeClock clock;
  final InMemoryProfileDraftStore drafts;
  final AppDependencies deps;
  final AuthUser? user;

  /// Pumps the whole app and lets the router settle.
  Future<void> pumpApp(WidgetTester tester, {String? initialLocation}) async {
    // A fresh element tree every time (a second pump of the same widget type
    // would otherwise reuse the previous State and its dependencies).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(StepUpApp(deps: deps, initialLocation: initialLocation));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A tall viewport so lazily-built list children are all on screen.
void useTallView(WidgetTester tester, {double height = 4000}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(800, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
