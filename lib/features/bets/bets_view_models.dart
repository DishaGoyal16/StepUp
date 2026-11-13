import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/clock.dart';
import '../../data/bets/bet_models.dart';
import '../../data/bets/bets_repository.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../domain/day_key.dart';
import 'bet_errors.dart';
import 'bet_rules.dart';

/// `/bets`: all my bets, split into segments, plus my points.
class BetsListViewModel extends ChangeNotifier {
  BetsListViewModel({required this.uid, required BetsRepository repository})
      : _repo = repository;

  final String uid;
  final BetsRepository _repo;

  StreamSubscription<List<StepBet>>? _betsSub;
  StreamSubscription<PointsBalance>? _pointsSub;

  List<StepBet>? _bets;
  Object? _error;
  BetSegment _segment = BetSegment.active;
  bool _segmentChosen = false;
  PointsBalance? _points;
  bool _disposed = false;

  bool get loading => _bets == null && _error == null;
  bool get hasError => _error != null;
  List<StepBet> get all => _bets ?? const [];
  PointsBalance? get points => _points;
  BetSegment get segment => _segment;

  List<StepBet> get visible => [for (final b in all) if (_segment.contains(b)) b];

  int count(BetSegment s) => all.where(s.contains).length;

  void start() {
    _betsSub?.cancel();
    _pointsSub?.cancel();
    _error = null;
    _bets = null;
    _betsSub = _repo.watchBets(uid).listen((list) {
      _bets = list;
      _error = null;
      if (!_segmentChosen) _segment = _defaultSegment(list);
      _notify();
    }, onError: (Object e) {
      _error = e;
      _notify();
    });
    _pointsSub = _repo.watchPoints(uid).listen((p) {
      _points = p;
      _notify();
    }, onError: (_) {});
    _notify();
  }

  /// First time: show Pending if something awaits an answer, else Active,
  /// else History. After the user picks a segment it is never changed.
  BetSegment _defaultSegment(List<StepBet> list) {
    if (list.any((b) => b.status == BetStatus.pending && b.isOpponent(uid))) {
      return BetSegment.pending;
    }
    if (list.any((b) => b.status == BetStatus.active)) return BetSegment.active;
    if (list.any((b) => b.status == BetStatus.pending)) return BetSegment.pending;
    return list.isEmpty ? BetSegment.active : BetSegment.history;
  }

  void selectSegment(BetSegment s) {
    _segment = s;
    _segmentChosen = true;
    notifyListeners();
  }

  void retry() => start();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _betsSub?.cancel();
    _pointsSub?.cancel();
    super.dispose();
  }
}

/// `/bets/new`.
class CreateBetViewModel extends ChangeNotifier {
  CreateBetViewModel({
    required this.myUid,
    required BetsRepository repository,
    required BuddyDirectory buddies,
    required Clock clock,
    this.presetBuddyUid,
    String Function()? requestIdGenerator,
  })  : _repo = repository,
        _buddies = buddies,
        _clock = clock,
        _newRequestId = requestIdGenerator ?? _randomRequestId {
    _requestId = _newRequestId();
  }

  final String myUid;
  final String? presetBuddyUid;
  final BetsRepository _repo;
  final BuddyDirectory _buddies;
  final Clock _clock;
  final String Function() _newRequestId;
  late String _requestId;

  StreamSubscription<List<BuddySummary>>? _buddiesSub;
  StreamSubscription<PointsBalance>? _pointsSub;

  List<BuddySummary>? _buddyList;
  Object? _buddiesError;
  BuddySummary? _selected;
  bool _presetApplied = false;
  bool _presetMissing = false;
  PointsBalance? _points;

  String _targetText = formatInt(BetLimits.defaultTarget);
  String _stakeText = '${BetLimits.defaultStake}';
  int _days = BetLimits.defaultDays;

  bool _submitting = false;
  bool _attempted = false;
  String? _error;
  bool _disposed = false;

  /// `abc12345-...` style id accepted by the server (`[A-Za-z0-9-]{8,40}`).
  static String _randomRequestId() {
    final r = Random.secure();
    final b = StringBuffer('bet-');
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    for (var i = 0; i < 24; i++) {
      b.write(chars[r.nextInt(chars.length)]);
    }
    return b.toString();
  }

  // --- state for the UI ---
  List<BuddySummary> get buddies => _buddyList ?? const [];
  bool get buddiesLoading => _buddyList == null && _buddiesError == null;
  bool get buddiesFailed => _buddiesError != null;
  BuddySummary? get selected => _selected;

  /// The `?buddy=` uid was given but that student is not an accepted buddy.
  bool get presetMissing => _presetMissing;
  PointsBalance? get points => _points;
  int? get available => _points?.available;

