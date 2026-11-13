import '../../domain/day_key.dart';
import '../../domain/hostel.dart';

// Plain value types of the admin panel. They mirror the admin callables in
// `functions/src/admin/admin.ts` (DATABASE_SCHEMA.md). Callable results carry
// timestamps as epoch milliseconds; Firestore readers hand us `DateTime`.

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

DateTime? _time(Object? v) {
  if (v is DateTime) return v.toUtc();
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
  return null;
}

List<String> _strings(Object? v) =>
    v is List ? [for (final e in v) if (e is String) e] : const <String>[];

Map<String, dynamic> _map(Object? v) =>
    v is Map ? {for (final e in v.entries) e.key.toString(): e.value} : <String, dynamic>{};

/// `adminStats` result.
class AdminStats {
  const AdminStats({
    required this.users,
    required this.activeUsers,
    required this.deletionRequests,
    required this.activeChallenges,
    required this.openReports,
    required this.openRiskEvents,
    required this.activeBets,
  });

  factory AdminStats.fromMap(Map<String, dynamic> m) => AdminStats(
        users: _int(m['users']),
        activeUsers: _int(m['activeUsers']),
        deletionRequests: _int(m['deletionRequests']),
        activeChallenges: _int(m['activeChallenges']),
        openReports: _int(m['openReports']),
        openRiskEvents: _int(m['openRiskEvents']),
        activeBets: _int(m['activeBets']),
      );

  /// Registered students (all `users` documents).
  final int users;

  /// Accounts with `status == ACTIVE` (the server does not report a per-day
  /// active count).
  final int activeUsers;
  final int deletionRequests;
  final int activeChallenges;
  final int openReports;
  final int openRiskEvents;
  final int activeBets;
}

/// A row of `adminListStudents`.
class AdminStudent {
  const AdminStudent({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.hostelId,
    required this.status,
    required this.role,
    required this.pointsBalance,
    required this.pointsReserved,
    required this.lifetimeVerifiedSteps,
    this.createdAt,
  });

  factory AdminStudent.fromMap(Map<String, dynamic> m) => AdminStudent(
        uid: (m['uid'] as String?) ?? '',
        displayName: _str(m['displayName']) ?? 'Unnamed student',
        email: (m['email'] as String?) ?? '',
        hostelId: _str(m['hostelId']),
        status: _str(m['status']) ?? 'ACTIVE',
        role: _str(m['role']) ?? 'student',
        pointsBalance: _int(m['pointsBalance']),
        pointsReserved: _int(m['pointsReserved']),
        lifetimeVerifiedSteps: _int(m['lifetimeVerifiedSteps']),
        createdAt: _time(m['createdAt']),
      );

  final String uid;
  final String displayName;
  final String email;
  final String? hostelId;

  /// `ACTIVE | SUSPENDED | DELETION_REQUESTED`.
  final String status;

  /// `student | admin`.
  final String role;
  final int pointsBalance;
  final int pointsReserved;
  final int lifetimeVerifiedSteps;
  final DateTime? createdAt;

  bool get isSuspended => status == 'SUSPENDED';
  bool get isAdmin => role == 'admin';

  AdminStudent copyWith({String? status, String? role}) => AdminStudent(
        uid: uid,
        displayName: displayName,
        email: email,
        hostelId: hostelId,
        status: status ?? this.status,
        role: role ?? this.role,
        pointsBalance: pointsBalance,
        pointsReserved: pointsReserved,
        lifetimeVerifiedSteps: lifetimeVerifiedSteps,
        createdAt: createdAt,
      );
}

class StudentPage {
  const StudentPage({required this.students, this.nextCursor});

  final List<AdminStudent> students;
  final String? nextCursor;
}

/// `reports/{id}` status.
enum ReportStatus {
  open('OPEN', 'Open'),
  dismissed('DISMISSED', 'Dismissed'),
  actioned('ACTIONED', 'Action taken');

  const ReportStatus(this.wire, this.label);
  final String wire;
  final String label;

