import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/firestore/firestore_access.dart';
import '../../data/firestore/hostel_repository.dart';
import '../../data/notifications/notifications_count.dart';
import '../../data/steps/step_sync_service.dart';
import '../../data/steps/step_tracking_controller.dart';
import '../../domain/campus_activity.dart';
import '../../domain/daily_step_summary.dart';
import '../../domain/day_key.dart';
import '../../domain/hostel_seed.dart';

/// One bar of the weekly chart.
class DayBar {
  const DayBar({required this.dayKey, required this.label, required this.verified, required this.isToday});

  final String dayKey;
  final String label;
  final int verified;
  final bool isToday;
}

/// Numbers shown in the Step breakdown card.
class StepBreakdown {
  const StepBreakdown({
    required this.raw,
    required this.verified,
    required this.pending,
    required this.rejected,
    required this.suspicious,
  });

  final int raw;
  final int verified;
  final int pending;
  final int rejected;
  final int suspicious;
}

/// State of the Home dashboard. Verified totals come from the native engine
/// (today) and from `dailyStepSummaries` (server-confirmed history); nothing
/// here can be edited by the user.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required this.uid,
    required FirestoreAccess firestore,
    required NotificationsCount notifications,
    required CampusActivitySource campus,
    required HostelRepository hostels,
    required this.tracking,
    required this.sync,
    required Clock clock,
    this.hostelId,
  })  : _firestore = firestore,
        _notifications = notifications,
        _campus = campus,
        _hostelsRepo = hostels,
        _clock = clock;

  final String uid;
  final String? hostelId;
  final StepTrackingController tracking;
  final StepSyncService sync;
  final FirestoreAccess _firestore;
  final NotificationsCount _notifications;
  final CampusActivitySource _campus;
  final HostelRepository _hostelsRepo;
  final Clock _clock;

  StreamSubscription<List<DailyStepSummary>>? _summarySub;
  StreamSubscription<int>? _unreadSub;
  List<DailyStepSummary> _summaries = const [];
  bool _summariesLoaded = false;
  bool _summariesFailed = false;
  int _unread = 0;
  CampusActivity? _campusActivity;
  bool _campusLoaded = false;
  String? _hostelName;
  bool _disposed = false;

  List<DailyStepSummary> get summaries => _summaries;
  bool get summariesLoaded => _summariesLoaded;
  bool get summariesFailed => _summariesFailed;
  int get unread => _unread;
  CampusActivity? get campusActivity => _campusActivity;
  bool get campusLoaded => _campusLoaded;

  String? get hostelName {
    if (_hostelName != null) return _hostelName;
    for (final h in hostelSeed) {
      if (h.id == hostelId) return h.displayName;
    }
    return hostelId;
  }

  void start() {
    _subscribe();
    _unreadSub = _notifications.watchUnread(uid).listen(
      (n) {
        _unread = n;
        _notify();
      },
      onError: (Object _) {},
    );
    unawaited(_loadCampus());
    unawaited(_loadHostelName());
    unawaited(tracking.refresh());
  }

  void _subscribe() {
    _summarySub?.cancel();
    _summariesFailed = false;
    _summarySub = _firestore.watchDailySummaries(uid, limit: 30).listen(
      (list) {
        _summaries = list;
        _summariesLoaded = true;
        _summariesFailed = false;
        _notify();
      },
      onError: (Object _) {
        _summariesLoaded = true;
        _summariesFailed = true;
        _notify();
      },
    );
  }

  Future<void> _loadCampus() async {
    try {
      _campusActivity = await _campus.load(uid);
    } catch (_) {
      _campusActivity = CampusActivity.empty;
    }
    _campusLoaded = true;
    _notify();
  }

  Future<void> _loadHostelName() async {
    if (hostelId == null) return;
    try {
      final dir = await _hostelsRepo.load();
      _hostelName = dir.byId(hostelId)?.displayName;
      _notify();
    } catch (_) {}
  }

  /// Pull-to-refresh: re-read the engine, push pending buckets to the server
  /// and reload the campus block.
  Future<void> refresh() async {
    _subscribe();
    await Future.wait([
      tracking.refresh(),
      sync.syncNow(force: true),
      _loadCampus(),
    ]);
  }

  // ---- derived values ----------------------------------------------------

  String get todayKey => DayKey.of(_clock.now());

  DailyStepSummary? get serverToday {
    final k = todayKey;
    for (final s in _summaries) {
      if (s.dayKey == k) return s;
    }
    return null;
  }

  /// Verified steps today: the larger of the engine's ledger and the
  /// server-confirmed summary (the engine is empty after a reinstall; the
  /// server is behind until the next sync).
  int get todayVerified {
    final engine = tracking.engineAvailable ? tracking.today?.verified : null;
    final server = serverToday?.verifiedSteps;
    return [engine ?? 0, server ?? 0].reduce((a, b) => a > b ? a : b);
  }

  StepBreakdown get breakdown {
    final eng = tracking.engineAvailable ? tracking.today : null;
    final server = serverToday;
    return StepBreakdown(
      raw: eng?.raw ?? server?.rawSteps ?? 0,
      verified: todayVerified,
      pending: eng?.pending ?? 0,
      rejected: eng?.rejected ?? server?.rejectedSteps ?? 0,
      suspicious: eng?.suspicious ?? 0,
    );
  }

  /// Seven bars, oldest first, ending today.
  List<DayBar> weeklyBars() {
    final keys = DayKey.lastDays(_clock.now(), 7);
    final byKey = {for (final s in _summaries) s.dayKey: s};
    return [
      for (final k in keys)
        DayBar(
          dayKey: k,
          label: DayKey.weekdayShort(k).substring(0, 1),
          verified: k == todayKey ? todayVerified : (byKey[k]?.verifiedSteps ?? 0),
          isToday: k == todayKey,
        ),
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _summarySub?.cancel();
    _unreadSub?.cancel();
    super.dispose();
  }
}
