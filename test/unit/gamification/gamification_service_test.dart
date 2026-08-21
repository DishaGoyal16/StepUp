import 'package:flutter_test/flutter_test.dart';
import 'package:thapar_stepup/core/services/gamification_service.dart';
import 'package:thapar_stepup/data/models/activity_models.dart';
import 'package:thapar_stepup/data/models/user_model.dart';

void main() {
  // ─── GamificationService ──────────────────────────────────────
  group('GamificationService.calculateXP', () {
    test('walking: 1 XP per 10 verified steps', () {
      final result = IntegrityResult(
        activityRecordId: 'test',
        classification: ActivityClass.genuineWalking,
        confidence: 0.9,
        verifiedSteps: 1000,
        suspiciousSteps: 0,
        positiveReasons: [],
        negativeReasons: [],
        detectorVersion: 'rule_based_v1',
        evaluatedAt: DateTime.now(),
        isBaseline: true,
      );
      expect(GamificationService.calculateXP(result), 100);
    });

    test('running: 2 XP per 10 verified steps', () {
      final result = IntegrityResult(
        activityRecordId: 'test',
        classification: ActivityClass.genuineRunning,
        confidence: 0.95,
        verifiedSteps: 1000,
        suspiciousSteps: 0,
        positiveReasons: [],
        negativeReasons: [],
        detectorVersion: 'rule_based_v1',
        evaluatedAt: DateTime.now(),
        isBaseline: true,
      );
      expect(GamificationService.calculateXP(result), 200);
    });

    test('suspicious activity earns 0 XP', () {
      final result = IntegrityResult(
        activityRecordId: 'test',
        classification: ActivityClass.phoneShaking,
        confidence: 0.2,
        verifiedSteps: 0,
        suspiciousSteps: 500,
        positiveReasons: [],
        negativeReasons: [],
        detectorVersion: 'rule_based_v1',
        evaluatedAt: DateTime.now(),
        isBaseline: true,
      );
      expect(GamificationService.calculateXP(result), 0);
    });
  });

  group('GamificationService.calculateCoins', () {
    test('10 coins per 1000 verified steps', () {
      expect(GamificationService.calculateCoins(1000), 10);
      expect(GamificationService.calculateCoins(5000), 50);
      expect(GamificationService.calculateCoins(500), 5);
    });

    test('zero steps earns zero coins', () {
      expect(GamificationService.calculateCoins(0), 0);
    });
  });

  group('GamificationService.levelFromXP', () {
    test('0 XP → Level 1', () {
      expect(GamificationService.levelFromXP(0), 1);
    });
    test('200 XP → Level 2', () {
      expect(GamificationService.levelFromXP(200), 2);
    });
    test('500 XP → Level 3', () {
      expect(GamificationService.levelFromXP(500), 3);
    });
    test('10000 XP → Level 10', () {
      expect(GamificationService.levelFromXP(10000), 10);
    });
    test('99999 XP → max Level 10', () {
      expect(GamificationService.levelFromXP(99999), 10);
    });
    test('199 XP stays at Level 1', () {
      expect(GamificationService.levelFromXP(199), 1);
    });
  });

  group('GamificationService.updateStreak', () {
    test('consecutive day increases streak', () {
      final user = _makeUser(currentStreak: 3);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final updated = GamificationService.updateStreak(user, yesterday);
      expect(updated.currentStreak, 4);
    });

    test('non-consecutive day resets streak to 1', () {
      final user = _makeUser(currentStreak: 10);
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final updated = GamificationService.updateStreak(user, twoDaysAgo);
      expect(updated.currentStreak, 1);
    });

    test('consecutive day updates longestStreak when exceeded', () {
      final user = _makeUser(currentStreak: 14, longestStreak: 14);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final updated = GamificationService.updateStreak(user, yesterday);
      expect(updated.currentStreak, 15);
      expect(updated.longestStreak, 15);
    });

    test('today date does not double-count streak', () {
      final user = _makeUser(currentStreak: 5);
      final today = DateTime.now();
      final updated = GamificationService.updateStreak(user, today);
      // Streak unchanged since it was already counted today
      expect(updated.currentStreak, 5);
    });
  });

  group('GamificationService.spendCoins', () {
    test('sufficient balance deducts correctly', () {
      final user = _makeUser(stepCoins: 1000);
      final updated = GamificationService.spendCoins(user, 500);
      expect(updated, isNotNull);
      expect(updated!.stepCoins, 500);
    });

    test('insufficient balance returns null', () {
      final user = _makeUser(stepCoins: 200);
      final updated = GamificationService.spendCoins(user, 500);
      expect(updated, isNull);
    });

    test('spending exact balance leaves 0', () {
      final user = _makeUser(stepCoins: 500);
      final updated = GamificationService.spendCoins(user, 500);
      expect(updated!.stepCoins, 0);
    });
  });

  group('GamificationService.streakBonusXP', () {
    test('less than 3 days earns no bonus', () {
      expect(GamificationService.streakBonusXP(1), 0);
      expect(GamificationService.streakBonusXP(2), 0);
    });

    test('3+ days earns bonus', () {
      expect(GamificationService.streakBonusXP(3), 25);
      expect(GamificationService.streakBonusXP(6), 50);
      expect(GamificationService.streakBonusXP(9), 75);
    });
  });
}

UserModel _makeUser({
  int currentStreak = 0,
  int longestStreak = 0,
  int stepCoins = 1000,
}) {
  return UserModel(
    id: 'test_user',
    name: 'Test User',
    email: 'test@thapar.edu',
    department: 'CSE',
    year: '3rd Year',
    hostel: 'KCB',
    stepCoins: stepCoins,
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    createdAt: DateTime(2024, 1, 1),
    lastActiveAt: DateTime(2024, 1, 1),
  );
}
