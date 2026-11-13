import 'package:intl/intl.dart' show NumberFormat;

import '../../data/leaderboard/leaderboard_models.dart';
import '../../domain/day_key.dart';

final NumberFormat _num = NumberFormat.decimalPattern('en_US');

/// `12,345` (fractions are rounded: averages are shown as whole steps).
String formatSteps(num n) => _num.format(n.round());

/// Fallback label when the server sends no `metricLabel`.
String defaultMetricLabel(LeaderboardQuery q) {
  if (q.isHostelBoard) {
    return q.hostelMetric == HostelMetric.average
        ? 'Average verified steps per participant'
        : 'Total verified steps';
  }
  return 'Verified steps';
}

/// Human text for a period key: `Fri 13 Nov`, `Nov 2026`, `Week 2026-W46`,
/// `All time`. Unknown formats are shown as sent.
String periodKeyLabel(LeaderboardPeriod period, String? key) {
  if (period == LeaderboardPeriod.allTime) return 'All time';
  if (key == null || key.isEmpty) return period.label;
  switch (period) {
    case LeaderboardPeriod.daily:
      if (RegExp(r'^\d{8}$').hasMatch(key)) return DayKey.label(key);
      return key;
    case LeaderboardPeriod.monthly:
      final m = RegExp(r'^(\d{4})-?(\d{2})$').firstMatch(key);
      if (m != null) {
        final month = int.parse(m.group(2)!);
        if (month >= 1 && month <= 12) {
          const names = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
          ];
          return '${names[month - 1]} ${m.group(1)}';
        }
      }
      return key;
    case LeaderboardPeriod.weekly:
      return 'Week $key';
    case LeaderboardPeriod.allTime:
      return 'All time';
  }
}

/// `just now`, `5 min ago`, `3 h ago`, otherwise an IST date like `12 Nov, 18:05`.
String updatedLabel(DateTime updatedAt, DateTime now) {
  final diff = now.toUtc().difference(updatedAt.toUtc());
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  final ist = updatedAt.toUtc().add(DayKey.istOffset);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = ist.hour.toString().padLeft(2, '0');
  final mm = ist.minute.toString().padLeft(2, '0');
  return '${ist.day} ${months[ist.month - 1]}, $hh:$mm';
}

/// The single "Ranked by ... · ... · updated ..." line shown above the list.
String metaLine(LeaderboardResult r, DateTime now) {
  final label = r.metricLabel ?? defaultMetricLabel(r.query);
  final parts = <String>[
    'Ranked by $label',
    periodKeyLabel(r.query.period, r.periodKey),
    if (r.updatedAt != null) 'updated ${updatedLabel(r.updatedAt!, now)}',
  ];
  return parts.join(' · ');
}
