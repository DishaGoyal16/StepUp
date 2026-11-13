import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/challenges/challenge_models.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/domain/daily_step_summary.dart';
import 'package:stepup/domain/campus_activity.dart';
import 'package:stepup/features/challenges/challenges_routes.dart';

import '../../support/harness.dart';
import 'challenge_test_support.dart';

Finder _segment(String label) => find.widgetWithText(ChoiceChip, label);

Challenge _fiveK() => mkChallenge(
      id: 'tpl_5k',
      title: '5,000 Steps Daily',
      metric: ChallengeMetric.dailyTargetDays,
      target: 1,
      dailyTarget: 5000,
      durationDays: 1,
      participantCount: 12,
      rewardPoints: 20,
    );

Challenge _weekly() => mkChallenge(
      id: 'tpl_50k',
      title: '50,000 Steps Weekly',
      target: 50000,
      durationDays: 7,
      participantCount: 1,
      rewardPoints: 60,
    );

void main() {
  group('discovery', () {
    testWidgets('lists the catalogue with plain-language goal, type, status, participants and my progress',
        (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [_weekly(), _fiveK()]);
      rig.reader.putParticipation(mkPart('tpl_50k', rig.uid, progress: 3200, windowStart: '20261113', windowEnd: '20261119'));
      await rig.pump(tester);

      expect(find.text('Challenges'), findsOneWidget);
      for (final s in ['Individual', 'Buddy', 'Inter-Hostel', 'Campus', 'My challenges']) {
        expect(_segment(s), findsOneWidget, reason: s);
      }
      expect(find.text('5,000 Steps Daily'), findsOneWidget);
      expect(find.text('Reach 5,000 verified steps in a day'), findsOneWidget);
      expect(find.text('50,000 Steps Weekly'), findsOneWidget);
      expect(find.text('Walk 50,000 verified steps'), findsOneWidget);
      expect(find.text('1 day, starts the day you join'), findsOneWidget);
      expect(find.text('7 days, starts the day you join'), findsOneWidget);
      expect(find.text('Active'), findsNWidgets(2));
      expect(find.text('12 participants'), findsOneWidget);
      expect(find.text('1 participant'), findsOneWidget);
      // my progress only on the joined one
      expect(find.text('3,200 / 50,000 steps - 6%'), findsOneWidget);
      expect(find.text('Joined'), findsOneWidget);
      expect(find.textContaining('Only verified steps count'), findsOneWidget);
      // the catalogue is ordered easiest first: 5,000 daily before 50,000 weekly
      final y5k = tester.getTopLeft(find.text('5,000 Steps Daily')).dy;
      final y50k = tester.getTopLeft(find.text('50,000 Steps Weekly')).dy;
      expect(y5k, lessThan(y50k));
    });

    testWidgets('no seed data in the app: an empty backend shows an honest empty state', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create();
      await rig.pump(tester);
      expect(find.text('No individual challenges yet'), findsOneWidget);
      expect(find.text('5,000 Steps Daily'), findsNothing);
    });

    testWidgets('offline: shows the error with Try again, which recovers', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [_fiveK()]);
      rig.reader.offline = true;
      await rig.pump(tester);
      expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);
      expect(find.text('5,000 Steps Daily'), findsNothing);

      rig.reader.offline = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('5,000 Steps Daily'), findsOneWidget);
    });

    testWidgets('pull to refresh re-queries the open challenges', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [_fiveK()]);
      await rig.pump(tester);
      final before = rig.reader.openFetchCount;
      // the trigger distance is 25 % of the (tall) test viewport
      await tester.drag(find.text('5,000 Steps Daily'), const Offset(0, 1800));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(rig.reader.openFetchCount, greaterThan(before));
    });

    testWidgets('inter-hostel segment: upcoming competition, whether my hostel competes and the ranking rule',
        (tester) async {
      useTallView(tester);
      final w = fixedWindow('20261115', 7);
      final rig = ChallengeRig.create(challenges: [
        mkChallenge(
          id: 'h1',
          type: ChallengeType.interHostel,
          title: 'Hostel Clash',
          status: ChallengeStatus.upcoming,
          windowMode: WindowMode.fixed,
          startAt: w.start,
          endAt: w.end,
          hostelIds: ['agira', 'tejas'],
          isTemplate: false,
        ),
        mkChallenge(
          id: 'h2',
          type: ChallengeType.interHostel,
          title: 'Girls Hall Cup',
          status: ChallengeStatus.upcoming,
          windowMode: WindowMode.fixed,
          startAt: w.start,
          endAt: w.end,
          hostelIds: ['ira'],
          aggregation: HostelAggregation.total,
          isTemplate: false,
        ),
      ]);
      await rig.pump(tester);
      await tester.tap(_segment('Inter-Hostel'));
      await settle(tester);
      expect(find.text('Hostel Clash'), findsOneWidget);
      expect(find.text('Upcoming'), findsNWidgets(2));
      expect(find.textContaining('Your hostel is competing. Ranked by average verified steps per participant'), findsOneWidget);
      expect(find.textContaining('Your hostel is not part of this competition. Ranked by total verified steps'), findsOneWidget);
      expect(find.text('Sun 15 Nov to Sat 21 Nov'), findsNWidgets(2));
      expect(find.text('Starts in 1d 12h'), findsNWidgets(2));
      expect(find.textContaining('created by the admin team'), findsOneWidget);
    });

    testWidgets('campus segment empty state and My challenges empty state with a way back', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [_fiveK()]);
      await rig.pump(tester);
      await tester.tap(_segment('Campus'));
      await settle(tester);
      expect(find.text('No campus challenges right now'), findsOneWidget);

      await tester.tap(_segment('My challenges'));
      await settle(tester);
      expect(find.text('You have not joined a challenge yet'), findsOneWidget);
      await tester.tap(find.text('Browse challenges'));
      await settle(tester);
      expect(find.text('5,000 Steps Daily'), findsOneWidget);
    });

    testWidgets('My challenges lists what I joined with live progress', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [_weekly(), _fiveK()]);
      rig.reader.putParticipation(mkPart('tpl_50k', rig.uid, progress: 10000, windowStart: '20261113', windowEnd: '20261119'));
      await rig.pump(tester);
      await tester.tap(_segment('My challenges'));
      await settle(tester);
      expect(find.text('50,000 Steps Weekly'), findsOneWidget);
      expect(find.text('5,000 Steps Daily'), findsNothing);
      expect(find.text('10,000 / 50,000 steps - 20%'), findsOneWidget);

      // live: progress moves without a reload
      rig.reader.putParticipation(mkPart('tpl_50k', rig.uid, progress: 25000, windowStart: '20261113', windowEnd: '20261119'));
      await settle(tester);
      expect(find.text('25,000 / 50,000 steps - 50%'), findsOneWidget);
    });

    testWidgets('tapping a card opens its detail', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [_weekly()]);
      rig.functions.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      await rig.pump(tester);
      await tester.tap(find.text('50,000 Steps Weekly'));
      await settle(tester);
      expect(find.text('Rules'), findsOneWidget);
      expect(find.text('Join challenge'), findsOneWidget);
    });
  });

  group('buddy segment', () {
    Challenge pendingInvite() => mkChallenge(
          id: 'inv',
          type: ChallengeType.buddy,
          title: 'Riya vs Aarav',
          status: ChallengeStatus.pending,
          target: 20000,
          durationDays: 3,
          isTemplate: false,
          createdBy: 'riya',
          participantCount: 1,
        );

    testWidgets('invitation shows Accept / Decline; Accept calls respondChallengeInvite', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [pendingInvite()]);
      rig.reader.putParticipation(mkPart('inv', rig.uid, status: ParticipantStatus.invited));
      rig.functions.on('respondChallengeInvite', (p) {
        rig.reader.putChallenge(mkChallenge(
          id: 'inv',
          type: ChallengeType.buddy,
          title: 'Riya vs Aarav',
          status: ChallengeStatus.upcoming,
          target: 20000,
          durationDays: 3,
          isTemplate: false,
        ));
        rig.reader.putParticipation(mkPart('inv', rig.uid));
        return {'ok': true};
      });
      await rig.pump(tester);
      await tester.tap(_segment('Buddy'));
      await settle(tester);

      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('Riya vs Aarav'), findsOneWidget);
      expect(find.text('Waiting for buddy'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await settle(tester);

      expect(rig.functions.callsTo('respondChallengeInvite').single.params, {'challengeId': 'inv', 'accept': true});
      expect(find.text('Challenge accepted. It starts at the next midnight (IST).'), findsOneWidget);
      expect(find.text('Invitations'), findsNothing);
      expect(find.text('Active and upcoming'), findsOneWidget);
    });

    testWidgets('Decline sends accept=false; a server error is shown', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [pendingInvite()]);
      rig.reader.putParticipation(mkPart('inv', rig.uid, status: ParticipantStatus.invited));
      rig.functions.failNext(
        'respondChallengeInvite',
        AppException.fromCallable(code: 'failed-precondition', message: 'invite is no longer pending'),
      );
      await rig.pump(tester);
      await tester.tap(_segment('Buddy'));
      await settle(tester);
      await tester.tap(find.text('Decline'));
      await settle(tester);
      expect(find.text('invite is no longer pending'), findsOneWidget);
      expect(rig.functions.callsTo('respondChallengeInvite').single.params['accept'], false);
      // the invitation is still there (nothing was changed)
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('empty state, "Challenge a buddy" button opens the form, history lists completed duels',
        (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(
        challenges: [
          mkChallenge(id: 'old', type: ChallengeType.buddy, title: 'Last week duel', status: ChallengeStatus.completed, isTemplate: false),
        ],
        buddies: const [BuddySummary(uid: 'riya', displayName: 'Riya Verma')],
      );
      await rig.pump(tester);
      await tester.tap(_segment('Buddy'));
      await settle(tester);
      expect(find.text('No buddy challenges yet'), findsOneWidget);

      rig.reader.putParticipation(mkPart('old', rig.uid, status: ParticipantStatus.completed, progress: 20000));
      await settle(tester);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Last week duel'), findsOneWidget);
      expect(find.text('Completed'), findsWidgets);

      await tester.tap(find.text('Challenge a buddy'));
      await settle(tester);
      expect(find.text('Choose a buddy'), findsOneWidget);
      expect(find.text('Riya Verma'), findsOneWidget);
    });
  });

  group('challenge detail', () {
    testWidgets('join: calls joinChallenge, then shows my progress and Leave', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [
        mkChallenge(id: 'c1', title: 'Weekly 50k', description: 'Reach 50,000 verified steps within 7 days of joining.', rewardPoints: 60, participantCount: 3),
      ]);
      rig.functions
        ..on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []))
        ..on('joinChallenge', (_) {
          rig.reader.putParticipation(mkPart('c1', rig.uid, progress: 1200, windowStart: '20261113', windowEnd: '20261119'));
          return {'ok': true};
        });
      await rig.pump(tester, location: '/challenges/c1');

      expect(find.text('Weekly 50k'), findsOneWidget);
      expect(find.text('Reach 50,000 verified steps within 7 days of joining.'), findsOneWidget);
      expect(find.text('Walk 50,000 verified steps'), findsOneWidget);
      expect(find.text('7 days, starts the day you join'), findsOneWidget);
      expect(find.text('Completion reward: 60 points'), findsOneWidget);
      expect(find.text('3 participants'), findsOneWidget);
      expect(find.textContaining('Only verified steps count'), findsOneWidget);
      expect(find.text('My progress'), findsNothing);

      await tester.tap(find.text('Join challenge'));
      await settle(tester);
      expect(rig.functions.callsTo('joinChallenge').single.params, {'challengeId': 'c1'});
      expect(find.textContaining('You joined "Weekly 50k"'), findsOneWidget);
      expect(find.text('My progress'), findsOneWidget);
      expect(find.text('1,200 / 50,000 steps'), findsOneWidget);
      expect(find.text('2%'), findsOneWidget);
      expect(find.text('Ends in 6d 12h'), findsOneWidget);
      expect(find.text('Join challenge'), findsNothing);
      expect(find.text('Leave challenge'), findsOneWidget);
    });

    testWidgets('a server rejection is shown and the Join button stays available', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [mkChallenge(id: 'c1')]);
      rig.functions
        ..on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []))
        ..failNext('joinChallenge', AppException.fromCallable(code: 'resource-exhausted', message: 'challenge is full'));
      await rig.pump(tester, location: '/challenges/c1');
      await tester.tap(find.text('Join challenge'));
      await settle(tester);
      expect(find.text('challenge is full'), findsOneWidget);
      expect(find.text('Join challenge'), findsOneWidget);
    });

    testWidgets('leave asks for confirmation, then calls leaveChallenge', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [mkChallenge(id: 'c1', title: 'Weekly 50k')]);
      rig.reader.putParticipation(mkPart('c1', rig.uid, progress: 10, windowStart: '20261113', windowEnd: '20261119'));
      rig.functions
        ..on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []))
        ..on('leaveChallenge', (_) {
          rig.reader.putParticipation(mkPart('c1', rig.uid, status: ParticipantStatus.left));
          return {'ok': true};
        });
      await rig.pump(tester, location: '/challenges/c1');
      await tester.tap(find.text('Leave challenge'));
      await settle(tester);
      expect(find.text('Leave this challenge?'), findsOneWidget);

      await tester.tap(find.text('Stay'));
      await settle(tester);
      expect(rig.functions.callsTo('leaveChallenge'), isEmpty);

      await tester.tap(find.text('Leave challenge'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await settle(tester);
      expect(rig.functions.callsTo('leaveChallenge'), hasLength(1));
      expect(find.text('You left "Weekly 50k".'), findsOneWidget);
      expect(find.text('Join challenge'), findsOneWidget, reason: 'LEFT participations can join again');
    });

    testWidgets('inter-hostel: not eligible -> clear reason, no Join; competing hostels and rule are shown',
        (tester) async {
      useTallView(tester);
      final w = fixedWindow('20261115', 7);
      final rig = ChallengeRig.create(challenges: [
        mkChallenge(
          id: 'h1',
          type: ChallengeType.interHostel,
          title: 'Hostel Clash',
          status: ChallengeStatus.upcoming,
          windowMode: WindowMode.fixed,
          startAt: w.start,
          endAt: w.end,
          hostelIds: ['tejas', 'vyan'],
          isTemplate: false,
        ),
      ]);
      rig.functions.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      await rig.pump(tester, location: '/challenges/h1');
      expect(find.text('Join challenge'), findsNothing);
      expect(find.textContaining('Your hostel is not part of this competition'), findsOneWidget);
      expect(find.text('Hostels competing'), findsOneWidget);
      expect(find.text('Tejas Hall'), findsOneWidget);
      expect(find.text('Vyan Hall'), findsOneWidget);
      expect(find.text('Ranked by average verified steps per participant'), findsOneWidget);
      expect(find.text('Starts in 1d 12h'), findsOneWidget);
    });

    testWidgets('inter-hostel: eligible hostel can join and sees the hostel ranking table', (tester) async {
      useTallView(tester);
      final w = fixedWindow('20261110', 7);
      final rig = ChallengeRig.create(challenges: [
        mkChallenge(
          id: 'h1',
          type: ChallengeType.interHostel,
          title: 'Hostel Clash',
          windowMode: WindowMode.fixed,
          startAt: w.start,
          endAt: w.end,
          hostelIds: ['agira', 'tejas'],
          aggregation: HostelAggregation.total,
          isTemplate: false,
        ),
      ]);
      rig.functions.on(
        'getChallengeLeaderboard',
        (_) => leaderboardJson(
          entries: [
            {'rank': 1, 'hostelId': 'tejas', 'name': 'Tejas Hall', 'value': 30000, 'participants': 3, 'total': 30000, 'progressPct': 60},
            {'rank': 2, 'hostelId': 'agira', 'name': 'Agira Hall', 'value': 12000, 'participants': 1, 'total': 12000, 'progressPct': 24},
          ],
          rank: 2,
          value: 12000,
          metricLabel: 'Verified steps (hostel total)',
        ),
      );
      await rig.pump(tester, location: '/challenges/h1');
      expect(find.text('Join challenge'), findsOneWidget);
      expect(find.text('Hostel ranking'), findsOneWidget);
      expect(find.text('Verified steps (hostel total)'), findsOneWidget);
      expect(find.text('Ranked by total verified steps'), findsOneWidget);
      expect(find.byKey(const ValueKey('hostel-row-tejas')), findsOneWidget);
      expect(find.byKey(const ValueKey('hostel-row-agira')), findsOneWidget);
      expect(find.text('30,000'), findsOneWidget);
      expect(find.text('3 participants'), findsOneWidget);
      expect(find.text('Your hostel'), findsOneWidget, reason: 'my hostel row is highlighted');
    });

    testWidgets('leaderboard: highlights me, shows hostel names and my rank when outside the list',
        (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [mkChallenge(id: 'c1', title: 'Weekly 50k')]);
      rig.reader.putParticipation(mkPart('c1', rig.uid, progress: 400, windowStart: '20261113', windowEnd: '20261119'));
      rig.functions.on(
        'getChallengeLeaderboard',
        (_) => leaderboardJson(
          entries: [
            {'rank': 1, 'uid': 'riya', 'name': 'Riya Verma', 'hostelId': 'tejas', 'value': 9000, 'progressPct': 18},
            {'rank': 2, 'uid': 'kabir', 'name': 'Kabir Singh', 'hostelId': 'agira', 'value': 7000, 'progressPct': 14},
          ],
          rank: 57,
          value: 400,
        ),
      );
      await rig.pump(tester, location: '/challenges/c1');
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('Riya Verma'), findsOneWidget);
      expect(find.text('Tejas Hall'), findsOneWidget);
      expect(find.text('9,000 steps'), findsOneWidget);
      expect(find.text('18%'), findsOneWidget);
      expect(find.text('Your rank: 57'), findsOneWidget);
      expect(find.text('400 steps'), findsOneWidget);
    });

    testWidgets('leaderboard row of mine is marked "You"', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [mkChallenge(id: 'c1')]);
      rig.reader.putParticipation(mkPart('c1', rig.uid, progress: 7000, windowStart: '20261113', windowEnd: '20261119'));
      rig.functions.on(
        'getChallengeLeaderboard',
        (_) => leaderboardJson(
          entries: [
            {'rank': 1, 'uid': rig.uid, 'name': 'Aarav Sharma', 'hostelId': 'agira', 'value': 7000, 'progressPct': 14},
          ],
          rank: 1,
          value: 7000,
        ),
      );
      await rig.pump(tester, location: '/challenges/c1');
      expect(find.text('You'), findsOneWidget);
      expect(find.textContaining('Your rank'), findsNothing, reason: 'already visible in the list');
    });

    testWidgets('leaderboard failure shows an inline error with retry; the rest of the screen stays',
        (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: [mkChallenge(id: 'c1', title: 'Weekly 50k')]);
      rig.functions.failNext('getChallengeLeaderboard', AppException.fromCallable(code: 'unavailable'));
      await rig.pump(tester, location: '/challenges/c1');
      expect(find.text('Weekly 50k'), findsOneWidget);
      expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);

      rig.functions.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: [], metricLabel: 'Verified steps'));
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('No ranking yet'), findsOneWidget);
    });

    testWidgets('unavailable challenge shows an error instead of a blank screen', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create();
      await rig.pump(tester, location: '/challenges/missing');
      expect(find.text('This challenge is not available.'), findsOneWidget);
    });

    testWidgets('completed: results panel shows the winner, ranking and metric from the server', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(
        challenges: [
          mkChallenge(id: 'cam', type: ChallengeType.campus, title: 'Campus Step Week', status: ChallengeStatus.completed, isTemplate: false, participantCount: 2),
        ],
        results: {
          'cam': const ChallengeResult(
            challengeId: 'cam',
            type: ChallengeType.campus,
            winnerUid: 'riya',
            ranking: [
              RankedEntry(rank: 1, uid: 'riya', name: 'Riya Verma', value: 90000),
              RankedEntry(rank: 2, uid: 'kabir', name: 'Kabir Singh', value: 80000),
            ],
            participantCount: 2,
            metricLabel: 'Verified steps',
          ),
        },
      );
      rig.functions.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      await rig.pump(tester, location: '/challenges/cam');
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Final result'), findsOneWidget);
      expect(find.text('Riya Verma won'), findsOneWidget);
      expect(find.text('Kabir Singh'), findsOneWidget);
      expect(find.text('90,000 steps'), findsOneWidget);
      expect(find.text('Verified steps'), findsWidgets);
      expect(find.text('Join challenge'), findsNothing);
      expect(find.text('This challenge has finished.'), findsOneWidget);
    });

    testWidgets('completed without a stored result yet: says it is being prepared (never guesses)', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(
        challenges: [mkChallenge(id: 'cam', type: ChallengeType.campus, status: ChallengeStatus.completed, isTemplate: false)],
      );
      rig.functions.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      await rig.pump(tester, location: '/challenges/cam');
      expect(find.textContaining('final result is being prepared'), findsOneWidget);
      expect(find.textContaining(' won'), findsNothing);
    });

    testWidgets('buddy: waiting for the buddy (I created it)', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(challenges: []);
      rig.reader.putChallenge(mkChallenge(
        id: 'b',
        type: ChallengeType.buddy,
        status: ChallengeStatus.pending,
        title: 'Aarav vs Riya',
        target: 20000,
        durationDays: 3,
        isTemplate: false,
        createdBy: rig.uid,
      ));
      rig.reader.putParticipation(mkPart('b', rig.uid));
      await rig.pump(tester, location: '/challenges/b');
      expect(find.textContaining('Waiting for your buddy to accept'), findsOneWidget);
      expect(find.text('Join challenge'), findsNothing);
      expect(find.text('Leave challenge'), findsNothing);
    });

    testWidgets('buddy invitation on the detail screen: Accept calls the callable', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create();
      rig.reader.putChallenge(mkChallenge(
        id: 'b',
        type: ChallengeType.buddy,
        status: ChallengeStatus.pending,
        title: 'Riya vs Aarav',
        isTemplate: false,
        createdBy: 'riya',
      ));
      rig.reader.putParticipation(mkPart('b', rig.uid, status: ParticipantStatus.invited));
      rig.functions
        ..on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []))
        ..on('respondChallengeInvite', (_) {
          rig.reader.putChallenge(mkChallenge(id: 'b', type: ChallengeType.buddy, status: ChallengeStatus.upcoming, title: 'Riya vs Aarav', isTemplate: false));
          rig.reader.putParticipation(mkPart('b', rig.uid));
          return {'ok': true};
        });
      await rig.pump(tester, location: '/challenges/b');
      expect(find.text('You were challenged'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await settle(tester);
      expect(rig.functions.callsTo('respondChallengeInvite').single.params, {'challengeId': 'b', 'accept': true});
      expect(find.text('You were challenged'), findsNothing);
      expect(find.text('Upcoming'), findsWidgets);
    });

    testWidgets('buddy head to head: both competitors, my daily steps, and the winner after completion',
        (tester) async {
      useTallView(tester);
      final w = fixedWindow('20261111', 5);
      final fs = FakeFirestoreAccess(summaries: const [
        DailyStepSummary(dayKey: '20261111', verifiedSteps: 1500),
        DailyStepSummary(dayKey: '20261113', verifiedSteps: 3500),
      ]);
      final rig = ChallengeRig.create(firestore: fs);
      rig.reader.putChallenge(mkChallenge(
        id: 'b',
        type: ChallengeType.buddy,
        title: 'Aarav vs Riya',
        status: ChallengeStatus.completed,
        windowMode: WindowMode.fixed,
        startAt: w.start,
        endAt: w.end,
        target: 20000,
        isTemplate: false,
        winnerUid: 'riya',
      ));
      rig.reader.putParticipation(mkPart('b', rig.uid, status: ParticipantStatus.completed, progress: 5000));
      rig.reader.putResult(const ChallengeResult(
        challengeId: 'b',
        type: ChallengeType.buddy,
        winnerUid: 'riya',
        ranking: [
          RankedEntry(rank: 1, uid: 'riya', name: 'Riya Verma', value: 21000),
          RankedEntry(rank: 2, uid: 'me', name: 'Aarav Sharma', value: 5000),
        ],
        metricLabel: 'Verified steps',
      ));
      rig.functions.on(
        'getChallengeLeaderboard',
        (_) => leaderboardJson(entries: [
          {'rank': 1, 'uid': 'riya', 'name': 'Riya Verma', 'value': 21000, 'progressPct': 100},
          {'rank': 2, 'uid': rig.uid, 'name': 'Aarav Sharma', 'value': 5000, 'progressPct': 25},
        ]),
      );
      await rig.pump(tester, location: '/challenges/b');
      expect(find.text('Head to head'), findsOneWidget);
      expect(find.byKey(ValueKey('competitor-${rig.uid}')), findsOneWidget);
      expect(find.byKey(const ValueKey('competitor-riya')), findsOneWidget);
      expect(find.text('Aarav Sharma (you)'), findsOneWidget);
      expect(find.text('21,000'), findsOneWidget);
      expect(find.text('100% of target'), findsOneWidget);
      expect(find.text('25% of target'), findsOneWidget);
      expect(find.text('Your verified steps per day'), findsOneWidget);
      expect(find.text('Thu 12 Nov'), findsOneWidget);
      expect(find.text('3,500'), findsOneWidget);
      // winner comes from challengeResults
      expect(find.text('Riya Verma won'), findsOneWidget);
      expect(find.text('Leave challenge'), findsNothing);
    });

    testWidgets('buddy challenge with no winner explains that nobody reached the target', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create();
      rig.reader.putChallenge(mkChallenge(id: 'b', type: ChallengeType.buddy, status: ChallengeStatus.completed, isTemplate: false));
      rig.reader.putParticipation(mkPart('b', rig.uid, status: ParticipantStatus.joined, progress: 100));
      rig.reader.putResult(const ChallengeResult(challengeId: 'b', type: ChallengeType.buddy, ranking: []));
      rig.functions.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      await rig.pump(tester, location: '/challenges/b');
      expect(find.text('No winner - nobody reached the target.'), findsOneWidget);
    });
  });

  group('create buddy challenge', () {
    const riya = BuddySummary(uid: 'riya', displayName: 'Riya Verma');
    const kabir = BuddySummary(uid: 'kabir', displayName: 'Kabir Singh');

    testWidgets('explains the start rule, preselects ?buddy= and sends the form', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(buddies: const [riya, kabir]);
      rig.reader.putChallenge(mkChallenge(
        id: 'ch9',
        type: ChallengeType.buddy,
        status: ChallengeStatus.pending,
        title: 'Weekend walk-off',
        isTemplate: false,
        createdBy: rig.uid,
      ));
      rig.reader.putParticipation(mkPart('ch9', rig.uid));
      rig.functions.on('createBuddyChallenge', (_) => {'challengeId': 'ch9'});
      await rig.pump(tester, location: ChallengesRoutes.newBuddyFor('kabir'));

      expect(find.text('Challenge a buddy'), findsOneWidget, reason: 'the form, not a challenge called "new-buddy"');
      expect(find.textContaining('starts at the next midnight (IST) after they accept'), findsOneWidget);
      expect(find.text('Riya Verma'), findsOneWidget);
      expect(find.text('Kabir Singh'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'Kabir is preselected');

      await tester.enterText(find.byKey(const ValueKey('title-field')), 'Weekend walk-off');
      await tester.tap(find.byTooltip('One day more'));
      await tester.tap(find.byTooltip('One day more'));
      await tester.pump();
      expect(find.text('5 days'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('target-field')), '30000');
      await tester.pump();
      expect(find.textContaining('First to 30,000 verified steps within 5 days wins.'), findsOneWidget);
      await tester.tap(find.text('Send challenge'));
      await settle(tester);

      expect(rig.functions.callsTo('createBuddyChallenge').single.params, {
        'buddyUid': 'kabir',
        'title': 'Weekend walk-off',
        'durationDays': 5,
        'targetSteps': 30000,
      });
      // lands on the new challenge
      expect(find.textContaining('Waiting for your buddy to accept'), findsOneWidget);
      expect(find.textContaining('Invitation sent'), findsOneWidget);
    });

    testWidgets('validation: no buddy and a too-small target never reach the server', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(buddies: const [riya]);
      await rig.pump(tester, location: ChallengesRoutes.newBuddy);
      await tester.tap(find.text('Send challenge'));
      await settle(tester);
      expect(find.text('Choose a buddy to challenge'), findsOneWidget);

      await tester.tap(find.text('Riya Verma'));
      await tester.enterText(find.byKey(const ValueKey('target-field')), '500');
      await tester.pump();
      expect(find.text('At least 1,000 steps'), findsOneWidget);
      await tester.tap(find.text('Send challenge'));
      await settle(tester);
      expect(rig.functions.callsTo('createBuddyChallenge'), isEmpty);

      await tester.enterText(find.byKey(const ValueKey('target-field')), '');
      await tester.pump();
      expect(find.text('Enter the number of steps to reach'), findsOneWidget);
    });

    testWidgets('quick target chips fill the field', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(buddies: const [riya]);
      await rig.pump(tester, location: ChallengesRoutes.newBuddy);
      await tester.tap(find.widgetWithText(ActionChip, '50,000'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '50000'), findsOneWidget);
    });

    testWidgets('a server error (duplicate pending invite) is shown and the form stays', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(buddies: const [riya]);
      rig.functions.failNext(
        'createBuddyChallenge',
        AppException.fromCallable(code: 'already-exists', message: 'a pending challenge with this buddy already exists'),
      );
      await rig.pump(tester, location: ChallengesRoutes.newBuddyFor('riya'));
      await tester.tap(find.text('Send challenge'));
      await settle(tester);
      expect(find.text('a pending challenge with this buddy already exists'), findsOneWidget);
      expect(find.text('Send challenge'), findsOneWidget);
    });

    testWidgets('no buddies: explains and points to the buddy finder', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create();
      await rig.pump(tester, location: ChallengesRoutes.newBuddy);
      expect(find.text('No buddies yet'), findsOneWidget);
      expect(find.text('Find buddies'), findsOneWidget);
    });

    testWidgets('?buddy= of a non-buddy shows a notice and selects nobody', (tester) async {
      useTallView(tester);
      final rig = ChallengeRig.create(buddies: const [riya]);
      await rig.pump(tester, location: ChallengesRoutes.newBuddyFor('stranger'));
      expect(find.textContaining('not one of your buddies yet'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });
  });

  group('app wiring', () {
    testWidgets('the Challenges tab of the real app uses this feature (no placeholder)', (tester) async {
      useTallView(tester);
      final h = Harness.create(signedIn: true, withProfile: true);
      await h.pumpApp(tester, initialLocation: '/challenges');
      await settle(tester);
      expect(find.text('Coming in phase 6'), findsNothing);
      expect(find.text('Challenges'), findsWidgets);
      expect(find.text('No individual challenges yet'), findsOneWidget);
      for (final s in ['Individual', 'Buddy', 'Inter-Hostel', 'Campus', 'My challenges']) {
        expect(_segment(s), findsOneWidget, reason: s);
      }
    });

    testWidgets('registers Home campus-activity numbers from real participation / hostel data', (tester) async {
      useTallView(tester);
      final w = fixedWindow('20261115', 7);
      final rig = ChallengeRig.create(challenges: [
        mkChallenge(id: 'a1', status: ChallengeStatus.active),
        mkChallenge(id: 'a2', type: ChallengeType.campus, status: ChallengeStatus.active, isTemplate: false),
        mkChallenge(id: 'up', status: ChallengeStatus.upcoming, windowMode: WindowMode.fixed, startAt: w.start, endAt: w.end),
        mkChallenge(id: 'h1', type: ChallengeType.interHostel, status: ChallengeStatus.upcoming, hostelIds: ['agira'], isTemplate: false),
        mkChallenge(id: 'h2', type: ChallengeType.interHostel, status: ChallengeStatus.upcoming, hostelIds: ['tejas'], isTemplate: false),
      ]);
      rig.reader.setParticipations([
        mkPart('a1', rig.uid),
        mkPart('a2', rig.uid),
        mkPart('up', rig.uid),
      ]);
      await rig.pump(tester);
      final activity = await rig.deps.campusActivity.load(rig.uid);
      expect(activity.activeChallenges, 2);
      expect(activity.upcomingHostelCompetitions, 1, reason: 'only h1 includes my hostel (agira)');
    });

    test('registry slots exist for both numbers', () {
      expect(CampusSlot.values, containsAll([CampusSlot.activeChallenges, CampusSlot.upcomingHostelCompetitions]));
    });
  });
}
