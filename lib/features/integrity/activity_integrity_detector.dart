import 'dart:math' as math;
import '../../data/models/activity_models.dart';
import '../../core/constants/app_constants.dart';

// ─────────────────────────────────────────────────────────
// INTEGRITY DETECTOR INTERFACE
// ─────────────────────────────────────────────────────────
/// Abstract interface that both the rule-based baseline and any future
/// ML model must implement.  The rest of the app depends only on this.
abstract class ActivityIntegrityDetector {
  /// Evaluate an imported health record (no raw sensor data available).
  Future<IntegrityResult> evaluateImportedRecord(ActivityRecord record);

  /// Evaluate a StepUp-recorded session where raw sensor samples are available.
  Future<IntegrityResult> evaluateSessionRecord({
    required ActivityRecord record,
    required List<SensorSample> sensorSamples,
    required int deviceStepCount,
  });

  String get version;
  bool get isBaseline;
}

// ─────────────────────────────────────────────────────────
// SENSOR FEATURE EXTRACTION
// ─────────────────────────────────────────────────────────
class SensorFeatures {
  final double meanAccelMagnitude;
  final double varianceAccelMagnitude;
  final double peakCount;          // zero-crossings / sec (proxy for steps)
  final double regularityScore;    // 0–1
  final double maxAccelMagnitude;

  const SensorFeatures({
    required this.meanAccelMagnitude,
    required this.varianceAccelMagnitude,
    required this.peakCount,
    required this.regularityScore,
    required this.maxAccelMagnitude,
  });
}

SensorFeatures extractFeatures(List<SensorSample> samples) {
  if (samples.isEmpty) {
    return const SensorFeatures(
      meanAccelMagnitude: 9.8,
      varianceAccelMagnitude: 0,
      peakCount: 0,
      regularityScore: 0,
      maxAccelMagnitude: 9.8,
    );
  }

  final magnitudes = samples.map((s) => s.accelMagnitude).toList();
  final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
  final variance = magnitudes
          .map((m) => (m - mean) * (m - mean))
          .reduce((a, b) => a + b) /
      magnitudes.length;

  // Count zero-crossings of de-meaned signal as peak proxy
  final demeaned = magnitudes.map((m) => m - mean).toList();
  int crossings = 0;
  for (int i = 1; i < demeaned.length; i++) {
    if (demeaned[i - 1] < 0 && demeaned[i] >= 0) crossings++;
  }
  final durationSec = samples.isNotEmpty
      ? samples.last.timestamp
              .difference(samples.first.timestamp)
              .inMilliseconds /
          1000.0
      : 1.0;
  final peakRate = durationSec > 0 ? crossings / durationSec : 0;

  final maxMag = magnitudes.reduce(math.max);

  // Regularity: low variance relative to mean → high regularity
  final cv = mean > 0 ? math.sqrt(variance) / mean : 0;
  final regularity = math.max(0.0, 1.0 - cv);

  return SensorFeatures(
    meanAccelMagnitude: mean,
    varianceAccelMagnitude: variance,
    peakCount: peakRate.toDouble(),
    regularityScore: regularity.toDouble(),
    maxAccelMagnitude: maxMag,
  );
}

// ─────────────────────────────────────────────────────────
// RULE-BASED INTEGRITY DETECTOR  (Prototype / Baseline v1)
// ─────────────────────────────────────────────────────────
/// Transparent, rule-based baseline.
/// Does NOT claim ML accuracy — labeled as Prototype / Baseline.
class RuleBasedIntegrityDetector implements ActivityIntegrityDetector {
  @override
  final String version = 'rule_based_v1';

  @override
  final bool isBaseline = true;

  @override
  Future<IntegrityResult> evaluateImportedRecord(
      ActivityRecord record) async {
    // For imported records: apply plausibility rules only (no raw sensor)
    return _runRules(
      record: record,
      sensorFeatures: null,
      deviceStepCount: null,
    );
  }

  @override
  Future<IntegrityResult> evaluateSessionRecord({
    required ActivityRecord record,
    required List<SensorSample> sensorSamples,
    required int deviceStepCount,
  }) async {
    final features =
        sensorSamples.isNotEmpty ? extractFeatures(sensorSamples) : null;
    return _runRules(
      record: record,
      sensorFeatures: features,
      deviceStepCount: deviceStepCount,
    );
  }

