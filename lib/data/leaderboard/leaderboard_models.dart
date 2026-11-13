/// Models of the `getLeaderboard` callable (DATABASE_SCHEMA.md). Pure Dart.
///
/// Everything here is a read-only view of what the server returned: ranks and
/// values are computed by the backend from VERIFIED steps only; the client
/// never ranks or aggregates anything. Parsing is deliberately tolerant of
/// missing optional fields.
library;

/// Which board is requested.
enum LeaderboardScope {
  campus('CAMPUS', 'Campus'),
  myHostel('MY_HOSTEL', 'My hostel'),
  hostels('HOSTELS', 'Hostels'),
  buddies('BUDDIES', 'Buddies');

  const LeaderboardScope(this.wire, this.label);

  final String wire;
  final String label;
}

/// Time window of a board.
enum LeaderboardPeriod {
  daily('DAILY', 'Daily'),
  weekly('WEEKLY', 'Weekly'),
  monthly('MONTHLY', 'Monthly'),
  allTime('ALL_TIME', 'All-time');

  const LeaderboardPeriod(this.wire, this.label);

  final String wire;
  final String label;
}

/// Ranking metric of the HOSTELS board.
enum HostelMetric {
  average('AVERAGE', 'Average per participant'),
  total('TOTAL', 'Total verified steps');

  const HostelMetric(this.wire, this.label);

  final String wire;
  final String label;
}

/// What the user selected: scope + period (+ hostel metric on the Hostels
/// board). Value-equal so it can be compared with a response's query.
class LeaderboardQuery {
  const LeaderboardQuery({
    required this.scope,
    required this.period,
    this.hostelMetric = HostelMetric.average,
  });

  final LeaderboardScope scope;
  final LeaderboardPeriod period;
  final HostelMetric hostelMetric;

  bool get isHostelBoard => scope == LeaderboardScope.hostels;

  /// Callable payload. `hostelMetric` is only sent for the Hostels board.
  Map<String, dynamic> toParams({required int limit}) => {
        'scope': scope.wire,
        'period': period.wire,
        if (isHostelBoard) 'hostelMetric': hostelMetric.wire,
        'limit': limit,
      };

  @override
  bool operator ==(Object other) =>
      other is LeaderboardQuery &&
      other.scope == scope &&
      other.period == period &&
      (!isHostelBoard || other.hostelMetric == hostelMetric);

  @override
  int get hashCode => Object.hash(scope, period, isHostelBoard ? hostelMetric : null);

  @override
  String toString() => 'LeaderboardQuery(${scope.wire}, ${period.wire}, ${hostelMetric.wire})';
}

num? _num(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String) {
    final n = num.tryParse(v.trim());
    return (n != null && n.isFinite) ? n : null;
  }
  return null;
}

