/// Models for the native step engine channel
/// (`edu.thapar.stepup/engine`, see DATABASE_SCHEMA.md).
library;

int _i(Object? v) => v is num ? v.toInt() : 0;
String? _s(Object? v) => v is String ? v : null;

/// `getCapabilities` result.
class EngineCapabilities {
  const EngineCapabilities({
    this.stepCounter = false,
    this.accelerometer = false,
    this.gyroscope = false,
    this.activityRecognitionGranted = false,
    this.notificationsGranted = false,
    this.evidenceMode = '',
    this.sdkInt = 0,
    this.model = '',
  });

  factory EngineCapabilities.fromMap(Map<dynamic, dynamic> m) => EngineCapabilities(
        stepCounter: m['stepCounter'] == true,
        accelerometer: m['accelerometer'] == true,
        gyroscope: m['gyroscope'] == true,
        activityRecognitionGranted: m['activityRecognitionGranted'] == true,
        notificationsGranted: m['notificationsGranted'] == true,
        evidenceMode: _s(m['evidenceMode']) ?? '',
        sdkInt: _i(m['sdkInt']),
        model: _s(m['model']) ?? '',
      );

  final bool stepCounter;
  final bool accelerometer;
  final bool gyroscope;
  final bool activityRecognitionGranted;
  final bool notificationsGranted;
  final String evidenceMode;
  final int sdkInt;
  final String model;
}

/// `startTracking` result.
class StartTrackingResult {
  const StartTrackingResult({required this.started, this.reason});

  factory StartTrackingResult.fromMap(Map<dynamic, dynamic> m) =>
      StartTrackingResult(started: m['started'] == true, reason: _s(m['reason']));

  final bool started;

  /// `PERMISSION_DENIED` or `NO_STEP_COUNTER` when not started.
  final String? reason;
}

/// `getTodaySummary` result (engine ledgers for the requested day range).
class TodaySummary {
  const TodaySummary({
    this.raw = 0,
    this.verified = 0,
    this.pending = 0,
    this.rejected = 0,
    this.suspicious = 0,
    this.unwitnessed = 0,
    this.gap = 0,
  });

  factory TodaySummary.fromMap(Map<dynamic, dynamic> m) => TodaySummary(
        raw: _i(m['raw']),
        verified: _i(m['verified']),
        pending: _i(m['pending']),
        rejected: _i(m['rejected']),
        suspicious: _i(m['suspicious']),
        unwitnessed: _i(m['unwitnessed']),
        gap: _i(m['gap']),
      );

  final int raw;
  final int verified;
  final int pending;
  final int rejected;

  /// Subset of [rejected] whose reason indicates shaking/vehicle/cadence.
  final int suspicious;
  final int unwitnessed;
  final int gap;
}

/// `bindUser` result: the native ledger is bound to one user at a time; after a
/// user switch only buckets with `startMs >= sinceMs` are offered/aggregated.
class BindResult {
  const BindResult({required this.bound, required this.changed, this.sinceMs = 0});

  /// Result for native builds that do not implement `bindUser` (treated as an
  /// unchanged binding so an older build keeps working).
  static const BindResult unsupported = BindResult(bound: false, changed: false);

  factory BindResult.fromMap(Map<dynamic, dynamic> m) => BindResult(
        bound: m['bound'] == true,
        changed: m['changed'] == true,
        sinceMs: _i(m['sinceMs']),
      );

  final bool bound;
  final bool changed;
  final int sinceMs;
}

/// `getLiveStatus` result.
class LiveStatus {
  const LiveStatus({
    this.tracking = false,
    this.liveLabel = '',
    this.carryMode = '',
    this.lastRejection,
  });

  factory LiveStatus.fromMap(Map<dynamic, dynamic> m) => LiveStatus(
        tracking: m['tracking'] == true,
        liveLabel: _s(m['liveLabel']) ?? '',
        carryMode: _s(m['carryMode']) ?? '',
        lastRejection: _s(m['lastRejection']),
      );

  final bool tracking;
  final String liveLabel;
  final String carryMode;
  final String? lastRejection;
}

/// One event of the `engine_events` stream (every ~2 s while listening).
class LiveSnapshot {
  const LiveSnapshot({
    this.tracking = false,
    this.raw = 0,
    this.verified = 0,
    this.pending = 0,
    this.rejected = 0,
    this.suspicious = 0,
    this.liveLabel = '',
  });

  factory LiveSnapshot.fromMap(Map<dynamic, dynamic> m) => LiveSnapshot(
        tracking: m['tracking'] == true,
        raw: _i(m['raw']),
        verified: _i(m['verified']),
        pending: _i(m['pending']),
        rejected: _i(m['rejected']),
        suspicious: _i(m['suspicious']),
        liveLabel: _s(m['liveLabel']) ?? '',
      );

  final bool tracking;
  final int raw;
  final int verified;
  final int pending;
  final int rejected;
  final int suspicious;
  final String liveLabel;
}

/// A settled 10 s bucket returned by `getBucketsForSync`.
class EngineBucket {
  const EngineBucket({
    required this.startMs,
    required this.bootCount,
    required this.rawDelta,
    required this.credited,
    required this.state,
    this.reason,
    this.walkFraction = 0,
    this.evidenceMode = '',
    this.carryMode = '',
    this.hops = const [],
    this.lateRawAdded = 0,
    this.lateCreditedAdded = 0,
  });

