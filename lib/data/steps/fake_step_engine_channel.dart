import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../domain/step_models.dart';
import 'step_engine_channel.dart';

/// Scriptable [StepEngineChannel] for tests and `AppDependencies.fake()`.
class FakeStepEngineChannel implements StepEngineChannel {
  FakeStepEngineChannel({
    this.capabilities = const EngineCapabilities(
      stepCounter: true,
      accelerometer: true,
      gyroscope: true,
      activityRecognitionGranted: true,
      notificationsGranted: true,
      evidenceMode: 'IMU',
      sdkInt: 34,
      model: 'Fake Phone',
    ),
    this.todaySummary = const TodaySummary(),
    this.deviceId = 'fake-device-id',
    this.tracking = false,
  });

  EngineCapabilities capabilities;
  TodaySummary todaySummary;
  String deviceId;
  bool tracking;
  StartTrackingResult startResult = const StartTrackingResult(started: true);
  LiveStatus liveStatus = const LiveStatus();

  /// Result returned by [bindUser] (scriptable).
  BindResult bindResult = const BindResult(bound: true, changed: true, sinceMs: 0);

  /// Every uid passed to [bindUser], in order.
  final List<String> bindCalls = [];

  /// When set, [bindUser] waits for it (simulates a slow native bind).
  Completer<void>? bindGate;

  /// When set, [getTodaySummary] waits for it (simulates a slow native call).
  Completer<void>? todayGate;

  /// Buckets waiting to be synced (not yet acknowledged).
  final List<EngineBucket> pendingBuckets = [];

  /// Every start time that was acknowledged, in order.
  final List<int> ackedStartMs = [];

  /// Names of methods called, in order.
  final List<String> calls = [];

  final Map<String, List<Object>> _failures = {};
  final StreamController<LiveSnapshot> _events = StreamController<LiveSnapshot>.broadcast();

  void addBuckets(Iterable<EngineBucket> b) => pendingBuckets.addAll(b);

  /// Queues an error thrown by the next call to [method].
  void failNext(String method, [Object? error]) {
    (_failures[method] ??= []).add(
      error ?? const AppException(code: 'engine-error', message: 'fake failure'),
    );
  }

  void emit(LiveSnapshot s) => _events.add(s);

  void _enter(String method) {
    calls.add(method);
    final q = _failures[method];
    if (q != null && q.isNotEmpty) throw q.removeAt(0);
  }

  @override
  Future<EngineCapabilities> getCapabilities() async {
    _enter('getCapabilities');
    return capabilities;
  }

  @override
  Future<StartTrackingResult> startTracking() async {
    _enter('startTracking');
    if (startResult.started) tracking = true;
    return startResult;
  }

  @override
  Future<void> stopTracking() async {
    _enter('stopTracking');
    tracking = false;
  }

  @override
  Future<bool> isTracking() async {
    _enter('isTracking');
    return tracking;
  }

  @override
  Future<TodaySummary> getTodaySummary({required int dayStartMs, required int dayEndMs}) async {
    _enter('getTodaySummary');
    final gate = todayGate;
    if (gate != null) await gate.future;
    return todaySummary;
  }

  @override
  Future<List<EngineBucket>> getBucketsForSync({int limit = 200}) async {
    _enter('getBucketsForSync');
    final sorted = [...pendingBuckets]..sort((a, b) => a.startMs.compareTo(b.startMs));
    return sorted.take(limit).toList();
  }

  @override
  Future<int> ackBuckets(List<int> startMsList) async {
    _enter('ackBuckets');
    final set = startMsList.toSet();
    final before = pendingBuckets.length;
    pendingBuckets.removeWhere((b) => set.contains(b.startMs));
    ackedStartMs.addAll(startMsList);
    return before - pendingBuckets.length;
  }

  @override
  Future<LiveStatus> getLiveStatus() async {
    _enter('getLiveStatus');
    return liveStatus;
  }

  @override
  Future<BindResult> bindUser(String uid) async {
    _enter('bindUser');
    bindCalls.add(uid);
    final gate = bindGate;
    if (gate != null) await gate.future;
    return bindResult;
  }

  @override
  Future<String> getDeviceId() async {
    _enter('getDeviceId');
    return deviceId;
  }

  @override
  Stream<LiveSnapshot> get liveEvents => _events.stream;

  void dispose() => _events.close();
}