  static ReportStatus fromWire(Object? v) => ReportStatus.values.firstWhere(
        (s) => s.wire == v,
        orElse: () => ReportStatus.open,
      );
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.reporterUid,
    required this.targetUid,
    required this.reason,
    required this.details,
    required this.status,
    this.resolvedBy,
    this.createdAt,
    this.resolvedAt,
  });

  factory AdminReport.fromMap(Map<String, dynamic> m) => AdminReport(
        id: (m['id'] as String?) ?? '',
        reporterUid: (m['reporterUid'] as String?) ?? '',
        targetUid: (m['targetUid'] as String?) ?? '',
        reason: (m['reason'] as String?) ?? '',
        details: (m['details'] as String?) ?? '',
        status: ReportStatus.fromWire(m['status']),
        resolvedBy: _str(m['resolvedBy']),
        createdAt: _time(m['createdAt']),
        resolvedAt: _time(m['resolvedAt']),
      );

  final String id;
  final String reporterUid;
  final String targetUid;
  final String reason;
  final String details;
  final ReportStatus status;
  final String? resolvedBy;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  /// Readable reason, e.g. `FAKE_PROFILE` -> `Fake profile`.
  String get reasonLabel => humanizeKey(reason);
}

/// `riskEvents/{id}` status.
enum RiskStatus {
  open('OPEN', 'Open'),
  reviewed('REVIEWED', 'Reviewed'),
  cleared('CLEARED', 'Cleared');

  const RiskStatus(this.wire, this.label);
  final String wire;
  final String label;

  static RiskStatus fromWire(Object? v) => RiskStatus.values.firstWhere(
        (s) => s.wire == v,
        orElse: () => RiskStatus.open,
      );
}

/// Suspicious step activity (`riskEvents`). It never feeds rewards; it is
/// only evidence for an admin to review.
class RiskEvent {
  const RiskEvent({
    required this.id,
    required this.uid,
    required this.kind,
    required this.detail,
    required this.status,
    required this.dayKey,
    this.createdAt,
  });

  factory RiskEvent.fromMap(Map<String, dynamic> m) => RiskEvent(
        id: (m['id'] as String?) ?? '',
        uid: (m['uid'] as String?) ?? '',
        kind: (m['kind'] as String?) ?? 'UNKNOWN',
        detail: _map(m['detail']),
        status: RiskStatus.fromWire(m['status']),
        dayKey: _str(m['dayKey']),
        createdAt: _time(m['createdAt']),
      );

  final String id;
  final String uid;
  final String kind;
  final Map<String, dynamic> detail;
  final RiskStatus status;
  final String? dayKey;
  final DateTime? createdAt;

  String get kindLabel => switch (kind) {
        'HARD_LIMIT' => 'Hard step limit exceeded',
        'DAILY_CAP' => 'Daily reward cap reached',
        'DOWNGRADE' => 'Steps downgraded by the server',
        'ROBOTIC' => 'Robotic stepping pattern',
        'MANY_REJECTIONS' => 'Many rejected buckets',
        'DEVICE_MISMATCH' => 'Device mismatch',
        _ => humanizeKey(kind),
      };

  /// `20261113` -> `Fri 13 Nov`; anything else is returned unchanged.
  String? get dayLabel {
    final k = dayKey;
    if (k == null) return null;
    try {
      return DayKey.label(k);
    } on FormatException {
      return k;
    }
  }
}

/// A challenge row read from the `challenges` collection.
class AdminChallenge {
  const AdminChallenge({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.metric,
    required this.target,
    required this.status,
    required this.windowMode,
    required this.hostelIds,
    required this.participantCount,
    required this.isTemplate,
    this.dailyTarget,
    this.startAt,
    this.endAt,
    this.durationDays,
    this.hostelAggregation,
    this.rewardPoints,
    this.createdAt,
  });

  factory AdminChallenge.fromMap(String id, Map<String, dynamic> m) => AdminChallenge(
        id: id,
        type: (m['type'] as String?) ?? 'CAMPUS',
        title: (m['title'] as String?) ?? id,
        description: (m['description'] as String?) ?? '',
        metric: (m['metric'] as String?) ?? 'TOTAL_STEPS',
        target: _int(m['target']),
        dailyTarget: m['dailyTarget'] is num ? _int(m['dailyTarget']) : null,
        status: (m['status'] as String?) ?? 'ACTIVE',
        windowMode: (m['windowMode'] as String?) ?? 'FIXED',
        startAt: _time(m['startAt']),
        endAt: _time(m['endAt']),
        durationDays: m['durationDays'] is num ? _int(m['durationDays']) : null,
        hostelIds: _strings(m['hostelIds']),
        hostelAggregation: _str(m['hostelAggregation']),
        rewardPoints: m['rewardPoints'] is num ? _int(m['rewardPoints']) : null,
        participantCount: _int(m['participantCount']),
        isTemplate: m['isTemplate'] == true,
        createdAt: _time(m['createdAt']),
      );

