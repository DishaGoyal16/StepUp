import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/buddies/buddies_repository.dart';
import '../../data/buddies/buddy_models.dart';
import '../../domain/hostel.dart';
import 'buddy_action_result.dart';

enum FinderStatus { idle, loading, ready, error }

/// State of the "Find buddies" tab: filters, debounced search, cursor
/// pagination and the per-student actions (request / cancel / accept /
/// reject / remove).
class BuddyFinderViewModel extends ChangeNotifier {
  BuddyFinderViewModel({
    required BuddiesRepository repository,
    required this.uid,
    Future<HostelDirectory> Function()? loadHostels,
    this.debounce = const Duration(milliseconds: 400),
    this.pageSize = 20,
  })  : _repo = repository,
        _loadHostels = loadHostels;

  final BuddiesRepository _repo;
  final String uid;
  final Future<HostelDirectory> Function()? _loadHostels;
  final Duration debounce;
  final int pageSize;

  BuddyFilters _filters = BuddyFilters.empty;
  List<BuddyProfile> _profiles = const [];
  FinderStatus _status = FinderStatus.idle;
  AppException? _error;
  bool _loadingMore = false;
  AppException? _loadMoreError;
  String? _nextCursor;
  HostelDirectory? _hostels;
  final Set<String> _busy = {};
  Timer? _debounceTimer;
  int _generation = 0;
  bool _disposed = false;

  BuddyFilters get filters => _filters;
  List<BuddyProfile> get profiles => _profiles;
  FinderStatus get status => _status;
  AppException? get error => _error;
  bool get loadingMore => _loadingMore;
  AppException? get loadMoreError => _loadMoreError;
  bool get hasMore => _nextCursor != null;
  HostelDirectory? get hostels => _hostels;

  /// True while an action on [uid] is in flight.
  bool isBusy(String uid) => _busy.contains(uid);

