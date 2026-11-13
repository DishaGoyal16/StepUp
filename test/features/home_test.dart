import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/data/steps/fake_step_engine_channel.dart';
import 'package:stepup/data/steps/step_permissions.dart';
import 'package:stepup/domain/campus_activity.dart';
import 'package:stepup/domain/daily_step_summary.dart';
import 'package:stepup/domain/step_models.dart';
import 'package:stepup/features/home/campus_activity_widget.dart';
import 'package:stepup/features/home/team_credits.dart';

import '../support/harness.dart';

/// Current router location of the running app.
String locationOf(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  return GoRouter.of(ctx).routerDelegate.currentConfiguration.last.matchedLocation;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _engineToday = TodaySummary(
  raw: 1200,
  verified: 900,
  pending: 50,
  rejected: 250,
  suspicious: 30,
);

Harness homeHarness({
  TodaySummary today = _engineToday,
  List<DailyStepSummary> summaries = const [],
  int unread = 0,
}) {
  return Harness.create(
    signedIn: true,
    withProfile: true,
    engine: FakeStepEngineChannel(todaySummary: today),
    firestore: FakeFirestoreAccess(summaries: summaries, unread: unread),
  );
}

void main() {
  testWidgets('shows hero, greeting, hostel and the engine\'s verified steps', (tester) async {
    useTallView(tester);
    final h = homeHarness();
    await h.pumpApp(tester);
    await settle(tester);

    expect(find.text('Welcome to StepUp'), findsOneWidget);
    expect(find.text('Your campus. Your fitness. Your community.'), findsOneWidget);
    expect(find.text('Hi, Aarav'), findsOneWidget);
    expect(find.text('Agira Hall'), findsOneWidget, reason: 'hostel under the greeting');
    // progress ring: verified / goal, percent, remaining, streak
    expect(find.text('of 10,000'), findsOneWidget);
    expect(find.text('9%'), findsOneWidget);
    expect(find.text('9,100'), findsOneWidget, reason: 'remaining');
    expect(find.text('4 days'), findsOneWidget, reason: 'streak from users.currentStreak');
    // bottom navigation order
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.map((d) => (d as NavigationDestination).label).toList(),
        ['Home', 'Buddies', 'Challenges', 'Leaderboard', 'Profile']);
  });

  testWidgets('step breakdown renders every value from the fake engine with the right labels',
      (tester) async {
    useTallView(tester);
    final h = homeHarness();
    await h.pumpApp(tester);
    await settle(tester);

    expect(find.text('Step breakdown'), findsOneWidget);
    for (final label in ['Raw', 'Verified', 'Pending', 'Rejected']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('1,200'), findsOneWidget, reason: 'raw');
    expect(find.text('900'), findsNWidgets(2), reason: 'verified: ring + tile');
    expect(find.text('50'), findsOneWidget, reason: 'pending');
    expect(find.text('250'), findsOneWidget, reason: 'rejected');
    expect(find.text('30 suspicious'), findsOneWidget);
    expect(find.text('Only verified steps count for competitions'), findsOneWidget);
  });

  testWidgets('no hard-coded numbers: an empty engine shows zeros', (tester) async {
    useTallView(tester);
    final h = homeHarness(today: const TodaySummary());
    await h.pumpApp(tester);
    await settle(tester);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 suspicious'), findsOneWidget);
    expect(find.text('10,000'), findsOneWidget, reason: 'remaining equals the goal');
    expect(find.textContaining('No verified steps recorded this week'), findsOneWidget);
  });

  testWidgets('weekly chart and verified total use dailyStepSummaries (server-confirmed history)',
      (tester) async {
    useTallView(tester);
    final semantics = tester.ensureSemantics();
    final h = homeHarness(
      today: const TodaySummary(), // engine empty (e.g. reinstall) -> server value for today
      summaries: const [
        DailyStepSummary(dayKey: '20261113', rawSteps: 5200, verifiedSteps: 4800),
        DailyStepSummary(dayKey: '20261112', rawSteps: 9000, verifiedSteps: 8000),
        DailyStepSummary(dayKey: '20261108', rawSteps: 3000, verifiedSteps: 2500),
      ],
    );
    await h.pumpApp(tester);
    await settle(tester);

    expect(find.text('4,800'), findsWidgets, reason: 'verified today from the server summary');
    expect(find.text('48%'), findsOneWidget);
    // the chart is custom painted; its semantics list every bar
    final chart = tester.getSemantics(find.bySemanticsLabel(RegExp('Weekly verified steps')));
    expect(chart.label, contains('8000 verified steps'));
    expect(chart.label, contains('4800 verified steps'));
    expect(chart.label, contains('2500 verified steps'));
    expect(find.textContaining('No verified steps recorded this week'), findsNothing);
    semantics.dispose();
  });

  testWidgets('engine and server disagree: the larger verified value for today wins', (tester) async {
    useTallView(tester);
    final h = homeHarness(
      today: const TodaySummary(raw: 3000, verified: 2000),
      summaries: const [DailyStepSummary(dayKey: '20261113', rawSteps: 1000, verifiedSteps: 500)],
    );
    await h.pumpApp(tester);
    await settle(tester);
    expect(find.text('20%'), findsOneWidget);
  });

  testWidgets('step engine unavailable: says so and falls back to server totals', (tester) async {
    useTallView(tester);
    final eng = FakeStepEngineChannel()..capabilities = const EngineCapabilities(stepCounter: false);
    final h = Harness.create(
      signedIn: true,
      withProfile: true,
      engine: eng,
      firestore: FakeFirestoreAccess(
        summaries: const [DailyStepSummary(dayKey: '20261113', rawSteps: 700, verifiedSteps: 600)],
      ),
    );
    await h.pumpApp(tester);
    await settle(tester);
    expect(find.textContaining('not available on this device'), findsWidgets);
    expect(find.text('600'), findsWidgets);
    final sw = tester.widget<Switch>(find.byKey(const ValueKey('tracking-switch')));
    expect(sw.onChanged, isNull, reason: 'cannot toggle without an engine');
  });

  testWidgets('notification bell shows the unread count', (tester) async {
    useTallView(tester);
    final h = homeHarness(unread: 3);
    await h.pumpApp(tester);
    await settle(tester);
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);

    h.firestore.setUnread(0);
    await settle(tester);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('quick actions navigate to the feature routes', (tester) async {
    useTallView(tester);
    final h = homeHarness();
    await h.pumpApp(tester);
    await settle(tester);
    for (final (label, path) in [
      ('Find a Buddy', '/buddies'),
      ('Join Challenge', '/challenges'),
      ('View Leaderboard', '/leaderboard'),
    ]) {
      await tester.tap(find.text(label));
      await settle(tester);
      expect(locationOf(tester), path, reason: label);
      await tester.tap(find.text('Home').last);
      await settle(tester);
      expect(find.text('Hi, Aarav'), findsOneWidget);
    }
    await tester.tap(find.text('Create Step Bet'));
    await settle(tester);
    expect(locationOf(tester), '/bets/new');
  });

  testWidgets('bell opens the notifications route', (tester) async {
    useTallView(tester);
    final h = homeHarness();
    await h.pumpApp(tester);
    await settle(tester);
    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester);
    expect(locationOf(tester), '/notifications');
  });

  group('step tracking card', () {
    testWidgets('switch asks for permission with a rationale, then starts tracking', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      await h.pumpApp(tester);
      await settle(tester);
      expect(find.text('Off - turn on to count steps'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tracking-switch')));
      await settle(tester);
      expect(find.text('Allow step tracking?'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(h.engine.tracking, isTrue);
      expect(find.text('On - counting your steps'), findsOneWidget);
      expect(h.permissions.prompts.length, 2);
    });

    testWidgets('declining the rationale leaves tracking off', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      await h.pumpApp(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tracking-switch')));
      await settle(tester);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(h.engine.tracking, isFalse);
      expect(find.textContaining('needs the Physical activity permission'), findsOneWidget);
    });

    testWidgets('permanently denied permission offers to open settings', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      h.permissions.promptResult[PermissionKind.activityRecognition] =
          StepPermissionState.permanentlyDenied;
      await h.pumpApp(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tracking-switch')));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('Permission needed'), findsOneWidget);
      expect(h.engine.tracking, isFalse);
      await tester.tap(find.text('Open settings'));
      await settle(tester);
      expect(h.permissions.openSettingsCalls, 1);
    });

    testWidgets('shows last sync time and the last sync problem', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      await h.pumpApp(tester);
      await settle(tester);
      expect(find.textContaining('Last synced'), findsOneWidget);

      h.engine.addBuckets([
        const EngineBucket(startMs: 1, bootCount: 1, rawDelta: 10, credited: 9, state: 'VERIFIED'),
      ]);
      h.functions.failNext('syncStepBuckets', Exception('offline'));
      await h.deps.stepSync.syncNow(force: true);
      await settle(tester);
      expect(find.textContaining('Last sync problem'), findsOneWidget);
    });

    testWidgets('"Why are some steps not counted?" explains every category and reason', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      await h.pumpApp(tester);
      await settle(tester);
      await tester.tap(find.text('Why are some steps not counted?'));
      await settle(tester);
      for (final t in [
        'Verified',
        'Pending',
        'Rejected',
        'Suspicious',
        'Unwitnessed',
        'SHAKE_PATTERN',
        'NOT_GAIT',
        'VEHICLE_MOTION',
        'EXCESS_OVER_IMU',
        'NO_IMU_EVIDENCE',
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.textContaining('only verified steps count'), findsOneWidget);
    });
  });

  group('campus activity', () {
    testWidgets('friendly empty states when nothing is provided', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: HomeCampusActivity(activity: CampusActivity.empty)),
      ));
      expect(find.text('Campus activity'), findsOneWidget);
      expect(find.text('No active challenges yet'), findsOneWidget);
      expect(find.text('Nothing scheduled yet'), findsOneWidget);
      expect(find.text('Find buddies to train with'), findsOneWidget);
      expect(find.text('Not ranked yet'), findsOneWidget);
    });

    testWidgets('Home shows the campus block fed by the registry', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      await h.pumpApp(tester);
      await settle(tester);
      expect(find.text('Campus activity'), findsOneWidget);
    });

    testWidgets('HomeCampusActivity widget on its own', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: HomeCampusActivity(activity: CampusActivity(activeChallenges: 2, myLeaderboardRank: 1)),
        ),
      ));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Not ranked yet'), findsNothing);
      expect(find.text('Nothing scheduled yet'), findsOneWidget);
    });
  });

  group('team credits', () {
    testWidgets('home shows the project lead line and the whole team', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      await h.pumpApp(tester);
      await settle(tester);
      expect(find.textContaining('Built for a healthier campus'), findsOneWidget);
      expect(find.textContaining('Project Lead: Disha'), findsOneWidget);
      for (final n in ['Disha', 'Raghav', 'Bhavya', 'Sanveer', 'Anvi', 'Kashish']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
    });

    testWidgets('Kashish is visibly lower prominence than the other team members', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TeamCredits())));
      TextStyle styleOf(String n) => tester.widget<Text>(find.text(n)).style!;
      final kashish = styleOf('Kashish');
      for (final n in ['Disha', 'Raghav', 'Bhavya', 'Sanveer', 'Anvi']) {
        final other = styleOf(n);
        expect(kashish.fontSize!, lessThan(other.fontSize!), reason: '$n font size');
        expect(kashish.fontWeight!.value, lessThan(other.fontWeight!.value), reason: '$n weight');
        expect(kashish.color!.computeLuminance(), greaterThan(other.color!.computeLuminance()),
            reason: '$n is darker/stronger');
      }
    });

    testWidgets('credits are plain text (no buttons or links)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TeamCredits())));
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('history', () {
    testWidgets('lists 30 days with raw vs verified and totals', (tester) async {
      useTallView(tester, height: 6000);
      final h = homeHarness(summaries: const [
        DailyStepSummary(dayKey: '20261113', rawSteps: 5200, verifiedSteps: 4800),
        DailyStepSummary(dayKey: '20261112', rawSteps: 9000, verifiedSteps: 8000),
      ]);
      await h.pumpApp(tester);
      await settle(tester);
      await tester.tap(find.text('View step history'));
      await settle(tester);
      expect(find.text('Step history'), findsOneWidget);
      expect(find.text('Fri 13 Nov'), findsOneWidget);
      expect(find.text('Thu 12 Nov'), findsOneWidget);
      expect(find.text('4,800 verified'), findsOneWidget);
      expect(find.text(' / 9,000 raw'), findsOneWidget);
      expect(find.text('12,800'), findsOneWidget, reason: '30-day verified total');
      expect(find.textContaining('Only verified counts'), findsOneWidget);
      expect(find.text('Thu 15 Oct'), findsOneWidget, reason: '30th day back');
    });

    testWidgets('empty history shows a friendly message', (tester) async {
      useTallView(tester);
      final h = homeHarness();
      await h.pumpApp(tester);
      await settle(tester);
      await tester.tap(find.text('View step history'));
      await settle(tester);
      expect(find.text('No synced steps yet'), findsOneWidget);
    });
  });
}
