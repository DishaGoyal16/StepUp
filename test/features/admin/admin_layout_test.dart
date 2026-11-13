import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/admin/admin_models.dart';
import 'package:stepup/data/admin/fake_admin_repository.dart';
import 'package:stepup/domain/hostel_seed.dart';

import 'admin_test_support.dart';

/// Every admin screen must lay out on a 360 px phone without overflow errors
/// (a RenderFlex overflow makes the test fail) and on a wide window.
void main() {
  FakeAdminRepository repo() => FakeAdminRepository(
        students: [testStudent('u1', name: 'A very long student name that keeps going and going')],
        hostels: hostelSeed.toList(),
        reports: [
          const AdminReport(
            id: 'r1',
            reporterUid: 'reporter-uid-very-long-0123456789',
            targetUid: 'u1',
            reason: 'HARASSMENT',
            details: 'A long description of what happened, repeated. ' 'A long description of what happened, repeated.',
            status: ReportStatus.open,
          ),
        ],
        risks: [
          const RiskEvent(
            id: 'e1',
            uid: 'u1',
            kind: 'MANY_REJECTIONS',
            detail: {'rejected': 90, 'sample': ['CADENCE_EXCEEDED', 'SHAKE_PATTERN']},
            status: RiskStatus.open,
            dayKey: '20261113',
          ),
        ],
        challenges: [
          AdminChallenge.fromMap('c1', {
            'type': 'INTER_HOSTEL',
            'title': 'A very long inter-hostel challenge title for a narrow phone screen',
            'metric': 'DAILY_TARGET_DAYS',
            'target': 7,
            'dailyTarget': 8000,
            'status': 'ACTIVE',
            'windowMode': 'FIXED',
            'hostelIds': ['agira', 'ira'],
            'startAt': DateTime.utc(2026, 11, 12, 18, 30),
            'endAt': DateTime.utc(2026, 11, 19, 18, 30),
          }),
        ],
        badges: [
          const BadgeDefinition(
            id: 'FIRST_1K',
            title: 'First 1,000',
            description: 'Walk your first 1,000 verified steps and keep walking every day.',
            icon: 'x',
            rule: 'rr',
            points: 10,
          ),
        ],
      );

  const paths = [
    '/admin',
    '/admin/students',
    '/admin/hostels',
    '/admin/challenges',
    '/admin/challenges/new',
    '/admin/reports',
    '/admin/risk',
    '/admin/settings',
    '/admin/badges',
  ];

  for (final size in const [Size(360, 740), Size(1200, 800)]) {
    for (final path in paths) {
      testWidgets('$path fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await pumpAdmin(tester, repo(), location: path, size: size);
        expect(tester.takeException(), isNull);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
  }

  testWidgets('create-challenge inter-hostel section fits a phone', (tester) async {
    await pumpAdmin(tester, repo(), location: '/admin/challenges/new', size: const Size(360, 740));
    await tester.tap(find.text('Inter-hostel'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Hostel score'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
}
