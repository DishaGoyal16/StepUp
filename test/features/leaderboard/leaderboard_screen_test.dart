import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/core/widgets/widgets.dart';
import 'package:stepup/domain/campus_activity.dart';
import 'package:stepup/features/leaderboard/leaderboard_list.dart';

import '../../support/harness.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> _student(int rank, String uid, String name, num value, {String? hostelId}) => {
      'rank': rank,
      'uid': uid,
      'name': name,
      'photoUrl': null,
      'hostelId': hostelId,
      'value': value,
    };

/// 1 server-updated 2 minutes before the harness clock (2026-11-13 06:00 UTC).
final int _updatedMs = DateTime.utc(2026, 11, 13, 5, 58).millisecondsSinceEpoch;

Harness _harness() => Harness.create(signedIn: true, withProfile: true);

Future<void> _open(WidgetTester tester, Harness h, {double height = 4000}) async {
  useTallView(tester, height: height);
  await h.pumpApp(tester, initialLocation: '/leaderboard');
  await settle(tester);
}

void main() {
  testWidgets('shows podium, ranked rows, metric label, caption and privacy note', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': [
            _student(1, 'u1', 'Asha Rao', 21000, hostelId: 'agira'),
            _student(2, 'u2', 'Bhavya Singh', 18000, hostelId: 'vyom'),
            _student(3, 'u3', 'Chirag Jain', 15000),
            _student(4, h.user!.uid, 'Aarav Sharma', 12000, hostelId: 'agira'),
          ],
          'me': {'rank': 4, 'value': 12000},
          'metricLabel': 'Verified steps',
          'periodKey': '2026-W46',
          'updatedAt': _updatedMs,
        });
    await _open(tester, h);

    // Default selection: Campus + Weekly.
    final call = h.functions.callsTo('getLeaderboard').first;
    expect(call.params['scope'], 'CAMPUS');
    expect(call.params['period'], 'WEEKLY');
    expect(call.params['limit'], 50);

    expect(find.text('Leaderboard'), findsWidgets);
    expect(find.byType(PodiumWidget), findsOneWidget);
    final podium = tester.widget<PodiumWidget>(find.byType(PodiumWidget));
    expect(podium.entries.map((e) => e.name), ['Asha Rao', 'Bhavya Singh', 'Chirag Jain']);
    expect(podium.entries.first.valueLabel, '21,000 steps');

    // Ranked rows: all four, with steps and hostel display names.
    expect(find.byType(LeaderboardRow), findsNWidgets(4));
    expect(find.text('21,000'), findsOneWidget);
    expect(find.text('12,000'), findsOneWidget);
    expect(find.text('Agira Hall'), findsNWidgets(2), reason: 'hostelId looked up via deps.hostels');
    expect(find.text('Vyom Hall'), findsOneWidget);
    expect(find.text('Asha Rao'), findsNWidgets(2), reason: 'podium + list');

    // My row is highlighted with a "You" tag; no pinned card (I am in the list).
    expect(find.text('You'), findsOneWidget);
    expect(find.byKey(const Key('leaderboard-your-rank')), findsNothing);

    // Metric label + period + updated time, caption, privacy note.
    expect(
      find.text('Ranked by Verified steps · Week 2026-W46 · updated 2 min ago'),
      findsOneWidget,
    );
    expect(find.text('Only verified steps are ranked.'), findsOneWidget);
    expect(
      find.text('Students who hide themselves from leaderboards are not shown.'),
      findsOneWidget,
    );

    // Selectors.
    for (final l in ['Campus', 'My hostel', 'Hostels', 'Buddies', 'Daily', 'Weekly', 'Monthly', 'All-time']) {
      expect(find.widgetWithText(ChoiceChip, l), findsOneWidget, reason: l);
    }
    expect(find.text('Average per participant'), findsNothing, reason: 'metric toggle only on Hostels');
  });

  testWidgets('pins a "Your rank" card when I am outside the returned list', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': [
            _student(1, 'u1', 'Asha Rao', 21000),
            _student(2, 'u2', 'Bhavya Singh', 18000),
          ],
          'me': {'rank': 57, 'value': 1234},
          'metricLabel': 'Verified steps',
          'periodKey': '2026-W46',
          'updatedAt': _updatedMs,
        });
    await _open(tester, h);

    final pinned = find.byKey(const Key('leaderboard-your-rank'));
    expect(pinned, findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('Your rank')), findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('57')), findsOneWidget, reason: 'rank badge');
    expect(find.descendant(of: pinned, matching: find.text('1,234')), findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('Aarav Sharma')), findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('You')), findsOneWidget);
    expect(find.byType(LeaderboardRow), findsNWidgets(3), reason: '2 list rows + the pinned one');
  });

  testWidgets('"not ranked" hint when the server has no rank for me', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': [_student(1, 'u1', 'Asha Rao', 21000)],
          'me': {'rank': null, 'value': 0},
          'metricLabel': 'Verified steps',
        });
    await _open(tester, h);
    expect(find.byKey(const Key('leaderboard-your-rank')), findsNothing);
    expect(find.byKey(const Key('leaderboard-not-ranked')), findsOneWidget);
  });

  testWidgets('switching the period calls the server again; DAILY bars use the daily goal', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': [
            _student(1, 'u1', 'Asha Rao', p['period'] == 'DAILY' ? 5000 : 21000),
          ],
          'metricLabel': 'Verified steps',
          'periodKey': p['period'] == 'DAILY' ? '20261113' : '2026-W46',
          'updatedAt': _updatedMs,
        });
    await _open(tester, h);
    LinearProgressIndicator bar() =>
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first);
    expect(bar().value, 1.0, reason: 'weekly: the leader is the basis');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Daily'));
    await settle(tester);
    expect(h.functions.callsTo('getLeaderboard').last.params['period'], 'DAILY');
    expect(find.text('Ranked by Verified steps · Fri 13 Nov · updated 2 min ago'), findsOneWidget);
    expect(bar().value, 0.5, reason: '5,000 of the 10,000 daily goal');

    await tester.tap(find.widgetWithText(ChoiceChip, 'All-time'));
    await settle(tester);
    expect(h.functions.callsTo('getLeaderboard').last.params['period'], 'ALL_TIME');
  });

  testWidgets('Hostels board: metric toggle, participants, total and average, my hostel highlighted',
      (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) {
      final avg = p['hostelMetric'] == 'AVERAGE';
      return {
        'entries': [
          {'rank': 1, 'hostelId': 'vyom', 'name': 'Vyom Hall', 'value': avg ? 4200 : 50400, 'participants': 12, 'total': 50400, 'average': 4200},
          {'rank': 2, 'hostelId': 'agira', 'name': 'Agira Hall', 'value': avg ? 3000 : 90000, 'participants': 30, 'total': 90000, 'average': 3000},
        ],
        'me': {'rank': 2, 'value': avg ? 3000 : 90000},
        'metricLabel': avg ? 'Average verified steps per participant' : 'Total verified steps',
        'periodKey': '2026-W46',
        'updatedAt': _updatedMs,
      };
    });
    await _open(tester, h);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Hostels'));
    await settle(tester);
    var call = h.functions.callsTo('getLeaderboard').last;
    expect(call.params['scope'], 'HOSTELS');
    expect(call.params['hostelMetric'], 'AVERAGE', reason: 'default: fairer for big hostels');

    expect(find.text('Hostel ranking metric'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Average per participant'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Total verified steps'), findsOneWidget);
    expect(
      find.text('Ranked by Average verified steps per participant · Week 2026-W46 · updated 2 min ago'),
      findsOneWidget,
    );
    expect(find.text('12 participants · Total 50,400 · Avg 4,200'), findsOneWidget);
    expect(find.text('30 participants · Total 90,000 · Avg 3,000'), findsOneWidget);
    expect(find.text('avg per participant'), findsNWidgets(2));
    // My hostel (Agira) is the highlighted row; I am in the list, so no pinned card.
    expect(find.text('You'), findsOneWidget);
    expect(find.byKey(const Key('leaderboard-your-rank')), findsNothing);
    final podium = tester.widget<PodiumWidget>(find.byType(PodiumWidget));
    expect(podium.entries.first.valueLabel, '4,200 avg');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Total verified steps'));
    await settle(tester);
    call = h.functions.callsTo('getLeaderboard').last;
    expect(call.params['hostelMetric'], 'TOTAL');
    expect(find.text('Ranked by Total verified steps · Week 2026-W46 · updated 2 min ago'), findsOneWidget);
    expect(find.text('total steps'), findsNWidgets(2));
    expect(tester.widget<PodiumWidget>(find.byType(PodiumWidget)).entries.first.valueLabel,
        '50,400 total');
  });

  testWidgets('empty board shows a friendly message and still the notes', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': <Object>[],
          'me': {'rank': null, 'value': 0},
          'metricLabel': 'Verified steps',
        });
    await _open(tester, h);
    expect(find.text('No rankings yet'), findsOneWidget);
    expect(find.byType(PodiumWidget), findsNothing);
    expect(find.text('Only verified steps are ranked.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Buddies'));
    await settle(tester);
    expect(find.textContaining('Add buddies'), findsOneWidget);
  });

  testWidgets('error state shows the message; "Try again" recovers', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': [_student(1, 'u1', 'Asha Rao', 100)],
          'metricLabel': 'Verified steps',
        });
    h.functions.failNext(
      'getLeaderboard',
      AppException.fromCallable(code: 'unavailable'),
    );
    await _open(tester, h);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);
    expect(find.byType(PodiumWidget), findsNothing);
    // Selectors and notes stay available.
    expect(find.widgetWithText(ChoiceChip, 'Weekly'), findsOneWidget);
    expect(find.text('Only verified steps are ranked.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.byType(PodiumWidget), findsOneWidget);
  });

  testWidgets('pull-to-refresh asks the server again and keeps the selection', (tester) async {
    final h = _harness();
    var n = 0;
    h.functions.on('getLeaderboard', (p) {
      n++;
      return {
        'entries': [_student(1, 'u1', 'Asha Rao', n * 1000)],
        'metricLabel': 'Verified steps',
      };
    });
    await _open(tester, h, height: 1000);
    expect(find.text('1,000'), findsOneWidget);
    expect(h.functions.callsTo('getLeaderboard'), hasLength(1));

    await tester.drag(find.byKey(const Key('leaderboard-scroll')), const Offset(0, 700));
    await settle(tester);
    expect(h.functions.callsTo('getLeaderboard'), hasLength(2));
    expect(find.text('2,000'), findsOneWidget);
    expect(h.functions.callsTo('getLeaderboard').last.params['scope'], 'CAMPUS');
  });

  testWidgets('a failed refresh keeps the board and shows an inline error', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': [_student(1, 'u1', 'Asha Rao', 1000)],
          'metricLabel': 'Verified steps',
        });
    await _open(tester, h, height: 1000);
    h.functions.failNext('getLeaderboard', AppException.fromCallable(code: 'unavailable'));
    await tester.drag(find.byKey(const Key('leaderboard-scroll')), const Offset(0, 700));
    await settle(tester);
    expect(find.byKey(const Key('leaderboard-refresh-error')), findsOneWidget);
    expect(find.byType(PodiumWidget), findsOneWidget, reason: 'old board still shown');
  });


  testWidgets('narrow phone (320 px): long names and hostel rows do not overflow', (tester) async {
    final h = _harness();
    h.functions.on('getLeaderboard', (p) => {
          'entries': [
            if (p['scope'] == 'HOSTELS')
              {'rank': 1, 'hostelId': 'vasudha-e', 'name': 'Vasudha Hall - Block E', 'value': 123456, 'participants': 120, 'total': 14814720, 'average': 123456}
            else
              _student(1, 'u1', 'A Remarkably Long Student Name Indeed', 1234567, hostelId: 'vasudha-e'),
          ],
          'me': {'rank': 120, 'value': 5},
          'metricLabel': 'Verified steps',
        });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await h.pumpApp(tester, initialLocation: '/leaderboard');
    await settle(tester);
    expect(find.text('Vasudha Hall - Block E'), findsWidgets);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Hostels'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hostels'));
    await settle(tester);
    expect(find.byType(LeaderboardRow), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  group('Home campus activity slot', () {
    testWidgets('registers my WEEKLY campus rank', (tester) async {
      final h = _harness();
      h.functions.on('getLeaderboard', (p) => {
            'entries': [_student(1, 'u1', 'Asha Rao', 1000)],
            'me': {'rank': 9, 'value': 500},
          });
      await _open(tester, h);
      final before = h.functions.callsTo('getLeaderboard').length;
      final a = await h.deps.campusActivity.load(h.user!.uid);
      expect(a.myLeaderboardRank, 9);
      final p = h.functions.callsTo('getLeaderboard').skip(before).single.params;
      expect(p['scope'], 'CAMPUS');
      expect(p['period'], 'WEEKLY');
    });

    testWidgets('is null when the callable fails', (tester) async {
      final h = _harness();
      h.functions.on('getLeaderboard', (p) => {'entries': <Object>[]});
      await _open(tester, h);
      h.functions.failNext('getLeaderboard', AppException.fromCallable(code: 'unavailable'));
      final a = await h.deps.campusActivity.load(h.user!.uid);
      expect(a.myLeaderboardRank, isNull);
      expect(CampusSlot.values, contains(CampusSlot.myLeaderboardRank));
    });
  });
}
