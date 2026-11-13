import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/bets/bet_models.dart';
import 'package:stepup/features/bets/bet_errors.dart';
import 'package:stepup/features/bets/bet_rules.dart';

import 'bets_support.dart';

StepBet completed({
  String? winner,
  BetResolution? resolution,
  int stake = 50,
}) =>
    makeBet(
      status: BetStatus.completed,
      winnerUid: winner,
      resolution: resolution,
      stake: stake,
      target: 10000,
      challengerSteps: 12000,
      opponentSteps: 11000,
    );

void main() {
  group('BetValidator.parseWhole', () {
    test('accepts plain and comma formatted numbers', () {
      expect(BetValidator.parseWhole('10000'), 10000);
      expect(BetValidator.parseWhole(' 10,000 '), 10000);
      expect(BetValidator.parseWhole('1 000'), 1000);
    });
    test('rejects empty, decimal, negative, text, absurd length', () {
      for (final s in ['', '  ', '12.5', '-5', 'abc', '1e3', '1234567890']) {
        expect(BetValidator.parseWhole(s), isNull, reason: s);
      }
    });
  });

  group('BetValidator.duration', () {
    test('1..30 only', () {
      expect(BetValidator.duration(1), isNull);
      expect(BetValidator.duration(30), isNull);
      expect(BetValidator.duration(0), isNotNull);
      expect(BetValidator.duration(31), isNotNull);
      expect(BetValidator.duration(null), isNotNull);
    });
  });

  group('BetValidator.target', () {
    test('positive, at least 1,000', () {
      expect(BetValidator.target(null, 7), isNotNull);
      expect(BetValidator.target(0, 7), isNotNull);
      expect(BetValidator.target(999, 7), contains('at least'));
      expect(BetValidator.target(1000, 7), isNull);
      expect(BetValidator.target(10000, 7), isNull);
    });
    test('cannot exceed what verified steps allow in that duration', () {
      expect(BetValidator.target(20000, 1), isNull);
      final msg = BetValidator.target(20001, 1)!;
      expect(msg, contains('20,000'));
      expect(msg, contains('1 day'));
      expect(BetValidator.target(140000, 7), isNull);
      expect(BetValidator.target(140001, 7), isNotNull);
      // 30 days -> 600,000 (below the 1,000,000 server maximum)
      expect(BetValidator.target(600000, 30), isNull);
      expect(BetValidator.target(600001, 30), isNotNull);
    });
    test('an invalid duration does not crash the target check', () {
      expect(BetValidator.target(5000, null), isNull);
      expect(BetValidator.target(5000, 99), isNull);
    });
  });

  group('BetValidator.stake', () {
    test('range 10..1000', () {
      expect(BetValidator.stake(9, null), isNotNull);
      expect(BetValidator.stake(10, null), isNull);
      expect(BetValidator.stake(1000, null), isNull);
      expect(BetValidator.stake(1001, null), isNotNull);
      expect(BetValidator.stake(null, null), isNotNull);
    });
    test('checked against AVAILABLE points', () {
      expect(BetValidator.stake(100, 100), isNull);
      expect(BetValidator.stake(101, 100), 'You only have 100 points available.');
      expect(BetValidator.stake(50, 5), contains('at least 10 available points'));
      expect(BetValidator.stake(10, 0), isNotNull);
      expect(BetValidator.stake(10, null), isNull, reason: 'unknown balance: server decides');
    });
    test('singular point wording', () {
      expect(pointsLabel(1), '1 point');
      expect(pointsLabel(1000), '1,000 points');
    });
  });

  group('BetText', () {
    test('notices state virtual points only, no real money', () {
      expect(BetText.virtualPointsNotice.toLowerCase(), contains('virtual points only'));
      expect(BetText.virtualPointsNotice.toLowerCase(), contains('no real money'));
      expect(BetText.virtualPointsNotice.toLowerCase(), contains('voluntary'));
    });

    test('winner rule covers every case incl. tie refund', () {
      final all = BetText.winnerRule.join(' ');
      expect(all, contains('higher number of verified steps'));
      expect(all, contains('tie refunds both stakes'));
      expect(all, contains('only one'));
      expect(all, contains('nobody reaches the target'));
    });

    test('expiry mentions 48 hours', () {
      expect(BetText.expiry, contains('48 hours'));
    });

    test('resolution HIGHER_STEPS', () {
      final b = completed(winner: kMe, resolution: BetResolution.higherSteps);
      expect(BetText.resolution(b, kMe), contains('Both of you reached the target of 10,000 steps'));
      expect(BetText.resolution(b, kMe), contains('You had more verified steps'));
      expect(BetText.resolution(b, kBuddy), contains('Aarav Sharma had more verified steps'));
      expect(BetText.resultHeadline(b, kMe), 'You won!');
      expect(BetText.resultHeadline(b, kBuddy), 'Aarav Sharma won');
    });

    test('resolution ONLY_ONE_REACHED_TARGET', () {
      final b = completed(winner: kBuddy, resolution: BetResolution.onlyOneReachedTarget);
      expect(BetText.resolution(b, kMe), 'Only Riya Verma reached the target of 10,000 steps.');
      expect(BetText.resolution(b, kBuddy), 'Only You reached the target of 10,000 steps.');
    });

    test('resolution refunds', () {
      final none = completed(resolution: BetResolution.refundNoneReached);
      expect(BetText.resolution(none, kMe), contains('Nobody reached the target'));
      expect(BetText.resultHeadline(none, kMe), 'Draw - stakes refunded');
      final tie = completed(resolution: BetResolution.refundTie);
      expect(BetText.resolution(tie, kMe), contains('exactly the same'));
      expect(BetText.pointsMoved(tie, kMe), 'Both stakes of 50 points were returned.');
    });

    test('points moved for winner and loser come from stake only', () {
      final b = completed(winner: kMe, resolution: BetResolution.higherSteps, stake: 80);
      expect(BetText.pointsMoved(b, kMe), contains('160 points'));
      expect(BetText.pointsMoved(b, kMe), contains('Riya Verma'));
      expect(BetText.pointsMoved(b, kBuddy), 'You lost your stake of 80 points.');
    });

    test('completed bet with missing resolution is "being finalised"', () {
      final b = completed();
      expect(BetText.resolution(b, kMe), contains('finalised'));
      expect(BetText.resultHeadline(b, kMe), 'Result pending');
      expect(BetText.pointsMoved(b, kMe), '');
    });

    test('non completed bets have no result text', () {
      final b = makeBet();
      expect(BetText.resolution(b, kMe), '');
      expect(BetText.resultHeadline(b, kMe), '');
    });

    test('winner is taken from winnerUid, never from the step counts', () {
      // The challenger has MORE steps, but the server says the opponent won.
      final b = completed(winner: kBuddy, resolution: BetResolution.higherSteps);
      expect(b.challengerSteps > b.opponentSteps, isTrue);
      expect(BetText.resultHeadline(b, kMe), 'Riya Verma won');
    });

    test('closed explanations', () {
      expect(BetText.closedExplanation(makeBet(status: BetStatus.cancelled), kMe),
          contains('You cancelled'));
      expect(BetText.closedExplanation(makeBet(status: BetStatus.cancelled), kBuddy),
          contains('Aarav Sharma cancelled'));
      expect(BetText.closedExplanation(makeBet(status: BetStatus.declined), kMe),
          contains('Riya Verma declined'));
      expect(BetText.closedExplanation(makeBet(status: BetStatus.declined), kBuddy),
          'You declined this bet.');
      expect(BetText.closedExplanation(makeBet(status: BetStatus.expired), kMe),
          contains('48 hours'));
    });

    test('duration formatting', () {
      expect(BetText.duration(const Duration(seconds: 20)), 'less than a minute');
      expect(BetText.duration(const Duration(minutes: 12)), '12m');
      expect(BetText.duration(const Duration(hours: 5, minutes: 12)), '5h 12m');
      expect(BetText.duration(const Duration(hours: 5)), '5h');
      expect(BetText.duration(const Duration(days: 2, hours: 5)), '2d 5h');
      expect(BetText.duration(const Duration(days: 2)), '2d');
    });

    test('countdown by status', () {
      final pending = makeBet(expiresAt: kNow.add(const Duration(hours: 47, minutes: 30)));
      expect(BetText.countdown(pending, kNow), 'Expires in 1d 23h');
      expect(BetText.countdown(makeBet(expiresAt: kNow.subtract(const Duration(minutes: 1))), kNow),
          contains('Past the 48 hour limit'));
      final start = kNow.add(const Duration(hours: 12));
      final upcoming = makeBet(
          status: BetStatus.active, startAt: start, endAt: start.add(const Duration(days: 7)));
      expect(BetText.countdown(upcoming, kNow), 'Starts in 12h');
      expect(BetText.countdown(activeBet(), kNow), 'Ends in 5d 12h');
      final ended = makeBet(
          status: BetStatus.active,
          startAt: kNow.subtract(const Duration(days: 8)),
          endAt: kNow.subtract(const Duration(hours: 1)));
      expect(BetText.countdown(ended, kNow), contains('final result is being confirmed'));
      expect(BetText.countdown(makeBet(status: BetStatus.completed), kNow), isNull);
      expect(BetText.countdown(makeBet(status: BetStatus.cancelled), kNow), isNull);
    });
  });

  group('BetSegment', () {
    final all = [
      makeBet(id: 'p', status: BetStatus.pending),
      makeBet(id: 'a', status: BetStatus.active),
      makeBet(id: 'c', status: BetStatus.completed),
      makeBet(id: 'x1', status: BetStatus.cancelled),
      makeBet(id: 'x2', status: BetStatus.declined),
      makeBet(id: 'x3', status: BetStatus.expired),
    ];
    List<String> ids(BetSegment s) => [for (final b in all.where(s.contains)) b.id];

    test('filters', () {
      expect(ids(BetSegment.pending), ['p']);
      expect(ids(BetSegment.active), ['a']);
      expect(ids(BetSegment.completed), ['c']);
      expect(ids(BetSegment.closed), ['x1', 'x2', 'x3']);
      expect(ids(BetSegment.history), hasLength(6));
    });
  });

  group('LedgerText', () {
    test('titles', () {
      expect(LedgerText.title(ledger('1', LedgerType.reserve)), 'Stake reserved for a step bet');
      expect(LedgerText.title(ledger('1', LedgerType.release)), 'Stake released');
      expect(LedgerText.title(ledger('1', LedgerType.betWin)), 'Won a step bet');
      expect(LedgerText.title(ledger('1', LedgerType.betLoss)), 'Lost a step bet');
      expect(LedgerText.title(ledger('1', LedgerType.reward, refType: 'DAILY_GOAL')), 'Daily goal reward');
      expect(LedgerText.title(ledger('1', LedgerType.reward, refType: 'STREAK')), 'Streak reward');
      expect(LedgerText.title(ledger('1', LedgerType.reward, refType: 'BADGE')), 'Badge reward');
      expect(LedgerText.title(ledger('1', LedgerType.reward, refType: 'CHALLENGE')), 'Challenge reward');
      expect(LedgerText.title(ledger('1', LedgerType.adjustment, refType: 'ADMIN')), 'Points adjustment');
    });
    test('amounts', () {
      expect(LedgerText.amount(ledger('1', LedgerType.reserve, delta: -50, reservedDelta: 50)), '-50');
      expect(LedgerText.amount(ledger('1', LedgerType.betWin, delta: 1100, reservedDelta: -500)), '+1,100');
      expect(LedgerText.amount(ledger('1', LedgerType.betLoss, delta: 0, reservedDelta: -50)),
          '-50 reserved');
      expect(LedgerText.amount(ledger('1', LedgerType.adjustment)), '0');
      expect(LedgerText.caption(ledger('1', LedgerType.reserve)), 'moved to reserved');
      expect(LedgerText.caption(ledger('1', LedgerType.reward)), isNull);
    });
  });

  group('BetErrors.friendly', () {
    String msg(String code, String reason) =>
        BetErrors.friendly(AppException.fromCallable(code: code, details: {'reason': reason}));

    test('maps the server reasons', () {
      expect(msg('failed-precondition', 'INSUFFICIENT_POINTS'), contains('enough available points'));
      expect(msg('failed-precondition', 'NOT_BUDDIES'), contains('accepted buddy'));
      expect(msg('failed-precondition', 'BET_NOT_PENDING'), contains('no longer pending'));
      expect(msg('failed-precondition', 'BET_EXPIRED'), contains('expired'));
      expect(msg('invalid-argument', 'CANNOT_BET_SELF'), contains('yourself'));
      expect(msg('permission-denied', 'NOT_BET_OPPONENT'), contains('invited buddy'));
      expect(msg('permission-denied', 'NOT_BET_CHALLENGER'), contains('created the bet'));
      expect(msg('not-found', 'BET_NOT_FOUND'), contains('could not find'));
      expect(msg('failed-precondition', 'OPPONENT_NOT_ACTIVE'), contains('cannot join'));
    });
    test('duplicates and network errors', () {
      expect(BetErrors.friendly(AppException.fromCallable(code: 'already-exists')),
          contains('already have a matching bet'));
      expect(BetErrors.friendly(AppException.fromCallable(code: 'unavailable')),
          contains('Network problem'));
      expect(BetErrors.friendly(StateError('x')), contains('Something went wrong'));
    });
  });
}
