import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// One accepted buddy, as other features (buddy challenges, step bets, buddy
/// leaderboard) need to see them. Only public-profile data - never e-mail.
class BuddySummary {
  const BuddySummary({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.hostelId,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? hostelId;
}

/// Read-only list of the signed-in user's ACTIVE buddies.
///
/// Shared by the buddies, challenges, bets and leaderboard features so they
/// all agree on who is a buddy. Mutations (request/accept/remove) happen only
/// through the callables, owned by the buddies feature.
abstract class BuddyDirectory {
  Stream<List<BuddySummary>> watchBuddies(String uid);
}

/// Reads `buddyConnections` (participant-readable) and each buddy's
/// `publicProfiles/{uid}` document.
class FirestoreBuddyDirectory implements BuddyDirectory {
  FirestoreBuddyDirectory(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<List<BuddySummary>> watchBuddies(String uid) {
    return _db
        .collection('buddyConnections')
        .where('uids', arrayContains: uid)
        .snapshots()
        .asyncMap((snap) async {
      final otherUids = <String>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['active'] == false) continue; // filter client-side: avoids a composite index
        final uids = (data['uids'] as List?)?.cast<String>() ?? const <String>[];
        for (final u in uids) {
          if (u != uid) otherUids.add(u);
        }
      }
      final out = <BuddySummary>[];
      for (final other in otherUids) {
        final p = await _db.collection('publicProfiles').doc(other).get();
        final data = p.data();
        out.add(BuddySummary(
          uid: other,
          displayName: (data?['displayName'] as String?) ?? 'Student',
          photoUrl: data?['photoUrl'] as String?,
          hostelId: data?['hostelId'] as String?,
        ));
      }
      out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return out;
    });
  }
}

/// Test double: set [buddies] and call [emit].
class FakeBuddyDirectory implements BuddyDirectory {
  FakeBuddyDirectory([List<BuddySummary> initial = const []]) : _current = List.of(initial);

  List<BuddySummary> _current;
  final _controller = StreamController<List<BuddySummary>>.broadcast();

  List<BuddySummary> get buddies => List.unmodifiable(_current);

  void setBuddies(List<BuddySummary> next) {
    _current = List.of(next);
    _controller.add(List.unmodifiable(_current));
  }

  @override
  Stream<List<BuddySummary>> watchBuddies(String uid) async* {
    yield List.unmodifiable(_current);
    yield* _controller.stream;
  }
}
