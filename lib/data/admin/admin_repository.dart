import '../../domain/hostel.dart';
import 'admin_models.dart';

/// Everything the admin panel does, behind one interface. Implementations:
/// [CallableAdminRepository] (admin callables + Firestore reads) and
/// `FakeAdminRepository` (tests). Every method throws `AppException` on
/// failure; a non-admin gets `permission-denied` from the backend.
abstract class AdminRepository {
  Future<AdminStats> stats();

  // students
  Future<StudentPage> listStudents({String? query, String? cursor, int limit = 50});
  Future<void> suspendUser(String uid, {required bool suspend, String? reason});
  Future<void> setUserRole(String uid, {required bool admin});

  // hostels
  /// All hostels, active and inactive.
  Future<List<Hostel>> listHostels();
  Future<void> upsertHostel(HostelDraft draft);
  Future<void> setHostelActive(String hostelId, bool active);

  // challenges
  Future<List<AdminChallenge>> listChallenges();
  Future<String> createChallenge(ChallengeDraft draft);
  Future<void> cancelChallenge(String challengeId);

  // moderation
  Future<List<AdminReport>> listReports({ReportStatus? status});
  Future<void> resolveReport(String reportId, ReportStatus status);
  Future<List<RiskEvent>> listRiskEvents({RiskStatus? status});
  Future<void> resolveRiskEvent(String eventId, RiskStatus status);

  // settings / badges / seed
  /// Effective global settings: stored values over the documented defaults.
  Future<Map<String, int>> loadSettings();
  Future<void> setSettings(Map<String, int> changes);
  Future<List<BadgeDefinition>> loadBadges();
  Future<void> upsertBadge(BadgeDefinition badge);
  Future<SeedReport> seedDefaults();
}
