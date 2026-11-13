import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/clock.dart';
import '../../domain/day_key.dart';
import '../../domain/step_models.dart';
import 'step_engine_binding.dart';
import 'step_engine_channel.dart';
import 'step_permissions.dart';
import 'step_sync_service.dart';

/// Outcome of [StepTrackingController.setTracking].
enum TrackingChange {
  started,
  stopped,

  /// User declined the rationale or the system prompt.
  permissionDenied,

  /// Permission is permanently denied - offer "Open settings".
  permissionPermanentlyDenied,

  /// Device has no step counter.
  unsupported,

  /// The foreground service could not start (`START_FAILED`).
  startFailed,
  failed,
}

/// App-wide state of the step engine: capabilities, tracking on/off,
/// permission status and the live snapshot. Verified numbers shown to the
/// user come from here (today) - there is no way to edit them.
class StepTrackingController extends ChangeNotifier {
  StepTrackingController({
    required StepEngineChannel engine,
    required StepPermissions permissions,
    required Clock clock,
    required StepEngineBinding binding,
    StepSyncService? sync,
  })  : _engine = engine,
        _binding = binding,
        _permissions = permissions,
        _clock = clock,
        _sync = sync {
    _binding.addListener(_onBinding);
  }

  final StepEngineChannel _engine;
  final StepPermissions _permissions;
  final Clock _clock;
  final StepSyncService? _sync;
  final StepEngineBinding _binding;
  bool _wantLive = false;

  EngineCapabilities? _capabilities;
  bool _tracking = false;
  TodaySummary? _today;
  LiveSnapshot? _live;
  StepPermissionStatus? _permissionStatus;
  AppException? _engineError;
  bool _busy = false;
  bool _loaded = false;
  bool _disposed = false;
  StreamSubscription<LiveSnapshot>? _liveSub;

  EngineCapabilities? get capabilities => _capabilities;
  bool get tracking => _tracking;
  StepPermissionStatus? get permissionStatus => _permissionStatus;
  bool get busy => _busy;
  bool get loaded => _loaded;

  /// Null when the engine answered normally.
  AppException? get engineError => _engineError;

  /// False on devices/builds without the native engine or a step counter.
  bool get engineAvailable =>
      _engineError == null && (_capabilities?.stepCounter ?? true);

  StepSyncService? get sync => _sync;

  /// Today's engine ledger (live values override while a stream is attached).
  TodaySummary? get today {
    final base = _today;
    final live = _live;
    if (live == null) return base;
    return TodaySummary(
      raw: live.raw,
      verified: live.verified,
      pending: live.pending,
      rejected: live.rejected,
      suspicious: live.suspicious,
      unwitnessed: base?.unwitnessed ?? 0,
      gap: base?.gap ?? 0,
    );
  }

  String get liveLabel => _live?.liveLabel ?? '';

  void _onBinding() {
    if (_disposed) return;
    if (!_binding.isReady) {
      // Unbound (signed out / switching user): never show the previous user's numbers.
      _today = null;
      _live = null;
      _liveSub?.cancel();
      _liveSub = null;
      _notify();
    } else {
      if (_wantLive) _subscribeLive();
      unawaited(refresh());
    }
  }

  /// Reloads capabilities, tracking state, permissions and today's ledger.
  /// Waits for the engine to be bound to the current user first.
  Future<void> refresh() async {
    if (!await _binding.whenReady()) {
      _notify();
      return;
    }
    // The user may sign out / switch while the (async) engine calls below are in flight. Their results then belong to
    // the PREVIOUS user and must be dropped, otherwise student A's numbers reappear after the unbind (found by the
    // on-device E2E run: `today` was still set right after sign-out).
    final uid = _binding.uid;
    bool stale() => _disposed || !_binding.isReady || _binding.uid != uid;
    try {
      final caps = await _engine.getCapabilities();
      final tracking = await _engine.isTracking();
      final b = DayKey.boundsMs(_clock.now());
      final today = await _engine.getTodaySummary(dayStartMs: b.startMs, dayEndMs: b.endMs);
      if (stale()) return;
      _capabilities = caps;
      _tracking = tracking;
      _today = today;
      _engineError = null;
    } on AppException catch (e) {
      if (stale()) return;
      _engineError = e;
    } catch (_) {
      if (stale()) return;
      _engineError = const AppException(
        code: 'engine-error',
        message: 'The step engine could not be reached.',
      );
    }
    try {
      _permissionStatus = await _permissions.check();
    } catch (_) {
      // Permission plugin unavailable (tests, unsupported platform).
    }
    _loaded = true;
    _notify();
  }

  /// Start receiving the ~2 s live snapshots (call when the UI is visible).
  void attach() {
    _wantLive = true;
    if (_binding.isReady) _subscribeLive();
  }

  void _subscribeLive() {
    if (_liveSub != null) return;
    try {
      _liveSub = _engine.liveEvents.listen(
        (s) {
          if (!_binding.isReady) return; // a late event of the previous user
          _live = s;
          _tracking = s.tracking;
          _notify();
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // No event channel available.
    }
  }

  /// Stop receiving live snapshots (app in background).
  void detach() {
    _wantLive = false;
    _liveSub?.cancel();
    _liveSub = null;
  }

  /// Turns tracking on/off. When enabling, asks for permissions first;
  /// [rationale] shows the explanation dialog (returns false to cancel).
  Future<TrackingChange> setTracking(bool on, {Future<bool> Function()? rationale}) async {
    if (_busy) return TrackingChange.failed;
    _busy = true;
    _notify();
    try {
      if (!on) {
        await _engine.stopTracking();
        _tracking = false;
        return TrackingChange.stopped;
      }
      if (!await _binding.whenReady()) {
        _engineError = const AppException(
          code: 'engine-not-bound',
          message: 'Step tracking is still getting ready. Please try again in a moment.',
        );
        return TrackingChange.failed;
      }
      final status = await _permissions.request(rationale: rationale);
      _permissionStatus = status;
      if (!status.canTrack) {
        return status.activityPermanentlyDenied
            ? TrackingChange.permissionPermanentlyDenied
            : TrackingChange.permissionDenied;
      }
      final result = await _engine.startTracking();
      if (!result.started) {
        if (result.reason == 'NO_STEP_COUNTER') return TrackingChange.unsupported;
        if (result.reason == 'PERMISSION_DENIED') return TrackingChange.permissionDenied;
        if (result.reason == 'START_FAILED') return TrackingChange.startFailed;
        return TrackingChange.failed;
      }
      _tracking = true;
      _engineError = null;
      unawaited(_sync?.syncNow(force: true));
      return TrackingChange.started;
    } on AppException catch (e) {
      _engineError = e;
      return TrackingChange.failed;
    } finally {
      _busy = false;
      _notify();
      // Pick up capability changes (e.g. permission just granted).
      unawaited(refresh());
    }
  }

  Future<bool> openSettings() => _permissions.openSettings();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _binding.removeListener(_onBinding);
    detach();
    super.dispose();
  }
}
