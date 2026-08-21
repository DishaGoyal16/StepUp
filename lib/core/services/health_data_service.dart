import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/activity_models.dart';

// ─────────────────────────────────────────────────────────
// HEALTH DATA SERVICE INTERFACE
// ─────────────────────────────────────────────────────────
/// Platform-agnostic interface.  UI never touches platform details.
abstract class HealthDataService {
  Future<bool> requestPermissions();
  Future<bool> get hasPermissions;
  Future<List<ActivityRecord>> fetchTodayRecords();
  Future<List<ActivityRecord>> fetchRecordsForRange(
      DateTime from, DateTime to);
  String get platformName;
}

// ─────────────────────────────────────────────────────────
// FACTORY — returns the right implementation
// ─────────────────────────────────────────────────────────
class HealthDataServiceFactory {
  static HealthDataService create() {
    if (kIsWeb) return MockHealthDataService();
    if (Platform.isAndroid) return AndroidHealthDataService();
    if (Platform.isIOS) return IOSHealthDataService();
    return MockHealthDataService();
  }
}

// ─────────────────────────────────────────────────────────
// ANDROID — Health Connect via `health` package
// ─────────────────────────────────────────────────────────
class AndroidHealthDataService implements HealthDataService {
  final Health _health = Health();

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_WALKING_RUNNING,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
  ];

  @override
  String get platformName => 'Health Connect (Android)';

  @override
  Future<bool> requestPermissions() async {
    try {
      // Activity Recognition permission
      await Permission.activityRecognition.request();

      final granted = await _health.requestAuthorization(
        _types,
        permissions: _types.map((_) => HealthDataAccess.READ).toList(),
      );
      return granted;
    } catch (e) {
      debugPrint('AndroidHealthDataService.requestPermissions error: $e');
      return false;
    }
  }

  @override
  Future<bool> get hasPermissions async {
    try {
      return await _health.hasPermissions(_types) ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<ActivityRecord>> fetchTodayRecords() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return fetchRecordsForRange(start, now);
  }

  @override
  Future<List<ActivityRecord>> fetchRecordsForRange(
      DateTime from, DateTime to) async {
    try {
      final dataPoints = await _health.getHealthDataFromTypes(
        startTime: from,
        endTime: to,
        types: _types,
      );

      // Group by time window and build ActivityRecord list
      return _groupToRecords(dataPoints, 'android');
    } catch (e) {
      debugPrint('AndroidHealthDataService.fetchRecords error: $e');
      return [];
    }
  }

  List<ActivityRecord> _groupToRecords(
      List<HealthDataPoint> points, String platform) {
    final stepsPoints =
        points.where((p) => p.type == HealthDataType.STEPS).toList();
    const uuid = Uuid();

    return stepsPoints.map((p) {
      final steps =
          int.tryParse(p.value.toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
              0;
      final durationMin =
          p.dateFrom.difference(p.dateTo).inMinutes.abs().toDouble();
      final cadence = durationMin > 0 ? steps / durationMin : null;

      return ActivityRecord(
        id: uuid.v4(),
        startTime: p.dateFrom,
        endTime: p.dateTo,
        steps: steps,
        distanceMeters: 0, // matched separately if available
        activityType: _inferType(cadence),
        cadenceStepsPerMin: cadence,
        sourceApp: p.sourceName,
        platform: platform,
      );
    }).toList();
  }

  String _inferType(double? cadence) {
    if (cadence == null) return 'unknown';
    if (cadence >= 140) return 'running';
    if (cadence >= 60) return 'walking';
    return 'unknown';
  }
}

// ─────────────────────────────────────────────────────────
// iOS — Apple HealthKit via `health` package
// ─────────────────────────────────────────────────────────
class IOSHealthDataService implements HealthDataService {
  final Health _health = Health();

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_WALKING_RUNNING,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
  ];

  @override
  String get platformName => 'Apple Health (iOS)';

  @override
  Future<bool> requestPermissions() async {
    try {
      return await _health.requestAuthorization(
        _types,
        permissions: _types.map((_) => HealthDataAccess.READ).toList(),
      );
    } catch (e) {
      debugPrint('IOSHealthDataService.requestPermissions error: $e');
      return false;
    }
  }

  @override
  Future<bool> get hasPermissions async {
    try {
      return await _health.hasPermissions(_types) ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<ActivityRecord>> fetchTodayRecords() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return fetchRecordsForRange(start, now);
  }

  @override
  Future<List<ActivityRecord>> fetchRecordsForRange(
      DateTime from, DateTime to) async {
    try {
      final dataPoints = await _health.getHealthDataFromTypes(
        startTime: from,
        endTime: to,
        types: _types,
      );
      return _groupToRecords(dataPoints, 'ios');
    } catch (e) {
      debugPrint('IOSHealthDataService.fetchRecords error: $e');
      return [];
    }
  }

  List<ActivityRecord> _groupToRecords(
      List<HealthDataPoint> points, String platform) {
    final stepsPoints =
        points.where((p) => p.type == HealthDataType.STEPS).toList();
    const uuid = Uuid();

    return stepsPoints.map((p) {
      final steps =
          int.tryParse(p.value.toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
              0;
      return ActivityRecord(
        id: uuid.v4(),
        startTime: p.dateFrom,
        endTime: p.dateTo,
        steps: steps,
        distanceMeters: 0,
        activityType: 'walking',
        sourceApp: p.sourceName,
        platform: platform,
      );
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────
// MOCK — for demo mode and tests
// ─────────────────────────────────────────────────────────
class MockHealthDataService implements HealthDataService {
  @override
  String get platformName => 'Demo Data';

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> get hasPermissions async => true;

  @override
  Future<List<ActivityRecord>> fetchTodayRecords() async =>
      DemoActivityData.todayRecords();

  @override
  Future<List<ActivityRecord>> fetchRecordsForRange(
      DateTime from, DateTime to) async =>
      DemoActivityData.weekRecords();
}

// ─────────────────────────────────────────────────────────
// DEMO ACTIVITY DATA  (clearly marked as simulated)
// ─────────────────────────────────────────────────────────
class DemoActivityData {
  static const uuid = Uuid();

  static List<ActivityRecord> todayRecords() {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    return [
      // Genuine morning walk
      ActivityRecord(
        id: uuid.v4(),
        startTime: base.add(const Duration(hours: 7, minutes: 0)),
        endTime: base.add(const Duration(hours: 7, minutes: 35)),
        steps: 3421,
        distanceMeters: 2480,
        activityType: 'walking',
        cadenceStepsPerMin: 97.7,
        speedKmh: 4.25,
        sourceApp: 'Samsung Health',
        platform: 'demo',
        isDemoData: true,
      ),
      // Genuine afternoon run
      ActivityRecord(
        id: uuid.v4(),
        startTime: base.add(const Duration(hours: 17, minutes: 30)),
        endTime: base.add(const Duration(hours: 18, minutes: 0)),
        steps: 4210,
        distanceMeters: 4100,
        activityType: 'running',
        cadenceStepsPerMin: 163.0,
        speedKmh: 8.2,
        sourceApp: 'Garmin',
        platform: 'demo',
        isDemoData: true,
      ),
      // Suspicious — phone shaking (injected)
      ActivityRecord(
        id: uuid.v4(),
        startTime: base.add(const Duration(hours: 12, minutes: 0)),
        endTime: base.add(const Duration(hours: 12, minutes: 5)),
        steps: 711,
        distanceMeters: 0,
        activityType: 'walking',
        cadenceStepsPerMin: 142.2,
        speedKmh: 0.0,
        sourceApp: 'Unknown App',
        platform: 'demo',
        isDemoData: true,
      ),
    ];
  }

  static List<ActivityRecord> weekRecords() {
    final records = <ActivityRecord>[];
    final today = DateTime.now();
    const weekSteps = [6800, 9200, 7100, 8900, 5500, 10200, 8642];
    for (int i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final base = DateTime(day.year, day.month, day.day);
      records.add(ActivityRecord(
        id: uuid.v4(),
        startTime: base.add(const Duration(hours: 7)),
        endTime: base.add(const Duration(hours: 20)),
        steps: weekSteps[6 - i],
        distanceMeters: weekSteps[6 - i] * 0.75,
        activityType: 'walking',
        cadenceStepsPerMin: 95,
        sourceApp: 'Demo',
        platform: 'demo',
        isDemoData: true,
      ));
    }
    return records;
  }
}
