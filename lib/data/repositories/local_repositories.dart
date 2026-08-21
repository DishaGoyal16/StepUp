import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import '../models/activity_models.dart';
import '../models/gamification_models.dart';
import '../models/sport_models.dart';
import '../../core/constants/hive_keys.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/gamification_service.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────
// USER REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalUserRepository {
  Box get _box => Hive.box(HiveKeys.userBox);

  UserModel? getCurrentUser() {
    final raw = _box.get(HiveKeys.currentUser);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw as String) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(UserModel user) async {
    await _box.put(HiveKeys.currentUser, jsonEncode(user.toJson()));
  }

  Future<void> clearUser() async {
    await _box.delete(HiveKeys.currentUser);
  }

  UserModel createDemoUser() {
    return UserModel(
      id: _uuid.v4(),
      name: 'Disha Goyal',
      email: 'disha.goyal@thapar.edu',
      department: 'Computer Science (CSE)',
      year: '3rd Year',
      hostel: 'Kalpana Chawla Bhawan',
      avatarEmoji: '🏃',
      xp: 1240,
      level: 8,
      stepCoins: 2450,
      totalVerifiedSteps: 42810,
      currentStreak: 6,
      longestStreak: 14,
      reliabilityScore: 0.94,
      completedSessions: 8,
      sports: ['Badminton', 'Running'],
      skillLevels: {'Badminton': 'Intermediate', 'Running': 'Advanced'},
      availableDays: ['Tue', 'Thu', 'Sat', 'Sun'],
      availableTimes: ['6 PM – 8 PM', 'Morning (6–8 AM)'],
      preferredGroupSizeMin: 2,
      preferredGroupSizeMax: 4,
      campusZone: 'Hostel Zone A',
      earnedBadgeIds: ['first_run', 'streak_7', 'steps_10k', 'sessions_5'],
      isDemoUser: true,
      createdAt: DateTime.now().subtract(const Duration(days: 60)),
      lastActiveAt: DateTime.now(),
    );
  }
}

// ─────────────────────────────────────────────────────────
// ACTIVITY REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalActivityRepository {
  Box get _box => Hive.box(HiveKeys.activityBox);

  Future<void> saveDailySummary(DailyActivitySummary summary) async {
    final key = 'summary_${_dateKey(summary.date)}';
    await _box.put(key, jsonEncode(summary.toJson()));
  }

  DailyActivitySummary? getTodaySummary() {
    final key = 'summary_${_dateKey(DateTime.now())}';
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      return DailyActivitySummary.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw as String) as Map));
    } catch (_) {
      return null;
    }
  }

  List<DailyActivitySummary> getWeeklySummaries() {
    final summaries = <DailyActivitySummary>[];
    for (int i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final key = 'summary_${_dateKey(day)}';
      final raw = _box.get(key);
      if (raw != null) {
        try {
          summaries.add(DailyActivitySummary.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw as String) as Map)));
        } catch (_) {}
      }
    }
    return summaries;
  }

  DailyActivitySummary demoTodaySummary() {
    return DailyActivitySummary(
      date: DateTime.now(),
      importedSteps: 8642,
      verifiedSteps: 7931,
      suspiciousSteps: 711,
      distanceMeters: 6580,
      walkingMinutes: 62,
      runningMinutes: 30,
      integrityScore: 0.918,
      xpEarned: 793,
      coinsEarned: 79,
      recordIds: [],
      isDemoData: true,
    );
  }

  List<DailyActivitySummary> demoWeeklySummaries() {
    const weekSteps = [6800, 9200, 7100, 8900, 5500, 10200, 8642];
    const weekVerified = [6200, 8800, 6500, 8400, 5000, 9700, 7931];
    return List.generate(7, (i) {
      final day = DateTime.now().subtract(Duration(days: 6 - i));
      return DailyActivitySummary(
        date: day,
        importedSteps: weekSteps[i],
        verifiedSteps: weekVerified[i],
        suspiciousSteps: weekSteps[i] - weekVerified[i],
        distanceMeters: weekVerified[i] * 0.75,
        walkingMinutes: 45 + i * 5,
        runningMinutes: i % 2 == 0 ? 30 : 0,
        integrityScore: 0.88 + (i * 0.01),
        xpEarned: weekVerified[i] ~/ 10,
        coinsEarned: weekVerified[i] ~/ 100,
        recordIds: [],
        isDemoData: true,
      );
    });
  }

  static String _dateKey(DateTime d) =>
      '${d.year}_${d.month.toString().padLeft(2, '0')}_${d.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────
