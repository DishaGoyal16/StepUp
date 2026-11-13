import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/admin/admin_models.dart';
import 'package:stepup/data/admin/fake_admin_repository.dart';
import 'package:stepup/domain/hostel.dart';
import 'package:stepup/domain/hostel_seed.dart';
import 'package:stepup/features/admin/admin_support.dart';
import 'package:stepup/features/admin/admin_view_models.dart';

AdminStudent student(String uid, {String name = 'Student', String status = 'ACTIVE', String role = 'student'}) =>
    AdminStudent(
      uid: uid,
      displayName: name,
      email: '$uid@thapar.edu',
      hostelId: 'agira',
      status: status,
      role: role,
      pointsBalance: 10,
      pointsReserved: 0,
      lifetimeVerifiedSteps: 1000,
    );

AdminReport report(String id, {String target = 'bad-user'}) => AdminReport(
      id: id,
      reporterUid: 'rep',
      targetUid: target,
      reason: 'SPAM',
      details: 'spamming',
      status: ReportStatus.open,
    );

final DateTime now = DateTime.utc(2026, 11, 13, 6);

void main() {
  group('adminErrorMessage', () {
    test('permission-denied is spelled out, other messages pass through', () {
      expect(adminErrorMessage(FakeAdminRepository.permissionDenied()), contains('Admin access required'));
      expect(
        adminErrorMessage(AppException.fromCallable(code: 'not-found', message: 'Student not found')),
        'Student not found',
      );
      expect(adminErrorMessage(StateError('x')), contains('Something went wrong'));
    });
  });

  group('DashboardViewModel', () {
    test('loads stats and flags an empty hostel list', () async {
      final repo = FakeAdminRepository(students: [student('a'), student('b', status: 'SUSPENDED')]);
      final vm = DashboardViewModel(repo);
      await vm.load();
      expect(vm.stats!.users, 2);
      expect(vm.stats!.activeUsers, 1);
      expect(vm.hostelsEmpty, isTrue);
      expect(vm.error, isNull);
    });

    test('non-admin: error state with denied flag, no stats', () async {
      final vm = DashboardViewModel(FakeAdminRepository(isAdmin: false));
      await vm.load();
      expect(vm.stats, isNull);
      expect(vm.denied, isTrue);
      expect(vm.error, contains('Admin access required'));
    });

    test('seed reloads and reports the result', () async {
      final repo = FakeAdminRepository(hostels: hostelSeed.toList());
      final vm = DashboardViewModel(repo);
      final r = await vm.seed();
      expect(r.ok, isTrue);
      expect(r.message, contains('18 hostel'));
      expect(repo.calls, contains('seedDefaults'));
    });
  });

  group('StudentsViewModel', () {
    FakeAdminRepository repo0() => FakeAdminRepository(
          students: [
            for (var i = 0; i < 5; i++) student('u$i', name: 'Student $i'),
            student('boss', name: 'Boss', role: 'admin'),
          ],
          hostels: hostelSeed.toList(),
          pageSize: 4,
        );

    test('paginates and de-duplicates', () async {
      final vm = StudentsViewModel(repo0(), currentUid: 'boss');
      await vm.load();
      expect(vm.students.length, 4);
      expect(vm.nextCursor, isNotNull);
      await vm.loadMore();
      expect(vm.students.length, 6);
      expect(vm.nextCursor, isNull);
      await vm.loadMore(); // no cursor: no-op
      expect(vm.students.length, 6);
    });

    test('search filters and shows hostel names', () async {
      final vm = StudentsViewModel(repo0(), currentUid: 'boss');
      await vm.load(query: ' student 3 ');
      expect(vm.students.map((s) => s.uid), ['u3']);
      expect(vm.hostelLabel(vm.students.single), 'Agira Hall');
    });

    test('suspend requires a reason, updates the row, and unsuspend restores', () async {
      final repo = repo0();
      final vm = StudentsViewModel(repo, currentUid: 'boss');
      await vm.load();
      final s = vm.students.first;
      var r = await vm.suspend(s, '   ');
      expect(r.ok, isFalse);
      expect(repo.calls.where((c) => c == 'suspendUser'), isEmpty);
      r = await vm.suspend(s, 'Cheating');
      expect(r.ok, isTrue);
      expect(vm.students.first.isSuspended, isTrue);
      r = await vm.unsuspend(vm.students.first);
      expect(r.ok, isTrue);
      expect(vm.students.first.isSuspended, isFalse);
    });

    test('admins cannot suspend or demote themselves', () async {
      final repo = repo0();
      final vm = StudentsViewModel(repo, currentUid: 'boss');
      await vm.load();
      await vm.loadMore();
      final boss = vm.students.firstWhere((s) => s.uid == 'boss');
      expect(vm.canModify(boss), isFalse);
      expect((await vm.suspend(boss, 'x')).ok, isFalse);
      expect((await vm.setAdmin(boss, false)).ok, isFalse);
      expect(repo.calls.where((c) => c == 'suspendUser' || c == 'setUserRole'), isEmpty);
    });

    test('grant and revoke admin update the row', () async {
      final vm = StudentsViewModel(repo0(), currentUid: 'boss');
      await vm.load();
      expect((await vm.setAdmin(vm.students.first, true)).ok, isTrue);
      expect(vm.students.first.isAdmin, isTrue);
      expect((await vm.setAdmin(vm.students.first, false)).ok, isTrue);
      expect(vm.students.first.isAdmin, isFalse);
    });

    test('server failure becomes a failed result and leaves the row unchanged', () async {
      final repo = repo0();
      final vm = StudentsViewModel(repo, currentUid: 'boss');
      await vm.load();
      repo.failNext('suspendUser', AppException.fromCallable(code: 'not-found', message: 'User gone'));
      final r = await vm.suspend(vm.students.first, 'reason');
      expect(r.ok, isFalse);
      expect(r.message, 'User gone');
      expect(vm.students.first.isSuspended, isFalse);
      expect(vm.busy, isEmpty);
    });

    test('non-admin: load fails with the denied state', () async {
      final vm = StudentsViewModel(FakeAdminRepository(isAdmin: false), currentUid: 'x');
      await vm.load();
      expect(vm.denied, isTrue);
      expect(vm.students, isEmpty);
      expect(vm.loading, isFalse);
    });

    test('a non-admin cannot change anything: every mutation fails with permission-denied text', () async {
      final repo = repo0();
      final vm = StudentsViewModel(repo, currentUid: 'x');
      await vm.load();
      final s = vm.students.first;
      repo.isAdmin = false;
      final r = await vm.suspend(s, 'why');
      expect(r.ok, isFalse);
      expect(r.message, contains('Admin access required'));
      expect((await vm.setAdmin(s, true)).message, contains('Admin access required'));
    });
  });

  group('HostelsViewModel', () {
    test('splits into the two groups, keeps Vasudha blocks separate, includes inactive', () async {
      final seed = hostelSeed.toList();
      final repo = FakeAdminRepository(hostels: seed);
      final vm = HostelsViewModel(repo);
      await vm.load();
      expect(vm.general.length, 11);
      expect(vm.girls.length, 7);
      expect(vm.girls.map((h) => h.id), containsAll(['vasudha-e', 'vasudha-g']));
      await vm.setActive(vm.general.first, false);
      expect(vm.general.first.active, isFalse);
      expect(vm.general.length, 11, reason: 'inactive hostels stay listed for admins');
    });

    test('admins can correct a category and add a hostel; duplicate id refused', () async {
      final repo = FakeAdminRepository(hostels: hostelSeed.toList());
      final vm = HostelsViewModel(repo);
      await vm.load();
      final ira = vm.girls.firstWhere((h) => h.id == 'ira');
      var r = await vm.save(
        HostelDraft(id: 'ira', displayName: ira.displayName, category: HostelCategory.general, sortOrder: ira.sortOrder),
        creating: false,
      );
      expect(r.ok, isTrue);
      expect(vm.girls.any((h) => h.id == 'ira'), isFalse);
      expect(vm.general.any((h) => h.id == 'ira'), isTrue);

      r = await vm.save(
        HostelDraft(id: 'new-hall', displayName: 'New Hall', category: HostelCategory.girls, sortOrder: vm.nextSortOrder),
        creating: true,
      );
      expect(r.ok, isTrue);
      expect(vm.hostels.length, 19);

      final dup = await vm.save(
        const HostelDraft(id: 'agira', displayName: 'Dup', category: HostelCategory.general, sortOrder: 1),
        creating: true,
      );
      expect(dup.ok, isFalse);
      expect(dup.message, contains('already exists'));
    });

    test('non-admin sees the denied state', () async {
      final vm = HostelsViewModel(FakeAdminRepository(isAdmin: false));
      await vm.load();
      expect(vm.denied, isTrue);
    });
  });

  group('ChallengesViewModel', () {
    AdminChallenge ch(String id, String status) => AdminChallenge.fromMap(id, {'title': 'T$id', 'status': status});

    test('filters by status and cancels', () async {
      final repo = FakeAdminRepository(challenges: [ch('1', 'ACTIVE'), ch('2', 'COMPLETED'), ch('3', 'UPCOMING')]);
      final vm = ChallengesViewModel(repo);
      await vm.load();
      expect(vm.visible.length, 3);
      vm.setFilter('ACTIVE');
      expect(vm.visible.map((c) => c.id), ['1']);
      vm.setFilter(null);
      final r = await vm.cancel(vm.all.first);
      expect(r.ok, isTrue);
      expect(vm.all.first.status, 'CANCELLED');
    });

    test('cancelling a completed challenge shows the server error', () async {
      final repo = FakeAdminRepository(challenges: [ch('2', 'COMPLETED')]);
      final vm = ChallengesViewModel(repo);
      await vm.load();
      final r = await vm.cancel(vm.all.single);
      expect(r.ok, isFalse);
      expect(r.message, contains('already completed'));
    });
  });

  group('CreateChallengeViewModel', () {
    Future<CreateChallengeViewModel> loaded(FakeAdminRepository repo) async {
      final vm = CreateChallengeViewModel(repo);
      await vm.loadHostels();
      return vm;
    }

    test('presets select all / girls / general active hostels; manual toggle switches to "selected"', () async {
      final seed = [...hostelSeed];
      final repo = FakeAdminRepository(hostels: seed);
      final vm = await loaded(repo);
      expect(vm.selected.length, 18);
      vm.setPreset(HostelPreset.girls);
      expect(vm.selected.length, 7);
      expect(vm.selected, contains('vasudha-e'));
      expect(vm.selected, contains('vasudha-g'));
      vm.setPreset(HostelPreset.general);
      expect(vm.selected.length, 11);
      vm.toggleHostel('agira');
      expect(vm.preset, HostelPreset.selected);
      expect(vm.selected.length, 10);
    });

    test('inactive hostels are never selectable', () async {
      final seed = [
        ...hostelSeed.take(3),
        const Hostel(id: 'old', displayName: 'Old', category: HostelCategory.general, sortOrder: 99, active: false),
      ];
      final vm = await loaded(FakeAdminRepository(hostels: seed));
      expect(vm.selected, isNot(contains('old')));
      expect(vm.activeHostels.length, 3);
    });

    test('invalid form: submit fails without calling the server', () async {
      final repo = FakeAdminRepository(hostels: hostelSeed.toList());
      final vm = await loaded(repo);
      final r = await vm.submit(now);
      expect(r.ok, isFalse);
      expect(vm.showErrors, isTrue);
      expect(repo.createdChallenges, isEmpty);
    });

    test('valid inter-hostel form creates the challenge with the chosen hostels and average rule', () async {
      final repo = FakeAdminRepository(hostels: hostelSeed.toList());
      final vm = await loaded(repo);
      vm.setType(AdminChallengeType.interHostel);
      vm.title = 'Girls hostel cup';
      vm.targetText = '1,000,000';
      vm.setStart('20261114');
      vm.setLastDay('20261120');
      vm.setPreset(HostelPreset.girls);
      vm.rewardText = '200';
      final r = await vm.submit(now);
      expect(r.ok, isTrue, reason: r.message);
      final d = repo.createdChallenges.single;
      expect(d.type, AdminChallengeType.interHostel);
      expect(d.hostelIds.length, 7);
      expect(d.aggregation, HostelAggregation.averagePerParticipant);
      expect(d.target, 1000000);
      expect(d.rewardPoints, 200);
      expect(repo.challenges.single.title, 'Girls hostel cup');
    });

    test('setStart moves the last day forward when needed; non-individual cannot roll', () async {
      final vm = await loaded(FakeAdminRepository());
      vm.setLastDay('20261115');
      vm.setStart('20261118');
      expect(vm.lastDayKey, '20261118');
      vm.setType(AdminChallengeType.individual);
      vm.setRolling(true);
      expect(vm.rolling, isTrue);
      vm.setType(AdminChallengeType.campus);
      expect(vm.rolling, isFalse);
      vm.setRolling(true);
      expect(vm.rolling, isFalse);
    });

    test('individual rolling challenge needs a duration and sends no dates', () async {
      final repo = FakeAdminRepository();
      final vm = await loaded(repo);
      vm.setType(AdminChallengeType.individual);
      vm.title = '14-day starter';
      vm.targetText = '70000';
      vm.setRolling(true);
      expect((await vm.submit(now)).ok, isFalse);
      vm.durationText = '14';
      expect((await vm.submit(now)).ok, isTrue);
      expect(repo.createdChallenges.single.toPayload()['windowMode'], 'ROLLING');
    });

    test('server error is returned and the form stays', () async {
      final repo = FakeAdminRepository();
      final vm = await loaded(repo);
      vm.setType(AdminChallengeType.individual);
      vm.title = 'Walk';
      vm.targetText = '5000';
      vm.setStart('20261114');
      vm.setLastDay('20261114');
      repo.failNext('createChallenge', AppException.fromCallable(code: 'invalid-argument', message: 'Window already over'));
      final r = await vm.submit(now);
      expect(r.ok, isFalse);
      expect(r.message, 'Window already over');
      expect(vm.submitting, isFalse);
    });
  });

  group('ReportsViewModel', () {
    test('dismiss resolves and the report leaves the open list', () async {
      final repo = FakeAdminRepository(reports: [report('r1'), report('r2')]);
      final vm = ReportsViewModel(repo);
      await vm.load();
      expect(vm.reports.length, 2);
      final r = await vm.dismiss(vm.reports.first);
      expect(r.ok, isTrue);
      expect(vm.reports.length, 1);
      await vm.load(filter: ReportStatus.dismissed);
      expect(vm.reports.single.id, 'r1');
    });

    test('action with suspend: needs a reason, suspends the target, then closes the report', () async {
      final repo = FakeAdminRepository(reports: [report('r1')], students: [student('bad-user')]);
      final vm = ReportsViewModel(repo);
      await vm.load();
      expect((await vm.takeAction(vm.reports.single, suspendUser: true)).ok, isFalse);
      expect(repo.calls.where((c) => c == 'suspendUser'), isEmpty);
      final r = await vm.takeAction(vm.reports.single, suspendUser: true, reason: 'Harassment');
      expect(r.ok, isTrue);
      expect(repo.students.single.isSuspended, isTrue);
      expect(repo.reports.single.status, ReportStatus.actioned);
    });

    test('if the suspension fails the report stays open', () async {
      final repo = FakeAdminRepository(reports: [report('r1')], students: [student('bad-user')]);
      final vm = ReportsViewModel(repo);
      await vm.load();
      repo.failNext('suspendUser', AppException.fromCallable(code: 'failed-precondition', message: 'Cannot'));
      final r = await vm.takeAction(vm.reports.single, suspendUser: true, reason: 'x');
      expect(r.ok, isFalse);
      expect(r.message, contains('Could not suspend'));
      expect(repo.reports.single.status, ReportStatus.open);
      expect(vm.busy, isFalse);
    });

    test('action without suspend only closes the report', () async {
      final repo = FakeAdminRepository(reports: [report('r1')], students: [student('bad-user')]);
      final vm = ReportsViewModel(repo);
      await vm.load();
      expect((await vm.takeAction(vm.reports.single)).ok, isTrue);
      expect(repo.students.single.isSuspended, isFalse);
      expect(repo.reports.single.status, ReportStatus.actioned);
    });

    test('non-admin: denied', () async {
      final vm = ReportsViewModel(FakeAdminRepository(isAdmin: false));
      await vm.load();
      expect(vm.denied, isTrue);
    });
  });

  group('RiskViewModel', () {
    RiskEvent ev(String id) => RiskEvent(
          id: id,
          uid: 'u',
          kind: 'ROBOTIC',
          detail: const {'steps': 12000},
          status: RiskStatus.open,
          dayKey: '20261113',
        );

    test('review and clear move events out of the open list', () async {
      final repo = FakeAdminRepository(risks: [ev('e1'), ev('e2')]);
      final vm = RiskViewModel(repo);
      await vm.load();
      expect((await vm.resolve(vm.events.first, RiskStatus.reviewed)).ok, isTrue);
      expect((await vm.resolve(vm.events.first, RiskStatus.cleared)).ok, isTrue);
      expect(vm.events, isEmpty);
      await vm.load(filter: RiskStatus.cleared);
      expect(vm.events.single.id, 'e2');
    });

    test('non-admin: denied', () async {
      final vm = RiskViewModel(FakeAdminRepository(isAdmin: false));
      await vm.load();
      expect(vm.denied, isTrue);
    });
  });

  group('SettingsViewModel', () {
    Map<String, String> raw(Map<String, int> v) => {for (final e in v.entries) e.key: '${e.value}'};

    test('saves only the changed fields', () async {
      final repo = FakeAdminRepository();
      final vm = SettingsViewModel(repo);
      await vm.load();
      final form = raw(vm.values)..['pointsDailyGoal'] = '15';
      expect(vm.changesFrom(form), {'pointsDailyGoal': 15});
      final r = await vm.save(form);
      expect(r.ok, isTrue);
      expect(repo.settings['pointsDailyGoal'], 15);
      expect(vm.values['pointsDailyGoal'], 15);
      expect((await vm.save(form)).message, 'No changes to save.');
    });

    test('invalid values are never sent', () async {
      final repo = FakeAdminRepository();
      final vm = SettingsViewModel(repo);
      await vm.load();
      final form = raw(vm.values)..['maxStepsPerBucket'] = '99';
      final r = await vm.save(form);
      expect(r.ok, isFalse);
      expect(repo.calls.where((c) => c == 'setSettings'), isEmpty);
    });

    test('non-admin: load is denied and save is refused by the server', () async {
      final repo = FakeAdminRepository();
      final vm = SettingsViewModel(repo);
      await vm.load();
      repo.isAdmin = false;
      final r = await vm.save(raw(vm.values)..['betExpiryHours'] = '24');
      expect(r.ok, isFalse);
      expect(r.message, contains('Admin access required'));
      expect(vm.values['betExpiryHours'], 48, reason: 'local copy unchanged on failure');
    });
  });

  group('BadgesViewModel', () {
    test('edit saves title/description/points and keeps icon and rule', () async {
      const b = BadgeDefinition(
        id: 'FIRST_1K',
        title: 'First 1,000',
        description: 'Walk',
        icon: 'directions_walk',
        rule: 'lifetime >= 1000',
        points: 10,
      );
      final repo = FakeAdminRepository(badges: [b]);
      final vm = BadgesViewModel(repo);
      await vm.load();
      final r = await vm.save(vm.badges.single.copyWith(title: 'First 2,000', points: 20));
      expect(r.ok, isTrue);
      final saved = repo.badges.single;
      expect((saved.title, saved.points, saved.icon, saved.rule), ('First 2,000', 20, 'directions_walk', 'lifetime >= 1000'));
      expect((await vm.save(saved.copyWith(points: -5))).ok, isFalse);
    });
  });
}
