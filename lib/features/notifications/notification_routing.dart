import 'package:flutter/material.dart';

import '../../core/router/app_routes.dart';
import '../../data/notifications_center/app_notification.dart';

/// Where tapping a notification leads, or `null` when it is informational
/// only (nothing to open).
///
/// | type                                  | destination                        |
/// |---------------------------------------|------------------------------------|
/// | BUDDY_REQUEST                         | /buddies/requests                  |
/// | BUDDY_ACCEPTED                        | /buddies                           |
/// | CHALLENGE_* (+ `data.challengeId`)    | `/challenges/{challengeId}`        |
/// | BET_* (+ `data.betId`)                | `/bets/{betId}`                    |
/// | LEADERBOARD, HOSTEL_RESULT            | /leaderboard                       |
/// | SYSTEM with `data.badgeId`            | /profile (achievements)            |
///
/// A challenge / bet notification without an id falls back to the list screen.
String? notificationRoute(AppNotification n) {
  String? id(String key) {
    final v = n.data[key]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  switch (n.type) {
    case 'BUDDY_REQUEST':
      return AppRoutes.buddyRequests;
    case 'BUDDY_ACCEPTED':
      return AppRoutes.buddies;
    case 'CHALLENGE_NEW':
    case 'CHALLENGE_REMINDER':
    case 'CHALLENGE_DONE':
      final c = id('challengeId');
      return c == null ? AppRoutes.challenges : AppRoutes.challengeDetail(c);
    case 'BET_INVITE':
    case 'BET_RESULT':
      final b = id('betId');
      return b == null ? AppRoutes.bets : AppRoutes.betDetail(b);
    case 'LEADERBOARD':
    case 'HOSTEL_RESULT':
      return AppRoutes.leaderboard;
    case 'SYSTEM':
      return id('badgeId') == null ? null : AppRoutes.profile;
    default:
      return null;
  }
}

/// Leading icon + a short type label for a notification row.
({IconData icon, String label}) notificationVisual(String type) => switch (type) {
      'BUDDY_REQUEST' => (icon: Icons.person_add_alt_1_outlined, label: 'Buddy request'),
      'BUDDY_ACCEPTED' => (icon: Icons.group_outlined, label: 'Buddy'),
      'CHALLENGE_NEW' => (icon: Icons.emoji_events_outlined, label: 'Challenge'),
      'CHALLENGE_REMINDER' => (icon: Icons.alarm_outlined, label: 'Reminder'),
      'CHALLENGE_DONE' => (icon: Icons.flag_outlined, label: 'Challenge result'),
      'LEADERBOARD' => (icon: Icons.leaderboard_outlined, label: 'Leaderboard'),
      'BET_INVITE' => (icon: Icons.casino_outlined, label: 'Step bet'),
      'BET_RESULT' => (icon: Icons.paid_outlined, label: 'Bet result'),
      'HOSTEL_RESULT' => (icon: Icons.apartment_outlined, label: 'Hostel result'),
      _ => (icon: Icons.notifications_none, label: 'StepUp'),
    };

/// "just now", "5 min ago", "3 h ago", "Yesterday", or "12 Nov".
String formatNotificationTime(DateTime? at, DateTime now) {
  if (at == null) return '';
  final diff = now.toUtc().difference(at.toUtc());
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inHours < 48) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final ist = at.toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${ist.day} ${months[ist.month - 1]}';
}
