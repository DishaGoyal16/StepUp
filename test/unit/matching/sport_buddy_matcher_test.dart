import 'package:flutter_test/flutter_test.dart';
import 'package:thapar_stepup/features/sport_buddy/sport_buddy_matcher.dart';
import 'package:thapar_stepup/data/models/sport_models.dart';

void main() {
  // ─────────────────────────────────────────────────────────
  // Helper factories
  // ─────────────────────────────────────────────────────────
  SportProfile makeProfile({
    String userId = 'user_a',
    String sport = 'Badminton',
    String skillLevel = 'Intermediate',
    List<String> days = const ['Tue', 'Thu', 'Sat'],
    List<String> times = const ['6 PM – 8 PM'],
    String campusZone = 'Hostel Zone A',
    double reliability = 0.9,
    int groupMin = 2,
    int groupMax = 4,
  }) {
    return SportProfile(
      userId: userId,
      sport: sport,
      skillLevel: skillLevel,
      availableDays: days,
      availableTimes: times,
      groupSizeMin: groupMin,
      groupSizeMax: groupMax,
      campusZone: campusZone,
      reliabilityScore: reliability,
    );
  }

  // ─────────────────────────────────────────────────────────
  // HARD CONSTRAINT TESTS
  // ─────────────────────────────────────────────────────────
  group('Hard constraints — returns null on failure', () {
    test('different sport → no match', () {
      final seeker = makeProfile(sport: 'Badminton');
      final candidate = makeProfile(userId: 'user_b', sport: 'Cricket');

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Bob',
        candidateAvatarEmoji: '🏏',
        candidateDepartment: 'ME',
        candidateHostel: 'Lohitya',
      );

      expect(result, isNull);
    });

    test('skill gap > 1 level → no match', () {
      final seeker = makeProfile(skillLevel: 'Beginner');
      final candidate =
          makeProfile(userId: 'user_b', skillLevel: 'Advanced');

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Bob',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'ME',
        candidateHostel: 'Lohitya',
      );

      expect(result, isNull);
    });

    test('no shared time slots → no match', () {
      final seeker = makeProfile(times: ['Morning (6–8 AM)']);
      final candidate = makeProfile(
          userId: 'user_b', times: ['6 PM – 8 PM', 'Evening (8–10 PM)']);

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Bob',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'ME',
        candidateHostel: 'Lohitya',
      );

      expect(result, isNull);
    });

    test('no shared days → no match', () {
      final seeker = makeProfile(days: ['Mon', 'Wed']);
      final candidate =
          makeProfile(userId: 'user_b', days: ['Tue', 'Thu', 'Sat']);

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Bob',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'ME',
        candidateHostel: 'Lohitya',
      );

      expect(result, isNull);
    });

    test('incompatible group sizes → no match', () {
      final seeker =
          makeProfile(groupMin: 8, groupMax: 10); // wants large group
      final candidate = makeProfile(
          userId: 'user_b', groupMin: 2, groupMax: 4); // wants small group

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Bob',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'ME',
        candidateHostel: 'Lohitya',
      );

      expect(result, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────
  // SUCCESSFUL MATCH TESTS
  // ─────────────────────────────────────────────────────────
  group('Successful match — returns SportMatch', () {
    test('perfect match (same sport, skill, time, day, zone) has high score',
        () {
      final seeker = makeProfile();
      final candidate = makeProfile(userId: 'user_b');

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Alice',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'CSE',
        candidateHostel: 'KCB',
      );

      expect(result, isNotNull);
      expect(result!.matchScore, greaterThan(0.7));
      expect(result.matchReasons, isNotEmpty);
    });

    test('adjacent skill levels (Beginner vs Intermediate) produces a match',
        () {
      final seeker = makeProfile(skillLevel: 'Beginner');
      final candidate =
          makeProfile(userId: 'user_b', skillLevel: 'Intermediate');

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Alice',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'CSE',
        candidateHostel: 'KCB',
      );

      expect(result, isNotNull);
      expect(result!.skillFitScore, closeTo(0.75, 0.01));
    });

    test('different campus zones reduces but does not eliminate match score',
        () {
      final seeker = makeProfile(campusZone: 'Hostel Zone A');
      final candidate =
          makeProfile(userId: 'user_b', campusZone: 'Sports Complex');

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Alice',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'CSE',
        candidateHostel: 'KCB',
      );

      // Should still match (zone is soft factor)
      expect(result, isNotNull);
    });

    test('match score is in valid range 0.0–1.0', () {
      final seeker = makeProfile();
      final candidate = makeProfile(userId: 'user_b');

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Alice',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'CSE',
        candidateHostel: 'KCB',
      );

      expect(result, isNotNull);
      expect(result!.matchScore, greaterThanOrEqualTo(0.0));
      expect(result.matchScore, lessThanOrEqualTo(1.0));
    });

    test('matchPercent is integer 0–100', () {
      final seeker = makeProfile();
      final candidate = makeProfile(userId: 'user_b');

      final result = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: candidate,
        candidateName: 'Alice',
        candidateAvatarEmoji: '🏸',
        candidateDepartment: 'CSE',
        candidateHostel: 'KCB',
      );

      expect(result, isNotNull);
      expect(result!.matchPercent, greaterThanOrEqualTo(0));
      expect(result.matchPercent, lessThanOrEqualTo(100));
    });

    test('low reliability candidate has lower score than high reliability',
        () {
      final seeker = makeProfile();
      final highReliability =
          makeProfile(userId: 'high', reliability: 1.0);
      final lowReliability =
          makeProfile(userId: 'low', reliability: 0.3);

      final highResult = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: highReliability,
        candidateName: 'High',
        candidateAvatarEmoji: '⭐',
        candidateDepartment: 'CSE',
        candidateHostel: 'KCB',
      );
      final lowResult = SportBuddyMatcher.computeMatch(
        seeker: seeker,
        candidate: lowReliability,
        candidateName: 'Low',
        candidateAvatarEmoji: '😅',
        candidateDepartment: 'CSE',
        candidateHostel: 'KCB',
      );

      // Low reliability might still match but score should be lower
      if (lowResult != null && highResult != null) {
        expect(highResult.matchScore, greaterThan(lowResult.matchScore));
      }
    });
  });

  // ─────────────────────────────────────────────────────────
  // RANKING TESTS
  // ─────────────────────────────────────────────────────────
  group('SportBuddyMatcher.rank', () {
    test('rank sorts matches by score descending', () {
      final matches = [
        _makeMatch(id: 'low', score: 0.55),
        _makeMatch(id: 'high', score: 0.92),
        _makeMatch(id: 'mid', score: 0.73),
      ];

      final ranked = SportBuddyMatcher.rank(matches);

      expect(ranked[0].id, 'high');
      expect(ranked[1].id, 'mid');
      expect(ranked[2].id, 'low');
    });

    test('rank with single match returns list of one', () {
      final matches = [_makeMatch(id: 'only', score: 0.8)];
      final ranked = SportBuddyMatcher.rank(matches);
      expect(ranked.length, 1);
    });

    test('rank with empty list returns empty list', () {
      final ranked = SportBuddyMatcher.rank([]);
      expect(ranked, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────
  // RELIABILITY UPDATE TESTS
  // ─────────────────────────────────────────────────────────
  group('SportBuddyMatcher.updateReliability', () {
    test('attending session increases reliability', () {
      final updated =
          SportBuddyMatcher.updateReliability(0.5, true);
      expect(updated, greaterThan(0.5));
    });

    test('no-show decreases reliability', () {
      final updated =
          SportBuddyMatcher.updateReliability(0.9, false);
      expect(updated, lessThan(0.9));
    });

    test('result is always in valid range 0.0–1.0', () {
      final after10Noshow = List.generate(
          10,
          (i) =>
              SportBuddyMatcher.updateReliability(1.0 - i * 0.1, false))
          .last;
      expect(after10Noshow, greaterThanOrEqualTo(0.0));
      expect(after10Noshow, lessThanOrEqualTo(1.0));
    });
  });
}

// ─────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────
SportMatch _makeMatch({required String id, required double score}) {
  return SportMatch(
    id: id,
    userId: id,
    userName: id,
    avatarEmoji: '🏸',
    department: 'CSE',
    hostel: 'KCB',
    sport: 'Badminton',
    skillLevel: 'Intermediate',
    availableDays: const ['Tue'],
    availableTimes: const ['6 PM – 8 PM'],
    campusZone: 'Hostel Zone A',
    reliabilityScore: 0.9,
    matchScore: score,
    skillFitScore: 0.8,
    preferenceFitScore: 0.7,
    matchReasons: const ['Test match'],
    groupSizeMin: 2,
    groupSizeMax: 4,
  );
}
