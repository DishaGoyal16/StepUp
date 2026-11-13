import '../../domain/profile_enums.dart';

/// How the signed-in student relates to another student (`searchBuddies`
/// `relation`).
enum BuddyRelation {
  none('NONE'),
  requestSent('REQUEST_SENT'),
  requestReceived('REQUEST_RECEIVED'),
  buddy('BUDDY');

  const BuddyRelation(this.wire);
  final String wire;

  static BuddyRelation fromWire(Object? v) {
    for (final r in values) {
      if (r.wire == v) return r;
    }
    return BuddyRelation.none;
  }
}

/// Reasons accepted by the `reportProfile` callable.
enum ReportReason {
  spam('SPAM', 'Spam'),
  harassment('HARASSMENT', 'Harassment or bullying'),
  fakeProfile('FAKE_PROFILE', 'Fake profile'),
  inappropriate('INAPPROPRIATE', 'Inappropriate content'),
  other('OTHER', 'Something else');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;
}

List<String> _strings(Object? v) =>
    v is List ? [for (final e in v) if (e is String && e.isNotEmpty) e] : const <String>[];

/// The public side of another student, as returned by `searchBuddies`
/// (`publicProfiles/{uid}` + `uid` + `relation`). It deliberately has no
/// e-mail and no location field: the backend never sends them and this
/// mapper would ignore them anyway.
class BuddyProfile {
  const BuddyProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.hostelId,
    this.fitnessLevel,
    this.sportsInterests = const [],
    this.preferredActivity,
    this.preferredTime,
    this.goals = const [],
    this.availability = const [],
    this.buddyType,
    this.bio = '',
    this.weeklyVerifiedSteps,
    this.relation = BuddyRelation.none,
    this.requestId,
  });

  /// Returns null when the map has no usable `uid`.
  static BuddyProfile? tryFromMap(Map<String, dynamic> m) {
    final uid = m['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final name = m['displayName'];
    final activity = m['preferredActivity'];
    final photo = m['photoUrl'];
    final hostel = m['hostelId'];
    final bio = m['bio'];
    final steps = m['weeklyVerifiedSteps'];
    final requestId = m['requestId'];
    return BuddyProfile(
      uid: uid,
      displayName: (name is String && name.trim().isNotEmpty) ? name.trim() : 'Student',
      photoUrl: (photo is String && photo.isNotEmpty) ? photo : null,
      hostelId: (hostel is String && hostel.isNotEmpty) ? hostel : null,
      fitnessLevel: FitnessLevel.fromWire(m['fitnessLevel']),
      sportsInterests: _strings(m['sportsInterests']),
      preferredActivity: (activity is String && activity.isNotEmpty) ? activity : null,
      preferredTime: PreferredTime.fromWire(m['preferredTime']),
      goals: _strings(m['goals']),
      availability: _strings(m['availability']),
      buddyType: BuddyType.fromWire(m['buddyType']),
      bio: bio is String ? bio : '',
      weeklyVerifiedSteps: steps is num ? steps.toInt() : null,
      relation: BuddyRelation.fromWire(m['relation']),
      requestId: (requestId is String && requestId.isNotEmpty) ? requestId : null,
    );
  }

  final String uid;
  final String displayName;
  final String? photoUrl;

  /// Present only when the student shares their hostel.
  final String? hostelId;
  final FitnessLevel? fitnessLevel;
  final List<String> sportsInterests;
  final String? preferredActivity;
  final PreferredTime? preferredTime;
  final List<String> goals;

  /// Weekdays, `MON`..`SUN`.
  final List<String> availability;
  final BuddyType? buddyType;
  final String bio;

  /// Present only when the student shares weekly verified steps.
  final int? weeklyVerifiedSteps;
  final BuddyRelation relation;

  /// Id of the pending request when [relation] is sent/received (when known).
  final String? requestId;

  BuddyProfile withRelation(BuddyRelation next, {String? requestId}) => BuddyProfile(
        uid: uid,
        displayName: displayName,
        photoUrl: photoUrl,
        hostelId: hostelId,
        fitnessLevel: fitnessLevel,
        sportsInterests: sportsInterests,
        preferredActivity: preferredActivity,
        preferredTime: preferredTime,
        goals: goals,
        availability: availability,
        buddyType: buddyType,
        bio: bio,
        weeklyVerifiedSteps: weeklyVerifiedSteps,
        relation: next,
        requestId: requestId,
      );

  /// The deterministic `buddyRequests` document id of the pending request
  /// between [myUid] and this student (`{fromUid}_{toUid}`).
  String? pendingRequestId(String myUid) {
    if (requestId != null) return requestId;
    return switch (relation) {
      BuddyRelation.requestSent => '${myUid}_$uid',
      BuddyRelation.requestReceived => '${uid}_$myUid',
      _ => null,
    };
  }
}

