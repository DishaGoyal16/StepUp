import 'dart:math' as math;
import '../../data/models/sport_models.dart';
import '../../core/constants/app_constants.dart';

// ─────────────────────────────────────────────────────────
// SPORT BUDDY MATCHING ENGINE
// ─────────────────────────────────────────────────────────
/// Constraint-based weighted matching.
/// Match Score = w1 × skillFit + w2 × reliability + w3 × preferenceFit
/// Hard constraints are checked first; any failure = score 0.
class SportBuddyMatcher {
  static const double _wSkill = AppConstants.matchWeightSkill;
  static const double _wReliability = AppConstants.matchWeightReliability;
  static const double _wPreference = AppConstants.matchWeightPreference;

  /// Compute a SportMatch between the seeker and a candidate.
  /// Returns null if any hard constraint fails.
  static SportMatch? computeMatch({
    required SportProfile seeker,
    required SportProfile candidate,
    required String candidateName,
    required String candidateAvatarEmoji,
    required String candidateDepartment,
    required String candidateHostel,
  }) {
    final reasons = <String>[];
    final mismatches = <String>[];

    // ── Hard constraint 1: same sport ─────────────────────
    if (seeker.sport != candidate.sport) return null;
    reasons.add('Same sport: ${seeker.sport}');

    // ── Hard constraint 2: skill compatibility ────────────
    final skillFit = _skillFit(seeker.skillLevel, candidate.skillLevel);
    if (skillFit == 0) {
      return null; // too far apart
    }
    if (skillFit >= 0.8) {
      reasons.add('Compatible skill level');
    } else {
      mismatches.add('Slight skill gap');
    }

    // ── Hard constraint 3: time overlap ───────────────────
    final timeOverlap =
        _timeOverlap(seeker.availableTimes, candidate.availableTimes);
    if (timeOverlap == 0) return null; // no shared time
    if (timeOverlap > 0.6) {
      reasons.add('Good time overlap');
    } else {
      reasons.add('Partial time overlap');
    }

    // ── Hard constraint 4: day overlap ────────────────────
    final dayOverlap =
        _dayOverlap(seeker.availableDays, candidate.availableDays);
    if (dayOverlap == 0) return null;
    if (dayOverlap > 0.5) {
      reasons.add('Matching available days');
    }

    // ── Hard constraint 5: group size compatibility ───────
    final groupFit = _groupFit(
      seekerMin: seeker.groupSizeMin,
      seekerMax: seeker.groupSizeMax,
      candidateMin: candidate.groupSizeMin,
      candidateMax: candidate.groupSizeMax,
    );
    if (groupFit == 0) return null;
    if (groupFit > 0.7) reasons.add('Compatible group size');

    // ── Soft factor: campus zone ───────────────────────────
    final zoneFit = seeker.campusZone == candidate.campusZone ? 1.0 : 0.6;
    if (zoneFit >= 1.0) {
      reasons.add('Same campus zone');
    } else {
      reasons.add('Nearby campus zone');
    }

    // ── Soft factor: reliability ───────────────────────────
    final reliability = candidate.reliabilityScore;
    if (reliability >= 0.9) {
      reasons.add('${(reliability * 100).round()}% reliability score');
    } else if (reliability >= 0.7) {
      reasons.add('Decent reliability');
    } else {
      mismatches.add('Lower reliability score');
    }

    // ── Preference fit (composite) ─────────────────────────
    final preferenceFit =
        (timeOverlap * 0.4 + dayOverlap * 0.3 + groupFit * 0.2 + zoneFit * 0.1);

    // ── Final score ────────────────────────────────────────
    final score = (_wSkill * skillFit) +
        (_wReliability * reliability) +
        (_wPreference * preferenceFit);

    if (score < AppConstants.minMatchScoreToShow) return null;

    final id = '${seeker.userId}_${candidate.userId}_${seeker.sport}';

    return SportMatch(
      id: id,
      userId: candidate.userId,
      userName: candidateName,
      avatarEmoji: candidateAvatarEmoji,
      department: candidateDepartment,
      hostel: candidateHostel,
      sport: candidate.sport,
      skillLevel: candidate.skillLevel,
      availableDays: candidate.availableDays,
      availableTimes: candidate.availableTimes,
      campusZone: candidate.campusZone,
      reliabilityScore: reliability,
      matchScore: score.clamp(0.0, 1.0),
      skillFitScore: skillFit,
      preferenceFitScore: preferenceFit,
      matchReasons: reasons,
      mismatchReasons: mismatches,
      groupSizeMin: candidate.groupSizeMin,
      groupSizeMax: candidate.groupSizeMax,
    );
  }

  /// Sort a list of matches by score descending.
  static List<SportMatch> rank(List<SportMatch> matches) {
    final sorted = [...matches]
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return sorted;
  }

  // ── Helpers ───────────────────────────────────────────────
  static double _skillFit(String a, String b) {
    const order = ['Beginner', 'Intermediate', 'Advanced', 'Pro'];
    final ia = order.indexOf(a);
    final ib = order.indexOf(b);
    if (ia < 0 || ib < 0) return 0;
    final diff = (ia - ib).abs();
    if (diff == 0) return 1.0;
    if (diff == 1) return 0.75;
    return 0.0; // more than 1 level apart → hard constraint fail
  }

  static double _timeOverlap(List<String> a, List<String> b) {
    final shared = a.toSet().intersection(b.toSet());
    final union = a.toSet().union(b.toSet());
    if (union.isEmpty) return 0;
    return shared.length / union.length;
  }

  static double _dayOverlap(List<String> a, List<String> b) {
    final shared = a.toSet().intersection(b.toSet());
    final union = a.toSet().union(b.toSet());
    if (union.isEmpty) return 0;
    return shared.length / union.length;
  }

  static double _groupFit({
    required int seekerMin,
    required int seekerMax,
    required int candidateMin,
    required int candidateMax,
  }) {
    // Overlap of ranges
    final overlapMin = math.max(seekerMin, candidateMin);
    final overlapMax = math.min(seekerMax, candidateMax);
    if (overlapMin > overlapMax) return 0.0;
    final overlapSize = overlapMax - overlapMin + 1;
    final totalRange = math.max(seekerMax, candidateMax) -
        math.min(seekerMin, candidateMin) +
        1;
    return overlapSize / totalRange;
  }

  /// Update reliability using exponential moving average.
  static double updateReliability(double oldScore, bool attended) {
    const alpha = AppConstants.reliabilityAlpha;
    final outcome = attended ? 1.0 : 0.0;
    return alpha * oldScore + (1 - alpha) * outcome;
  }
}
