import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/core/utils/clock.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/challenges/challenge_models.dart';
import 'package:stepup/data/challenges/challenge_repository.dart';
import 'package:stepup/data/challenges/fake_challenge_reader.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/domain/daily_step_summary.dart';
import 'package:stepup/domain/hostel.dart';
import 'package:stepup/domain/hostel_seed.dart';
import 'package:stepup/features/challenges/challenge_detail_view_model.dart';
import 'package:stepup/features/challenges/challenges_view_model.dart';
import 'package:stepup/features/challenges/create_buddy_view_model.dart';

import 'challenge_test_support.dart';

const _me = 'me';

class _Env {
  _Env({
    List<Challenge> challenges = const [],
    List<ChallengeParticipation> parts = const [],
    Map<String, ChallengeResult> results = const {},
    List<BuddySummary> buddyList = const [],
  })  : reader = FakeChallengeReader(challenges: challenges, participations: parts, results: results),
        fn = FakeFunctionsClient(),
        buddies = FakeBuddyDirectory(buddyList) {
    repo = ChallengeRepository(reader: reader, functions: fn, buddies: buddies);
  }

  final FakeChallengeReader reader;
  final FakeFunctionsClient fn;
  final FakeBuddyDirectory buddies;
  late final ChallengeRepository repo;
}