  BuddyProfile? profileById(String uid) {
    for (final p in _profiles) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  /// Display name of [hostelId] (null when not shared, not loaded yet or
  /// unknown: a raw hostel slug is never shown).
  String? hostelName(String? hostelId) {
    if (hostelId == null) return null;
    return _hostels?.byId(hostelId)?.displayName;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the hostel list (for the filter and the cards) and the first page.
  Future<void> start() async {
    unawaited(_loadHostelList());
    await _runSearch();
  }

  Future<void> _loadHostelList() async {
    final load = _loadHostels;
    if (load == null) return;
    try {
      _hostels = await load();
      _notify();
    } catch (_) {
      // Hostel names are cosmetic; the filter just offers fewer options.
    }
  }

  /// Text box changed: the search runs after [debounce] without typing.
  void setQuery(String text) {
    final next = text.length > BuddyFilters.maxQueryLength
        ? text.substring(0, BuddyFilters.maxQueryLength)
        : text;
    if (next.trim() == _filters.query.trim()) {
      _filters = _filters.copyWith(query: next);
      return;
    }
    _filters = _filters.copyWith(query: next);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(_runSearch()));
  }

  /// Applies the filters of the filter sheet (the text query is kept).
  Future<void> applyFilters(BuddyFilters next) {
    _debounceTimer?.cancel();
    _filters = next.copyWith(query: _filters.query);
    return _runSearch();
  }

  /// Removes every non-text filter.
  Future<void> clearFilters() => applyFilters(BuddyFilters.empty);

  /// Re-runs the current search from the first page.
  Future<void> refresh() {
    _debounceTimer?.cancel();
    return _runSearch(silent: _status == FinderStatus.ready);
  }

  /// Retry after an initial-load error.
  Future<void> retry() => refresh();

  Future<void> _runSearch({bool silent = false}) async {
    final gen = ++_generation;
    _loadingMore = false;
    _loadMoreError = null;
    if (!silent) {
      _status = FinderStatus.loading;
      _error = null;
      _notify();
    }
    try {
      final page = await _repo.search(_filters, limit: pageSize);
      if (gen != _generation || _disposed) return;
      _profiles = page.profiles;
      _nextCursor = page.nextCursor;
      _status = FinderStatus.ready;
      _error = null;
    } on AppException catch (e) {
      if (gen != _generation || _disposed) return;
      if (silent) {
        // Keep what is on screen; the list is only slightly stale.
        _notify();
        return;
      }
      _status = FinderStatus.error;
      _error = e;
    } catch (_) {
      if (gen != _generation || _disposed) return;
      if (silent) return;
      _status = FinderStatus.error;
      _error = AppException.fromCallable(code: 'unavailable');
    }
    _notify();
  }

  /// Loads the next page (no-op while loading or when nothing is left).
  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore || _status != FinderStatus.ready) return;
    final gen = _generation;
    _loadingMore = true;
    _loadMoreError = null;
    _notify();
    try {
      final page = await _repo.search(_filters, cursor: cursor, limit: pageSize);
      if (gen != _generation || _disposed) return;
      final known = {for (final p in _profiles) p.uid};
      _profiles = [..._profiles, ...page.profiles.where((p) => !known.contains(p.uid))];
      _nextCursor = page.nextCursor;
    } on AppException catch (e) {
      if (gen != _generation || _disposed) return;
      _loadMoreError = e;
    } catch (_) {
      if (gen != _generation || _disposed) return;
      _loadMoreError = AppException.fromCallable(code: 'unavailable');
    } finally {
      if (gen == _generation) _loadingMore = false;
    }
    _notify();
  }

  // ---- actions ------------------------------------------------------------

  void _replace(BuddyProfile next) {
    _profiles = [for (final p in _profiles) p.uid == next.uid ? next : p];
  }

  Future<BuddyActionResult> _run(
    String targetUid,
    Future<BuddyActionResult> Function() body,
  ) async {
    if (_busy.contains(targetUid)) {
      return const BuddyActionResult.failure('Please wait, still working on that.');
    }
    _busy.add(targetUid);
    _notify();
    try {
      final result = await body();
      return result;
    } on AppException catch (e) {
      final r = buddyFailure(e);
      if (r.needsRefresh) unawaited(refresh());
      return r;
    } catch (_) {
      return buddyFailure(AppException.fromCallable(code: 'unavailable'));
    } finally {
      _busy.remove(targetUid);
      _notify();
    }
  }

  /// Sends a request (optional short [message]).
  Future<BuddyActionResult> sendRequest(BuddyProfile p, {String? message}) {
    return _run(p.uid, () async {
      final id = await _repo.sendRequest(p.uid, message: message);
      _replace(p.withRelation(BuddyRelation.requestSent, requestId: id ?? '${uid}_${p.uid}'));
      return BuddyActionResult.success('Buddy request sent to ${p.displayName}.');
    });
  }

  /// Cancels the request this student received from us.
  Future<BuddyActionResult> cancelRequest(BuddyProfile p) {
    return _run(p.uid, () async {
      final id = p.pendingRequestId(uid);
      if (id == null) {
        return const BuddyActionResult.failure('This request is no longer pending.');
      }
      await _repo.cancel(id);
      _replace(p.withRelation(BuddyRelation.none));
      return BuddyActionResult.success('Request to ${p.displayName} cancelled.');
    });
  }

  /// Accepts or rejects the request this student sent us.
  Future<BuddyActionResult> respond(BuddyProfile p, {required bool accept}) {
    return _run(p.uid, () async {
      final id = p.pendingRequestId(uid);
      if (id == null) {
        return const BuddyActionResult.failure('This request is no longer pending.');
      }
      await _repo.respond(id, accept: accept);
      _replace(p.withRelation(accept ? BuddyRelation.buddy : BuddyRelation.none));
      return BuddyActionResult.success(
        accept ? 'You and ${p.displayName} are now buddies.' : 'Request from ${p.displayName} rejected.',
      );
    });
  }

  Future<BuddyActionResult> removeBuddy(BuddyProfile p) {
    return _run(p.uid, () async {
      await _repo.removeBuddy(p.uid);
      _replace(p.withRelation(BuddyRelation.none));
      return BuddyActionResult.success('${p.displayName} was removed from your buddies.');
    });
  }

  Future<BuddyActionResult> report(BuddyProfile p, ReportReason reason, {String? details}) {
    return _run(p.uid, () async {
      await _repo.report(p.uid, reason, details: details);
      return BuddyActionResult.success('Thanks, your report was sent to the StepUp team.');
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
