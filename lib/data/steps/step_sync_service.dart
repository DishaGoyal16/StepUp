import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/clock.dart';
import '../../domain/step_models.dart';
import '../functions/callables.dart';
import 'step_engine_binding.dart';
import 'step_engine_channel.dart';

/// Result of one [StepSyncService.syncNow] run.
class SyncReport {
  const SyncReport({
    this.skipped = false,
    this.sent = 0,
    this.acked = 0,
    this.accepted = 0,
    this.duplicates = 0,
    this.rejected = 0,
    this.error,
  });

  const SyncReport.skipped() : this(skipped: true);

  final bool skipped;
  final int sent;
  final int acked;
  final int accepted;
  final int duplicates;
  final int rejected;

  /// Friendly message when the run failed (nothing was acknowledged for the
  /// failing batch, so it is retried).
  final String? error;

  bool get ok => !skipped && error == null;
}

/// Moves settled step buckets from the native engine to the backend.
///
/// Delivery guarantee: **at-least-once + deterministic server IDs**.
/// 1. `getDeviceId`, then `registerDevice` once per app start.
/// 2. Loop: `getBucketsForSync(200)` -> `syncStepBuckets` -> `ackBuckets`
///    ONLY for buckets the server reported as accepted, duplicate or
///    permanently rejected. On any network/server error nothing is
///    acknowledged, so the same buckets are retried (the server ignores
///    duplicates, so nothing is ever double counted).
/// 3. Failures back off exponentially (`baseBackoff` doubling up to
///    `maxBackoff`) for periodic runs; forced runs (app resume, tracking just
///    started) ignore the back-off but still grow it on failure.
///
/// Runs every [interval] (~60 s) while [start]ed (call [start] when the app is
/// in the foreground, [stop] when it is paused).
class StepSyncService extends ChangeNotifier {
  StepSyncService({
    required StepEngineChannel engine,
    required Callables callables,
    required Clock clock,
    required StepEngineBinding binding,
    this.interval = const Duration(seconds: 60),
    this.baseBackoff = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 5),
    this.batchLimit = 200,
    this.maxBatchesPerRun = 25,
    this.appVersion = '1.0.0',
  })  : _engine = engine,
        _callables = callables,
        _clock = clock,
        _binding = binding;

  final StepEngineChannel _engine;
  final Callables _callables;
  final Clock _clock;
  final StepEngineBinding _binding;

  final Duration interval;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final int batchLimit;
  final int maxBatchesPerRun;
  final String appVersion;

  Timer? _timer;
  Future<SyncReport>? _inFlight;
  String? _deviceId;
  bool _registered = false;
  String? _fcmToken;
  int _consecutiveFailures = 0;
  DateTime? _nextAttemptAt;

  DateTime? _lastSyncAt;
  String? _lastError;
  bool _syncing = false;
  bool _disposed = false;
  bool _isRewardDevice = true;
  ServerToday? _lastServerToday;
  int _totalAcked = 0;

  /// Last successful run (UTC), or null if none yet.
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Friendly message of the last failed run; cleared by the next success.
  String? get lastError => _lastError;

  bool get syncing => _syncing;
  bool get isRewardDevice => _isRewardDevice;
  ServerToday? get lastServerToday => _lastServerToday;
  int get totalAcked => _totalAcked;
  int get consecutiveFailures => _consecutiveFailures;
  DateTime? get nextAttemptAt => _nextAttemptAt;

  /// Begin periodic sync (idempotent). Call when the app is in the foreground.
  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(syncNow()));
  }

  /// Stop periodic sync (app in background).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isRunning => _timer != null;

  /// Provides/updates the FCM token; it is sent with the next
  /// `registerDevice` (which is repeated because the token changed).
  void updateFcmToken(String? token) {
    if (token == _fcmToken) return;
    _fcmToken = token;
    _registered = false;
  }

  /// The engine binding shared with the tracking controller.
  StepEngineBinding get binding => _binding;

  /// Makes [uid] the active user: no sync runs until the native ledger is
  /// bound to [uid]. Waits for a run that is still in flight for the previous
  /// user, resets per-user state, then binds. Syncs requested meanwhile are
  /// skipped (not queued under the wrong user).
  Future<void> activateUser(String uid) async {
    _binding.unbind();
    final running = _inFlight;
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    resetForNewUser();
    await _binding.bind(uid);
  }

  /// Signed out: stop syncing; nothing needs clearing natively.
  void deactivateUser() {
    _binding.unbind();
    stop();
  }

  /// Call when a different account signs in: the device must be registered
  /// again for the new user and old errors/back-off no longer apply.
  void resetForNewUser() {
    _registered = false;
    _lastError = null;
    _lastSyncAt = null;
    _lastServerToday = null;
    _consecutiveFailures = 0;
    _nextAttemptAt = null;
    _notify();
  }

  /// Runs one sync. Concurrent calls share the in-flight run. Periodic callers
  /// respect the back-off; pass [force] for resume / after tracking starts.
  Future<SyncReport> syncNow({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final next = _nextAttemptAt;
    if (!force && next != null && _clock.now().isBefore(next)) {
      return Future.value(const SyncReport.skipped());
    }
    final run = _run().whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<SyncReport> _run() async {
    // Never read or send steps under an unbound / previous user.
    if (!await _binding.whenReady()) return const SyncReport.skipped();
    _syncing = true;
    _notify();
    var sent = 0, acked = 0, accepted = 0, duplicates = 0, rejected = 0;
    try {
      final deviceId = _deviceId ??= await _engine.getDeviceId();
      if (!_registered) {
        final caps = await _engine.getCapabilities();
        _isRewardDevice = await _callables.registerDevice(
          deviceId: deviceId,
          model: caps.model,
          appVersion: appVersion,
          fcmToken: _fcmToken,
        );
        _registered = true;
      }

      var incomplete = false;
      for (var batchNo = 0; batchNo < maxBatchesPerRun; batchNo++) {
        final buckets = await _engine.getBucketsForSync(limit: batchLimit);
        if (buckets.isEmpty) break;
        final startMs = [for (final b in buckets) b.startMs];
        final resp = await _callables.syncStepBuckets(deviceId: deviceId, buckets: buckets);
        sent += buckets.length;
        accepted += resp.acceptedIds?.length ?? resp.acceptedCount;
        duplicates += resp.duplicateIds?.length ?? resp.duplicateCount;
        rejected += resp.rejected.length;
        if (resp.today != null) _lastServerToday = resp.today;

        final ack = resp.ackable(startMs).toList()..sort();
        if (ack.isEmpty) {
          throw const AppException(
            code: 'sync-unconfirmed',
            message: 'The server did not confirm your steps yet. Will retry.',
          );
        }
        await _engine.ackBuckets(ack);
        acked += ack.length;
        _totalAcked += ack.length;
        if (ack.length < startMs.length) {
          // Some buckets were not confirmed - retry them later with back-off
          // instead of hammering the server in a tight loop.
          incomplete = true;
          break;
        }
        if (buckets.length < batchLimit) break;
      }
      if (incomplete) {
        throw const AppException(
          code: 'sync-unconfirmed',
          message: 'Some steps were not confirmed yet. Will retry.',
        );
      }
      _lastSyncAt = _clock.now();
      _lastError = null;
      _consecutiveFailures = 0;
      _nextAttemptAt = null;
      return SyncReport(
        sent: sent,
        acked: acked,
        accepted: accepted,
        duplicates: duplicates,
        rejected: rejected,
      );
    } catch (e) {
      _consecutiveFailures++;
      final factor = math.pow(2, math.min(_consecutiveFailures - 1, 20)).toInt();
      var wait = baseBackoff * factor;
      if (wait > maxBackoff) wait = maxBackoff;
      _nextAttemptAt = _clock.now().add(wait);
      final message = e is AppException ? e.message : 'Could not sync your steps. Will retry.';
      _lastError = message;
      return SyncReport(
        sent: sent,
        acked: acked,
        accepted: accepted,
        duplicates: duplicates,
        rejected: rejected,
        error: message,
      );
    } finally {
      _syncing = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
