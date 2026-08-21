import 'package:equatable/equatable.dart';

// ─────────────────────────────────────────────────────────
// RAW ACTIVITY RECORD  (from Health Connect / HealthKit)
// ─────────────────────────────────────────────────────────
class ActivityRecord extends Equatable {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int steps;
  final double distanceMeters;
  final String activityType;     // 'walking' | 'running' | 'unknown'
  final double? cadenceStepsPerMin;
  final double? speedKmh;
  final String? sourceApp;       // e.g. 'Samsung Health', 'Pacer'
  final String platform;         // 'android' | 'ios'
  final bool isDemoData;

  const ActivityRecord({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.steps,
    required this.distanceMeters,
    required this.activityType,
    this.cadenceStepsPerMin,
    this.speedKmh,
    this.sourceApp,
    required this.platform,
    this.isDemoData = false,
  });

  Duration get duration => endTime.difference(startTime);

  double get durationMinutes => duration.inSeconds / 60.0;

  double get computedCadence {
    if (cadenceStepsPerMin != null) return cadenceStepsPerMin!;
    if (durationMinutes <= 0) return 0;
    return steps / durationMinutes;
  }

  double get computedSpeedKmh {
    if (speedKmh != null) return speedKmh!;
    final hours = duration.inSeconds / 3600.0;
    if (hours <= 0) return 0;
    return (distanceMeters / 1000.0) / hours;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'steps': steps,
        'distanceMeters': distanceMeters,
        'activityType': activityType,
        'cadenceStepsPerMin': cadenceStepsPerMin,
        'speedKmh': speedKmh,
        'sourceApp': sourceApp,
        'platform': platform,
        'isDemoData': isDemoData,
      };

