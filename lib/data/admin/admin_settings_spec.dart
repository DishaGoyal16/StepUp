/// One numeric field of `adminSettings/global` an admin may edit. Bounds
/// mirror `SETTING_BOUNDS` in `functions/src/admin/admin.ts` and defaults
/// mirror `DEFAULT_SETTINGS` in `functions/src/config.ts`. The server is the
/// authority; these only give instant feedback in the form.
class AdminSettingSpec {
  const AdminSettingSpec({
    required this.key,
    required this.label,
    required this.help,
    required this.group,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit,
  });

  final String key;
  final String label;
  final String help;
  final String group;
  final int min;
  final int max;
  final int defaultValue;
  final String? unit;

  /// `null` when [raw] is a valid value for this field, else a message.
  String? validate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Required.';
    final v = int.tryParse(t);
    if (v == null) return 'Enter a whole number.';
    if (v < min || v > max) return 'Must be between $min and $max.';
    return null;
  }
}

abstract final class AdminSettingGroups {
  static const stepLimits = 'Step validation limits';
  static const points = 'Points';
  static const bets = 'Step bets';
  static const other = 'Other';
}

/// Editable settings, in display order.
const List<AdminSettingSpec> adminSettingSpecs = [
  AdminSettingSpec(
    key: 'maxStepsPerBucket',
    label: 'Max steps per 10 s bucket',
    help: 'Buckets above this are rejected as impossible cadence.',
    group: AdminSettingGroups.stepLimits,
    min: 1,
    max: 35,
    defaultValue: 35,
    unit: 'steps',
  ),
  AdminSettingSpec(
    key: 'maxStepsPer30Min',
    label: 'Max steps per 30 minutes',
    help: 'Rolling 30 minute ceiling.',
    group: AdminSettingGroups.stepLimits,
    min: 1,
    max: 6300,
    defaultValue: 6300,
    unit: 'steps',
  ),
  AdminSettingSpec(
    key: 'maxRewardStepsPerDay',
    label: 'Max reward-eligible steps per day',
    help: 'Verified steps above this are stored but earn nothing.',
    group: AdminSettingGroups.stepLimits,
    min: 1000,
    max: 100000,
    defaultValue: 20000,
    unit: 'steps',
  ),
  AdminSettingSpec(
    key: 'maxBucketAgeHours',
    label: 'Oldest accepted bucket',
    help: 'Buckets older than this are not accepted.',
    group: AdminSettingGroups.stepLimits,
    min: 1,
    max: 168,
    defaultValue: 72,
    unit: 'hours',
  ),
  AdminSettingSpec(
    key: 'futureToleranceSec',
    label: 'Future clock tolerance',
    help: 'How far in the future a bucket timestamp may be.',
    group: AdminSettingGroups.stepLimits,
    min: 0,
    max: 600,
    defaultValue: 120,
    unit: 'seconds',
  ),
  AdminSettingSpec(
    key: 'settlementGraceHours',
    label: 'Settlement grace',
    help: 'Wait this long after a challenge/bet ends before settling it.',
    group: AdminSettingGroups.stepLimits,
    min: 0,
    max: 72,
    defaultValue: 6,
    unit: 'hours',
  ),
  AdminSettingSpec(
    key: 'dailyGoalDefault',
    label: 'Default daily goal',
    help: 'Daily step goal for new students.',
    group: AdminSettingGroups.points,
    min: 1000,
    max: 50000,
    defaultValue: 10000,
    unit: 'steps',
  ),
  AdminSettingSpec(
    key: 'pointsDailyGoal',
    label: 'Points for reaching the daily goal',
    help: 'Virtual points, paid once per day.',
    group: AdminSettingGroups.points,
    min: 0,
    max: 100000,
    defaultValue: 10,
    unit: 'points',
  ),
  AdminSettingSpec(
    key: 'pointsStreak7',
    label: 'Points for a 7-day streak',
    help: 'Virtual points.',
    group: AdminSettingGroups.points,
    min: 0,
    max: 100000,
    defaultValue: 50,
    unit: 'points',
  ),
  AdminSettingSpec(
    key: 'pointsChallengeComplete',
    label: 'Points for completing a challenge',
    help: 'Default completion reward.',
    group: AdminSettingGroups.points,
    min: 0,
    max: 100000,
    defaultValue: 50,
    unit: 'points',
  ),
  AdminSettingSpec(
    key: 'pointsChallengeWin',
    label: 'Points for winning a challenge',
    help: 'Default winner reward.',
    group: AdminSettingGroups.points,
    min: 0,
    max: 100000,
    defaultValue: 100,
    unit: 'points',
  ),
  AdminSettingSpec(
    key: 'betMinStake',
    label: 'Minimum bet stake',
    help: 'Virtual points each side stakes.',
    group: AdminSettingGroups.bets,
    min: 1,
    max: 100000,
    defaultValue: 10,
    unit: 'points',
  ),
  AdminSettingSpec(
    key: 'betMaxStake',
    label: 'Maximum bet stake',
    help: 'Must not be lower than the minimum stake.',
    group: AdminSettingGroups.bets,
    min: 1,
    max: 100000,
    defaultValue: 1000,
    unit: 'points',
  ),
  AdminSettingSpec(
    key: 'betExpiryHours',
    label: 'Pending bet expiry',
    help: 'A bet nobody answers expires after this.',
    group: AdminSettingGroups.bets,
    min: 1,
    max: 168,
    defaultValue: 48,
    unit: 'hours',
  ),
  AdminSettingSpec(
    key: 'rewardDeviceTakeoverDays',
    label: 'Reward device takeover',
    help: 'A reward device unseen this long may be replaced by a new one.',
    group: AdminSettingGroups.other,
    min: 1,
    max: 365,
    defaultValue: 14,
    unit: 'days',
  ),
  AdminSettingSpec(
    key: 'buddyRerequestCooldownHours',
    label: 'Buddy re-request cooldown',
    help: 'Wait after a rejected or cancelled buddy request.',
    group: AdminSettingGroups.other,
    min: 0,
    max: 168,
    defaultValue: 24,
    unit: 'hours',
  ),
];

/// Validates a whole settings form. [raw] maps each key to its text.
/// Returns field errors by key (empty = valid), including the cross-field
/// rule `betMaxStake >= betMinStake`.
Map<String, String> validateSettingsForm(Map<String, String> raw) {
  final errors = <String, String>{};
  for (final spec in adminSettingSpecs) {
    final msg = spec.validate(raw[spec.key] ?? '');
    if (msg != null) errors[spec.key] = msg;
  }
  if (!errors.containsKey('betMinStake') && !errors.containsKey('betMaxStake')) {
    final min = int.parse(raw['betMinStake']!.trim());
    final max = int.parse(raw['betMaxStake']!.trim());
    if (max < min) errors['betMaxStake'] = 'Must be at least the minimum stake.';
  }
  return errors;
}
