import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:stepup/app_dependencies.dart';
import 'package:stepup/core/theme/app_theme.dart';
import 'package:stepup/data/admin/admin_models.dart';
import 'package:stepup/data/admin/admin_repository.dart';
import 'package:stepup/features/admin/admin_routes.dart';

import '../../support/harness.dart';

AdminStudent testStudent(
  String uid, {
  String name = 'Aarav Sharma',
  String status = 'ACTIVE',
  String role = 'student',
}) =>
    AdminStudent(
      uid: uid,
      displayName: name,
      email: '$uid@thapar.edu',
      hostelId: 'agira',
      status: status,
      role: role,
      pointsBalance: 120,
      pointsReserved: 10,
      lifetimeVerifiedSteps: 54321,
    );

/// Pumps the admin routes (no app guard, no shell) at [location] with a fake
/// repository. Returns the router so tests can inspect the location.
Future<GoRouter> pumpAdmin(
  WidgetTester tester,
  AdminRepository repo, {
  String location = '/admin',
  Size size = const Size(800, 3000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final deps = Harness.create().deps;
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/home', builder: (c, s) => const Scaffold(body: Text('HOME'))),
      ...adminRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: deps),
        Provider<AdminRepository>.value(value: repo),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: 'text "$text" not found');
  await tester.tap(last ? f.last : f.first);
  await tester.pumpAndSettle();
}
