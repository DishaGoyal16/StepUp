import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore/firebase_firestore_access.dart' show convertFirestoreValue;
import 'challenge_models.dart';
import 'challenge_reader.dart';

Map<String, dynamic> _data(DocumentSnapshot<Map<String, dynamic>> s) =>
    (convertFirestoreValue(s.data() ?? const <String, dynamic>{}) as Map).cast<String, dynamic>();

/// Cloud Firestore implementation of [ChallengeReader]. Reads only.
///
/// Queries are written so that they need NO composite index (equality / `in`
/// filters only, sorting happens on the client) and so that the security rules
/// can prove every returned document is readable:
/// * `challenges` is always filtered by an equality on `type` (never BUDDY);
/// * `challengeParticipants` is always filtered by `uid == me`.
class FirestoreChallengeReader implements ChallengeReader {
  FirestoreChallengeReader(this._db);

  final FirebaseFirestore _db;

  static const List<String> _openStatuses = ['UPCOMING', 'ACTIVE'];

  CollectionReference<Map<String, dynamic>> get _challenges => _db.collection('challenges');
  CollectionReference<Map<String, dynamic>> get _participants => _db.collection('challengeParticipants');

  @override
  Future<List<Challenge>> fetchOpenChallenges(ChallengeType type) async {
    assert(type != ChallengeType.buddy, 'BUDDY challenges are not listable');
    try {
      // INDIVIDUAL includes the catalogue templates AND admin-created individual challenges (isTemplate=false);
      // the only other non-template challenges are BUDDY ones, which are a different type and never listed here.
      final Query<Map<String, dynamic>> q =
          _challenges.where('type', isEqualTo: type.wire).where('status', whereIn: _openStatuses);
      final snap = await q.get();
      return [
        for (final d in snap.docs)
          ?Challenge.tryFromMap(d.id, _data(d)),
      ];
    } catch (e) {
      throw mapReadError(e);
    }
  }

  @override
  Future<List<ChallengeParticipation>> fetchMyParticipations(String uid) async {
    try {
      final snap = await _participants.where('uid', isEqualTo: uid).get();
      return [
        for (final d in snap.docs)
          ?ChallengeParticipation.tryFromMap(_data(d)),
      ];
    } catch (e) {
      throw mapReadError(e);
    }
  }

  @override
  Stream<List<ChallengeParticipation>> watchMyParticipations(String uid) => _participants
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snap) => [
            for (final d in snap.docs)
              ?ChallengeParticipation.tryFromMap(_data(d)),
          ])
      .transform(mapStreamErrors<List<ChallengeParticipation>>());

  @override
  Stream<ChallengeParticipation?> watchParticipation(String challengeId, String uid) => _participants
      .doc('${challengeId}_$uid')
      .snapshots()
      .map((s) => s.exists ? ChallengeParticipation.tryFromMap(_data(s)) : null)
      .transform(mapStreamErrors<ChallengeParticipation?>());

  @override
  Future<Challenge?> fetchChallenge(String id) async {
    try {
      final s = await _challenges.doc(id).get();
      if (!s.exists) return null;
      return Challenge.tryFromMap(s.id, _data(s));
    } catch (e) {
      throw mapReadError(e);
    }
  }

  @override
  Future<List<Challenge>> fetchChallenges(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return const [];
    try {
      final snaps = await Future.wait([for (final id in unique) _challenges.doc(id).get()]);
      return [
        for (final s in snaps)
          if (s.exists) ?Challenge.tryFromMap(s.id, _data(s)),
      ];
    } catch (e) {
      throw mapReadError(e);
    }
  }

  @override
  Future<ChallengeResult?> fetchResult(String challengeId) async {
    try {
      final s = await _db.collection('challengeResults').doc(challengeId).get();
      if (!s.exists) return null;
      return ChallengeResult.tryFromMap(s.id, _data(s));
    } catch (e) {
      throw mapReadError(e);
    }
  }
}
