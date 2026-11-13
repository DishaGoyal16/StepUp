DateTime? _asTime(Object? v) {
  if (v is DateTime) return v.toUtc();
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
  return null;
}

/// A challenge the user finished (`challengeParticipants.status == COMPLETED`)
/// with the challenge's title read from `challenges/{id}`.
class CompletedChallenge {
  const CompletedChallenge({
    required this.challengeId,
    required this.title,
    this.type,
    this.completedAt,
  });

  final String challengeId;
  final String title;

  /// `INDIVIDUAL | BUDDY | INTER_HOSTEL | CAMPUS` when the challenge doc could be read.
  final String? type;
  final DateTime? completedAt;

  static DateTime? parseTime(Object? v) => _asTime(v);
}

/// One `virtualPointsLedger` entry (own, read-only). Used only for the short
/// "recent activity" preview on the profile; the full history lives in the
/// points ledger screen.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.delta,
    required this.type,
    this.note = '',
    this.createdAt,
  });

  factory LedgerEntry.fromMap(String id, Map<String, dynamic> m) => LedgerEntry(
        id: id,
        delta: (m['delta'] as num?)?.toInt() ?? 0,
        type: (m['type'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        createdAt: _asTime(m['createdAt']),
      );

  final String id;
  final int delta;

  /// `RESERVE | RELEASE | BET_WIN | BET_LOSS | REWARD | ADJUSTMENT`.
  final String type;
  final String note;
  final DateTime? createdAt;

  /// Short human label for [type].
  String get label => switch (type) {
        'RESERVE' => 'Stake reserved',
        'RELEASE' => 'Stake released',
        'BET_WIN' => 'Bet won',
        'BET_LOSS' => 'Bet lost',
        'REWARD' => 'Reward',
        'ADJUSTMENT' => 'Adjustment',
        _ => 'Points',
      };
}

/// The user's position on the campus weekly board (`getLeaderboard`).
class CampusRank {
  const CampusRank({required this.rank, required this.value});

  final int rank;

  /// Verified steps this week.
  final int value;
}
