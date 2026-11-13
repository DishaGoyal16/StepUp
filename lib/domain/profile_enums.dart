/// Enumerations used in `users/{uid}` and `publicProfiles/{uid}` with their
/// wire values (what the backend stores) and display labels.
library;

enum FitnessLevel {
  beginner('BEGINNER', 'Beginner'),
  intermediate('INTERMEDIATE', 'Intermediate'),
  advanced('ADVANCED', 'Advanced');

  const FitnessLevel(this.wire, this.label);
  final String wire;
  final String label;

  static FitnessLevel? fromWire(Object? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

enum PreferredTime {
  morning('MORNING', 'Morning'),
  afternoon('AFTERNOON', 'Afternoon'),
  evening('EVENING', 'Evening'),
  night('NIGHT', 'Night'),
  anytime('ANYTIME', 'Anytime');

  const PreferredTime(this.wire, this.label);
  final String wire;
  final String label;

  static PreferredTime? fromWire(Object? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

enum BuddyType {
  individual('INDIVIDUAL', 'One-on-one'),
  group('GROUP', 'Group'),
  both('BOTH', 'Either');

  const BuddyType(this.wire, this.label);
  final String wire;
  final String label;

  static BuddyType? fromWire(Object? v) {
    for (final e in values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

/// Sports a student can pick as interests / preferred activity.
const List<String> kSportsOptions = [
  'Cricket',
  'Football',
  'Basketball',
  'Badminton',
  'Volleyball',
  'Tennis',
  'Running',
  'Walking',
  'Gym',
  'Cycling',
  'Swimming',
  'Table Tennis',
  'Yoga',
  'Other',
];

const int kBioMaxLength = 160;
const int kDefaultDailyGoal = 10000;
const int kMinDailyGoal = 1000;
const int kMaxDailyGoal = 50000;
