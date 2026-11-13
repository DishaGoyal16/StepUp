import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/profile_extras/badges.dart';
import 'package:stepup/data/profile_extras/campus_rank_reader.dart';
import 'package:stepup/data/profile_extras/extras_models.dart';
import 'package:stepup/data/profile_extras/profile_extras_reader.dart';

void main() {
  group('buildBadgeCatalogue', () {
    test('without a document: the six known badges in order', () {
      final c = buildBadgeCatalogue(null);
      expect(c.map((b) => b.id).toList(), [
        'FIRST_1K',
        'TEN_K_WALKER',
        'STREAK_7',
        'CHALLENGE_CHAMPION',
        'HOSTEL_CHAMPION',
        'CAMPUS_FITNESS_STAR',
      ]);
      expect(c.map((b) => b.title).toList(), [
        'First 1K',
        '10K Walker',
        '7-Day Streak',
        'Challenge Champion',
        'Hostel Champion',
        'Campus Fitness Star',
      ]);
      expect(c.every((b) => b.howToEarn.isNotEmpty), isTrue);
    });

    test('the adminSettings/badges document overrides fields; non-map values are ignored', () {
      final c = buildBadgeCatalogue({
        'FIRST_1K': {
          'title': 'Thousand!',
          'description': 'Walk 1,000 steps.',
          'icon': 'star',
          'rule': 'lifetimeVerifiedSteps >= 1000',
          'points': 15,
        },
        'updatedAt': 12345,
        'MARATHONER': {'title': 'Marathoner', 'description': 'Walk a lot.', 'icon': 'directions_walk'},
      });
      final first = c.first;
      expect(first.title, 'Thousand!');
      expect(first.description, 'Walk 1,000 steps.');
      expect(first.points, 15);
      expect(c.last.id, 'MARATHONER', reason: 'badge only present in the document is appended');
      expect(c.last.title, 'Marathoner');
      expect(c.any((b) => b.id == 'updatedAt'), isFalse);
      expect(c, hasLength(7));
    });

    test('a partial entry keeps the default for missing fields', () {
      final c = buildBadgeCatalogue({
        'STREAK_7': {'points': 5},
      });
      final s = c.firstWhere((b) => b.id == 'STREAK_7');
      expect(s.title, '7-Day Streak');
      expect(s.points, 5);
    });
  });

  group('mergeBadgeStatus', () {
    final catalogue = buildBadgeCatalogue(null);

    test('earned badges come first and are marked earned; the rest stay locked', () {
      final merged = mergeBadgeStatus(catalogue, [
        Achievement(badgeId: 'STREAK_7', awardedAt: DateTime.utc(2026, 11, 1)),
        const Achievement(badgeId: 'FIRST_1K'),
      ]);
      expect(merged.where((b) => b.earned).map((b) => b.definition.id).toList(), ['FIRST_1K', 'STREAK_7']);
      expect(merged.take(2).every((b) => b.earned), isTrue);
      expect(merged.skip(2).every((b) => !b.earned), isTrue);
      expect(merged, hasLength(6));
      expect(merged[1].awardedAt, DateTime.utc(2026, 11, 1));
    });

    test('no achievements: everything locked', () {
      final merged = mergeBadgeStatus(catalogue, const []);
      expect(merged.every((b) => !b.earned), isTrue);
    });

    test('an achievement missing from the catalogue is still listed as earned', () {
      final merged = mergeBadgeStatus(catalogue, const [Achievement(badgeId: 'NEW_BADGE_X')]);
      expect(merged.first.earned, isTrue);
      expect(merged.first.definition.title, 'New Badge X');
      expect(merged, hasLength(7));
    });
  });

  group('model parsing', () {
    test('Achievement.fromMap reads awardedAt as DateTime or millis', () {
      final a = Achievement.fromMap({'badgeId': 'FIRST_1K', 'awardedAt': 1700000000000, 'refId': '20261101'});
      expect(a.badgeId, 'FIRST_1K');
      expect(a.awardedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
      expect(a.refId, '20261101');
    });

    test('LedgerEntry labels', () {
      expect(LedgerEntry.fromMap('x', {'delta': 50, 'type': 'BET_WIN'}).label, 'Bet won');
      expect(LedgerEntry.fromMap('x', {'delta': -20, 'type': 'RESERVE'}).label, 'Stake reserved');
      expect(LedgerEntry.fromMap('x', {'delta': 1, 'type': 'ZZZ'}).label, 'Points');
    });
  });

  group('CampusRankReader', () {
    test('calls getLeaderboard CAMPUS/WEEKLY and returns me.rank', () async {
      final fn = FakeFunctionsClient()
        ..on('getLeaderboard', (_) => {
              'entries': <Object>[],
              'me': {'rank': 7, 'value': 4200},
            });
      final r = await CampusRankReader(fn).fetchWeekly();
      expect(r?.rank, 7);
      expect(r?.value, 4200);
      expect(fn.calls.single.name, 'getLeaderboard');
      expect(fn.calls.single.params['scope'], 'CAMPUS');
      expect(fn.calls.single.params['period'], 'WEEKLY');
    });

    test('null when the user is not on the board', () async {
      final fn = FakeFunctionsClient()
        ..on('getLeaderboard', (_) => {'entries': <Object>[], 'me': null});
      expect(await CampusRankReader(fn).fetchWeekly(), isNull);
      fn.on('getLeaderboard', (_) => {'me': {'rank': 0, 'value': 0}});
      expect(await CampusRankReader(fn).fetchWeekly(), isNull);
    });

    test('propagates AppException so the caller can tolerate it', () async {
      final fn = FakeFunctionsClient()
        ..failNext('getLeaderboard', AppException.fromCallable(code: 'unavailable'));
      expect(CampusRankReader(fn).fetchWeekly(), throwsA(isA<AppException>()));
    });
  });

  group('FakeProfileExtrasReader', () {
    test('streams achievements and updates', () async {
      final r = FakeProfileExtrasReader(achievements: const [Achievement(badgeId: 'FIRST_1K')]);
      final seen = <int>[];
      final sub = r.watchAchievements('u').listen((l) => seen.add(l.length));
      await Future<void>.delayed(Duration.zero);
      r.setAchievements(const [Achievement(badgeId: 'FIRST_1K'), Achievement(badgeId: 'STREAK_7')]);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [1, 2]);
      await sub.cancel();
    });

    test('errors are surfaced per source', () async {
      final r = FakeProfileExtrasReader()
        ..ledgerError = StateError('x')
        ..catalogueError = StateError('y');
      expect(r.fetchRecentLedger('u'), throwsStateError);
      expect(r.fetchBadgeCatalogue(), throwsStateError);
      r.completedError = StateError('z');
      expect(r.watchCompletedChallenges('u'), emitsError(isA<StateError>()));
    });
  });
}
