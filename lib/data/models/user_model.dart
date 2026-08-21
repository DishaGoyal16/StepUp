import 'package:equatable/equatable.dart';

// ─────────────────────────────────────────────────────────
// USER MODEL
// ─────────────────────────────────────────────────────────
class UserModel extends Equatable {
  final String id;
  final String name;
  final String email;
  final String department;
  final String year;
  final String hostel;
  final String avatarEmoji;
  final int xp;
  final int level;
  final int stepCoins;
  final int totalVerifiedSteps;
  final int currentStreak;
  final int longestStreak;
  final double reliabilityScore;
  final int completedSessions;
  final List<String> sports;
  final Map<String, String> skillLevels; // sport -> skill
  final List<String> availableDays;
  final List<String> availableTimes;
  final int preferredGroupSizeMin;
  final int preferredGroupSizeMax;
  final String campusZone;
  final List<String> earnedBadgeIds;
  final bool isDemoUser;
  final DateTime createdAt;
  final DateTime lastActiveAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.department,
    required this.year,
    required this.hostel,
    this.avatarEmoji = '🏃',
    this.xp = 0,
    this.level = 1,
    this.stepCoins = 1000,
    this.totalVerifiedSteps = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.reliabilityScore = 1.0,
    this.completedSessions = 0,
    this.sports = const [],
    this.skillLevels = const {},
    this.availableDays = const [],
    this.availableTimes = const [],
    this.preferredGroupSizeMin = 2,
    this.preferredGroupSizeMax = 4,
    this.campusZone = 'Hostel Zone A',
    this.earnedBadgeIds = const [],
    this.isDemoUser = false,
    required this.createdAt,
    required this.lastActiveAt,
  });

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? department,
    String? year,
    String? hostel,
    String? avatarEmoji,
    int? xp,
    int? level,
    int? stepCoins,
    int? totalVerifiedSteps,
    int? currentStreak,
    int? longestStreak,
    double? reliabilityScore,
    int? completedSessions,
    List<String>? sports,
    Map<String, String>? skillLevels,
    List<String>? availableDays,
    List<String>? availableTimes,
    int? preferredGroupSizeMin,
    int? preferredGroupSizeMax,
    String? campusZone,
    List<String>? earnedBadgeIds,
    bool? isDemoUser,
    DateTime? createdAt,
    DateTime? lastActiveAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      department: department ?? this.department,
      year: year ?? this.year,
      hostel: hostel ?? this.hostel,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      xp: xp ?? this.xp,
      level: level ?? this.level,
      stepCoins: stepCoins ?? this.stepCoins,
      totalVerifiedSteps: totalVerifiedSteps ?? this.totalVerifiedSteps,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      completedSessions: completedSessions ?? this.completedSessions,
      sports: sports ?? this.sports,
      skillLevels: skillLevels ?? this.skillLevels,
      availableDays: availableDays ?? this.availableDays,
      availableTimes: availableTimes ?? this.availableTimes,
      preferredGroupSizeMin:
          preferredGroupSizeMin ?? this.preferredGroupSizeMin,
      preferredGroupSizeMax:
          preferredGroupSizeMax ?? this.preferredGroupSizeMax,
      campusZone: campusZone ?? this.campusZone,
      earnedBadgeIds: earnedBadgeIds ?? this.earnedBadgeIds,
      isDemoUser: isDemoUser ?? this.isDemoUser,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'department': department,
        'year': year,
        'hostel': hostel,
        'avatarEmoji': avatarEmoji,
        'xp': xp,
        'level': level,
        'stepCoins': stepCoins,
        'totalVerifiedSteps': totalVerifiedSteps,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'reliabilityScore': reliabilityScore,
        'completedSessions': completedSessions,
        'sports': sports,
        'skillLevels': skillLevels,
        'availableDays': availableDays,
        'availableTimes': availableTimes,
        'preferredGroupSizeMin': preferredGroupSizeMin,
        'preferredGroupSizeMax': preferredGroupSizeMax,
        'campusZone': campusZone,
        'earnedBadgeIds': earnedBadgeIds,
        'isDemoUser': isDemoUser,
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
      };

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        department: j['department'] as String,
        year: j['year'] as String,
        hostel: j['hostel'] as String,
        avatarEmoji: j['avatarEmoji'] as String? ?? '🏃',
        xp: j['xp'] as int? ?? 0,
        level: j['level'] as int? ?? 1,
        stepCoins: j['stepCoins'] as int? ?? 1000,
        totalVerifiedSteps: j['totalVerifiedSteps'] as int? ?? 0,
        currentStreak: j['currentStreak'] as int? ?? 0,
        longestStreak: j['longestStreak'] as int? ?? 0,
        reliabilityScore: (j['reliabilityScore'] as num?)?.toDouble() ?? 1.0,
        completedSessions: j['completedSessions'] as int? ?? 0,
        sports: List<String>.from(j['sports'] as List? ?? []),
        skillLevels: Map<String, String>.from(j['skillLevels'] as Map? ?? {}),
        availableDays: List<String>.from(j['availableDays'] as List? ?? []),
        availableTimes: List<String>.from(j['availableTimes'] as List? ?? []),
        preferredGroupSizeMin: j['preferredGroupSizeMin'] as int? ?? 2,
        preferredGroupSizeMax: j['preferredGroupSizeMax'] as int? ?? 4,
        campusZone: j['campusZone'] as String? ?? 'Hostel Zone A',
        earnedBadgeIds:
            List<String>.from(j['earnedBadgeIds'] as List? ?? []),
        isDemoUser: j['isDemoUser'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
        lastActiveAt: DateTime.parse(j['lastActiveAt'] as String),
      );

  String get levelTitle {
    const titles = [
      'Fresh Starter',
      'Active Student',
      'Campus Walker',
      'Fitness Grinder',
      'Step Warrior',
      'Campus Runner',
      'Elite Mover',
      'Campus Athlete',
      'StepUp Legend',
      'StepUp Champion',
    ];
    final idx = (level - 1).clamp(0, titles.length - 1);
    return titles[idx];
  }

  int get xpForNextLevel {
    const thresholds = [0, 200, 500, 1000, 1800, 2800, 4000, 5500, 7500, 10000, 999999];
    final nextIdx = level.clamp(0, thresholds.length - 1);
    return thresholds[nextIdx];
  }

  int get xpForCurrentLevel {
    const thresholds = [0, 200, 500, 1000, 1800, 2800, 4000, 5500, 7500, 10000, 999999];
    final curIdx = (level - 1).clamp(0, thresholds.length - 1);
    return thresholds[curIdx];
  }

  double get levelProgress {
    final cur = xpForCurrentLevel;
    final next = xpForNextLevel;
    if (next <= cur) return 1.0;
    return ((xp - cur) / (next - cur)).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [id, xp, stepCoins, currentStreak, earnedBadgeIds];
}