  final String id;
  final String type;
  final String title;
  final String description;
  final String metric;
  final int target;
  final int? dailyTarget;
  final String status;
  final String windowMode;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? durationDays;
  final List<String> hostelIds;
  final String? hostelAggregation;
  final int? rewardPoints;
  final int participantCount;
  final bool isTemplate;
  final DateTime? createdAt;

  /// Cancelling is only possible before the challenge has been finalised.
  bool get canCancel => status == 'PENDING' || status == 'UPCOMING' || status == 'ACTIVE';

  String get typeLabel => switch (type) {
        'CAMPUS' => 'Campus',
        'INTER_HOSTEL' => 'Inter-hostel',
        'INDIVIDUAL' => 'Individual',
        'BUDDY' => 'Buddy',
        _ => humanizeKey(type),
      };

  String get metricLabel => switch (metric) {
        'TOTAL_STEPS' => 'Total steps',
        'DAILY_TARGET_DAYS' => 'Days hitting the daily target',
        'STREAK_DAYS' => 'Streak days',
        _ => humanizeKey(metric),
      };
}

/// A badge definition in `adminSettings/badges`.
class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.rule,
    required this.points,
  });

  factory BadgeDefinition.fromMap(String id, Map<String, dynamic> m) => BadgeDefinition(
        id: id,
        title: (m['title'] as String?) ?? humanizeKey(id),
        description: (m['description'] as String?) ?? '',
        icon: (m['icon'] as String?) ?? 'emoji_events',
        rule: (m['rule'] as String?) ?? '',
        points: _int(m['points']),
      );

  final String id;
  final String title;
  final String description;
  final String icon;
  final String rule;
  final int points;

  BadgeDefinition copyWith({String? title, String? description, int? points}) => BadgeDefinition(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        icon: icon,
        rule: rule,
        points: points ?? this.points,
      );

  /// `adminUpsertBadge` payload. `icon` and `rule` are required by the
  /// backend and are preserved from the stored definition.
  Map<String, dynamic> toPayload() => {
        'badgeId': id,
        'title': title.trim(),
        'description': description.trim(),
        'icon': icon,
        'rule': rule,
        'points': points,
      };

  static const int titleMax = 60;
  static const int descriptionMax = 200;
  static const int pointsMax = 100000;

  /// Field errors keyed by `title | description | points`.
  Map<String, String> validate() {
    final e = <String, String>{};
    final t = title.trim();
    if (t.length < 2 || t.length > titleMax) e['title'] = 'Title must be 2-$titleMax characters.';
    final d = description.trim();
    if (d.length < 2 || d.length > descriptionMax) {
      e['description'] = 'Description must be 2-$descriptionMax characters.';
    }
    if (points < 0 || points > pointsMax) e['points'] = 'Points must be 0-$pointsMax.';
    if (icon.isEmpty) e['icon'] = 'The badge has no icon.';
    if (rule.trim().length < 2) e['rule'] = 'The badge has no rule text.';
    return e;
  }
}

/// `adminSeedDefaults` report.
class SeedReport {
  const SeedReport({
    this.hostelsCreated = 0,
    this.challengeTemplatesCreated = 0,
    this.settingsCreatedOrFilled = false,
    this.badgesCreatedOrFilled = false,
  });

  factory SeedReport.fromMap(Map<String, dynamic> m) {
    final r = m['report'] is Map ? _map(m['report']) : m;
    return SeedReport(
      hostelsCreated: _int(r['hostelsCreated']),
      challengeTemplatesCreated: _int(r['challengeTemplatesCreated']),
      settingsCreatedOrFilled: r['settingsCreatedOrFilled'] == true,
      badgesCreatedOrFilled: r['badgesCreatedOrFilled'] == true,
    );
  }

  final int hostelsCreated;
  final int challengeTemplatesCreated;
  final bool settingsCreatedOrFilled;
  final bool badgesCreatedOrFilled;

