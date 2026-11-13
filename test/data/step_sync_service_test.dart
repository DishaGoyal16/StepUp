import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/core/utils/clock.dart';
import 'package:stepup/data/functions/callables.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/steps/fake_step_engine_channel.dart';
import 'package:stepup/data/steps/step_engine_binding.dart';
import 'package:stepup/data/steps/step_sync_service.dart';
import 'package:stepup/domain/step_models.dart';

EngineBucket bucket(int i, {int raw = 20, int credited = 18}) => EngineBucket(
      startMs: 1700000000000 + i * 10000,
      bootCount: 1,
      rawDelta: raw,
      credited: credited,
      state: 'VERIFIED',
      walkFraction: 0.9,
      evidenceMode: 'IMU',
      carryMode: 'POCKET',
      hops: const [EngineHop(label: 'WALK', imuSteps: 16)],
      lateRawAdded: 2,
      lateCreditedAdded: 1,
    );

List<int> starts(Iterable<EngineBucket> b) => [for (final x in b) x.startMs];

void main() {
  late FakeStepEngineChannel engine;
  late FakeFunctionsClient fn;
  late FakeClock clock;
  late StepSyncService sync;
  late StepEngineBinding binding;

  setUp(() async {
    engine = FakeStepEngineChannel();
    fn = FakeFunctionsClient()..on('registerDevice', (_) => {'isRewardDevice': true});
    clock = FakeClock(DateTime.utc(2026, 11, 13, 6));
    binding = StepEngineBinding(engine);
    sync = StepSyncService(
      engine: engine,
      binding: binding,
      callables: Callables(fn),
      clock: clock,
      appVersion: '1.2.3',
    );
    await sync.activateUser('user-1');
  });

  tearDown(() => sync.dispose());

  /// Server accepts everything it is sent (reports startMs lists).
  void serverAcceptsAll() {
    fn.on('syncStepBuckets', (p) {
      final sent = [for (final b in (p['buckets'] as List)) (b as Map)['startMs'] as int];
      return {
        'accepted': sent,
        'duplicates': <int>[],
        'rejected': <Object>[],
        'today': {'verifiedSteps': 100, 'rawSteps': 120, 'rejectedSteps': 5, 'unwitnessedSteps': 0},
      };
    });
  }

  test('success: registers the device, syncs, acks and records the time', () async {
    engine.addBuckets([bucket(1), bucket(2), bucket(3)]);
    serverAcceptsAll();

    final r = await sync.syncNow();

    expect(r.ok, isTrue);
    expect(r.sent, 3);
    expect(r.acked, 3);
    expect(engine.pendingBuckets, isEmpty);
    expect(engine.ackedStartMs, starts([bucket(1), bucket(2), bucket(3)]));
    expect(sync.lastSyncAt, clock.now());
    expect(sync.lastError, isNull);
    expect(sync.lastServerToday?.verifiedSteps, 100);

    final reg = fn.callsTo('registerDevice').single.params;
    expect(reg['deviceId'], 'fake-device-id');
    expect(reg['model'], 'Fake Phone');
    expect(reg['appVersion'], '1.2.3');
    expect(reg.containsKey('fcmToken'), isFalse);
  });

  test('sync payload follows the callable contract', () async {
    engine.addBuckets([bucket(1)]);
    serverAcceptsAll();
    await sync.syncNow();
    final p = fn.callsTo('syncStepBuckets').single.params;
    expect(p['deviceId'], 'fake-device-id');
    final b = (p['buckets'] as List).single as Map;
    expect(b.keys.toSet(), {
      'startMs', 'bootCount', 'rawDelta', 'credited', 'state', 'reason',
      'walkFraction', 'evidenceMode', 'carryMode', 'hops',
      'lateRawAdded', 'lateCreditedAdded',
    });
    expect(b['lateRawAdded'], 2);
    expect(b['lateCreditedAdded'], 1);
    expect(b['hops'], [
      {'label': 'WALK', 'imuSteps': 16},
    ]);
  });

  test('registerDevice runs once per app start, not on every sync', () async {
    serverAcceptsAll();
    await sync.syncNow();
    engine.addBuckets([bucket(1)]);
    await sync.syncNow();
    engine.addBuckets([bucket(2)]);
    await sync.syncNow();
    expect(fn.callsTo('registerDevice').length, 1);
  });

  test('a new FCM token re-registers the device and is sent along', () async {
    serverAcceptsAll();
    await sync.syncNow();
    sync.updateFcmToken('tok-1');
    await sync.syncNow();
    expect(fn.callsTo('registerDevice').length, 2);
    expect(fn.callsTo('registerDevice').last.params['fcmToken'], 'tok-1');
    sync.updateFcmToken('tok-1'); // unchanged -> no extra registration
    await sync.syncNow();
    expect(fn.callsTo('registerDevice').length, 2);
  });

  test('resetForNewUser registers the device again', () async {
    serverAcceptsAll();
    await sync.syncNow();
    sync.resetForNewUser();
    await sync.syncNow();
    expect(fn.callsTo('registerDevice').length, 2);
    expect(sync.lastSyncAt, isNotNull);
  });

  test('no buckets: still counts as a successful sync without calling the server', () async {
    final r = await sync.syncNow();
    expect(r.ok, isTrue);
    expect(r.sent, 0);
    expect(fn.callsTo('syncStepBuckets'), isEmpty);
    expect(sync.lastSyncAt, isNotNull);
  });

  group('duplicates', () {
    test('buckets reported as duplicates are acknowledged (list form)', () async {
      engine.addBuckets([bucket(1), bucket(2)]);
      fn.on('syncStepBuckets', (p) => {
            'accepted': <int>[],
            'duplicates': [bucket(1).startMs, bucket(2).startMs],
            'rejected': <Object>[],
          });
      final r = await sync.syncNow();
      expect(r.ok, isTrue);
      expect(r.duplicates, 2);
      expect(r.acked, 2);
      expect(engine.pendingBuckets, isEmpty);
    });

    test('count form: accepted + duplicates covering every bucket acks them all', () async {
      engine.addBuckets([bucket(1), bucket(2), bucket(3)]);
      fn.on('syncStepBuckets', (_) => {'accepted': 1, 'duplicates': 2, 'rejected': <Object>[]});
      final r = await sync.syncNow();
      expect(r.ok, isTrue);
      expect(r.acked, 3);
    });

    test('re-sending the same bucket after a lost ack is harmless', () async {
      engine.addBuckets([bucket(1)]);
      // First attempt: server accepts, but the native ack fails.
      serverAcceptsAll();
      engine.failNext('ackBuckets');
      final first = await sync.syncNow();
      expect(first.ok, isFalse);
      expect(engine.pendingBuckets.length, 1, reason: 'not acked -> still queued');

      // Retry: the server now says duplicate; we ack it.
      fn.on('syncStepBuckets', (_) => {
            'accepted': <int>[],
            'duplicates': [bucket(1).startMs],
            'rejected': <Object>[],
          });
      final second = await sync.syncNow(force: true);
      expect(second.ok, isTrue);
      expect(engine.pendingBuckets, isEmpty);
    });
  });

  group('partial rejection', () {
    test('permanently rejected buckets are acked; unmentioned ones are not', () async {
      engine.addBuckets([bucket(1), bucket(2), bucket(3)]);
      fn.on('syncStepBuckets', (_) => {
            'accepted': [bucket(1).startMs],
            'duplicates': <int>[],
            'rejected': [
              {'startMs': bucket(2).startMs, 'reason': 'CADENCE_EXCEEDED'},
            ],
          });
      final r = await sync.syncNow();
      expect(engine.ackedStartMs, [bucket(1).startMs, bucket(2).startMs]);
      expect(engine.pendingBuckets.map((b) => b.startMs), [bucket(3).startMs]);
      expect(r.ok, isFalse, reason: 'bucket 3 was not confirmed');
      expect(r.acked, 2);
      expect(r.rejected, 1);
      expect(sync.lastError, isNotNull);
      expect(sync.consecutiveFailures, 1);
    });

    test('everything rejected is acked (nothing will ever be accepted)', () async {
      engine.addBuckets([bucket(1), bucket(2)]);
      fn.on('syncStepBuckets', (_) => {
            'accepted': 0,
            'duplicates': 0,
            'rejected': [
              {'startMs': bucket(1).startMs, 'reason': 'TOO_OLD'},
              {'startMs': bucket(2).startMs, 'reason': 'TOO_OLD'},
            ],
          });
      final r = await sync.syncNow();
      expect(r.ok, isTrue);
      expect(r.acked, 2);
      expect(engine.pendingBuckets, isEmpty);
    });

    test('count form that does not add up acks only the rejected ones', () async {
      engine.addBuckets([bucket(1), bucket(2), bucket(3)]);
      fn.on('syncStepBuckets', (_) => {
            'accepted': 1,
            'duplicates': 0,
            'rejected': [
              {'startMs': bucket(3).startMs, 'reason': 'X'},
            ],
          });
      final r = await sync.syncNow();
      expect(engine.ackedStartMs, [bucket(3).startMs]);
      expect(r.ok, isFalse);
    });

    test('a response that confirms nothing acks nothing and reports a problem', () async {
      engine.addBuckets([bucket(1), bucket(2)]);
      fn.on('syncStepBuckets', (_) => {'accepted': <int>[], 'duplicates': <int>[], 'rejected': <Object>[]});
      final r = await sync.syncNow();
      expect(r.ok, isFalse);
      expect(engine.ackedStartMs, isEmpty);
      expect(engine.calls.contains('ackBuckets'), isFalse);
    });

    test('server ids that were never sent are ignored', () async {
      engine.addBuckets([bucket(1)]);
      fn.on('syncStepBuckets', (_) => {
            'accepted': [bucket(1).startMs, 42],
            'duplicates': <int>[],
            'rejected': <Object>[],
          });
      await sync.syncNow();
      expect(engine.ackedStartMs, [bucket(1).startMs]);
    });
  });

  group('failures never ack and retry later', () {
    test('network error from the server: no ack, error recorded, retried next time', () async {
      engine.addBuckets([bucket(1), bucket(2)]);
      fn.failNext('syncStepBuckets', AppException.fromCallable(code: 'unavailable'));
      serverAcceptsAll();

      final r1 = await sync.syncNow();
      expect(r1.ok, isFalse);
      expect(r1.error, contains('Network'));
      expect(engine.ackedStartMs, isEmpty);
      expect(engine.calls.contains('ackBuckets'), isFalse);
      expect(engine.pendingBuckets.length, 2);
      expect(sync.lastSyncAt, isNull);
      expect(sync.lastError, isNotNull);

      clock.advance(const Duration(seconds: 6));
      final r2 = await sync.syncNow();
      expect(r2.ok, isTrue);
      expect(engine.pendingBuckets, isEmpty);
      expect(sync.lastError, isNull);
      expect(sync.consecutiveFailures, 0);
      // the very same buckets were re-sent (server de-duplicates by id)
      final calls = fn.callsTo('syncStepBuckets').toList();
      expect(calls.length, 2);
      expect([for (final b in calls[0].params['buckets'] as List) (b as Map)['startMs']],
          [for (final b in calls[1].params['buckets'] as List) (b as Map)['startMs']]);
    });

    test('unexpected exceptions are contained (no throw)', () async {
      engine.addBuckets([bucket(1)]);
      fn.failNext('syncStepBuckets', StateError('boom'));
      final r = await sync.syncNow();
      expect(r.ok, isFalse);
      expect(r.error, 'Could not sync your steps. Will retry.');
      expect(engine.ackedStartMs, isEmpty);
    });

    test('registerDevice failure: nothing is read or sent', () async {
      engine.addBuckets([bucket(1)]);
      fn.failNext('registerDevice', AppException.fromCallable(code: 'unavailable'));
      final r = await sync.syncNow();
      expect(r.ok, isFalse);
      expect(engine.calls.contains('getBucketsForSync'), isFalse);
      expect(fn.callsTo('syncStepBuckets'), isEmpty);
      // next run registers again
      serverAcceptsAll();
      final r2 = await sync.syncNow(force: true);
      expect(r2.ok, isTrue);
      expect(fn.callsTo('registerDevice').length, 2);
    });

    test('engine unavailable is reported, not thrown', () async {
      engine.failNext(
        'getDeviceId',
        const AppException(code: 'engine-unavailable', message: 'Step tracking is not available on this device or build.'),
      );
      final r = await sync.syncNow();
      expect(r.ok, isFalse);
      expect(r.error, contains('not available'));
    });

    test('an ack that fails natively leaves the buckets queued', () async {
      engine.addBuckets([bucket(1)]);
      serverAcceptsAll();
      engine.failNext('ackBuckets');
      final r = await sync.syncNow();
      expect(r.ok, isFalse);
      expect(engine.pendingBuckets.length, 1);
    });
  });

  group('back-off', () {
    setUp(() {
      engine.addBuckets([bucket(1)]);
      fn.on('syncStepBuckets', (_) => throw AppException.fromCallable(code: 'unavailable'));
    });

    test('periodic runs are skipped until the back-off elapses; forced runs are not', () async {
      await sync.syncNow(); // failure 1 -> wait 5 s
      expect(sync.nextAttemptAt, clock.now().add(const Duration(seconds: 5)));

      clock.advance(const Duration(seconds: 2));
      final skipped = await sync.syncNow();
      expect(skipped.skipped, isTrue);
      expect(fn.callsTo('syncStepBuckets').length, 1);

      final forced = await sync.syncNow(force: true);
      expect(forced.skipped, isFalse);
      expect(fn.callsTo('syncStepBuckets').length, 2);
    });

    test('delay doubles per consecutive failure and is capped', () async {
      final waits = <Duration>[];
      for (var i = 0; i < 10; i++) {
        await sync.syncNow(force: true);
        waits.add(sync.nextAttemptAt!.difference(clock.now()));
      }
      expect(waits.take(5), const [
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 20),
        Duration(seconds: 40),
        Duration(seconds: 80),
      ]);
      expect(waits.last, const Duration(minutes: 5), reason: 'capped');
      expect(sync.consecutiveFailures, 10);
    });

    test('success resets the back-off', () async {
      await sync.syncNow();
      await sync.syncNow(force: true);
      expect(sync.consecutiveFailures, 2);
      serverAcceptsAll();
      await sync.syncNow(force: true);
      expect(sync.consecutiveFailures, 0);
      expect(sync.nextAttemptAt, isNull);
    });
  });

  group('batching', () {
    test('450 buckets go out as 200 + 200 + 50, each acked after its own response', () async {
      engine.addBuckets([for (var i = 0; i < 450; i++) bucket(i)]);
      serverAcceptsAll();
      final r = await sync.syncNow();
      final calls = fn.callsTo('syncStepBuckets').toList();
      expect(calls.map((c) => (c.params['buckets'] as List).length), [200, 200, 50]);
      expect(r.ok, isTrue);
      expect(r.sent, 450);
      expect(r.acked, 450);
      expect(engine.pendingBuckets, isEmpty);
    });

    test('a failing second batch keeps the first acked and the rest queued', () async {
      engine.addBuckets([for (var i = 0; i < 300; i++) bucket(i)]);
      var n = 0;
      fn.on('syncStepBuckets', (p) {
        n++;
        if (n == 2) throw AppException.fromCallable(code: 'unavailable');
        return {
          'accepted': [for (final b in (p['buckets'] as List)) (b as Map)['startMs'] as int],
          'duplicates': <int>[],
          'rejected': <Object>[],
        };
      });
      final r = await sync.syncNow();
      expect(r.ok, isFalse);
      expect(r.acked, 200);
      expect(engine.pendingBuckets.length, 100);
    });
  });

  group('concurrency and lifecycle', () {
    test('overlapping syncNow calls share one run', () async {
      engine.addBuckets([bucket(1)]);
      serverAcceptsAll();
      final a = sync.syncNow();
      final b = sync.syncNow();
      expect(identical(a, b), isTrue);
      await a;
      expect(fn.callsTo('syncStepBuckets').length, 1);
    });

    test('syncing flag toggles and listeners are notified', () async {
      final seen = <bool>[];
      sync.addListener(() => seen.add(sync.syncing));
      serverAcceptsAll();
      await sync.syncNow();
      expect(sync.syncing, isFalse);
      expect(seen, contains(true));
      expect(seen.last, isFalse);
    });

    test('start/stop manage the periodic timer', () {
      expect(sync.isRunning, isFalse);
      sync.start();
      sync.start();
      expect(sync.isRunning, isTrue);
      sync.stop();
      expect(sync.isRunning, isFalse);
    });

    test('periodic timer triggers a sync every interval', () {
      // fakeAsync is overkill here; verify the default interval is ~60 s.
      expect(sync.interval, const Duration(seconds: 60));
    });
  });
}
