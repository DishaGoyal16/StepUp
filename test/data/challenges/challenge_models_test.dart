import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/challenges/challenge_models.dart';

void main() {
  group('Challenge.tryFromMap', () {
    test('parses a Firestore INDIVIDUAL template', () {
      final c = Challenge.tryFromMap('tpl_steps-50k-weekly', {
        'type': 'INDIVIDUAL',
        'title': '50,000 Steps Weekly',
        'description': 'Reach 50,000 verified steps within 7 days of joining.',
        'metric': 'TOTAL_STEPS',
        'target': 50000,
        'dailyTarget': null,
        'windowMode': 'ROLLING',
        'startAt': null,
        'endAt': null,
        'durationDays': 7,
        'status': 'ACTIVE',
        'createdBy': 'system',
        'hostelIds': <String>[],
        'hostelAggregation': 'AVERAGE_PER_PARTICIPANT',
        'maxParticipants': null,
        'participantCount': 12,
        'rewardPoints': 60,
        'isTemplate': true,
      })!;
      expect(c.id, 'tpl_steps-50k-weekly');
      expect(c.type, ChallengeType.individual);
      expect(c.metric, ChallengeMetric.totalSteps);
      expect(c.status, ChallengeStatus.active);
      expect(c.isRolling, isTrue);
      expect(c.target, 50000);
      expect(c.dailyTarget, isNull);
      expect(c.durationDays, 7);
      expect(c.participantCount, 12);
      expect(c.rewardPoints, 60);
      expect(c.isTemplate, isTrue);
      expect(c.isFull, isFalse);
    });

    test('parses dates (DateTime or epoch millis) and hostel fields', () {
      final c = Challenge.tryFromMap('h1', {
        'type': 'INTER_HOSTEL',
        'title': 'Hostel Clash',
        'metric': 'TOTAL_STEPS',
        'target': 50000,
        'windowMode': 'FIXED',
        'startAt': DateTime.utc(2026, 11, 14, 18, 30),
        'endAt': DateTime.utc(2026, 11, 20, 18, 30).millisecondsSinceEpoch,
        'status': 'UPCOMING',
        'hostelIds': ['agira', 'tejas'],
        'hostelAggregation': 'TOTAL',
        'maxParticipants': 10,
        'participantCount': 10,
      })!;
      expect(c.startAt, DateTime.utc(2026, 11, 14, 18, 30));
      expect(c.endAt, DateTime.utc(2026, 11, 20, 18, 30));
      expect(c.isRolling, isFalse);
      expect(c.hostelIds, ['agira', 'tejas']);
      expect(c.hostelAggregation, HostelAggregation.total);
      expect(c.isFull, isTrue);
    });

    test('unknown type / metric / status is skipped instead of crashing', () {
      expect(Challenge.tryFromMap('x', {'type': 'WEIRD', 'metric': 'TOTAL_STEPS', 'status': 'ACTIVE'}), isNull);
      expect(Challenge.tryFromMap('x', {'type': 'CAMPUS', 'metric': 'NOPE', 'status': 'ACTIVE'}), isNull);
      expect(Challenge.tryFromMap('x', {'type': 'CAMPUS', 'metric': 'TOTAL_STEPS', 'status': 'LIVE'}), isNull);
    });

    test('missing title falls back to a generic one; BUDDY participantUids are read', () {
      final c = Challenge.tryFromMap('b', {
        'type': 'BUDDY',
        'metric': 'TOTAL_STEPS',
        'status': 'PENDING',
        'target': 20000,
        'participantUids': ['a', 'b'],
      })!;
      expect(c.title, 'Challenge');
      expect(c.participantUids, ['a', 'b']);
      expect(c.status.isOpen, isFalse);
    });

    test('difficultyKey orders the catalogue by window then size', () {
      Challenge mk(ChallengeMetric m, int target, int? daily, int days) => Challenge(
            id: '$m$target',
            type: ChallengeType.individual,
            title: 't',
            metric: m,
            target: target,
            dailyTarget: daily,
            status: ChallengeStatus.active,
            durationDays: days,
          );
      final keys = [
        mk(ChallengeMetric.dailyTargetDays, 1, 5000, 1),
        mk(ChallengeMetric.dailyTargetDays, 1, 10000, 1),
        mk(ChallengeMetric.streakDays, 7, 5000, 7),
        mk(ChallengeMetric.totalSteps, 50000, null, 7),
        mk(ChallengeMetric.totalSteps, 100000, null, 7),
        mk(ChallengeMetric.dailyTargetDays, 25, 5000, 30),
      ].map((c) => c.difficultyKey).toList();
      expect([...keys]..sort(), keys, reason: 'already in the intended order');
    });
  });

  group('ChallengeParticipation.tryFromMap', () {
    test('parses a participant document', () {
      final p = ChallengeParticipation.tryFromMap({
        'challengeId': 'c1',
        'uid': 'u1',
        'displayName': 'Aarav',
        'status': 'JOINED',
        'progress': 1234,
        'windowStart': '20261113',
        'windowEnd': '20261119',
        'rewardPaid': false,
      })!;
      expect(p.status, ParticipantStatus.joined);
      expect(p.progress, 1234);
      expect(p.windowEnd, '20261119');
      expect(p.hasProgress, isTrue);
      expect(p.isCompleted, isFalse);
    });

    test('INVITED has no progress; bad documents are skipped', () {
      final p = ChallengeParticipation.tryFromMap(
          {'challengeId': 'c', 'uid': 'u', 'status': 'INVITED'})!;
      expect(p.hasProgress, isFalse);
      expect(ChallengeParticipation.tryFromMap({'uid': 'u', 'status': 'JOINED'}), isNull);
      expect(ChallengeParticipation.tryFromMap({'challengeId': 'c', 'uid': 'u', 'status': 'X'}), isNull);
    });
  });

  group('leaderboard + result', () {
    test('student rows and hostel rows are told apart', () {
      final lb = ChallengeLeaderboard.fromMap({
        'entries': [
          {'rank': 1, 'uid': 'u1', 'name': 'Aarav', 'photoUrl': null, 'hostelId': 'agira', 'value': 5000, 'progressPct': 50},
          {'rank': 1, 'hostelId': 'tejas', 'name': 'Tejas Hall', 'value': 4200, 'participants': 3, 'total': 12600, 'progressPct': 120},
        ],
        'me': {'rank': 7, 'value': 900},
        'metricLabel': 'Verified steps (average per participant)',
      });
      expect(lb.entries[0].isHostel, isFalse);
      expect(lb.entries[0].id, 'u1');
      expect(lb.entries[0].hostelId, 'agira');
      expect(lb.entries[1].isHostel, isTrue);
      expect(lb.entries[1].id, 'tejas');
      expect(lb.entries[1].participants, 3);
      expect(lb.entries[1].progressPct, 100, reason: 'clamped to 0..100');
      expect(lb.myRank, 7);
      expect(lb.myValue, 900);
      expect(lb.metricLabel, contains('average per participant'));
    });

    test('me.rank may be null (not participating)', () {
      final lb = ChallengeLeaderboard.fromMap({
        'entries': <Object>[],
        'me': {'rank': null, 'value': 0},
        'metricLabel': 'x',
      });
      expect(lb.myRank, isNull);
      expect(lb.entries, isEmpty);
    });

    test('ChallengeResult winner name comes from the stored ranking', () {
      final r = ChallengeResult.tryFromMap('c1', {
        'type': 'CAMPUS',
        'winnerUid': 'u2',
        'winnerHostelId': null,
        'ranking': [
          {'rank': 1, 'uid': 'u2', 'name': 'Riya', 'value': 9000},
          {'rank': 2, 'uid': 'u1', 'name': 'Aarav', 'value': 8000},
        ],
        'participantCount': 2,
        'metricLabel': 'Verified steps',
      })!;
      expect(r.hasWinner, isTrue);
      expect(r.winnerName, 'Riya');
      expect(r.type, ChallengeType.campus);
      expect(r.ranking, hasLength(2));
    });

    test('result without a winner', () {
      final r = ChallengeResult.tryFromMap('c1', {'type': 'BUDDY', 'ranking': <Object>[]})!;
      expect(r.hasWinner, isFalse);
      expect(r.winnerName, isNull);
    });

    test('hostel winner resolves the hostel name', () {
      final r = ChallengeResult.tryFromMap('h', {
        'type': 'INTER_HOSTEL',
        'winnerHostelId': 'tejas',
        'ranking': [
          {'rank': 1, 'hostelId': 'tejas', 'name': 'Tejas Hall', 'value': 5000},
        ],
      })!;
      expect(r.winnerName, 'Tejas Hall');
    });
  });
}
