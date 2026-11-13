import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/core/utils/clock.dart';
import 'package:stepup/data/bets/bet_models.dart';
import 'package:stepup/data/bets/bets_repository.dart';
import 'package:stepup/data/bets/fake_bets_read_source.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/features/bets/bet_rules.dart';
import 'package:stepup/features/bets/bets_view_models.dart';

import 'bets_support.dart';

const _riya = BuddySummary(uid: 'buddy1', displayName: 'Riya Verma');
const _kabir = BuddySummary(uid: 'buddy2', displayName: 'Kabir Singh');

Future<void> pump() => Future<void>.delayed(Duration.zero);

class _Rig {
  _Rig({int available = 500, int reserved = 0}) {
    fs.setProfile(profileWithPoints(kMe, available: available, reserved: reserved));
    repo = FunctionsBetsRepository(functions: fn, source: source, firestore: fs);
  }

  final fn = FakeFunctionsClient();
  final source = FakeBetsReadSource();
  final fs = FakeFirestoreAccess();
  final buddies = FakeBuddyDirectory([_riya, _kabir]);
  final clock = FakeClock(kNow);
  late final FunctionsBetsRepository repo;

  CreateBetViewModel create({String? preset, String Function()? ids}) => CreateBetViewModel(
        myUid: kMe,
        repository: repo,
        buddies: buddies,
        clock: clock,
        presetBuddyUid: preset,
        requestIdGenerator: ids,
      );
}

