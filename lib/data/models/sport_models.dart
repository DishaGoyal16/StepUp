import 'package:equatable/equatable.dart';

// ─────────────────────────────────────────────────────────
// SPORT PROFILE  (user's sport preferences)
// ─────────────────────────────────────────────────────────
class SportProfile extends Equatable {
  final String userId;
  final String sport;
  final String skillLevel;       // Beginner | Intermediate | Advanced | Pro
  final List<String> availableDays;
  final List<String> availableTimes;
  final int groupSizeMin;
  final int groupSizeMax;
  final String campusZone;
  final double reliabilityScore;
  final int noShowCount;
  final int completedSessionCount;
  final bool isVisible;

  const SportProfile({
    required this.userId,
    required this.sport,
    required this.skillLevel,
    required this.availableDays,
    required this.availableTimes,
    required this.groupSizeMin,
    required this.groupSizeMax,
    required this.campusZone,
    this.reliabilityScore = 1.0,
    this.noShowCount = 0,
    this.completedSessionCount = 0,
    this.isVisible = true,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'sport': sport,
        'skillLevel': skillLevel,
        'availableDays': availableDays,
        'availableTimes': availableTimes,
        'groupSizeMin': groupSizeMin,
        'groupSizeMax': groupSizeMax,
        'campusZone': campusZone,
        'reliabilityScore': reliabilityScore,
        'noShowCount': noShowCount,
        'completedSessionCount': completedSessionCount,
        'isVisible': isVisible,
      };

  factory SportProfile.fromJson(Map<String, dynamic> j) => SportProfile(
        userId: j['userId'] as String,
        sport: j['sport'] as String,
        skillLevel: j['skillLevel'] as String,
        availableDays: List<String>.from(j['availableDays'] as List),
        availableTimes: List<String>.from(j['availableTimes'] as List),
        groupSizeMin: j['groupSizeMin'] as int,
        groupSizeMax: j['groupSizeMax'] as int,
        campusZone: j['campusZone'] as String,
        reliabilityScore: (j['reliabilityScore'] as num).toDouble(),
        noShowCount: j['noShowCount'] as int? ?? 0,
        completedSessionCount: j['completedSessionCount'] as int? ?? 0,
        isVisible: j['isVisible'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [userId, sport, skillLevel];
}

// ─────────────────────────────────────────────────────────
// SPORT MATCH  (a recommended buddy)
// ─────────────────────────────────────────────────────────
class SportMatch extends Equatable {
  final String id;
  final String userId;
  final String userName;
  final String avatarEmoji;
  final String department;
  final String hostel;
  final String sport;
  final String skillLevel;
  final List<String> availableDays;
  final List<String> availableTimes;
  final String campusZone;
  final double reliabilityScore;
  final double matchScore;          // 0.0 – 1.0
  final double skillFitScore;
  final double preferenceFitScore;
  final List<String> matchReasons;  // human-readable why matched
  final List<String> mismatchReasons;
  final MatchRequestStatus requestStatus;
  final int groupSizeMin;
  final int groupSizeMax;
  final bool isDemoData;

  const SportMatch({
    required this.id,
    required this.userId,
    required this.userName,
    required this.avatarEmoji,
    required this.department,
    required this.hostel,
    required this.sport,
    required this.skillLevel,
    required this.availableDays,
    required this.availableTimes,
    required this.campusZone,
    required this.reliabilityScore,
    required this.matchScore,
    required this.skillFitScore,
    required this.preferenceFitScore,
    required this.matchReasons,
    this.mismatchReasons = const [],
    this.requestStatus = MatchRequestStatus.none,
    required this.groupSizeMin,
    required this.groupSizeMax,
    this.isDemoData = false,
  });

  int get matchPercent => (matchScore * 100).round();

  SportMatch copyWith({MatchRequestStatus? requestStatus}) => SportMatch(
        id: id,
        userId: userId,
        userName: userName,
        avatarEmoji: avatarEmoji,
        department: department,
        hostel: hostel,
        sport: sport,
        skillLevel: skillLevel,
        availableDays: availableDays,
        availableTimes: availableTimes,
        campusZone: campusZone,
        reliabilityScore: reliabilityScore,
        matchScore: matchScore,
        skillFitScore: skillFitScore,
        preferenceFitScore: preferenceFitScore,
        matchReasons: matchReasons,
        mismatchReasons: mismatchReasons,
        requestStatus: requestStatus ?? this.requestStatus,
        groupSizeMin: groupSizeMin,
        groupSizeMax: groupSizeMax,
        isDemoData: isDemoData,
      );

  @override
  List<Object?> get props => [id, matchScore, requestStatus];
}

enum MatchRequestStatus { none, sent, received, accepted, declined }

// ─────────────────────────────────────────────────────────
// SPORTS SESSION
// ─────────────────────────────────────────────────────────
enum SessionStatus { upcoming, active, completed, cancelled, disputed }

class SportSession extends Equatable {
  final String id;
  final String organizerId;
  final String organizerName;
  final String sport;
  final String location;
  final DateTime scheduledAt;
  final int maxParticipants;
  final List<String> participantIds;
  final List<String> participantNames;
  final SessionStatus status;
  final int xpReward;
  final int coinReward;
  final List<String> confirmedUserIds;   // mutual check-in
  final bool isDemoData;
  final String? notes;

  const SportSession({
    required this.id,
    required this.organizerId,
    required this.organizerName,
    required this.sport,
    required this.location,
    required this.scheduledAt,
    required this.maxParticipants,
    this.participantIds = const [],
    this.participantNames = const [],
    required this.status,
    required this.xpReward,
    required this.coinReward,
    this.confirmedUserIds = const [],
    this.isDemoData = false,
    this.notes,
  });

  int get currentCount => participantIds.length;
  bool get isFull => currentCount >= maxParticipants;

  bool isConfirmedBy(String userId) => confirmedUserIds.contains(userId);

  bool isVerified(String userId1, String userId2) =>
      confirmedUserIds.contains(userId1) && confirmedUserIds.contains(userId2);

  SportSession copyWith({
    SessionStatus? status,
    List<String>? participantIds,
    List<String>? participantNames,
    List<String>? confirmedUserIds,
  }) =>
      SportSession(
        id: id,
        organizerId: organizerId,
        organizerName: organizerName,
        sport: sport,
        location: location,
        scheduledAt: scheduledAt,
        maxParticipants: maxParticipants,
        participantIds: participantIds ?? this.participantIds,
        participantNames: participantNames ?? this.participantNames,
        status: status ?? this.status,
        xpReward: xpReward,
        coinReward: coinReward,
        confirmedUserIds: confirmedUserIds ?? this.confirmedUserIds,
        isDemoData: isDemoData,
        notes: notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizerId': organizerId,
        'organizerName': organizerName,
        'sport': sport,
        'location': location,
        'scheduledAt': scheduledAt.toIso8601String(),
        'maxParticipants': maxParticipants,
        'participantIds': participantIds,
        'participantNames': participantNames,
        'status': status.name,
        'xpReward': xpReward,
        'coinReward': coinReward,
        'confirmedUserIds': confirmedUserIds,
        'isDemoData': isDemoData,
        'notes': notes,
      };

  factory SportSession.fromJson(Map<String, dynamic> j) => SportSession(
        id: j['id'] as String,
        organizerId: j['organizerId'] as String,
        organizerName: j['organizerName'] as String,
        sport: j['sport'] as String,
        location: j['location'] as String,
        scheduledAt: DateTime.parse(j['scheduledAt'] as String),
        maxParticipants: j['maxParticipants'] as int,
        participantIds: List<String>.from(j['participantIds'] as List? ?? []),
        participantNames:
            List<String>.from(j['participantNames'] as List? ?? []),
        status: SessionStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => SessionStatus.upcoming,
        ),
        xpReward: j['xpReward'] as int,
        coinReward: j['coinReward'] as int,
        confirmedUserIds:
            List<String>.from(j['confirmedUserIds'] as List? ?? []),
        isDemoData: j['isDemoData'] as bool? ?? false,
        notes: j['notes'] as String?,
      );

  @override
  List<Object?> get props => [id, status, currentCount, confirmedUserIds];
}
