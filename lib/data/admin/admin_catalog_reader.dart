import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/hostel.dart';
import '../firestore/firebase_firestore_access.dart' show convertFirestoreValue;
import 'admin_models.dart';

/// Read-only access to the documents the admin panel lists but that have no
/// admin callable (all hostels, challenges, global settings, badges). The
/// rules let every eligible user read these; only writes are admin-only and
/// go through callables.
abstract class AdminCatalogReader {
  Future<List<Hostel>> fetchAllHostels();
  Future<List<AdminChallenge>> fetchChallenges();

  /// Raw `adminSettings/global` numbers (may be empty before seeding).
  Future<Map<String, int>> fetchGlobalSettings();
  Future<List<BadgeDefinition>> fetchBadges();
}

/// Firestore implementation. Failures surface as [AppException].
class FirestoreAdminCatalogReader implements AdminCatalogReader {
  FirestoreAdminCatalogReader(this._db);

  final FirebaseFirestore _db;

  static Map<String, dynamic> _data(DocumentSnapshot<Map<String, dynamic>> s) =>
      (convertFirestoreValue(s.data() ?? const {}) as Map).cast<String, dynamic>();

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      throw AppException.fromCallable(code: e.code, message: e.message);
    }
  }

  @override
  Future<List<Hostel>> fetchAllHostels() => _guard(() async {
        final q = await _db.collection('hostels').get();
        return [for (final d in q.docs) Hostel.fromMap(d.id, _data(d))]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      });

  @override
  Future<List<AdminChallenge>> fetchChallenges() => _guard(() async {
        // One equality query per type: the rules only allow reading
        // non-BUDDY challenges, and an equality filter proves that.
        final results = await Future.wait([
          for (final type in const ['CAMPUS', 'INTER_HOSTEL', 'INDIVIDUAL'])
            _db.collection('challenges').where('type', isEqualTo: type).limit(100).get(),
        ]);
        final list = [
          for (final q in results)
            for (final d in q.docs) AdminChallenge.fromMap(d.id, _data(d)),
        ]..sort((a, b) {
            final x = a.createdAt, y = b.createdAt;
            if (x == null && y == null) return a.title.compareTo(b.title);
            if (x == null) return 1;
            if (y == null) return -1;
            return y.compareTo(x);
          });
        return list;
      });

  @override
  Future<Map<String, int>> fetchGlobalSettings() => _guard(() async {
        final s = await _db.collection('adminSettings').doc('global').get();
        if (!s.exists) return <String, int>{};
        return {
          for (final e in _data(s).entries)
            if (e.value is num) e.key: (e.value as num).toInt(),
        };
      });

  @override
  Future<List<BadgeDefinition>> fetchBadges() => _guard(() async {
        final s = await _db.collection('adminSettings').doc('badges').get();
        if (!s.exists) return <BadgeDefinition>[];
        final out = <BadgeDefinition>[];
        for (final e in _data(s).entries) {
          if (e.value is Map) {
            out.add(BadgeDefinition.fromMap(e.key, (e.value as Map).cast<String, dynamic>()));
          }
        }
        out.sort((a, b) => a.id.compareTo(b.id));
        return out;
      });
}

/// In-memory reader for tests / fake wiring.
class FakeAdminCatalogReader implements AdminCatalogReader {
  FakeAdminCatalogReader({
    List<Hostel>? hostels,
    List<AdminChallenge>? challenges,
    Map<String, int>? settings,
    List<BadgeDefinition>? badges,
  })  : hostels = hostels ?? <Hostel>[],
        challenges = challenges ?? <AdminChallenge>[],
        settings = settings ?? <String, int>{},
        badges = badges ?? <BadgeDefinition>[];

  List<Hostel> hostels;
  List<AdminChallenge> challenges;
  Map<String, int> settings;
  List<BadgeDefinition> badges;

  @override
  Future<List<Hostel>> fetchAllHostels() async => List.of(hostels);

  @override
  Future<List<AdminChallenge>> fetchChallenges() async => List.of(challenges);

  @override
  Future<Map<String, int>> fetchGlobalSettings() async => Map.of(settings);

  @override
  Future<List<BadgeDefinition>> fetchBadges() async => List.of(badges);
}