void main() {
  group('CreateBetViewModel', () {
    test('starts with sensible defaults and no buddy selected (invalid)', () async {
      final r = _Rig();
      final vm = r.create()..start();
      await pump();
      expect(vm.target, 10000);
      expect(vm.stake, 50);
      expect(vm.days, 7);
      expect(vm.buddies.map((b) => b.uid), ['buddy1', 'buddy2']);
      expect(vm.selected, isNull);
      expect(vm.isValid, isFalse);
      expect(vm.canSubmit, isFalse);
      vm.dispose();
    });

    test('valid once a buddy is chosen; preview shows reserved and remaining points', () async {
      final r = _Rig(available: 500);
      final vm = r.create()..start();
      await pump();
      vm.selectBuddy(_riya);
      expect(vm.isValid, isTrue);
      expect(vm.reservedNow, 50);
      expect(vm.availableAfter, 450);
      vm.setStakeText('200');
      expect(vm.availableAfter, 300);
      vm.dispose();
    });

    test('stake validated against AVAILABLE points (not reserved / total)', () async {
      final r = _Rig(available: 100, reserved: 900);
      final vm = r.create()..start();
      await pump();
      vm.selectBuddy(_riya);
      vm.setStakeText('101');
      expect(vm.stakeError, 'You only have 100 points available.');
      expect(vm.isValid, isFalse);
      vm.setStakeText('100');
      expect(vm.stakeError, isNull);
      expect(vm.isValid, isTrue);
      vm.dispose();
    });

    test('stake and target limits', () async {
      final r = _Rig(available: 5000);
      final vm = r.create()..start();
      await pump();
      vm.selectBuddy(_riya);
      vm.setStakeText('5');
      expect(vm.isValid, isFalse);
      vm.setStakeText('1001');
      expect(vm.isValid, isFalse);
      vm.setStakeText('1000');
      expect(vm.isValid, isTrue);
      vm.setTargetText('500');
      expect(vm.targetError, contains('at least'));
      vm.setTargetText('abc');
      expect(vm.isValid, isFalse);
      vm.setTargetText('10,000');
      expect(vm.isValid, isTrue);
      vm.setTargetText('25000');
      expect(vm.isValid, isTrue);
      vm.setDays(1);
      expect(vm.targetError, contains('most you can ask for'));
      vm.setTargetText('20000');
      expect(vm.isValid, isTrue);
      vm.setDays(99);
      expect(vm.days, 30);
      vm.setDays(0);
      expect(vm.days, 1);
      vm.dispose();
    });

    test('errors for empty fields only appear after a submit attempt', () async {
      final r = _Rig();
      final vm = r.create()..start();
      await pump();
      vm.setTargetText('');
      vm.setStakeText('');
      expect(vm.targetError, isNull);
      expect(vm.stakeError, isNull);
      expect(await vm.submit(), isNull);
      expect(vm.targetError, isNotNull);
      expect(vm.stakeError, isNotNull);
      expect(vm.buddyError, isNotNull);
      expect(r.fn.calls, isEmpty, reason: 'nothing sent while invalid');
      vm.dispose();
    });

    test('example period starts at the next IST midnight', () async {
      final r = _Rig();
      final vm = r.create()..start();
      await pump();
      // now = Fri 13 Nov 11:30 IST -> starts Sat 14 Nov 00:00 IST
      expect(vm.examplePeriod.start, DateTime.utc(2026, 11, 13, 18, 30));
      vm.setDays(7);
      expect(vm.examplePeriodLabel, 'Sat 14 Nov to Fri 20 Nov');
      vm.setDays(1);
      expect(vm.examplePeriodLabel, 'Sat 14 Nov');
      vm.dispose();
    });

    test('?buddy= preselects an accepted buddy', () async {
      final r = _Rig();
      final vm = r.create(preset: 'buddy2')..start();
      await pump();
      expect(vm.selected?.uid, 'buddy2');
      expect(vm.presetMissing, isFalse);
      vm.dispose();
    });

    test('?buddy= of a non-buddy is flagged and not selected', () async {
      final r = _Rig();
      final vm = r.create(preset: 'stranger')..start();
      await pump();
      expect(vm.selected, isNull);
      expect(vm.presetMissing, isTrue);
      vm.selectBuddy(_riya);
      expect(vm.presetMissing, isFalse);
      vm.dispose();
    });

    test('selection is dropped when the buddy is removed', () async {
      final r = _Rig();
      final vm = r.create()..start();
      await pump();
      vm.selectBuddy(_riya);
      r.buddies.setBuddies([_kabir]);
      await pump();
      expect(vm.selected, isNull);
      vm.dispose();
    });

    test('submit calls createStepBet with the form values and returns the id', () async {
      final r = _Rig();
      r.fn.on('createStepBet', (p) => {'betId': 'newbet', 'duplicate': false});
      final vm = r.create(ids: () => 'bet-fixedid01')..start();
      await pump();
      vm.selectBuddy(_kabir);
      vm.setTargetText('12,000');
      vm.setDays(3);
      vm.setStakeText('75');
      final id = await vm.submit();
      expect(id, 'newbet');
      expect(vm.error, isNull);
      expect(vm.submitting, isFalse);
      expect(r.fn.callsTo('createStepBet').single.params, {
        'opponentUid': 'buddy2',
        'targetSteps': 12000,
        'durationDays': 3,
        'stakePoints': 75,
        'requestId': 'bet-fixedid01',
      });
      vm.dispose();
    });

    test('double submit sends ONE request', () async {
      final r = _Rig();
      final gate = Completer<Map<String, dynamic>>();
      r.fn.on('createStepBet', (p) => {'betId': 'b'});
      // Make the call slow by wrapping the repository.
      final slow = _SlowRepo(r.repo, gate.future);
      final vm = CreateBetViewModel(
          myUid: kMe, repository: slow, buddies: r.buddies, clock: r.clock)
        ..start();
      await pump();
      vm.selectBuddy(_riya);
      final first = vm.submit();
      expect(vm.submitting, isTrue);
      expect(vm.canSubmit, isFalse);
      final second = await vm.submit();
      expect(second, isNull);
      gate.complete({});
      expect(await first, 'b');
      expect(slow.createCalls, 1);
      vm.dispose();
    });

    test('insufficient points from the server gives a friendly message and re-enables submit', () async {
      final r = _Rig();
      r.fn.failNext(
        'createStepBet',
        AppException.fromCallable(
            code: 'failed-precondition',
            message: 'not enough points',
            details: {'reason': 'INSUFFICIENT_POINTS'}),
      );
      final vm = r.create()..start();
      await pump();
      vm.selectBuddy(_riya);
      expect(await vm.submit(), isNull);
      expect(vm.error, 'You do not have enough available points for this stake.');
      expect(vm.submitting, isFalse);
      expect(vm.canSubmit, isTrue);
      vm.dispose();
    });

    test('not-a-buddy and duplicate errors are friendly', () async {
      final r = _Rig();
      r.fn
        ..failNext('createStepBet',
            AppException.fromCallable(code: 'failed-precondition', details: {'reason': 'NOT_BUDDIES'}))
        ..failNext('createStepBet', AppException.fromCallable(code: 'already-exists'));
      final vm = r.create()..start();
      await pump();
      vm.selectBuddy(_riya);
      await vm.submit();
      expect(vm.error, 'You can only bet with an accepted buddy.');
      await vm.submit();
      expect(vm.error, 'You already have a matching bet with this buddy.');
      vm.dispose();
    });

    test('network failure keeps the same request id for a safe retry; editing renews it', () async {
      final r = _Rig();
      var n = 0;
      r.fn.failNext('createStepBet', AppException.fromCallable(code: 'unavailable'));
      r.fn.on('createStepBet', (p) => {'betId': 'ok', 'duplicate': true});
      final vm = r.create(ids: () => 'bet-id-${n++}00000')..start();
      await pump();
      vm.selectBuddy(_riya);
      final before = vm.requestId;
      expect(await vm.submit(), isNull);
      expect(vm.error, contains('Network problem'));
      expect(vm.requestId, before);
      expect(await vm.submit(), 'ok', reason: 'server dedupes via requestId (duplicate:true)');
      expect(r.fn.callsTo('createStepBet').map((c) => c.params['requestId']).toSet(), {before});
      vm.setStakeText('60');
      expect(vm.requestId, isNot(before));
      vm.dispose();
    });

    test('generated request ids match the server pattern', () {
      final r = _Rig();
      final id = r.create().requestId;
      expect(RegExp(r'^[A-Za-z0-9-]{8,40}$').hasMatch(id), isTrue, reason: id);
    });
  });

  group('BetDetailViewModel', () {
    BetDetailViewModel make(_Rig r, {String id = 'bet1', String me = kBuddy}) =>
        BetDetailViewModel(betId: id, myUid: me, repository: r.repo, clock: r.clock);

    test('opponent can respond to a pending bet; challenger can cancel', () async {
      final r = _Rig();
      r.source.setBets([makeBet()]);
      final opp = make(r)..start();
      final chal = make(r, me: kMe)..start();
      await pump();
      expect(opp.canRespond, isTrue);
      expect(opp.canCancel, isFalse);
      expect(chal.canCancel, isTrue);
      expect(chal.canRespond, isFalse);
      opp.dispose();
      chal.dispose();
    });

    test('no actions once the bet is active/completed', () async {
      final r = _Rig();
      r.source.setBets([activeBet(id: 'bet1')]);
      final vm = make(r)..start();
      await pump();
      expect(vm.canRespond, isFalse);
      expect(vm.canCancel, isFalse);
      vm.dispose();
    });

    test('accept disabled when available points are known to be too low', () async {
      final r = _Rig(available: 20);
      r.fs.setProfile(profileWithPoints(kBuddy, available: 20));
      r.source.setBets([makeBet(stake: 50)]);
      final vm = make(r)..start();
      await pump();
      expect(vm.insufficientToAccept, isTrue);
      expect(vm.canAccept, isFalse);
      expect(vm.canRespond, isTrue, reason: 'decline stays possible');
      vm.dispose();
    });

    test('respond is disabled for an invite past 48 h', () async {
      final r = _Rig();
      r.source.setBets([makeBet(expiresAt: kNow.subtract(const Duration(minutes: 1)))]);
      final vm = make(r)..start();
      await pump();
      expect(vm.inviteExpired, isTrue);
      expect(vm.canRespond, isFalse);
      vm.dispose();
    });

    test('accept / decline / cancel call the right callables', () async {
      final r = _Rig();
      r.fn
        ..on('respondStepBet', (p) => {'ok': true})
        ..on('cancelStepBet', (p) => {'ok': true});
      r.source.setBets([makeBet()]);
      final opp = make(r)..start();
      final chal = make(r, me: kMe)..start();
      await pump();
      expect(await opp.accept(), isTrue);
      expect(await opp.decline(), isTrue);
      expect(await chal.cancel(), isTrue);
      expect(r.fn.calls.map((c) => '${c.name}:${c.params}').toList(), [
        'respondStepBet:{betId: bet1, accept: true}',
        'respondStepBet:{betId: bet1, accept: false}',
        'cancelStepBet:{betId: bet1}',
      ]);
      opp.dispose();
      chal.dispose();
    });

    test('server error is shown in friendly words and the user can retry', () async {
      final r = _Rig();
      r.fn
        ..failNext('respondStepBet',
            AppException.fromCallable(code: 'failed-precondition', details: {'reason': 'BET_EXPIRED'}))
        ..on('respondStepBet', (p) => {'ok': true});
      r.source.setBets([makeBet()]);
      final vm = make(r)..start();
      await pump();
      expect(await vm.accept(), isFalse);
      expect(vm.actionError, contains('expired'));
      expect(vm.busy, isFalse);
      expect(await vm.accept(), isTrue);
      expect(vm.actionError, isNull);
      vm.dispose();
    });

    test('missing bet -> notFound; stream error -> hasError', () async {
      final r = _Rig();
      final vm = make(r, id: 'nope')..start();
      await pump();
      expect(vm.notFound, isTrue);
      vm.dispose();
      r.source.streamError = const AppException(code: 'permission-denied', message: 'x');
      final bad = make(r)..start();
      await pump();
      expect(bad.hasError, isTrue);
      bad.dispose();
    });
  });

  group('LedgerViewModel', () {
    List<LedgerEntry> entries(int n) => [
          for (var i = 0; i < n; i++)
            ledger('e$i', LedgerType.reward, refType: 'DAILY_GOAL', refId: 'd$i', delta: 10),
        ];

    test('loads the first page then pages on demand', () async {
      final r = _Rig(available: 77, reserved: 23);
      r.source.setLedger(entries(5));
      final vm = LedgerViewModel(uid: kMe, repository: r.repo, pageSize: 2)..start();
      await pump();
      await pump();
      expect(vm.entries.map((e) => e.id), ['e0', 'e1']);
      expect(vm.hasMore, isTrue);
      expect(vm.points!.total, 100);
      await vm.loadMore();
      await vm.loadMore();
      expect(vm.entries.map((e) => e.id), ['e0', 'e1', 'e2', 'e3', 'e4']);
      expect(vm.hasMore, isFalse);
      final fetches = r.source.ledgerFetches;
      await vm.loadMore();
      expect(r.source.ledgerFetches, fetches, reason: 'no fetch when there is no more');
      vm.dispose();
    });

    test('empty ledger', () async {
      final r = _Rig();
      final vm = LedgerViewModel(uid: kMe, repository: r.repo)..start();
      await pump();
      await pump();
      expect(vm.isEmpty, isTrue);
      vm.dispose();
    });

    test('first page failure -> error then refresh recovers', () async {
      final r = _Rig();
      r.source
        ..setLedger(entries(1))
        ..failNextLedger = AppException.fromCallable(code: 'unavailable');
      final vm = LedgerViewModel(uid: kMe, repository: r.repo)..start();
      await pump();
      await pump();
      expect(vm.error, contains('Network problem'));
      await vm.refresh();
      expect(vm.error, isNull);
      expect(vm.entries, hasLength(1));
      vm.dispose();
    });

    test('load-more failure keeps entries and reports moreError', () async {
      final r = _Rig();
      r.source.setLedger(entries(4));
      final vm = LedgerViewModel(uid: kMe, repository: r.repo, pageSize: 2)..start();
      await pump();
      await pump();
      r.source.failNextLedger = AppException.fromCallable(code: 'unavailable');
      await vm.loadMore();
      expect(vm.entries, hasLength(2));
      expect(vm.moreError, isNotNull);
      await vm.loadMore();
      expect(vm.entries, hasLength(4));
      expect(vm.moreError, isNull);
      vm.dispose();
    });
  });

  group('BetsListViewModel', () {
    test('default segment: Pending when an invite awaits me, else Active, else History', () async {
      final r = _Rig();
      r.source.setBets([
        makeBet(id: 'inv', challengerUid: kBuddy, opponentUid: kMe),
        activeBet(id: 'a'),
      ]);
      var vm = BetsListViewModel(uid: kMe, repository: r.repo)..start();
      await pump();
      expect(vm.segment, BetSegment.pending);
      vm.dispose();

      r.source.setBets([activeBet(id: 'a')]);
      vm = BetsListViewModel(uid: kMe, repository: r.repo)..start();
      await pump();
      expect(vm.segment, BetSegment.active);
      vm.dispose();

      r.source.setBets([makeBet(status: BetStatus.completed)]);
      vm = BetsListViewModel(uid: kMe, repository: r.repo)..start();
      await pump();
      expect(vm.segment, BetSegment.history);
      vm.dispose();
    });

    test('user choice sticks; counts and filtering work', () async {
      final r = _Rig();
      r.source.setBets([
        makeBet(id: 'p'),
        activeBet(id: 'a'),
        makeBet(id: 'c', status: BetStatus.completed),
        makeBet(id: 'x', status: BetStatus.declined),
      ]);
      final vm = BetsListViewModel(uid: kMe, repository: r.repo)..start();
      await pump();
      expect(vm.segment, BetSegment.active, reason: 'no invite for me, so Active is the default');
      expect([for (final b in vm.visible) b.id], ['a']);
      expect(vm.count(BetSegment.pending), 1);
      expect(vm.count(BetSegment.closed), 1);
      expect(vm.count(BetSegment.history), 4);
      vm.selectSegment(BetSegment.closed);
      expect([for (final b in vm.visible) b.id], ['x']);
      // a later server update must not switch the user's chosen segment
      r.source.upsertBet(makeBet(id: 'new', challengerUid: kBuddy, opponentUid: kMe));
      await pump();
      expect(vm.segment, BetSegment.closed);
      vm.selectSegment(BetSegment.history);
      expect(vm.visible, hasLength(5));
      vm.dispose();
    });

    test('points are exposed and a stream error is reported with retry', () async {
      final r = _Rig(available: 300, reserved: 40);
      r.source.streamError = const AppException(code: 'unavailable', message: 'x');
      final vm = BetsListViewModel(uid: kMe, repository: r.repo)..start();
      await pump();
      expect(vm.hasError, isTrue);
      expect(vm.points, const PointsBalance(available: 300, reserved: 40));
      r.source.streamError = null;
      vm.retry();
      await pump();
      expect(vm.hasError, isFalse);
      expect(vm.loading, isFalse);
      vm.dispose();
    });
  });
}

