import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────
// STEP FORMATTER
// ─────────────────────────────────────────────────────────
class StepFormatter {
  /// Format a step count for display: 1,250 → "1,250" or 12500 → "12.5K"
  static String format(int steps) {
    if (steps >= 10000) {
      final k = steps / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}K';
    }
    return NumberFormat('#,###').format(steps);
  }

  /// Format large step counts for leaderboard display
  static String formatLong(int steps) {
    if (steps >= 1000000) {
      return '${(steps / 1000000).toStringAsFixed(1)}M';
    }
    if (steps >= 10000) {
      return '${(steps / 1000).toStringAsFixed(1)}K';
    }
    return NumberFormat('#,###').format(steps);
  }
}

// ─────────────────────────────────────────────────────────
// COIN FORMATTER
// ─────────────────────────────────────────────────────────
class CoinFormatter {
  static String format(int coins) {
    if (coins >= 1000) {
      final k = coins / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}K';
    }
    return coins.toString();
  }
}

// ─────────────────────────────────────────────────────────
// PERCENTAGE FORMATTER
// ─────────────────────────────────────────────────────────
class PercentFormatter {
  static String format(double value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  static String formatInt(double value) {
    return '${(value * 100).round()}%';
  }
}

// ─────────────────────────────────────────────────────────
// DATE / TIME UTILITIES
// ─────────────────────────────────────────────────────────
class DateUtils {
  static final _dayFormat = DateFormat('EEE, d MMM');
  static final _timeFormat = DateFormat('h:mm a');
  static final _shortDayFormat = DateFormat('EEE');
  static final _fullFormat = DateFormat('d MMM yyyy');

  static String formatDay(DateTime dt) => _dayFormat.format(dt);
  static String formatTime(DateTime dt) => _timeFormat.format(dt);
  static String formatShortDay(DateTime dt) => _shortDayFormat.format(dt);
  static String formatFull(DateTime dt) => _fullFormat.format(dt);

  static String relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatFull(dt);
  }

  static String syncStatus(DateTime? lastSync) {
    if (lastSync == null) return 'Never synced';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inMinutes < 2) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${diff.inDays}d ago';
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime get startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime get endOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  /// Format duration in seconds to mm:ss or hh:mm:ss
  static String formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Format seconds to a human-friendly string: "5 min", "1h 30m"
  static String humanDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    if (m > 0) return '${m}m';
    return '${totalSeconds}s';
  }
}

// ─────────────────────────────────────────────────────────
// LEVEL UTILITIES
// ─────────────────────────────────────────────────────────
class LevelUtils {
  static const _titles = [
    'Fresh Starter',    // L1
    'Active Student',   // L2
    'Campus Walker',    // L3
    'Fitness Grinder',  // L4
    'Step Hustler',     // L5
    'Campus Athlete',   // L6
    'Elite Runner',     // L7
    'Campus Champion',  // L8
    'StepUp Legend',    // L9
    'StepUp Champion',  // L10+
  ];

  static String titleForLevel(int level) {
    final idx = (level - 1).clamp(0, _titles.length - 1);
    return _titles[idx];
  }

  static int xpForLevel(int level) {
    // Progressive XP requirements
    return level * 500 + (level - 1) * 250;
  }

  static int levelFromXp(int xp) {
    int level = 1;
    int xpConsumed = 0;
    while (true) {
      final needed = xpForLevel(level);
      if (xpConsumed + needed > xp) break;
      xpConsumed += needed;
      level++;
      if (level >= 10) break;
    }
    return level;
  }

  static int xpInCurrentLevel(int xp, int level) {
    int consumed = 0;
    for (int l = 1; l < level; l++) {
      consumed += xpForLevel(l);
    }
    return xp - consumed;
  }

  static int xpToNextLevel(int level) => xpForLevel(level);
}

// ─────────────────────────────────────────────────────────
// INTEGRITY DISPLAY HELPERS
// ─────────────────────────────────────────────────────────
class IntegrityUtils {
  static String integrityLabel(double confidence) {
    if (confidence >= 0.95) return 'Excellent';
    if (confidence >= 0.85) return 'Good';
    if (confidence >= 0.70) return 'Fair';
    if (confidence >= 0.50) return 'Low';
    return 'Suspicious';
  }

  static String integrityEmoji(double confidence) {
    if (confidence >= 0.95) return '🛡️';
    if (confidence >= 0.85) return '✅';
    if (confidence >= 0.70) return '⚠️';
    return '🚩';
  }
}