  factory ActivityRecord.fromJson(Map<String, dynamic> j) => ActivityRecord(
        id: j['id'] as String,
        startTime: DateTime.parse(j['startTime'] as String),
        endTime: DateTime.parse(j['endTime'] as String),
        steps: j['steps'] as int,
        distanceMeters: (j['distanceMeters'] as num).toDouble(),
        activityType: j['activityType'] as String,
        cadenceStepsPerMin: (j['cadenceStepsPerMin'] as num?)?.toDouble(),
        speedKmh: (j['speedKmh'] as num?)?.toDouble(),
        sourceApp: j['sourceApp'] as String?,
        platform: j['platform'] as String,
        isDemoData: j['isDemoData'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [id, startTime, steps];
}

// ─────────────────────────────────────────────────────────
// INTEGRITY CLASSIFICATION
// ─────────────────────────────────────────────────────────
enum ActivityClass {
  genuineWalking,
  genuineRunning,
  phoneShaking,
  vehicleMovement,
  duplicateSync,
  unknown,
}

extension ActivityClassX on ActivityClass {
  String get label {
    switch (this) {
      case ActivityClass.genuineWalking:
        return 'Genuine Walking';
      case ActivityClass.genuineRunning:
        return 'Genuine Running';
      case ActivityClass.phoneShaking:
        return 'Phone Shaking';
      case ActivityClass.vehicleMovement:
        return 'Vehicle Movement';
      case ActivityClass.duplicateSync:
        return 'Duplicate Sync';
      case ActivityClass.unknown:
        return 'Unknown';
    }
  }

  bool get isGenuine =>
      this == ActivityClass.genuineWalking ||
      this == ActivityClass.genuineRunning;

  String get emoji {
    switch (this) {
      case ActivityClass.genuineWalking:
        return '🚶';
      case ActivityClass.genuineRunning:
        return '🏃';
      case ActivityClass.phoneShaking:
        return '📱';
      case ActivityClass.vehicleMovement:
        return '🚗';
      case ActivityClass.duplicateSync:
        return '🔄';
      case ActivityClass.unknown:
        return '❓';
    }
  }
}

// ─────────────────────────────────────────────────────────
// INTEGRITY RESULT
// ─────────────────────────────────────────────────────────
class IntegrityResult extends Equatable {
  final String activityRecordId;
  final ActivityClass classification;
  final double confidence;         // 0.0 – 1.0
  final int verifiedSteps;
  final int suspiciousSteps;
  final List<String> positiveReasons;
  final List<String> negativeReasons;
  final String detectorVersion;    // 'rule_based_v1' | 'ml_v1'
  final DateTime evaluatedAt;
  final bool isBaseline;           // true = prototype / baseline
  final bool isDemoData;

  const IntegrityResult({
    required this.activityRecordId,
    required this.classification,
    required this.confidence,
    required this.verifiedSteps,
    required this.suspiciousSteps,
    required this.positiveReasons,
    required this.negativeReasons,
    required this.detectorVersion,
    required this.evaluatedAt,
    this.isBaseline = true,
    this.isDemoData = false,
  });

  double get integrityPercent =>
      (verifiedSteps + suspiciousSteps) == 0
          ? 0
          : verifiedSteps / (verifiedSteps + suspiciousSteps);

  Map<String, dynamic> toJson() => {
        'activityRecordId': activityRecordId,
        'classification': classification.name,
        'confidence': confidence,
        'verifiedSteps': verifiedSteps,
        'suspiciousSteps': suspiciousSteps,
        'positiveReasons': positiveReasons,
        'negativeReasons': negativeReasons,
        'detectorVersion': detectorVersion,
        'evaluatedAt': evaluatedAt.toIso8601String(),
        'isBaseline': isBaseline,
        'isDemoData': isDemoData,
      };

  factory IntegrityResult.fromJson(Map<String, dynamic> j) => IntegrityResult(
        activityRecordId: j['activityRecordId'] as String,
        classification: ActivityClass.values.firstWhere(
          (e) => e.name == j['classification'],
          orElse: () => ActivityClass.unknown,
        ),
        confidence: (j['confidence'] as num).toDouble(),
        verifiedSteps: j['verifiedSteps'] as int,
        suspiciousSteps: j['suspiciousSteps'] as int,
        positiveReasons: List<String>.from(j['positiveReasons'] as List),
        negativeReasons: List<String>.from(j['negativeReasons'] as List),
        detectorVersion: j['detectorVersion'] as String,
        evaluatedAt: DateTime.parse(j['evaluatedAt'] as String),
        isBaseline: j['isBaseline'] as bool? ?? true,
        isDemoData: j['isDemoData'] as bool? ?? false,
      );

  @override
  List<Object?> get props =>
      [activityRecordId, classification, verifiedSteps, confidence];
}

// ─────────────────────────────────────────────────────────
// DAILY ACTIVITY SUMMARY
// ─────────────────────────────────────────────────────────
class DailyActivitySummary extends Equatable {
  final DateTime date;
  final int importedSteps;
  final int verifiedSteps;
  final int suspiciousSteps;
  final double distanceMeters;
  final int walkingMinutes;
  final int runningMinutes;
  final double integrityScore;    // 0.0 – 1.0
  final int xpEarned;
  final int coinsEarned;
  final List<String> recordIds;
  final bool isDemoData;

  const DailyActivitySummary({
    required this.date,
    required this.importedSteps,
    required this.verifiedSteps,
    required this.suspiciousSteps,
    required this.distanceMeters,
    required this.walkingMinutes,
    required this.runningMinutes,
    required this.integrityScore,
    required this.xpEarned,
    required this.coinsEarned,
    required this.recordIds,
    this.isDemoData = false,
  });

  String get integrityLabel {
    if (integrityScore >= 0.90) return 'Excellent';
    if (integrityScore >= 0.75) return 'Good';
    if (integrityScore >= 0.55) return 'Fair';
    return 'Poor';
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'importedSteps': importedSteps,
        'verifiedSteps': verifiedSteps,
        'suspiciousSteps': suspiciousSteps,
        'distanceMeters': distanceMeters,
        'walkingMinutes': walkingMinutes,
        'runningMinutes': runningMinutes,
        'integrityScore': integrityScore,
        'xpEarned': xpEarned,
        'coinsEarned': coinsEarned,
        'recordIds': recordIds,
        'isDemoData': isDemoData,
      };

  factory DailyActivitySummary.fromJson(Map<String, dynamic> j) =>
      DailyActivitySummary(
        date: DateTime.parse(j['date'] as String),
        importedSteps: j['importedSteps'] as int,
        verifiedSteps: j['verifiedSteps'] as int,
        suspiciousSteps: j['suspiciousSteps'] as int,
        distanceMeters: (j['distanceMeters'] as num).toDouble(),
        walkingMinutes: j['walkingMinutes'] as int,
        runningMinutes: j['runningMinutes'] as int,
        integrityScore: (j['integrityScore'] as num).toDouble(),
        xpEarned: j['xpEarned'] as int,
        coinsEarned: j['coinsEarned'] as int,
        recordIds: List<String>.from(j['recordIds'] as List),
        isDemoData: j['isDemoData'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [date, verifiedSteps, integrityScore];
}

// ─────────────────────────────────────────────────────────
// SENSOR SAMPLE (raw, session-only — NOT from Health APIs)
// ─────────────────────────────────────────────────────────
class SensorSample {
  final DateTime timestamp;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;

  const SensorSample({
    required this.timestamp,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
  });

  double get accelMagnitude =>
      _sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    double x = v, y = 1;
    double e = 0.000001;
    while (x - y > e) {
      x = (x + y) / 2;
      y = v / x;
    }
    return x;
  }
}

// ─────────────────────────────────────────────────────────
// VERIFIED SESSION  (StepUp-recorded — richer data)
// ─────────────────────────────────────────────────────────
class VerifiedSessionRecord extends Equatable {
  final String id;
  final String userId;
  final DateTime startTime;
  final DateTime endTime;
  final String activityType;      // 'walking' | 'running'
  final IntegrityResult integrityResult;
  final int deviceStepCount;       // from pedometer during session
  final String platform;
  final bool isDemoData;

  const VerifiedSessionRecord({
    required this.id,
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.activityType,
    required this.integrityResult,
    required this.deviceStepCount,
    required this.platform,
    this.isDemoData = false,
  });

  Duration get duration => endTime.difference(startTime);

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'activityType': activityType,
        'integrityResult': integrityResult.toJson(),
        'deviceStepCount': deviceStepCount,
        'platform': platform,
        'isDemoData': isDemoData,
      };

  factory VerifiedSessionRecord.fromJson(Map<String, dynamic> j) =>
      VerifiedSessionRecord(
        id: j['id'] as String,
        userId: j['userId'] as String,
        startTime: DateTime.parse(j['startTime'] as String),
        endTime: DateTime.parse(j['endTime'] as String),
        activityType: j['activityType'] as String,
        integrityResult:
            IntegrityResult.fromJson(j['integrityResult'] as Map<String, dynamic>),
        deviceStepCount: j['deviceStepCount'] as int,
        platform: j['platform'] as String,
        isDemoData: j['isDemoData'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [id, startTime, integrityResult];
}
