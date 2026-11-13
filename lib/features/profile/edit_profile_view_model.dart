import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/functions/callables.dart';
import '../../data/profile/photo_services.dart';
import '../../domain/profile_enums.dart';
import '../../domain/user_profile.dart';
import '../../domain/validators.dart';

/// Weekday wire values of `availability` (Monday first).
const List<String> kWeekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// Fitness goals offered as chips (`goals` is a free string list on the
/// server, max 10 entries of at most 40 characters).
const List<String> kGoalOptions = [
  'Stay active',
  'Build stamina',
  'Lose weight',
  'Build muscle',
  'Meet workout partners',
  'Prepare for sports trials',
  'Reduce stress',
];

enum SaveOutcome { success, noChanges, invalid, failed }

/// Form state of the edit-profile screen. Only the permitted fields are
/// editable (never hostel, points, status, role or e-mail) and the result is
/// sent through the `updateProfile` callable - changed fields only.
class EditProfileViewModel extends ChangeNotifier {
  EditProfileViewModel({
    required UserProfile profile,
    required Callables callables,
    required PhotoPicker picker,
    required PhotoUploader uploader,
  })  : _profile = profile,
        _callables = callables,
        _picker = picker,
        _uploader = uploader,
        displayName = profile.displayName,
        bio = profile.bio,
        dailyGoalText = profile.dailyGoal.toString(),
        fitnessLevel = profile.fitnessLevel,
        sports = List.of(profile.sportsInterests),
        preferredActivity = profile.preferredActivity,
        preferredTime = profile.preferredTime,
        goals = List.of(profile.goals),
        availability = List.of(profile.availability),
        buddyType = profile.buddyType;

  final UserProfile _profile;
  final Callables _callables;
  final PhotoPicker _picker;
  final PhotoUploader _uploader;

  String displayName;
  String bio;
  String dailyGoalText;
  FitnessLevel? fitnessLevel;
  List<String> sports;
  String? preferredActivity;
  PreferredTime? preferredTime;
  List<String> goals;
  List<String> availability;
  BuddyType? buddyType;

  /// Local path of a newly picked photo (uploaded on save).
  String? pickedPhotoPath;
  bool removePhoto = false;

  bool _saving = false;
  String? _error;
  bool _disposed = false;

  bool get saving => _saving;

  /// Last save error (cleared on the next edit / save).
  String? get error => _error;

  bool get hasPhoto => !removePhoto && (pickedPhotoPath != null || (_profile.photoUrl ?? '').isNotEmpty);

  // --- validators (also used by the form fields) -----------------------------

