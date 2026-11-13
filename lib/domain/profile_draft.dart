import 'profile_enums.dart';

/// The answers collected during registration (step 2) / onboarding, before
/// the profile exists on the server. Persisted locally so nothing is lost
/// between account creation and the first verified login.
class ProfileDraft {
  const ProfileDraft({
    this.displayName = '',
    this.hostelId,
    this.block = '',
    this.fitnessLevel,
    this.sportsInterests = const [],
    this.preferredActivity,
    this.preferredTime,
    this.buddyType,
    this.bio = '',
    this.photoLocalPath,
  });

  factory ProfileDraft.fromJson(Map<String, dynamic> j) => ProfileDraft(
        displayName: (j['displayName'] as String?) ?? '',
        hostelId: j['hostelId'] as String?,
        block: (j['block'] as String?) ?? '',
        fitnessLevel: FitnessLevel.fromWire(j['fitnessLevel']),
        sportsInterests: ((j['sportsInterests'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        preferredActivity: j['preferredActivity'] as String?,
        preferredTime: PreferredTime.fromWire(j['preferredTime']),
        buddyType: BuddyType.fromWire(j['buddyType']),
        bio: (j['bio'] as String?) ?? '',
        photoLocalPath: j['photoLocalPath'] as String?,
      );

  final String displayName;
  final String? hostelId;
  final String block;
  final FitnessLevel? fitnessLevel;
  final List<String> sportsInterests;
  final String? preferredActivity;
  final PreferredTime? preferredTime;
  final BuddyType? buddyType;
  final String bio;

  /// Local path of an optional chosen photo (uploaded after verification).
  final String? photoLocalPath;

  ProfileDraft copyWith({
    String? displayName,
    Object? hostelId = _unset,
    String? block,
    Object? fitnessLevel = _unset,
    List<String>? sportsInterests,
    Object? preferredActivity = _unset,
    Object? preferredTime = _unset,
    Object? buddyType = _unset,
    String? bio,
    Object? photoLocalPath = _unset,
  }) =>
      ProfileDraft(
        displayName: displayName ?? this.displayName,
        hostelId: identical(hostelId, _unset) ? this.hostelId : hostelId as String?,
        block: block ?? this.block,
        fitnessLevel: identical(fitnessLevel, _unset)
            ? this.fitnessLevel
            : fitnessLevel as FitnessLevel?,
        sportsInterests: sportsInterests ?? this.sportsInterests,
        preferredActivity: identical(preferredActivity, _unset)
            ? this.preferredActivity
            : preferredActivity as String?,
        preferredTime: identical(preferredTime, _unset)
            ? this.preferredTime
            : preferredTime as PreferredTime?,
        buddyType: identical(buddyType, _unset) ? this.buddyType : buddyType as BuddyType?,
        bio: bio ?? this.bio,
        photoLocalPath: identical(photoLocalPath, _unset)
            ? this.photoLocalPath
            : photoLocalPath as String?,
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'hostelId': hostelId,
        'block': block,
        'fitnessLevel': fitnessLevel?.wire,
        'sportsInterests': sportsInterests,
        'preferredActivity': preferredActivity,
        'preferredTime': preferredTime?.wire,
        'buddyType': buddyType?.wire,
        'bio': bio,
        'photoLocalPath': photoLocalPath,
      };

  /// True when every field the `createProfile` callable needs is present.
  bool get isComplete =>
      displayName.trim().length >= 2 &&
      hostelId != null &&
      fitnessLevel != null &&
      sportsInterests.isNotEmpty &&
      preferredActivity != null &&
      preferredTime != null &&
      buddyType != null &&
      bio.length <= kBioMaxLength;

  /// Payload for the `createProfile` callable. `photoUrl` is added by the
  /// caller after the optional upload.
  Map<String, dynamic> toCallablePayload({String? photoUrl}) => {
        'displayName': displayName.trim(),
        'hostelId': hostelId,
        if (block.trim().isNotEmpty) 'block': block.trim(),
        'fitnessLevel': fitnessLevel?.wire,
        'sportsInterests': sportsInterests,
        'preferredActivity': preferredActivity,
        'preferredTime': preferredTime?.wire,
        'buddyType': buddyType?.wire,
        'bio': bio.trim(),
        'goals': const <String>[],
        'availability': const <String>[],
        'photoUrl': ?photoUrl,
      };
}

const Object _unset = Object();
