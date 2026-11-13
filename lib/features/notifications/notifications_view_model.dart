import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/functions/callables.dart';
import '../../data/notifications_center/app_notification.dart';
import '../../data/notifications_center/notifications_reader.dart';

/// State of the notifications screen: a live, growing window of the user's
/// newest notifications plus "mark read" actions (server-side through
/// `markNotificationsRead`; notifications can never be deleted by the client).
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel({
    required this.uid,
    required NotificationsReader reader,
    required Callables callables,
    this.pageSize = 20,
  })  : _reader = reader,
        _callables = callables,
        _limit = pageSize;

  final String uid;
  final int pageSize;
  final NotificationsReader _reader;
  final Callables _callables;

  StreamSubscription<List<AppNotification>>? _sub;
  List<AppNotification> _raw = const [];
  final Set<String> _optimisticRead = {};
  int _limit;
  bool _loading = true;
  bool _loadingMore = false;
  bool _disposed = false;
  bool _marking = false;
  Object? _error;
  String? _actionError;

  /// Newest first, with locally pending "read" marks applied.
  List<AppNotification> get items => [
        for (final n in _raw) _optimisticRead.contains(n.id) && !n.read ? n.copyWith(read: true) : n,
      ];

  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get marking => _marking;
  bool get failed => _error != null && _raw.isEmpty;

  /// A full window came back, so there may be older notifications.
  bool get hasMore => _raw.length >= _limit;

  int get unreadCount => items.where((n) => !n.read).length;

  /// One-shot error text from the last action (cleared when read).
  String? takeActionError() {
    final e = _actionError;
    _actionError = null;
    return e;
  }

  void start() => _subscribe();

  void _subscribe() {
    _sub?.cancel();
    _sub = _reader.watchLatest(uid, limit: _limit).listen(
      (list) {
        _raw = list;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _notify();
      },
      onError: (Object e) {
        _loading = false;
        _loadingMore = false;
        _error = e;
        _notify();
      },
    );
  }

  /// Re-tries after a load error.
  void retry() {
    _error = null;
    _loading = true;
    _notify();
    _subscribe();
  }

  /// Shows the next page (grows the live window by [pageSize]).
  void loadMore() {
    if (_loadingMore || !hasMore) return;
    _loadingMore = true;
    _limit += pageSize;
    _notify();
    _subscribe();
  }

  /// Marks one notification read. Optimistic; reverted (with an error
  /// message) when the server call fails.
  Future<void> markRead(String id) async {
    final target = items.where((n) => n.id == id);
    if (target.isEmpty || target.first.read) return;
    _optimisticRead.add(id);
    _notify();
    try {
      await _callables.markNotificationsRead([id]);
    } catch (e) {
      _optimisticRead.remove(id);
      _actionError = _messageOf(e, 'Could not mark it as read.');
      _notify();
    }
  }

  /// Marks every notification read (also those beyond the loaded page).
  Future<void> markAllRead() async {
    if (_marking || unreadCount == 0) return;
    final ids = [for (final n in items) if (!n.read) n.id];
    _marking = true;
    _optimisticRead.addAll(ids);
    _notify();
    try {
      await _callables.markNotificationsRead();
    } catch (e) {
      _optimisticRead.removeAll(ids);
      _actionError = _messageOf(e, 'Could not mark all as read.');
    } finally {
      _marking = false;
      _notify();
    }
  }

  static String _messageOf(Object e, String fallback) => e is AppException ? e.message : fallback;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
