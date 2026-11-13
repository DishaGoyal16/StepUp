import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/firestore/firebase_firestore_access.dart';
import 'package:stepup/domain/campus_activity.dart';
import 'package:stepup/domain/daily_step_summary.dart';
import 'package:stepup/domain/day_key.dart';
import 'package:stepup/domain/profile_draft.dart';
import 'package:stepup/domain/profile_enums.dart';
import 'package:stepup/domain/step_models.dart';
import 'package:stepup/domain/user_profile.dart';

void main() {
  group('DailyStepSummary.fromMap (summary mapping)', () {
    test('maps every field', () {
      final s = DailyStepSummary.fromMap({
        'uid': 'u1',
        'dayKey': '20261112',
        'hostelId': 'agira',
        'rawSteps': 9000,
        'verifiedSteps': 7500.0, // numbers may arrive as double
        'rejectedSteps': 1000,
        'unwitnessedSteps': 500,
        'pendingSteps': 0,
        'updatedAt': 'ignored',
      });
      expect(s.uid, 'u1');
      expect(s.dayKey, '20261112');
      expect(s.hostelId, 'agira');
      expect(s.rawSteps, 9000);
      expect(s.verifiedSteps, 7500);
      expect(s.rejectedSteps, 1000);
      expect(s.unwitnessedSteps, 500);
      expect(s.pendingSteps, 0);
    });

    test('missing fields default to zero, never throw', () {
      final s = DailyStepSummary.fromMap({'dayKey': '20261101'});
      expect(s.verifiedSteps, 0);
      expect(s.rawSteps, 0);
      expect(s.hostelId, isNull);
    });
  });

  group('DayKey (IST)', () {
    test('of: 18:29 UTC is still the same IST day, 18:30 UTC is the next', () {
      expect(DayKey.of(DateTime.utc(2026, 11, 13, 18, 29, 59)), '20261113');
      expect(DayKey.of(DateTime.utc(2026, 11, 13, 18, 30)), '20261114');
      expect(DayKey.of(DateTime.utc(2026, 11, 13, 0, 0)), '20261113');
    });

    test('boundsMs covers exactly 24 h from IST midnight', () {
      final b = DayKey.boundsMs(DateTime.utc(2026, 11, 13, 6));
      expect(b.startMs, DateTime.utc(2026, 11, 12, 18, 30).millisecondsSinceEpoch);
      expect(b.endMs - b.startMs, const Duration(days: 1).inMilliseconds);
    });

    test('parse/of round trip and weekday label', () {
      final t = DayKey.parse('20261113');
      expect(DayKey.of(t), '20261113');
      expect(DayKey.label('20261113'), 'Fri 13 Nov');
      expect(DayKey.weekdayShort('20261114'), 'Sat');
      expect(() => DayKey.parse('2026-11-13'), throwsFormatException);
    });

    test('lastDays is oldest first and ends with today, across month edges', () {
      final days = DayKey.lastDays(DateTime.utc(2026, 12, 2, 6), 4);
      expect(days, ['20261129', '20261130', '20261201', '20261202']);
      expect(DayKey.lastDays(DateTime.utc(2026, 11, 13, 6), 7).length, 7);
    });
  });

  group('UserProfile.fromMap', () {
    test('maps the users/{uid} document', () {
      final p = UserProfile.fromMap('u1', {
        'displayName': 'Aarav Kumar Sharma',
        'email': 'aarav@thapar.edu',
        'hostelId': 'vasudha-e',
        'block': 'E',
        'fitnessLevel': 'ADVANCED',
        'sportsInterests': ['Cricket', 'Gym', 7],
        'preferredActivity': 'Gym',
        'preferredTime': 'EVENING',
        'buddyType': 'GROUP',
        'bio': 'hi',
        'dailyGoal': 12000,
        'currentStreak': 5,
        'bestStreak': 9,
        'lifetimeVerifiedSteps': 123456,
        'pointsBalance': 100,
        'pointsReserved': 20,
        'status': 'ACTIVE',
        'role': 'admin',
        'privacy': {'discoverable': true, 'showHostel': false},
        'createdAt': DateTime.utc(2026, 11, 1),
      });
      expect(p.uid, 'u1');
      expect(p.fitnessLevel, FitnessLevel.advanced);
      expect(p.preferredTime, PreferredTime.evening);
      expect(p.buddyType, BuddyType.group);
      expect(p.sportsInterests, ['Cricket', 'Gym']);
      expect(p.dailyGoal, 12000);
      expect(p.currentStreak, 5);
      expect(p.isAdmin, isTrue);
      expect(p.privacy['showHostel'], isFalse);
      expect(p.createdAt, DateTime.utc(2026, 11, 1));
      expect(p.firstName, 'Aarav');
      expect(p.initials, 'AS');
    });

    test('defaults for a sparse document', () {
      final p = UserProfile.fromMap('u2', const {});
      expect(p.dailyGoal, kDefaultDailyGoal);
      expect(p.role, 'student');
      expect(p.isAdmin, isFalse);
      expect(p.firstName, 'there');
      expect(p.initials, '?');
    });
  });

  test('convertFirestoreValue turns Timestamps into UTC DateTimes (recursively)', () {
    final ts = Timestamp.fromDate(DateTime.utc(2026, 11, 13, 6));
    final out = convertFirestoreValue({
      'createdAt': ts,
      'nested': {'t': ts},
      'list': [ts, 1],
    }) as Map;
    expect(out['createdAt'], DateTime.utc(2026, 11, 13, 6));
    expect((out['nested'] as Map)['t'], DateTime.utc(2026, 11, 13, 6));
    expect((out['list'] as List).first, DateTime.utc(2026, 11, 13, 6));
  });

  group('engine channel models', () {
    test('TodaySummary.fromMap', () {
      final t = TodaySummary.fromMap({
        'raw': 100, 'verified': 80, 'pending': 5, 'rejected': 10,
        'suspicious': 4, 'unwitnessed': 3, 'gap': 2,
      });
      expect([t.raw, t.verified, t.pending, t.rejected, t.suspicious, t.unwitnessed, t.gap],
          [100, 80, 5, 10, 4, 3, 2]);
    });

    test('EngineBucket.fromMap tolerates int64 and missing optional fields', () {
      final b = EngineBucket.fromMap({
        'startMs': 1763000000000,
        'bootCount': 2,
        'rawDelta': 30,
        'credited': 25,
        'state': 'PARTIAL',
        'reason': null,
        'walkFraction': 1, // int where a double is expected
        'hops': [
          {'label': 'WALK', 'imuSteps': 14},
          {'label': 'STILL', 'imuSteps': 0},
        ],
        'lateRawAdded': 0,
        'lateCreditedAdded': 0,
      });
      expect(b.startMs, 1763000000000);
      expect(b.walkFraction, 1.0);
      expect(b.hops.length, 2);
      expect(b.toSyncJson()['lateRawAdded'], 0, reason: 'late fields are passed through');
      expect(b.toSyncJson()['lateCreditedAdded'], 0);
    });

    test('LiveSnapshot.fromMap', () {
      final s = LiveSnapshot.fromMap({
        'tracking': true, 'raw': 10, 'verified': 8, 'pending': 1,
        'rejected': 1, 'suspicious': 0, 'liveLabel': 'Walking',
      });
      expect(s.tracking, isTrue);
      expect(s.liveLabel, 'Walking');
    });
  });

  group('SyncResponse.ackable', () {
    const sent = [1, 2, 3, 4];

    test('lists: accepted + duplicates + rejected only', () {
      final r = SyncResponse.fromMap({
        'accepted': [1],
        'duplicates': [2],
        'rejected': [
          {'startMs': 3, 'reason': 'X'},
        ],
      });
      expect(r.ackable(sent), {1, 2, 3});
    });

    test('counts that add up to the batch size ack everything', () {
      final r = SyncResponse.fromMap({'accepted': 3, 'duplicates': 1, 'rejected': []});
      expect(r.ackable(sent), {1, 2, 3, 4});
    });

    test('counts that do not add up ack only the rejected ones', () {
      final r = SyncResponse.fromMap({
        'accepted': 1,
        'duplicates': 0,
        'rejected': [
          {'startMs': 4, 'reason': 'X'},
        ],
      });
      expect(r.ackable(sent), {4});
    });

    test('empty response acks nothing', () {
      expect(SyncResponse.fromMap(const {}).ackable(sent), isEmpty);
    });

    test('accepted may be a list of {startMs} maps', () {
      final r = SyncResponse.fromMap({
        'accepted': [
          {'startMs': 1},
        ],
        'duplicates': <int>[],
        'rejected': [],
      });
      expect(r.ackable(sent), {1});
    });
  });

  group('ProfileDraft', () {
    ProfileDraft complete() => const ProfileDraft(
          displayName: 'Aarav',
          hostelId: 'agira',
          fitnessLevel: FitnessLevel.beginner,
          sportsInterests: ['Running'],
          preferredActivity: 'Running',
          preferredTime: PreferredTime.morning,
          buddyType: BuddyType.both,
        );

    test('isComplete', () {
      expect(complete().isComplete, isTrue);
      expect(const ProfileDraft().isComplete, isFalse);
      expect(complete().copyWith(hostelId: null).isComplete, isFalse);
      expect(complete().copyWith(sportsInterests: const []).isComplete, isFalse);
      expect(complete().copyWith(bio: 'x' * 161).isComplete, isFalse);
    });

    test('JSON round trip keeps everything', () {
      final d = complete().copyWith(block: 'E', bio: 'hello', photoLocalPath: '/tmp/a.jpg');
      final back = ProfileDraft.fromJson(d.toJson());
      expect(back.toJson(), d.toJson());
      expect(back.fitnessLevel, FitnessLevel.beginner);
    });

    test('callable payload uses wire values and omits empty optional fields', () {
      final p = complete().toCallablePayload();
      expect(p['fitnessLevel'], 'BEGINNER');
      expect(p['preferredTime'], 'MORNING');
      expect(p['buddyType'], 'BOTH');
      expect(p.containsKey('block'), isFalse);
      expect(p.containsKey('photoUrl'), isFalse);
      final q = complete().copyWith(block: ' E ').toCallablePayload(photoUrl: 'https://x/y.jpg');
      expect(q['block'], 'E');
      expect(q['photoUrl'], 'https://x/y.jpg');
    });
  });

  group('CampusActivityRegistry', () {
    test('empty source returns an all-null activity', () async {
      final a = await const EmptyCampusActivitySource().load('u');
      expect(a.activeChallenges, isNull);
      expect(a.myLeaderboardRank, isNull);
    });

    test('registered loaders fill their slot; failures leave it empty', () async {
      final r = CampusActivityRegistry()
        ..register(CampusSlot.activeChallenges, (uid) async => 3)
        ..register(CampusSlot.buddiesAvailable, (uid) async => throw StateError('x'))
        ..register(CampusSlot.myLeaderboardRank, (uid) async => 12);
      final a = await r.load('u1');
      expect(a.activeChallenges, 3);
      expect(a.buddiesAvailable, isNull);
      expect(a.myLeaderboardRank, 12);
      expect(a.upcomingHostelCompetitions, isNull);
    });
  });
}