  static String? validateName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your name';
    if (s.length < 2) return 'Name is too short';
    if (s.length > 50) return 'Name must be 50 characters or fewer';
    return null;
  }

  static String? validateBio(String? v) => Validators.bio(v);

  static String? validateDailyGoal(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'Enter a number of steps';
    if (n < kMinDailyGoal || n > kMaxDailyGoal) {
      return 'Choose between $kMinDailyGoal and $kMaxDailyGoal steps';
    }
    return null;
  }

  /// First problem with the current values, or `null` when everything is valid.
  String? get validationError =>
      validateName(displayName) ??
      validateBio(bio) ??
      validateDailyGoal(dailyGoalText) ??
      (fitnessLevel == null ? 'Choose your fitness level' : null) ??
      (sports.isEmpty ? 'Pick at least one sport' : null);

  // --- edits ---------------------------------------------------------------------

  void setDisplayName(String v) => _edit(() => displayName = v);
  void setBio(String v) => _edit(() => bio = v);
  void setDailyGoalText(String v) => _edit(() => dailyGoalText = v);
  void setFitnessLevel(FitnessLevel v) => _edit(() => fitnessLevel = v);
  void setPreferredActivity(String? v) => _edit(() => preferredActivity = v);
  void setPreferredTime(PreferredTime v) => _edit(() => preferredTime = v);
  void setBuddyType(BuddyType v) => _edit(() => buddyType = v);

  void toggleSport(String sport) => _edit(() => _toggle(sports, sport));
  void toggleGoal(String goal) => _edit(() => _toggle(goals, goal));
  void toggleDay(String day) => _edit(() => _toggle(availability, day));

  static void _toggle(List<String> list, String v) {
    if (!list.remove(v)) list.add(v);
  }

  void _edit(VoidCallback change) {
    change();
    _error = null;
    _notify();
  }

  /// Opens the gallery picker; a cancelled pick changes nothing.
  Future<void> pickPhoto() async {
    try {
      final path = await _picker.pickAvatar();
      if (path == null) return;
      _edit(() {
        pickedPhotoPath = path;
        removePhoto = false;
      });
    } catch (_) {
      _error = 'Could not open your photos.';
      _notify();
    }
  }

  void clearPhoto() => _edit(() {
        pickedPhotoPath = null;
        removePhoto = (_profile.photoUrl ?? '').isNotEmpty;
      });

  // --- save ----------------------------------------------------------------------

  static bool _sameSet(Iterable<String> a, Iterable<String> b) {
    final sa = a.toSet();
    final sb = b.toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }

  /// The fields that differ from the stored profile (photo excluded: it is
  /// resolved to a URL during [save]).
  Map<String, dynamic> buildChanges() {
    final c = <String, dynamic>{};
    final name = displayName.trim();
    if (name != _profile.displayName) c['displayName'] = name;
    final b = bio.trim();
    if (b != _profile.bio.trim()) c['bio'] = b;
    final goal = int.tryParse(dailyGoalText.trim());
    if (goal != null && goal != _profile.dailyGoal) c['dailyGoal'] = goal;
    if (fitnessLevel != null && fitnessLevel != _profile.fitnessLevel) {
      c['fitnessLevel'] = fitnessLevel!.wire;
    }
    if (!_sameSet(sports, _profile.sportsInterests)) c['sportsInterests'] = List.of(sports);
    if (preferredActivity != null && preferredActivity != _profile.preferredActivity) {
      c['preferredActivity'] = preferredActivity;
    }
    if (preferredTime != null && preferredTime != _profile.preferredTime) {
      c['preferredTime'] = preferredTime!.wire;
    }
    if (!_sameSet(goals, _profile.goals)) c['goals'] = List.of(goals);
    if (!_sameSet(availability, _profile.availability)) c['availability'] = List.of(availability);
    if (buddyType != null && buddyType != _profile.buddyType) c['buddyType'] = buddyType!.wire;
    return c;
  }

  bool get hasChanges => buildChanges().isNotEmpty || pickedPhotoPath != null || removePhoto;

  Future<SaveOutcome> save() async {
    if (_saving) return SaveOutcome.failed;
    final problem = validationError;
    if (problem != null) {
      _error = problem;
      _notify();
      return SaveOutcome.invalid;
    }
    final changes = buildChanges();
    if (changes.isEmpty && pickedPhotoPath == null && !removePhoto) {
      return SaveOutcome.noChanges;
    }
    _saving = true;
    _error = null;
    _notify();
    try {
      if (pickedPhotoPath != null) {
        try {
          changes['photoUrl'] = await _uploader.uploadAvatar(
            uid: _profile.uid,
            localPath: pickedPhotoPath!,
          );
        } catch (_) {
          _error = 'Could not upload your photo. Check your connection and try again.';
          return SaveOutcome.failed;
        }
      } else if (removePhoto) {
        changes['photoUrl'] = null;
      }
      await _callables.updateProfile(changes);
      return SaveOutcome.success;
    } on AppException catch (e) {
      _error = e.message;
      return SaveOutcome.failed;
    } catch (_) {
      _error = 'Something went wrong. Please try again.';
      return SaveOutcome.failed;
    } finally {
      _saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
