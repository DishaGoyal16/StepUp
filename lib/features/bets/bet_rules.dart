/// Pure rules, validation and wording for step bets. No Flutter, no Firebase.
///
/// Nothing here decides a winner or moves points: [BetText.resolution] only
/// DESCRIBES the `winnerUid` / `resolution` the server wrote.
library;

import 'package:intl/intl.dart';

import '../../data/bets/bet_models.dart';

/// Limits shared with the backend (`BET_LIMITS`, `adminSettings/global`).
abstract final class BetLimits {
  static const int minTarget = 1000;
  static const int maxTarget = 1000000;
  static const int minDays = 1;
  static const int maxDays = 30;
  static const int minStake = 10;
  static const int maxStake = 1000;

  /// Verified steps that can count per day (reward cap); a target above
  /// `days * maxVerifiedStepsPerDay` can never be reached.
  static const int maxVerifiedStepsPerDay = 20000;
  static const int expiryHours = 48;

  static const int defaultTarget = 10000;
  static const int defaultDays = 7;
  static const int defaultStake = 50;

  static int maxTargetFor(int days) {
    final reachable = days * maxVerifiedStepsPerDay;
    return reachable < maxTarget ? reachable : maxTarget;
  }
}

/// `12,345`.
String formatInt(int n) => NumberFormat.decimalPattern('en').format(n);

String pointsLabel(int n) => '${formatInt(n)} ${n == 1 ? 'point' : 'points'}';

/// Validation of the create-bet form. Each function returns an error message
/// or `null` when valid.
abstract final class BetValidator {
  /// Parses a whole positive number typed by the user ("12,000" / " 500 ").
  /// Returns `null` for empty, decimal, negative or non-numeric input.
  static int? parseWhole(String input) {
    final cleaned = input.trim().replaceAll(',', '').replaceAll(' ', '');
    if (cleaned.isEmpty || !RegExp(r'^\d{1,9}$').hasMatch(cleaned)) return null;
    return int.parse(cleaned);
  }

  static String? duration(int? days) {
    if (days == null) return 'Choose how many days the bet lasts.';
    if (days < BetLimits.minDays || days > BetLimits.maxDays) {
      return 'Duration must be between ${BetLimits.minDays} and ${BetLimits.maxDays} days.';
    }
    return null;
  }

  static String? target(int? steps, int? days) {
    if (steps == null) return 'Enter a whole number of steps.';
    if (steps < BetLimits.minTarget) {
      return 'Target must be at least ${formatInt(BetLimits.minTarget)} steps.';
    }
    final d = (days != null && duration(days) == null) ? days : BetLimits.maxDays;
    final max = BetLimits.maxTargetFor(d);
    if (steps > max) {
      return d == BetLimits.maxDays && max == BetLimits.maxTarget
          ? 'Target cannot be more than ${formatInt(max)} steps.'
          : 'Only up to ${formatInt(BetLimits.maxVerifiedStepsPerDay)} verified steps count per day, '
              'so the most you can ask for in $d ${d == 1 ? 'day' : 'days'} is ${formatInt(max)}.';
    }
    return null;
  }

  /// [available] is the AVAILABLE balance (`pointsBalance`), `null` while
  /// unknown (then only the fixed range is checked; the server re-checks).
  static String? stake(int? points, int? available) {
    if (points == null) return 'Enter a whole number of points.';
    if (points < BetLimits.minStake || points > BetLimits.maxStake) {
      return 'Stake must be between ${BetLimits.minStake} and ${formatInt(BetLimits.maxStake)} points.';
    }
    if (available != null && points > available) {
      return available < BetLimits.minStake
          ? 'You need at least ${BetLimits.minStake} available points to place a bet.'
          : 'You only have ${pointsLabel(available)} available.';
    }
    return null;
  }
}

/// All user-facing wording in one place (and unit-tested).
abstract final class BetText {
  static const String virtualPointsNotice =
      'Step bets are a friendly competition using VIRTUAL POINTS ONLY. '
      'No real money, no deposits and no withdrawals are involved, and '
      'joining or accepting a bet is always voluntary.';

  static const String virtualPointsShort =
      'Virtual points only - no real money. Joining is voluntary.';

  static const List<String> winnerRule = [
    'If both of you reach the target, the higher number of verified steps wins. '
        'An exact tie refunds both stakes.',
    'If only one of you reaches the target, that person wins.',
    'If nobody reaches the target, both stakes are refunded.',
    'Only verified genuine steps count. The winner receives both stakes (virtual points).',
  ];

  static const String expiry =
      'If your buddy does not respond within ${BetLimits.expiryHours} hours the bet '
      'expires and your stake is released.';

  static const String startRule =
      'The bet starts at the next midnight (IST) after your buddy accepts.';

  /// Short sentence used on the accept/cancel UI.
  static String reserveNotice(int stake) =>
      'Accepting reserves ${pointsLabel(stake)} of your available points until the bet is settled.';

  static String resolution(StepBet bet, String myUid) {
    final r = bet.resolution;
    if (bet.status != BetStatus.completed) return '';
    if (r == null) return 'The result is being finalised.';
    final winner = bet.winnerUid;
    String who(String uid) => uid == myUid ? 'You' : bet.nameOf(uid);
    switch (r) {
      case BetResolution.higherSteps:
        if (winner == null) return 'The result is being finalised.';
        return 'Both of you reached the target of ${formatInt(bet.targetSteps)} steps, '
            'and ${who(winner)} had more verified steps.';
      case BetResolution.onlyOneReachedTarget:
        if (winner == null) return 'The result is being finalised.';
        return 'Only ${who(winner)} reached the target of ${formatInt(bet.targetSteps)} steps.';
      case BetResolution.refundNoneReached:
        return 'Nobody reached the target of ${formatInt(bet.targetSteps)} steps, '
            'so both stakes were refunded.';
      case BetResolution.refundTie:
        return 'Both of you reached the target with exactly the same number of verified steps, '
            'so both stakes were refunded.';
    }
  }

