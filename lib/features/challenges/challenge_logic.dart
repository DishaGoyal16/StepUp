import 'package:intl/intl.dart' show NumberFormat;

import '../../data/challenges/challenge_models.dart';
import '../../domain/day_key.dart';

/// Pure presentation logic of the challenges feature: labels, progress
/// percentages, countdowns and the join decision. No Flutter, no I/O, so it is
/// fully unit-tested. Nothing here decides winners or progress - those values
/// come from the server.

final NumberFormat _num = NumberFormat.decimalPattern('en_US');

String formatCount(int n) => _num.format(n);

String typeLabel(ChallengeType t) => switch (t) {
      ChallengeType.individual => 'Individual',
      ChallengeType.buddy => 'Buddy',
      ChallengeType.interHostel => 'Inter-Hostel',
      ChallengeType.campus => 'Campus',
    };

/// Challenge status in plain words.
String statusLabel(ChallengeStatus s) => switch (s) {
      ChallengeStatus.pending => 'Waiting for buddy',
      ChallengeStatus.upcoming => 'Upcoming',
      ChallengeStatus.active => 'Active',
      ChallengeStatus.completed => 'Completed',
      ChallengeStatus.cancelled => 'Cancelled',
    };

/// My own participation status in plain words.
String participantStatusLabel(ParticipantStatus s) => switch (s) {
      ParticipantStatus.invited => 'Invited',
      ParticipantStatus.joined => 'Joined',
      ParticipantStatus.left => 'Left',
      ParticipantStatus.completed => 'Completed',
    };

/// The goal in plain words (never the raw metric name).
String targetText(Challenge c) {
  final daily = formatCount(c.dailyTarget ?? 0);
  return switch (c.metric) {
    ChallengeMetric.totalSteps => 'Walk ${formatCount(c.target)} verified steps',
    ChallengeMetric.dailyTargetDays => c.target == 1
        ? 'Reach $daily verified steps in a day'
        : 'Reach $daily verified steps on ${c.target} days',
    ChallengeMetric.streakDays =>
      'Reach $daily verified steps every day for ${c.target} days in a row',
  };
}

/// What the progress number counts.
String metricUnit(ChallengeMetric m) => switch (m) {
      ChallengeMetric.totalSteps => 'steps',
      ChallengeMetric.dailyTargetDays => 'days',
      ChallengeMetric.streakDays => 'days in a row',
    };

/// `3,200 / 50,000 steps`, `2 / 25 days`, `3 / 7 days in a row`.
String progressText(Challenge c, int progress) =>
    '${formatCount(progress)} / ${formatCount(c.target)} ${metricUnit(c.metric)}';

/// A bare value with its unit, e.g. `3,200 steps`.
String valueText(Challenge c, int value) => '${formatCount(value)} ${metricUnit(c.metric)}';

/// 0..1 fraction for progress bars.
double progressFraction(int progress, int target) {
  if (target <= 0 || progress <= 0) return 0;
  return (progress / target).clamp(0.0, 1.0);
}

/// Whole percent (floored, so 99.6 % is never shown as complete).
int progressPercent(int progress, int target) {
  if (target <= 0 || progress <= 0) return 0;
  return ((100 * progress) ~/ target).clamp(0, 100);
}

/// How hostels are ranked in an INTER_HOSTEL challenge.
String aggregationRule(Challenge c) {
  final noun = switch (c.metric) {
    ChallengeMetric.totalSteps => 'verified steps',
    ChallengeMetric.dailyTargetDays => 'days reaching the daily target',
    ChallengeMetric.streakDays => 'streak days',
  };
  return c.hostelAggregation == HostelAggregation.total
      ? 'Ranked by total $noun'
      : 'Ranked by average $noun per participant';
}

/// `2d 5h`, `5h 20m`, `12m`.
String formatDuration(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  final m = d.inMinutes;
  return '${m < 1 ? 1 : m}m';
}

String _dayRange(DateTime start, DateTime end) {
  final first = DayKey.label(DayKey.of(start));
  final last = DayKey.label(DayKey.of(end.subtract(const Duration(milliseconds: 1))));
  return first == last ? first : '$first to $last';
}

/// Dates or duration, in plain words.
String scheduleText(Challenge c) {
  final start = c.startAt;
  final end = c.endAt;
  if (start != null && end != null) return _dayRange(start, end);
  final days = c.durationDays;
  final length = days == null ? null : (days == 1 ? '1 day' : '$days days');
  if (c.type == ChallengeType.buddy) {
    return '${length ?? 'Set duration'}, starts at the next midnight (IST) after your buddy accepts';
  }
  if (c.isRolling) {
    return '${length ?? 'Flexible'}, starts the day you join';
  }
  return length ?? 'Dates to be announced';
}

