import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_model.dart';
import '../../data/models/gamification_models.dart';
import '../../data/models/activity_models.dart';
import '../constants/app_constants.dart';

// ─────────────────────────────────────────────────────────
// GAMIFICATION SERVICE
// ─────────────────────────────────────────────────────────
class GamificationService {
  /// Calculate XP earned from an integrity result
  static int calculateXP(IntegrityResult result) {
    if (!result.classification.isGenuine) return 0;
    final isRunning = result.classification == ActivityClass.genuineRunning;
    if (isRunning) {
      return (result.verifiedSteps *
              AppConstants.xpPerRunningStep /
              AppConstants.xpPerRunningStepDivisor)
          .round();
    }
    return (result.verifiedSteps *
            AppConstants.xpPerVerifiedStep /
            AppConstants.xpPerVerifiedStepDivisor)
        .round();
  }

  /// Calculate StepCoins earned from verified steps
  static int calculateCoins(int verifiedSteps) {
    return (verifiedSteps / 1000 * AppConstants.coinsPerThousandSteps).round();
  }

  /// Calculate streak bonus XP
  static int streakBonusXP(int streakDays) {
    if (streakDays < 3) return 0;
    return AppConstants.xpStreakBonus * (streakDays ~/ 3);
  }

  /// Determine level from total XP
  static int levelFromXP(int xp) {
    const thresholds = [0, 200, 500, 1000, 1800, 2800, 4000, 5500, 7500, 10000];
    int level = 1;
    for (int i = 0; i < thresholds.length; i++) {
      if (xp >= thresholds[i]) level = i + 1;
    }
    return level.clamp(1, 10);
  }

  /// Apply XP gain to user model
  static UserModel applyXPGain(UserModel user, int xpGain) {
    final newXP = user.xp + xpGain;
    final newLevel = levelFromXP(newXP);
    return user.copyWith(xp: newXP, level: newLevel);
  }

  /// Apply coin gain to user model
  static UserModel applyCoinGain(UserModel user, int coins) {
    final newCoins = (user.stepCoins + coins).clamp(0, 9999999);
    return user.copyWith(stepCoins: newCoins);
  }

  /// Apply coin spend to user model
  static UserModel? spendCoins(UserModel user, int coins) {
    if (user.stepCoins < coins) return null; // insufficient
    return user.copyWith(stepCoins: user.stepCoins - coins);
  }

  /// Update streak
  static UserModel updateStreak(UserModel user, DateTime lastActiveDate) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final isConsecutive = lastActiveDate.year == yesterday.year &&
        lastActiveDate.month == yesterday.month &&
        lastActiveDate.day == yesterday.day;
    final isToday = lastActiveDate.year == today.year &&
        lastActiveDate.month == today.month &&
        lastActiveDate.day == today.day;

    if (isToday) return user; // already counted today
    if (isConsecutive) {
      final newStreak = user.currentStreak + 1;
      final newLongest =
          newStreak > user.longestStreak ? newStreak : user.longestStreak;
      return user.copyWith(
        currentStreak: newStreak,
        longestStreak: newLongest,
        lastActiveAt: today,
      );
    }
    // Streak broken
    return user.copyWith(currentStreak: 1, lastActiveAt: today);
  }

  /// Evaluate which badges should be unlocked
  static List<BadgeModel> evaluateBadges(
      UserModel user, List<BadgeModel> allBadges) {
    return allBadges.map((badge) {
      if (badge.isUnlocked) return badge;
      final shouldUnlock = _checkBadgeCondition(badge.id, user);
      if (shouldUnlock) {
        return badge.copyWith(isUnlocked: true, unlockedAt: DateTime.now());
      }
      return badge;
    }).toList();
  }

  static bool _checkBadgeCondition(String badgeId, UserModel user) {
    switch (badgeId) {
      case 'first_run':
        return user.totalVerifiedSteps > 500;
      case 'streak_7':
        return user.currentStreak >= 7;
      case 'streak_30':
        return user.currentStreak >= 30;
      case 'steps_10k':
        return user.totalVerifiedSteps >= 10000;
      case 'steps_50k':
        return user.totalVerifiedSteps >= 50000;
      case 'steps_100k':
        return user.totalVerifiedSteps >= 100000;
      case 'level_5':
        return user.level >= 5;
      case 'level_10':
        return user.level >= 10;
      case 'sessions_5':
        return user.completedSessions >= 5;
      case 'reliable_buddy':
        return user.reliabilityScore >= 0.9 && user.completedSessions >= 3;
      default:
        return false;
    }
  }
}

// ─────────────────────────────────────────────────────────
// ALL BADGES CATALOG
// ─────────────────────────────────────────────────────────
final allBadgesCatalog = [
  const BadgeModel(
    id: 'first_run',
    name: 'First Steps',
    description: 'Complete your first verified activity',
    emoji: '🏃',
    rarity: BadgeRarity.common,
  ),
  const BadgeModel(
    id: 'streak_7',
    name: '7-Day Streak',
    description: 'Stay active 7 days in a row',
    emoji: '🔥',
    rarity: BadgeRarity.common,
  ),
  const BadgeModel(
    id: 'streak_30',
    name: '30-Day Champion',
    description: 'Maintain a 30-day streak',
    emoji: '⚡',
    rarity: BadgeRarity.epic,
  ),
  const BadgeModel(
    id: 'steps_10k',
    name: '10K Verified',
    description: 'Reach 10,000 verified steps total',
    emoji: '👟',
    rarity: BadgeRarity.common,
  ),
  const BadgeModel(
    id: 'steps_50k',
    name: '50K Mover',
    description: 'Reach 50,000 verified steps total',
    emoji: '🛡',
    rarity: BadgeRarity.rare,
  ),
  const BadgeModel(
    id: 'steps_100k',
    name: 'Century Club',
    description: 'Reach 100,000 verified steps total',
    emoji: '🏆',
    rarity: BadgeRarity.legendary,
  ),
  const BadgeModel(
    id: 'level_5',
    name: 'Step Warrior',
    description: 'Reach Level 5',
    emoji: '⚔',
    rarity: BadgeRarity.rare,
  ),
  const BadgeModel(
    id: 'level_10',
    name: 'StepUp Champion',
    description: 'Reach the maximum level',
    emoji: '👑',
    rarity: BadgeRarity.legendary,
  ),
  const BadgeModel(
    id: 'sessions_5',
    name: 'Sport Enthusiast',
    description: 'Complete 5 verified sport sessions',
    emoji: '🏸',
    rarity: BadgeRarity.rare,
  ),
  const BadgeModel(
    id: 'reliable_buddy',
    name: 'Reliable Buddy',
    description: 'Maintain 90%+ reliability with 3+ sessions',
    emoji: '🤝',
    rarity: BadgeRarity.rare,
  ),
  const BadgeModel(
    id: 'integrity_champ',
    name: 'Integrity Champion',
    description: 'Score 95%+ integrity on 10 sessions',
    emoji: '🛡',
    rarity: BadgeRarity.epic,
  ),
  const BadgeModel(
    id: 'battle_winner',
    name: 'Step Battle Winner',
    description: 'Win your first Step Battle',
    emoji: '⚔',
    rarity: BadgeRarity.rare,
  ),
];

// ─────────────────────────────────────────────────────────
// GAMIFICATION PROVIDER
// ─────────────────────────────────────────────────────────
final gamificationServiceProvider = Provider<GamificationService>(
  (_) => GamificationService(),
);
