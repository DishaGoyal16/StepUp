import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/leaderboard/leaderboard_models.dart';
import 'package:stepup/features/leaderboard/leaderboard_format.dart';

void main() {
  test('formatSteps groups thousands and rounds fractions', () {
    expect(formatSteps(0), '0');
    expect(formatSteps(12345), '12,345');
    expect(formatSteps(1234.6), '1,235');
    expect(formatSteps(1234567), '1,234,567');
  });

  test('defaultMetricLabel covers every board', () {
    expect(
      defaultMetricLabel(const LeaderboardQuery(
          scope: LeaderboardScope.campus, period: LeaderboardPeriod.daily)),
      'Verified steps',
    );
    expect(
      defaultMetricLabel(const LeaderboardQuery(
          scope: LeaderboardScope.hostels, period: LeaderboardPeriod.daily)),
      'Average verified steps per participant',
    );
    expect(
      defaultMetricLabel(const LeaderboardQuery(
        scope: LeaderboardScope.hostels,
        period: LeaderboardPeriod.daily,
        hostelMetric: HostelMetric.total,
      )),
      'Total verified steps',
    );
  });

  test('periodKeyLabel', () {
    expect(periodKeyLabel(LeaderboardPeriod.daily, '20261113'), 'Fri 13 Nov');
    expect(periodKeyLabel(LeaderboardPeriod.daily, 'weird'), 'weird');
    expect(periodKeyLabel(LeaderboardPeriod.monthly, '202611'), 'Nov 2026');
    expect(periodKeyLabel(LeaderboardPeriod.monthly, '2026-11'), 'Nov 2026');
    expect(periodKeyLabel(LeaderboardPeriod.monthly, '202613'), '202613');
    expect(periodKeyLabel(LeaderboardPeriod.weekly, '2026-W46'), 'Week 2026-W46');
    expect(periodKeyLabel(LeaderboardPeriod.allTime, 'ALL'), 'All time');
    expect(periodKeyLabel(LeaderboardPeriod.weekly, null), 'Weekly');
  });

  test('updatedLabel is relative, then an IST timestamp', () {
    final now = DateTime.utc(2026, 11, 13, 6);
    expect(updatedLabel(now, now), 'just now');
    expect(updatedLabel(now.add(const Duration(minutes: 5)), now), 'just now', reason: 'clock skew');
    expect(updatedLabel(now.subtract(const Duration(seconds: 30)), now), 'just now');
    expect(updatedLabel(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(updatedLabel(now.subtract(const Duration(hours: 3, minutes: 10)), now), '3 h ago');
    // 2 days ago 12:35 UTC == 18:05 IST
    expect(updatedLabel(DateTime.utc(2026, 11, 11, 12, 35), now), '11 Nov, 18:05');
  });

  test('metaLine: "Ranked by ... · period · updated ..."', () {
    final now = DateTime.utc(2026, 11, 13, 6);
    const q = LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.daily);
    expect(
      metaLine(
        LeaderboardResult(
          query: q,
          entries: const [],
          metricLabel: 'Verified steps today',
          periodKey: '20261113',
          updatedAt: now.subtract(const Duration(minutes: 2)),
        ),
        now,
      ),
      'Ranked by Verified steps today · Fri 13 Nov · updated 2 min ago',
    );
    // No metricLabel / updatedAt from the server: still labelled.
    expect(
      metaLine(const LeaderboardResult(query: q, entries: []), now),
      'Ranked by Verified steps · Daily',
    );
  });
}