  factory EngineBucket.fromMap(Map<dynamic, dynamic> m) => EngineBucket(
        startMs: _i(m['startMs']),
        bootCount: _i(m['bootCount']),
        rawDelta: _i(m['rawDelta']),
        credited: _i(m['credited']),
        state: _s(m['state']) ?? 'UNWITNESSED',
        reason: _s(m['reason']),
        walkFraction: (m['walkFraction'] as num?)?.toDouble() ?? 0,
        evidenceMode: _s(m['evidenceMode']) ?? '',
        carryMode: _s(m['carryMode']) ?? '',
        hops: [
          for (final h in (m['hops'] as List? ?? const []))
            if (h is Map)
              EngineHop(label: _s(h['label']) ?? 'UNKNOWN', imuSteps: _i(h['imuSteps'])),
        ],
        lateRawAdded: _i(m['lateRawAdded']),
        lateCreditedAdded: _i(m['lateCreditedAdded']),
      );

  final int startMs;
  final int bootCount;
  final int rawDelta;
  final int credited;
  final String state;
  final String? reason;
  final double walkFraction;
  final String evidenceMode;
  final String carryMode;
  final List<EngineHop> hops;

  /// Late steps added to this bucket after it first settled. `rawDelta` and
  /// `credited` already include them; passed through unchanged so the backend
  /// can upsert late credit.
  final int lateRawAdded;
  final int lateCreditedAdded;

  /// Shape expected by the `syncStepBuckets` callable. The server re-validates
  /// everything and can only downgrade the claim.
  Map<String, dynamic> toSyncJson() => {
        'startMs': startMs,
        'bootCount': bootCount,
        'rawDelta': rawDelta,
        'credited': credited,
        'state': state,
        'reason': reason,
        'walkFraction': walkFraction,
        'evidenceMode': evidenceMode,
        'carryMode': carryMode,
        'hops': [for (final h in hops) h.toJson()],
        'lateRawAdded': lateRawAdded,
        'lateCreditedAdded': lateCreditedAdded,
      };
}

class EngineHop {
  const EngineHop({required this.label, required this.imuSteps});

  final String label;
  final int imuSteps;

  Map<String, dynamic> toJson() => {'label': label, 'imuSteps': imuSteps};
}

/// `today` block of the `syncStepBuckets` result (server-confirmed).
class ServerToday {
  const ServerToday({
    this.verifiedSteps = 0,
    this.rawSteps = 0,
    this.rejectedSteps = 0,
    this.unwitnessedSteps = 0,
  });

  factory ServerToday.fromMap(Map<dynamic, dynamic> m) => ServerToday(
        verifiedSteps: _i(m['verifiedSteps']),
        rawSteps: _i(m['rawSteps']),
        rejectedSteps: _i(m['rejectedSteps']),
        unwitnessedSteps: _i(m['unwitnessedSteps']),
      );

  final int verifiedSteps;
  final int rawSteps;
  final int rejectedSteps;
  final int unwitnessedSteps;
}

/// Parsed `syncStepBuckets` response.
///
/// `accepted` / `duplicates` may be either counts or lists of `startMs`;
/// `rejected` is a list of `{startMs, reason}` (permanent rejections).
/// [ackable] decides which of the sent buckets may be acknowledged natively:
/// only those the server explicitly reports as accepted, duplicate or
/// permanently rejected.
class SyncResponse {
  const SyncResponse({
    this.acceptedIds,
    this.acceptedCount = 0,
    this.duplicateIds,
    this.duplicateCount = 0,
    this.rejected = const {},
    this.today,
  });

  factory SyncResponse.fromMap(Map<dynamic, dynamic> m) {
    Set<int>? ids(Object? v) => v is List
        ? {
            for (final e in v)
              if (e is num) e.toInt() else if (e is Map && e['startMs'] is num) (e['startMs'] as num).toInt(),
          }
        : null;
    int count(Object? v) => v is num ? v.toInt() : (v is List ? v.length : 0);
    final rejected = <int, String>{};
    final r = m['rejected'];
    if (r is List) {
      for (final e in r) {
        if (e is Map && e['startMs'] is num) {
          rejected[(e['startMs'] as num).toInt()] = _s(e['reason']) ?? 'REJECTED';
        }
      }
    }
    final today = m['today'];
    return SyncResponse(
      acceptedIds: ids(m['accepted']),
      acceptedCount: count(m['accepted']),
      duplicateIds: ids(m['duplicates']),
      duplicateCount: count(m['duplicates']),
      rejected: rejected,
      today: today is Map ? ServerToday.fromMap(today) : null,
    );
  }

  final Set<int>? acceptedIds;
  final int acceptedCount;
  final Set<int>? duplicateIds;
  final int duplicateCount;
  final Map<int, String> rejected;
  final ServerToday? today;

  /// Start times of [sent] buckets that are safe to acknowledge.
  Set<int> ackable(List<int> sent) {
    final sentSet = sent.toSet();
    final out = <int>{...rejected.keys.where(sentSet.contains)};
    final listsKnown = acceptedIds != null && duplicateIds != null;
    if (listsKnown) {
      out
        ..addAll(acceptedIds!.where(sentSet.contains))
        ..addAll(duplicateIds!.where(sentSet.contains));
    } else if (acceptedCount + duplicateCount + rejected.length == sent.length) {
      // Only counts reported and they account for every bucket sent.
      out.addAll(sentSet);
    }
    return out;
  }
}
