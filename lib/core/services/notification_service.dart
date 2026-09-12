import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

// ─────────────────────────────────────────────────────────
// NOTIFICATION SERVICE
// ─────────────────────────────────────────────────────────
/// Abstract notification service — prepares architecture for both local
/// demo notifications and future push notifications from the backend.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  final Logger _log = Logger();
  bool _initialized = false;

  NotificationService(this._plugin);

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(settings);
      _initialized = true;
      _log.i('NotificationService initialized');
    } catch (e) {
      _log.w('NotificationService init failed: $e');
    }
  }

  // ── Notification Channels (Android) ──────────────────
  Future<void> _createChannels() async {
    const activityChannel = AndroidNotificationChannel(
      'activity_channel',
      'Activity Reminders',
      description: 'Reminders to stay active and maintain your streak.',
      importance: Importance.defaultImportance,
    );

    const battleChannel = AndroidNotificationChannel(
      'battle_channel',
      'Step Battles',
      description: 'Updates on your Step Battles.',
      importance: Importance.high,
    );

    const sessionChannel = AndroidNotificationChannel(
      'session_channel',
      'Sport Sessions',
      description: 'Reminders and updates for upcoming sport sessions.',
      importance: Importance.high,
    );

    const achievementChannel = AndroidNotificationChannel(
      'achievement_channel',
      'Achievements',
      description: 'Badge and achievement notifications.',
      importance: Importance.defaultImportance,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(activityChannel);
    await androidPlugin?.createNotificationChannel(battleChannel);
    await androidPlugin?.createNotificationChannel(sessionChannel);
    await androidPlugin?.createNotificationChannel(achievementChannel);
  }

  // ── Public API ────────────────────────────────────────

  Future<void> showStreakReminder() async {
    await _show(
      id: 1001,
      channelId: 'activity_channel',
      title: '🔥 Keep your streak alive!',
      body: 'You haven\'t logged any verified steps today. '
          'Start a session to maintain your streak.',
    );
  }

  Future<void> showBattleAccepted(String opponentName) async {
    await _show(
      id: 2001,
      channelId: 'battle_channel',
      title: '⚔️ Step Battle accepted!',
      body: '$opponentName accepted your Step Battle challenge. Let\'s go!',
    );
  }

  Future<void> showBattleWon(String opponentName, int coinsWon) async {
    await _show(
      id: 2002,
      channelId: 'battle_channel',
      title: '🏆 You won the Step Battle!',
      body: 'You beat $opponentName and earned $coinsWon StepCoins!',
    );
  }

  Future<void> showSessionReminder(String sport, String time) async {
    await _show(
      id: 3001,
      channelId: 'session_channel',
      title: '🏸 Session starting soon!',
      body: 'Your $sport session starts at $time. Get ready!',
    );
  }

  Future<void> showBadgeUnlocked(String badgeName, String badgeEmoji) async {
    await _show(
      id: 4001,
      channelId: 'achievement_channel',
      title: '$badgeEmoji Badge Unlocked!',
      body: 'You unlocked the "$badgeName" badge. Keep it up!',
    );
  }

  Future<void> showChallengeCompleted(String challengeName) async {
    await _show(
      id: 4002,
      channelId: 'achievement_channel',
      title: '🏆 Challenge completed!',
      body: 'You completed "$challengeName". Rewards have been added to your wallet.',
    );
  }

  Future<void> showDemoNotification() async {
    await _show(
      id: 9999,
      channelId: 'activity_channel',
      title: '📱 Demo Notification',
      body: 'This is how Thapar StepUp will notify you about activity, '
          'battles, and achievements.',
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ── Private ───────────────────────────────────────────
  Future<void> _show({
    required int id,
    required String channelId,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      _log.w('NotificationService not initialized, skipping notification');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(id, title, body, details, payload: payload);
    } catch (e) {
      _log.w('Failed to show notification: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────
final flutterLocalNotificationsProvider =
    Provider<FlutterLocalNotificationsPlugin>(
  (ref) => FlutterLocalNotificationsPlugin(),
);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(
    ref.read(flutterLocalNotificationsProvider),
  );
});
