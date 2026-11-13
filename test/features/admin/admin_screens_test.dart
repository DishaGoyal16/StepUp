import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/admin/admin_models.dart';
import 'package:stepup/data/admin/fake_admin_repository.dart';
import 'package:stepup/domain/hostel_seed.dart';

import 'admin_test_support.dart';

FakeAdminRepository seeded({bool admin = true}) => FakeAdminRepository(
      isAdmin: admin,
      students: [
        testStudent('u1', name: 'Aarav Sharma'),
        testStudent('u2', name: 'Diya Verma', status: 'SUSPENDED'),
        testStudent('u3', name: 'Kabir Singh', role: 'admin'),
      ],
      hostels: hostelSeed.toList(),
      reports: [
        const AdminReport(
          id: 'r1',
          reporterUid: 'reporter-uid',
          targetUid: 'u1',
          reason: 'FAKE_PROFILE',
          details: 'Uses a stock photo',
          status: ReportStatus.open,
        ),
      ],
      risks: [
        const RiskEvent(
          id: 'e1',
          uid: 'u1',
          kind: 'DAILY_CAP',
          detail: {
            'verifiedSteps': 25000,
            'cap': 20000,
            'device': {'model': 'Pixel'},
            'flags': ['A', 'B'],
          },
          status: RiskStatus.open,
          dayKey: '20261113',
        ),
      ],
      challenges: [
        AdminChallenge.fromMap('c1', {
          'type': 'CAMPUS',
          'title': 'Campus November',
          'metric': 'TOTAL_STEPS',
          'target': 500000,
          'status': 'ACTIVE',
          'windowMode': 'FIXED',
          'startAt': DateTime.utc(2026, 11, 12, 18, 30),
          'endAt': DateTime.utc(2026, 11, 19, 18, 30),
          'participantCount': 12,
        }),
        AdminChallenge.fromMap('c2', {
          'type': 'INDIVIDUAL',
          'title': 'Old walk',
          'status': 'COMPLETED',
          'target': 5000,
        }),
      ],
      badges: [
        const BadgeDefinition(
          id: 'FIRST_1K',
          title: 'First 1,000',
          description: 'Walk your first 1,000 verified steps.',
          icon: 'directions_walk',
          rule: 'lifetimeVerifiedSteps >= 1000',
          points: 10,
        ),
      ],
    );

