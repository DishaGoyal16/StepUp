import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:stepup/app_dependencies.dart';
import 'package:stepup/core/theme/app_theme.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/challenges/challenge_models.dart';
import 'package:stepup/data/challenges/fake_challenge_reader.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/domain/day_key.dart';
import 'package:stepup/features/auth/session_controller.dart';
import 'package:stepup/features/challenges/challenges_providers.dart';
import 'package:stepup/features/challenges/challenges_routes.dart';

import '../../support/harness.dart';

/// 2026-11-13 06:00 UTC (the harness clock) = Friday 13 Nov, 11:30 IST.
final DateTime kNow = DateTime.utc(2026, 11, 13, 6);

Challenge mkChallenge({
  String id = 'c1',
  ChallengeType type = ChallengeType.individual,
  String title = 'Test challenge',
  String description = '',
  ChallengeMetric metric = ChallengeMetric.totalSteps,
  int target = 50000,
  int? dailyTarget,
  ChallengeStatus status = ChallengeStatus.active,
  WindowMode windowMode = WindowMode.rolling,
  DateTime? startAt,
  DateTime? endAt,
  int? durationDays = 7,
  List<String> hostelIds = const [],
  HostelAggregation aggregation = HostelAggregation.averagePerParticipant,
  int? maxParticipants,
  int participantCount = 0,
  int rewardPoints = 0,
  bool isTemplate = true,
  String? createdBy,
  String? winnerUid,
  String? winnerHostelId,
}) =>
    Challenge(
      id: id,
      type: type,
      title: title,
      description: description,
      metric: metric,
      target: target,
      dailyTarget: dailyTarget,
      status: status,
      windowMode: windowMode,
      startAt: startAt,
      endAt: endAt,
      durationDays: durationDays,
      hostelIds: hostelIds,
      hostelAggregation: aggregation,
      maxParticipants: maxParticipants,
      participantCount: participantCount,
      rewardPoints: rewardPoints,
      isTemplate: isTemplate,
      createdBy: createdBy,
      winnerUid: winnerUid,
      winnerHostelId: winnerHostelId,
    );

ChallengeParticipation mkPart(
  String challengeId,
  String uid, {
  ParticipantStatus status = ParticipantStatus.joined,
  int progress = 0,
  String name = 'Me',
  String? windowStart,
  String? windowEnd,
}) =>
    ChallengeParticipation(
      challengeId: challengeId,
      uid: uid,
      status: status,
      displayName: name,
      progress: progress,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

/// A FIXED-window challenge from [startKey] (inclusive) for [days] days.
({DateTime start, DateTime end}) fixedWindow(String startKey, int days) {
  final s = DayKey.parse(startKey);
  return (start: s, end: s.add(Duration(days: days)));
}

Map<String, dynamic> leaderboardJson({
  required List<Map<String, dynamic>> entries,
  int? rank,
  int value = 0,
  String metricLabel = 'Verified steps',
}) =>
    {
      'entries': entries,
      'me': {'rank': rank, 'value': value},
      'metricLabel': metricLabel,
    };

/// Everything a challenges widget test needs, wired with fakes.
class ChallengeRig {
  ChallengeRig._(this.h, this.reader, this.buddies, this.functions, this.fs);

  factory ChallengeRig.create({
    List<Challenge> challenges = const [],
    List<ChallengeParticipation> participations = const [],
    Map<String, ChallengeResult> results = const {},
    List<BuddySummary> buddies = const [],
    FakeFirestoreAccess? firestore,
  }) {
    final fs = firestore ?? FakeFirestoreAccess();
    final h = Harness.create(signedIn: true, withProfile: true, firestore: fs);
    return ChallengeRig._(
      h,
      FakeChallengeReader(challenges: challenges, participations: participations, results: results),
      FakeBuddyDirectory(buddies),
      h.functions,
      fs,
    );
  }

  final Harness h;
  final FakeChallengeReader reader;
  final FakeBuddyDirectory buddies;
  final FakeFunctionsClient functions;
  final FakeFirestoreAccess fs;

  AppDependencies get deps => h.deps;
  String get uid => h.user!.uid;
  GoRouter? router;

  /// Pumps the challenges routes (no shell) under the real providers.
  Future<void> pump(WidgetTester tester, {String location = '/challenges'}) async {
    deps.session.start();
    await tester.pump();
    await tester.pump();
    router = GoRouter(initialLocation: location, routes: challengesRoutes);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDependencies>.value(value: deps),
          ChangeNotifierProvider<SessionController>.value(value: deps.session),
          ...challengesProviders(deps, reader: reader, buddies: buddies),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router!),
      ),
    );
    await settle(tester);
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
