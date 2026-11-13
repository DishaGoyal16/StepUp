import 'package:intl/intl.dart';

import '../../data/buddies/buddy_models.dart';
import '../../domain/profile_enums.dart';

const Map<String, String> _dayLabels = {
  'MON': 'Mon',
  'TUE': 'Tue',
  'WED': 'Wed',
  'THU': 'Thu',
  'FRI': 'Fri',
  'SAT': 'Sat',
  'SUN': 'Sun',
};

/// `MON` -> `Mon` (unknown values are returned unchanged).
String dayLabel(String wire) => _dayLabels[wire] ?? wire;

/// Weekdays of [days] in calendar order, e.g. `Mon, Wed, Sat`.
String daysSummary(Iterable<String> days) {
  final set = days.toSet();
  return [for (final d in BuddyFilters.weekdays) if (set.contains(d)) dayLabel(d)].join(', ');
}

final NumberFormat _stepsFormat = NumberFormat.decimalPattern('en_IN');

/// `12,345` style grouping.
String formatSteps(int steps) => _stepsFormat.format(steps);

/// "Running · Morning" (either part may be missing; null when both are).
String? preferenceSummary(BuddyProfile p) {
  final parts = <String>[
    if (p.preferredActivity != null) p.preferredActivity!,
    if (p.preferredTime != null) p.preferredTime!.label,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String relationBadgeLabel(BuddyRelation r) => switch (r) {
      BuddyRelation.buddy => 'Buddy',
      BuddyRelation.requestSent => 'Pending',
      BuddyRelation.requestReceived => 'Wants to connect',
      BuddyRelation.none => '',
    };

/// "just now", "5 min ago", "3 h ago", "2 d ago", or a short date.
String timeAgo(DateTime? t, DateTime now) {
  if (t == null) return '';
  final d = now.difference(t);
  if (d.isNegative || d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat.MMMd().format(t);
}

String fitnessLabel(FitnessLevel? l) => l?.label ?? '';