  String get targetText => _targetText;
  String get stakeText => _stakeText;
  int get days => _days;
  int? get target => BetValidator.parseWhole(_targetText);
  int? get stake => BetValidator.parseWhole(_stakeText);

  bool get submitting => _submitting;
  String? get error => _error;
  String get requestId => _requestId;

  // --- validation (shown once the field has text or after a submit attempt) ---
  String? get buddyError =>
      _selected == null && _attempted ? 'Choose the buddy you want to challenge.' : null;
  String? get targetError =>
      (_targetText.trim().isEmpty && !_attempted) ? null : BetValidator.target(target, _days);
  String? get stakeError =>
      (_stakeText.trim().isEmpty && !_attempted) ? null : BetValidator.stake(stake, available);
  String? get durationError => BetValidator.duration(_days);

  bool get isValid =>
      _selected != null &&
      BetValidator.target(target, _days) == null &&
      BetValidator.stake(stake, available) == null &&
      BetValidator.duration(_days) == null;

  bool get canSubmit => isValid && !_submitting;

  // --- preview of what will happen ---
  int? get reservedNow => BetValidator.stake(stake, null) == null ? stake : null;
  int? get availableAfter =>
      (reservedNow != null && available != null) ? available! - reservedNow! : null;

  /// If accepted right now: first day (IST midnight after now) and the last
  /// day of the window.
  ({DateTime start, DateTime end}) get examplePeriod {
    final start = DayKey.startOfDay(_clock.now()).add(const Duration(days: 1));
    return (start: start, end: start.add(Duration(days: _days)));
  }

  String get examplePeriodLabel {
    final p = examplePeriod;
    final first = DayKey.label(DayKey.of(p.start));
    final last = DayKey.label(DayKey.of(p.end.subtract(const Duration(milliseconds: 1))));
    return _days == 1 ? first : '$first to $last';
  }

  void start() {
    _buddiesSub = _buddies.watchBuddies(myUid).listen((list) {
      _buddyList = list;
      _buddiesError = null;
      if (_selected != null) {
        // Keep the selection only while that person is still a buddy.
        final still = list.where((b) => b.uid == _selected!.uid);
        _selected = still.isEmpty ? null : still.first;
      }
      if (!_presetApplied && presetBuddyUid != null) {
        _presetApplied = true;
        final match = list.where((b) => b.uid == presetBuddyUid);
        if (match.isEmpty) {
          _presetMissing = true;
        } else {
          _selected = match.first;
        }
      }
      _notify();
    }, onError: (Object e) {
      _buddiesError = e;
      _notify();
    });
    _pointsSub = _repo.watchPoints(myUid).listen((p) {
      _points = p;
      _notify();
    }, onError: (_) {});
  }

  void selectBuddy(BuddySummary? b) {
    _selected = b;
    _presetMissing = false;
    _inputsChanged();
  }

  void setTargetText(String v) {
    _targetText = v;
    _inputsChanged();
  }

  void setStakeText(String v) {
    _stakeText = v;
    _inputsChanged();
  }

  void setDays(int d) {
    _days = d.clamp(BetLimits.minDays, BetLimits.maxDays);
    _inputsChanged();
  }

  /// Any change of the bet terms invalidates the previous idempotency key.
  void _inputsChanged() {
    _requestId = _newRequestId();
    _error = null;
    _notify();
  }

  /// Sends `createStepBet`. Returns the bet id on success (also when the
  /// server reports that an identical request already created it), `null`
  /// when invalid, already submitting, or failed ([error] is then set).
  Future<String?> submit() async {
    if (_submitting) return null; // no double submit
    _attempted = true;
    if (!isValid) {
      _notify();
      return null;
    }
    _submitting = true;
    _error = null;
    _notify();
    try {
      final created = await _repo.createBet(
        opponentUid: _selected!.uid,
        targetSteps: target!,
        durationDays: _days,
        stakePoints: stake!,
        requestId: _requestId,
      );
      return created.betId;
    } on AppException catch (e) {
      _error = BetErrors.friendly(e);
      return null;
    } catch (_) {
      _error = 'Something went wrong. Please try again.';
      return null;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _buddiesSub?.cancel();
    _pointsSub?.cancel();
    super.dispose();
  }
}

/// `/bets/:id`.
class BetDetailViewModel extends ChangeNotifier {
  BetDetailViewModel({
    required this.betId,
    required this.myUid,
    required BetsRepository repository,
    required Clock clock,
  })  : _repo = repository,
        _clock = clock;

  final String betId;
  final String myUid;
  final BetsRepository _repo;
  final Clock _clock;

  StreamSubscription<StepBet?>? _sub;
  StreamSubscription<PointsBalance>? _pointsSub;

  StepBet? _bet;
  bool _loaded = false;
  Object? _error;
  PointsBalance? _points;
  bool _busy = false;
  String? _actionError;
  bool _disposed = false;