/// Delays `createBet` until [gate] completes and counts calls.
class _SlowRepo implements BetsRepository {
  _SlowRepo(this._inner, this._gate);

  final BetsRepository _inner;
  final Future<Map<String, dynamic>> _gate;
  int createCalls = 0;

  @override
  Future<CreatedBet> createBet({
    required String opponentUid,
    required int targetSteps,
    required int durationDays,
    required int stakePoints,
    String? requestId,
  }) async {
    createCalls++;
    await _gate;
    return _inner.createBet(
      opponentUid: opponentUid,
      targetSteps: targetSteps,
      durationDays: durationDays,
      stakePoints: stakePoints,
      requestId: requestId,
    );
  }

  @override
  Future<void> cancel(String betId) => _inner.cancel(betId);
  @override
  Future<LedgerPage> fetchLedger(String uid, {Object? cursor, int limit = 30}) =>
      _inner.fetchLedger(uid, cursor: cursor, limit: limit);
  @override
  Future<void> respond(String betId, {required bool accept}) =>
      _inner.respond(betId, accept: accept);
  @override
  Stream<StepBet?> watchBet(String betId) => _inner.watchBet(betId);
  @override
  Stream<List<StepBet>> watchBets(String uid) => _inner.watchBets(uid);
  @override
  Stream<PointsBalance> watchPoints(String uid) => _inner.watchPoints(uid);
}