/// A pending buddy request seen from the signed-in student.
class BuddyRequest {
  const BuddyRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.incoming,
    required this.otherName,
    this.otherPhotoUrl,
    this.message = '',
    this.createdAt,
  });

  /// Maps a `buddyRequests` document. [otherName]/[otherPhotoUrl] describe the
  /// other student (for incoming requests the document itself carries them in
  /// `fromName`/`fromPhotoUrl`; for outgoing ones they come from the recipient's
  /// public profile). Returns null for malformed documents.
  static BuddyRequest? tryFromMap(
    String id,
    Map<String, dynamic> m, {
    required String myUid,
    String? otherName,
    String? otherPhotoUrl,
  }) {
    final from = m['fromUid'];
    final to = m['toUid'];
    if (from is! String || to is! String) return null;
    final incoming = to == myUid;
    if (!incoming && from != myUid) return null;
    final created = m['createdAt'];
    DateTime? createdAt;
    if (created is DateTime) {
      createdAt = created;
    } else if (created != null) {
      // Firestore Timestamp (has toDate()) - kept dynamic so this file stays
      // free of Firebase types.
      try {
        createdAt = (created as dynamic).toDate() as DateTime;
      } catch (_) {
        createdAt = null;
      }
    }
    final fromName = m['fromName'];
    final fromPhoto = m['fromPhotoUrl'];
    String name;
    String? photo;
    if (incoming) {
      name = (fromName is String && fromName.trim().isNotEmpty) ? fromName.trim() : 'Student';
      photo = (fromPhoto is String && fromPhoto.isNotEmpty) ? fromPhoto : null;
    } else {
      name = (otherName != null && otherName.trim().isNotEmpty) ? otherName.trim() : 'Student';
      photo = (otherPhotoUrl != null && otherPhotoUrl.isNotEmpty) ? otherPhotoUrl : null;
    }
    final message = m['message'];
    return BuddyRequest(
      id: id,
      fromUid: from,
      toUid: to,
      incoming: incoming,
      otherName: name,
      otherPhotoUrl: photo,
      message: message is String ? message.trim() : '',
      createdAt: createdAt,
    );
  }

  final String id;
  final String fromUid;
  final String toUid;

  /// True when the signed-in student is the recipient.
  final bool incoming;
  final String otherName;
  final String? otherPhotoUrl;
  final String message;
  final DateTime? createdAt;

  String get otherUid => incoming ? fromUid : toUid;
}

/// The filters of the Buddy Finder. Immutable; every setter returns a copy.
class BuddyFilters {
  const BuddyFilters({
    this.query = '',
    this.fitnessLevel,
    this.sports = const {},
    this.hostelId,
    this.preferredTime,
    this.goals = const {},
    this.availability = const {},
    this.buddyType,
  });

  static const BuddyFilters empty = BuddyFilters();

  /// The `searchBuddies` name filter accepts at most this many characters.
  static const int maxQueryLength = 60;

  /// Filter values the finder offers (Individual / Group only, as specified).
  static const List<BuddyType> buddyTypeOptions = [BuddyType.individual, BuddyType.group];

  /// Goal presets (profiles store goals as free text; these are the ones the
  /// finder can match on).
  static const List<String> goalOptions = [
    'Stay active',
    'Lose weight',
    'Build stamina',
    'Gain muscle',
    'Compete',
    'Make friends',
  ];

  static const List<String> weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  final String query;
  final FitnessLevel? fitnessLevel;
  final Set<String> sports;
  final String? hostelId;
  final PreferredTime? preferredTime;
  final Set<String> goals;
  final Set<String> availability;
  final BuddyType? buddyType;

  static const Object _keep = Object();

  BuddyFilters copyWith({
    String? query,
    Object? fitnessLevel = _keep,
    Set<String>? sports,
    Object? hostelId = _keep,
    Object? preferredTime = _keep,
    Set<String>? goals,
    Set<String>? availability,
    Object? buddyType = _keep,
  }) =>
      BuddyFilters(
        query: query ?? this.query,
        fitnessLevel: identical(fitnessLevel, _keep) ? this.fitnessLevel : fitnessLevel as FitnessLevel?,
        sports: sports ?? this.sports,
        hostelId: identical(hostelId, _keep) ? this.hostelId : hostelId as String?,
        preferredTime:
            identical(preferredTime, _keep) ? this.preferredTime : preferredTime as PreferredTime?,
        goals: goals ?? this.goals,
        availability: availability ?? this.availability,
        buddyType: identical(buddyType, _keep) ? this.buddyType : buddyType as BuddyType?,
      );

  /// Number of non-text filters in use.
  int get activeCount =>
      (fitnessLevel != null ? 1 : 0) +
      (sports.isNotEmpty ? 1 : 0) +
      (hostelId != null ? 1 : 0) +
      (preferredTime != null ? 1 : 0) +
      (goals.isNotEmpty ? 1 : 0) +
      (availability.isNotEmpty ? 1 : 0) +
      (buddyType != null ? 1 : 0);

  bool get hasAny => activeCount > 0 || query.trim().isNotEmpty;

  /// The same filters without the text query.
  BuddyFilters get withoutQuery => copyWith(query: '');

  /// The `searchBuddies` parameters. Only filters in use are sent.
  Map<String, dynamic> toParams({int? limit, String? cursor}) {
    var q = query.trim();
    if (q.length > maxQueryLength) q = q.substring(0, maxQueryLength);
    final order = weekdays;
    return {
      if (fitnessLevel != null) 'fitnessLevel': fitnessLevel!.wire,
      if (sports.isNotEmpty) 'sports': sports.toList()..sort(),
      if (hostelId != null) 'hostelId': hostelId,
      if (preferredTime != null) 'preferredTime': preferredTime!.wire,
      if (goals.isNotEmpty) 'goals': goals.toList()..sort(),
      if (availability.isNotEmpty)
        'availability': (availability.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)))),
      if (buddyType != null) 'buddyType': buddyType!.wire,
      if (q.isNotEmpty) 'query': q,
      'limit': ?limit,
      'cursor': ?cursor,
    };
  }
}

/// One page of `searchBuddies` results.
class BuddySearchPage {
  const BuddySearchPage({required this.profiles, this.nextCursor});

  final List<BuddyProfile> profiles;

  /// Null when there is nothing more to load.
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