/// The instant my part of the challenge ends: the fixed end date, or - for a
/// rolling challenge I joined - the end of my personal window.
DateTime? effectiveEnd(Challenge c, ChallengeParticipation? mine) {
  if (!c.isRolling) return c.endAt;
  final we = mine?.windowEnd;
  if (we == null || !RegExp(r'^\d{8}$').hasMatch(we)) return null;
  return DayKey.parse(we).add(const Duration(days: 1));
}

/// "Starts in 2d 5h" / "Ends in 3h 20m" / "Finished" (or `null`).
String? countdownText(Challenge c, DateTime now, {ChallengeParticipation? mine}) {
  switch (c.status) {
    case ChallengeStatus.pending:
      return 'Starts after your buddy accepts';
    case ChallengeStatus.upcoming:
      final start = c.startAt;
      if (start == null) return null;
      final d = start.difference(now);
      return d <= Duration.zero ? 'Starting now' : 'Starts in ${formatDuration(d)}';
    case ChallengeStatus.active:
      final end = effectiveEnd(c, mine);
      if (end == null) return null;
      final d = end.difference(now);
      return d <= Duration.zero
          ? 'Ended - final results are being calculated'
          : 'Ends in ${formatDuration(d)}';
    case ChallengeStatus.completed:
      return 'Finished';
    case ChallengeStatus.cancelled:
      return null;
  }
}

enum JoinState {
  canJoin,
  joined,
  completed,
  inviteOnly,
  notOpen,
  ended,
  full,
  hostelNotEligible,
}

class JoinDecision {
  const JoinDecision(this.state, [this.reason]);

  final JoinState state;

  /// Human-readable explanation when joining is not possible.
  final String? reason;

  bool get canJoin => state == JoinState.canJoin;
}

/// Mirrors the server's join checks so that the UI can explain WHY a user
/// cannot join. The server stays the authority (it re-checks everything).
JoinDecision decideJoin({
  required Challenge challenge,
  required ChallengeParticipation? mine,
  required String? myHostelId,
  required DateTime now,
}) {
  if (mine?.status == ParticipantStatus.completed) {
    return const JoinDecision(JoinState.completed, 'You have completed this challenge.');
  }
  if (mine?.status == ParticipantStatus.joined) {
    return const JoinDecision(JoinState.joined);
  }
  if (challenge.type == ChallengeType.buddy) {
    return const JoinDecision(
      JoinState.inviteOnly,
      'Buddy challenges are joined through an invitation from your buddy.',
    );
  }
  switch (challenge.status) {
    case ChallengeStatus.completed:
      return const JoinDecision(JoinState.ended, 'This challenge has finished.');
    case ChallengeStatus.cancelled:
      return const JoinDecision(JoinState.notOpen, 'This challenge was cancelled.');
    case ChallengeStatus.pending:
      return const JoinDecision(JoinState.notOpen, 'This challenge is not open yet.');
    case ChallengeStatus.upcoming:
      if (challenge.isRolling) {
        return const JoinDecision(JoinState.notOpen, 'This challenge is not open yet.');
      }
    case ChallengeStatus.active:
      break;
  }
  if (!challenge.isRolling) {
    final end = challenge.endAt;
    if (end != null && !end.isAfter(now)) {
      return const JoinDecision(JoinState.ended, 'This challenge has already ended.');
    }
  }
  if (challenge.type == ChallengeType.interHostel &&
      (myHostelId == null || !challenge.hostelIds.contains(myHostelId))) {
    return const JoinDecision(
      JoinState.hostelNotEligible,
      'Only students from the competing hostels can join. Your hostel is not part of this competition.',
    );
  }
  if (challenge.isFull) {
    return const JoinDecision(JoinState.full, 'This challenge is full.');
  }
  return const JoinDecision(JoinState.canJoin);
}

/// Leaving is allowed for my own running participation, never for buddy
/// challenges and never once the challenge is over.
bool canLeave(Challenge challenge, ChallengeParticipation? mine) =>
    mine != null &&
    mine.isJoined &&
    challenge.type != ChallengeType.buddy &&
    challenge.status.isOpen;

/// Winner line for the results panel; derived only from the server's result.
String winnerText(ChallengeResult result, {required String? myUid, required String? myHostelId}) {
  if (!result.hasWinner) return 'No winner for this challenge';
  final name = result.winnerName ?? (result.winnerHostelId != null ? 'A hostel' : 'A student');
  if (result.winnerUid != null && result.winnerUid == myUid) return 'You won!';
  if (result.winnerHostelId != null && result.winnerHostelId == myHostelId) {
    return '$name won - your hostel!';
  }
  return '$name won';
}
