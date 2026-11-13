import 'profile_enums.dart';

DateTime? _dt(Object? v) {
  if (v is DateTime) return v.toUtc();
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
  return null;
}

List<String> _strings(Object? v) =>
    v is Iterable ? v.whereType<String>().toList(growable: false) : const [];

Map<String, bool> _bools(Object? v) {
  if (v is! Map) return const {};
  return {
    for (final e in v.entries)
      if (e.key is String && e.value is bool) e.key as String: e.value as bool,
  };
}

/// The signed-in student's own `users/{uid}` document (read only on the
/// client; every mutation goes through a callable).
///
/// Timestamps must already be converted to [DateTime] (or epoch millis) by the
/// data layer, which keeps this class free of Firebase types.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.hostelId,
    this.block,
    this.fitnessLevel,
    this.sportsInterests = const [],
    this.preferredActivity,
    this.preferredTime,
    this.goals = const [],
    this.availability = const [],
    this.buddyType,
    this.bio = '',
    this.photoUrl,
    this.dailyGoal = kDefaultDailyGoal,
    this.privacy = const {},
    this.notificationPrefs = const {},
    this.pointsBalance = 0,
    this.pointsReserved = 0,
    this.lifetimeVerifiedSteps = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastGoalDayKey,
    this.status = 'ACTIVE',
    this.role = 'student',
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        displayName: (m['displayName'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        hostelId: (m['hostelId'] as String?) ?? '',
        block: m['block'] as String?,
        fitnessLevel: FitnessLevel.fromWire(m['fitnessLevel']),
        sportsInterests: _strings(m['sportsInterests']),
        preferredActivity: m['preferredActivity'] as String?,
        preferredTime: PreferredTime.fromWire(m['preferredTime']),
        goals: _strings(m['goals']),
        availability: _strings(m['availability']),
        buddyType: BuddyType.fromWire(m['buddyType']),
        bio: (m['bio'] as String?) ?? '',
        photoUrl: m['photoUrl'] as String?,
        dailyGoal: (m['dailyGoal'] as num?)?.toInt() ?? kDefaultDailyGoal,
        privacy: _bools(m['privacy']),
        notificationPrefs: _bools(m['notificationPrefs']),
        pointsBalance: (m['pointsBalance'] as num?)?.toInt() ?? 0,
        pointsReserved: (m['pointsReserved'] as num?)?.toInt() ?? 0,
        lifetimeVerifiedSteps: (m['lifetimeVerifiedSteps'] as num?)?.toInt() ?? 0,
        currentStreak: (m['currentStreak'] as num?)?.toInt() ?? 0,
        bestStreak: (m['bestStreak'] as num?)?.toInt() ?? 0,
        lastGoalDayKey: m['lastGoalDayKey'] as String?,
        status: (m['status'] as String?) ?? 'ACTIVE',
        role: (m['role'] as String?) ?? 'student',
        createdAt: _dt(m['createdAt']),
        updatedAt: _dt(m['updatedAt']),
      );

  final String uid;
  final String displayName;
  final String email;
  final String hostelId;
  final String? block;
  final FitnessLevel? fitnessLevel;
  final List<String> sportsInterests;
  final String? preferredActivity;
  final PreferredTime? preferredTime;
  final List<String> goals;
  final List<String> availability;
  final BuddyType? buddyType;
  final String bio;
  final String? photoUrl;
  final int dailyGoal;
  final Map<String, bool> privacy;
  final Map<String, bool> notificationPrefs;
  final int pointsBalance;
  final int pointsReserved;
  final int lifetimeVerifiedSteps;
  final int currentStreak;
  final int bestStreak;
  final String? lastGoalDayKey;
  final String status;
  final String role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'ACTIVE';

  String get firstName {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'there' : parts.first;
  }

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