void main() {
  group('ChallengesViewModel', () {
    test('individual catalogue loads from the reader and is ordered easiest first', () async {
      final env = _Env(challenges: [
        mkChallenge(id: 'big', title: '100,000 Steps Weekly', target: 100000, durationDays: 7),
        mkChallenge(id: 'd5', title: '5,000 Steps Daily', metric: ChallengeMetric.dailyTargetDays, target: 1, dailyTarget: 5000, durationDays: 1),
        mkChallenge(id: 'mid', title: '50,000 Steps Weekly', target: 50000, durationDays: 7),
        mkChallenge(id: 'fit', title: '30-Day Fitness Challenge', metric: ChallengeMetric.dailyTargetDays, target: 25, dailyTarget: 5000, durationDays: 30),
      ]);
      final vm = ChallengesViewModel(repository: env.repo, uid: _me)..start();
      expect(vm.open(ChallengeType.individual).loading, isTrue);
      await pumpEventQueue();
      expect(vm.individualCatalogue.map((c) => c.id), ['d5', 'mid', 'big', 'fit']);
      vm.dispose();
    });

    test('segments load lazily and are cached', () async {
      final env = _Env(challenges: [
        mkChallenge(id: 'cam', type: ChallengeType.campus, status: ChallengeStatus.upcoming, isTemplate: false),
      ]);
      final vm = ChallengesViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      expect(env.reader.openFetchCount, 1, reason: 'only the individual segment so far');
      vm.selectSegment(ChallengeSegment.campus);
      await pumpEventQueue();
      expect(env.reader.openFetchCount, 2);
      vm.selectSegment(ChallengeSegment.individual);
      vm.selectSegment(ChallengeSegment.campus);
      await pumpEventQueue();
      expect(env.reader.openFetchCount, 2, reason: 'cached, no refetch');
      expect(vm.competitions(ChallengeType.campus).single.id, 'cam');
      // buddy / mine segments never run an open-challenge query
      vm.selectSegment(ChallengeSegment.buddy);
      vm.selectSegment(ChallengeSegment.mine);
      await pumpEventQueue();
      expect(env.reader.openFetchCount, 2);
      vm.dispose();
    });

    test('running competitions are listed before upcoming ones', () async {
      final a = fixedWindow('20261120', 7);
      final b = fixedWindow('20261110', 7);
      final env = _Env(challenges: [
        mkChallenge(id: 'up', type: ChallengeType.interHostel, status: ChallengeStatus.upcoming, windowMode: WindowMode.fixed, startAt: a.start, endAt: a.end, isTemplate: false),
        mkChallenge(id: 'live', type: ChallengeType.interHostel, windowMode: WindowMode.fixed, startAt: b.start, endAt: b.end, isTemplate: false),
      ]);
      final vm = ChallengesViewModel(repository: env.repo, uid: _me, initial: ChallengeSegment.interHostel)..start();
      await pumpEventQueue();
      expect(vm.competitions(ChallengeType.interHostel).map((c) => c.id), ['live', 'up']);
      vm.dispose();
    });

    test('my progress is live from the participation stream', () async {
      final env = _Env(
        challenges: [mkChallenge(id: 'c1')],
        parts: [mkPart('c1', _me, progress: 100)],
      );
      final vm = ChallengesViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      expect(vm.progressOf('c1')!.progress, 100);
      env.reader.putParticipation(mkPart('c1', _me, progress: 2500));
      await pumpEventQueue();
      expect(vm.progressOf('c1')!.progress, 2500);
      expect(vm.progressOf('other'), isNull);
      env.reader.putParticipation(mkPart('c1', _me, status: ParticipantStatus.left));
      await pumpEventQueue();
      expect(vm.progressOf('c1'), isNull, reason: 'LEFT has no progress to show');
      vm.dispose();
    });

    test('buddy segment classifies invitations, sent, active and history', () async {
      final env = _Env(
        challenges: [
          mkChallenge(id: 'inv', type: ChallengeType.buddy, status: ChallengeStatus.pending, title: 'Invite', isTemplate: false, createdBy: 'b'),
          mkChallenge(id: 'sent', type: ChallengeType.buddy, status: ChallengeStatus.pending, title: 'Sent', isTemplate: false, createdBy: _me),
          mkChallenge(id: 'live', type: ChallengeType.buddy, status: ChallengeStatus.active, title: 'Live', isTemplate: false),
          mkChallenge(id: 'soon', type: ChallengeType.buddy, status: ChallengeStatus.upcoming, title: 'Soon', isTemplate: false),
          mkChallenge(id: 'old', type: ChallengeType.buddy, status: ChallengeStatus.completed, title: 'Old', isTemplate: false),
          mkChallenge(id: 'no', type: ChallengeType.buddy, status: ChallengeStatus.cancelled, title: 'Declined', isTemplate: false),
          mkChallenge(id: 'solo', status: ChallengeStatus.active, title: 'Solo'),
        ],
        parts: [
          mkPart('inv', _me, status: ParticipantStatus.invited),
          mkPart('sent', _me),
          mkPart('live', _me, progress: 10),
          mkPart('soon', _me),
          mkPart('old', _me, status: ParticipantStatus.completed, progress: 50),
          mkPart('no', _me, status: ParticipantStatus.left),
          mkPart('solo', _me, progress: 3),
        ],
      );
      final vm = ChallengesViewModel(repository: env.repo, uid: _me, initial: ChallengeSegment.buddy)..start();
      await pumpEventQueue();
      expect(vm.invitations.map((e) => e.challenge.id), ['inv']);
      expect(vm.sentInvitations.map((e) => e.challenge.id), ['sent']);
      expect(vm.activeBuddyChallenges.map((e) => e.challenge.id), ['live', 'soon']);
      expect(vm.buddyHistory.map((e) => e.challenge.id), ['no', 'old']);
      // "My challenges": everything joined/completed that is not pending/cancelled; running first
      expect(vm.myChallenges.map((e) => e.challenge.id), ['live', 'solo', 'soon', 'old']);
      vm.dispose();
    });

    test('respondToInvite calls the callable once even with double taps, then refreshes status', () async {
      final env = _Env(
        challenges: [mkChallenge(id: 'inv', type: ChallengeType.buddy, status: ChallengeStatus.pending, isTemplate: false, createdBy: 'b')],
        parts: [mkPart('inv', _me, status: ParticipantStatus.invited)],
      );
      env.fn.on('respondChallengeInvite', (_) {
        // the server accepts: challenge becomes UPCOMING, my participation JOINED
        env.reader.putChallenge(mkChallenge(id: 'inv', type: ChallengeType.buddy, status: ChallengeStatus.upcoming, isTemplate: false));
        env.reader.putParticipation(mkPart('inv', _me));
        return {'ok': true};
      });
      final vm = ChallengesViewModel(repository: env.repo, uid: _me, initial: ChallengeSegment.buddy)..start();
      await pumpEventQueue();
      expect(vm.invitations, hasLength(1));

      final first = vm.respondToInvite('inv', accept: true);
      final second = await vm.respondToInvite('inv', accept: true);
      expect(second.ok, isTrue);
      expect(second.message, isNull, reason: 'duplicate tap is ignored silently');
      final r = await first;
      await pumpEventQueue();
      expect(r.ok, isTrue);
      expect(r.message, contains('starts at the next midnight'));
      expect(env.fn.callsTo('respondChallengeInvite'), hasLength(1));
      expect(vm.invitations, isEmpty);
      expect(vm.activeBuddyChallenges.single.challenge.id, 'inv');
      vm.dispose();
    });

    test('declining reports the server error message', () async {
      final env = _Env(
        challenges: [mkChallenge(id: 'inv', type: ChallengeType.buddy, status: ChallengeStatus.pending, isTemplate: false)],
        parts: [mkPart('inv', _me, status: ParticipantStatus.invited)],
      );
      env.fn.failNext(
        'respondChallengeInvite',
        AppException.fromCallable(code: 'failed-precondition', message: 'invite is no longer pending'),
      );
      final vm = ChallengesViewModel(repository: env.repo, uid: _me, initial: ChallengeSegment.buddy)..start();
      await pumpEventQueue();
      final r = await vm.respondToInvite('inv', accept: false);
      expect(r.ok, isFalse);
      expect(r.message, 'invite is no longer pending');
      expect(vm.isBusy('inv'), isFalse, reason: 'busy flag is released after a failure');
      vm.dispose();
    });

    test('offline: first load fails with a friendly message, retry recovers', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')]);
      env.reader.offline = true;
      final vm = ChallengesViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      expect(vm.open(ChallengeType.individual).error, contains('Network problem'));
      env.reader.offline = false;
      final r = await vm.refresh();
      expect(r.ok, isTrue);
      expect(vm.open(ChallengeType.individual).data!.single.id, 'c1');
      vm.dispose();
    });

    test('offline refresh keeps the stale list and reports the error', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')]);
      final vm = ChallengesViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      env.reader.offline = true;
      final r = await vm.refresh();
      expect(r.ok, isFalse);
      expect(vm.individualCatalogue, hasLength(1), reason: 'stale data stays visible');
      vm.dispose();
    });
  });

  group('ChallengeDetailViewModel', () {
    ChallengeDetailViewModel detail(_Env env, String id, {String? hostel = 'agira', List<DailyStepSummary> daily = const []}) =>
        ChallengeDetailViewModel(
          repository: env.repo,
          challengeId: id,
          uid: _me,
          myHostelId: hostel,
          clock: FakeClock(kNow),
          loadHostels: () async => const HostelDirectory(hostels: hostelSeed, isFallback: true),
          watchDailySummaries: (_) => Stream.value(daily),
        );

    test('unknown challenge id -> not available', () async {
      final env = _Env();
      final vm = detail(env, 'nope')..start();
      await pumpEventQueue();
      expect(vm.challenge.error, 'This challenge is not available.');
      vm.dispose();
    });

    test('offline load fails with a retryable error; refresh recovers', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')]);
      env.reader.offline = true;
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      expect(vm.challenge.error, isNotNull);
      env.reader.offline = false;
      env.fn.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      await vm.refresh();
      expect(vm.challengeOrNull!.id, 'c1');
      vm.dispose();
    });

    test('loads the leaderboard through the callable and exposes my rank', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')], parts: [mkPart('c1', _me, progress: 40)]);
      env.fn.on(
        'getChallengeLeaderboard',
        (_) => leaderboardJson(
          entries: [
            {'rank': 1, 'uid': 'x', 'name': 'Riya', 'value': 900, 'progressPct': 2},
          ],
          rank: 57,
          value: 40,
        ),
      );
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      expect(env.fn.callsTo('getChallengeLeaderboard').single.params['challengeId'], 'c1');
      expect(vm.leaderboard.data!.myRank, 57);
      expect(vm.myProgress, 40);
      expect(vm.myPercent, 0);
      vm.dispose();
    });

    test('a leaderboard failure does not break the screen', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')]);
      env.fn.failNext('getChallengeLeaderboard', AppException.fromCallable(code: 'unavailable'));
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      expect(vm.challenge.hasData, isTrue);
      expect(vm.leaderboard.error, contains('Network problem'));
      env.fn.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      await vm.reloadLeaderboard();
      expect(vm.leaderboard.hasData, isTrue);
      vm.dispose();
    });

    test('pending buddy challenges do not request a leaderboard', () async {
      final env = _Env(
        challenges: [mkChallenge(id: 'b', type: ChallengeType.buddy, status: ChallengeStatus.pending, isTemplate: false, createdBy: _me)],
        parts: [mkPart('b', _me)],
      );
      final vm = detail(env, 'b')..start();
      await pumpEventQueue();
      expect(env.fn.callsTo('getChallengeLeaderboard'), isEmpty);
      expect(vm.waitingForBuddy, isTrue);
      expect(vm.hasInviteForMe, isFalse);
      expect(vm.showLeaderboard, isFalse);
      vm.dispose();
    });

    test('join: calls the callable once (double tap guarded), then reloads', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1', title: 'Weekly 50k')]);
      env.fn
        ..on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []))
        ..on('joinChallenge', (_) {
          env.reader.putParticipation(mkPart('c1', _me, windowStart: '20261113', windowEnd: '20261119'));
          env.reader.putChallenge(mkChallenge(id: 'c1', title: 'Weekly 50k', participantCount: 1));
          return {'ok': true};
        });
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      expect(vm.joinDecision!.canJoin, isTrue);
      final first = vm.join();
      final second = await vm.join();
      expect(second.message, isNull);
      final r = await first;
      await pumpEventQueue();
      expect(r.ok, isTrue);
      expect(r.message, contains('Only verified steps count'));
      expect(env.fn.callsTo('joinChallenge'), hasLength(1));
      expect(vm.mine!.isJoined, isTrue);
      expect(vm.challengeOrNull!.participantCount, 1);
      expect(vm.canLeaveChallenge, isTrue);
      expect(vm.countdown, 'Ends in 6d 12h');
      expect(vm.busy, isFalse);
      vm.dispose();
    });

    test('join is blocked client-side with a clear reason when my hostel is not competing', () async {
      final w = fixedWindow('20261115', 7);
      final env = _Env(challenges: [
        mkChallenge(
          id: 'h1',
          type: ChallengeType.interHostel,
          status: ChallengeStatus.upcoming,
          windowMode: WindowMode.fixed,
          startAt: w.start,
          endAt: w.end,
          hostelIds: ['tejas', 'vyan'],
          isTemplate: false,
        ),
      ]);
      env.fn.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      final vm = detail(env, 'h1')..start();
      await pumpEventQueue();
      final r = await vm.join();
      expect(r.ok, isFalse);
      expect(r.message, contains('Your hostel is not part of this competition'));
      expect(env.fn.callsTo('joinChallenge'), isEmpty);
      expect(vm.competingHostels.map((h) => h.name), ['Tejas Hall', 'Vyan Hall']);
      expect(vm.competingHostels.any((h) => h.isMine), isFalse);
      vm.dispose();
    });

    test('server rejection of a join is reported and busy is released', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')]);
      env.fn
        ..on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []))
        ..failNext('joinChallenge', AppException.fromCallable(code: 'resource-exhausted', message: 'challenge is full'));
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      final r = await vm.join();
      expect(r.ok, isFalse);
      expect(r.message, 'challenge is full');
      expect(vm.busy, isFalse);
      vm.dispose();
    });

    test('leave calls leaveChallenge; buddy challenges cannot be left', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')], parts: [mkPart('c1', _me)]);
      env.fn
        ..on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []))
        ..on('leaveChallenge', (_) {
          env.reader.putParticipation(mkPart('c1', _me, status: ParticipantStatus.left));
          return {'ok': true};
        });
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      expect(vm.canLeaveChallenge, isTrue);
      final r = await vm.leave();
      await pumpEventQueue();
      expect(r.ok, isTrue);
      expect(env.fn.callsTo('leaveChallenge'), hasLength(1));
      expect(vm.canLeaveChallenge, isFalse);
      vm.dispose();

      final env2 = _Env(
        challenges: [mkChallenge(id: 'b', type: ChallengeType.buddy, status: ChallengeStatus.active, isTemplate: false)],
        parts: [mkPart('b', _me)],
      );
      env2.fn.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      final vm2 = detail(env2, 'b')..start();
      await pumpEventQueue();
      expect((await vm2.leave()).ok, isFalse);
      expect(env2.fn.callsTo('leaveChallenge'), isEmpty);
      vm2.dispose();
    });

    test('live progress: a changed participant document refreshes the ranking quietly', () async {
      final env = _Env(challenges: [mkChallenge(id: 'c1')], parts: [mkPart('c1', _me, progress: 100)]);
      env.fn.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      expect(env.fn.callsTo('getChallengeLeaderboard'), hasLength(1));
      env.reader.putParticipation(mkPart('c1', _me, progress: 900));
      await pumpEventQueue();
      expect(vm.myProgress, 900);
      expect(env.fn.callsTo('getChallengeLeaderboard'), hasLength(2));
      // same progress again: no extra call
      env.reader.putParticipation(mkPart('c1', _me, progress: 900));
      await pumpEventQueue();
      expect(env.fn.callsTo('getChallengeLeaderboard'), hasLength(2));
      vm.dispose();
    });

    test('completed challenges load the server result; the client never computes a winner', () async {
      final env = _Env(
        challenges: [mkChallenge(id: 'c1', type: ChallengeType.campus, status: ChallengeStatus.completed, isTemplate: false)],
        results: {
          'c1': const ChallengeResult(
            challengeId: 'c1',
            type: ChallengeType.campus,
            winnerUid: 'riya',
            ranking: [RankedEntry(rank: 1, uid: 'riya', name: 'Riya', value: 9000)],
            metricLabel: 'Verified steps',
          ),
        },
      );
      env.fn.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      final vm = detail(env, 'c1')..start();
      await pumpEventQueue();
      expect(vm.result!.winnerName, 'Riya');
      vm.dispose();
    });

    test('buddy: me first in head-to-head and my daily steps inside the window', () async {
      final w = fixedWindow('20261111', 5); // 11..15 Nov; today is 13 Nov
      final env = _Env(
        challenges: [
          mkChallenge(id: 'b', type: ChallengeType.buddy, status: ChallengeStatus.active, windowMode: WindowMode.fixed, startAt: w.start, endAt: w.end, target: 20000, isTemplate: false),
        ],
        parts: [mkPart('b', _me, progress: 5000)],
      );
      env.fn.on(
        'getChallengeLeaderboard',
        (_) => leaderboardJson(entries: [
          {'rank': 1, 'uid': 'buddy', 'name': 'Riya', 'value': 6000, 'progressPct': 30},
          {'rank': 2, 'uid': _me, 'name': 'Me', 'value': 5000, 'progressPct': 25},
        ]),
      );
      final vm = detail(env, 'b', daily: const [
        DailyStepSummary(dayKey: '20261111', verifiedSteps: 1500),
        DailyStepSummary(dayKey: '20261113', verifiedSteps: 3500),
        DailyStepSummary(dayKey: '20261101', verifiedSteps: 9999),
      ])..start();
      await pumpEventQueue();
      expect(vm.buddyRows.map((r) => r.id), [_me, 'buddy']);
      final rows = vm.myDailyRows;
      expect(rows.map((r) => r.dayKey), ['20261111', '20261112', '20261113'], reason: 'future days are not listed');
      expect(rows.map((r) => r.verified), [1500, 0, 3500]);
      vm.dispose();
    });

    test('buddy invitation: respond accepts through the callable', () async {
      final env = _Env(
        challenges: [mkChallenge(id: 'b', type: ChallengeType.buddy, status: ChallengeStatus.pending, isTemplate: false, createdBy: 'riya')],
        parts: [mkPart('b', _me, status: ParticipantStatus.invited)],
      );
      env.fn.on('respondChallengeInvite', (_) {
        env.reader.putChallenge(mkChallenge(id: 'b', type: ChallengeType.buddy, status: ChallengeStatus.upcoming, isTemplate: false));
        env.reader.putParticipation(mkPart('b', _me));
        return {'ok': true};
      });
      env.fn.on('getChallengeLeaderboard', (_) => leaderboardJson(entries: []));
      final vm = detail(env, 'b')..start();
      await pumpEventQueue();
      expect(vm.hasInviteForMe, isTrue);
      final r = await vm.respond(accept: true);
      await pumpEventQueue();
      expect(r.ok, isTrue);
      expect(env.fn.callsTo('respondChallengeInvite').single.params, {'challengeId': 'b', 'accept': true});
      expect(vm.hasInviteForMe, isFalse);
      expect(vm.challengeOrNull!.status, ChallengeStatus.upcoming);
      vm.dispose();
    });
  });

  group('CreateBuddyChallengeViewModel', () {
    const riya = BuddySummary(uid: 'riya', displayName: 'Riya Verma');
    const kabir = BuddySummary(uid: 'kabir', displayName: 'Kabir Singh');

    test('target parsing and validation', () {
      expect(CreateBuddyChallengeViewModel.parseTarget('20,000'), 20000);
      expect(CreateBuddyChallengeViewModel.parseTarget(' 5000 '), 5000);
      expect(CreateBuddyChallengeViewModel.parseTarget(''), isNull);
      expect(CreateBuddyChallengeViewModel.parseTarget('abc'), isNull);
      expect(CreateBuddyChallengeViewModel.validateTarget(null), isNotNull);
      expect(CreateBuddyChallengeViewModel.validateTarget(999), 'At least 1,000 steps');
      expect(CreateBuddyChallengeViewModel.validateTarget(1000), isNull);
      expect(CreateBuddyChallengeViewModel.validateTarget(1000000), isNull);
      expect(CreateBuddyChallengeViewModel.validateTarget(1000001), 'At most 1,000,000 steps');
    });

    test('duration is clamped to 1..30', () {
      final env = _Env();
      final vm = CreateBuddyChallengeViewModel(repository: env.repo, uid: _me);
      vm.setDuration(0);
      expect(vm.durationDays, 1);
      vm.setDuration(99);
      expect(vm.durationDays, 30);
      vm.setDuration(12);
      expect(vm.durationDays, 12);
      vm.dispose();
    });

    test('?buddy= preselects an accepted buddy; a stranger shows a notice', () async {
      final env = _Env(buddyList: [riya, kabir]);
      final vm = CreateBuddyChallengeViewModel(repository: env.repo, uid: _me, initialBuddyUid: 'kabir')..start();
      await pumpEventQueue();
      expect(vm.selectedBuddyUid, 'kabir');
      expect(vm.selectedBuddy!.displayName, 'Kabir Singh');
      expect(vm.initialNotice, isNull);
      vm.dispose();

      final vm2 = CreateBuddyChallengeViewModel(repository: env.repo, uid: _me, initialBuddyUid: 'stranger')..start();
      await pumpEventQueue();
      expect(vm2.selectedBuddyUid, isNull);
      expect(vm2.initialNotice, contains('not one of your buddies'));
      vm2.dispose();
    });

    test('a buddy removed meanwhile is deselected', () async {
      final env = _Env(buddyList: [riya]);
      final vm = CreateBuddyChallengeViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      vm.selectBuddy('riya');
      env.buddies.setBuddies([]);
      await pumpEventQueue();
      expect(vm.selectedBuddyUid, isNull);
      vm.dispose();
    });

    test('submit without a buddy / with a bad target does not call the server', () async {
      final env = _Env(buddyList: [riya]);
      final vm = CreateBuddyChallengeViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      var out = await vm.submit();
      expect(out.result.ok, isFalse);
      expect(vm.buddyError, 'Choose a buddy to challenge');
      vm.selectBuddy('riya');
      vm.setTargetText('500');
      out = await vm.submit();
      expect(out.result.ok, isFalse);
      expect(vm.targetError, 'At least 1,000 steps');
      expect(env.fn.calls, isEmpty);
      vm.dispose();
    });

    test('submit sends the form once and returns the new challenge id', () async {
      final env = _Env(buddyList: [riya]);
      env.fn.on('createBuddyChallenge', (_) => {'challengeId': 'ch9'});
      final vm = CreateBuddyChallengeViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      vm
        ..selectBuddy('riya')
        ..setTitle('Weekend walk-off')
        ..setDuration(5)
        ..setTargetText('30000');
      final first = vm.submit();
      final dup = await vm.submit();
      expect(dup.challengeId, isNull, reason: 'second tap while submitting is ignored');
      final out = await first;
      expect(out.challengeId, 'ch9');
      expect(out.result.message, contains('next midnight (IST)'));
      expect(env.fn.callsTo('createBuddyChallenge'), hasLength(1));
      expect(env.fn.calls.single.params, {
        'buddyUid': 'riya',
        'title': 'Weekend walk-off',
        'durationDays': 5,
        'targetSteps': 30000,
      });
      expect(vm.submitting, isFalse);
      vm.dispose();
    });

    test('server error (e.g. pending invite exists) is shown and the form stays usable', () async {
      final env = _Env(buddyList: [riya]);
      env.fn.failNext(
        'createBuddyChallenge',
        AppException.fromCallable(code: 'already-exists', message: 'a pending challenge with this buddy already exists'),
      );
      final vm = CreateBuddyChallengeViewModel(repository: env.repo, uid: _me)..start();
      await pumpEventQueue();
      vm.selectBuddy('riya');
      final out = await vm.submit();
      expect(out.challengeId, isNull);
      expect(out.result.message, 'a pending challenge with this buddy already exists');
      expect(vm.submitting, isFalse);
      vm.dispose();
    });
  });
}
