import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/step_models.dart';
import 'step_engine_channel.dart';

/// [StepEngineChannel] over the real platform channels.
///
/// `MethodChannel('edu.thapar.stepup/engine')` and
/// `EventChannel('edu.thapar.stepup/engine_events')`.
class MethodStepEngineChannel implements StepEngineChannel {
  MethodStepEngineChannel({MethodChannel? method, EventChannel? events})
      : _method = method ?? const MethodChannel(methodChannelName),
        _events = events ?? const EventChannel(eventChannelName);

  static const String methodChannelName = 'edu.thapar.stepup/engine';
  static const String eventChannelName = 'edu.thapar.stepup/engine_events';

  final MethodChannel _method;
  final EventChannel _events;

  static const AppException _unavailable = AppException(
    code: 'engine-unavailable',
    message: 'Step tracking is not available on this device or build.',
  );

  Future<T> _invoke<T>(String name, [Map<String, Object?>? args]) async {
    try {
      final r = await _method.invokeMethod<T>(name, args);
      if (r == null) {
        throw AppException(code: 'engine-error', message: 'The step engine returned no data ($name).');
      }
      return r;
    } on MissingPluginException {
      throw _unavailable;
    } on PlatformException catch (e) {
      throw AppException(
        code: 'engine-error',
        reason: e.code,
        message: e.message ?? 'The step engine reported an error.',
      );
    }
  }

  @override
  Future<EngineCapabilities> getCapabilities() async =>
      EngineCapabilities.fromMap(await _invoke<Map<Object?, Object?>>('getCapabilities'));

  @override
  Future<StartTrackingResult> startTracking() async =>
      StartTrackingResult.fromMap(await _invoke<Map<Object?, Object?>>('startTracking'));

  @override
  Future<void> stopTracking() async {
    try {
      await _method.invokeMethod<Object?>('stopTracking');
    } on MissingPluginException {
      throw _unavailable;
    } on PlatformException catch (e) {
      throw AppException(code: 'engine-error', reason: e.code, message: e.message ?? 'Could not stop tracking.');
    }
  }

  @override
  Future<bool> isTracking() async => (await _invoke<bool>('isTracking'));

  @override
  Future<TodaySummary> getTodaySummary({required int dayStartMs, required int dayEndMs}) async =>
      TodaySummary.fromMap(await _invoke<Map<Object?, Object?>>(
        'getTodaySummary',
        {'dayStartMs': dayStartMs, 'dayEndMs': dayEndMs},
      ));

  @override
  Future<List<EngineBucket>> getBucketsForSync({int limit = 200}) async {
    final raw = await _invoke<List<Object?>>('getBucketsForSync', {'limit': limit});
    return [
      for (final b in raw)
        if (b is Map) EngineBucket.fromMap(b),
    ];
  }

  @override
  Future<int> ackBuckets(List<int> startMsList) async {
    if (startMsList.isEmpty) return 0;
    final r = await _invoke<Map<Object?, Object?>>('ackBuckets', {'startMsList': startMsList});
    final acked = r['acked'];
    return acked is num ? acked.toInt() : 0;
  }

  @override
  Future<LiveStatus> getLiveStatus() async =>
      LiveStatus.fromMap(await _invoke<Map<Object?, Object?>>('getLiveStatus'));

  @override
  Future<BindResult> bindUser(String uid) async {
    try {
      final r = await _method.invokeMethod<Map<Object?, Object?>>('bindUser', {'uid': uid});
      return r == null ? BindResult.unsupported : BindResult.fromMap(r);
    } on MissingPluginException {
      return BindResult.unsupported;
    } on PlatformException {
      return BindResult.unsupported;
    }
  }

  @override
  Future<String> getDeviceId() => _invoke<String>('getDeviceId');

  @override
  Stream<LiveSnapshot> get liveEvents => _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => LiveSnapshot.fromMap(e as Map));
}