String? _str(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

/// Accepts epoch millis / seconds, ISO strings, [DateTime] and the
/// `{_seconds,_nanoseconds}` / `{seconds,nanoseconds}` timestamp maps that
/// callables produce.
DateTime? parseServerTime(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toUtc();
  if (v is num) {
    final n = v.toInt();
    // Below 1e11 it cannot be milliseconds (that would be before 1973).
    return DateTime.fromMillisecondsSinceEpoch(n < 100000000000 ? n * 1000 : n, isUtc: true);
  }
  if (v is String) return DateTime.tryParse(v)?.toUtc();
  if (v is Map) {
    final s = _num(v['_seconds'] ?? v['seconds']);
    if (s == null) return null;
    final ns = _num(v['_nanoseconds'] ?? v['nanoseconds']) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(
      s.toInt() * 1000 + ns ~/ 1000000,
      isUtc: true,
    );
  }
  return null;
}

/// One ranked row: a student (CAMPUS / MY_HOSTEL / BUDDIES) or a hostel
/// (HOSTELS). [value] is always the metric the board is ranked by.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.id,
    required this.name,
    required this.value,
    this.photoUrl,
    this.hostelId,
    this.participants,
    this.total,
    this.average,
    this.isHostel = false,
  });

  /// Parses a student row `{rank, uid, name, photoUrl, hostelId, value}` or a
  /// hostel row `{rank, hostelId, name, value, participants, total, average}`.
  /// Returns null when [raw] is not a map. [index] supplies a fallback rank.
  static LeaderboardEntry? tryParse(
    Object? raw, {
    required bool isHostel,
    required int index,
  }) {
    if (raw is! Map) return null;
    final m = {for (final e in raw.entries) e.key.toString(): e.value};
    final rank = _num(m['rank'])?.toInt();
    final hostelId = _str(m['hostelId']);
    final id = isHostel ? (hostelId ?? _str(m['id']) ?? '') : (_str(m['uid']) ?? _str(m['id']) ?? '');
    final name = _str(m['name']) ??
        _str(m['displayName']) ??
        (isHostel ? (hostelId ?? 'Hostel') : 'Student');
    final total = _num(m['total'] ?? m['totalVerifiedSteps']);
    final average = _num(m['average'] ?? m['averagePerParticipant']);
    return LeaderboardEntry(
      rank: (rank != null && rank > 0) ? rank : index + 1,
      id: id,
      name: name,
      photoUrl: _str(m['photoUrl']),
      hostelId: hostelId,
      value: _num(m['value']) ?? 0,
      participants: _num(m['participants'])?.toInt(),
      total: total,
      average: average,
      isHostel: isHostel,
    );
  }

  final int rank;

  /// `uid` for students, `hostelId` for hostels.
  final String id;
  final String name;
  final String? photoUrl;

  /// Student rows: the student's hostel (only present when they show it).
  /// Hostel rows: the hostel itself.
  final String? hostelId;

  /// The ranking metric (verified steps, or per-participant average / total
  /// on the Hostels board).
  final num value;

  // Hostel rows only (all optional on the wire).
  final int? participants;
  final num? total;
  final num? average;
  final bool isHostel;
}

/// The caller's own standing (`me`). [rank] is null when the user is not
/// ranked (no verified steps in the period, or hidden from leaderboards).
class LeaderboardMe {
  const LeaderboardMe({this.rank, this.value});

  static LeaderboardMe? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final rank = _num(raw['rank'])?.toInt();
    return LeaderboardMe(
      rank: (rank != null && rank > 0) ? rank : null,
      value: _num(raw['value']),
    );
  }

  final int? rank;
  final num? value;
}

/// A full `getLeaderboard` response.
class LeaderboardResult {
  const LeaderboardResult({
    required this.query,
    required this.entries,
    this.me,
    this.metricLabel,
    this.periodKey,
    this.updatedAt,
  });

  factory LeaderboardResult.fromMap(Map<String, dynamic> m, {required LeaderboardQuery query}) {
    final raw = m['entries'];
    final parsed = <LeaderboardEntry>[];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final e = LeaderboardEntry.tryParse(raw[i], isHostel: query.isHostelBoard, index: i);
        if (e != null) parsed.add(e);
      }
    }
    // Presentation order only (the server already sends them ranked): keep
    // the server's order for equal ranks.
    final indexed = [for (var i = 0; i < parsed.length; i++) (i, parsed[i])]
      ..sort((a, b) {
        final c = a.$2.rank.compareTo(b.$2.rank);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return LeaderboardResult(
      query: query,
      entries: List.unmodifiable([for (final e in indexed) e.$2]),
      me: LeaderboardMe.tryParse(m['me']),
      metricLabel: _str(m['metricLabel']),
      periodKey: _str(m['periodKey']),
      updatedAt: parseServerTime(m['updatedAt']),
    );
  }

  final LeaderboardQuery query;
  final List<LeaderboardEntry> entries;
  final LeaderboardMe? me;
  final String? metricLabel;
  final String? periodKey;
  final DateTime? updatedAt;

  bool get isEmpty => entries.isEmpty;

  /// Value of the leader (rank 1), the basis of the progress bars.
  num get leaderValue => entries.isEmpty ? 0 : entries.first.value;
}
