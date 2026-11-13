import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/auth/fake_auth_repository.dart';
import 'package:stepup/data/functions/callables.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/features/profile/settings_screen.dart';
import 'package:stepup/features/profile/settings_view_model.dart';

import '../../support/harness.dart';
import 'profile_test_support.dart';

Finder switchOf(String group, String key) => find.byKey(ValueKey('switch-$group-$key'));

bool isOn(WidgetTester tester, String group, String key) =>
    tester.widget<SwitchListTile>(switchOf(group, key)).value;

void main() {
  group('SettingsViewModel', () {
    late FakeFunctionsClient fn;
    late FakeAuthRepository auth;
    late SettingsViewModel vm;
    late int signOuts;
    final profile = makeProfile('u1');

    setUp(() {
      fn = FakeFunctionsClient()
        ..on('updateProfile', (_) => {'ok': true})
        ..on('requestAccountDeletion', (_) => {'ok': true});
      auth = FakeAuthRepository();
      signOuts = 0;
      vm = SettingsViewModel(
        callables: Callables(fn),
        functions: fn,
        auth: auth,
        signOut: () async => signOuts++,
      );
    });

    tearDown(() => vm.dispose());

    test('missing preferences default to true (server default)', () {
      expect(vm.valueOf(profile, SettingsGroup.notificationPrefs, 'buddy'), isTrue);
      expect(vm.valueOf(profile, SettingsGroup.privacy, 'discoverable'), isTrue);
    });

    test('setSwitch is optimistic and sends only that key through updateProfile', () async {
      final f = vm.setSwitch(profile, SettingsGroup.notificationPrefs, 'bets', false);
      expect(vm.valueOf(profile, SettingsGroup.notificationPrefs, 'bets'), isFalse, reason: 'before the server answers');
      await f;
      expect(fn.callsTo('updateProfile').single.params, {
        'notificationPrefs': {'bets': false},
      });
      expect(vm.valueOf(profile, SettingsGroup.notificationPrefs, 'bets'), isFalse);
      expect(vm.takeFeedback(), isNull);
    });

    test('privacy switches use the privacy map', () async {
      await vm.setSwitch(profile, SettingsGroup.privacy, 'showHostel', false);
      expect(fn.callsTo('updateProfile').single.params, {
        'privacy': {'showHostel': false},
      });
    });

    test('a failed save rolls the switch back and reports the error', () async {
      fn.failNext('updateProfile', AppException.fromCallable(code: 'unavailable'));
      await vm.setSwitch(profile, SettingsGroup.privacy, 'discoverable', false);
      expect(vm.valueOf(profile, SettingsGroup.privacy, 'discoverable'), isTrue);
      final fb = vm.takeFeedback()!;
      expect(fb.isError, isTrue);
      expect(fb.text, contains('Network problem'));
    });

    test('setting a switch to its current value sends nothing', () async {
      await vm.setSwitch(profile, SettingsGroup.privacy, 'discoverable', true);
      expect(fn.calls, isEmpty);
    });

    test('reconcile drops choices the live profile has caught up with', () async {
      await vm.setSwitch(profile, SettingsGroup.privacy, 'showWeeklySteps', false);
      final updated = rebuildProfile(profile, privacy: {'showWeeklySteps': false});
      vm.reconcile(updated);
      expect(vm.valueOf(updated, SettingsGroup.privacy, 'showWeeklySteps'), isFalse);
      // the profile now flips it back elsewhere: the UI follows the profile
      final back = rebuildProfile(profile, privacy: {'showWeeklySteps': true});
      expect(vm.valueOf(back, SettingsGroup.privacy, 'showWeeklySteps'), isTrue);
    });

    test('password reset calls the auth repository; errors become feedback', () async {
      await vm.sendPasswordReset('student@thapar.edu');
      expect(auth.passwordResetsSentTo, ['student@thapar.edu']);
      expect(vm.takeFeedback()!.text, contains('student@thapar.edu'));
      auth.failNextWithCode = 'network-request-failed';
      await vm.sendPasswordReset('student@thapar.edu');
      expect(vm.takeFeedback()!.isError, isTrue);
    });

    test('requestDeletion calls requestAccountDeletion once and marks it requested', () async {
      expect(await vm.requestDeletion(), isTrue);
      expect(fn.callsTo('requestAccountDeletion'), hasLength(1));
      expect(vm.deletionRequested, isTrue);
      expect(vm.takeFeedback()!.text, contains('admin'));
    });

    test('requestDeletion failure is reported and not marked as requested', () async {
      fn.failNext('requestAccountDeletion', AppException.fromCallable(code: 'unavailable'));
      expect(await vm.requestDeletion(), isFalse);
      expect(vm.deletionRequested, isFalse);
      expect(vm.takeFeedback()!.isError, isTrue);
    });

    test('logout signs out', () async {
      await vm.logout();
      expect(signOuts, 1);
    });
  });

  group('SettingsScreen', () {
    testWidgets('lists all notification and privacy switches', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/settings');
      for (final k in ['buddy', 'challenges', 'bets', 'leaderboard', 'reminders']) {
        expect(switchOf('notificationPrefs', k), findsOneWidget, reason: k);
      }
      for (final k in ['discoverable', 'showHostel', 'showWeeklySteps', 'showOnLeaderboards']) {
        expect(switchOf('privacy', k), findsOneWidget, reason: k);
      }
    });

    testWidgets('toggling a switch saves through updateProfile', (tester) async {
      final env = ProfileEnv();
      env.functions.on('updateProfile', (_) => {'ok': true});
      await env.pump(tester, initial: '/profile/settings');
      expect(isOn(tester, 'notificationPrefs', 'challenges'), isTrue);
      await tapVisible(tester, switchOf('notificationPrefs', 'challenges'));
      expect(isOn(tester, 'notificationPrefs', 'challenges'), isFalse);
      expect(env.functions.callsTo('updateProfile').single.params, {
        'notificationPrefs': {'challenges': false},
      });
    });

    testWidgets('server failure rolls the switch back and shows an error', (tester) async {
      final env = ProfileEnv();
      env.functions.failNext('updateProfile', AppException.fromCallable(code: 'unavailable'));
      await env.pump(tester, initial: '/profile/settings');
      await tapVisible(tester, switchOf('privacy', 'showOnLeaderboards'));
      expect(isOn(tester, 'privacy', 'showOnLeaderboards'), isTrue, reason: 'rolled back');
      expect(find.textContaining('Network problem'), findsOneWidget);
    });

    testWidgets('stored preferences are reflected', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/settings');
      env.harness.profiles.setProfile(
        rebuildProfile(env.profile, privacy: {'discoverable': false}, notificationPrefs: {'reminders': false}),
      );
      await settle(tester);
      expect(isOn(tester, 'privacy', 'discoverable'), isFalse);
      expect(isOn(tester, 'notificationPrefs', 'reminders'), isFalse);
      expect(isOn(tester, 'privacy', 'showHostel'), isTrue);
    });

    testWidgets('account: email is read-only and the reset email is sent via auth', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/settings');
      expect(find.byKey(const ValueKey('account-email')), findsOneWidget);
      expect(find.text('student@thapar.edu'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'email cannot be edited');
      await tapVisible(tester, find.text('Send password reset email'));
      expect(env.harness.auth.passwordResetsSentTo, ['student@thapar.edu']);
      expect(find.textContaining('Password reset email sent'), findsOneWidget);
    });

    testWidgets('logout asks for confirmation, then signs out', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/settings');
      expect(env.harness.auth.currentUser, isNotNull);
      await tapVisible(tester, find.text('Log out'));
      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(env.harness.auth.currentUser, isNotNull);
      await tapVisible(tester, find.text('Log out'));
      await tester.tap(find.widgetWithText(TextButton, 'Log out'));
      await settle(tester);
      expect(env.harness.auth.currentUser, isNull);
    });

    testWidgets('delete account: dialog explains it is a request; confirming calls requestAccountDeletion', (tester) async {
      final env = ProfileEnv();
      env.functions.on('requestAccountDeletion', (_) => {'ok': true});
      await env.pump(tester, initial: '/profile/settings');
      await tapVisible(tester, find.byKey(const ValueKey('delete-account')));
      expect(find.text('Request account deletion?'), findsOneWidget);
      expect(find.textContaining('an admin reviews and processes it'), findsOneWidget);
      // cancel first: nothing is sent
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(env.functions.callsTo('requestAccountDeletion'), isEmpty);
      await tapVisible(tester, find.byKey(const ValueKey('delete-account')));
      await tester.tap(find.text('Send request'));
      await settle(tester);
      expect(env.functions.callsTo('requestAccountDeletion'), hasLength(1));
      expect(find.byKey(const ValueKey('deletion-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-account')), findsNothing);
    });

    testWidgets('an account already pending deletion shows the pending note instead of the button', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/settings');
      env.harness.profiles.setProfile(rebuildProfile(env.profile, status: 'DELETION_REQUESTED'));
      await settle(tester);
      expect(find.byKey(const ValueKey('deletion-pending')), findsOneWidget);
    });

    testWidgets('about card shows the version and the credits line', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/profile/settings');
      await tester.ensureVisible(find.text(kCreditsLine));
      expect(find.text('Built for a healthier campus — Project Lead: Disha'), findsOneWidget);
      expect(find.text('Version ${env.deps.config.appVersion}'), findsOneWidget);
    });

    testWidgets('admin link appears only for admins and opens /admin', (tester) async {
      final student = ProfileEnv();
      await student.pump(tester, initial: '/profile/settings');
      expect(find.text('Open admin tools'), findsNothing);

      final admin = ProfileEnv(role: 'admin');
      await admin.pump(tester, initial: '/profile/settings');
      expect(find.text('Open admin tools'), findsOneWidget);
      await tapVisible(tester, find.text('Open admin tools'));
      expect(find.text('STUB /admin'), findsOneWidget);
    });
  });
}
