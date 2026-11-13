import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/challenges/challenge_models.dart';
import 'package:stepup/features/challenges/challenge_logic.dart';

import 'challenge_test_support.dart';

void main() {
  group('plain-language text', () {
    test('target text for each metric (no raw enum names)', () {
      expect(
        targetText(mkChallenge(metric: ChallengeMetric.totalSteps, target: 50000)),
        'Walk 50,000 verified steps',
      );
      expect(
        targetText(mkChallenge(metric: ChallengeMetric.dailyTargetDays, target: 1, dailyTarget: 5000)),
        'Reach 5,000 verified steps in a day',
      );
      expect(
        targetText(mkChallenge(metric: ChallengeMetric.dailyTargetDays, target: 25, dailyTarget: 5000)),
        'Reach 5,000 verified steps on 25 days',
      );
      expect(
        targetText(mkChallenge(metric: ChallengeMetric.streakDays, target: 7, dailyTarget: 5000)),
        'Reach 5,000 verified steps every day for 7 days in a row',
      );
    });

    test('type and status labels', () {
      expect(typeLabel(ChallengeType.interHostel), 'Inter-Hostel');
      expect(typeLabel(ChallengeType.individual), 'Individual');
      expect(statusLabel(ChallengeStatus.pending), 'Waiting for buddy');
      expect(statusLabel(ChallengeStatus.active), 'Active');
      expect(statusLabel(ChallengeStatus.upcoming), 'Upcoming');
      expect(statusLabel(ChallengeStatus.completed), 'Completed');
      expect(statusLabel(ChallengeStatus.cancelled), 'Cancelled');
      expect(participantStatusLabel(ParticipantStatus.invited), 'Invited');
      expect(participantStatusLabel(ParticipantStatus.joined), 'Joined');
    });

    test('progress text per metric', () {
      expect(progressText(mkChallenge(target: 50000), 3200), '3,200 / 50,000 steps');
      expect(
        progressText(mkChallenge(metric: ChallengeMetric.dailyTargetDays, target: 25, dailyTarget: 5000), 2),
        '2 / 25 days',
      );
      expect(
        progressText(mkChallenge(metric: ChallengeMetric.streakDays, target: 7, dailyTarget: 5000), 3),
        '3 / 7 days in a row',
      );
    });

    test('hostel aggregation rule is stated clearly', () {
      expect(
        aggregationRule(mkChallenge(type: ChallengeType.interHostel)),
        'Ranked by average verified steps per participant',
      );
      expect(
        aggregationRule(mkChallenge(type: ChallengeType.interHostel, aggregation: HostelAggregation.total)),
        'Ranked by total verified steps',
      );
    });
  });

  group('progress percentage', () {
    test('floors and clamps to 0..100', () {
      expect(progressPercent(0, 100), 0);
      expect(progressPercent(1, 3), 33);
      expect(progressPercent(2, 3), 66);
      expect(progressPercent(996, 1000), 99, reason: '99.6 % must not read as complete');
      expect(progressPercent(1000, 1000), 100);
      expect(progressPercent(5000, 1000), 100);
      expect(progressPercent(-5, 1000), 0);
    });

    test('zero or negative target never divides by zero', () {
      expect(progressPercent(50, 0), 0);
      expect(progressFraction(50, 0), 0);
      expect(progressFraction(50, -1), 0);
    });

    test('fraction for the bar', () {
      expect(progressFraction(250, 1000), 0.25);
      expect(progressFraction(2000, 1000), 1);
      expect(progressFraction(0, 1000), 0);
    });
  });

  group('dates and countdown', () {
    test('duration formatting', () {
      expect(formatDuration(const Duration(days: 2, hours: 5, minutes: 9)), '2d 5h');
      expect(formatDuration(const Duration(hours: 5, minutes: 20)), '5h 20m');
      expect(formatDuration(const Duration(minutes: 12, seconds: 30)), '12m');
      expect(formatDuration(const Duration(seconds: 5)), '1m');
    });

    test('FIXED schedule shows IST dates (end day is inclusive)', () {
      final w = fixedWindow('20261114', 7);
      final c = mkChallenge(windowMode: WindowMode.fixed, startAt: w.start, endAt: w.end);
      expect(scheduleText(c), 'Sat 14 Nov to Fri 20 Nov');
      final one = fixedWindow('20261114', 1);
      expect(
        scheduleText(mkChallenge(windowMode: WindowMode.fixed, startAt: one.start, endAt: one.end)),
        'Sat 14 Nov',
      );
    });

    test('ROLLING and BUDDY schedules describe the duration', () {
      expect(scheduleText(mkChallenge(durationDays: 7)), '7 days, starts the day you join');
      expect(scheduleText(mkChallenge(durationDays: 1)), '1 day, starts the day you join');
      expect(
        scheduleText(mkChallenge(type: ChallengeType.buddy, status: ChallengeStatus.pending, durationDays: 3)),
        '3 days, starts at the next midnight (IST) after your buddy accepts',
      );
    });

    test('upcoming: starts in', () {
      final w = fixedWindow('20261115', 7); // starts Sun 15 Nov 00:00 IST = 14 Nov 18:30 UTC
      final c = mkChallenge(
        status: ChallengeStatus.upcoming,
        windowMode: WindowMode.fixed,
        startAt: w.start,
        endAt: w.end,
      );
      // now = 13 Nov 06:00 UTC -> start in 1d 12h 30m
      expect(countdownText(c, kNow), 'Starts in 1d 12h');
      expect(countdownText(c, w.start), 'Starting now');
    });

    test('active FIXED: ends in; after the end: waiting for the final result', () {
      final w = fixedWindow('20261110', 5); // ends 15 Nov 00:00 IST = 14 Nov 18:30 UTC
      final c = mkChallenge(windowMode: WindowMode.fixed, startAt: w.start, endAt: w.end);
      expect(countdownText(c, kNow), 'Ends in 1d 12h');
      expect(countdownText(c, w.end.add(const Duration(minutes: 1))), contains('final results are being calculated'));
    });

    test('active ROLLING counts down to the end of MY window', () {
      final c = mkChallenge(durationDays: 7);
      expect(countdownText(c, kNow), isNull, reason: 'not joined: no personal end');
      final mine = mkPart('c1', 'me', windowStart: '20261113', windowEnd: '20261119');
      // window ends at the end of 19 Nov IST = 19 Nov 18:30 UTC
      expect(countdownText(c, kNow, mine: mine), 'Ends in 6d 12h');
    });

    test('pending, completed and cancelled', () {
      expect(countdownText(mkChallenge(status: ChallengeStatus.pending), kNow), 'Starts after your buddy accepts');
      expect(countdownText(mkChallenge(status: ChallengeStatus.completed), kNow), 'Finished');
      expect(countdownText(mkChallenge(status: ChallengeStatus.cancelled), kNow), isNull);
    });
  });

  group('join decision', () {
    JoinDecision decide(Challenge c, {ChallengeParticipation? mine, String? hostel = 'agira'}) =>
        decideJoin(challenge: c, mine: mine, myHostelId: hostel, now: kNow);

    test('open rolling challenge can be joined', () {
      expect(decide(mkChallenge()).canJoin, isTrue);
    });

    test('already joined / completed', () {
      expect(decide(mkChallenge(), mine: mkPart('c1', 'me')).state, JoinState.joined);
      final done = decide(mkChallenge(), mine: mkPart('c1', 'me', status: ParticipantStatus.completed));
      expect(done.state, JoinState.completed);
      expect(done.reason, isNotNull);
    });

    test('a participation that LEFT can join again', () {
      expect(decide(mkChallenge(), mine: mkPart('c1', 'me', status: ParticipantStatus.left)).canJoin, isTrue);
    });

    test('buddy challenges are invite-only', () {
      final d = decide(mkChallenge(type: ChallengeType.buddy, status: ChallengeStatus.upcoming));
      expect(d.state, JoinState.inviteOnly);
      expect(d.reason, contains('invitation'));
    });

    test('completed / cancelled / pending are not open', () {
      expect(decide(mkChallenge(status: ChallengeStatus.completed)).state, JoinState.ended);
      expect(decide(mkChallenge(status: ChallengeStatus.cancelled)).state, JoinState.notOpen);
      expect(decide(mkChallenge(status: ChallengeStatus.pending)).state, JoinState.notOpen);
    });

    test('rolling challenges are only joinable while ACTIVE', () {
      expect(decide(mkChallenge(status: ChallengeStatus.upcoming)).state, JoinState.notOpen);
    });

    test('FIXED upcoming can be joined; FIXED past its end cannot', () {
      final future = fixedWindow('20261115', 7);
      expect(
        decide(mkChallenge(
          type: ChallengeType.campus,
          status: ChallengeStatus.upcoming,
          windowMode: WindowMode.fixed,
          startAt: future.start,
          endAt: future.end,
        )).canJoin,
        isTrue,
      );
      final past = fixedWindow('20261101', 3);
      expect(
        decide(mkChallenge(
          type: ChallengeType.campus,
          windowMode: WindowMode.fixed,
          startAt: past.start,
          endAt: past.end,
        )).state,
        JoinState.ended,
      );
    });

    test('inter-hostel: only competing hostels may join, with a clear reason', () {
      final c = mkChallenge(
        type: ChallengeType.interHostel,
        status: ChallengeStatus.upcoming,
        windowMode: WindowMode.fixed,
        startAt: fixedWindow('20261115', 7).start,
        endAt: fixedWindow('20261115', 7).end,
        hostelIds: ['tejas', 'vyan'],
      );
      final no = decide(c);
      expect(no.state, JoinState.hostelNotEligible);
      expect(no.reason, contains('Your hostel is not part of this competition'));
      expect(decide(c, hostel: 'tejas').canJoin, isTrue);
      expect(decide(c, hostel: null).state, JoinState.hostelNotEligible);
    });

    test('full challenge', () {
      final d = decide(mkChallenge(maxParticipants: 5, participantCount: 5));
      expect(d.state, JoinState.full);
    });

    test('leaving: own JOINED participation of an open non-buddy challenge only', () {
      final c = mkChallenge();
      expect(canLeave(c, mkPart('c1', 'me')), isTrue);
      expect(canLeave(c, null), isFalse);
      expect(canLeave(c, mkPart('c1', 'me', status: ParticipantStatus.completed)), isFalse);
      expect(canLeave(c, mkPart('c1', 'me', status: ParticipantStatus.left)), isFalse);
      expect(canLeave(mkChallenge(status: ChallengeStatus.completed), mkPart('c1', 'me')), isFalse);
      expect(
        canLeave(mkChallenge(type: ChallengeType.buddy, status: ChallengeStatus.active), mkPart('c1', 'me')),
        isFalse,
      );
    });
  });

  group('winner text (only from the server result)', () {
    ChallengeResult res({String? uid, String? hostel}) => ChallengeResult(
          challengeId: 'c',
          type: ChallengeType.campus,
          winnerUid: uid,
          winnerHostelId: hostel,
          ranking: [
            if (uid != null) RankedEntry(rank: 1, uid: uid, name: 'Riya', value: 10),
            if (hostel != null) RankedEntry(rank: 1, hostelId: hostel, name: 'Tejas Hall', value: 10),
          ],
        );

    test('someone else won / I won / my hostel won / nobody won', () {
      expect(winnerText(res(uid: 'u2'), myUid: 'me', myHostelId: 'agira'), 'Riya won');
      expect(winnerText(res(uid: 'me'), myUid: 'me', myHostelId: 'agira'), 'You won!');
      expect(winnerText(res(hostel: 'tejas'), myUid: 'me', myHostelId: 'agira'), 'Tejas Hall won');
      expect(winnerText(res(hostel: 'tejas'), myUid: 'me', myHostelId: 'tejas'), 'Tejas Hall won - your hostel!');
      expect(winnerText(res(), myUid: 'me', myHostelId: 'agira'), 'No winner for this challenge');
    });
  });
}
