abstract class AppConstants {
  // App identity
  static const String appName = 'Thapar StepUp';
  static const String tagline = 'Your Campus. Your Steps. Your Challenge.';
  static const String version = '1.0.0';

  // Step goals
  static const int defaultDailyStepGoal = 10000;
  static const int minDailyStepGoal = 2000;
  static const int maxDailyStepGoal = 30000;

  // Gamification — XP
  static const int xpPerVerifiedStep = 1;       // 1 XP per 10 verified steps
  static const int xpPerVerifiedStepDivisor = 10;
  static const int xpPerRunningStep = 2;        // Running earns double
  static const int xpPerRunningStepDivisor = 10;
  static const int xpChallengeDaily = 50;
  static const int xpChallengeWeekly = 200;
  static const int xpChallengeCampus = 500;
  static const int xpSportSession = 100;
  static const int xpStreakBonus = 25;          // per streak day
  static const int xpBetWin = 150;

  // Gamification — Coins
  static const int coinsPerThousandSteps = 10;
  static const int coinsChallengeDaily = 25;
  static const int coinsChallengeWeekly = 100;
  static const int coinsChallengeCampus = 300;
  static const int coinsSportSession = 50;
  static const int coinsStreakBonus = 10;

  // Levels
  static const List<LevelConfig> levels = [
    LevelConfig(level: 1, title: 'Fresh Starter',     xpRequired: 0),
    LevelConfig(level: 2, title: 'Active Student',    xpRequired: 200),
    LevelConfig(level: 3, title: 'Campus Walker',     xpRequired: 500),
    LevelConfig(level: 4, title: 'Fitness Grinder',   xpRequired: 1000),
    LevelConfig(level: 5, title: 'Step Warrior',      xpRequired: 1800),
    LevelConfig(level: 6, title: 'Campus Runner',     xpRequired: 2800),
    LevelConfig(level: 7, title: 'Elite Mover',       xpRequired: 4000),
    LevelConfig(level: 8, title: 'Campus Athlete',    xpRequired: 5500),
    LevelConfig(level: 9, title: 'StepUp Legend',     xpRequired: 7500),
    LevelConfig(level: 10, title: 'StepUp Champion',  xpRequired: 10000),
  ];

  // Activity integrity thresholds
  static const double minWalkingCadence = 60.0;    // steps/min
  static const double maxWalkingCadence = 140.0;
  static const double minRunningCadence = 140.0;
  static const double maxRunningCadence = 220.0;
  static const double maxWalkingSpeedKmh = 7.5;
  static const double maxRunningSpeedKmh = 30.0;
  static const double vehicleSpeedThresholdKmh = 15.0;
  static const double minAccelerationVariance = 0.1;
  static const double maxShakingAccelVariance = 15.0;
  static const double shakingDetectionThreshold = 25.0;
  static const double duplicateSyncWindowSeconds = 300.0;
  static const double minConfidenceForVerification = 0.5;

  // Feature windows (seconds) for sensor analysis
  static const int walkingWindowSeconds = 10;
  static const int runningWindowSeconds = 10;
  static const int shakingWindowSeconds = 7;
  static const int vehicleWindowSeconds = 30;
  static const int sessionMinDurationSeconds = 30;

  // Sport matching weights
  static const double matchWeightSkill = 0.40;
  static const double matchWeightReliability = 0.30;
  static const double matchWeightPreference = 0.30;
  static const double minMatchScoreToShow = 0.50;

  // Reliability tracking (exponential moving average alpha)
  static const double reliabilityAlpha = 0.3;
  static const double defaultReliability = 1.0;

  // Step Battle
  static const List<int> battleTargets = [2000, 5000, 7500, 10000, 15000];
  static const List<int> battleStakes = [100, 250, 500, 1000, 2500];
  static const List<String> battleDurations = ['Today', '24 hours', '3 days', '7 days'];
  static const int startingWalletBalance = 1000;

  // Sports supported
  static const List<String> supportedSports = [
    'Badminton',
    'Cricket',
    'Football',
    'Basketball',
    'Volleyball',
    'Running',
    'Table Tennis',
    'Tennis',
    'Gym/Workout',
  ];

  static const List<String> skillLevels = [
    'Beginner',
    'Intermediate',
    'Advanced',
    'Pro',
  ];

  // Campus zones (coarse only — no GPS trails)
  static const List<String> campusZones = [
    'Hostel Zone A',
    'Hostel Zone B',
    'Hostel Zone C',
    'Hostel Zone D',
    'Academic Block',
    'Sports Complex',
    'Main Gate Area',
    'Off Campus',
  ];

  // Thapar departments
  static const List<String> departments = [
    'Computer Science (CSE)',
    'Electronics (ECE)',
    'Mechanical (ME)',
    'Civil (CE)',
    'Chemical (CHE)',
    'Biotechnology (BTECH)',
    'Physics (PHY)',
    'Mathematics (MATH)',
    'MBA',
    'MCA',
    'Other',
  ];

  static const List<String> years = ['1st Year', '2nd Year', '3rd Year', '4th Year', 'PG'];

  static const List<String> hostels = [
    'Kalpana Chawla Bhawan',
    'Sarojini Naidu Bhawan',
    'Kasturba Bhawan',
    'Meerabai Bhawan',
    'Lohitya Bhawan',
    'Ganga Bhawan',
    'Yamuna Bhawan',
    'Sutlej Bhawan',
    'Beas Bhawan',
    'Cauvery Bhawan',
    'Day Scholar',
  ];
}

class LevelConfig {
  final int level;
  final String title;
  final int xpRequired;
  const LevelConfig({
    required this.level,
    required this.title,
    required this.xpRequired,
  });
}
