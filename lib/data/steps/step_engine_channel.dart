import '../../domain/step_models.dart';

/// Dart view of the native genuine-step engine (Kotlin). The contract is
/// defined in DATABASE_SCHEMA.md, section "Android <-> Flutter channel
/// contract". UI code never uses the channel directly; it goes through
/// `StepTrackingController` / `StepSyncService`.
///
/// All methods throw `AppException` when the engine is unavailable.
abstract class StepEngineChannel {
  Future<EngineCapabilities> getCapabilities();

  /// Starts the foreground tracking service. `started == false` carries a
  /// `reason` (`PERMISSION_DENIED`, `NO_STEP_COUNTER`).
  Future<StartTrackingResult> startTracking();

  Future<void> stopTracking();

  Future<bool> isTracking();

  /// Engine ledger totals for buckets starting in `[dayStartMs, dayEndMs)`.
  Future<TodaySummary> getTodaySummary({required int dayStartMs, required int dayEndMs});

  /// Settled buckets not yet acknowledged, oldest first.
  Future<List<EngineBucket>> getBucketsForSync({int limit = 200});

  /// Marks buckets as delivered. Idempotent. Returns the number acknowledged.
  Future<int> ackBuckets(List<int> startMsList);

  Future<LiveStatus> getLiveStatus();

  /// Binds the native ledger to [uid]. Must complete before any
  /// summary/sync/start for that user. Older native builds without this method
  /// resolve to [BindResult.unsupported] (never throws for that reason).
  Future<BindResult> bindUser(String uid);

  /// Stable random per-install id (not an advertising/hardware id).
  Future<String> getDeviceId();

  /// Snapshot every ~2 s while at least one listener is attached.
  Stream<LiveSnapshot> get liveEvents;
}
