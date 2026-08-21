import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../data/models/activity_models.dart';

// ─────────────────────────────────────────────────────────
// MOTION SENSOR SERVICE INTERFACE
// ─────────────────────────────────────────────────────────
/// Cross-platform abstraction:
///   Android → SensorManager (via sensors_plus)
///   iOS     → Core Motion  (via sensors_plus)
///
/// Raw sensor data is collected ONLY during explicit verified sessions.
/// It is NOT collected continuously.
abstract class MotionSensorService {
  /// Start buffering sensor samples.
  void startSession();

  /// Stop buffering and return collected samples.
  /// Raw samples are discarded after feature extraction.
  List<SensorSample> stopSession();

  /// Stream of live accelerometer magnitude for UI feedback.
  Stream<double> get liveAccelMagnitude;

  bool get isSessionActive;
  String get platformName;
}

// ─────────────────────────────────────────────────────────
// FACTORY
// ─────────────────────────────────────────────────────────
class MotionSensorServiceFactory {
  static MotionSensorService create() {
    if (kIsWeb) return MockMotionSensorService();
    if (Platform.isAndroid) return NativeMotionSensorService();
    if (Platform.isIOS) return NativeMotionSensorService();
    return MockMotionSensorService();
  }
}

// ─────────────────────────────────────────────────────────
// NATIVE — uses sensors_plus (works on Android & iOS)
//   Android: SensorManager accelerometer + gyroscope
//   iOS:     CMMotion accelerometer + gyroscope
// ─────────────────────────────────────────────────────────
class NativeMotionSensorService implements MotionSensorService {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  final List<SensorSample> _buffer = [];
  final _liveController = StreamController<double>.broadcast();
  GyroscopeEvent? _lastGyro;
  bool _active = false;

  @override
  String get platformName =>
      Platform.isIOS ? 'Core Motion (iOS)' : 'SensorManager (Android)';

  @override
  bool get isSessionActive => _active;

  @override
  Stream<double> get liveAccelMagnitude => _liveController.stream;

  @override
  void startSession() {
    if (_active) return;
    _active = true;
    _buffer.clear();

    // Gyroscope subscription (optional — may not be available on all devices)
    _gyroSub = gyroscopeEventStream().listen(
      (event) => _lastGyro = event,
      onError: (_) => _gyroSub = null,
    );

    // Accelerometer at ~50 Hz
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      final sample = SensorSample(
        timestamp: DateTime.now(),
        accelX: event.x,
        accelY: event.y,
        accelZ: event.z,
        gyroX: _lastGyro?.x,
        gyroY: _lastGyro?.y,
        gyroZ: _lastGyro?.z,
      );
      _buffer.add(sample);
      if (!_liveController.isClosed) {
        _liveController.add(sample.accelMagnitude);
      }
    });
  }

  @override
  List<SensorSample> stopSession() {
    _active = false;
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;

    final result = List<SensorSample>.from(_buffer);
    _buffer.clear(); // discard raw data per privacy principle
    return result;
  }

  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _liveController.close();
  }
}

// ─────────────────────────────────────────────────────────
// MOCK — for demo and tests
// ─────────────────────────────────────────────────────────
class MockMotionSensorService implements MotionSensorService {
  bool _active = false;
  final _liveController = StreamController<double>.broadcast();
  Timer? _mockTimer;

  @override
  String get platformName => 'Mock Sensor (Demo)';

  @override
  bool get isSessionActive => _active;

  @override
  Stream<double> get liveAccelMagnitude => _liveController.stream;

  @override
  void startSession() {
    _active = true;
    // Emit simulated walking-like accelerometer values
    _mockTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_liveController.isClosed) {
        final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final mag = 9.8 + 1.2 * _sin(t * 1.7 * 3.14159);
        _liveController.add(mag);
      }
    });
  }

  @override
  List<SensorSample> stopSession() {
    _active = false;
    _mockTimer?.cancel();
    return _generateWalkingSamples();
  }

  static double _sin(double x) {
    // Taylor approximation for sin(x)
    final nx = x % (2 * 3.14159265);
    return nx - (nx * nx * nx) / 6.0 + (nx * nx * nx * nx * nx) / 120.0;
  }

  List<SensorSample> _generateWalkingSamples() {
    final samples = <SensorSample>[];
    final base = DateTime.now().subtract(const Duration(seconds: 30));
    for (int i = 0; i < 1500; i++) {
      final t = i / 50.0;
      final sinVal = _sin(t * 1.7 * 3.14159);
      samples.add(SensorSample(
        timestamp: base.add(Duration(milliseconds: (i * 20).round())),
        accelX: 0.3 * sinVal,
        accelY: 9.6 + 0.8 * sinVal,
        accelZ: 0.2 * sinVal,
      ));
    }
    return samples;
  }

  void dispose() {
    _mockTimer?.cancel();
    _liveController.close();
  }
}
