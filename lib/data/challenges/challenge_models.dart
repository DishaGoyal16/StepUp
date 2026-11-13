/// Pure data models of the challenges feature (no Firebase types).
///
/// Mirrors `challenges`, `challengeParticipants`, `challengeResults` and the
/// `getChallengeLeaderboard` result in DATABASE_SCHEMA.md. The client only
/// ever READS these; progress, winners and rewards are computed by the server
/// from verified steps.
library;

DateTime? _dt(Object? v) {
  if (v is DateTime) return v.toUtc();
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
  if (v is String) return DateTime.tryParse(v)?.toUtc();
  return null;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

List<String> _strings(Object? v) =>
    v is Iterable ? v.whereType<String>().toList(growable: false) : const [];

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? {for (final e in v.entries) e.key.toString(): e.value} : const {};

enum ChallengeType {
  individual('INDIVIDUAL'),
  buddy('BUDDY'),
  interHostel('INTER_HOSTEL'),
  campus('CAMPUS');

  const ChallengeType(this.wire);
  final String wire;

  static ChallengeType? fromWire(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

enum ChallengeMetric {
  totalSteps('TOTAL_STEPS'),
  dailyTargetDays('DAILY_TARGET_DAYS'),
  streakDays('STREAK_DAYS');

  const ChallengeMetric(this.wire);
  final String wire;

  static ChallengeMetric? fromWire(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

enum ChallengeStatus {
  /// Buddy invite not accepted yet.
  pending('PENDING'),
  upcoming('UPCOMING'),
  active('ACTIVE'),
  completed('COMPLETED'),
  cancelled('CANCELLED');

  const ChallengeStatus(this.wire);
  final String wire;

  static ChallengeStatus? fromWire(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }

  /// Open for joining / still running (the discovery query statuses).
  bool get isOpen => this == upcoming || this == active;
}

enum ParticipantStatus {
  invited('INVITED'),
  joined('JOINED'),
  left('LEFT'),
  completed('COMPLETED');

  const ParticipantStatus(this.wire);
  final String wire;

  static ParticipantStatus? fromWire(Object? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

enum WindowMode { fixed, rolling }

enum HostelAggregation { averagePerParticipant, total }

/// A `challenges/{challengeId}` document.
class Challenge {
  const Challenge({
    required this.id,
    required this.type,
    required this.title,
    required this.metric,
    required this.target,
    required this.status,
    this.description = '',
    this.dailyTarget,
    this.windowMode = WindowMode.fixed,
    this.startAt,
    this.endAt,
    this.durationDays,
    this.createdBy,
    this.hostelIds = const [],
    this.hostelAggregation = HostelAggregation.averagePerParticipant,
    this.maxParticipants,
    this.participantCount = 0,
    this.rewardPoints = 0,
    this.isTemplate = false,
    this.winnerUid,
    this.winnerHostelId,
    this.finalizedAt,
    this.participantUids = const [],
  });

  /// Returns `null` for documents with an unknown type / metric / status so
  /// that one bad document never breaks a list.
  static Challenge? tryFromMap(String id, Map<String, dynamic> m) {
    final type = ChallengeType.fromWire(m['type']);
    final metric = ChallengeMetric.fromWire(m['metric']);
    final status = ChallengeStatus.fromWire(m['status']);
    if (type == null || metric == null || status == null) return null;
    final start = _dt(m['startAt']);
    final end = _dt(m['endAt']);
    return Challenge(
      id: id,
      type: type,
      title: (m['title'] as String?)?.trim().isNotEmpty == true ? (m['title'] as String).trim() : 'Challenge',
      description: (m['description'] as String?) ?? '',
      metric: metric,
      target: _int(m['target']),
      dailyTarget: _intOrNull(m['dailyTarget']),
      windowMode: m['windowMode'] == 'ROLLING'
          ? WindowMode.rolling
          : (m['windowMode'] == 'FIXED' || start != null ? WindowMode.fixed : WindowMode.rolling),
      startAt: start,
      endAt: end,
      durationDays: _intOrNull(m['durationDays']),
      status: status,
      createdBy: m['createdBy'] as String?,
      hostelIds: _strings(m['hostelIds']),
      hostelAggregation: m['hostelAggregation'] == 'TOTAL'
          ? HostelAggregation.total
          : HostelAggregation.averagePerParticipant,
      maxParticipants: _intOrNull(m['maxParticipants']),
      participantCount: _int(m['participantCount']),
      rewardPoints: _int(m['rewardPoints']),
      isTemplate: m['isTemplate'] == true,
      winnerUid: m['winnerUid'] as String?,
      winnerHostelId: m['winnerHostelId'] as String?,
      finalizedAt: _dt(m['finalizedAt']),
      participantUids: _strings(m['participantUids']),
    );
  }

  final String id;
  final ChallengeType type;
  final String title;
  final String description;
  final ChallengeMetric metric;

  /// Steps for [ChallengeMetric.totalSteps]; days for the other two metrics.
  final int target;

  /// Steps per day for the two day-based metrics.
  final int? dailyTarget;
  final WindowMode windowMode;
  final DateTime? startAt;

  /// Exclusive end (IST midnight after the last day).
  final DateTime? endAt;
  final int? durationDays;
  final ChallengeStatus status;
  final String? createdBy;
  final List<String> hostelIds;
  final HostelAggregation hostelAggregation;
  final int? maxParticipants;
  final int participantCount;
  final int rewardPoints;
  final bool isTemplate;
  final String? winnerUid;
  final String? winnerHostelId;
  final DateTime? finalizedAt;
  final List<String> participantUids;

  bool get isRolling => windowMode == WindowMode.rolling;
  bool get isFull => maxParticipants != null && maxParticipants! > 0 && participantCount >= maxParticipants!;

  /// Rough "how hard" key used only to order the individual catalogue
  /// (shortest window first, then fewest steps).
  int get difficultyKey {
    final steps = switch (metric) {
      ChallengeMetric.totalSteps => target,
      ChallengeMetric.dailyTargetDays || ChallengeMetric.streakDays => (dailyTarget ?? 0) * target,
    };
    return (durationDays ?? 0) * 100000000 + steps;
  }
}

/// A `challengeParticipants/{challengeId}_{uid}` document (own document only;
/// other students' progress is only visible through the leaderboard callable).
class ChallengeParticipation {
  const ChallengeParticipation({
    required this.challengeId,
    required this.uid,
    required this.status,
    this.displayName = '',
    this.photoUrl,
    this.hostelId,
    this.joinedAt,
    this.windowStart,
    this.windowEnd,
    this.progress = 0,
    this.progressUpdatedAt,
    this.completedAt,
    this.rewardPaid = false,
  });

  static ChallengeParticipation? tryFromMap(Map<String, dynamic> m) {
    final status = ParticipantStatus.fromWire(m['status']);
    final challengeId = m['challengeId'];
    final uid = m['uid'];
    if (status == null || challengeId is! String || uid is! String) return null;
    return ChallengeParticipation(
      challengeId: challengeId,
      uid: uid,
      status: status,
      displayName: (m['displayName'] as String?) ?? '',
      photoUrl: m['photoUrl'] as String?,
      hostelId: m['hostelId'] as String?,
      joinedAt: _dt(m['joinedAt']),
      windowStart: m['windowStart'] as String?,
      windowEnd: m['windowEnd'] as String?,
      progress: _int(m['progress']),
      progressUpdatedAt: _dt(m['progressUpdatedAt']),
      completedAt: _dt(m['completedAt']),
      rewardPaid: m['rewardPaid'] == true,
    );
  }

  final String challengeId;
  final String uid;
  final ParticipantStatus status;
  final String displayName;
  final String? photoUrl;
  final String? hostelId;
  final DateTime? joinedAt;

  /// ROLLING challenges: inclusive `YYYYMMDD` window set at join.
  final String? windowStart;
  final String? windowEnd;
  final int progress;
  final DateTime? progressUpdatedAt;
  final DateTime? completedAt;
  final bool rewardPaid;

  bool get isJoined => status == ParticipantStatus.joined;
  bool get isCompleted => status == ParticipantStatus.completed;

  /// Joined or completed: has a progress value worth showing.
  bool get hasProgress => isJoined || isCompleted;
}

/// One row of `getChallengeLeaderboard`: a student, or a hostel for
/// INTER_HOSTEL challenges.
class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.id,
    required this.isHostel,
    required this.name,
    required this.value,
    required this.progressPct,
    this.photoUrl,
    this.hostelId,
    this.participants,
    this.total,
  });

  factory LeaderboardRow.fromMap(Map<String, dynamic> m) {
    final uid = m['uid'];
    final hostelId = m['hostelId'];
    final isHostel = uid is! String && hostelId is String;
    return LeaderboardRow(
      rank: _int(m['rank']),
      id: uid is String ? uid : (hostelId is String ? hostelId : ''),
      isHostel: isHostel,
      name: (m['name'] as String?) ?? '',
      photoUrl: m['photoUrl'] as String?,
      hostelId: hostelId is String ? hostelId : null,
      value: _int(m['value']),
      progressPct: _int(m['progressPct']).clamp(0, 100),
      participants: _intOrNull(m['participants']),
      total: _intOrNull(m['total']),
    );
  }

  final int rank;

  /// uid for students, hostelId for hostel rows.
  final String id;
  final bool isHostel;
  final String name;
  final String? photoUrl;

  /// A student's hostel (student rows) or the hostel itself (hostel rows).
  final String? hostelId;
  final int value;
  final int progressPct;

  /// Hostel rows: students who contributed.
  final int? participants;

  /// Hostel rows: total verified progress of the hostel.
  final int? total;
}

/// Result of `getChallengeLeaderboard`.
class ChallengeLeaderboard {
  const ChallengeLeaderboard({
    required this.entries,
    required this.myValue,
    required this.metricLabel,
    this.myRank,
  });

  factory ChallengeLeaderboard.fromMap(Map<String, dynamic> m) {
    final me = _asMap(m['me']);
    final raw = m['entries'];
    return ChallengeLeaderboard(
      entries: [
        if (raw is Iterable)
          for (final e in raw)
            if (e is Map) LeaderboardRow.fromMap(_asMap(e)),
      ],
      myRank: _intOrNull(me['rank']),
      myValue: _int(me['value']),
      metricLabel: (m['metricLabel'] as String?) ?? '',
    );
  }

  final List<LeaderboardRow> entries;

  /// `null` when I am not ranked (not participating).
  final int? myRank;
  final int myValue;
  final String metricLabel;
}

/// One row of the final ranking in `challengeResults/{id}.ranking`.
class RankedEntry {
  const RankedEntry({
    required this.rank,
    required this.name,
    required this.value,
    this.uid,
    this.hostelId,
  });

  factory RankedEntry.fromMap(Map<String, dynamic> m) => RankedEntry(
        rank: _int(m['rank']),
        uid: m['uid'] as String?,
        hostelId: m['hostelId'] as String?,
        name: (m['name'] as String?) ?? '',
        value: _int(m['value']),
      );

  final int rank;
  final String? uid;
  final String? hostelId;
  final String name;
  final int value;
}

/// A `challengeResults/{challengeId}` document (written by the server when a
/// challenge is finalized; the client never decides a winner).
class ChallengeResult {
  const ChallengeResult({
    required this.challengeId,
    required this.type,
    required this.ranking,
    this.winnerUid,
    this.winnerHostelId,
    this.participantCount = 0,
    this.finalizedAt,
    this.metricLabel = '',
  });

  static ChallengeResult? tryFromMap(String id, Map<String, dynamic> m) {
    final raw = m['ranking'];
    return ChallengeResult(
      challengeId: id,
      type: ChallengeType.fromWire(m['type']),
      winnerUid: m['winnerUid'] as String?,
      winnerHostelId: m['winnerHostelId'] as String?,
      ranking: [
        if (raw is Iterable)
          for (final e in raw)
            if (e is Map) RankedEntry.fromMap(_asMap(e)),
      ],
      participantCount: _int(m['participantCount']),
      finalizedAt: _dt(m['finalizedAt']),
      metricLabel: (m['metricLabel'] as String?) ?? '',
    );
  }

  final String challengeId;
  final ChallengeType? type;
  final String? winnerUid;
  final String? winnerHostelId;
  final List<RankedEntry> ranking;
  final int participantCount;
  final DateTime? finalizedAt;
  final String metricLabel;

  bool get hasWinner => winnerUid != null || winnerHostelId != null;

  /// Display name of the winner taken from the stored ranking, or `null`.
  String? get winnerName {
    for (final r in ranking) {
      if (winnerHostelId != null && r.hostelId == winnerHostelId) return r.name;
      if (winnerUid != null && r.uid == winnerUid) return r.name;
    }
    return null;
  }
}
