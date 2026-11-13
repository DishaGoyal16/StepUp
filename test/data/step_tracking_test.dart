import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/core/utils/clock.dart';
import 'package:stepup/data/functions/callables.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/steps/fake_permission_client.dart';
import 'package:stepup/data/steps/fake_step_engine_channel.dart';
import 'package:stepup/data/steps/method_step_engine_channel.dart';
import 'package:stepup/data/steps/step_permissions.dart';
import 'package:stepup/data/steps/step_engine_binding.dart';
import 'package:stepup/data/steps/step_sync_service.dart';
import 'package:stepup/data/steps/step_tracking_controller.dart';
import 'package:stepup/domain/step_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StepPermissions', () {
    test('rationale, then ACTIVITY_RECOGNITION, then POST_NOTIFICATIONS', () async {
      final client = FakePermissionClient();
      var rationaleCalls = 0;
      final r = await StepPermissions(client).request(rationale: () async {
        rationaleCalls++;
        return true;
      });
      expect(rationaleCalls, 1);
      expect(client.prompts, [PermissionKind.activityRecognition, PermissionKind.notifications]);
      expect(r.canTrack, isTrue);
      expect(r.notifications, StepPermissionState.granted);
    });

    test('declining the rationale does not prompt', () async {
      final client = FakePermissionClient();
      final r = await StepPermissions(client).request(rationale: () async => false);
      expect(client.prompts, isEmpty);
      expect(r.canTrack, isFalse);
    });

    test('activity denied: notifications are not requested', () async {
      final client = FakePermissionClient()
        ..promptResult[PermissionKind.activityRecognition] = StepPermissionState.denied;
      final r = await StepPermissions(client).request();
      expect(client.prompts, [PermissionKind.activityRecognition]);
      expect(r.canTrack, isFalse);
    });

    test('permanently denied is not re-requested (open settings instead)', () async {
      final client = FakePermissionClient(activity: StepPermissionState.permanentlyDenied);
      final perms = StepPermissions(client);
      final r = await perms.request(rationale: () async => true);
      expect(client.prompts, isEmpty);
      expect(r.activityPermanentlyDenied, isTrue);
      expect(await perms.openSettings(), isTrue);
      expect(client.openSettingsCalls, 1);
    });

    test('already granted: no rationale, no prompts', () async {
      final client = FakePermissionClient(
        activity: StepPermissionState.granted,
        notifications: StepPermissionState.granted,
      );
      var rationale = 0;
      final r = await StepPermissions(client).request(rationale: () async {
        rationale++;
        return true;
      });
      expect(rationale, 0);
      expect(client.prompts, isEmpty);
      expect(r.canTrack, isTrue);
    });

    test('notifications denied still allows tracking', () async {
      final client = FakePermissionClient()
        ..promptResult[PermissionKind.notifications] = StepPermissionState.denied;
      final r = await StepPermissions(client).request();
      expect(r.canTrack, isTrue);
      expect(r.notifications, StepPermissionState.denied);
    });
  });

  group('StepTrackingController', () {
    late FakeStepEngineChannel engine;
    late FakePermissionClient client;
    late FakeClock clock;
    late StepSyncService sync;
    late StepEngineBinding binding;
    late StepTrackingController c;

    setUp(() async {
      engine = FakeStepEngineChannel(
        todaySummary: const TodaySummary(raw: 100, verified: 80, pending: 5, rejected: 15, suspicious: 3),
      );
      client = FakePermissionClient();
      clock = FakeClock(DateTime.utc(2026, 11, 13, 6));
      final fn = FakeFunctionsClient()
        ..on('registerDevice', (_) => {'isRewardDevice': true})
        ..on('syncStepBuckets', (_) => {'accepted': 0, 'duplicates': 0, 'rejected': <Object>[]});
      binding = StepEngineBinding(engine);
      await binding.bind('user-1');
      sync = StepSyncService(engine: engine, binding: binding, callables: Callables(fn), clock: clock);
      c = StepTrackingController(
        engine: engine,
        binding: binding,
        permissions: StepPermissions(client),
        clock: clock,
        sync: sync,
      );
    });

    tearDown(() {
      c.dispose();
      sync.dispose();
    });

    test('refresh loads capabilities, tracking state and today\'s ledger', () async {
      await c.refresh();
      expect(c.capabilities?.model, 'Fake Phone');
      expect(c.tracking, isFalse);
      expect(c.today?.verified, 80);
      expect(c.engineAvailable, isTrue);
      expect(c.engineError, isNull);
    });

    test('a refresh that finishes after sign-out must not resurrect the previous user\'s numbers', () async {
      // Found by the on-device E2E run: `today` was still set right after sign-out.
      await c.refresh();
      expect(c.today?.verified, 80);
      final gate = Completer<void>();
      engine.todayGate = gate; // next getTodaySummary stays in flight
      final inFlight = c.refresh();
      await Future<void>.delayed(Duration.zero);
      binding.unbind(); // user signs out while the engine call is pending
      expect(c.today, isNull);
      gate.complete();
      await inFlight;
      expect(c.today, isNull, reason: 'late result belongs to the previous user and must be dropped');
      expect(c.capabilities?.model, 'Fake Phone');
    });

    test('live events of the previous user stop at unbind', () async {
      c.attach();
      binding.unbind();
      engine.emit(const LiveSnapshot(tracking: true, raw: 9, verified: 9));
      await Future<void>.delayed(Duration.zero);
      expect(c.today, isNull);
    });

    test('engine failure is surfaced as unavailable, never thrown', () async {
      engine.failNext(
        'getCapabilities',
        const AppException(code: 'engine-unavailable', message: 'not available'),
      );
      await c.refresh();
      expect(c.engineAvailable, isFalse);
      expect(c.engineError?.code, 'engine-unavailable');
    });

    test('device without a step counter is reported as unavailable', () async {
      engine.capabilities = const EngineCapabilities(stepCounter: false);
      await c.refresh();
      expect(c.engineAvailable, isFalse);
    });

    test('enable: asks permissions, starts the engine and triggers a sync', () async {
      final result = await c.setTracking(true, rationale: () async => true);
      expect(result, TrackingChange.started);
      expect(engine.tracking, isTrue);
      expect(c.tracking, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls.contains('getDeviceId'), isTrue, reason: 'sync kicked off');
    });

    test('enable: declining the rationale never starts the engine', () async {
      final result = await c.setTracking(true, rationale: () async => false);
      expect(result, TrackingChange.permissionDenied);
      expect(engine.calls.contains('startTracking'), isFalse);
    });

    test('enable: permanently denied -> caller should offer settings', () async {
      final blocked = FakePermissionClient(activity: StepPermissionState.permanentlyDenied);
      final ctrl = StepTrackingController(
        engine: engine,
        binding: binding,
        permissions: StepPermissions(blocked),
        clock: clock,
      );
      final result = await ctrl.setTracking(true);
      expect(result, TrackingChange.permissionPermanentlyDenied);
      expect(await ctrl.openSettings(), isTrue);
      expect(blocked.openSettingsCalls, 1);
      ctrl.dispose();
    });

    test('enable: engine says NO_STEP_COUNTER', () async {
      engine.startResult = const StartTrackingResult(started: false, reason: 'NO_STEP_COUNTER');
      expect(await c.setTracking(true), TrackingChange.unsupported);
    });

    test('enable: engine says PERMISSION_DENIED', () async {
      engine.startResult = const StartTrackingResult(started: false, reason: 'PERMISSION_DENIED');
      expect(await c.setTracking(true), TrackingChange.permissionDenied);
    });

    test('enable: engine says START_FAILED', () async {
      engine.startResult = const StartTrackingResult(started: false, reason: 'START_FAILED');
      expect(await c.setTracking(true), TrackingChange.startFailed);
    });

    test('disable stops the engine', () async {
      await c.setTracking(true);
      expect(await c.setTracking(false), TrackingChange.stopped);
      expect(engine.tracking, isFalse);
      expect(c.tracking, isFalse);
    });

    test('engine error while starting is reported as failed', () async {
      engine.failNext('startTracking', const AppException(code: 'engine-error', message: 'boom'));
      expect(await c.setTracking(true), TrackingChange.failed);
      expect(c.engineError?.message, 'boom');
    });

    test('live snapshots override today\'s numbers while attached', () async {
      await c.refresh();
      c.attach();
      engine.emit(const LiveSnapshot(tracking: true, raw: 200, verified: 150, pending: 10, rejected: 40, suspicious: 6, liveLabel: 'Walking'));
      await Future<void>.delayed(Duration.zero);
      expect(c.today?.verified, 150);
      expect(c.today?.suspicious, 6);
      expect(c.tracking, isTrue);
      expect(c.liveLabel, 'Walking');
      c.detach();
      engine.emit(const LiveSnapshot(tracking: true, raw: 999, verified: 999));
      await Future<void>.delayed(Duration.zero);
      expect(c.today?.verified, 150, reason: 'detached: no more updates');
    });
  });

  group('MethodStepEngineChannel follows the channel contract', () {
    const method = MethodChannel(MethodStepEngineChannel.methodChannelName);
    late List<MethodCall> calls;

    void mock(Future<Object?> Function(MethodCall) handler) {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(method, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(method, null);
    });

    test('bindUser sends {uid} and parses the result', () async {
      mock((_) async => {'bound': true, 'changed': true, 'sinceMs': 1763000000000});
      final r = await MethodStepEngineChannel().bindUser('uid-1');
      expect(calls.single.method, 'bindUser');
      expect(calls.single.arguments, {'uid': 'uid-1'});
      expect(r.bound, isTrue);
      expect(r.changed, isTrue);
      expect(r.sinceMs, 1763000000000);
    });

    test('bindUser tolerates an older native build (MissingPluginException)', () async {
      mock((_) async => throw MissingPluginException());
      final r = await MethodStepEngineChannel().bindUser('uid-1');
      expect(r.changed, isFalse);
      expect(r.bound, isFalse);
    });

    test('bindUser tolerates PlatformException as changed:false', () async {
      mock((_) async => throw PlatformException(code: 'E'));
      final r = await MethodStepEngineChannel().bindUser('uid-1');
      expect(r.changed, isFalse);
    });

    test('channel names', () {
      expect(MethodStepEngineChannel.methodChannelName, 'edu.thapar.stepup/engine');
      expect(MethodStepEngineChannel.eventChannelName, 'edu.thapar.stepup/engine_events');
    });

    test('getCapabilities', () async {
      mock((_) async => {
            'stepCounter': true,
            'accelerometer': true,
            'gyroscope': false,
            'activityRecognitionGranted': true,
            'notificationsGranted': false,
            'evidenceMode': 'IMU',
            'sdkInt': 34,
            'model': 'RMX3990',
          });
      final c = await MethodStepEngineChannel().getCapabilities();
      expect(calls.single.method, 'getCapabilities');
      expect(c.stepCounter, isTrue);
      expect(c.gyroscope, isFalse);
      expect(c.sdkInt, 34);
      expect(c.model, 'RMX3990');
    });

    test('startTracking / stopTracking / isTracking', () async {
      mock((call) async => switch (call.method) {
            'startTracking' => {'started': false, 'reason': 'PERMISSION_DENIED'},
            'isTracking' => true,
            _ => <String, Object?>{},
          });
      final ch = MethodStepEngineChannel();
      final r = await ch.startTracking();
      expect(r.started, isFalse);
      expect(r.reason, 'PERMISSION_DENIED');
      await ch.stopTracking();
      expect(await ch.isTracking(), isTrue);
      expect(calls.map((c) => c.method), ['startTracking', 'stopTracking', 'isTracking']);
    });

    test('getTodaySummary sends dayStartMs/dayEndMs and parses the ledger', () async {
      mock((_) async => {
            'raw': 10, 'verified': 8, 'pending': 1, 'rejected': 1,
            'suspicious': 1, 'unwitnessed': 0, 'gap': 0,
          });
      final t = await MethodStepEngineChannel().getTodaySummary(dayStartMs: 1000, dayEndMs: 2000);
      expect(calls.single.arguments, {'dayStartMs': 1000, 'dayEndMs': 2000});
      expect(t.verified, 8);
      expect(t.suspicious, 1);
    });

    test('getBucketsForSync sends limit and parses int64 bucket times', () async {
      mock((_) async => [
            {
              'startMs': 1763000000000,
              'bootCount': 1,
              'rawDelta': 20,
              'credited': 18,
              'state': 'VERIFIED',
              'reason': null,
              'walkFraction': 0.9,
              'evidenceMode': 'IMU',
              'carryMode': 'POCKET',
              'hops': [
                {'label': 'WALK', 'imuSteps': 16},
              ],
              'lateRawAdded': 0,
              'lateCreditedAdded': 0,
            },
          ]);
      final b = await MethodStepEngineChannel().getBucketsForSync(limit: 200);
      expect(calls.single.arguments, {'limit': 200});
      expect(b.single.startMs, 1763000000000);
      expect(b.single.hops.single.imuSteps, 16);
    });

    test('ackBuckets sends startMsList; an empty list does not call native', () async {
      mock((_) async => {'acked': 2});
      final ch = MethodStepEngineChannel();
      expect(await ch.ackBuckets([1, 2]), 2);
      expect(calls.single.method, 'ackBuckets');
      expect(calls.single.arguments, {'startMsList': [1, 2]});
      calls.clear();
      expect(await ch.ackBuckets([]), 0);
      expect(calls, isEmpty);
    });

    test('getLiveStatus and getDeviceId', () async {
      mock((call) async => call.method == 'getDeviceId'
          ? 'uuid-1234'
          : {'tracking': true, 'liveLabel': 'Walking', 'carryMode': 'HAND', 'lastRejection': null});
      final ch = MethodStepEngineChannel();
      expect(await ch.getDeviceId(), 'uuid-1234');
      final s = await ch.getLiveStatus();
      expect(s.tracking, isTrue);
      expect(s.carryMode, 'HAND');
    });

    test('missing native implementation becomes engine-unavailable', () async {
      // no handler registered at all
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(method, null);
      await expectLater(
        MethodStepEngineChannel().getCapabilities(),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'engine-unavailable')),
      );
    });

    test('platform errors become engine-error with the platform code as reason', () async {
      mock((_) async => throw PlatformException(code: 'E_SERVICE', message: 'service crashed'));
      await expectLater(
        MethodStepEngineChannel().startTracking(),
        throwsA(isA<AppException>()
            .having((e) => e.code, 'code', 'engine-error')
            .having((e) => e.reason, 'reason', 'E_SERVICE')
            .having((e) => e.message, 'message', 'service crashed')),
      );
    });

    test('event channel maps events to LiveSnapshot', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel(MethodStepEngineChannel.eventChannelName),
        MockStreamHandler.inline(onListen: (args, sink) {
          sink.success({
            'tracking': true, 'raw': 5, 'verified': 4, 'pending': 1,
            'rejected': 0, 'suspicious': 0, 'liveLabel': 'Walking',
          });
          sink.endOfStream();
        }),
      );
      final first = await MethodStepEngineChannel().liveEvents.first;
      expect(first.verified, 4);
      expect(first.liveLabel, 'Walking');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel(MethodStepEngineChannel.eventChannelName),
        null,
      );
    });
  });
}
