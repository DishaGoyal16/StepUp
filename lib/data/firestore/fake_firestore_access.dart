import 'dart:async';

import '../../domain/daily_step_summary.dart';
import '../../domain/hostel.dart';
import '../../domain/user_profile.dart';
import 'firestore_access.dart';

/// A value that replays its latest state to every new listener.
class ReplayValue<T> {
  ReplayValue(this._value);

  T _value;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    _controller.add(v);
  }

  Stream<T> get stream => Stream<T>.multi((c) {
        c.add(_value);
        final sub = _controller.stream.listen(c.add, onError: c.addError);
        c.onCancel = sub.cancel;
      }, isBroadcast: true);
}

/// In-memory [FirestoreAccess] for tests and `AppDependencies.fake()`.
class FakeFirestoreAccess implements FirestoreAccess {
  FakeFirestoreAccess({
    UserProfile? profile,
    List<DailyStepSummary> summaries = const [],
    List<Hostel>? hostels,
    int unread = 0,
  })  : _profile = ReplayValue(profile),
        _summaries = ReplayValue(summaries),
        _unread = ReplayValue(unread),
        _hostels = hostels;

  final ReplayValue<UserProfile?> _profile;
  final ReplayValue<List<DailyStepSummary>> _summaries;
  final ReplayValue<int> _unread;
  List<Hostel>? _hostels;

  /// When true [fetchActiveHostels] throws (simulates offline).
  bool hostelsOffline = false;

  void setProfile(UserProfile? p) => _profile.value = p;
  void setSummaries(List<DailyStepSummary> s) => _summaries.value = s;
  void setUnread(int n) => _unread.value = n;
  void setHostels(List<Hostel>? h) => _hostels = h;

  @override
  Stream<UserProfile?> watchUserProfile(String uid) => _profile.stream;

  @override
  Stream<List<DailyStepSummary>> watchDailySummaries(String uid, {int limit = 30}) =>
      _summaries.stream.map((l) => l.take(limit).toList());

  @override
  Future<List<Hostel>> fetchActiveHostels() async {
    if (hostelsOffline || _hostels == null) {
      throw StateError('hostels unavailable');
    }
    return _hostels!;
  }

  @override
  Stream<int> watchUnreadNotificationCount(String uid) => _unread.stream;
}
