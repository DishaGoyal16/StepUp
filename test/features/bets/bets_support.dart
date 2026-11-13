import 'package:stepup/data/bets/bet_models.dart';
import 'package:stepup/domain/user_profile.dart';

/// Fixed "now" used by the harness clock: 2026-11-13 06:00 UTC = 11:30 IST.
final DateTime kNow = DateTime.utc(2026, 11, 13, 6);

const String kMe = 'me';
const String kBuddy = 'buddy1';

StepBet makeBet({
  String id = 'bet1',
  String challengerUid = kMe,
  String opponentUid = kBuddy,
  String challengerName = 'Aarav Sharma',
  String opponentName = 'Riya Verma',
  int target = 10000,
  int days = 7,
  int stake = 50,
  BetStatus status = BetStatus.pending,
  DateTime? startAt,
  DateTime? endAt,
  int challengerSteps = 0,
  int opponentSteps = 0,
  String? winnerUid,
  BetResolution? resolution,
  DateTime? createdAt,
  DateTime? settledAt,
  DateTime? expiresAt,
}) =>
    StepBet(
      id: id,
      challengerUid: challengerUid,
      opponentUid: opponentUid,
      challengerName: challengerName,
      opponentName: opponentName,
      targetSteps: target,
      durationDays: days,
      stakePoints: stake,
      status: status,
      startAt: startAt,
      endAt: endAt,
      challengerSteps: challengerSteps,
      opponentSteps: opponentSteps,
      winnerUid: winnerUid,
      resolution: resolution,
      createdAt: createdAt ?? kNow.subtract(const Duration(hours: 2)),
      settledAt: settledAt,
      expiresAt: expiresAt ?? kNow.add(const Duration(hours: 46)),
    );

/// Active bet: started 2026-11-12 00:00 IST, 7 days.
StepBet activeBet({
  String id = 'act1',
  int challengerSteps = 4200,
  int opponentSteps = 6100,
  String challengerUid = kMe,
  String opponentUid = kBuddy,
}) {
  final start = DateTime.utc(2026, 11, 11, 18, 30); // 12 Nov 00:00 IST
  return makeBet(
    id: id,
    status: BetStatus.active,
    challengerUid: challengerUid,
    opponentUid: opponentUid,
    startAt: start,
    endAt: start.add(const Duration(days: 7)),
    challengerSteps: challengerSteps,
    opponentSteps: opponentSteps,
    createdAt: kNow.subtract(const Duration(days: 2)),
  );
}

LedgerEntry ledger(
  String id,
  LedgerType type, {
  int delta = 0,
  int reservedDelta = 0,
  String refType = 'BET',
  String refId = 'bet1',
  int balanceAfter = 100,
  int reservedAfter = 0,
  String note = '',
  DateTime? at,
}) =>
    LedgerEntry(
      id: id,
      type: type,
      refType: refType,
      refId: refId,
      delta: delta,
      reservedDelta: reservedDelta,
      balanceAfter: balanceAfter,
      reservedAfter: reservedAfter,
      note: note,
      createdAt: at ?? kNow,
    );

UserProfile profileWithPoints(String uid, {int available = 500, int reserved = 50}) => UserProfile(
      uid: uid,
      displayName: 'Aarav Sharma',
      email: 'student@thapar.edu',
      hostelId: 'agira',
      pointsBalance: available,
      pointsReserved: reserved,
    );
