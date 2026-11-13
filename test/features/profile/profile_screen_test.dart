import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/core/widgets/widgets.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/profile_extras/badges.dart';
import 'package:stepup/data/profile_extras/extras_models.dart';
import 'package:stepup/data/profile_extras/profile_extras_reader.dart';
import 'package:stepup/domain/daily_step_summary.dart';

import 'profile_test_support.dart';

FakeFunctionsClient rank(Map<String, dynamic> me) =>
    FakeFunctionsClient()..on('getLeaderboard', (_) => {'entries': <Object>[], 'me': me});

void main() {
  testWidgets('header shows avatar, name, hostel display name, level and sports chips', (tester) async {
    final env = ProfileEnv(rankFunctions: rank({'rank': 3, 'value': 5000}));
    await env.pump(tester);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Agira Hall'), findsOneWidget);
    expect(find.text('Intermediate'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.byType(AvatarCircle), findsWidgets);
  });

  testWidgets('verified steps summary uses server summaries and links to the history', (tester) async {
    final env = ProfileEnv(rankFunctions: rank({'rank': 3, 'value': 5000}));
    // 20261113 is "today" (FakeClock 2026-11-13 11:30 IST); 20261101 is 12 days earlier.
    (env.deps.firestore as FakeFirestoreAccess).setSummaries(const [
      DailyStepSummary(dayKey: '20261113', verifiedSteps: 4000, rawSteps: 5000),
      DailyStepSummary(dayKey: '20261110', verifiedSteps: 3000, rawSteps: 3200),
      DailyStepSummary(dayKey: '20261101', verifiedSteps: 2000, rawSteps: 2100),
    ]);
    await env.pump(tester);
    expect(find.text('Verified steps'), findsOneWidget);
    expect(find.text('7,000'), findsOneWidget, reason: 'last 7 days');
    expect(find.text('9,000'), findsOneWidget, reason: 'last 30 days');
    expect(find.text('0'), findsWidgets, reason: 'lifetime verified steps default');
    await tapVisible(tester, find.text('View step history'));
    expect(find.text('STUB /home/history'), findsOneWidget);
  });

  group('campus rank', () {
    testWidgets('shows me.rank from getLeaderboard CAMPUS WEEKLY', (tester) async {
      final env = ProfileEnv(rankFunctions: rank({'rank': 12, 'value': 21000}));
      await env.pump(tester);
      expect(find.text('#12 on campus'), findsOneWidget);
      expect(find.text('21,000 verified steps this week'), findsOneWidget);
      final call = env.rankFunctions.calls.single;
      expect(call.name, 'getLeaderboard');
      expect(call.params['scope'], 'CAMPUS');
      expect(call.params['period'], 'WEEKLY');
    });

    testWidgets('not ranked yet when the board has no entry for me', (tester) async {
      final fn = FakeFunctionsClient()..on('getLeaderboard', (_) => {'entries': <Object>[]});
      final env = ProfileEnv(rankFunctions: fn);
      await env.pump(tester);
      expect(find.textContaining('Not ranked yet'), findsOneWidget);
    });

    testWidgets('a failing rank call is tolerated: the rest of the profile still renders', (tester) async {
      final fn = FakeFunctionsClient()
        ..failNext('getLeaderboard', AppException.fromCallable(code: 'unavailable'));
      final env = ProfileEnv(rankFunctions: fn);
      await env.pump(tester);
      expect(find.text('Rank unavailable right now.'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('Virtual points'), findsOneWidget);
      // retry works
      fn.on('getLeaderboard', (_) => {'me': {'rank': 2, 'value': 10}});
      await tapVisible(tester, find.text('Retry').first);
      expect(find.text('#2 on campus'), findsOneWidget);
    });

    testWidgets('tapping the card opens the leaderboard', (tester) async {
      final env = ProfileEnv(rankFunctions: rank({'rank': 1, 'value': 1}));
      await env.pump(tester);
      await tapVisible(tester, find.text('Campus rank (this week)'));
      expect(find.text('STUB /leaderboard'), findsOneWidget);
    });
  });

  group('virtual points', () {
    testWidgets('balance, reserved, recent ledger and a link to /bets/ledger', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader(
          ledger: const [
            LedgerEntry(id: '1', delta: 50, type: 'BET_WIN', note: 'vs Riya'),
            LedgerEntry(id: '2', delta: -20, type: 'RESERVE'),
          ],
        ),
      );
      await env.pump(tester);
      env.harness.profiles.setProfile(
        rebuildProfile(env.profile, pointsBalance: 340, pointsReserved: 60),
      );
      await settle(tester);
      expect(find.text('Virtual points'), findsOneWidget);
      expect(find.text('340'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Bet won - vs Riya'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(find.text('-20'), findsOneWidget);
      await tapVisible(tester, find.text('Points history'));
      expect(find.text('STUB /bets/ledger'), findsOneWidget);
    });

    testWidgets('ledger preview failure does not break the card', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader()..ledgerError = StateError('x'),
      );
      await env.pump(tester);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Points history'), findsOneWidget);
    });
  });

  group('achievements', () {
    testWidgets('earned badges are coloured, locked ones greyed with how to earn them', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader(
          achievements: [
            Achievement(badgeId: 'FIRST_1K', awardedAt: DateTime.utc(2026, 11, 2)),
            const Achievement(badgeId: 'STREAK_7'),
          ],
        ),
      );
      await env.pump(tester);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('2 of 6 earned'), findsOneWidget);
      for (final id in ['FIRST_1K', 'STREAK_7']) {
        expect(find.byKey(ValueKey('badge-$id-earned')), findsOneWidget, reason: id);
      }
      for (final id in ['TEN_K_WALKER', 'CHALLENGE_CHAMPION', 'HOSTEL_CHAMPION', 'CAMPUS_FITNESS_STAR']) {
        expect(find.byKey(ValueKey('badge-$id-locked')), findsOneWidget, reason: id);
      }
      expect(find.text('First 1K'), findsOneWidget);
      expect(find.text('10K Walker'), findsOneWidget);
      expect(find.text('Earned 2 Nov 2026'), findsOneWidget);
      expect(find.text('How to earn: Reach 10,000 verified steps in a single day.'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
    });

    testWidgets('the catalogue document text wins over the built-in layout', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader()
          ..catalogue = {
            'TEN_K_WALKER': {'title': 'Ten Thousand', 'description': 'Walk 10k in a day, no excuses.'},
          },
      );
      await env.pump(tester);
      expect(find.text('Ten Thousand'), findsOneWidget);
      expect(find.text('How to earn: Walk 10k in a day, no excuses.'), findsOneWidget);
    });

    testWidgets('an unreachable catalogue still shows the six known badges, all locked', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader()..catalogueError = StateError('offline'),
      );
      await env.pump(tester);
      expect(find.text('0 of 6 earned'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(6));
    });

    testWidgets('achievements failure shows an inline error, not a crash', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader()..achievementsError = StateError('denied'),
      );
      await env.pump(tester);
      expect(find.text('Could not load your achievements.'), findsOneWidget);
    });

    testWidgets('a newly earned badge appears live; the client never creates achievements', (tester) async {
      final extras = FakeProfileExtrasReader();
      final env = ProfileEnv(rankFunctions: rank({'rank': 1, 'value': 1}), extras: extras);
      await env.pump(tester);
      expect(find.text('0 of 6 earned'), findsOneWidget);
      extras.setAchievements(const [Achievement(badgeId: 'CAMPUS_FITNESS_STAR')]);
      await settle(tester);
      expect(find.text('1 of 6 earned'), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-CAMPUS_FITNESS_STAR-earned')), findsOneWidget);
      expect(env.functions.calls, isEmpty, reason: 'nothing was sent to the server');
    });
  });

  group('completed challenges', () {
    testWidgets('lists completed challenges with titles and opens the detail', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader(
          completed: [
            CompletedChallenge(
              challengeId: 'c1',
              title: '10,000 Steps Daily',
              completedAt: DateTime.utc(2026, 11, 5),
            ),
            const CompletedChallenge(challengeId: 'c2', title: '7-Day Walking Streak'),
          ],
        ),
      );
      await env.pump(tester);
      expect(find.text('10,000 Steps Daily'), findsOneWidget);
      expect(find.text('7-Day Walking Streak'), findsOneWidget);
      expect(find.text('Completed 5 Nov 2026'), findsOneWidget);
      await tapVisible(tester, find.text('10,000 Steps Daily'));
      expect(find.text('STUB /challenges/c1'), findsOneWidget);
    });

    testWidgets('empty state offers to browse challenges', (tester) async {
      final env = ProfileEnv(rankFunctions: rank({'rank': 1, 'value': 1}));
      await env.pump(tester);
      expect(find.text('No completed challenges yet'), findsOneWidget);
      await tapVisible(tester, find.text('Browse challenges'));
      expect(find.text('STUB /challenges'), findsOneWidget);
    });

    testWidgets('failure shows an inline error', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        extras: FakeProfileExtrasReader()..completedError = StateError('x'),
      );
      await env.pump(tester);
      expect(find.text('Could not load your challenges.'), findsOneWidget);
    });
  });

  group('buddies', () {
    testWidgets('lists accepted buddies with a count', (tester) async {
      final env = ProfileEnv(
        rankFunctions: rank({'rank': 1, 'value': 1}),
        buddies: FakeBuddyDirectory(const [
          BuddySummary(uid: 'b1', displayName: 'Riya Gupta'),
          BuddySummary(uid: 'b2', displayName: 'Kabir Singh'),
        ]),
      );
      await env.pump(tester);
      expect(find.text('2 buddies'), findsOneWidget);
      expect(find.text('Riya Gupta'), findsOneWidget);
      expect(find.text('Kabir Singh'), findsOneWidget);
      await tapVisible(tester, find.text('See all'));
      expect(find.text('STUB /buddies'), findsOneWidget);
    });

    testWidgets('empty state offers to find buddies', (tester) async {
      final env = ProfileEnv(rankFunctions: rank({'rank': 1, 'value': 1}));
      await env.pump(tester);
      expect(find.text('No buddies yet'), findsOneWidget);
      await tapVisible(tester, find.text('Find buddies'));
      expect(find.text('STUB /buddies'), findsOneWidget);
    });
  });

  testWidgets('app bar buttons open settings and notifications; Edit profile opens the editor', (tester) async {
    final env = ProfileEnv(rankFunctions: rank({'rank': 1, 'value': 1}));
    final router = await env.pump(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('Privacy'), findsOneWidget);
    router.go('/profile');
    await settle(tester);
    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
    router.go('/profile');
    await settle(tester);
    await tester.tap(find.text('Edit profile'));
    await settle(tester);
    expect(find.text('Save changes'), findsOneWidget);
  });
}