  /// Headline of the result panel.
  static String resultHeadline(StepBet bet, String myUid) {
    if (bet.status != BetStatus.completed) return '';
    final w = bet.winnerUid;
    if (w == null) return bet.resolution == null ? 'Result pending' : 'Draw - stakes refunded';
    return w == myUid ? 'You won!' : '${bet.nameOf(w)} won';
  }

  /// Plain description of how the points moved (as recorded by the server).
  static String pointsMoved(StepBet bet, String myUid) {
    if (bet.status != BetStatus.completed) return '';
    final s = bet.stakePoints;
    final w = bet.winnerUid;
    if (w == null) {
      return bet.resolution == null
          ? ''
          : 'Both stakes of ${pointsLabel(s)} were returned.';
    }
    if (w == myUid) {
      return 'You received ${pointsLabel(s * 2)} (your stake back plus ${pointsLabel(s)} from '
          '${bet.otherNameOf(myUid)}).';
    }
    return 'You lost your stake of ${pointsLabel(s)}.';
  }

  /// Why a not-played bet ended, for the detail screen.
  static String closedExplanation(StepBet bet, String myUid) {
    switch (bet.status) {
      case BetStatus.cancelled:
        return bet.isChallenger(myUid)
            ? 'You cancelled this bet. Your stake of ${pointsLabel(bet.stakePoints)} was released.'
            : '${bet.challengerName} cancelled this bet before you answered.';
      case BetStatus.declined:
        return bet.isChallenger(myUid)
            ? '${bet.opponentName} declined this bet. Your stake of '
                '${pointsLabel(bet.stakePoints)} was released.'
            : 'You declined this bet.';
      case BetStatus.expired:
        return 'This bet was not answered within ${BetLimits.expiryHours} hours and expired. '
            'No points were lost.';
      default:
        return '';
    }
  }

  /// `2d 5h`, `5h 12m`, `12m`, `less than a minute`.
  static String duration(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    if (d.inDays >= 1) {
      final h = d.inHours % 24;
      return h == 0 ? '${d.inDays}d' : '${d.inDays}d ${h}h';
    }
    if (d.inHours >= 1) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
    }
    return '${d.inMinutes}m';
  }

  /// Live countdown line for a bet, or `null` when there is nothing to count.
  static String? countdown(StepBet bet, DateTime now) {
    switch (bet.status) {
      case BetStatus.pending:
        final e = bet.expiresAt;
        if (e == null) return null;
        return now.isBefore(e)
            ? 'Expires in ${duration(e.difference(now))}'
            : 'Past the ${BetLimits.expiryHours} hour limit - expiring';
      case BetStatus.active:
        final s = bet.startAt;
        final e = bet.endAt;
        if (s == null || e == null) return null;
        if (now.isBefore(s)) return 'Starts in ${duration(s.difference(now))}';
        if (now.isBefore(e)) return 'Ends in ${duration(e.difference(now))}';
        return 'Ended - the final result is being confirmed';
      default:
        return null;
    }
  }

  static String durationDays(int days) => '$days ${days == 1 ? 'day' : 'days'}';
}

/// Which list segment a bet belongs to.
enum BetSegment {
  pending('Pending'),
  active('Active'),
  completed('Completed'),
  closed('Cancelled/Declined/Expired'),
  history('History');

  const BetSegment(this.label);

  final String label;

  bool contains(StepBet b) => switch (this) {
        BetSegment.pending => b.status == BetStatus.pending,
        BetSegment.active => b.status == BetStatus.active,
        BetSegment.completed => b.status == BetStatus.completed,
        BetSegment.closed => b.status.closedWithoutPlay,
        BetSegment.history => true,
      };

  String get emptyTitle => switch (this) {
        BetSegment.pending => 'No pending bets',
        BetSegment.active => 'No active bets',
        BetSegment.completed => 'No completed bets yet',
        BetSegment.closed => 'Nothing cancelled, declined or expired',
        BetSegment.history => 'No bets yet',
      };
}

/// Ledger wording.
abstract final class LedgerText {
  static String title(LedgerEntry e) {
    switch (e.type) {
      case LedgerType.reserve:
        return 'Stake reserved for a step bet';
      case LedgerType.release:
        return 'Stake released';
      case LedgerType.betWin:
        return 'Won a step bet';
      case LedgerType.betLoss:
        return 'Lost a step bet';
      case LedgerType.reward:
        return switch (e.refType) {
          'DAILY_GOAL' => 'Daily goal reward',
          'STREAK' => 'Streak reward',
          'BADGE' => 'Badge reward',
          'CHALLENGE' => 'Challenge reward',
          _ => 'Reward',
        };
      case LedgerType.adjustment:
        return 'Points adjustment';
      case LedgerType.unknown:
        return 'Points update';
    }
  }

  /// Signed amount shown on the right of a ledger row.
  static String amount(LedgerEntry e) {
    String signed(int n) => n > 0 ? '+${formatInt(n)}' : (n < 0 ? '-${formatInt(-n)}' : '0');
    if (e.delta != 0) return signed(e.delta);
    if (e.reservedDelta != 0) return '${signed(e.reservedDelta)} reserved';
    return '0';
  }

  /// Small caption below the amount.
  static String? caption(LedgerEntry e) => switch (e.type) {
        LedgerType.reserve => 'moved to reserved',
        LedgerType.release => 'moved back to available',
        LedgerType.betLoss => 'from reserved',
        _ => null,
      };
}
