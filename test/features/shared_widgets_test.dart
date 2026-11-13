import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/theme/app_theme.dart';
import 'package:stepup/core/widgets/not_configured_screen.dart';
import 'package:stepup/core/widgets/widgets.dart';
import 'package:stepup/data/notifications/fake_push_service.dart';
import 'package:stepup/data/notifications/push_service.dart';
import 'package:stepup/data/profile/profile_repository.dart';
import 'package:stepup/domain/profile_draft.dart';
import 'package:stepup/domain/user_profile.dart';
import 'package:stepup/domain/auth_state.dart';
import 'package:stepup/features/auth/session_controller.dart';

import '../support/harness.dart';

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void main() {
  group('backend not configured screen', () {
    testWidgets('explains the missing configuration and how to provide it', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const BackendNotConfiguredScreen()));
      expect(find.text('Backend not configured'), findsOneWidget);
      expect(find.textContaining('Nothing is faked'), findsOneWidget);
      for (final key in [
        'FIREBASE_API_KEY',
        'FIREBASE_APP_ID',
        'FIREBASE_PROJECT_ID',
        'FIREBASE_MESSAGING_SENDER_ID',
        'FIREBASE_STORAGE_BUCKET',
        'USE_FIREBASE_EMULATOR',
        'EMULATOR_HOST',
      ]) {
        expect(find.textContaining(key, findRichText: true), findsWidgets, reason: key);
      }
      expect(find.textContaining('demo-stepup'), findsOneWidget);
      // there is no sign-in UI on this screen
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('shared widgets', () {
    testWidgets('PrimaryButton: disabled, loading, enabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(Column(children: [
        const PrimaryButton(label: 'Off', onPressed: null),
        PrimaryButton(label: 'Busy', onPressed: () => taps++, loading: true),
        PrimaryButton(label: 'On', onPressed: () => taps++),
      ])));
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Off')).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('On'));
      expect(taps, 1);
    });

    testWidgets('AvatarCircle shows initials when there is no photo', (tester) async {
      await tester.pumpWidget(wrap(const Column(children: [
        AvatarCircle(name: 'Aarav Sharma'),
        AvatarCircle(name: 'single'),
        AvatarCircle(name: ''),
      ])));
      expect(find.text('AS'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('ProgressRing clamps and paints', (tester) async {
      await tester.pumpWidget(wrap(const Column(children: [
        ProgressRing(progress: 0, size: 80, child: Text('zero')),
        ProgressRing(progress: 0.5, size: 80, child: Text('half')),
        ProgressRing(progress: 7, size: 80, child: Text('over')),
        ProgressRing(progress: double.nan, size: 80, child: Text('nan')),
      ])));
      expect(find.text('half'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatTile, SectionHeader, RankBadge', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(Column(children: [
        const StatTile(label: 'Streak', value: '5 days', caption: 'best 9'),
        SectionHeader('Title', actionLabel: 'See all', onAction: () => tapped = true),
        const RankBadge(rank: 1),
        const RankBadge(rank: 12),
      ])));
      expect(find.text('5 days'), findsOneWidget);
      expect(find.text('best 9'), findsOneWidget);
      await tester.tap(find.text('See all'));
      expect(tapped, isTrue);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('FilterChipsRow selects', (tester) async {
      var selected = 'Daily';
      await tester.pumpWidget(wrap(StatefulBuilder(
        builder: (context, set) => FilterChipsRow<String>(
          options: const ['Daily', 'Weekly', 'Monthly'],
          selected: selected,
          labelOf: (s) => s,
          onSelected: (s) => set(() => selected = s),
        ),
      )));
      await tester.tap(find.text('Weekly'));
      await tester.pump();
      expect(selected, 'Weekly');
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Weekly')).selected, isTrue);
    });

    testWidgets('PodiumWidget lays out 2nd | 1st | 3rd and tolerates fewer entries', (tester) async {
      await tester.pumpWidget(wrap(const PodiumWidget(entries: [
        PodiumEntry(name: 'Gold', valueLabel: '300'),
        PodiumEntry(name: 'Silver', valueLabel: '200'),
        PodiumEntry(name: 'Bronze', valueLabel: '100'),
      ])));
      final gold = tester.getCenter(find.text('Gold')).dx;
      final silver = tester.getCenter(find.text('Silver')).dx;
      final bronze = tester.getCenter(find.text('Bronze')).dx;
      expect(silver, lessThan(gold));
      expect(gold, lessThan(bronze));

      await tester.pumpWidget(wrap(const PodiumWidget(entries: [PodiumEntry(name: 'Solo', valueLabel: '1')])));
      expect(find.text('Solo'), findsOneWidget);
      await tester.pumpWidget(wrap(const PodiumWidget(entries: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState and ErrorState (retry)', (tester) async {
      var retried = 0;
      await tester.pumpWidget(wrap(Column(children: [
        const EmptyState(title: 'Nothing', message: 'yet'),
        ErrorState(message: 'Broke', onRetry: () => retried++),
        const LoadingState(label: 'Loading...'),
      ])));
      expect(find.text('Nothing'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('AsyncStreamBuilder: loading -> data -> empty -> error with retry', (tester) async {
      final c = StreamController<List<int>>();
      addTearDown(c.close);
      var retried = false;
      Widget build() => wrap(AsyncStreamBuilder<List<int>>(
            stream: c.stream,
            isEmpty: (l) => l.isEmpty,
            empty: const Text('EMPTY'),
            onRetry: () => retried = true,
            builder: (context, l) => Text('items ${l.length}'),
          ));
      await tester.pumpWidget(build());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      c.add([1, 2]);
      await tester.pump();
      expect(find.text('items 2'), findsOneWidget);
      c.add([]);
      await tester.pump();
      expect(find.text('EMPTY'), findsOneWidget);
      c.addError('x');
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not load this right now.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });

  group('theme', () {
    test('uses the design-system colours and is light only', () {
      final t = AppTheme.light();
      expect(t.brightness, Brightness.light);
      expect(t.colorScheme.primary, const Color(0xFF35A86B));
      expect(t.colorScheme.secondary, const Color(0xFF8BD6A8));
      expect(t.scaffoldBackgroundColor, const Color(0xFFF7FAF7));
      expect(t.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(t.colorScheme.onSurface, const Color(0xFF18352A));
      expect(AppColors.mint, const Color(0xFFE6F5EC));
      expect(AppColors.grey, const Color(0xFFE7ECE8));
      expect(t.useMaterial3, isTrue);
      expect(AppRadius.card, 20);
    });

    testWidgets('app never switches to dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      useTallView(tester);
      final h = Harness.create();
      await h.pumpApp(tester);
      final ctx = tester.element(find.text('Welcome to StepUp'));
      expect(Theme.of(ctx).brightness, Brightness.light);
    });
  });

  group('SessionController', () {
    test('tracks auth + profile state transitions', () async {
      final h = Harness.create();
      final session = SessionController(auth: h.auth, profiles: h.profiles)..start();
      addTearDown(session.dispose);
      expect(session.state.initializing, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(session.state.initializing, isFalse);
      expect(session.state.isSignedIn, isFalse);

      final u = h.auth.seedAccount(email: kStudentEmail, verified: false);
      await Future<void>.delayed(Duration.zero);
      expect(session.state.user?.uid, u.uid);
      expect(session.state.isVerified, isFalse);
      expect(session.state.profileStatus, ProfileStatus.unknown);

      h.auth.simulateEmailVerified();
      await h.auth.reloadUser();
      await Future<void>.delayed(Duration.zero);
      expect(session.state.isVerified, isTrue);
      expect(session.state.profileStatus, ProfileStatus.missing);

      h.profiles.setProfile(makeProfile(u.uid, role: 'admin'));
      await Future<void>.delayed(Duration.zero);
      expect(session.state.profileStatus, ProfileStatus.exists);
      expect(session.state.isAdmin, isTrue);
      expect(session.profile?.displayName, 'Aarav Sharma');

      await h.auth.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(session.state.isSignedIn, isFalse);
      expect(session.profile, isNull);
    });

    // Found on a real phone: right after e-mail verification the first profile read was denied by the rules (the
    // cached ID token still said email_verified=false) and the student saw "We could not load your profile".
    test('a profile read error right after verification refreshes the token and retries once', () async {
      final h = Harness.create();
      final flaky = _FlakyProfiles(h.profiles, failures: 1);
      final session = SessionController(auth: h.auth, profiles: flaky)..start();
      addTearDown(session.dispose);
      h.auth.seedAccount(email: kStudentEmail, verified: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(flaky.watchCalls, 2, reason: 'one failed read + one automatic retry');
      expect(session.state.profileStatus, ProfileStatus.missing, reason: 'recovered: no error screen');
    });

    test('a second consecutive error is shown (no endless retry loop); manual retry works again', () async {
      final h = Harness.create();
      final flaky = _FlakyProfiles(h.profiles, failures: 2);
      final session = SessionController(auth: h.auth, profiles: flaky)..start();
      addTearDown(session.dispose);
      h.auth.seedAccount(email: kStudentEmail, verified: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(flaky.watchCalls, 2);
      expect(session.state.profileStatus, ProfileStatus.error);
      session.retryProfile();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(session.state.profileStatus, ProfileStatus.missing);
    });
  });

  group('push', () {
    testWidgets('foreground messages appear as a snackbar', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      await h.pumpApp(tester);
      (h.deps.push as FakePushService).deliver(const PushMessage(title: 'Buddy request', body: 'Riya wants to train'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Buddy request - Riya wants to train'), findsOneWidget);
    });

    testWidgets('push is initialised once the user is set up, and the token reaches device registration',
        (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      await h.pumpApp(tester);
      final push = h.deps.push as FakePushService;
      expect(push.initCalls, 1);
      push.deliverToken('fcm-token-1');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      final regs = h.functions.callsTo('registerDevice').toList();
      expect(regs.last.params['fcmToken'], 'fcm-token-1');
    });

    testWidgets('push is not started while signed out', (tester) async {
      useTallView(tester);
      final h = Harness.create();
      await h.pumpApp(tester);
      expect((h.deps.push as FakePushService).initCalls, 0);
    });
  });

  group('sign out', () {
    testWidgets('flushes unsent steps, stops tracking, then signs out', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      await h.pumpApp(tester);
      await tester.runAsync(() async {
        h.engine.tracking = true;
        await h.deps.signOut();
      });
      expect(h.engine.tracking, isFalse);
      expect(h.engine.calls, contains('getBucketsForSync'));
      expect(h.auth.currentUser, isNull);
    });
  });
}

/// Profile repository whose first [failures] reads fail (like a denied read with a stale ID token).
class _FlakyProfiles implements ProfileRepository {
  _FlakyProfiles(this.inner, {required this.failures});

  final ProfileRepository inner;
  int failures;
  int watchCalls = 0;

  @override
  Stream<UserProfile?> watchProfile(String uid) {
    watchCalls++;
    if (failures > 0) {
      failures--;
      return Stream<UserProfile?>.error(Exception('permission-denied'));
    }
    return inner.watchProfile(uid);
  }

  @override
  Future<void> createProfile(ProfileDraft draft, {String? photoUrl}) => inner.createProfile(draft, photoUrl: photoUrl);

  @override
  Future<void> updateProfile(Map<String, dynamic> fields) => inner.updateProfile(fields);
}