  String get summary =>
      '$hostelsCreated hostel(s) and $challengeTemplatesCreated challenge template(s) created'
      '${settingsCreatedOrFilled ? ', settings filled' : ''}'
      '${badgesCreatedOrFilled ? ', badges filled' : ''}.';
}

/// Input of `adminUpsertHostel`.
class HostelDraft {
  const HostelDraft({
    required this.id,
    required this.displayName,
    required this.category,
    required this.sortOrder,
    this.legacyName,
    this.block,
    this.active = true,
  });

  factory HostelDraft.fromHostel(Hostel h) => HostelDraft(
        id: h.id,
        displayName: h.displayName,
        legacyName: h.legacyName,
        block: h.block,
        category: h.category,
        sortOrder: h.sortOrder,
        active: h.active,
      );

  final String id;
  final String displayName;
  final String? legacyName;
  final String? block;
  final HostelCategory category;
  final int sortOrder;
  final bool active;

  static final RegExp idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,39}$');

  /// Field errors keyed by `id | displayName | legacyName | block | sortOrder`.
  /// [existingIds] guards against silently overwriting another hostel when
  /// creating (the server upsert is a merge).
  Map<String, String> validate({Set<String> existingIds = const {}, bool creating = true}) {
    final e = <String, String>{};
    if (!idPattern.hasMatch(id)) {
      e['id'] = 'Use 2-40 lowercase letters, digits or "-" (e.g. vasudha-e).';
    } else if (creating && existingIds.contains(id)) {
      e['id'] = 'A hostel with this id already exists. Edit it instead.';
    }
    final n = displayName.trim();
    if (n.length < 2 || n.length > 80) e['displayName'] = 'Name must be 2-80 characters.';
    if ((legacyName ?? '').trim().length > 40) e['legacyName'] = 'At most 40 characters.';
    if ((block ?? '').trim().length > 10) e['block'] = 'At most 10 characters.';
    if (sortOrder < 0 || sortOrder > 10000) e['sortOrder'] = 'Sort order must be 0-10000.';
    return e;
  }

  Map<String, dynamic> toPayload() => {
        'hostelId': id,
        'displayName': displayName.trim(),
        'legacyName': (legacyName ?? '').trim(),
        'block': (block ?? '').trim(),
        'category': category.wire,
        'active': active,
        'sortOrder': sortOrder,
      };
}

/// Types an admin can create (`adminCreateChallenge`).
enum AdminChallengeType {
  campus('CAMPUS', 'Campus'),
  interHostel('INTER_HOSTEL', 'Inter-hostel'),
  individual('INDIVIDUAL', 'Individual');

  const AdminChallengeType(this.wire, this.label);
  final String wire;
  final String label;
}

enum AdminChallengeMetric {
  totalSteps('TOTAL_STEPS', 'Total steps'),
  dailyTargetDays('DAILY_TARGET_DAYS', 'Days hitting a daily target'),
  streakDays('STREAK_DAYS', 'Streak days');

  const AdminChallengeMetric(this.wire, this.label);
  final String wire;
  final String label;
}

enum HostelAggregation {
  averagePerParticipant('AVERAGE_PER_PARTICIPANT', 'Average per participant'),
  total('TOTAL', 'Total');

  const HostelAggregation(this.wire, this.label);
  final String wire;
  final String label;
}

/// Input of `adminCreateChallenge` with the backend's validation mirrored
/// (`functions/src/admin/admin.ts`). Dates are IST calendar days as `dayKey`s
/// (`YYYYMMDD`); [lastDayKey] is the last day INCLUDED, so `endAt` is the IST
/// midnight after it.
class ChallengeDraft {
  const ChallengeDraft({
    required this.type,
    this.title = '',
    this.description = '',
    this.metric = AdminChallengeMetric.totalSteps,
    this.target,
    this.dailyTarget,
    this.rolling = false,
    this.durationDays,
    this.startDayKey,
    this.lastDayKey,
    this.hostelIds = const [],
    this.aggregation = HostelAggregation.averagePerParticipant,
    this.rewardPoints,
  });

  final AdminChallengeType type;
  final String title;
  final String description;
  final AdminChallengeMetric metric;
  final int? target;
  final int? dailyTarget;

