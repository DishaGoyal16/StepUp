/// Models of the step-bet feature (virtual points only - no currency).
///
/// Pure Dart: Firestore `Timestamp`s must already be converted to [DateTime]
/// (or epoch millis) by the data layer. Everything in here is READ-ONLY on the
/// client: winners, step totals and points are decided by the server.
library;

DateTime? _dt(Object? v) {
  if (v is DateTime) return v.toUtc();
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
  return null;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

String _str(Object? v) => v is String ? v : '';

/// `stepBets.status`.
enum BetStatus {
  pending('PENDING', 'Pending'),
  active('ACTIVE', 'Active'),
  declined('DECLINED', 'Declined'),
  cancelled('CANCELLED', 'Cancelled'),
  expired('EXPIRED', 'Expired'),
  completed('COMPLETED', 'Completed'),
  unknown('UNKNOWN', 'Unknown');

  const BetStatus(this.wire, this.label);

  final String wire;
  final String label;

  static BetStatus fromWire(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return BetStatus.unknown;
  }

  /// Cancelled, declined or expired: the bet never started and any reserved
  /// stake went back to the challenger.
  bool get closedWithoutPlay =>
      this == BetStatus.cancelled || this == BetStatus.declined || this == BetStatus.expired;
}

/// `stepBets.resolution` (set by the server when a bet is settled).
enum BetResolution {
  higherSteps('HIGHER_STEPS'),
  onlyOneReachedTarget('ONLY_ONE_REACHED_TARGET'),
  refundNoneReached('REFUND_NONE_REACHED'),
  refundTie('REFUND_TIE');

  const BetResolution(this.wire);

  final String wire;

  static BetResolution? fromWire(Object? v) {
    for (final r in values) {
      if (r.wire == v) return r;
    }
    return null;
  }

  bool get isRefund => this == refundNoneReached || this == refundTie;
}

/// A step bet between two accepted buddies (`stepBets/{betId}`).
class StepBet {
  const StepBet({
    required this.id,
    required this.challengerUid,
    required this.opponentUid,
    required this.challengerName,
    required this.opponentName,
    required this.targetSteps,
    required this.durationDays,
    required this.stakePoints,
    required this.status,
    this.startAt,
    this.endAt,
    this.challengerSteps = 0,
    this.opponentSteps = 0,
    this.winnerUid,
    this.resolution,
    this.createdAt,
    this.respondedAt,
    this.settledAt,
    this.expiresAt,
  });

  factory StepBet.fromMap(String id, Map<String, dynamic> m) => StepBet(
        id: id,
        challengerUid: _str(m['challengerUid']),
        opponentUid: _str(m['opponentUid']),
        challengerName: _str(m['challengerName']),
        opponentName: _str(m['opponentName']),
        targetSteps: _int(m['targetSteps']),
        durationDays: _int(m['durationDays']),
        stakePoints: _int(m['stakePoints']),
        status: BetStatus.fromWire(m['status']),
        startAt: _dt(m['startAt']),
        endAt: _dt(m['endAt']),
        challengerSteps: _int(m['challengerSteps']),
        opponentSteps: _int(m['opponentSteps']),
        winnerUid: m['winnerUid'] is String && (m['winnerUid'] as String).isNotEmpty
            ? m['winnerUid'] as String
            : null,
        resolution: BetResolution.fromWire(m['resolution']),
        createdAt: _dt(m['createdAt']),
        respondedAt: _dt(m['respondedAt']),
        settledAt: _dt(m['settledAt']),
        expiresAt: _dt(m['expiresAt']),
      );

  final String id;
  final String challengerUid;
  final String opponentUid;
  final String challengerName;
  final String opponentName;
  final int targetSteps;
  final int durationDays;

  /// Virtual points each side stakes.
  final int stakePoints;
  final BetStatus status;

  /// Window `[startAt, endAt)`, day aligned in IST. `null` until accepted.
  final DateTime? startAt;
  final DateTime? endAt;

  /// Verified steps inside the window (maintained by the server).
  final int challengerSteps;
  final int opponentSteps;

  /// `null` on a draw / refund and while the bet is not settled.
  final String? winnerUid;
  final BetResolution? resolution;
  final DateTime? createdAt;
  final DateTime? respondedAt;
  final DateTime? settledAt;
  final DateTime? expiresAt;

  bool involves(String uid) => uid == challengerUid || uid == opponentUid;
  bool isChallenger(String uid) => uid == challengerUid;
  bool isOpponent(String uid) => uid == opponentUid;

  /// Uid of the other participant as seen by [uid].
  String otherUid(String uid) => uid == challengerUid ? opponentUid : challengerUid;

  String nameOf(String uid) => uid == challengerUid ? challengerName : opponentName;

  /// Name of the other participant as seen by [uid].
  String otherNameOf(String uid) => nameOf(otherUid(uid));

  int stepsOf(String uid) => uid == challengerUid ? challengerSteps : opponentSteps;

  /// Verified steps of [uid] relative to the target, clamped to 0..1.
  double progressOf(String uid) {
    if (targetSteps <= 0) return 0;
    return (stepsOf(uid) / targetSteps).clamp(0.0, 1.0);
  }

  bool reachedTarget(String uid) => targetSteps > 0 && stepsOf(uid) >= targetSteps;

  /// Settled without a winner (refund): server `winnerUid` is empty.
  bool get isRefund => status == BetStatus.completed && winnerUid == null;

  /// Total virtual points at stake (both stakes).
  int get potPoints => stakePoints * 2;

  /// Last IST day of the window (the instant just before [endAt]).
  DateTime? get lastDayInstant => endAt?.subtract(const Duration(milliseconds: 1));

  /// Sort key for lists: newest first; bets whose server timestamp is not
  /// resolved yet (null) are treated as newest.
  DateTime get sortKey => createdAt ?? DateTime.utc(9999);
}

/// `virtualPointsLedger.type`.
enum LedgerType {
  reserve('RESERVE'),
  release('RELEASE'),
  betWin('BET_WIN'),
  betLoss('BET_LOSS'),
  reward('REWARD'),
  adjustment('ADJUSTMENT'),
  unknown('UNKNOWN');

  const LedgerType(this.wire);

  final String wire;

  static LedgerType fromWire(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return LedgerType.unknown;
  }
}

/// One own `virtualPointsLedger/{entryId}` document.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.refType,
    required this.refId,
    required this.delta,
    this.reservedDelta = 0,
    this.balanceAfter = 0,
    this.reservedAfter = 0,
    this.note = '',
    this.createdAt,
  });

  factory LedgerEntry.fromMap(String id, Map<String, dynamic> m) => LedgerEntry(
        id: id,
        type: LedgerType.fromWire(m['type']),
        refType: _str(m['refType']),
        refId: _str(m['refId']),
        delta: _int(m['delta']),
        reservedDelta: _int(m['reservedDelta']),
        balanceAfter: _int(m['balanceAfter']),
        reservedAfter: _int(m['reservedAfter']),
        note: _str(m['note']),
        createdAt: _dt(m['createdAt']),
      );

  final String id;
  final LedgerType type;

  /// `BET|CHALLENGE|DAILY_GOAL|STREAK|BADGE|ADMIN`
  final String refType;
  final String refId;

  /// Change of the AVAILABLE balance (signed).
  final int delta;

  /// Change of the RESERVED balance (signed); 0 on older documents.
  final int reservedDelta;
  final int balanceAfter;
  final int reservedAfter;
  final String note;
  final DateTime? createdAt;

  bool get isBetEntry => refType == 'BET' && refId.isNotEmpty;
}

/// One page of the ledger plus the opaque cursor for the next page.
class LedgerPage {
  const LedgerPage({required this.entries, this.cursor, this.hasMore = false});

  final List<LedgerEntry> entries;

  /// Opaque: pass back to `fetchLedger(cursor:)` to get the following page.
  final Object? cursor;
  final bool hasMore;
}

/// Own points as stored on `users/{uid}`: `pointsBalance` is AVAILABLE,
/// `pointsReserved` is locked in open bets.
class PointsBalance {
  const PointsBalance({required this.available, required this.reserved});

  static const PointsBalance zero = PointsBalance(available: 0, reserved: 0);

  final int available;
  final int reserved;

  int get total => available + reserved;

  @override
  bool operator ==(Object other) =>
      other is PointsBalance && other.available == available && other.reserved == reserved;

  @override
  int get hashCode => Object.hash(available, reserved);
}

/// Result of `createStepBet`. [duplicate] is true when the server recognised
/// the request id and returned the bet created by an earlier identical call.
class CreatedBet {
  const CreatedBet({required this.betId, this.duplicate = false});

  final String betId;
  final bool duplicate;
}
