/// Plain-language explanations of why some steps are not counted.
/// Engine reason codes come from `getBucketsForSync` / the verifier.
class StepReasonInfo {
  const StepReasonInfo(this.code, this.title, this.explanation);

  final String code;
  final String title;
  final String explanation;
}

const List<StepReasonInfo> kStepReasons = [
  StepReasonInfo(
    'SHAKE_PATTERN',
    'Shaking',
    'The phone moved like it was being shaken, not carried by someone walking.',
  ),
  StepReasonInfo(
    'NOT_GAIT',
    'Not a walking pattern',
    'The motion did not look like walking or running, so the steps were not credited.',
  ),
  StepReasonInfo(
    'VEHICLE_MOTION',
    'Vehicle motion',
    'The phone seemed to be in a vehicle (bus, car, bike). Steps counted while riding are not credited.',
  ),
  StepReasonInfo(
    'EXCESS_OVER_IMU',
    'More steps than the motion supports',
    'The step counter reported more steps than your movement sensors could confirm, so only the confirmed part counts.',
  ),
  StepReasonInfo(
    'NO_IMU_EVIDENCE',
    'No motion evidence',
    'There was not enough movement-sensor data to confirm the steps (for example the app could not run in the background).',
  ),
];

StepReasonInfo? stepReasonFor(String? code) {
  for (final r in kStepReasons) {
    if (r.code == code) return r;
  }
  return null;
}

/// Short glossary of the step categories shown in the app.
const List<(String, String)> kStepCategoryGlossary = [
  ('Verified', 'Steps confirmed by your phone\'s movement sensors. Only these count for challenges, bets, leaderboards and rewards.'),
  ('Pending', 'Steps from the last couple of minutes that are still being checked.'),
  ('Rejected', 'Steps that did not look like genuine walking.'),
  ('Suspicious', 'Rejected steps that looked like shaking, a vehicle or an impossible walking speed.'),
  ('Unwitnessed', 'Steps counted by the phone while the movement sensors had no data, so they cannot be confirmed.'),
];
