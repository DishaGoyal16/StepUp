import '../../core/errors/app_exception.dart';
import 'bet_rules.dart';

/// Friendly wording for the stable `details.reason` codes of the bet
/// callables (`functions/src/bets/bets.ts`). Falls back to the safe
/// [AppException.message].
abstract final class BetErrors {
  static String friendly(Object error) {
    if (error is! AppException) return 'Something went wrong. Please try again.';
    switch (error.reason) {
      case 'INSUFFICIENT_POINTS':
        return 'You do not have enough available points for this stake.';
      case 'NOT_BUDDIES':
        return 'You can only bet with an accepted buddy.';
      case 'OPPONENT_NOT_ACTIVE':
        return 'That student cannot join step bets right now.';
      case 'CANNOT_BET_SELF':
        return 'You cannot bet against yourself.';
      case 'BET_NOT_PENDING':
        return 'This bet is no longer pending. It may already have been answered or cancelled.';
      case 'BET_EXPIRED':
        return 'This bet was not answered within ${BetLimits.expiryHours} hours and has expired.';
      case 'BET_NOT_FOUND':
        return 'We could not find this bet.';
      case 'NOT_BET_OPPONENT':
        return 'Only the invited buddy can accept or decline this bet.';
      case 'NOT_BET_CHALLENGER':
        return 'Only the person who created the bet can cancel it.';
    }
    if (error.code == 'already-exists') {
      return 'You already have a matching bet with this buddy.';
    }
    return error.message;
  }
}