void main() {
  group('dashboard', () {
    testWidgets('shows adminStats and a card for every area; cards navigate', (tester) async {
      final repo = seeded();
      final router = await pumpAdmin(tester, repo);
      expect(find.text('Registered students'), findsOneWidget);
      expect(find.text('Active accounts'), findsOneWidget);
      expect(find.text('Challenges running'), findsOneWidget);
      expect(find.text('Open reports'), findsOneWidget);
      expect(find.text('Open risk events'), findsOneWidget);
      for (final t in ['Students', 'Hostels', 'Challenges', 'Reports', 'Suspicious activity', 'Settings', 'Badges']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      await tapText(tester, 'Suspicious activity');
      expect(router.state.uri.path, '/admin/risk');
      expect(find.text('Daily reward cap reached'), findsOneWidget);
    });

    testWidgets('a non-admin hitting the callable sees a clear permission-denied state', (tester) async {
      final repo = seeded(admin: false);
      await pumpAdmin(tester, repo);
      expect(find.text('Admins only'), findsOneWidget);
      expect(find.textContaining('Admin access required'), findsOneWidget);
      expect(find.text('Registered students'), findsNothing);
      // retry performs a real call
      final before = repo.calls.length;
      await tapText(tester, 'Try again');
      expect(repo.calls.length, greaterThan(before));
    });

    testWidgets('generic failure shows the message with retry', (tester) async {
      final repo = seeded();
      repo.failNext('stats', AppException.fromCallable(code: 'unavailable'));
      await pumpAdmin(tester, repo);
      expect(find.textContaining('Network problem'), findsOneWidget);
      await tapText(tester, 'Try again');
      expect(find.text('Registered students'), findsOneWidget);
    });

    testWidgets('empty hostel list offers the seed with confirmation and a result snackbar', (tester) async {
      final repo = FakeAdminRepository();
      await pumpAdmin(tester, repo);
      expect(find.text('No hostels yet'), findsOneWidget);
      await tapText(tester, 'Load default data');
      expect(find.text('Load default data?'), findsOneWidget);
      // cancel: nothing is called
      await tapText(tester, 'Cancel');
      expect(repo.calls.where((c) => c == 'seedDefaults'), isEmpty);
      await tapText(tester, 'Load default data');
      await tapText(tester, 'Load defaults');
      expect(repo.calls.where((c) => c == 'seedDefaults'), hasLength(1));
      expect(find.textContaining('Defaults loaded'), findsOneWidget);
    });
  });

  group('students', () {
    testWidgets('lists name, hostel, status, role and points; search calls the server', (tester) async {
      final repo = FakeAdminRepository(
        students: [testStudent('u1', name: 'Aarav Sharma'), testStudent('u2', name: 'Diya Verma', status: 'SUSPENDED'), testStudent('u3', name: 'Kabir Singh', role: 'admin')],
        hostels: hostelSeed.toList(),
      );
      await pumpAdmin(tester, repo, location: '/admin/students');
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.textContaining('Agira Hall'), findsWidgets);
      expect(find.textContaining('120 pts'), findsWidgets);
      expect(find.text('Suspended'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'diya');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Diya Verma'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'nobody');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('load more appears when the server returns a cursor', (tester) async {
      final repo = FakeAdminRepository(
        students: [for (var i = 0; i < 5; i++) testStudent('u$i', name: 'Student $i')],
        hostels: hostelSeed.toList(),
        pageSize: 3,
      );
      await pumpAdmin(tester, repo, location: '/admin/students');
      expect(find.text('Student 2'), findsOneWidget);
      expect(find.text('Student 3'), findsNothing);
      await tapText(tester, 'Load more');
      expect(find.text('Student 4'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('suspend needs a reason; result snackbar; then reactivate with confirmation', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/students');
      await tapText(tester, 'Aarav Sharma');
      await tapText(tester, 'Suspend student');
      expect(find.text('Suspend Aarav Sharma?'), findsOneWidget);
      // empty reason is refused locally
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();
      expect(find.text('A reason is required.'), findsOneWidget);
      expect(repo.calls.where((c) => c == 'suspendUser'), isEmpty);
      await tester.enterText(find.byType(TextField).last, 'Fake steps');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();
      expect(repo.students.first.isSuspended, isTrue);
      expect(find.text('Aarav Sharma suspended.'), findsOneWidget);
      // sheet now offers reactivation
      await tapText(tester, 'Reactivate student');
      expect(find.text('Reactivate Aarav Sharma?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
      await tester.pumpAndSettle();
      expect(repo.students.first.isSuspended, isFalse);
      expect(find.text('Aarav Sharma reactivated.'), findsOneWidget);
    });

    testWidgets('granting admin needs two confirmations including a typed phrase', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/students');
      await tapText(tester, 'Aarav Sharma');
      await tapText(tester, 'Make admin');
      expect(find.text('Make Aarav Sharma an admin?'), findsOneWidget);
      // cancelling the first dialog changes nothing
      await tapText(tester, 'Cancel');
      expect(repo.calls.where((c) => c == 'setUserRole'), isEmpty);
      await tapText(tester, 'Make admin');
      await tapText(tester, 'Continue');
      expect(find.text('Are you sure?'), findsOneWidget);
      // wrong phrase
      await tester.enterText(find.byType(TextField).last, 'yes');
      await tester.tap(find.widgetWithText(FilledButton, 'Grant admin'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Type exactly'), findsOneWidget);
      expect(repo.students.first.isAdmin, isFalse);
      // right phrase
      await tester.enterText(find.byType(TextField).last, 'GRANT ADMIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Grant admin'));
      await tester.pumpAndSettle();
      expect(repo.students.first.isAdmin, isTrue);
      expect(find.text('Aarav Sharma is now an admin.'), findsOneWidget);
    });

    testWidgets('revoking admin needs the REVOKE ADMIN phrase', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/students');
      await tapText(tester, 'Kabir Singh');
      await tapText(tester, 'Remove admin role');
      await tapText(tester, 'Continue');
      await tester.enterText(find.byType(TextField).last, 'REVOKE ADMIN');
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke admin'));
      await tester.pumpAndSettle();
      expect(repo.students.last.isAdmin, isFalse);
    });

    testWidgets('server error on suspend shows an error snackbar and the row is unchanged', (tester) async {
      final repo = seeded();
      repo.failNext('suspendUser', AppException.fromCallable(code: 'failed-precondition', message: 'Cannot suspend now'));
      await pumpAdmin(tester, repo, location: '/admin/students');
      await tapText(tester, 'Aarav Sharma');
      await tapText(tester, 'Suspend student');
      await tester.enterText(find.byType(TextField).last, 'reason');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();
      expect(find.text('Cannot suspend now'), findsOneWidget);
      expect(repo.students.first.isSuspended, isFalse);
    });

    testWidgets('non-admin sees the denied state instead of data', (tester) async {
      await pumpAdmin(tester, seeded(admin: false), location: '/admin/students');
      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Aarav Sharma'), findsNothing);
    });
  });

  group('hostels', () {
    testWidgets('shows the two groups with all 18 hostels, Vasudha blocks separate', (tester) async {
      await pumpAdmin(tester, seeded(), location: '/admin/hostels');
      expect(find.text('General hostels'), findsOneWidget);
      expect(find.text("Girls' hostels"), findsOneWidget);
      expect(find.text('11 hostel(s)'), findsOneWidget);
      expect(find.text('7 hostel(s)'), findsOneWidget);
      expect(find.text('Vasudha Hall - Block E'), findsOneWidget);
      expect(find.text('Vasudha Hall - Block G'), findsOneWidget);
    });

    testWidgets('add a hostel: validation, confirmation, result', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/hostels');
      await tapText(tester, 'Add hostel');
      // invalid id and name
      await tester.enterText(find.widgetWithText(TextField, 'Hostel id (slug)'), 'Bad Id');
      await tapText(tester, 'Continue');
      expect(find.textContaining('lowercase letters'), findsOneWidget);
      expect(find.textContaining('Name must be'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Hostel id (slug)'), 'new-hall');
      await tester.enterText(find.widgetWithText(TextField, 'Display name'), 'New Hall');
      await tester.tap(find.text('Girls'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Continue');
      expect(find.text('Add New Hall?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add hostel'));
      await tester.pumpAndSettle();
      expect(repo.upsertedHostels.single.id, 'new-hall');
      expect(repo.upsertedHostels.single.category.wire, 'GIRLS');
      expect(find.text('New Hall added.'), findsOneWidget);
      expect(find.text('8 hostel(s)'), findsOneWidget);
    });

    testWidgets('adding an existing id is refused', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/hostels');
      await tapText(tester, 'Add hostel');
      await tester.enterText(find.widgetWithText(TextField, 'Hostel id (slug)'), 'agira');
      await tester.enterText(find.widgetWithText(TextField, 'Display name'), 'Another');
      await tapText(tester, 'Continue');
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(repo.upsertedHostels, isEmpty);
    });

    testWidgets('edit corrects the category; the id is locked', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/hostels');
      await tester.tap(find.byTooltip('Edit Ira Hall'));
      await tester.pumpAndSettle();
      final idField = tester.widget<TextField>(find.widgetWithText(TextField, 'Hostel id (slug)'));
      expect(idField.enabled, isFalse);
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Continue');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.hostels.firstWhere((h) => h.id == 'ira').category.wire, 'GENERAL');
      expect(find.text('Ira Hall updated.'), findsOneWidget);
      expect(find.text('12 hostel(s)'), findsOneWidget);
    });

    testWidgets('deactivate asks for confirmation then reports', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/hostels');
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Deactivate Agira Hall?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await tester.pumpAndSettle();
      expect(repo.hostels.firstWhere((h) => h.id == 'agira').active, isFalse);
      expect(find.text('Agira Hall deactivated.'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('empty list offers seeding', (tester) async {
      final repo = FakeAdminRepository();
      await pumpAdmin(tester, repo, location: '/admin/hostels');
      expect(find.text('No hostels yet'), findsOneWidget);
      await tapText(tester, 'Load default data');
      await tapText(tester, 'Load defaults');
      expect(repo.calls, contains('seedDefaults'));
      expect(find.textContaining('Defaults loaded'), findsOneWidget);
    });

    testWidgets('non-admin sees the denied state', (tester) async {
      await pumpAdmin(tester, seeded(admin: false), location: '/admin/hostels');
      expect(find.text('Admins only'), findsOneWidget);
    });
  });

  group('challenges', () {
    testWidgets('lists with status, filters, and cancels after confirmation', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/challenges');
      expect(find.text('Campus November'), findsOneWidget);
      expect(find.text('Old walk'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      await tapText(tester, 'Completed');
      expect(find.text('Campus November'), findsNothing);
      expect(find.text('Old walk'), findsOneWidget);
      expect(find.text('Cancel challenge'), findsNothing, reason: 'completed challenges cannot be cancelled');
      await tapText(tester, 'All');
      await tapText(tester, 'Cancel challenge');
      expect(find.text('Cancel "Campus November"?'), findsOneWidget);
      await tapText(tester, 'Cancel'); // dismiss dialog: nothing happens
      expect(repo.calls.where((c) => c == 'cancelChallenge'), isEmpty);
      await tapText(tester, 'Cancel challenge');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel challenge'));
      await tester.pumpAndSettle();
      expect(repo.challenges.first.status, 'CANCELLED');
      expect(find.text('"Campus November" cancelled.'), findsOneWidget);
    });

    testWidgets('create inter-hostel challenge with the girls preset and date pickers', (tester) async {
      final repo = seeded();
      final router = await pumpAdmin(tester, repo, location: '/admin/challenges');
      await tapText(tester, 'New challenge');
      expect(router.state.uri.path, '/admin/challenges/new');

      await tester.tap(find.text('Inter-hostel'));
      await tester.pumpAndSettle();
      expect(find.text('Competing hostels'), findsOneWidget);
      expect(find.text('18 selected'), findsOneWidget, reason: 'default preset: all hostels');
      await tester.tap(find.text("Girls' hostels").first);
      await tester.pumpAndSettle();
      expect(find.text('7 selected'), findsOneWidget);

      // submit with nothing else: field errors
      await tester.ensureVisible(find.text('Create challenge'));
      await tapText(tester, 'Create challenge');
      expect(find.textContaining('Title must be'), findsWidgets);
      expect(find.text('Pick a start date.'), findsOneWidget);
      expect(repo.createdChallenges, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Girls hostel cup');
      await tester.enterText(find.widgetWithText(TextField, 'Target (total steps)'), '1000000');
      // first day: 20 Nov (clock is 13 Nov 2026 IST)
      await tester.tap(find.text('Pick a date').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick a date').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('27').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('20 Nov 2026'), findsOneWidget);
      expect(find.text('27 Nov 2026'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Reward points (optional)'), '250');
      await tester.ensureVisible(find.text('Create challenge'));
      await tapText(tester, 'Create challenge');
      expect(find.text('Create this challenge?'), findsOneWidget);
      expect(find.textContaining('7 hostels, average per participant'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      final d = repo.createdChallenges.single;
      expect(d.hostelIds, containsAll(['vasudha-e', 'vasudha-g', 'ira']));
      expect(d.hostelIds.length, 7);
      expect(d.startDayKey, '20261120');
      expect(d.lastDayKey, '20261127');
      expect(d.rewardPoints, 250);
      // back on the list with a result snackbar
      expect(router.state.uri.path, '/admin/challenges');
      expect(find.text('Challenge "Girls hostel cup" created.'), findsOneWidget);
      expect(find.text('Girls hostel cup'), findsWidgets);
    });

    testWidgets('individual challenge can use a rolling window; day metrics ask for a daily target', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/challenges/new');
      await tester.tap(find.text('Individual'));
      await tester.pumpAndSettle();
      expect(find.text('Starts when a student joins'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Duration (days, 1-90)'), findsOneWidget);
      expect(find.text('First day'), findsNothing);
      expect(find.text('Competing hostels'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<AdminChallengeMetric>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Streak days').last);
      await tester.pumpAndSettle();
      expect(find.text('Daily target (steps per day)'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Title'), '7-day streak');
      await tester.enterText(find.widgetWithText(TextField, 'Target (days)'), '7');
      await tester.enterText(find.widgetWithText(TextField, 'Daily target (steps per day)'), '8000');
      await tester.enterText(find.widgetWithText(TextField, 'Duration (days, 1-90)'), '7');
      await tester.ensureVisible(find.text('Create challenge'));
      await tapText(tester, 'Create challenge');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      final p = repo.createdChallenges.single.toPayload();
      expect(p['windowMode'], 'ROLLING');
      expect(p['metric'], 'STREAK_DAYS');
      expect(p['dailyTarget'], 8000);
      expect(p['durationDays'], 7);
    });

    testWidgets('a server refusal on create shows the error and keeps the form', (tester) async {
      final repo = seeded();
      repo.failNext('createChallenge', AppException.fromCallable(code: 'permission-denied', message: 'admin only'));
      await pumpAdmin(tester, repo, location: '/admin/challenges/new');
      await tester.tap(find.text('Individual'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Walk more');
      await tester.enterText(find.widgetWithText(TextField, 'Target (total steps)'), '50000');
      await tester.enterText(find.widgetWithText(TextField, 'Duration (days, 1-90)'), '7');
      await tester.ensureVisible(find.text('Create challenge'));
      await tapText(tester, 'Create challenge');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Admin access required'), findsOneWidget);
      expect(find.text('New challenge'), findsOneWidget);
    });

    testWidgets('non-admin sees the denied state on the list', (tester) async {
      await pumpAdmin(tester, seeded(admin: false), location: '/admin/challenges');
      expect(find.text('Admins only'), findsOneWidget);
    });
  });

  group('reports', () {
    testWidgets('detail shows the report; dismiss asks for confirmation', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/reports');
      expect(find.text('Fake profile'), findsOneWidget);
      await tapText(tester, 'Fake profile');
      expect(find.text('Uses a stock photo'), findsWidgets);
      expect(find.text('reporter-uid'), findsOneWidget);
      await tapText(tester, 'Dismiss report');
      expect(find.text('Dismiss this report?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
      await tester.pumpAndSettle();
      expect(repo.reports.single.status, ReportStatus.dismissed);
      expect(find.text('Report dismissed.'), findsOneWidget);
      expect(find.text('No open reports'), findsOneWidget);
      await tapText(tester, 'Dismissed');
      expect(find.text('Fake profile'), findsOneWidget);
    });

    testWidgets('take action and suspend: reason is mandatory', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/reports');
      await tapText(tester, 'Fake profile');
      await tapText(tester, 'Take action');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend and close'));
      await tester.pumpAndSettle();
      expect(find.text('A reason is required to suspend.'), findsOneWidget);
      expect(repo.calls.where((c) => c == 'suspendUser'), isEmpty);
      await tester.enterText(find.widgetWithText(TextField, 'Reason for suspension'), 'Impersonation');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend and close'));
      await tester.pumpAndSettle();
      expect(repo.students.first.isSuspended, isTrue);
      expect(repo.reports.single.status, ReportStatus.actioned);
      expect(find.text('Student suspended and report closed.'), findsOneWidget);
    });

    testWidgets('non-admin sees the denied state', (tester) async {
      await pumpAdmin(tester, seeded(admin: false), location: '/admin/reports');
      expect(find.text('Admins only'), findsOneWidget);
    });
  });

  group('risk events', () {
    testWidgets('detail map is shown readably; mark reviewed', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/risk');
      expect(find.text('Daily reward cap reached'), findsOneWidget);
      expect(find.textContaining('Fri 13 Nov'), findsOneWidget);
      await tapText(tester, 'Daily reward cap reached');
      expect(find.text('Verified steps'), findsOneWidget);
      expect(find.text('25,000'), findsOneWidget);
      expect(find.text('Cap'), findsOneWidget);
      expect(find.text('Device / Model'), findsOneWidget);
      expect(find.text('Pixel'), findsOneWidget);
      expect(find.text('A, B'), findsOneWidget);
      await tapText(tester, 'Mark as reviewed');
      expect(find.text('Mark as reviewed?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark reviewed'));
      await tester.pumpAndSettle();
      expect(repo.risks.single.status, RiskStatus.reviewed);
      expect(find.text('Event marked as reviewed.'), findsOneWidget);
      await tapText(tester, 'Reviewed');
      expect(find.text('Daily reward cap reached'), findsOneWidget);
    });

    testWidgets('clear requires confirmation', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/risk');
      await tapText(tester, 'Daily reward cap reached');
      await tapText(tester, 'Clear (no concern)');
      await tapText(tester, 'Cancel');
      expect(repo.risks.single.status, RiskStatus.open);
      await tapText(tester, 'Clear (no concern)');
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(repo.risks.single.status, RiskStatus.cleared);
    });

    testWidgets('non-admin sees the denied state', (tester) async {
      await pumpAdmin(tester, seeded(admin: false), location: '/admin/risk');
      expect(find.text('Admins only'), findsOneWidget);
    });
  });

  group('settings and badges', () {
    testWidgets('invalid numbers are flagged and nothing is sent', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/settings');
      await tester.enterText(find.byKey(const ValueKey('setting-maxStepsPerBucket')), '99');
      await tester.enterText(find.byKey(const ValueKey('setting-pointsDailyGoal')), 'abc');
      await tester.ensureVisible(find.text('Save settings').last);
      await tapText(tester, 'Save settings', last: true);
      expect(find.text('Must be between 1 and 35.'), findsWidgets);
      expect(find.text('Enter a whole number.'), findsOneWidget);
      expect(repo.calls.where((c) => c == 'setSettings'), isEmpty);
    });

    testWidgets('a valid change is confirmed (old -> new) and saved', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/settings');
      await tester.enterText(find.byKey(const ValueKey('setting-pointsDailyGoal')), '15');
      await tester.ensureVisible(find.text('Save settings').last);
      await tapText(tester, 'Save settings', last: true);
      expect(find.textContaining('Points for reaching the daily goal: 10 -> 15'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Save settings'),
      ));
      await tester.pumpAndSettle();
      expect(repo.settings['pointsDailyGoal'], 15);
      expect(find.text('Saved 1 setting(s).'), findsOneWidget);
    });

    testWidgets('no changes is reported, not sent', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/settings');
      await tester.ensureVisible(find.text('Save settings').last);
      await tapText(tester, 'Save settings', last: true);
      expect(find.text('No changes to save.'), findsOneWidget);
    });

    testWidgets('seed from settings asks for confirmation', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/settings');
      await tester.ensureVisible(find.text('Load default data'));
      await tapText(tester, 'Load default data');
      await tapText(tester, 'Load defaults');
      expect(repo.calls, contains('seedDefaults'));
      expect(find.textContaining('Defaults loaded'), findsOneWidget);
    });

    testWidgets('settings: non-admin sees the denied state', (tester) async {
      await pumpAdmin(tester, seeded(admin: false), location: '/admin/settings');
      expect(find.text('Admins only'), findsOneWidget);
    });

    testWidgets('badge edit: validation, confirmation, saved', (tester) async {
      final repo = seeded();
      await pumpAdmin(tester, repo, location: '/admin/badges');
      expect(find.text('First 1,000'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit First 1,000'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Reward points'), '-3');
      await tapText(tester, 'Continue');
      expect(find.text('Points must be 0-100000.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Reward points'), '25');
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'First 1K steps');
      await tapText(tester, 'Continue');
      expect(find.text('Save "First 1K steps"?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save badge'));
      await tester.pumpAndSettle();
      expect(repo.badges.single.points, 25);
      expect(repo.badges.single.icon, 'directions_walk');
      expect(find.text('"First 1K steps" saved.'), findsOneWidget);
    });
  });
}
