import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../functions/functions_client.dart';
import 'buddy_directory.dart';
import 'buddy_models.dart';
import 'buddy_requests_source.dart';

/// Everything the buddies feature needs from the backend. UI code only sees
/// this interface; failures are always [AppException].
abstract class BuddiesRepository {
  /// `searchBuddies`: one page of discoverable students (never includes the
  /// caller). Pass the previous page's `nextCursor` to continue.
  Future<BuddySearchPage> search(BuddyFilters filters, {String? cursor, int limit = 20});

  /// `sendBuddyRequest`. Returns the new request id when the server sent it.
  Future<String?> sendRequest(String toUid, {String? message});

  /// `respondBuddyRequest` (recipient only).
  Future<void> respond(String requestId, {required bool accept});

  /// `cancelBuddyRequest` (sender only).
  Future<void> cancel(String requestId);

  /// `removeBuddy`.
  Future<void> removeBuddy(String buddyUid);

  /// `reportProfile`.
  Future<void> report(String targetUid, ReportReason reason, {String? details});

  /// Live PENDING requests addressed to [uid].
  Stream<List<BuddyRequest>> watchIncoming(String uid);

  /// Live PENDING requests sent by [uid].
  Stream<List<BuddyRequest>> watchOutgoing(String uid);

  /// Live list of [uid]'s active buddies (shared `BuddyDirectory`).
  Stream<List<BuddySummary>> watchBuddies(String uid);

  /// Number of active buddies, or null when it cannot be read (offline,
  /// denied...). Feeds the Home "buddies" figure.
  Future<int?> activeBuddyCount(String uid);
}

/// Production implementation: every write is a callable
/// ([FunctionsClient.call]); reads come from the injected Firestore sources.
class CallableBuddiesRepository implements BuddiesRepository {
  CallableBuddiesRepository({
    required FunctionsClient functions,
    required BuddyRequestsSource requests,
    required BuddyDirectory directory,
    this.countTimeout = const Duration(seconds: 8),
  })  : _functions = functions,
        _requests = requests,
        _directory = directory;

  final FunctionsClient _functions;
  final BuddyRequestsSource _requests;
  final BuddyDirectory _directory;
  final Duration countTimeout;

  /// Runs [body] turning every non-[AppException] failure into one.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AppException {
      rethrow;
    } catch (_) {
      throw AppException.fromCallable(code: 'unavailable');
    }
  }

  @override
  Future<BuddySearchPage> search(BuddyFilters filters, {String? cursor, int limit = 20}) {
    return _guard(() async {
      final r = await _functions.call(
        'searchBuddies',
        filters.toParams(limit: limit, cursor: cursor),
      );
      final raw = r['profiles'];
      final profiles = <BuddyProfile>[];
      if (raw is List) {
        for (final p in raw) {
          if (p is Map) {
            final parsed = BuddyProfile.tryFromMap(Map<String, dynamic>.from(p));
            if (parsed != null) profiles.add(parsed);
          }
        }
      }
      final next = r['nextCursor'];
      return BuddySearchPage(
        profiles: profiles,
        nextCursor: (next is String && next.isNotEmpty) ? next : null,
      );
    });
  }

  @override
  Future<String?> sendRequest(String toUid, {String? message}) {
    return _guard(() async {
      final text = message?.trim();
      final r = await _functions.call('sendBuddyRequest', {
        'toUid': toUid,
        if (text != null && text.isNotEmpty) 'message': text,
      });
      final id = r['requestId'];
      return id is String && id.isNotEmpty ? id : null;
    });
  }

  @override
  Future<void> respond(String requestId, {required bool accept}) {
    return _guard(() async {
      await _functions.call('respondBuddyRequest', {'requestId': requestId, 'accept': accept});
    });
  }

  @override
  Future<void> cancel(String requestId) {
    return _guard(() async {
      await _functions.call('cancelBuddyRequest', {'requestId': requestId});
    });
  }

  @override
  Future<void> removeBuddy(String buddyUid) {
    return _guard(() async {
      await _functions.call('removeBuddy', {'buddyUid': buddyUid});
    });
  }

  @override
  Future<void> report(String targetUid, ReportReason reason, {String? details}) {
    return _guard(() async {
      final text = details?.trim();
      await _functions.call('reportProfile', {
        'targetUid': targetUid,
        'reason': reason.wire,
        if (text != null && text.isNotEmpty) 'details': text,
      });
    });
  }

  @override
  Stream<List<BuddyRequest>> watchIncoming(String uid) => _requests.watchIncoming(uid);

  @override
  Stream<List<BuddyRequest>> watchOutgoing(String uid) => _requests.watchOutgoing(uid);

  @override
  Stream<List<BuddySummary>> watchBuddies(String uid) => _directory.watchBuddies(uid);

  @override
  Future<int?> activeBuddyCount(String uid) async {
    try {
      final list = await _directory.watchBuddies(uid).first.timeout(countTimeout);
      return list.length;
    } catch (_) {
      return null;
    }
  }
}