  /// Only INDIVIDUAL challenges may roll (window starts when a student joins).
  final bool rolling;
  final int? durationDays;
  final String? startDayKey;
  final String? lastDayKey;
  final List<String> hostelIds;
  final HostelAggregation aggregation;
  final int? rewardPoints;

  bool get needsDailyTarget => metric != AdminChallengeMetric.totalSteps;
  bool get isRolling => rolling && type == AdminChallengeType.individual;

  static int? startMs(String? dayKey) => _dayMs(dayKey);

  /// IST midnight AFTER the inclusive last day.
  static int? endMs(String? lastDayKey) {
    final s = _dayMs(lastDayKey);
    return s == null ? null : s + const Duration(days: 1).inMilliseconds;
  }

  static int? _dayMs(String? k) {
    if (k == null) return null;
    try {
      return DayKey.parse(k).millisecondsSinceEpoch;
    } on FormatException {
      return null;
    }
  }

  /// Field errors keyed by `title | description | target | dailyTarget |
  /// duration | start | end | hostels | rewardPoints`. Empty = valid.
  /// [now] is the current instant, [knownHostelIds] the ids that may be used.
  Map<String, String> validate({required DateTime now, Set<String>? knownHostelIds}) {
    final e = <String, String>{};
    final t = title.trim();
    if (t.length < 3 || t.length > 80) e['title'] = 'Title must be 3-80 characters.';
    if (description.trim().length > 400) e['description'] = 'At most 400 characters.';
    final tg = target;
    if (tg == null || tg < 1 || tg > 100000000) {
      e['target'] = metric == AdminChallengeMetric.totalSteps
          ? 'Enter a step target between 1 and 100,000,000.'
          : 'Enter the number of days (1-100,000,000).';
    }
    if (needsDailyTarget) {
      final d = dailyTarget;
      if (d == null || d < 100 || d > 100000) e['dailyTarget'] = 'Daily target must be 100-100,000 steps.';
    }
    if (isRolling) {
      final d = durationDays;
      if (d == null || d < 1 || d > 90) e['duration'] = 'Duration must be 1-90 days.';
    } else {
      final s = _dayMs(startDayKey);
      final l = _dayMs(lastDayKey);
      if (s == null) e['start'] = 'Pick a start date.';
      if (l == null) e['end'] = 'Pick a last day.';
      if (s != null && l != null) {
        if (l < s) {
          e['end'] = 'The last day cannot be before the start date.';
        } else if (endMs(lastDayKey)! <= now.millisecondsSinceEpoch) {
          e['end'] = 'The challenge would already be over.';
        }
      }
    }
    if (type == AdminChallengeType.interHostel) {
      if (hostelIds.length < 2) {
        e['hostels'] = 'Select at least two hostels.';
      } else if (hostelIds.length > 30) {
        e['hostels'] = 'At most 30 hostels.';
      } else if (knownHostelIds != null && hostelIds.any((h) => !knownHostelIds.contains(h))) {
        e['hostels'] = 'One of the selected hostels is unknown.';
      }
    }
    final r = rewardPoints;
    if (r != null && (r < 0 || r > 100000)) e['rewardPoints'] = 'Reward must be 0-100,000 points.';
    return e;
  }

  Map<String, dynamic> toPayload() => {
        'type': type.wire,
        'title': title.trim(),
        'description': description.trim(),
        'metric': metric.wire,
        'target': target,
        if (needsDailyTarget) 'dailyTarget': dailyTarget,
        'windowMode': isRolling ? 'ROLLING' : 'FIXED',
        if (isRolling) 'durationDays': durationDays,
        if (!isRolling) 'startAt': startMs(startDayKey),
        if (!isRolling) 'endAt': endMs(lastDayKey),
        if (type == AdminChallengeType.interHostel) ...{
          'hostelIds': hostelIds,
          'hostelAggregation': aggregation.wire,
        },
        if (rewardPoints != null) 'rewardPoints': rewardPoints,
      };
}

/// `FRAUD_LIMIT` -> `Fraud limit`; keeps unknown values readable.
String humanizeKey(String key) {
  final cleaned = key.replaceAll('_', ' ').trim();
  if (cleaned.isEmpty) return key;
  final spaced = cleaned.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ');
  final lower = spaced.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}