  StepBet? get bet => _bet;
  bool get loading => !_loaded && _error == null;
  bool get notFound => _loaded && _bet == null;
  bool get hasError => _error != null;
  PointsBalance? get points => _points;
  bool get busy => _busy;
  String? get actionError => _actionError;
  DateTime get now => _clock.now();

  bool get isChallenger => _bet?.isChallenger(myUid) ?? false;
  bool get isOpponent => _bet?.isOpponent(myUid) ?? false;
  bool get _pending => _bet?.status == BetStatus.pending;

  bool get canCancel => _pending && isChallenger && !_busy;

  /// Past the 48 h limit (server expires it on the next sweep or on answer).
  bool get inviteExpired {
    final e = _bet?.expiresAt;
    return e != null && !_clock.now().isBefore(e);
  }

  /// Opponent may answer a pending, not yet expired bet.
  bool get canRespond => _pending && isOpponent && !_busy && !inviteExpired;

  /// Known to be too few available points to accept (null = unknown).
  bool get insufficientToAccept {
    final p = _points;
    final b = _bet;
    return p != null && b != null && p.available < b.stakePoints;
  }

  bool get canAccept => canRespond && !insufficientToAccept;

  void start() {
    _sub?.cancel();
    _pointsSub?.cancel();
    _error = null;
    _loaded = false;
    _sub = _repo.watchBet(betId).listen((b) {
      _bet = b;
      _loaded = true;
      _error = null;
      _notify();
    }, onError: (Object e) {
      _error = e;
      _notify();
    });
    _pointsSub = _repo.watchPoints(myUid).listen((p) {
      _points = p;
      _notify();
    }, onError: (_) {});
    _notify();
  }

  Future<bool> accept() => _act(() => _repo.respond(betId, accept: true));
  Future<bool> decline() => _act(() => _repo.respond(betId, accept: false));
  Future<bool> cancel() => _act(() => _repo.cancel(betId));

  void clearActionError() {
    _actionError = null;
    _notify();
  }

  Future<bool> _act(Future<void> Function() call) async {
    if (_busy) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      await call();
      return true;
    } on AppException catch (e) {
      _actionError = BetErrors.friendly(e);
      return false;
    } catch (_) {
      _actionError = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _pointsSub?.cancel();
    super.dispose();
  }
}

/// `/bets/ledger`: balance and a paginated list of own ledger entries.
class LedgerViewModel extends ChangeNotifier {
  LedgerViewModel({required this.uid, required BetsRepository repository, this.pageSize = 30})
      : _repo = repository;

  final String uid;
  final int pageSize;
  final BetsRepository _repo;

  StreamSubscription<PointsBalance>? _pointsSub;
  final List<LedgerEntry> _entries = [];
  Object? _cursor;
  bool _hasMore = false;
  bool _loadingFirst = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;
  PointsBalance? _points;
  int _generation = 0;
  bool _disposed = false;

  List<LedgerEntry> get entries => List.unmodifiable(_entries);
  bool get loadingFirst => _loadingFirst;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  String? get moreError => _moreError;
  PointsBalance? get points => _points;
  bool get isEmpty => !_loadingFirst && _error == null && _entries.isEmpty;

  void start() {
    _pointsSub?.cancel();
    _pointsSub = _repo.watchPoints(uid).listen((p) {
      _points = p;
      _notify();
    }, onError: (_) {});
    unawaited(refresh());
  }

  /// Reloads from the first page.
  Future<void> refresh() async {
    final gen = ++_generation;
    _loadingFirst = true;
    _error = null;
    _moreError = null;
    _notify();
    try {
      final page = await _repo.fetchLedger(uid, limit: pageSize);
      if (gen != _generation) return;
      _entries
        ..clear()
        ..addAll(page.entries);
      _cursor = page.cursor;
      _hasMore = page.hasMore;
    } on AppException catch (e) {
      if (gen != _generation) return;
      _error = e.message;
    } catch (_) {
      if (gen != _generation) return;
      _error = 'Could not load your points history.';
    } finally {
      if (gen == _generation) {
        _loadingFirst = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loadingFirst || !_hasMore) return;
    final gen = _generation;
    _loadingMore = true;
    _moreError = null;
    _notify();
    try {
      final page = await _repo.fetchLedger(uid, cursor: _cursor, limit: pageSize);
      if (gen != _generation) return;
      final known = {for (final e in _entries) e.id};
      _entries.addAll(page.entries.where((e) => !known.contains(e.id)));
      _cursor = page.cursor;
      _hasMore = page.hasMore;
    } on AppException catch (e) {
      if (gen != _generation) return;
      _moreError = e.message;
    } catch (_) {
      if (gen != _generation) return;
      _moreError = 'Could not load more entries.';
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pointsSub?.cancel();
    super.dispose();
  }
}
