import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/leaderboard/fake_leaderboard_repository.dart';
import 'package:stepup/data/leaderboard/leaderboard_models.dart';
import 'package:stepup/domain/hostel.dart';
import 'package:stepup/features/leaderboard/leaderboard_view_model.dart';

LeaderboardEntry student(int rank, String uid, {num value = 1000, String? hostelId}) =>
    LeaderboardEntry(rank: rank, id: uid, name: 'S$rank', value: value, hostelId: hostelId);

LeaderboardResult board(
  LeaderboardQuery q,
  List<LeaderboardEntry> entries, {
  LeaderboardMe? me,
}) =>
    LeaderboardResult(query: q, entries: entries, me: me, metricLabel: 'Verified steps');

LeaderboardViewModel makeVm(FakeLeaderboardRepository repo, {Future<HostelDirectory> Function()? hostels}) =>
    LeaderboardViewModel(
      repository: repo,
      uid: 'me',
      myHostelId: 'agira',
      myName: 'Me Myself',
      dailyGoal: 8000,
      loadHostels: hostels,
    );

void main() {
  test('starts loading the WEEKLY CAMPUS board, then becomes ready', () async {
    final repo = FakeLeaderboardRepository(
      handler: (q, limit) async => board(q, [student(1, 'a')]),
    );
    final vm = makeVm(repo);
    expect(vm.status, LeaderboardStatus.loading);
    vm.start();
    expect(vm.status, LeaderboardStatus.loading);
    await pumpEventQueue();
    expect(vm.status, LeaderboardStatus.ready);
    expect(repo.calls.single,
        const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.weekly));
    expect(vm.result!.entries.single.id, 'a');
    vm.dispose();
  });

  test('switching scope and period reloads and clears the old board', () async {
    final repo = FakeLeaderboardRepository(
      handler: (q, limit) async => board(q, [student(1, '${q.scope.wire}-${q.period.wire}')]),
    );
    final vm = makeVm(repo)..start();
    await pumpEventQueue();

    vm.selectScope(LeaderboardScope.buddies);
    expect(vm.status, LeaderboardStatus.loading, reason: 'no stale board while loading');
    expect(vm.result, isNull);
    await pumpEventQueue();
    expect(vm.result!.entries.single.id, 'BUDDIES-WEEKLY');

    vm.selectPeriod(LeaderboardPeriod.allTime);
    await pumpEventQueue();
    expect(vm.result!.entries.single.id, 'BUDDIES-ALL_TIME');

    // Re-selecting the same chip does nothing.
    final before = repo.calls.length;
    vm.selectScope(LeaderboardScope.buddies);
    vm.selectPeriod(LeaderboardPeriod.allTime);
    await pumpEventQueue();
    expect(repo.calls.length, before);
    vm.dispose();
  });

  test('hostel metric reloads only on the Hostels board', () async {
    final repo = FakeLeaderboardRepository(handler: (q, l) async => board(q, const []));
    final vm = makeVm(repo)..start();
    await pumpEventQueue();

    vm.selectHostelMetric(HostelMetric.total);
    await pumpEventQueue();
    expect(repo.calls.length, 1, reason: 'metric is irrelevant on the Campus board');

    vm.selectScope(LeaderboardScope.hostels);
    await pumpEventQueue();
    expect(repo.calls.last.hostelMetric, HostelMetric.total);
    expect(repo.calls.last.scope, LeaderboardScope.hostels);

    vm.selectHostelMetric(HostelMetric.average);
    await pumpEventQueue();
    expect(repo.calls.last.hostelMetric, HostelMetric.average);
    expect(repo.calls.length, 3);
    vm.dispose();
  });

  group('race handling', () {
    test('a slow response of an earlier selection is ignored', () async {
      final pending = <LeaderboardScope, Completer<LeaderboardResult>>{};
      final repo = FakeLeaderboardRepository(handler: (q, l) {
        final c = Completer<LeaderboardResult>();
        pending[q.scope] = c;
        return c.future;
      });
      final vm = makeVm(repo)..start(); // campus
      await pumpEventQueue();
      vm.selectScope(LeaderboardScope.hostels);
      vm.selectScope(LeaderboardScope.buddies);
      await pumpEventQueue();
      expect(pending.keys, containsAll(<LeaderboardScope>[
        LeaderboardScope.campus,
        LeaderboardScope.hostels,
        LeaderboardScope.buddies,
      ]));

      // Newest answers first, then the older ones arrive late.
      final q = vm.query;
      pending[LeaderboardScope.buddies]!.complete(board(q, [student(1, 'buddy')]));
      await pumpEventQueue();
      expect(vm.result!.entries.single.id, 'buddy');

      pending[LeaderboardScope.hostels]!.complete(
        board(const LeaderboardQuery(scope: LeaderboardScope.hostels, period: LeaderboardPeriod.weekly),
            [student(1, 'hostel')]),
      );
      pending[LeaderboardScope.campus]!.complete(
        board(const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.weekly),
            [student(1, 'campus')]),
      );
      await pumpEventQueue();
      expect(vm.scope, LeaderboardScope.buddies);
      expect(vm.result!.entries.single.id, 'buddy', reason: 'late replies must not overwrite');
      expect(vm.status, LeaderboardStatus.ready);
      vm.dispose();
    });

    test('an older response arriving BEFORE the newest does not end loading', () async {
      final pending = <LeaderboardPeriod, Completer<LeaderboardResult>>{};
      final repo = FakeLeaderboardRepository(handler: (q, l) {
        final c = Completer<LeaderboardResult>();
        pending[q.period] = c;
        return c.future;
      });
      final vm = makeVm(repo)..start(); // weekly
      await pumpEventQueue();
      vm.selectPeriod(LeaderboardPeriod.daily);
      pending[LeaderboardPeriod.weekly]!.complete(board(
          const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.weekly),
          [student(1, 'weekly')]));
      await pumpEventQueue();
      expect(vm.status, LeaderboardStatus.loading, reason: 'daily is still pending');
      expect(vm.result, isNull);

      pending[LeaderboardPeriod.daily]!.complete(board(
          const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.daily),
          [student(1, 'daily')]));
      await pumpEventQueue();
      expect(vm.result!.entries.single.id, 'daily');
      vm.dispose();
    });

    test('a stale ERROR is ignored too', () async {
      final pending = <LeaderboardScope, Completer<LeaderboardResult>>{};
      final repo = FakeLeaderboardRepository(handler: (q, l) {
        final c = Completer<LeaderboardResult>();
        pending[q.scope] = c;
        return c.future;
      });
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      vm.selectScope(LeaderboardScope.myHostel);
      await pumpEventQueue();
      pending[LeaderboardScope.myHostel]!.complete(board(vm.query, [student(1, 'mine')]));
      pending[LeaderboardScope.campus]!
          .completeError(AppException.fromCallable(code: 'unavailable'));
      await pumpEventQueue();
      expect(vm.status, LeaderboardStatus.ready);
      expect(vm.error, isNull);
      expect(vm.result!.entries.single.id, 'mine');
      vm.dispose();
    });

    test('a response after dispose is dropped silently', () async {
      final c = Completer<LeaderboardResult>();
      final repo = FakeLeaderboardRepository(handler: (q, l) => c.future);
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      vm.dispose();
      c.complete(board(
          const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.weekly),
          [student(1, 'x')]));
      await pumpEventQueue(); // would throw if it notified a disposed notifier
    });
  });

  group('errors and refresh', () {
    test('failure with nothing to show goes to the error state; retry recovers', () async {
      var fail = true;
      final repo = FakeLeaderboardRepository(handler: (q, l) async {
        if (fail) throw AppException.fromCallable(code: 'unavailable');
        return board(q, [student(1, 'a')]);
      });
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      expect(vm.status, LeaderboardStatus.error);
      expect(vm.error!.code, 'unavailable');
      expect(vm.result, isNull);

      fail = false;
      await vm.refresh();
      expect(vm.status, LeaderboardStatus.ready);
      expect(vm.error, isNull);
      vm.dispose();
    });

    test('non-AppException failures become AppException', () async {
      final repo = FakeLeaderboardRepository(handler: (q, l) async => throw StateError('x'));
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      expect(vm.status, LeaderboardStatus.error);
      expect(vm.error, isA<AppException>());
      vm.dispose();
    });

    test('a failed refresh keeps the shown board and exposes refreshError', () async {
      var fail = false;
      final repo = FakeLeaderboardRepository(handler: (q, l) async {
        if (fail) throw AppException.fromCallable(code: 'unavailable');
        return board(q, [student(1, 'a')]);
      });
      final vm = makeVm(repo)..start();
      await pumpEventQueue();

      fail = true;
      final f = vm.refresh();
      expect(vm.isRefreshing, isTrue);
      expect(vm.status, LeaderboardStatus.ready, reason: 'board stays visible while refreshing');
      await f;
      expect(vm.isRefreshing, isFalse);
      expect(vm.status, LeaderboardStatus.ready);
      expect(vm.refreshError!.code, 'unavailable');
      expect(vm.result!.entries.single.id, 'a');

      fail = false;
      await vm.refresh();
      expect(vm.refreshError, isNull);
      vm.dispose();
    });

    test('refresh re-requests the SAME selection', () async {
      final repo = FakeLeaderboardRepository(handler: (q, l) async => board(q, const []));
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      vm.selectScope(LeaderboardScope.hostels);
      vm.selectHostelMetric(HostelMetric.total);
      await pumpEventQueue();
      await vm.refresh();
      expect(repo.calls.last,
          const LeaderboardQuery(
            scope: LeaderboardScope.hostels,
            period: LeaderboardPeriod.weekly,
            hostelMetric: HostelMetric.total,
          ));
      vm.dispose();
    });
  });

  group('derived values', () {
    test('isMine, showPinnedMe and myPinnedEntry for a student outside the list', () async {
      final repo = FakeLeaderboardRepository(handler: (q, l) async => board(
            q,
            [student(1, 'a', value: 5000), student(2, 'b', value: 4000)],
            me: const LeaderboardMe(rank: 57, value: 1234),
          ));
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      expect(vm.meInList, isFalse);
      expect(vm.showPinnedMe, isTrue);
      expect(vm.notRanked, isFalse);
      final pinned = vm.myPinnedEntry!;
      expect([pinned.rank, pinned.id, pinned.name, pinned.value], [57, 'me', 'Me Myself', 1234]);
      expect(vm.isMine(student(1, 'me')), isTrue);
      expect(vm.isMine(student(1, 'someone')), isFalse);
      vm.dispose();
    });

    test('no pinned card when I am in the list', () async {
      final repo = FakeLeaderboardRepository(handler: (q, l) async => board(
            q,
            [student(1, 'a'), student(2, 'me')],
            me: const LeaderboardMe(rank: 2, value: 900),
          ));
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      expect(vm.meInList, isTrue);
      expect(vm.showPinnedMe, isFalse);
      vm.dispose();
    });

    test('not ranked: me without a rank and not in the list', () async {
      final repo = FakeLeaderboardRepository(
        handler: (q, l) async => board(q, [student(1, 'a')], me: const LeaderboardMe()),
      );
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      expect(vm.showPinnedMe, isFalse);
      expect(vm.notRanked, isTrue);
      expect(vm.myPinnedEntry, isNull);
      vm.dispose();
    });

    test('Hostels board: my row is my hostel; the pinned card is my hostel', () async {
      final repo = FakeLeaderboardRepository(handler: (q, l) async => board(
            q,
            [
              const LeaderboardEntry(rank: 1, id: 'vyom', name: 'Vyom Hall', value: 10, isHostel: true),
              const LeaderboardEntry(rank: 2, id: 'agira', name: 'Agira Hall', value: 8, isHostel: true),
            ],
            me: const LeaderboardMe(rank: 2, value: 8),
          ));
      final vm = makeVm(repo)..start();
      vm.selectScope(LeaderboardScope.hostels);
      await pumpEventQueue();
      expect(vm.isMine(vm.result!.entries[1]), isTrue);
      expect(vm.isMine(vm.result!.entries[0]), isFalse);
      expect(vm.showPinnedMe, isFalse);
      vm.dispose();
    });

    test('progressBase: daily goal on DAILY student boards, leader otherwise', () async {
      final repo = FakeLeaderboardRepository(handler: (q, l) async => board(q, const []));
      final vm = makeVm(repo)..start();
      await pumpEventQueue();
      expect(vm.progressBase, isNull, reason: 'weekly -> relative to the leader');
      vm.selectPeriod(LeaderboardPeriod.daily);
      expect(vm.progressBase, 8000);
      vm.selectScope(LeaderboardScope.hostels);
      expect(vm.progressBase, isNull, reason: 'hostel averages are not compared to a personal goal');
      await pumpEventQueue();
      vm.dispose();
    });

    test('hostelNameOf: live directory, then seed, then the raw id', () async {
      final repo = FakeLeaderboardRepository(handler: (q, l) async => board(q, const []));
      final vm = makeVm(
        repo,
        hostels: () async => const HostelDirectory(
          isFallback: false,
          hostels: [
            Hostel(id: 'custom', displayName: 'Custom Hall', category: HostelCategory.general, sortOrder: 1),
          ],
        ),
      );
      expect(vm.hostelNameOf('agira'), 'Agira Hall', reason: 'seed before the directory loads');
      vm.start();
      await pumpEventQueue();
      expect(vm.hostelNameOf('custom'), 'Custom Hall');
      expect(vm.hostelNameOf('unknown-id'), 'unknown-id');
      expect(vm.hostelNameOf(null), isNull);
      expect(vm.hostelNameOf(''), isNull);
      vm.dispose();
    });

    test('a failing hostel directory does not break the board', () async {
      final repo = FakeLeaderboardRepository(
          handler: (q, l) async => board(q, [student(1, 'a', hostelId: 'agira')]));
      final vm = makeVm(repo, hostels: () async => throw StateError('offline'))..start();
      await pumpEventQueue();
      expect(vm.status, LeaderboardStatus.ready);
      expect(vm.hostelNameOf('agira'), 'Agira Hall');
      vm.dispose();
    });
  });
}
