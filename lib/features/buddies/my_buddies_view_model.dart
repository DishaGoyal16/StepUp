import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/buddies/buddies_repository.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../data/buddies/buddy_models.dart';
import '../../domain/hostel.dart';
import 'buddy_action_result.dart';

/// State of the "My buddies" tab: the live list of accepted buddies
/// (`BuddyDirectory`) and the remove / report actions.
class MyBuddiesViewModel extends ChangeNotifier {
  MyBuddiesViewModel({
    required BuddiesRepository repository,
    required this.uid,
    Future<HostelDirectory> Function()? loadHostels,
  })  : _repo = repository,
        _loadHostels = loadHostels;

  final BuddiesRepository _repo;
  final String uid;
  final Future<HostelDirectory> Function()? _loadHostels;

  StreamSubscription<List<BuddySummary>>? _sub;
  List<BuddySummary>? _buddies;
  AppException? _error;
  HostelDirectory? _hostels;
  final Set<String> _busy = {};
  bool _disposed = false;

  /// Null until the first snapshot arrives.
  List<BuddySummary>? get buddies => _buddies;
  AppException? get error => _error;
  bool isBusy(String uid) => _busy.contains(uid);

  /// Display name of [hostelId] (null when not shared, not loaded yet or unknown).
  String? hostelName(String? hostelId) {
    if (hostelId == null) return null;
    return _hostels?.byId(hostelId)?.displayName;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void start() {
    _sub?.cancel();
    _error = null;
    _sub = _repo.watchBuddies(uid).listen(
      (list) {
        _buddies = list;
        _error = null;
        _notify();
      },
      onError: (Object e) {
        _error = e is AppException ? e : AppException.fromCallable(code: 'unavailable');
        _notify();
      },
    );
    final load = _loadHostels;
    if (load != null) {
      unawaited(load().then((h) {
        _hostels = h;
        _notify();
      }).catchError((Object _) {}));
    }
  }

  void retry() {
    _buddies = null;
    _notify();
    start();
  }

  Future<BuddyActionResult> _run(String buddyUid, Future<BuddyActionResult> Function() body) async {
    if (_busy.contains(buddyUid)) {
      return const BuddyActionResult.failure('Please wait, still working on that.');
    }
    _busy.add(buddyUid);
    _notify();
    try {
      return await body();
    } on AppException catch (e) {
      return buddyFailure(e);
    } catch (_) {
      return buddyFailure(AppException.fromCallable(code: 'unavailable'));
    } finally {
      _busy.remove(buddyUid);
      _notify();
    }
  }

  Future<BuddyActionResult> remove(BuddySummary b) {
    return _run(b.uid, () async {
      await _repo.removeBuddy(b.uid);
      _buddies = _buddies?.where((x) => x.uid != b.uid).toList();
      return BuddyActionResult.success('${b.displayName} was removed from your buddies.');
    });
  }

  Future<BuddyActionResult> report(BuddySummary b, ReportReason reason, {String? details}) {
    return _run(b.uid, () async {
      await _repo.report(b.uid, reason, details: details);
      return BuddyActionResult.success('Thanks, your report was sent to the StepUp team.');
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
