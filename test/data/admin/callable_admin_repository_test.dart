import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/admin/admin_catalog_reader.dart';
import 'package:stepup/data/admin/admin_models.dart';
import 'package:stepup/data/admin/admin_settings_spec.dart';
import 'package:stepup/data/admin/callable_admin_repository.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/domain/hostel.dart';

void main() {
  late FakeFunctionsClient fn;
  late FakeAdminCatalogReader reader;
  late CallableAdminRepository repo;

  setUp(() {
    fn = FakeFunctionsClient();
    reader = FakeAdminCatalogReader();
    repo = CallableAdminRepository(functions: fn, reader: reader);
  });

  test('stats parses adminStats', () async {
    fn.on('adminStats', (_) => {
          'users': 120,
          'activeUsers': 100,
          'deletionRequests': 2,
          'activeChallenges': 3,
          'openReports': 4,
          'openRiskEvents': 5,
          'activeBets': 6,
        });
    final s = await repo.stats();
    expect((s.users, s.activeUsers, s.activeChallenges, s.openReports, s.openRiskEvents), (120, 100, 3, 4, 5));
  });

  test('listStudents sends query/cursor/limit and parses the page', () async {
    fn.on('adminListStudents', (_) => {
          'students': [
            {'uid': 'u1', 'displayName': 'Aarav', 'email': 'a@thapar.edu', 'status': 'ACTIVE', 'role': 'student'},
          ],
          'nextCursor': 'u1',
        });
    final p = await repo.listStudents(query: '  aar ', cursor: 'u0', limit: 20);
    expect(p.students.single.displayName, 'Aarav');
    expect(p.nextCursor, 'u1');
    expect(fn.callsTo('adminListStudents').single.params, {'limit': 20, 'query': 'aar', 'cursor': 'u0'});
  });

  test('listStudents omits blank query and null cursor', () async {
    fn.on('adminListStudents', (_) => {'students': <Object>[], 'nextCursor': null});
    final p = await repo.listStudents(query: '   ');
    expect(p.nextCursor, isNull);
    expect(fn.calls.single.params, {'limit': 50});
  });

  test('suspend sends the reason, unsuspend does not', () async {
    fn.on('adminSuspendUser', (_) => {'ok': true});
    await repo.suspendUser('u1', suspend: true, reason: ' cheating ');
    await repo.suspendUser('u1', suspend: false, reason: 'ignored');
    final calls = fn.callsTo('adminSuspendUser').toList();
    expect(calls[0].params, {'uid': 'u1', 'suspend': true, 'reason': 'cheating'});
    expect(calls[1].params, {'uid': 'u1', 'suspend': false});
  });

  test('setUserRole maps to student/admin', () async {
    fn.on('adminSetUserRole', (_) => {'ok': true});
    await repo.setUserRole('u1', admin: true);
    await repo.setUserRole('u1', admin: false);
    final c = fn.callsTo('adminSetUserRole').toList();
    expect(c[0].params, {'uid': 'u1', 'role': 'admin'});
    expect(c[1].params, {'uid': 'u1', 'role': 'student'});
  });

  test('hostel upsert / active payloads', () async {
    fn.on('adminUpsertHostel', (_) => {'ok': true});
    fn.on('adminSetHostelActive', (_) => {'ok': true});
    await repo.upsertHostel(const HostelDraft(
      id: 'ira',
      displayName: 'Ira Hall',
      legacyName: 'Hostel-I',
      category: HostelCategory.girls,
      sortOrder: 14,
    ));
    await repo.setHostelActive('ira', false);
    expect(fn.callsTo('adminUpsertHostel').single.params['category'], 'GIRLS');
    expect(fn.callsTo('adminSetHostelActive').single.params, {'hostelId': 'ira', 'active': false});
  });

  test('lists hostels and challenges from the reader', () async {
    reader.hostels = [
      const Hostel(id: 'a1', displayName: 'A', category: HostelCategory.general, sortOrder: 1, active: false),
    ];
    expect((await repo.listHostels()).single.active, isFalse);
    reader.challenges = [AdminChallenge.fromMap('c1', {'title': 'T'})];
    expect((await repo.listChallenges()).single.id, 'c1');
  });

  test('createChallenge posts the draft payload and returns the id', () async {
    fn.on('adminCreateChallenge', (_) => {'challengeId': 'abc'});
    final id = await repo.createChallenge(const ChallengeDraft(
      type: AdminChallengeType.interHostel,
      title: 'Hostel wars',
      target: 1000000,
      startDayKey: '20261114',
      lastDayKey: '20261120',
      hostelIds: ['agira', 'ira'],
      rewardPoints: 200,
    ));
    expect(id, 'abc');
    final p = fn.callsTo('adminCreateChallenge').single.params;
    expect(p['type'], 'INTER_HOSTEL');
    expect(p['hostelIds'], ['agira', 'ira']);
    expect(p['rewardPoints'], 200);
    expect(p['windowMode'], 'FIXED');
  });

  test('cancelChallenge', () async {
    fn.on('adminCancelChallenge', (_) => {'ok': true});
    await repo.cancelChallenge('c9');
    expect(fn.calls.single.params, {'challengeId': 'c9'});
  });

  test('reports: list with status filter, resolve DISMISSED/ACTIONED only', () async {
    fn.on('adminListReports', (_) => {
          'reports': [
            {
              'id': 'r1',
              'targetUid': 't',
              'reporterUid': 'p',
              'reason': 'SPAM',
              'status': 'OPEN',
              'createdAt': 1763000000000,
            },
          ],
        });
    fn.on('adminResolveReport', (_) => {'ok': true});
    final r = await repo.listReports(status: ReportStatus.open);
    expect(r.single.reasonLabel, 'Spam');
    expect(fn.callsTo('adminListReports').single.params, {'limit': 100, 'status': 'OPEN'});
    await repo.resolveReport('r1', ReportStatus.dismissed);
    expect(fn.callsTo('adminResolveReport').single.params, {'reportId': 'r1', 'status': 'DISMISSED'});
    expect(() => repo.resolveReport('r1', ReportStatus.open), throwsArgumentError);
  });

  test('risk events: list, resolve uses the "id" key', () async {
    fn.on('adminListRiskEvents', (_) => {
          'events': [
            {'id': 'e1', 'uid': 'u', 'kind': 'DAILY_CAP', 'dayKey': '20261113', 'status': 'OPEN', 'detail': {'x': 1}},
          ],
        });
    fn.on('adminResolveRiskEvent', (_) => {'ok': true});
    expect((await repo.listRiskEvents()).single.kind, 'DAILY_CAP');
    expect(fn.callsTo('adminListRiskEvents').single.params, {'limit': 100});
    await repo.resolveRiskEvent('e1', RiskStatus.cleared);
    expect(fn.callsTo('adminResolveRiskEvent').single.params, {'id': 'e1', 'status': 'CLEARED'});
    expect(() => repo.resolveRiskEvent('e1', RiskStatus.open), throwsArgumentError);
  });

  test('settings: stored values override defaults; set sends {settings: ...}', () async {
    reader.settings = {'betMinStake': 25};
    final s = await repo.loadSettings();
    expect(s['betMinStake'], 25);
    expect(s['betMaxStake'], 1000);
    expect(s.length, adminSettingSpecs.length);
    fn.on('adminSetSettings', (_) => {'ok': true});
    await repo.setSettings({'betMinStake': 30});
    expect(fn.calls.single.params, {
      'settings': {'betMinStake': 30},
    });
  });

  test('badges: upsert payload and list', () async {
    reader.badges = [
      const BadgeDefinition(id: 'FIRST_1K', title: 'T', description: 'Dd', icon: 'i', rule: 'rr', points: 1),
    ];
    expect((await repo.loadBadges()).single.id, 'FIRST_1K');
    fn.on('adminUpsertBadge', (_) => {'ok': true});
    await repo.upsertBadge(reader.badges.single.copyWith(points: 5));
    expect(fn.calls.single.params['badgeId'], 'FIRST_1K');
    expect(fn.calls.single.params['points'], 5);
  });

  test('seedDefaults parses the report', () async {
    fn.on('adminSeedDefaults', (_) => {
          'ok': true,
          'report': {
            'hostelsCreated': 18,
            'challengeTemplatesCreated': 6,
            'settingsCreatedOrFilled': true,
            'badgesCreatedOrFilled': true,
          },
        });
    final r = await repo.seedDefaults();
    expect(r.hostelsCreated, 18);
    expect(r.badgesCreatedOrFilled, isTrue);
  });

  test('a non-admin gets the server permission-denied AppException on every kind of call', () async {
    final denied = AppException.fromCallable(
      code: 'permission-denied',
      message: 'admin only',
      details: {'reason': 'ADMIN_REQUIRED'},
    );
    for (final name in ['adminStats', 'adminListStudents', 'adminSuspendUser', 'adminSetUserRole', 'adminSeedDefaults']) {
      fn.failNext(name, denied);
    }
    await expectLater(repo.stats(), throwsA(isA<AppException>().having((e) => e.code, 'code', 'permission-denied')));
    await expectLater(
      repo.listStudents(),
      throwsA(isA<AppException>().having((e) => e.reason, 'reason', 'ADMIN_REQUIRED')),
    );
    await expectLater(repo.suspendUser('u', suspend: true, reason: 'x'), throwsA(isA<AppException>()));
    await expectLater(repo.setUserRole('u', admin: true), throwsA(isA<AppException>()));
    await expectLater(repo.seedDefaults(), throwsA(isA<AppException>()));
  });
}
