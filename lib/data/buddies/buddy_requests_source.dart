import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_exception.dart';
import 'buddy_models.dart';

/// Read-only live view of the signed-in student's PENDING buddy requests.
abstract class BuddyRequestsSource {
  /// Requests sent TO [uid] (`toUid == uid`, status PENDING), newest first.
  Stream<List<BuddyRequest>> watchIncoming(String uid);

  /// Requests sent BY [uid] (`fromUid == uid`, status PENDING), newest first.
  Stream<List<BuddyRequest>> watchOutgoing(String uid);
}

/// Sorts newest first; requests without a (yet resolved) server timestamp
/// are the newest.
List<BuddyRequest> sortRequestsNewestFirst(Iterable<BuddyRequest> requests) {
  final list = requests.toList();
  list.sort((a, b) {
    final x = a.createdAt;
    final y = b.createdAt;
    if (x == null && y == null) return a.id.compareTo(b.id);
    if (x == null) return -1;
    if (y == null) return 1;
    return y.compareTo(x);
  });
  return list;
}

AppException _mapError(Object e) {
  if (e is AppException) return e;
  if (e is FirebaseException) return AppException.fromCallable(code: e.code, message: e.message);
  return AppException.fromCallable(code: 'unavailable');
}

StreamTransformer<T, T> _mapErrors<T>() => StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stack, sink) => sink.addError(_mapError(error), stack),
    );

/// `buddyRequests` reader.
///
/// Both queries are equality-only (`toUid|fromUid == me` and
/// `status == PENDING`), which Firestore serves from its automatic
/// single-field indexes: no composite index is needed because the sort is
/// done on the client.
///
/// The documents are readable by their two participants
/// (`firestore.rules`: `fromUid == auth.uid || toUid == auth.uid`). For
/// OUTGOING requests the recipient's name/photo are read from
/// `publicProfiles/{toUid}` (readable by every eligible student).
class FirestoreBuddyRequestsSource implements BuddyRequestsSource {
  FirestoreBuddyRequestsSource(this._db);

  final FirebaseFirestore _db;
  final Map<String, ({String name, String? photoUrl})> _nameCache = {};

  @override
  Stream<List<BuddyRequest>> watchIncoming(String uid) {
    return _db
        .collection('buddyRequests')
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'PENDING')
        .snapshots()
        .map((snap) {
      final out = <BuddyRequest>[];
      for (final d in snap.docs) {
        final r = BuddyRequest.tryFromMap(d.id, d.data(), myUid: uid);
        if (r != null) out.add(r);
      }
      return sortRequestsNewestFirst(out);
    }).transform(_mapErrors<List<BuddyRequest>>());
  }

  @override
  Stream<List<BuddyRequest>> watchOutgoing(String uid) {
    return _db
        .collection('buddyRequests')
        .where('fromUid', isEqualTo: uid)
        .where('status', isEqualTo: 'PENDING')
        .snapshots()
        .asyncMap((snap) async {
      final raw = [for (final d in snap.docs) (id: d.id, data: d.data())];
      final missing = <String>{
        for (final r in raw)
          if (r.data['toUid'] is String && !_nameCache.containsKey(r.data['toUid'])) r.data['toUid'] as String,
      };
      await Future.wait([for (final other in missing) _loadName(other)]);
      final out = <BuddyRequest>[];
      for (final r in raw) {
        final cached = _nameCache[r.data['toUid']];
        final req = BuddyRequest.tryFromMap(
          r.id,
          r.data,
          myUid: uid,
          otherName: cached?.name,
          otherPhotoUrl: cached?.photoUrl,
        );
        if (req != null) out.add(req);
      }
      return sortRequestsNewestFirst(out);
    }).transform(_mapErrors<List<BuddyRequest>>());
  }

  Future<void> _loadName(String uid) async {
    try {
      final p = await _db.collection('publicProfiles').doc(uid).get();
      final data = p.data();
      final name = data?['displayName'];
      final photo = data?['photoUrl'];
      _nameCache[uid] = (
        name: (name is String && name.trim().isNotEmpty) ? name.trim() : 'Student',
        photoUrl: photo is String ? photo : null,
      );
    } catch (_) {
      // Leave it uncached so the next snapshot retries; the list still shows
      // the request with a generic name.
    }
  }
}