// CHALLENGE REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalChallengeRepository {
  List<ChallengeModel> getActiveChallenges() {
    final now = DateTime.now();
    return [
      ChallengeModel(
        id: _uuid.v4(),
        title: 'Morning 3K',
        description: 'Walk 3,000 verified steps before noon',
        emoji: '☀️',
        type: ChallengeType.daily,
        status: ChallengeStatus.active,
        targetSteps: 3000,
        currentSteps: 2340,
        xpReward: AppConstants.xpChallengeDaily,
        coinReward: AppConstants.coinsChallengeDaily,
        startDate: DateTime(now.year, now.month, now.day),
        endDate: DateTime(now.year, now.month, now.day, 12, 0),
        isDemoData: true,
      ),
      ChallengeModel(
        id: _uuid.v4(),
        title: '7-Day Step Streak',
        description: 'Hit 8,000+ verified steps for 7 consecutive days',
        emoji: '🔥',
        type: ChallengeType.weekly,
        status: ChallengeStatus.active,
        targetSteps: 56000,
        currentSteps: 39200,
        xpReward: AppConstants.xpChallengeWeekly,
        coinReward: AppConstants.coinsChallengeWeekly,
        startDate: now.subtract(const Duration(days: 4)),
        endDate: now.add(const Duration(days: 3)),
        isDemoData: true,
      ),
      ChallengeModel(
        id: _uuid.v4(),
        title: 'Thapar 100K',
        description: 'Campus-wide challenge: collect 100K verified steps this month',
        emoji: '🏛️',
        type: ChallengeType.campus,
        status: ChallengeStatus.active,
        targetSteps: 100000,
        currentSteps: 42810,
        xpReward: AppConstants.xpChallengeCampus,
        coinReward: AppConstants.coinsChallengeCampus,
        badgeReward: 'campus_100k',
        startDate: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year, now.month + 1, 0),
        isDemoData: true,
      ),
      ChallengeModel(
        id: _uuid.v4(),
        title: 'Hostel Step War',
        description: 'KCB vs GNVB — which hostel walks more this week?',
        emoji: '🏠',
        type: ChallengeType.hostel,
        status: ChallengeStatus.active,
        targetSteps: 200000,
        currentSteps: 87400,
        xpReward: 300,
        coinReward: 150,
        startDate: now.subtract(const Duration(days: 2)),
        endDate: now.add(const Duration(days: 5)),
        isDemoData: true,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────
// BET REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalBetRepository {
  Box get _box => Hive.box(HiveKeys.betBox);

  List<BetModel> getActiveBets(String userId) {
    return _demoBets(userId)
        .where((b) => b.status == BetStatus.active || b.status == BetStatus.pending)
        .toList();
  }

  List<BetModel> getAllBets(String userId) => _demoBets(userId);

  Future<void> saveBet(BetModel bet) async {
    await _box.put(bet.id, jsonEncode(bet.toJson()));
  }

  List<BetModel> _demoBets(String userId) {
    return [
      BetModel(
        id: 'bet_demo_1',
        challenger: BetParticipant(
          userId: userId,
          userName: 'Disha Goyal',
          avatarEmoji: '🏃',
          currentVerifiedSteps: 4850,
        ),
        opponent: const BetParticipant(
          userId: 'arjun_123',
          userName: 'Arjun Mehta',
          avatarEmoji: '🏃‍♂️',
          currentVerifiedSteps: 4100,
        ),
        targetSteps: 5000,
        stakeCoins: 500,
        prizeCoins: 1000,
        duration: '24 hours',
        status: BetStatus.active,
        createdAt: DateTime.now().subtract(const Duration(hours: 8)),
        expiresAt: DateTime.now().add(const Duration(hours: 16)),
        isDemoData: true,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────
// SPORT BUDDY REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalSportBuddyRepository {
  List<SportMatch> getDemoMatches(String sport, String skillLevel) {
    return [
      SportMatch(
        id: 'match_1',
        userId: 'anvi_456',
        userName: 'Anvi Sharma',
        avatarEmoji: '🏸',
        department: 'Electronics (ECE)',
        hostel: 'Sarojini Naidu Bhawan',
        sport: sport,
        skillLevel: skillLevel,
        availableDays: ['Tue', 'Thu'],
        availableTimes: ['6 PM – 8 PM'],
        campusZone: 'Hostel Zone A',
        reliabilityScore: 0.92,
        matchScore: 0.94,
        skillFitScore: 1.0,
        preferenceFitScore: 0.88,
        matchReasons: [
          'Same sport: $sport',
          'Compatible skill level',
          'Good time overlap',
          'Same campus zone',
          '92% reliability score',
        ],
        groupSizeMin: 2,
        groupSizeMax: 4,
        isDemoData: true,
      ),
      SportMatch(
        id: 'match_2',
        userId: 'raghav_789',
        userName: 'Raghav Bhatia',
        avatarEmoji: '🎯',
        department: 'Mechanical (ME)',
        hostel: 'Lohitya Bhawan',
        sport: sport,
        skillLevel: skillLevel,
        availableDays: ['Thu', 'Sat'],
        availableTimes: ['6 PM – 8 PM', 'Morning (6–8 AM)'],
        campusZone: 'Sports Complex',
        reliabilityScore: 0.85,
        matchScore: 0.87,
        skillFitScore: 0.75,
        preferenceFitScore: 0.80,
        matchReasons: [
          'Same sport: $sport',
          'Compatible skill level',
          'Partial time overlap',
          'Nearby campus zone',
        ],
        mismatchReasons: ['Slight skill gap'],
        groupSizeMin: 2,
        groupSizeMax: 6,
        isDemoData: true,
      ),
      SportMatch(
        id: 'match_3',
        userId: 'kashish_101',
        userName: 'Kashish Arora',
        avatarEmoji: '⚡',
        department: 'Computer Science (CSE)',
        hostel: 'Meerabai Bhawan',
        sport: sport,
        skillLevel: skillLevel,
        availableDays: ['Tue', 'Fri', 'Sun'],
        availableTimes: ['6 PM – 8 PM'],
        campusZone: 'Hostel Zone A',
        reliabilityScore: 0.78,
        matchScore: 0.79,
        skillFitScore: 0.75,
        preferenceFitScore: 0.74,
        matchReasons: [
          'Same sport: $sport',
          'Matching available days',
          'Compatible group size',
        ],
        groupSizeMin: 2,
        groupSizeMax: 4,
        isDemoData: true,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────
// SESSION REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalSessionRepository {
  List<SportSession> getDemoSessions() {
    final now = DateTime.now();
    return [
      SportSession(
        id: 'session_1',
        organizerId: 'anvi_456',
        organizerName: 'Anvi Sharma',
        sport: 'Badminton',
        location: 'Sports Complex — Court 3',
        scheduledAt: DateTime(now.year, now.month, now.day, 18, 30),
        maxParticipants: 4,
        participantIds: ['anvi_456', 'raghav_789', 'kashish_101'],
        participantNames: ['Anvi', 'Raghav', 'Kashish'],
        status: SessionStatus.upcoming,
        xpReward: AppConstants.xpSportSession,
        coinReward: AppConstants.coinsSportSession,
        isDemoData: true,
      ),
      SportSession(
        id: 'session_2',
        organizerId: 'demo_user',
        organizerName: 'Disha Goyal',
        sport: 'Running',
        location: 'Campus Track',
        scheduledAt: DateTime(now.year, now.month, now.day + 1, 6, 30),
        maxParticipants: 6,
        participantIds: ['demo_user', 'anvi_456'],
        participantNames: ['Disha', 'Anvi'],
        status: SessionStatus.upcoming,
        xpReward: AppConstants.xpSportSession,
        coinReward: AppConstants.coinsSportSession,
        isDemoData: true,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────
// LEADERBOARD REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalLeaderboardRepository {
  List<LeaderboardEntry> getHostelLeaderboard(String currentUserId) {
    return [
      LeaderboardEntry(
        rank: 1,
        userId: 'anvi_456',
        userName: 'Anvi Sharma',
        avatarEmoji: '🏸',
        department: 'Electronics (ECE)',
        hostel: 'Kalpana Chawla Bhawan',
        verifiedSteps: 48230,
      ),
      LeaderboardEntry(
        rank: 2,
        userId: currentUserId,
        userName: 'Disha Goyal',
        avatarEmoji: '🏃',
        department: 'Computer Science (CSE)',
        hostel: 'Kalpana Chawla Bhawan',
        verifiedSteps: 42810,
        isCurrentUser: true,
      ),
      LeaderboardEntry(
        rank: 3,
        userId: 'raghav_789',
        userName: 'Raghav Bhatia',
        avatarEmoji: '🎯',
        department: 'Mechanical (ME)',
        hostel: 'Lohitya Bhawan',
        verifiedSteps: 39400,
      ),
      LeaderboardEntry(
        rank: 4,
        userId: 'kashish_101',
        userName: 'Kashish Arora',
        avatarEmoji: '⚡',
        department: 'Computer Science (CSE)',
        hostel: 'Meerabai Bhawan',
        verifiedSteps: 35600,
      ),
      LeaderboardEntry(
        rank: 5,
        userId: 'priya_202',
        userName: 'Priya Nair',
        avatarEmoji: '🌟',
        department: 'Biotechnology (BTECH)',
        hostel: 'Kasturba Bhawan',
        verifiedSteps: 31200,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────
// WALLET REPOSITORY
// ─────────────────────────────────────────────────────────
class LocalWalletRepository {
  Box get _box => Hive.box(HiveKeys.walletBox);

  WalletModel getWallet() {
    final raw = _box.get('wallet');
    if (raw != null) {
      try {
        return WalletModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw as String) as Map));
      } catch (_) {}
    }
    return _demoWallet();
  }

  Future<void> saveWallet(WalletModel wallet) async {
    await _box.put('wallet', jsonEncode(wallet.toJson()));
  }

  WalletModel _demoWallet() {
    final now = DateTime.now();
    return WalletModel(
      balance: 2450,
      transactions: [
        WalletTransaction(
          id: _uuid.v4(),
          type: TransactionType.credit,
          amount: 100,
          reason: TransactionReason.streakBonus,
          description: '7-Day Streak Bonus',
          timestamp: now.subtract(const Duration(hours: 2)),
        ),
        WalletTransaction(
          id: _uuid.v4(),
          type: TransactionType.credit,
          amount: 250,
          reason: TransactionReason.challengeReward,
          description: 'Challenge Completed: Morning 3K',
          timestamp: now.subtract(const Duration(days: 1)),
        ),
        WalletTransaction(
          id: _uuid.v4(),
          type: TransactionType.debit,
          amount: 500,
          reason: TransactionReason.betStake,
          description: 'Step Battle Stake vs Arjun',
          timestamp: now.subtract(const Duration(days: 1, hours: 8)),
        ),
        WalletTransaction(
          id: _uuid.v4(),
          type: TransactionType.credit,
          amount: 79,
          reason: TransactionReason.stepReward,
          description: 'Daily Step Reward',
          timestamp: now.subtract(const Duration(days: 2)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// PROVIDER REGISTRATIONS
// ─────────────────────────────────────────────────────────
final localUserRepositoryProvider =
    Provider<LocalUserRepository>((_) => LocalUserRepository());

final localActivityRepositoryProvider =
    Provider<LocalActivityRepository>((_) => LocalActivityRepository());

final localChallengeRepositoryProvider =
    Provider<LocalChallengeRepository>((_) => LocalChallengeRepository());

final localBetRepositoryProvider =
    Provider<LocalBetRepository>((_) => LocalBetRepository());

final localSportBuddyRepositoryProvider =
    Provider<LocalSportBuddyRepository>((_) => LocalSportBuddyRepository());

final localSessionRepositoryProvider =
    Provider<LocalSessionRepository>((_) => LocalSessionRepository());

final localLeaderboardRepositoryProvider =
    Provider<LocalLeaderboardRepository>((_) => LocalLeaderboardRepository());

final localWalletRepositoryProvider =
    Provider<LocalWalletRepository>((_) => LocalWalletRepository());
