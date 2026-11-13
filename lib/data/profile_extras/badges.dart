/// Badge catalogue (`adminSettings/badges`) merged with the user's
/// `achievements`. Badges are awarded ONLY by Cloud Functions; the client just
/// shows which ones exist and which are earned.
library;

/// One badge definition: `adminSettings/badges.<badgeId>`.
class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.rule = '',
    this.points = 0,
  });

  final String id;
  final String title;

  /// Plain-language "how to earn it".
  final String description;

  /// Material icon name (e.g. `directions_walk`); mapped to an icon in the UI.
  final String icon;

  /// Machine-oriented rule text from the backend (not shown as the primary
  /// "how to earn"; [description] is).
  final String rule;
  final int points;

  /// Text shown on a locked badge.
  String get howToEarn => description.isNotEmpty ? description : rule;

  BadgeDefinition _overlay(Map<String, dynamic> m) => BadgeDefinition(
        id: id,
        title: _nonEmpty(m['title']) ?? title,
        description: _nonEmpty(m['description']) ?? description,
        icon: _nonEmpty(m['icon']) ?? icon,
        rule: _nonEmpty(m['rule']) ?? rule,
        points: (m['points'] as num?)?.toInt() ?? points,
      );
}

String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

/// The six badge ids defined by the backend (`functions/src/seed/badges.ts`),
/// in display order. This is reference data for the layout only: the live
/// `adminSettings/badges` document overrides every field, and a badge is only
/// ever "earned" when a server-written `achievements` document exists.
const List<BadgeDefinition> kKnownBadges = [
  BadgeDefinition(
    id: 'FIRST_1K',
    title: 'First 1K',
    description: 'Walk your first 1,000 verified steps.',
    icon: 'directions_walk',
    points: 10,
  ),
  BadgeDefinition(
    id: 'TEN_K_WALKER',
    title: '10K Walker',
    description: 'Reach 10,000 verified steps in a single day.',
    icon: 'emoji_events',
    points: 20,
  ),
  BadgeDefinition(
    id: 'STREAK_7',
    title: '7-Day Streak',
    description: 'Hit your daily goal 7 days in a row.',
    icon: 'local_fire_department',
  ),
  BadgeDefinition(
    id: 'CHALLENGE_CHAMPION',
    title: 'Challenge Champion',
    description: 'Win a buddy or campus challenge.',
    icon: 'military_tech',
    points: 25,
  ),
  BadgeDefinition(
    id: 'HOSTEL_CHAMPION',
    title: 'Hostel Champion',
    description: 'Your hostel won an inter-hostel challenge.',
    icon: 'apartment',
    points: 25,
  ),
  BadgeDefinition(
    id: 'CAMPUS_FITNESS_STAR',
    title: 'Campus Fitness Star',
    description: 'Finish first in a campus-wide challenge.',
    icon: 'star',
    points: 50,
  ),
];

/// Builds the catalogue: the known badges (in order), each overlaid by the
/// matching entry of the `adminSettings/badges` document [doc], followed by
/// any extra badge ids that only exist in [doc]. Non-map values of the
/// document (e.g. `updatedAt`) are ignored.
List<BadgeDefinition> buildBadgeCatalogue(Map<String, dynamic>? doc) {
  final source = doc ?? const <String, dynamic>{};
  final out = <BadgeDefinition>[];
  final seen = <String>{};
  for (final known in kKnownBadges) {
    seen.add(known.id);
    final entry = source[known.id];
    out.add(entry is Map ? known._overlay(entry.cast<String, dynamic>()) : known);
  }
  final extraIds = source.keys.where((k) => !seen.contains(k) && source[k] is Map).toList()..sort();
  for (final id in extraIds) {
    final m = (source[id] as Map).cast<String, dynamic>();
    out.add(
      BadgeDefinition(id: id, title: prettifyBadgeId(id), description: '', icon: '')._overlay(m),
    );
  }
  return out;
}

/// `CAMPUS_FITNESS_STAR` -> `Campus Fitness Star`.
String prettifyBadgeId(String id) => id
    .split('_')
    .where((p) => p.isNotEmpty)
    .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
    .join(' ');

/// `achievements/{uid}_{badgeId}` (server-written).
class Achievement {
  const Achievement({required this.badgeId, this.awardedAt, this.refId});

  factory Achievement.fromMap(Map<String, dynamic> m) {
    final at = m['awardedAt'];
    return Achievement(
      badgeId: (m['badgeId'] as String?) ?? '',
      awardedAt: at is DateTime
          ? at.toUtc()
          : at is num
              ? DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true)
              : null,
      refId: m['refId'] as String?,
    );
  }

  final String badgeId;
  final DateTime? awardedAt;
  final String? refId;
}

/// A catalogue badge with its earned state for this user.
class BadgeStatus {
  const BadgeStatus({required this.definition, required this.earned, this.awardedAt});

  final BadgeDefinition definition;
  final bool earned;
  final DateTime? awardedAt;
}

/// Merges [catalogue] with the user's [achievements]: earned badges first
/// (catalogue order), then locked ones. An achievement whose id is not in the
/// catalogue is still shown (as earned) with a prettified title.
List<BadgeStatus> mergeBadgeStatus(List<BadgeDefinition> catalogue, List<Achievement> achievements) {
  final earnedById = <String, Achievement>{};
  for (final a in achievements) {
    if (a.badgeId.isNotEmpty) earnedById[a.badgeId] = a;
  }
  final earned = <BadgeStatus>[];
  final locked = <BadgeStatus>[];
  final known = <String>{};
  for (final def in catalogue) {
    known.add(def.id);
    final a = earnedById[def.id];
    if (a != null) {
      earned.add(BadgeStatus(definition: def, earned: true, awardedAt: a.awardedAt));
    } else {
      locked.add(BadgeStatus(definition: def, earned: false));
    }
  }
  for (final a in earnedById.values) {
    if (known.contains(a.badgeId)) continue;
    earned.add(
      BadgeStatus(
        definition: BadgeDefinition(
          id: a.badgeId,
          title: prettifyBadgeId(a.badgeId),
          description: '',
          icon: '',
        ),
        earned: true,
        awardedAt: a.awardedAt,
      ),
    );
  }
  return [...earned, ...locked];
}
