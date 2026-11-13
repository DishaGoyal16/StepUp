import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore/firebase_firestore_access.dart' show convertFirestoreValue;
import 'badges.dart';
import 'extras_models.dart';

/// Read-only data for the profile screen that the foundation does not cover.
/// Every method only reads documents the Firestore rules allow:
/// `adminSettings/badges`, own `achievements`, own `challengeParticipants`,
/// `challenges/{id}` and own `virtualPointsLedger`.
abstract class ProfileExtrasReader {
  /// The merged badge catalogue (known badges overlaid by
  /// `adminSettings/badges`). If the document is unreachable the caller gets
  /// the built-in layout of the six known badges via [buildBadgeCatalogue].
  Future<List<BadgeDefinition>> fetchBadgeCatalogue();

  /// Own `achievements` (server-written; the client never creates them).
  Stream<List<Achievement>> watchAchievements(String uid);

  /// Own completed challenges, newest first, with their titles.
  Stream<List<CompletedChallenge>> watchCompletedChallenges(String uid, {int limit = 20});

  /// The latest [limit] own points-ledger entries (newest first).
  Future<List<LedgerEntry>> fetchRecentLedger(String uid, {int limit = 3});
}

Map<String, dynamic> _map(Object? data) =>
    (convertFirestoreValue(data ?? const <String, dynamic>{}) as Map).cast<String, dynamic>();

class FirestoreProfileExtrasReader implements ProfileExtrasReader {
  FirestoreProfileExtrasReader(this._db);

  final FirebaseFirestore _db;

  /// challengeId -> (title, type); a challenge title never changes in a way
  /// that matters here, so each document is read once per session.
  final Map<String, ({String title, String? type})> _challengeCache = {};

  @override
  Future<List<BadgeDefinition>> fetchBadgeCatalogue() async {
    final snap = await _db.collection('adminSettings').doc('badges').get();
    return buildBadgeCatalogue(snap.exists ? _map(snap.data()) : null);
  }

  @override
  Stream<List<Achievement>> watchAchievements(String uid) {
    return _db
        .collection('achievements')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((q) => [for (final d in q.docs) Achievement.fromMap(_map(d.data()))]);
  }

  @override
  Stream<List<CompletedChallenge>> watchCompletedChallenges(String uid, {int limit = 20}) {
    // Two equality filters: served by the automatic single-field indexes, no
    // composite index needed. Sorted client-side by completion time.
    return _db
        .collection('challengeParticipants')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'COMPLETED')
        .limit(50)
        .snapshots()
        .asyncMap((q) async {
      final rows = <CompletedChallenge>[];
      for (final d in q.docs) {
        final m = _map(d.data());
        final id = (m['challengeId'] as String?) ?? d.id.split('_').first;
        final meta = await _challengeMeta(id);
        rows.add(
          CompletedChallenge(
            challengeId: id,
            title: meta.title,
            type: meta.type,
            completedAt: CompletedChallenge.parseTime(m['completedAt']),
          ),
        );
      }
      rows.sort((a, b) {
        final at = a.completedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.completedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      return rows.take(limit).toList(growable: false);
    });
  }

  Future<({String title, String? type})> _challengeMeta(String id) async {
    final cached = _challengeCache[id];
    if (cached != null) return cached;
    try {
      final snap = await _db.collection('challenges').doc(id).get();
      final m = _map(snap.data());
      final title = (m['title'] as String?)?.trim();
      final meta = (
        title: (title == null || title.isEmpty) ? 'Challenge' : title,
        type: m['type'] as String?,
      );
      if (snap.exists) _challengeCache[id] = meta;
      return meta;
    } catch (_) {
      // Unreadable (e.g. removed or restricted): still list the completion.
      return (title: 'Challenge', type: null);
    }
  }

  @override
  Future<List<LedgerEntry>> fetchRecentLedger(String uid, {int limit = 3}) async {
    final q = await _db
        .collection('virtualPointsLedger')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return [for (final d in q.docs) LedgerEntry.fromMap(d.id, _map(d.data()))];
  }
}

/// In-memory reader for tests and fake-mode wiring.
class FakeProfileExtrasReader implements ProfileExtrasReader {
  FakeProfileExtrasReader({
    this.catalogue,
    List<Achievement> achievements = const [],
    List<CompletedChallenge> completed = const [],
    List<LedgerEntry> ledger = const [],
  })  : _achievements = List.of(achievements),
        _completed = List.of(completed),
        _ledger = List.of(ledger);

  /// `adminSettings/badges` document content (null = document missing).
  Map<String, dynamic>? catalogue;
  List<Achievement> _achievements;
  List<CompletedChallenge> _completed;
  final List<LedgerEntry> _ledger;

  /// Per-source failures.
  Object? catalogueError;
  Object? achievementsError;
  Object? completedError;
  Object? ledgerError;

  final StreamController<void> _changed = StreamController<void>.broadcast();

  void setAchievements(List<Achievement> a) {
    _achievements = List.of(a);
    _changed.add(null);
  }

  void setCompleted(List<CompletedChallenge> c) {
    _completed = List.of(c);
    _changed.add(null);
  }

  @override
  Future<List<BadgeDefinition>> fetchBadgeCatalogue() async {
    final e = catalogueError;
    if (e != null) throw e;
    return buildBadgeCatalogue(catalogue);
  }

  @override
  Stream<List<Achievement>> watchAchievements(String uid) {
    final e = achievementsError;
    if (e != null) return Stream<List<Achievement>>.error(e);
    return Stream<List<Achievement>>.multi((c) {
      c.add(List.unmodifiable(_achievements));
      final sub = _changed.stream.listen((_) => c.add(List.unmodifiable(_achievements)));
      c.onCancel = sub.cancel;
    }, isBroadcast: true);
  }

  @override
  Stream<List<CompletedChallenge>> watchCompletedChallenges(String uid, {int limit = 20}) {
    final e = completedError;
    if (e != null) return Stream<List<CompletedChallenge>>.error(e);
    return Stream<List<CompletedChallenge>>.multi((c) {
      c.add(_completed.take(limit).toList(growable: false));
      final sub = _changed.stream.listen((_) => c.add(_completed.take(limit).toList(growable: false)));
      c.onCancel = sub.cancel;
    }, isBroadcast: true);
  }

  @override
  Future<List<LedgerEntry>> fetchRecentLedger(String uid, {int limit = 3}) async {
    final e = ledgerError;
    if (e != null) throw e;
    return _ledger.take(limit).toList(growable: false);
  }
}
