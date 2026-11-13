import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_exception.dart';
import '../firestore/firebase_firestore_access.dart' show convertFirestoreValue;
import 'bet_models.dart';
import 'bets_repository.dart';

Map<String, dynamic> _data(DocumentSnapshot<Map<String, dynamic>> s) =>
    (convertFirestoreValue(s.data() ?? const {}) as Map).cast<String, dynamic>();

AppException _toApp(Object e) {
  if (e is AppException) return e;
  if (e is FirebaseException) return AppException.fromCallable(code: e.code, message: e.message);
  return AppException.fromCallable(code: 'unavailable');
}

/// Reads `stepBets` (participant-only) and own `virtualPointsLedger`.
///
/// Queries (indexes are in `firestore.indexes.json`):
/// * `stepBets` where `challengerUid == me` order by `createdAt desc`
/// * `stepBets` where `opponentUid == me` order by `createdAt desc`
/// * `virtualPointsLedger` where `uid == me` order by `createdAt desc`
class FirestoreBetsReadSource implements BetsReadSource {
  FirestoreBetsReadSource(this._db, {this.betLimit = 100});

  final FirebaseFirestore _db;
  final int betLimit;

  Stream<List<StepBet>> _side(String field, String uid) => _db
      .collection('stepBets')
      .where(field, isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(betLimit)
      .snapshots()
      .map((q) => [for (final d in q.docs) StepBet.fromMap(d.id, _data(d))]);

  @override
  Stream<List<StepBet>> watchBets(String uid) => mergeBetStreams(
        _side('challengerUid', uid),
        _side('opponentUid', uid),
      ).transform(StreamTransformer.fromHandlers(
        handleError: (e, st, sink) => sink.addError(_toApp(e), st),
      ));

  @override
  Stream<StepBet?> watchBet(String betId) =>
      _db.collection('stepBets').doc(betId).snapshots().map(
            (s) => s.exists ? StepBet.fromMap(s.id, _data(s)) : null,
          ).transform(StreamTransformer.fromHandlers(
            handleError: (e, st, sink) => sink.addError(_toApp(e), st),
          ));

  @override
  Future<LedgerPage> fetchLedger(String uid, {Object? cursor, int limit = 30}) async {
    try {
      var q = _db
          .collection('virtualPointsLedger')
          .where('uid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      if (cursor is DocumentSnapshot) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      return LedgerPage(
        entries: [for (final d in snap.docs) LedgerEntry.fromMap(d.id, _data(d))],
        cursor: snap.docs.isEmpty ? null : snap.docs.last,
        hasMore: snap.docs.length >= limit,
      );
    } catch (e) {
      throw _toApp(e);
    }
  }
}
