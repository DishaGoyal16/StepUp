import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../data/firestore/firestore_access.dart';
import '../../data/firestore/hostel_repository.dart';
import '../../data/profile_extras/badges.dart';
import '../../data/profile_extras/extras_models.dart';
import '../../domain/day_key.dart';
import 'profile_providers.dart';

/// Load state of one profile section; sections fail independently so one
/// broken read never blanks the whole tab.
class SectionState<T> {
  const SectionState.loading() : this._(null, true, false);
  const SectionState.data(T data) : this._(data, false, false);
  const SectionState.failed() : this._(null, false, true);
  const SectionState._(this.data, this.loading, this.failed);

  final T? data;
  final bool loading;
  final bool failed;
}

/// Verified-step totals shown on the profile (server-confirmed only).
class VerifiedStepsSummary {
  const VerifiedStepsSummary({required this.last7Days, required this.last30Days});

  final int last7Days;
  final int last30Days;
}

/// Everything the profile tab shows besides the live `users/{uid}` document
/// (which comes from the session).
class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required this.uid,
    required this.hostelId,
    required ProfileDataSources sources,
    required FirestoreAccess firestore,
    required HostelRepository hostels,
    required Clock clock,
  })  : _sources = sources,
        _firestore = firestore,
        _hostels = hostels,
        _clock = clock;

  final String uid;
  final String hostelId;
  final ProfileDataSources _sources;
  final FirestoreAccess _firestore;
  final HostelRepository _hostels;
  final Clock _clock;

  final List<StreamSubscription<Object?>> _subs = [];
  bool _disposed = false;
  int _generation = 0;

  String? hostelName;
  SectionState<VerifiedStepsSummary> steps = const SectionState.loading();
  SectionState<CampusRank?> rank = const SectionState.loading();
  SectionState<List<BadgeStatus>> badges = const SectionState.loading();
  SectionState<List<CompletedChallenge>> completed = const SectionState.loading();
  SectionState<List<BuddySummary>> buddies = const SectionState.loading();
  SectionState<List<LedgerEntry>> ledger = const SectionState.loading();

  List<BadgeDefinition>? _catalogue;
  List<Achievement>? _achievements;
  bool _achievementsFailed = false;

  void start() {
    final gen = ++_generation;
    unawaited(_loadHostel(gen));
    _listenSteps();
    _listenAchievements();
    unawaited(_loadCatalogue(gen));
    _listenCompleted();
    _listenBuddies();
    unawaited(_loadRank(gen));
    unawaited(_loadLedger(gen));
  }

  /// Reloads every section (pull-to-refresh / retry).
  Future<void> refresh() async {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _catalogue = null;
    _achievements = null;
    _achievementsFailed = false;
    steps = const SectionState.loading();
    rank = const SectionState.loading();
    badges = const SectionState.loading();
    completed = const SectionState.loading();
    buddies = const SectionState.loading();
    ledger = const SectionState.loading();
    _notify();
    start();
  }

  // --- sections -------------------------------------------------------------

  Future<void> _loadHostel(int gen) async {
    if (hostelId.isEmpty) return;
    final dir = await _hostels.load();
    if (_stale(gen)) return;
    hostelName = dir.byId(hostelId)?.displayName ?? hostelId;
    _notify();
  }

  void _listenSteps() {
    _subs.add(
      _firestore.watchDailySummaries(uid, limit: 30).listen(
        (list) {
          final now = _clock.now();
          final last7 = DayKey.lastDays(now, 7).toSet();
          final last30 = DayKey.lastDays(now, 30).toSet();
          var s7 = 0;
          var s30 = 0;
          for (final d in list) {
            if (last30.contains(d.dayKey)) s30 += d.verifiedSteps;
            if (last7.contains(d.dayKey)) s7 += d.verifiedSteps;
          }
          steps = SectionState.data(VerifiedStepsSummary(last7Days: s7, last30Days: s30));
          _notify();
        },
        onError: (Object _) {
          steps = const SectionState.failed();
          _notify();
        },
      ),
    );
  }

  void _listenAchievements() {
    _subs.add(
      _sources.extras.watchAchievements(uid).listen(
        (list) {
          _achievements = list;
          _achievementsFailed = false;
          _recomputeBadges();
        },
        onError: (Object _) {
          _achievementsFailed = true;
          _recomputeBadges();
        },
      ),
    );
  }

  Future<void> _loadCatalogue(int gen) async {
    List<BadgeDefinition> catalogue;
    try {
      catalogue = await _sources.extras.fetchBadgeCatalogue();
    } catch (_) {
      // Catalogue document unreachable: show the built-in layout of the six
      // known badges (still all locked unless a server achievement exists).
      catalogue = buildBadgeCatalogue(null);
    }
    if (_stale(gen)) return;
    _catalogue = catalogue;
    _recomputeBadges();
  }

  void _recomputeBadges() {
    if (_achievementsFailed) {
      badges = const SectionState.failed();
    } else if (_catalogue != null && _achievements != null) {
      badges = SectionState.data(mergeBadgeStatus(_catalogue!, _achievements!));
    }
    _notify();
  }

  void _listenCompleted() {
    _subs.add(
      _sources.extras.watchCompletedChallenges(uid).listen(
        (list) {
          completed = SectionState.data(list);
          _notify();
        },
        onError: (Object _) {
          completed = const SectionState.failed();
          _notify();
        },
      ),
    );
  }

  void _listenBuddies() {
    _subs.add(
      _sources.buddies.watchBuddies(uid).listen(
        (list) {
          buddies = SectionState.data(list);
          _notify();
        },
        onError: (Object _) {
          buddies = const SectionState.failed();
          _notify();
        },
      ),
    );
  }

  Future<void> _loadRank(int gen) async {
    SectionState<CampusRank?> next;
    try {
      next = SectionState.data(await _sources.rank.fetchWeekly());
    } catch (_) {
      next = const SectionState.failed(); // tolerated: the card shows "unavailable"
    }
    if (_stale(gen)) return;
    rank = next;
    _notify();
  }

  Future<void> _loadLedger(int gen) async {
    SectionState<List<LedgerEntry>> next;
    try {
      next = SectionState.data(await _sources.extras.fetchRecentLedger(uid));
    } catch (_) {
      next = const SectionState.failed();
    }
    if (_stale(gen)) return;
    ledger = next;
    _notify();
  }

  bool _stale(int gen) => _disposed || gen != _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
