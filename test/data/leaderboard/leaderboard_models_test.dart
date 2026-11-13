import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/leaderboard/leaderboard_models.dart';

const _campusWeekly = LeaderboardQuery(
  scope: LeaderboardScope.campus,
  period: LeaderboardPeriod.weekly,
);
const _hostelsAvg = LeaderboardQuery(
  scope: LeaderboardScope.hostels,
  period: LeaderboardPeriod.weekly,
);

void main() {
  group('LeaderboardQuery', () {
    test('params: hostelMetric only on the Hostels board', () {
      expect(_campusWeekly.toParams(limit: 50), {
        'scope': 'CAMPUS',
        'period': 'WEEKLY',
        'limit': 50,
      });
      expect(
        const LeaderboardQuery(
          scope: LeaderboardScope.hostels,
          period: LeaderboardPeriod.allTime,
          hostelMetric: HostelMetric.total,
        ).toParams(limit: 20),
        {'scope': 'HOSTELS', 'period': 'ALL_TIME', 'hostelMetric': 'TOTAL', 'limit': 20},
      );
    });

    test('equality ignores hostelMetric outside the Hostels board', () {
      const a = LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.daily);
      const b = LeaderboardQuery(
        scope: LeaderboardScope.campus,
        period: LeaderboardPeriod.daily,
        hostelMetric: HostelMetric.total,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        const LeaderboardQuery(scope: LeaderboardScope.hostels, period: LeaderboardPeriod.daily),
        isNot(const LeaderboardQuery(
          scope: LeaderboardScope.hostels,
          period: LeaderboardPeriod.daily,
          hostelMetric: HostelMetric.total,
        )),
      );
    });

    test('wire names match the callable contract', () {
      expect(LeaderboardScope.values.map((s) => s.wire),
          ['CAMPUS', 'MY_HOSTEL', 'HOSTELS', 'BUDDIES']);
      expect(LeaderboardPeriod.values.map((p) => p.wire),
          ['DAILY', 'WEEKLY', 'MONTHLY', 'ALL_TIME']);
      expect(HostelMetric.values.map((m) => m.wire), ['AVERAGE', 'TOTAL']);
    });
  });

  group('LeaderboardResult.fromMap', () {
    test('parses student rows, me, label, period key and updatedAt', () {
      final r = LeaderboardResult.fromMap({
        'entries': [
          {'rank': 1, 'uid': 'u1', 'name': 'Asha Rao', 'photoUrl': 'http://x/p.png', 'hostelId': 'agira', 'value': 21000},
          {'rank': 2, 'uid': 'u2', 'name': 'Bhavya', 'hostelId': null, 'value': 18000.0},
        ],
        'me': {'rank': 14, 'value': 9000},
        'metricLabel': 'Verified steps',
        'periodKey': '2026-W46',
        'updatedAt': 1794556800000,
      }, query: _campusWeekly);
      expect(r.entries, hasLength(2));
      final a = r.entries.first;
      expect([a.rank, a.id, a.name, a.photoUrl, a.hostelId, a.value, a.isHostel],
          [1, 'u1', 'Asha Rao', 'http://x/p.png', 'agira', 21000, false]);
      expect(r.entries[1].hostelId, isNull);
      expect(r.me!.rank, 14);
      expect(r.me!.value, 9000);
      expect(r.metricLabel, 'Verified steps');
      expect(r.periodKey, '2026-W46');
      expect(r.updatedAt, DateTime.fromMillisecondsSinceEpoch(1794556800000, isUtc: true));
      expect(r.leaderValue, 21000);
      expect(r.isEmpty, isFalse);
    });

    test('parses hostel rows with participants, total and average', () {
      final r = LeaderboardResult.fromMap({
        'entries': [
          {'rank': 1, 'hostelId': 'vyom', 'name': 'Vyom Hall', 'value': 4200, 'participants': 12, 'total': 50400, 'average': 4200},
        ],
      }, query: _hostelsAvg);
      final e = r.entries.single;
      expect(e.isHostel, isTrue);
      expect(e.id, 'vyom');
      expect(e.participants, 12);
      expect(e.total, 50400);
      expect(e.average, 4200);
    });

    test('hostel rows accept the Firestore field names', () {
      final r = LeaderboardResult.fromMap({
        'entries': [
          {'rank': 1, 'hostelId': 'ira', 'displayName': 'Ira Hall', 'value': 1, 'totalVerifiedSteps': 10, 'averagePerParticipant': 5},
        ],
      }, query: _hostelsAvg);
      final e = r.entries.single;
      expect([e.name, e.total, e.average], ['Ira Hall', 10, 5]);
    });

    test('is tolerant of missing optional fields and bad rows', () {
      final r = LeaderboardResult.fromMap({
        'entries': [
          'garbage',
          {'uid': 'u1', 'value': '1500'},
          {'rank': 0, 'uid': 'u2', 'name': '  ', 'value': null},
          null,
        ],
        'me': 'nope',
      }, query: _campusWeekly);
      expect(r.entries, hasLength(2));
      expect(r.entries[0].rank, 2, reason: 'fallback rank = position when rank missing');
      expect(r.entries[0].name, 'Student');
      expect(r.entries[0].value, 1500, reason: 'numeric strings are accepted');
      expect(r.entries[1].value, 0);
      expect(r.me, isNull);
      expect(r.metricLabel, isNull);
      expect(r.periodKey, isNull);
      expect(r.updatedAt, isNull);
    });

    test('missing/odd entries field gives an empty board', () {
      expect(LeaderboardResult.fromMap({}, query: _campusWeekly).isEmpty, isTrue);
      expect(LeaderboardResult.fromMap({'entries': 'x'}, query: _campusWeekly).isEmpty, isTrue);
      expect(LeaderboardResult.fromMap({}, query: _campusWeekly).leaderValue, 0);
    });

    test('entries are ordered by rank (server order kept for ties)', () {
      final r = LeaderboardResult.fromMap({
        'entries': [
          {'rank': 3, 'uid': 'c', 'name': 'C', 'value': 1},
          {'rank': 1, 'uid': 'a', 'name': 'A', 'value': 3},
          {'rank': 2, 'uid': 'b1', 'name': 'B1', 'value': 2},
          {'rank': 2, 'uid': 'b2', 'name': 'B2', 'value': 2},
        ],
      }, query: _campusWeekly);
      expect(r.entries.map((e) => e.id), ['a', 'b1', 'b2', 'c']);
    });

    test('me without a rank means "not ranked"', () {
      final r = LeaderboardResult.fromMap({
        'entries': const [],
        'me': {'rank': null, 'value': 0},
      }, query: _campusWeekly);
      expect(r.me, isNotNull);
      expect(r.me!.rank, isNull);
    });
  });

  group('parseServerTime', () {
    test('handles millis, seconds, ISO, timestamp maps and junk', () {
      final t = DateTime.utc(2026, 11, 13, 6, 30);
      expect(parseServerTime(t.millisecondsSinceEpoch), t);
      expect(parseServerTime(t.millisecondsSinceEpoch ~/ 1000), t);
      expect(parseServerTime(t.toIso8601String()), t);
      expect(parseServerTime({'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0}), t);
      expect(parseServerTime({'seconds': t.millisecondsSinceEpoch ~/ 1000}), t);
      expect(parseServerTime(t), t);
      expect(parseServerTime('not a date'), isNull);
      expect(parseServerTime(null), isNull);
      expect(parseServerTime({'x': 1}), isNull);
    });
  });
}
