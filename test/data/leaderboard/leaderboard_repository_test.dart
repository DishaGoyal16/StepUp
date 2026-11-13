import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/leaderboard/leaderboard_models.dart';
import 'package:stepup/data/leaderboard/leaderboard_repository.dart';

void main() {
  late FakeFunctionsClient fn;
  late CallableLeaderboardRepository repo;

  setUp(() {
    fn = FakeFunctionsClient();
    repo = CallableLeaderboardRepository(fn);
  });

  test('calls getLeaderboard with scope/period/limit and parses the answer', () async {
    fn.on('getLeaderboard', (_) => {
          'entries': [
            {'rank': 1, 'uid': 'u1', 'name': 'Asha', 'value': 100},
          ],
          'me': {'rank': 1, 'value': 100},
          'metricLabel': 'Verified steps',
          'periodKey': '20261113',
          'updatedAt': 1794556800000,
        });
    final r = await repo.load(
      const LeaderboardQuery(scope: LeaderboardScope.myHostel, period: LeaderboardPeriod.daily),
      limit: 25,
    );
    final c = fn.callsTo('getLeaderboard').single;
    expect(c.params, {'scope': 'MY_HOSTEL', 'period': 'DAILY', 'limit': 25});
    expect(r.entries.single.name, 'Asha');
    expect(r.me!.rank, 1);
    expect(r.metricLabel, 'Verified steps');
    expect(r.periodKey, '20261113');
    expect(r.query.scope, LeaderboardScope.myHostel);
  });

  test('sends hostelMetric only for the Hostels board', () async {
    fn.on('getLeaderboard', (_) => {'entries': <Object>[]});
    await repo.load(const LeaderboardQuery(
      scope: LeaderboardScope.hostels,
      period: LeaderboardPeriod.monthly,
      hostelMetric: HostelMetric.total,
    ));
    await repo.load(const LeaderboardQuery(
      scope: LeaderboardScope.buddies,
      period: LeaderboardPeriod.monthly,
      hostelMetric: HostelMetric.total,
    ));
    final calls = fn.callsTo('getLeaderboard').toList();
    expect(calls[0].params['hostelMetric'], 'TOTAL');
    expect(calls[0].params['limit'], LeaderboardRepository.defaultLimit);
    expect(calls[1].params.containsKey('hostelMetric'), isFalse);
  });

  test('server AppException is rethrown unchanged', () async {
    final err = AppException.fromCallable(code: 'permission-denied', message: 'Not allowed here');
    fn.failNext('getLeaderboard', err);
    await expectLater(
      repo.load(const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.weekly)),
      throwsA(same(err)),
    );
  });

  test('any other failure is wrapped as AppException (the only error type)', () async {
    fn.failNext('getLeaderboard', StateError('boom'));
    await expectLater(
      repo.load(const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.weekly)),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'unavailable')),
    );
  });

  group('myWeeklyCampusRank', () {
    test('asks for the WEEKLY CAMPUS board and returns me.rank', () async {
      fn.on('getLeaderboard', (_) => {
            'entries': <Object>[],
            'me': {'rank': 7, 'value': 12345},
          });
      expect(await repo.myWeeklyCampusRank(), 7);
      final p = fn.callsTo('getLeaderboard').single.params;
      expect(p['scope'], 'CAMPUS');
      expect(p['period'], 'WEEKLY');
    });

    test('null when unranked', () async {
      fn.on('getLeaderboard', (_) => {'entries': <Object>[], 'me': {'rank': null, 'value': 0}});
      expect(await repo.myWeeklyCampusRank(), isNull);
    });

    test('null when me is missing', () async {
      fn.on('getLeaderboard', (_) => {'entries': <Object>[]});
      expect(await repo.myWeeklyCampusRank(), isNull);
    });

    test('null on error', () async {
      fn.failNext('getLeaderboard', AppException.fromCallable(code: 'unavailable'));
      expect(await repo.myWeeklyCampusRank(), isNull);
    });
  });
}
