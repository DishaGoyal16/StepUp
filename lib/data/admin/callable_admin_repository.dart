import '../../domain/hostel.dart';
import '../functions/functions_client.dart';
import 'admin_catalog_reader.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'admin_settings_spec.dart';

/// [AdminRepository] over the admin callables (`DATABASE_SCHEMA.md`) plus the
/// read-only [AdminCatalogReader]. All admin power is enforced by the backend
/// (`token.admin === true`); nothing here grants anything.
class CallableAdminRepository implements AdminRepository {
  CallableAdminRepository({required FunctionsClient functions, required AdminCatalogReader reader})
      : _fn = functions,
        _reader = reader;

  final FunctionsClient _fn;
  final AdminCatalogReader _reader;

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> r, String key) {
    final v = r[key];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) {for (final x in e.entries) x.key.toString(): x.value},
    ];
  }

  @override
  Future<AdminStats> stats() async => AdminStats.fromMap(await _fn.call('adminStats'));

  @override
  Future<StudentPage> listStudents({String? query, String? cursor, int limit = 50}) async {
    final q = query?.trim();
    final r = await _fn.call('adminListStudents', {
      'limit': limit,
      if (q != null && q.isNotEmpty) 'query': q.length > 60 ? q.substring(0, 60) : q,
      'cursor': ?cursor,
    });
    final next = r['nextCursor'];
    return StudentPage(
      students: [for (final m in _rows(r, 'students')) AdminStudent.fromMap(m)],
      nextCursor: next is String && next.isNotEmpty ? next : null,
    );
  }

  @override
  Future<void> suspendUser(String uid, {required bool suspend, String? reason}) async {
    final trimmed = reason?.trim() ?? '';
    await _fn.call('adminSuspendUser', {
      'uid': uid,
      'suspend': suspend,
      if (suspend && trimmed.isNotEmpty) 'reason': trimmed,
    });
  }

  @override
  Future<void> setUserRole(String uid, {required bool admin}) async {
    await _fn.call('adminSetUserRole', {'uid': uid, 'role': admin ? 'admin' : 'student'});
  }

  @override
  Future<List<Hostel>> listHostels() => _reader.fetchAllHostels();

  @override
  Future<void> upsertHostel(HostelDraft draft) async {
    await _fn.call('adminUpsertHostel', draft.toPayload());
  }

  @override
  Future<void> setHostelActive(String hostelId, bool active) async {
    await _fn.call('adminSetHostelActive', {'hostelId': hostelId, 'active': active});
  }

  @override
  Future<List<AdminChallenge>> listChallenges() => _reader.fetchChallenges();

  @override
  Future<String> createChallenge(ChallengeDraft draft) async {
    final r = await _fn.call('adminCreateChallenge', draft.toPayload());
    return (r['challengeId'] as String?) ?? '';
  }

  @override
  Future<void> cancelChallenge(String challengeId) async {
    await _fn.call('adminCancelChallenge', {'challengeId': challengeId});
  }

  @override
  Future<List<AdminReport>> listReports({ReportStatus? status}) async {
    final r = await _fn.call('adminListReports', {
      'limit': 100,
      if (status != null) 'status': status.wire,
    });
    return [for (final m in _rows(r, 'reports')) AdminReport.fromMap(m)];
  }

  @override
  Future<void> resolveReport(String reportId, ReportStatus status) async {
    if (status == ReportStatus.open) {
      throw ArgumentError('A report can only be resolved as DISMISSED or ACTIONED.');
    }
    await _fn.call('adminResolveReport', {'reportId': reportId, 'status': status.wire});
  }

  @override
  Future<List<RiskEvent>> listRiskEvents({RiskStatus? status}) async {
    final r = await _fn.call('adminListRiskEvents', {
      'limit': 100,
      if (status != null) 'status': status.wire,
    });
    return [for (final m in _rows(r, 'events')) RiskEvent.fromMap(m)];
  }

  @override
  Future<void> resolveRiskEvent(String eventId, RiskStatus status) async {
    if (status == RiskStatus.open) {
      throw ArgumentError('A risk event can only be resolved as REVIEWED or CLEARED.');
    }
    await _fn.call('adminResolveRiskEvent', {'id': eventId, 'status': status.wire});
  }

  @override
  Future<Map<String, int>> loadSettings() async {
    final stored = await _reader.fetchGlobalSettings();
    return {
      for (final s in adminSettingSpecs) s.key: stored[s.key] ?? s.defaultValue,
    };
  }

  @override
  Future<void> setSettings(Map<String, int> changes) async {
    await _fn.call('adminSetSettings', {'settings': changes});
  }

  @override
  Future<List<BadgeDefinition>> loadBadges() => _reader.fetchBadges();

  @override
  Future<void> upsertBadge(BadgeDefinition badge) async {
    await _fn.call('adminUpsertBadge', badge.toPayload());
  }

  @override
  Future<SeedReport> seedDefaults() async =>
      SeedReport.fromMap(await _fn.call('adminSeedDefaults'));
}
