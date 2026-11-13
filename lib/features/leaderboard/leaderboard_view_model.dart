import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/leaderboard/leaderboard_models.dart';
import '../../data/leaderboard/leaderboard_repository.dart';
import '../../domain/hostel.dart';
import '../../domain/hostel_seed.dart';

enum LeaderboardStatus { loading, ready, error }

/// State of the Leaderboard tab: selected scope / period / hostel metric and
/// the server's answer for that selection.
///
/// Every load carries a sequence number; a response is applied only if it is
/// still the latest request, so switching chips quickly never shows the board
/// of an earlier selection.
class LeaderboardViewModel extends ChangeNotifier {
  LeaderboardViewModel({
    required LeaderboardRepository repository,
    required this.uid,
    this.myHostelId,
    this.myName,
    this.dailyGoal,
    Future<HostelDirectory> Function()? loadHostels,
    this.limit = LeaderboardRepository.defaultLimit,
    LeaderboardScope scope = LeaderboardScope.campus,
    LeaderboardPeriod period = LeaderboardPeriod.weekly,
  })  : _repository = repository,
        _loadHostels = loadHostels,
        _scope = scope,
        _period = period;

  final LeaderboardRepository _repository;
  final Future<HostelDirectory> Function()? _loadHostels;

  final String uid;
  final String? myHostelId;
  final String? myName;

  /// The user's daily goal: the progress-bar basis of DAILY student boards.
  final int? dailyGoal;
  final int limit;

  LeaderboardScope _scope;
  LeaderboardPeriod _period;
  HostelMetric _hostelMetric = HostelMetric.average;

  LeaderboardStatus _status = LeaderboardStatus.loading;
  LeaderboardResult? _result;
  AppException? _error;
  AppException? _refreshError;
  bool _refreshing = false;
  HostelDirectory? _hostels;

  int _seq = 0;
  bool _disposed = false;

  LeaderboardScope get scope => _scope;
  LeaderboardPeriod get period => _period;
  HostelMetric get hostelMetric => _hostelMetric;
  LeaderboardQuery get query =>
      LeaderboardQuery(scope: _scope, period: _period, hostelMetric: _hostelMetric);

  LeaderboardStatus get status => _status;
  LeaderboardResult? get result => _result;

  /// Failure while there is nothing to show (full error state).
  AppException? get error => _error;

  /// Failure of a refresh while an older board is still on screen.
  AppException? get refreshError => _refreshError;
  bool get isRefreshing => _refreshing;

  bool get isHostelBoard => _scope == LeaderboardScope.hostels;

  void start() {
    unawaited(_loadHostelNames());
    unawaited(_load(clear: true));
  }

  void selectScope(LeaderboardScope s) {
    if (s == _scope) return;
    _scope = s;
    unawaited(_load(clear: true));
  }

  void selectPeriod(LeaderboardPeriod p) {
    if (p == _period) return;
    _period = p;
    unawaited(_load(clear: true));
  }

  void selectHostelMetric(HostelMetric m) {
    if (m == _hostelMetric) return;
    _hostelMetric = m;
    // Only the Hostels board depends on the metric.
    if (isHostelBoard) unawaited(_load(clear: true));
  }

  /// Pull-to-refresh / retry. Keeps the current board on screen meanwhile.
  Future<void> refresh() => _load(clear: _status == LeaderboardStatus.error);

  Future<void> _load({required bool clear}) async {
    final seq = ++_seq;
    final q = query;
    if (clear) {
      _result = null;
      _status = LeaderboardStatus.loading;
      _refreshing = false;
    } else {
      _refreshing = _result != null;
      if (_result == null) _status = LeaderboardStatus.loading;
    }
    _error = null;
    _refreshError = null;
    _notify();
    try {
      final r = await _repository.load(q, limit: limit);
      if (_stale(seq)) return;
      _result = r;
      _status = LeaderboardStatus.ready;
      _refreshing = false;
    } on AppException catch (e) {
      if (_stale(seq)) return;
      _fail(e);
    } catch (_) {
      if (_stale(seq)) return;
      _fail(AppException.fromCallable(code: 'internal'));
    }
    _notify();
  }

  void _fail(AppException e) {
    _refreshing = false;
    if (_result != null) {
      _refreshError = e;
    } else {
      _error = e;
      _status = LeaderboardStatus.error;
    }
  }

  bool _stale(int seq) => _disposed || seq != _seq;

  Future<void> _loadHostelNames() async {
    final loader = _loadHostels;
    if (loader == null) return;
    try {
      final dir = await loader();
      if (_disposed) return;
      _hostels = dir;
      _notify();
    } catch (_) {
      // Display names fall back to the built-in seed / the id.
    }
  }

  // ---- derived values ----------------------------------------------------

  /// Display name of [hostelId]; null when there is none to show.
  String? hostelNameOf(String? hostelId) {
    if (hostelId == null || hostelId.isEmpty) return null;
    final live = _hostels?.byId(hostelId);
    if (live != null) return live.displayName;
    for (final h in hostelSeed) {
      if (h.id == hostelId) return h.displayName;
    }
    return hostelId;
  }

  /// Is [e] the signed-in user's row (their hostel's row on the Hostels board)?
  bool isMine(LeaderboardEntry e) {
    if (e.id.isEmpty) return false;
    return e.isHostel ? (myHostelId != null && e.id == myHostelId) : e.id == uid;
  }

  /// Progress-bar denominator: the daily goal for DAILY student boards,
  /// otherwise `null` meaning "relative to the leader".
  num? get progressBase {
    if (!isHostelBoard && _period == LeaderboardPeriod.daily && (dailyGoal ?? 0) > 0) {
      return dailyGoal;
    }
    return null;
  }

  bool get meInList => _result?.entries.any(isMine) ?? false;

  /// Show the extra "Your rank" card: the server ranked me but not within the
  /// returned entries.
  bool get showPinnedMe {
    final r = _result;
    if (r == null) return false;
    final rank = r.me?.rank;
    return rank != null && !meInList;
  }

  /// The user is not on this board (not ranked).
  bool get notRanked {
    final r = _result;
    if (r == null) return false;
    return r.me?.rank == null && !meInList;
  }

  /// The pinned card's row, built from `me`.
  LeaderboardEntry? get myPinnedEntry {
    final r = _result;
    final me = r?.me;
    if (r == null || me?.rank == null) return null;
    final hostel = r.query.isHostelBoard;
    return LeaderboardEntry(
      rank: me!.rank!,
      id: hostel ? (myHostelId ?? '') : uid,
      name: hostel ? (hostelNameOf(myHostelId) ?? 'Your hostel') : (myName ?? 'You'),
      hostelId: myHostelId,
      value: me.value ?? 0,
      isHostel: hostel,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
