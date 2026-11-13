/// `dailyStepSummaries/{uid}_{dayKey}` - the server-confirmed daily totals.
/// Only [verifiedSteps] feeds leaderboards, challenges, bets and rewards.
class DailyStepSummary {
  const DailyStepSummary({
    required this.dayKey,
    this.uid = '',
    this.hostelId,
    this.rawSteps = 0,
    this.verifiedSteps = 0,
    this.rejectedSteps = 0,
    this.unwitnessedSteps = 0,
    this.pendingSteps = 0,
  });

  factory DailyStepSummary.fromMap(Map<String, dynamic> m) => DailyStepSummary(
        uid: (m['uid'] as String?) ?? '',
        dayKey: (m['dayKey'] as String?) ?? '',
        hostelId: m['hostelId'] as String?,
        rawSteps: (m['rawSteps'] as num?)?.toInt() ?? 0,
        verifiedSteps: (m['verifiedSteps'] as num?)?.toInt() ?? 0,
        rejectedSteps: (m['rejectedSteps'] as num?)?.toInt() ?? 0,
        unwitnessedSteps: (m['unwitnessedSteps'] as num?)?.toInt() ?? 0,
        pendingSteps: (m['pendingSteps'] as num?)?.toInt() ?? 0,
      );

  final String uid;
  final String dayKey;
  final String? hostelId;
  final int rawSteps;
  final int verifiedSteps;
  final int rejectedSteps;
  final int unwitnessedSteps;
  final int pendingSteps;
}
