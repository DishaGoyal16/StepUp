import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/admin/admin_models.dart';
import 'package:stepup/data/admin/admin_settings_spec.dart';
import 'package:stepup/domain/day_key.dart';
import 'package:stepup/domain/hostel.dart';

// 2026-11-13 11:30 IST
final DateTime now = DateTime.utc(2026, 11, 13, 6);

ChallengeDraft valid({
  AdminChallengeType type = AdminChallengeType.campus,
  List<String> hostels = const [],
  bool rolling = false,
}) =>
    ChallengeDraft(
      type: type,
      title: 'November steps',
      target: 100000,
      startDayKey: '20261114',
      lastDayKey: '20261120',
      hostelIds: hostels,
      rolling: rolling,
      durationDays: 7,
    );

void main() {
  group('ChallengeDraft', () {
    test('valid campus draft has no errors and an IST day-aligned payload', () {
      final d = valid();
      expect(d.validate(now: now), isEmpty);
      final p = d.toPayload();
      expect(p['type'], 'CAMPUS');
      expect(p['windowMode'], 'FIXED');
      expect(p['startAt'], DayKey.parse('20261114').millisecondsSinceEpoch);
      // endAt is the IST midnight AFTER the inclusive last day (21 Nov 00:00 IST).
      expect(p['endAt'], DayKey.parse('20261121').millisecondsSinceEpoch);
      expect(p.containsKey('dailyTarget'), isFalse);
      expect(p.containsKey('hostelIds'), isFalse);
      expect(p.containsKey('durationDays'), isFalse);
    });

    test('startAt/endAt are exactly IST midnights', () {
      final p = valid().toPayload();
      for (final k in ['startAt', 'endAt']) {
        final ms = p[k] as int;
        expect(DayKey.boundsMs(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)).startMs, ms);
      }
    });

    test('title, target and window are validated', () {
      final e = const ChallengeDraft(type: AdminChallengeType.campus, title: 'ab').validate(now: now);
      expect(e.keys, containsAll(['title', 'target', 'start', 'end']));
    });

    test('last day before start and a window already over are rejected', () {
      final before = const ChallengeDraft(
        type: AdminChallengeType.campus,
        title: 'Abc',
        target: 10,
        startDayKey: '20261120',
        lastDayKey: '20261119',
      ).validate(now: now);
      expect(before['end'], contains('before'));
      final over = const ChallengeDraft(
        type: AdminChallengeType.campus,
        title: 'Abc',
        target: 10,
        startDayKey: '20261101',
        lastDayKey: '20261112',
      ).validate(now: now);
      expect(over['end'], contains('over'));
      // Today as last day is still fine (ends at the coming midnight).
      final today = const ChallengeDraft(
        type: AdminChallengeType.campus,
        title: 'Abc',
        target: 10,
        startDayKey: '20261113',
        lastDayKey: '20261113',
      ).validate(now: now);
      expect(today, isEmpty);
    });

    test('day based metrics need a daily target of 100..100000', () {
      const base = ChallengeDraft(
        type: AdminChallengeType.campus,
        title: 'Streak',
        metric: AdminChallengeMetric.streakDays,
        target: 7,
        startDayKey: '20261114',
        lastDayKey: '20261120',
      );
      expect(base.validate(now: now)['dailyTarget'], isNotNull);
      final ok = ChallengeDraft(
        type: base.type,
        title: base.title,
        metric: base.metric,
        target: 7,
        dailyTarget: 8000,
        startDayKey: base.startDayKey,
        lastDayKey: base.lastDayKey,
      );
      expect(ok.validate(now: now), isEmpty);
      expect(ok.toPayload()['dailyTarget'], 8000);
    });

    test('inter-hostel needs 2+ known hostels and sends aggregation', () {
      final one = valid(type: AdminChallengeType.interHostel, hostels: ['agira']);
      expect(one.validate(now: now)['hostels'], contains('two'));
      final unknown = valid(type: AdminChallengeType.interHostel, hostels: ['agira', 'nope']);
      expect(unknown.validate(now: now, knownHostelIds: {'agira', 'ira'})['hostels'], contains('unknown'));
      final ok = valid(type: AdminChallengeType.interHostel, hostels: ['agira', 'ira']);
      expect(ok.validate(now: now, knownHostelIds: {'agira', 'ira'}), isEmpty);
      final p = ok.toPayload();
      expect(p['hostelIds'], ['agira', 'ira']);
      expect(p['hostelAggregation'], 'AVERAGE_PER_PARTICIPANT');
    });

    test('only INDIVIDUAL may roll; group types stay FIXED', () {
      final ind = valid(type: AdminChallengeType.individual, rolling: true);
      final p = ind.toPayload();
      expect(p['windowMode'], 'ROLLING');
      expect(p['durationDays'], 7);
      expect(p.containsKey('startAt'), isFalse);
      expect(ind.validate(now: now), isEmpty);

      final campus = valid(rolling: true);
      expect(campus.isRolling, isFalse);
      expect(campus.toPayload()['windowMode'], 'FIXED');

      expect(
        const ChallengeDraft(
          type: AdminChallengeType.individual,
          title: 'Abc',
          target: 5,
          rolling: true,
          durationDays: 91,
        ).validate(now: now)['duration'],
        isNotNull,
      );
    });

    test('reward points are bounded', () {
      const d = ChallengeDraft(
        type: AdminChallengeType.campus,
        title: 'Abc',
        target: 5,
        startDayKey: '20261114',
        lastDayKey: '20261114',
        rewardPoints: 100001,
      );
      expect(d.validate(now: now)['rewardPoints'], isNotNull);
    });
  });

  group('HostelDraft', () {
    HostelDraft draft({String id = 'vasudha-e', String name = 'Vasudha Hall - Block E', int sort = 12}) =>
        HostelDraft(id: id, displayName: name, category: HostelCategory.girls, sortOrder: sort);

    test('valid draft and payload', () {
      const d = HostelDraft(
        id: 'vasudha-e',
        displayName: ' Vasudha Hall - Block E ',
        legacyName: 'Hostel-E',
        block: 'E',
        category: HostelCategory.girls,
        sortOrder: 12,
      );
      expect(d.validate(), isEmpty);
      expect(d.toPayload(), {
        'hostelId': 'vasudha-e',
        'displayName': 'Vasudha Hall - Block E',
        'legacyName': 'Hostel-E',
        'block': 'E',
        'category': 'GIRLS',
        'active': true,
        'sortOrder': 12,
      });
    });

    test('slug rules', () {
      for (final bad in ['A', 'Agira', 'a b', '-agira', 'a', 'x' * 41, 'agira_hall']) {
        expect(draft(id: bad).validate()['id'], isNotNull, reason: bad);
      }
      for (final good in ['ab', 'frf-g', 'vasudha-e', '9-block']) {
        expect(draft(id: good).validate().containsKey('id'), isFalse, reason: good);
      }
    });

    test('creating with an existing id is refused (upsert is a merge); editing is fine', () {
      expect(draft().validate(existingIds: {'vasudha-e'})['id'], contains('already exists'));
      expect(draft().validate(existingIds: {'vasudha-e'}, creating: false), isEmpty);
    });

    test('name, legacy, block, sort bounds', () {
      final e = HostelDraft(
        id: 'ab',
        displayName: 'x',
        legacyName: 'y' * 41,
        block: 'z' * 11,
        category: HostelCategory.general,
        sortOrder: 10001,
      ).validate();
      expect(e.keys, containsAll(['displayName', 'legacyName', 'block', 'sortOrder']));
    });
  });

  group('settings spec', () {
    Map<String, String> defaults() => {for (final s in adminSettingSpecs) s.key: '${s.defaultValue}'};

    test('the documented defaults validate', () {
      expect(validateSettingsForm(defaults()), isEmpty);
    });

    test('covers the backend editable keys', () {
      expect(adminSettingSpecs.map((s) => s.key).toSet(), {
        'dailyGoalDefault', 'maxStepsPerBucket', 'maxStepsPer30Min', 'maxRewardStepsPerDay',
        'maxBucketAgeHours', 'futureToleranceSec', 'settlementGraceHours', 'pointsDailyGoal',
        'pointsStreak7', 'pointsChallengeComplete', 'pointsChallengeWin', 'betMinStake',
        'betMaxStake', 'betExpiryHours', 'rewardDeviceTakeoverDays', 'buddyRerequestCooldownHours',
      });
    });

    test('rejects empty, non-numeric and out-of-range values', () {
      final raw = defaults()
        ..['maxStepsPerBucket'] = '36'
        ..['dailyGoalDefault'] = '999'
        ..['pointsDailyGoal'] = '1.5'
        ..['betExpiryHours'] = ''
        ..['maxStepsPer30Min'] = 'abc';
      final e = validateSettingsForm(raw);
      expect(
        e.keys,
        containsAll(['maxStepsPerBucket', 'dailyGoalDefault', 'pointsDailyGoal', 'betExpiryHours', 'maxStepsPer30Min']),
      );
    });

    test('max stake may not be below min stake', () {
      final raw = defaults()
        ..['betMinStake'] = '500'
        ..['betMaxStake'] = '100';
      expect(validateSettingsForm(raw)['betMaxStake'], isNotNull);
    });
  });

  group('parsing', () {
    test('student, report and risk event from callable maps (timestamps are ms)', () {
      final s = AdminStudent.fromMap({
        'uid': 'u1',
        'displayName': 'Aarav',
        'email': 'a@thapar.edu',
        'hostelId': 'agira',
        'status': 'SUSPENDED',
        'role': 'admin',
        'pointsBalance': 40,
        'createdAt': 1763000000000,
      });
      expect(s.isSuspended, isTrue);
      expect(s.isAdmin, isTrue);
      expect(s.createdAt, DateTime.fromMillisecondsSinceEpoch(1763000000000, isUtc: true));
      expect(s.copyWith(status: 'ACTIVE').isSuspended, isFalse);

      final r = AdminReport.fromMap({'id': 'r1', 'reason': 'FAKE_PROFILE', 'status': 'ACTIONED'});
      expect(r.reasonLabel, 'Fake profile');
      expect(r.status, ReportStatus.actioned);

      final e = RiskEvent.fromMap({
        'id': 'e1',
        'uid': 'u1',
        'kind': 'ROBOTIC',
        'dayKey': '20261113',
        'detail': {'a': 1},
      });
      expect(e.kindLabel, 'Robotic stepping pattern');
      expect(e.dayLabel, 'Fri 13 Nov');
      expect(e.status, RiskStatus.open);
      expect(RiskEvent.fromMap({'kind': 'NEW_KIND'}).kindLabel, 'New kind');
    });

    test('challenge from a Firestore map', () {
      final c = AdminChallenge.fromMap('c1', {
        'type': 'INTER_HOSTEL',
        'title': 'Hostel wars',
        'metric': 'TOTAL_STEPS',
        'target': 500000,
        'status': 'ACTIVE',
        'windowMode': 'FIXED',
        'hostelIds': ['agira', 'ira'],
        'startAt': DateTime.utc(2026, 11, 13),
      });
      expect(c.typeLabel, 'Inter-hostel');
      expect(c.hostelIds, ['agira', 'ira']);
      expect(c.canCancel, isTrue);
      expect(AdminChallenge.fromMap('c2', {'status': 'COMPLETED'}).canCancel, isFalse);
      expect(AdminChallenge.fromMap('c3', {'status': 'CANCELLED'}).canCancel, isFalse);
    });

    test('badge validation preserves icon and rule', () {
      const b = BadgeDefinition(
        id: 'FIRST_1K',
        title: 'First 1,000',
        description: 'Walk',
        icon: 'directions_walk',
        rule: 'lifetime >= 1000',
        points: 10,
      );
      expect(b.validate(), isEmpty);
      final p = b.copyWith(points: 15).toPayload();
      expect(p['icon'], 'directions_walk');
      expect(p['rule'], 'lifetime >= 1000');
      expect(p['points'], 15);
      expect(b.copyWith(title: 'x').validate()['title'], isNotNull);
      expect(b.copyWith(points: -1).validate()['points'], isNotNull);
    });

    test('seed report reads the nested callable result', () {
      final r = SeedReport.fromMap({
        'ok': true,
        'report': {'hostelsCreated': 18, 'challengeTemplatesCreated': 6, 'settingsCreatedOrFilled': true},
      });
      expect(r.hostelsCreated, 18);
      expect(r.summary, contains('18 hostel'));
    });

    test('humanizeKey', () {
      expect(humanizeKey('MANY_REJECTIONS'), 'Many rejections');
      expect(humanizeKey('startMs'), 'Start ms');
    });
  });
}
