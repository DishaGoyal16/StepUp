import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/utils/clock.dart';
import 'package:stepup/data/functions/callables.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/steps/fake_permission_client.dart';
import 'package:stepup/data/steps/fake_step_engine_channel.dart';
import 'package:stepup/data/steps/step_engine_binding.dart';
import 'package:stepup/data/steps/step_permissions.dart';
import 'package:stepup/data/steps/step_sync_service.dart';
import 'package:stepup/data/steps/step_tracking_controller.dart';
import 'package:stepup/domain/step_models.dart';

EngineBucket bucket(int i) => EngineBucket(
      startMs: 1700000000000 + i * 10000,
      bootCount: 1,
      rawDelta: 10,
      credited: 9,
      state: 'VERIFIED',
    );

void main() {
  late FakeStepEngineChannel engine;
  late FakeFunctionsClient fn;
  late StepEngineBinding binding;
  late StepSyncService sync;
  late StepTrackingController tracking;

  setUp(() {
    engine = FakeStepEngineChannel(todaySummary: const TodaySummary(raw: 10, verified: 9));
    fn = FakeFunctionsClient()
      ..on('registerDevice', (_) => {'isRewardDevice': true})
      ..on('syncStepBuckets', (p) => {
            'accepted': [for (final b in (p['buckets'] as List)) (b as Map)['startMs'] as int],
            'duplicates': <int>[],
            'rejected': <Object>[],
          });
    final clock = FakeClock();
    binding = StepEngineBinding(engine);
    sync = StepSyncService(engine: engine, binding: binding, callables: Callables(fn), clock: clock);
    tracking = StepTrackingController(
      engine: engine,
      binding: binding,
      permissions: StepPermissions(FakePermissionClient()),
      clock: clock,
      sync: sync,
    );
  });

  tearDown(() {
    tracking.dispose();
    sync.dispose();
    binding.dispose();
  });

  test('sync never runs before bindUser (no user bound -> skipped, engine untouched)', () async {
    engine.addBuckets([bucket(1)]);
    final r = await sync.syncNow(force: true);
    expect(r.skipped, isTrue);
    expect(engine.calls, isEmpty, reason: 'no getDeviceId/getBucketsForSync before binding');
    expect(fn.calls, isEmpty);
  });

  test('a sync requested while the native bind is still running waits for it', () async {
    engine.addBuckets([bucket(1)]);
    engine.bindGate = Completer<void>();
    final activating = sync.activateUser('A');
    await Future<void>.delayed(Duration.zero);
    final pending = sync.syncNow(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(engine.calls, ['bindUser'], reason: 'nothing else touched the engine yet');
    engine.bindGate!.complete();
    await activating;
    final r = await pending;
    expect(r.ok, isTrue);
    expect(engine.calls.first, 'bindUser');
    expect(engine.calls.indexOf('bindUser'), lessThan(engine.calls.indexOf('getBucketsForSync')));
    expect(engine.bindCalls, ['A']);
  });

  test('switching user A -> B binds B before any sync under B; nothing runs unbound in between',
      () async {
    await sync.activateUser('A');
    engine.addBuckets([bucket(1)]);
    expect((await sync.syncNow(force: true)).ok, isTrue);
    engine.calls.clear();

    engine.bindGate = Completer<void>();
    final switching = sync.activateUser('B');
    await Future<void>.delayed(Duration.zero);
    expect(binding.isReady, isFalse);
    expect(tracking.today, isNull);

    // A sync requested during the switch waits for B's binding.
    engine.addBuckets([bucket(2)]);
    final during = sync.syncNow(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(engine.calls, ['bindUser'], reason: 'nothing touches the engine while unbound');
    engine.bindGate!.complete();
    await switching;
    engine.bindGate = null;
    expect(binding.uid, 'B');
    expect(binding.isReady, isTrue);

    final r = await during;
    expect(r.ok, isTrue);
    expect(engine.bindCalls, ['A', 'B']);
    expect(engine.calls.indexOf('bindUser'), lessThan(engine.calls.indexOf('getBucketsForSync')));
    // the device is registered again for the new user
    expect(fn.callsTo('registerDevice').length, 2);
  });

  test('a run in flight for user A finishes before B is bound', () async {
    await sync.activateUser('A');
    engine.addBuckets([bucket(1)]);
    final run = sync.syncNow(force: true);
    final switching = sync.activateUser('B');
    await run;
    await switching;
    final order = engine.calls;
    expect(order.lastIndexOf('ackBuckets'), lessThan(order.lastIndexOf('bindUser')),
        reason: 'buckets of A were acked before the ledger moved to B');
  });

  test('bindUser result is stored (changed / sinceMs)', () async {
    engine.bindResult = const BindResult(bound: true, changed: true, sinceMs: 123);
    await sync.activateUser('A');
    expect(binding.lastResult?.sinceMs, 123);
    expect(binding.lastResult?.changed, isTrue);
  });

  test('older native build (unsupported bind result) still lets sync run', () async {
    engine.bindResult = BindResult.unsupported;
    await sync.activateUser('A');
    engine.addBuckets([bucket(1)]);
    expect(binding.isReady, isTrue);
    expect((await sync.syncNow(force: true)).ok, isTrue);
  });

  test('a failing bind keeps everything blocked and is retried on the next request', () async {
    engine.failNext('bindUser');
    await sync.activateUser('A');
    expect(binding.isReady, isFalse);
    engine.addBuckets([bucket(1)]);
    final r = await sync.syncNow(force: true); // whenReady() retries the bind
    expect(r.ok, isTrue);
    expect(engine.calls.where((c) => c == 'bindUser').length, 2, reason: 'failed once, retried');
  });

  test('summary and tracking wait for the binding; sign-out unbinds', () async {
    await tracking.refresh();
    expect(engine.calls, isEmpty, reason: 'no summary without a bound user');
    expect(tracking.today, isNull);

    await sync.activateUser('A');
    await Future<void>.delayed(Duration.zero);
    await tracking.refresh();
    expect(tracking.today?.verified, 9);
    expect(engine.calls.indexOf('bindUser'), lessThan(engine.calls.indexOf('getTodaySummary')));

    expect(await tracking.setTracking(true), TrackingChange.started);
    expect(engine.calls.indexOf('bindUser'), lessThan(engine.calls.indexOf('startTracking')));

    sync.deactivateUser();
    await Future<void>.delayed(Duration.zero);
    expect(binding.isReady, isFalse);
    expect(tracking.today, isNull, reason: 'numbers of the previous user are cleared');
    engine.calls.clear();
    expect((await sync.syncNow(force: true)).skipped, isTrue);
    expect(await tracking.setTracking(true), TrackingChange.failed, reason: 'cannot start while unbound');
    expect(engine.calls, isNot(contains('startTracking')));
  });
}
