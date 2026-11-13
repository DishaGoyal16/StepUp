import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/bets/bet_models.dart';
import 'package:stepup/data/bets/bets_repository.dart';
import 'package:stepup/data/bets/fake_bets_read_source.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';

import '../../features/bets/bets_support.dart';

void main() {
  group('StepBet.fromMap', () {
    test('parses every server field', () {
      final bet = StepBet.fromMap('b1', {
        'challengerUid': 'a',
        'opponentUid': 'b',
        'challengerName': 'Asha',
        'opponentName': 'Bala',
        'targetSteps': 12000,
        'durationDays': 5,
        'stakePoints': 80,
        'status': 'COMPLETED',
        'startAt': DateTime.utc(2026, 11, 1, 18, 30),
        'endAt': 1762457400000,
        'challengerSteps': 13000,
        'opponentSteps': 12500,
        'winnerUid': 'a',
        'resolution': 'HIGHER_STEPS',
        'createdAt': DateTime.utc(2026, 10, 30),
        'settledAt': DateTime.utc(2026, 11, 7),
        'expiresAt': null,
      });
      expect(bet.id, 'b1');
      expect(bet.status, BetStatus.completed);
      expect(bet.resolution, BetResolution.higherSteps);
      expect(bet.winnerUid, 'a');
      expect(bet.potPoints, 160);
      expect(bet.endAt, DateTime.fromMillisecondsSinceEpoch(1762457400000, isUtc: true));
      expect(bet.expiresAt, isNull);
      expect(bet.reachedTarget('a'), isTrue);
      expect(bet.otherNameOf('a'), 'Bala');
      expect(bet.isRefund, isFalse);
    });

    test('unknown/missing values are safe', () {
      final bet = StepBet.fromMap('x', {'status': 'WHAT', 'winnerUid': '', 'resolution': 'NOPE'});
      expect(bet.status, BetStatus.unknown);
      expect(bet.winnerUid, isNull);
      expect(bet.resolution, isNull);
      expect(bet.targetSteps, 0);
      expect(bet.progressOf('anyone'), 0);
    });

    test('progress is clamped to 0..1 and uses the right side', () {
      final bet = makeBet(target: 1000, challengerSteps: 2500, opponentSteps: 250);
      expect(bet.progressOf(kMe), 1.0);
      expect(bet.progressOf(kBuddy), 0.25);
      expect(bet.stepsOf(kBuddy), 250);
      expect(bet.otherUid(kMe), kBuddy);
      expect(bet.otherUid(kBuddy), kMe);
    });

    test('closedWithoutPlay covers cancelled, declined, expired only', () {
      expect(
        BetStatus.values.where((s) => s.closedWithoutPlay).toSet(),
        {BetStatus.cancelled, BetStatus.declined, BetStatus.expired},
      );
    });

    test('refund = completed without winner', () {
      expect(makeBet(status: BetStatus.completed, resolution: BetResolution.refundTie).isRefund, isTrue);
      expect(makeBet(status: BetStatus.active).isRefund, isFalse);
    });
  });

  test('LedgerEntry.fromMap', () {
    final e = LedgerEntry.fromMap('BET_b1_u_RESERVE', {
      'type': 'RESERVE',
      'refType': 'BET',
      'refId': 'b1',
      'delta': -50,
      'reservedDelta': 50,
      'balanceAfter': 450,
      'reservedAfter': 50,
      'note': 'Stake reserved for step bet',
      'createdAt': DateTime.utc(2026, 11, 13),
    });
    expect(e.type, LedgerType.reserve);
    expect(e.delta, -50);
    expect(e.isBetEntry, isTrue);
    expect(LedgerEntry.fromMap('z', {'type': 'NEW'}).type, LedgerType.unknown);
    expect(LedgerEntry.fromMap('z', {'refType': 'ADMIN'}).isBetEntry, isFalse);
  });

  group('mergeBetStreams', () {
    test('waits for both sides, merges, de-duplicates and sorts newest first', () async {
      final a = StreamController<List<StepBet>>();
      final b = StreamController<List<StepBet>>();
      final out = <List<String>>[];
      final sub = mergeBetStreams(a.stream, b.stream).listen((l) => out.add([for (final x in l) x.id]));
      a.add([
        makeBet(id: 'old', createdAt: kNow.subtract(const Duration(days: 3))),
        makeBet(id: 'mid', createdAt: kNow.subtract(const Duration(days: 2))),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(out, isEmpty, reason: 'not emitted until both sides have data');
      b.add([makeBet(id: 'new', createdAt: kNow), makeBet(id: 'mid', createdAt: kNow.subtract(const Duration(days: 2)))]);
      await Future<void>.delayed(Duration.zero);
      expect(out.single, ['new', 'mid', 'old']);
      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('forwards errors', () async {
      final a = StreamController<List<StepBet>>();
      final b = StreamController<List<StepBet>>();
      final errors = <Object>[];
      final sub = mergeBetStreams(a.stream, b.stream).listen((_) {}, onError: errors.add);
      a.addError('boom');
      await Future<void>.delayed(Duration.zero);
      expect(errors, ['boom']);
      await sub.cancel();
      await a.close();
      await b.close();
    });
  });

  group('FunctionsBetsRepository', () {
    late FakeFunctionsClient fn;
    late FakeBetsReadSource source;
    late FakeFirestoreAccess fs;
    late FunctionsBetsRepository repo;

    setUp(() {
      fn = FakeFunctionsClient();
      source = FakeBetsReadSource();
      fs = FakeFirestoreAccess();
      repo = FunctionsBetsRepository(functions: fn, source: source, firestore: fs);
    });

    test('createBet sends the exact params to createStepBet and returns the id', () async {
      fn.on('createStepBet', (p) => {'betId': 'new1', 'duplicate': false});
      final r = await repo.createBet(
        opponentUid: 'u2',
        targetSteps: 8000,
        durationDays: 3,
        stakePoints: 40,
        requestId: 'bet-abcdefgh',
      );
      expect(r.betId, 'new1');
      expect(r.duplicate, isFalse);
      final call = fn.callsTo('createStepBet').single;
      expect(call.params, {
        'opponentUid': 'u2',
        'targetSteps': 8000,
        'durationDays': 3,
        'stakePoints': 40,
        'requestId': 'bet-abcdefgh',
      });
    });

    test('createBet omits requestId when null and reports duplicates', () async {
      fn.on('createStepBet', (p) => {'betId': 'old1', 'duplicate': true});
      final r = await repo.createBet(
        opponentUid: 'u2',
        targetSteps: 8000,
        durationDays: 3,
        stakePoints: 40,
      );
      expect(r.duplicate, isTrue);
      expect(fn.calls.single.params.containsKey('requestId'), isFalse);
    });

    test('createBet rejects a response without a bet id', () async {
      fn.on('createStepBet', (p) => {'ok': true});
      expect(
        repo.createBet(opponentUid: 'u', targetSteps: 1000, durationDays: 1, stakePoints: 10),
        throwsA(isA<AppException>()),
      );
    });

    test('server errors surface as AppException with their reason', () async {
      fn.failNext(
        'createStepBet',
        AppException.fromCallable(
          code: 'failed-precondition',
          message: 'not enough points',
          details: {'reason': 'INSUFFICIENT_POINTS'},
        ),
      );
      await expectLater(
        repo.createBet(opponentUid: 'u', targetSteps: 1000, durationDays: 1, stakePoints: 10),
        throwsA(isA<AppException>().having((e) => e.reason, 'reason', 'INSUFFICIENT_POINTS')),
      );
    });

    test('respond and cancel call the right callables', () async {
      fn
        ..on('respondStepBet', (p) => {'ok': true})
        ..on('cancelStepBet', (p) => {'ok': true});
      await repo.respond('b1', accept: true);
      await repo.respond('b2', accept: false);
      await repo.cancel('b3');
      expect(fn.calls.map((c) => c.name), ['respondStepBet', 'respondStepBet', 'cancelStepBet']);
      expect(fn.calls[0].params, {'betId': 'b1', 'accept': true});
      expect(fn.calls[1].params, {'betId': 'b2', 'accept': false});
      expect(fn.calls[2].params, {'betId': 'b3'});
    });

    test('watchPoints reads pointsBalance / pointsReserved from users/{uid}', () async {
      fs.setProfile(profileWithPoints(kMe, available: 321, reserved: 79));
      final p = await repo.watchPoints(kMe).first;
      expect(p.available, 321);
      expect(p.reserved, 79);
      expect(p.total, 400);
      fs.setProfile(null);
      expect(await repo.watchPoints(kMe).first, PointsBalance.zero);
    });

    test('watchBets only returns my bets, newest first', () async {
      source.setBets([
        makeBet(id: 'mine-old', createdAt: kNow.subtract(const Duration(days: 1))),
        makeBet(id: 'other', challengerUid: 'x', opponentUid: 'y'),
        makeBet(id: 'mine-new', challengerUid: kBuddy, opponentUid: kMe, createdAt: kNow),
      ]);
      final list = await repo.watchBets(kMe).first;
      expect([for (final b in list) b.id], ['mine-new', 'mine-old']);
    });

    test('watchBet emits null for an unknown bet and updates on change', () async {
      source.setBets([makeBet()]);
      expect(await repo.watchBet('nope').first, isNull);
      final seen = <BetStatus?>[];
      final sub = repo.watchBet('bet1').listen((b) => seen.add(b?.status));
      await Future<void>.delayed(Duration.zero);
      source.upsertBet(makeBet(status: BetStatus.active));
      await Future<void>.delayed(Duration.zero);
      expect(seen, [BetStatus.pending, BetStatus.active]);
      await sub.cancel();
    });

    test('ledger pagination returns pages, cursor and hasMore', () async {
      source.setLedger([for (var i = 0; i < 5; i++) ledger('e$i', LedgerType.reward, refType: 'DAILY_GOAL', refId: 'd$i')]);
      final p1 = await repo.fetchLedger(kMe, limit: 2);
      expect([for (final e in p1.entries) e.id], ['e0', 'e1']);
      expect(p1.hasMore, isTrue);
      final p2 = await repo.fetchLedger(kMe, cursor: p1.cursor, limit: 2);
      expect([for (final e in p2.entries) e.id], ['e2', 'e3']);
      final p3 = await repo.fetchLedger(kMe, cursor: p2.cursor, limit: 2);
      expect([for (final e in p3.entries) e.id], ['e4']);
      expect(p3.hasMore, isFalse);
    });
  });
}
