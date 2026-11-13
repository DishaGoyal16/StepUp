import '../../data/admin/admin_models.dart';
import '../../data/admin/admin_repository.dart';
import '../../data/admin/admin_settings_spec.dart';
import '../../domain/day_key.dart';
import '../../domain/hostel.dart';
import 'admin_support.dart';

/// Dashboard: `adminStats` plus a "no hostels yet" hint for the seed button.
class DashboardViewModel extends SafeNotifier {
  DashboardViewModel(this._repo);

  final AdminRepository _repo;

  AdminStats? stats;
  bool loading = false;
  String? error;
  bool denied = false;

  /// True when the `hostels` collection is empty (offer to seed defaults).
  bool hostelsEmpty = false;

  Future<void> load() async {
    loading = true;
    error = null;
    denied = false;
    notifyListeners();
    try {
      stats = await _repo.stats();
    } catch (e) {
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    if (error == null) {
      try {
        hostelsEmpty = (await _repo.listHostels()).isEmpty;
      } catch (_) {
        hostelsEmpty = false;
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<AdminResult> seed() async {
    try {
      final r = await _repo.seedDefaults();
      await load();
      return AdminResult.ok('Defaults loaded: ${r.summary}');
    } catch (e) {
      return AdminResult.fail(adminErrorMessage(e));
    }
  }
}

/// Students: search + pagination + suspend / role actions.
class StudentsViewModel extends SafeNotifier {
  StudentsViewModel(this._repo, {this.currentUid});

  final AdminRepository _repo;

  /// The signed-in admin; they cannot suspend or demote themselves (the
  /// server refuses it too).
  final String? currentUid;

  List<AdminStudent> students = const [];
  String? nextCursor;
  String query = '';
  bool loading = false;
  bool loadingMore = false;
  String? error;
  bool denied = false;
  Map<String, String> hostelNames = const {};
  final Set<String> busy = {};
  int _generation = 0;

  bool canModify(AdminStudent s) => s.uid != currentUid;

  String hostelLabel(AdminStudent s) {
    final id = s.hostelId;
    if (id == null) return 'No hostel';
    return hostelNames[id] ?? id;
  }

  Future<void> load({String? query}) async {
    if (query != null) this.query = query.trim();
    final gen = ++_generation;
    loading = true;
    error = null;
    denied = false;
    students = const [];
    nextCursor = null;
    notifyListeners();
    try {
      if (hostelNames.isEmpty) {
        try {
          final hostels = await _repo.listHostels();
          hostelNames = {for (final h in hostels) h.id: h.displayName};
        } catch (_) {}
      }
      final page = await _repo.listStudents(query: this.query);
      if (gen != _generation) return;
      students = page.students;
      nextCursor = page.nextCursor;
    } catch (e) {
      if (gen != _generation) return;
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    if (gen == _generation) {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (cursor == null || loadingMore || loading) return;
    final gen = _generation;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await _repo.listStudents(query: query, cursor: cursor);
      if (gen != _generation) return;
      final known = {for (final s in students) s.uid};
      students = [...students, ...page.students.where((s) => !known.contains(s.uid))];
      nextCursor = page.nextCursor;
    } catch (e) {
      if (gen == _generation) error = adminErrorMessage(e);
    }
    if (gen == _generation) {
      loadingMore = false;
      notifyListeners();
    }
  }

  void _replace(AdminStudent updated) {
    students = [for (final s in students) s.uid == updated.uid ? updated : s];
  }

  Future<AdminResult> suspend(AdminStudent s, String reason) async {
    final r = reason.trim();
    if (r.isEmpty) return const AdminResult.fail('A reason is required to suspend a student.');
    if (r.length > 300) return const AdminResult.fail('The reason can be at most 300 characters.');
    if (!canModify(s)) return const AdminResult.fail('You cannot suspend your own account.');
    return _run(s, () async {
      await _repo.suspendUser(s.uid, suspend: true, reason: r);
      _replace(s.copyWith(status: 'SUSPENDED'));
      return '${s.displayName} suspended.';
    });
  }

  Future<AdminResult> unsuspend(AdminStudent s) => _run(s, () async {
        await _repo.suspendUser(s.uid, suspend: false);
        _replace(s.copyWith(status: 'ACTIVE'));
        return '${s.displayName} reactivated.';
      });

  Future<AdminResult> setAdmin(AdminStudent s, bool admin) async {
    if (!admin && !canModify(s)) {
      return const AdminResult.fail('You cannot remove your own admin role.');
    }
    return _run(s, () async {
      await _repo.setUserRole(s.uid, admin: admin);
      _replace(s.copyWith(role: admin ? 'admin' : 'student'));
      return admin ? '${s.displayName} is now an admin.' : '${s.displayName} is no longer an admin.';
    });
  }

  Future<AdminResult> _run(AdminStudent s, Future<String> Function() body) async {
    busy.add(s.uid);
    notifyListeners();
    try {
      return AdminResult.ok(await body());
    } catch (e) {
      return AdminResult.fail(adminErrorMessage(e));
    } finally {
      busy.remove(s.uid);
      notifyListeners();
    }
  }
}

/// Hostels: the two groups (General / Girls), add, edit, activate.
class HostelsViewModel extends SafeNotifier {
  HostelsViewModel(this._repo);

  final AdminRepository _repo;

  List<Hostel> hostels = const [];
  bool loading = false;
  String? error;
  bool denied = false;
  bool saving = false;

  List<Hostel> _group(HostelCategory c) =>
      hostels.where((h) => h.category == c).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Hostel> get general => _group(HostelCategory.general);
  List<Hostel> get girls => _group(HostelCategory.girls);

  /// Suggested sort order for a new hostel (after the last one).
  int get nextSortOrder => hostels.isEmpty
      ? 1
      : (hostels.map((h) => h.sortOrder).reduce((a, b) => a > b ? a : b) + 1).clamp(0, 10000);

  Set<String> get ids => {for (final h in hostels) h.id};

  Future<void> load() async {
    loading = true;
    error = null;
    denied = false;
    notifyListeners();
    try {
      hostels = await _repo.listHostels();
    } catch (e) {
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<AdminResult> save(HostelDraft draft, {required bool creating}) async {
    final errors = draft.validate(existingIds: ids, creating: creating);
    if (errors.isNotEmpty) return AdminResult.fail(errors.values.first);
    saving = true;
    notifyListeners();
    try {
      await _repo.upsertHostel(draft);
      saving = false;
      await load();
      return AdminResult.ok(creating ? '${draft.displayName} added.' : '${draft.displayName} updated.');
    } catch (e) {
      saving = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }

  Future<AdminResult> setActive(Hostel h, bool active) async {
    saving = true;
    notifyListeners();
    try {
      await _repo.setHostelActive(h.id, active);
      saving = false;
      await load();
      return AdminResult.ok(active ? '${h.displayName} activated.' : '${h.displayName} deactivated.');
    } catch (e) {
      saving = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }

  Future<AdminResult> seed() async {
    saving = true;
    notifyListeners();
    try {
      final r = await _repo.seedDefaults();
      saving = false;
      await load();
      return AdminResult.ok('Defaults loaded: ${r.summary}');
    } catch (e) {
      saving = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }
}

/// Challenge list with a status filter and cancel.
class ChallengesViewModel extends SafeNotifier {
  ChallengesViewModel(this._repo);

  final AdminRepository _repo;

  List<AdminChallenge> all = const [];
  String? statusFilter;
  bool loading = false;
  String? error;
  bool denied = false;
  final Set<String> busy = {};

  static const filters = <String?>[null, 'ACTIVE', 'UPCOMING', 'COMPLETED', 'CANCELLED'];

  List<AdminChallenge> get visible =>
      statusFilter == null ? all : all.where((c) => c.status == statusFilter).toList();

  void setFilter(String? status) {
    statusFilter = status;
    notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    denied = false;
    notifyListeners();
    try {
      all = await _repo.listChallenges();
    } catch (e) {
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<AdminResult> cancel(AdminChallenge c) async {
    busy.add(c.id);
    notifyListeners();
    try {
      await _repo.cancelChallenge(c.id);
      busy.remove(c.id);
      await load();
      return AdminResult.ok('"${c.title}" cancelled.');
    } catch (e) {
      busy.remove(c.id);
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }
}

enum HostelPreset {
  all('All hostels'),
  girls("Girls' hostels"),
  general('General hostels'),
  selected('Selected');

  const HostelPreset(this.label);
  final String label;
}

/// State of the create-challenge form.
class CreateChallengeViewModel extends SafeNotifier {
  CreateChallengeViewModel(this._repo);

  final AdminRepository _repo;

  AdminChallengeType type = AdminChallengeType.campus;
  String title = '';
  String description = '';
  AdminChallengeMetric metric = AdminChallengeMetric.totalSteps;
  String targetText = '';
  String dailyTargetText = '';
  bool rolling = false;
  String durationText = '';
  String? startDayKey;
  String? lastDayKey;
  HostelPreset preset = HostelPreset.all;
  Set<String> selected = {};
  HostelAggregation aggregation = HostelAggregation.averagePerParticipant;
  String rewardText = '';

  List<Hostel> hostels = const [];
  bool loadingHostels = false;
  String? hostelsError;
  bool submitting = false;
  bool showErrors = false;

  List<Hostel> get activeHostels => hostels.where((h) => h.active).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<void> loadHostels() async {
    loadingHostels = true;
    hostelsError = null;
    notifyListeners();
    try {
      hostels = await _repo.listHostels();
      _applyPreset();
    } catch (e) {
      hostelsError = adminErrorMessage(e);
    }
    loadingHostels = false;
    notifyListeners();
  }

  static int? _parse(String raw) {
    final t = raw.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return int.tryParse(t) ?? -1;
  }

  void _applyPreset() {
    switch (preset) {
      case HostelPreset.all:
        selected = {for (final h in activeHostels) h.id};
      case HostelPreset.girls:
        selected = {for (final h in activeHostels) if (h.isGirls) h.id};
      case HostelPreset.general:
        selected = {for (final h in activeHostels) if (!h.isGirls) h.id};
      case HostelPreset.selected:
        selected = selected.where((id) => activeHostels.any((h) => h.id == id)).toSet();
    }
  }

  void setPreset(HostelPreset p) {
    preset = p;
    _applyPreset();
    notifyListeners();
  }

  void toggleHostel(String id) {
    selected = {...selected};
    if (!selected.remove(id)) selected.add(id);
    preset = HostelPreset.selected;
    notifyListeners();
  }

  void setType(AdminChallengeType t) {
    type = t;
    if (t != AdminChallengeType.individual) rolling = false;
    notifyListeners();
  }

  void setMetric(AdminChallengeMetric m) {
    metric = m;
    notifyListeners();
  }

  void setRolling(bool v) {
    rolling = v && type == AdminChallengeType.individual;
    notifyListeners();
  }

  void setAggregation(HostelAggregation a) {
    aggregation = a;
    notifyListeners();
  }

  /// Dates are IST calendar days (`YYYYMMDD`).
  void setStart(String dayKey) {
    startDayKey = dayKey;
    final last = lastDayKey;
    if (last != null && last.compareTo(dayKey) < 0) lastDayKey = dayKey;
    notifyListeners();
  }

  void setLastDay(String dayKey) {
    lastDayKey = dayKey;
    notifyListeners();
  }

  /// Notifies after plain text edits so error text and the summary update.
  void touch() => notifyListeners();

  ChallengeDraft get draft => ChallengeDraft(
        type: type,
        title: title,
        description: description,
        metric: metric,
        target: _parse(targetText),
        dailyTarget: _parse(dailyTargetText),
        rolling: rolling,
        durationDays: _parse(durationText),
        startDayKey: startDayKey,
        lastDayKey: lastDayKey,
        hostelIds: selected.toList()..sort(),
        aggregation: aggregation,
        rewardPoints: _parse(rewardText),
      );

  Map<String, String> errors(DateTime now) =>
      draft.validate(now: now, knownHostelIds: {for (final h in activeHostels) h.id});

  /// IST calendar day of [instant] (the earliest selectable date).
  static String todayKey(DateTime instant) => DayKey.of(instant);

  /// Validates and creates. [AdminResult.message] is the error or the
  /// success text.
  Future<AdminResult> submit(DateTime now) async {
    showErrors = true;
    final errs = errors(now);
    if (errs.isNotEmpty) {
      notifyListeners();
      return AdminResult.fail(errs.values.first);
    }
    submitting = true;
    notifyListeners();
    try {
      await _repo.createChallenge(draft);
      submitting = false;
      notifyListeners();
      return AdminResult.ok('Challenge "${title.trim()}" created.');
    } catch (e) {
      submitting = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }
}

/// Reports queue.
class ReportsViewModel extends SafeNotifier {
  ReportsViewModel(this._repo);

  final AdminRepository _repo;

  List<AdminReport> reports = const [];
  ReportStatus filter = ReportStatus.open;
  bool loading = false;
  String? error;
  bool denied = false;
  bool busy = false;

  Future<void> load({ReportStatus? filter}) async {
    if (filter != null) this.filter = filter;
    loading = true;
    error = null;
    denied = false;
    notifyListeners();
    try {
      reports = await _repo.listReports(status: this.filter);
    } catch (e) {
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<AdminResult> dismiss(AdminReport r) => _resolve(
        r,
        ReportStatus.dismissed,
        'Report dismissed.',
      );

  /// Marks the report ACTIONED. With [suspendUser] the reported student is
  /// suspended first (needs a [reason]); if that fails the report stays open.
  Future<AdminResult> takeAction(AdminReport r, {bool suspendUser = false, String reason = ''}) async {
    if (suspendUser && reason.trim().isEmpty) {
      return const AdminResult.fail('A reason is required to suspend the reported student.');
    }
    if (suspendUser) {
      busy = true;
      notifyListeners();
      try {
        await _repo.suspendUser(r.targetUid, suspend: true, reason: reason.trim());
      } catch (e) {
        busy = false;
        notifyListeners();
        return AdminResult.fail('Could not suspend the student: ${adminErrorMessage(e)}');
      }
    }
    final res = await _resolve(
      r,
      ReportStatus.actioned,
      suspendUser ? 'Student suspended and report closed.' : 'Report closed as action taken.',
    );
    if (!res.ok && suspendUser) {
      return AdminResult.fail('Student suspended, but the report could not be closed: ${res.message}');
    }
    return res;
  }

  Future<AdminResult> _resolve(AdminReport r, ReportStatus status, String done) async {
    busy = true;
    notifyListeners();
    try {
      await _repo.resolveReport(r.id, status);
      busy = false;
      await load();
      return AdminResult.ok(done);
    } catch (e) {
      busy = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }
}

/// Suspicious step activity queue.
class RiskViewModel extends SafeNotifier {
  RiskViewModel(this._repo);

  final AdminRepository _repo;

  List<RiskEvent> events = const [];
  RiskStatus filter = RiskStatus.open;
  bool loading = false;
  String? error;
  bool denied = false;
  bool busy = false;

  Future<void> load({RiskStatus? filter}) async {
    if (filter != null) this.filter = filter;
    loading = true;
    error = null;
    denied = false;
    notifyListeners();
    try {
      events = await _repo.listRiskEvents(status: this.filter);
    } catch (e) {
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<AdminResult> resolve(RiskEvent e, RiskStatus status) async {
    busy = true;
    notifyListeners();
    try {
      await _repo.resolveRiskEvent(e.id, status);
      busy = false;
      await load();
      return AdminResult.ok(status == RiskStatus.cleared ? 'Event cleared.' : 'Event marked as reviewed.');
    } catch (err) {
      busy = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(err));
    }
  }
}

/// `adminSettings/global` editor.
class SettingsViewModel extends SafeNotifier {
  SettingsViewModel(this._repo);

  final AdminRepository _repo;

  Map<String, int> values = const {};
  bool loading = false;
  String? error;
  bool denied = false;
  bool saving = false;

  Future<void> load() async {
    loading = true;
    error = null;
    denied = false;
    notifyListeners();
    try {
      values = await _repo.loadSettings();
    } catch (e) {
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    loading = false;
    notifyListeners();
  }

  /// The fields of [raw] that differ from the stored values.
  Map<String, int> changesFrom(Map<String, String> raw) {
    final out = <String, int>{};
    for (final spec in adminSettingSpecs) {
      final v = int.tryParse((raw[spec.key] ?? '').trim());
      if (v != null && v != values[spec.key]) out[spec.key] = v;
    }
    return out;
  }

  Future<AdminResult> save(Map<String, String> raw) async {
    final errs = validateSettingsForm(raw);
    if (errs.isNotEmpty) return AdminResult.fail(errs.values.first);
    final changes = changesFrom(raw);
    if (changes.isEmpty) return const AdminResult.fail('No changes to save.');
    saving = true;
    notifyListeners();
    try {
      await _repo.setSettings(changes);
      values = {...values, ...changes};
      saving = false;
      notifyListeners();
      return AdminResult.ok('Saved ${changes.length} setting(s).');
    } catch (e) {
      saving = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }

  Future<AdminResult> seed() async {
    saving = true;
    notifyListeners();
    try {
      final r = await _repo.seedDefaults();
      saving = false;
      notifyListeners();
      await load();
      return AdminResult.ok('Defaults loaded: ${r.summary}');
    } catch (e) {
      saving = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }
}

/// Badge catalogue editor.
class BadgesViewModel extends SafeNotifier {
  BadgesViewModel(this._repo);

  final AdminRepository _repo;

  List<BadgeDefinition> badges = const [];
  bool loading = false;
  String? error;
  bool denied = false;
  bool saving = false;

  Future<void> load() async {
    loading = true;
    error = null;
    denied = false;
    notifyListeners();
    try {
      badges = await _repo.loadBadges();
    } catch (e) {
      error = adminErrorMessage(e);
      denied = isPermissionDenied(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<AdminResult> save(BadgeDefinition b) async {
    final errs = b.validate();
    if (errs.isNotEmpty) return AdminResult.fail(errs.values.first);
    saving = true;
    notifyListeners();
    try {
      await _repo.upsertBadge(b);
      saving = false;
      await load();
      return AdminResult.ok('"${b.title.trim()}" saved.');
    } catch (e) {
      saving = false;
      notifyListeners();
      return AdminResult.fail(adminErrorMessage(e));
    }
  }
}
