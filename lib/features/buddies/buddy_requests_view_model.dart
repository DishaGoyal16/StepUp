import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/buddies/buddies_repository.dart';
import '../../data/buddies/buddy_models.dart';
import 'buddy_action_result.dart';

AppException _toAppException(Object e) =>
    e is AppException ? e : AppException.fromCallable(code: 'unavailable');

/// Live PENDING requests count shown on the "Requests" button of the buddies
/// header. Provided by the buddies screen (`Provider<BuddyRequestsCount>`).
class BuddyRequestsCount extends ChangeNotifier {
  BuddyRequestsCount({required BuddiesRepository repository, required this.uid})
      : _repo = repository;

  final BuddiesRepository _repo;
  final String uid;
  StreamSubscription<List<BuddyRequest>>? _sub;
  int _count = 0;
  bool _failed = false;
  bool _disposed = false;

  /// Pending requests waiting for the signed-in student's answer.
  int get count => _count;

  /// True when the count could not be read (the badge is then hidden).
  bool get failed => _failed;

  void start() {
    _sub?.cancel();
    _sub = _repo.watchIncoming(uid).listen(
      (list) {
        _count = list.length;
        _failed = false;
        if (!_disposed) notifyListeners();
      },
      onError: (Object _) {
        _failed = true;
        _count = 0;
        if (!_disposed) notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}

/// State of the Requests screen: Incoming / Outgoing lists (live) and their
/// actions.
class BuddyRequestsViewModel extends ChangeNotifier {
  BuddyRequestsViewModel({required BuddiesRepository repository, required this.uid})
      : _repo = repository;

  final BuddiesRepository _repo;
  final String uid;

  StreamSubscription<List<BuddyRequest>>? _inSub;
  StreamSubscription<List<BuddyRequest>>? _outSub;
  List<BuddyRequest>? _incoming;
  List<BuddyRequest>? _outgoing;
  AppException? _incomingError;
  AppException? _outgoingError;
  final Set<String> _busy = {};
  final Set<String> _handled = {};
  bool _disposed = false;

  /// Null until the first snapshot arrives.
  List<BuddyRequest>? get incoming => _incoming;
  List<BuddyRequest>? get outgoing => _outgoing;
  AppException? get incomingError => _incomingError;
  AppException? get outgoingError => _outgoingError;
  bool isBusy(String requestId) => _busy.contains(requestId);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void start() {
    _inSub?.cancel();
    _outSub?.cancel();
    _incomingError = null;
    _outgoingError = null;
    _inSub = _repo.watchIncoming(uid).listen(
      (list) {
        _incoming = _visible(list);
        _incomingError = null;
        _notify();
      },
      onError: (Object e) {
        _incomingError = _toAppException(e);
        _notify();
      },
    );
    _outSub = _repo.watchOutgoing(uid).listen(
      (list) {
        _outgoing = _visible(list);
        _outgoingError = null;
        _notify();
      },
      onError: (Object e) {
        _outgoingError = _toAppException(e);
        _notify();
      },
    );
  }

  /// Re-subscribes (after an error).
  void retry() {
    _incoming = null;
    _outgoing = null;
    _notify();
    start();
  }

  /// Hides requests this screen already answered, until the server list
  /// stops containing them.
  List<BuddyRequest> _visible(List<BuddyRequest> list) {
    _handled.removeWhere((id) => !list.any((r) => r.id == id));
    return [for (final r in list) if (!_handled.contains(r.id)) r];
  }

  Future<BuddyActionResult> _run(
    BuddyRequest r,
    Future<BuddyActionResult> Function() body,
  ) async {
    if (_busy.contains(r.id)) {
      return const BuddyActionResult.failure('Please wait, still working on that.');
    }
    _busy.add(r.id);
    _notify();
    try {
      return await body();
    } on AppException catch (e) {
      return buddyFailure(e);
    } catch (_) {
      return buddyFailure(AppException.fromCallable(code: 'unavailable'));
    } finally {
      _busy.remove(r.id);
      _notify();
    }
  }

  void _hide(BuddyRequest r) {
    _handled.add(r.id);
    _incoming = _incoming?.where((x) => x.id != r.id).toList();
    _outgoing = _outgoing?.where((x) => x.id != r.id).toList();
  }

  Future<BuddyActionResult> accept(BuddyRequest r) => _respond(r, true);
  Future<BuddyActionResult> reject(BuddyRequest r) => _respond(r, false);

  Future<BuddyActionResult> _respond(BuddyRequest r, bool accept) {
    return _run(r, () async {
      await _repo.respond(r.id, accept: accept);
      _hide(r);
      return BuddyActionResult.success(
        accept
            ? 'You and ${r.otherName} are now buddies.'
            : 'Request from ${r.otherName} rejected.',
      );
    });
  }

  Future<BuddyActionResult> cancel(BuddyRequest r) {
    return _run(r, () async {
      await _repo.cancel(r.id);
      _hide(r);
      return BuddyActionResult.success('Request to ${r.otherName} cancelled.');
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _inSub?.cancel();
    _outSub?.cancel();
    super.dispose();
  }
}
