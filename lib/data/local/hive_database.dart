import 'package:hive_flutter/hive_flutter.dart';
import '../models/activity_models.dart';
import '../models/gamification_models.dart';
import '../models/sport_models.dart';
import '../models/user_model.dart';
import '../../core/constants/hive_keys.dart';

// ─────────────────────────────────────────────────────────
// HIVE DATABASE HELPER
// ─────────────────────────────────────────────────────────
/// Centralises all Hive box access.
/// The repositories use these typed accessors instead of
/// raw Hive.box() calls scattered through the codebase.
class HiveDatabase {
  // ── Boxes ─────────────────────────────────────────────
  static Box get userBox => Hive.box(HiveKeys.userBox);
  static Box get activityBox => Hive.box(HiveKeys.activityBox);
  static Box get challengeBox => Hive.box(HiveKeys.challengeBox);
  static Box get walletBox => Hive.box(HiveKeys.walletBox);
  static Box get sessionBox => Hive.box(HiveKeys.sessionBox);
  static Box get settingsBox => Hive.box(HiveKeys.settingsBox);
  static Box get betBox => Hive.box(HiveKeys.betBox);
  static Box get sportBuddyBox => Hive.box(HiveKeys.sportBuddyBox);
  static Box get leaderboardBox => Hive.box(HiveKeys.leaderboardBox);

  // ── User ──────────────────────────────────────────────
  static UserModel? readUser() {
    final raw = userBox.get(HiveKeys.currentUser);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeUser(UserModel user) async {
    await userBox.put(HiveKeys.currentUser, user.toJson());
  }

  static Future<void> deleteUser() async {
    await userBox.delete(HiveKeys.currentUser);
  }

  // ── Activity Records ──────────────────────────────────
  static List<ActivityRecord> readActivityRecords() {
    final raw = activityBox.get(HiveKeys.activityRecords);
    if (raw == null) return [];
    try {
      return (raw as List)
          .map((e) => ActivityRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeActivityRecords(List<ActivityRecord> records) async {
    await activityBox.put(
      HiveKeys.activityRecords,
      records.map((r) => r.toJson()).toList(),
    );
  }

  // ── Integrity Results ─────────────────────────────────
  static List<IntegrityResult> readIntegrityResults() {
    final raw = activityBox.get(HiveKeys.integrityResults);
    if (raw == null) return [];
    try {
      return (raw as List)
          .map((e) => IntegrityResult.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeIntegrityResults(List<IntegrityResult> results) async {
    await activityBox.put(
      HiveKeys.integrityResults,
      results.map((r) => r.toJson()).toList(),
    );
  }

  // ── Challenges ────────────────────────────────────────
  static List<ChallengeModel> readChallenges() {
    final raw = challengeBox.get(HiveKeys.challenges);
    if (raw == null) return [];
    try {
      return (raw as List)
          .map((e) => ChallengeModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeChallenges(List<ChallengeModel> challenges) async {
    await challengeBox.put(
      HiveKeys.challenges,
      challenges.map((c) => c.toJson()).toList(),
    );
  }

  // ── Wallet ────────────────────────────────────────────
  static WalletModel? readWallet() {
    final raw = walletBox.get(HiveKeys.wallet);
    if (raw == null) return null;
    try {
      return WalletModel.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeWallet(WalletModel wallet) async {
    await walletBox.put(HiveKeys.wallet, wallet.toJson());
  }

  // ── Bets ──────────────────────────────────────────────
  static List<BetModel> readBets() {
    final raw = betBox.get(HiveKeys.bets);
    if (raw == null) return [];
    try {
      return (raw as List)
          .map((e) => BetModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeBets(List<BetModel> bets) async {
    await betBox.put(
      HiveKeys.bets,
      bets.map((b) => b.toJson()).toList(),
    );
  }

  // ── Sport Profiles ────────────────────────────────────
  static List<SportProfile> readSportProfiles() {
    final raw = sportBuddyBox.get(HiveKeys.sportProfiles);
    if (raw == null) return [];
    try {
      return (raw as List)
          .map((e) => SportProfile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeSportProfiles(List<SportProfile> profiles) async {
    await sportBuddyBox.put(
      HiveKeys.sportProfiles,
      profiles.map((p) => p.toJson()).toList(),
    );
  }

  // ── Sport Sessions ────────────────────────────────────
  static List<SportSession> readSportSessions() {
    final raw = sessionBox.get(HiveKeys.sportSessions);
    if (raw == null) return [];
    try {
      return (raw as List)
          .map((e) => SportSession.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeSportSessions(List<SportSession> sessions) async {
    await sessionBox.put(
      HiveKeys.sportSessions,
      sessions.map((s) => s.toJson()).toList(),
    );
  }

  // ── Leaderboard ───────────────────────────────────────
  static LeaderboardModel? readLeaderboard(LeaderboardType type) {
    final raw = leaderboardBox.get(type.name);
    if (raw == null) return null;
    try {
      return LeaderboardModel.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeLeaderboard(LeaderboardModel leaderboard) async {
    await leaderboardBox.put(leaderboard.type.name, leaderboard.toJson());
  }

  // ── Clear All (for data reset / account deletion) ─────
  static Future<void> clearAll() async {
    await userBox.clear();
    await activityBox.clear();
    await challengeBox.clear();
    await walletBox.clear();
    await sessionBox.clear();
    await betBox.clear();
    await sportBuddyBox.clear();
    await leaderboardBox.clear();
    // Note: settingsBox is intentionally NOT cleared — preserves theme pref etc.
  }
}
