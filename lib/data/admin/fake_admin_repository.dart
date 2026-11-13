import '../../core/errors/app_exception.dart';
import '../../domain/hostel.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'admin_settings_spec.dart';

/// In-memory [AdminRepository] for tests. With `isAdmin: false` every method
/// fails with the backend's `permission-denied` error, like a non-admin
/// calling the real callables.
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    this.isAdmin = true,
    List<AdminStudent>? students,
    List<Hostel>? hostels,
    List<AdminChallenge>? challenges,
    List<AdminReport>? reports,
    List<RiskEvent>? risks,
    Map<String, int>? settings,
    List<BadgeDefinition>? badges,
    this.pageSize = 50,
  })  : students = students ?? <AdminStudent>[],
        hostels = hostels ?? <Hostel>[],
        challenges = challenges ?? <AdminChallenge>[],
        reports = reports ?? <AdminReport>[],
        risks = risks ?? <RiskEvent>[],
        settings = settings ?? {for (final s in adminSettingSpecs) s.key: s.defaultValue},
        badges = badges ?? <BadgeDefinition>[];

  bool isAdmin;
  int pageSize;
  final List<AdminStudent> students;
  final List<Hostel> hostels;
  final List<AdminChallenge> challenges;
  final List<AdminReport> reports;
  final List<RiskEvent> risks;
  final Map<String, int> settings;
  final List<BadgeDefinition> badges;

  /// Names of the methods called, in order (`'suspendUser'`, ...).
  final List<String> calls = [];
  final List<ChallengeDraft> createdChallenges = [];
  final List<HostelDraft> upsertedHostels = [];
  final Map<String, List<AppException>> _failures = {};

  /// Makes the next call of [method] throw [error].
  void failNext(String method, AppException error) =>
      (_failures[method] ??= []).add(error);

  static AppException permissionDenied() => AppException.fromCallable(
        code: 'permission-denied',
        message: 'admin only',
        details: {'reason': 'ADMIN_REQUIRED'},
      );

  void _enter(String method) {
    calls.add(method);
    final q = _failures[method];
    if (q != null && q.isNotEmpty) throw q.removeAt(0);
    if (!isAdmin) throw permissionDenied();
  }

  @override
  Future<AdminStats> stats() async {
    _enter('stats');
    return AdminStats(
      users: students.length,
      activeUsers: students.where((s) => s.status == 'ACTIVE').length,
      deletionRequests: students.where((s) => s.status == 'DELETION_REQUESTED').length,
      activeChallenges: challenges.where((c) => c.status == 'ACTIVE').length,
      openReports: reports.where((r) => r.status == ReportStatus.open).length,
      openRiskEvents: risks.where((r) => r.status == RiskStatus.open).length,
      activeBets: 0,
    );
  }

  @override
  Future<StudentPage> listStudents({String? query, String? cursor, int limit = 50}) async {
    _enter('listStudents');
    final q = (query ?? '').trim().toLowerCase();
    final all = students
        .where((s) => q.isEmpty || s.displayName.toLowerCase().contains(q) || s.email.toLowerCase().contains(q))
        .toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, all.length);
    return StudentPage(
      students: all.sublist(start.clamp(0, all.length), end),
      nextCursor: end < all.length ? '$end' : null,
    );
  }

  int _studentIndex(String uid) {
    final i = students.indexWhere((s) => s.uid == uid);
    if (i < 0) {
      throw AppException.fromCallable(code: 'not-found', message: 'USER_NOT_FOUND');
    }
    return i;
  }

  @override
  Future<void> suspendUser(String uid, {required bool suspend, String? reason}) async {
    _enter('suspendUser');
    final i = _studentIndex(uid);
    students[i] = students[i].copyWith(status: suspend ? 'SUSPENDED' : 'ACTIVE');
  }

  @override
  Future<void> setUserRole(String uid, {required bool admin}) async {
    _enter('setUserRole');
    final i = _studentIndex(uid);
    students[i] = students[i].copyWith(role: admin ? 'admin' : 'student');
  }

  @override
  Future<List<Hostel>> listHostels() async {
    _enter('listHostels');
    return List.of(hostels);
  }

  @override
  Future<void> upsertHostel(HostelDraft d) async {
    _enter('upsertHostel');
    upsertedHostels.add(d);
    final h = Hostel(
      id: d.id,
      displayName: d.displayName,
      legacyName: (d.legacyName ?? '').isEmpty ? null : d.legacyName,
      block: (d.block ?? '').isEmpty ? null : d.block,
      category: d.category,
      sortOrder: d.sortOrder,
      active: d.active,
    );
    final i = hostels.indexWhere((x) => x.id == d.id);
    if (i < 0) {
      hostels.add(h);
    } else {
      hostels[i] = h;
    }
  }

  @override
  Future<void> setHostelActive(String hostelId, bool active) async {
    _enter('setHostelActive');
    final i = hostels.indexWhere((x) => x.id == hostelId);
    if (i < 0) throw AppException.fromCallable(code: 'not-found', message: 'HOSTEL_NOT_FOUND');
    final h = hostels[i];
    hostels[i] = Hostel(
      id: h.id,
      displayName: h.displayName,
      legacyName: h.legacyName,
      block: h.block,
      category: h.category,
      sortOrder: h.sortOrder,
      active: active,
    );
  }

  @override
  Future<List<AdminChallenge>> listChallenges() async {
    _enter('listChallenges');
    return List.of(challenges);
  }

  @override
  Future<String> createChallenge(ChallengeDraft draft) async {
    _enter('createChallenge');
    createdChallenges.add(draft);
    final id = 'ch${createdChallenges.length}';
    challenges.insert(
      0,
      AdminChallenge(
        id: id,
        type: draft.type.wire,
        title: draft.title,
        description: draft.description,
        metric: draft.metric.wire,
        target: draft.target ?? 0,
        dailyTarget: draft.dailyTarget,
        status: 'UPCOMING',
        windowMode: draft.isRolling ? 'ROLLING' : 'FIXED',
        hostelIds: draft.hostelIds,
        participantCount: 0,
        isTemplate: false,
      ),
    );
    return id;
  }

  @override
  Future<void> cancelChallenge(String challengeId) async {
    _enter('cancelChallenge');
    final i = challenges.indexWhere((c) => c.id == challengeId);
    if (i < 0) throw AppException.fromCallable(code: 'not-found', message: 'CHALLENGE_NOT_FOUND');
    final c = challenges[i];
    if (c.status == 'COMPLETED') {
      throw AppException.fromCallable(
        code: 'failed-precondition',
        message: 'This challenge is already completed.',
      );
    }
    challenges[i] = AdminChallenge(
      id: c.id,
      type: c.type,
      title: c.title,
      description: c.description,
      metric: c.metric,
      target: c.target,
      dailyTarget: c.dailyTarget,
      status: 'CANCELLED',
      windowMode: c.windowMode,
      startAt: c.startAt,
      endAt: c.endAt,
      durationDays: c.durationDays,
      hostelIds: c.hostelIds,
      hostelAggregation: c.hostelAggregation,
      rewardPoints: c.rewardPoints,
      participantCount: c.participantCount,
      isTemplate: c.isTemplate,
      createdAt: c.createdAt,
    );
  }

  @override
  Future<List<AdminReport>> listReports({ReportStatus? status}) async {
    _enter('listReports');
    return reports.where((r) => status == null || r.status == status).toList();
  }

  @override
  Future<void> resolveReport(String reportId, ReportStatus status) async {
    _enter('resolveReport');
    final i = reports.indexWhere((r) => r.id == reportId);
    if (i < 0) throw AppException.fromCallable(code: 'not-found', message: 'REPORT_NOT_FOUND');
    final r = reports[i];
    reports[i] = AdminReport(
      id: r.id,
      reporterUid: r.reporterUid,
      targetUid: r.targetUid,
      reason: r.reason,
      details: r.details,
      status: status,
      createdAt: r.createdAt,
    );
  }

  @override
  Future<List<RiskEvent>> listRiskEvents({RiskStatus? status}) async {
    _enter('listRiskEvents');
    return risks.where((r) => status == null || r.status == status).toList();
  }

  @override
  Future<void> resolveRiskEvent(String eventId, RiskStatus status) async {
    _enter('resolveRiskEvent');
    final i = risks.indexWhere((r) => r.id == eventId);
    if (i < 0) throw AppException.fromCallable(code: 'not-found', message: 'RISK_EVENT_NOT_FOUND');
    final r = risks[i];
    risks[i] = RiskEvent(
      id: r.id,
      uid: r.uid,
      kind: r.kind,
      detail: r.detail,
      status: status,
      dayKey: r.dayKey,
      createdAt: r.createdAt,
    );
  }

  @override
  Future<Map<String, int>> loadSettings() async {
    _enter('loadSettings');
    return Map.of(settings);
  }

  @override
  Future<void> setSettings(Map<String, int> changes) async {
    _enter('setSettings');
    settings.addAll(changes);
  }

  @override
  Future<List<BadgeDefinition>> loadBadges() async {
    _enter('loadBadges');
    return List.of(badges);
  }

  @override
  Future<void> upsertBadge(BadgeDefinition badge) async {
    _enter('upsertBadge');
    final i = badges.indexWhere((b) => b.id == badge.id);
    if (i < 0) {
      badges.add(badge);
    } else {
      badges[i] = badge;
    }
  }

  @override
  Future<SeedReport> seedDefaults() async {
    _enter('seedDefaults');
    return const SeedReport(hostelsCreated: 18, challengeTemplatesCreated: 6, settingsCreatedOrFilled: true);
  }
}