  IntegrityResult _runRules({
    required ActivityRecord record,
    required SensorFeatures? sensorFeatures,
    required int? deviceStepCount,
  }) {
    final flags = <_Flag>[];

    // ── Cadence check ──────────────────────────────────────
    final cadence = record.computedCadence;
    final type = record.activityType;

    if (type == 'walking') {
      if (cadence >= AppConstants.minWalkingCadence &&
          cadence <= AppConstants.maxWalkingCadence) {
        flags.add(const _Flag(true, 'Plausible walking cadence'));
      } else if (cadence > AppConstants.maxWalkingCadence) {
        flags.add(const _Flag(false, 'Cadence too high for walking'));
      } else if (cadence > 0 && cadence < AppConstants.minWalkingCadence) {
        flags.add(const _Flag(false, 'Cadence too low'));
      }
    } else if (type == 'running') {
      if (cadence >= AppConstants.minRunningCadence &&
          cadence <= AppConstants.maxRunningCadence) {
        flags.add(const _Flag(true, 'Plausible running cadence'));
      } else {
        flags.add(const _Flag(false, 'Cadence outside running range'));
      }
    }

    // ── Speed check ────────────────────────────────────────
    final speed = record.computedSpeedKmh;
    if (speed > 0) {
      if (speed > AppConstants.vehicleSpeedThresholdKmh) {
        flags.add(const _Flag(false, 'Speed consistent with vehicle'));
      } else if (type == 'walking' &&
          speed <= AppConstants.maxWalkingSpeedKmh) {
        flags.add(const _Flag(true, 'Normal walking speed'));
      } else if (type == 'running' &&
          speed <= AppConstants.maxRunningSpeedKmh) {
        flags.add(const _Flag(true, 'Normal running speed'));
      }
    }

    // ── Duration / step plausibility ──────────────────────
    final durationMin = record.durationMinutes;
    final stepsPerMin = durationMin > 0 ? record.steps / durationMin : 0;
    if (stepsPerMin > 0 && stepsPerMin < 200) {
      flags.add(const _Flag(true, 'Plausible steps-per-minute'));
    } else if (stepsPerMin >= 200) {
      flags.add(const _Flag(false, 'Steps per minute implausibly high'));
    }

    // ── Sensor analysis (session only) ────────────────────
    if (sensorFeatures != null) {
      // Shaking detection: high variance, irregular peaks
      if (sensorFeatures.varianceAccelMagnitude >
          AppConstants.maxShakingAccelVariance) {
        flags.add(const _Flag(false, 'High acceleration variance (shaking?)'));
      } else if (sensorFeatures.regularityScore > 0.55) {
        flags.add(const _Flag(true, 'Consistent rhythmic motion'));
      } else {
        flags.add(const _Flag(false, 'Irregular motion pattern'));
      }

      // Step count consistency (sensor vs device counter)
      if (deviceStepCount != null && record.steps > 0) {
        final ratio = deviceStepCount / record.steps;
        if (ratio >= 0.7 && ratio <= 1.3) {
          flags.add(const _Flag(true, 'Step count matches device counter'));
        } else {
          flags.add(const _Flag(false, 'Step count mismatch with device'));
        }
      }
    }

    // ── Source / duplicate check ───────────────────────────
    if (record.sourceApp != null && record.sourceApp!.isNotEmpty) {
      flags.add(_Flag(true, 'Source identified: ${record.sourceApp}'));
    }

    // ── Determine classification ───────────────────────────
    final positives = flags.where((f) => f.positive).toList();
    final negatives = flags.where((f) => !f.positive).toList();

    // Detect vehicle
    final hasVehicleSpeed = negatives
        .any((f) => f.reason.contains('vehicle'));

    // Detect shaking
    final hasShaking = negatives.any((f) => f.reason.contains('shaking'));

    ActivityClass classification;
    if (hasVehicleSpeed) {
      classification = ActivityClass.vehicleMovement;
    } else if (hasShaking) {
      classification = ActivityClass.phoneShaking;
    } else if (negatives.length > positives.length) {
      classification = ActivityClass.unknown;
    } else if (type == 'running') {
      classification = ActivityClass.genuineRunning;
    } else {
      classification = ActivityClass.genuineWalking;
    }

    // ── Confidence ──────────────────────────────────────────
    final totalFlags = flags.length;
    final confidence = totalFlags == 0
        ? 0.5
        : positives.length / totalFlags;

    // ── Verified steps ─────────────────────────────────────
    int verifiedSteps;
    int suspiciousSteps;
    if (classification.isGenuine) {
      verifiedSteps = (record.steps * confidence).round();
      suspiciousSteps = record.steps - verifiedSteps;
    } else {
      verifiedSteps = 0;
      suspiciousSteps = record.steps;
    }

    return IntegrityResult(
      activityRecordId: record.id,
      classification: classification,
      confidence: confidence,
      verifiedSteps: verifiedSteps,
      suspiciousSteps: suspiciousSteps,
      positiveReasons: positives.map((f) => f.reason).toList(),
      negativeReasons: negatives.map((f) => f.reason).toList(),
      detectorVersion: version,
      evaluatedAt: DateTime.now(),
      isBaseline: true,
      isDemoData: record.isDemoData,
    );
  }
}

// ─────────────────────────────────────────────────────────
// ML INTEGRITY DETECTOR  (Placeholder — not yet trained)
// ─────────────────────────────────────────────────────────
/// Architecture stub ready to be connected to a trained TFLite/ONNX model.
/// Currently falls back to the rule-based detector.
/// DO NOT claim accuracy that has not been measured.
class MLIntegrityDetector implements ActivityIntegrityDetector {
  final ActivityIntegrityDetector _fallback = RuleBasedIntegrityDetector();

  @override
  final String version = 'ml_v1_placeholder';

  @override
  final bool isBaseline = false;

  /// TODO: Load TFLite / ONNX model from assets when available.
  bool get isModelLoaded => false;

  @override
  Future<IntegrityResult> evaluateImportedRecord(ActivityRecord record) async {
    if (!isModelLoaded) return _fallback.evaluateImportedRecord(record);
    // TODO: run model inference
    throw UnimplementedError('ML model not yet loaded');
  }

  @override
  Future<IntegrityResult> evaluateSessionRecord({
    required ActivityRecord record,
    required List<SensorSample> sensorSamples,
    required int deviceStepCount,
  }) async {
    if (!isModelLoaded) {
      return _fallback.evaluateSessionRecord(
        record: record,
        sensorSamples: sensorSamples,
        deviceStepCount: deviceStepCount,
      );
    }
    // TODO: extract features → flatten to float array → run inference
    throw UnimplementedError('ML model not yet loaded');
  }
}

// ─────────────────────────────────────────────────────────
// INTERNAL FLAG HELPER
// ─────────────────────────────────────────────────────────
class _Flag {
  final bool positive;
  final String reason;
  const _Flag(this.positive, this.reason);
}
