import 'package:flutter/foundation.dart';

import '../../domain/hostel.dart';
import '../../domain/profile_draft.dart';
import '../../domain/profile_enums.dart';
import '../../domain/validators.dart';

/// State + validation of the profile questionnaire shared by registration
/// step 2 and the onboarding screen.
class ProfileFormController extends ChangeNotifier {
  ProfileFormController({ProfileDraft initial = const ProfileDraft(), HostelDirectory? directory})
      : _draft = initial,
        _directory = directory;

  ProfileDraft _draft;
  HostelDirectory? _directory;
  bool _showErrors = false;

  ProfileDraft get draft => _draft;
  HostelDirectory? get directory => _directory;
  bool get showErrors => _showErrors;

  Hostel? get selectedHostel => _directory?.byId(_draft.hostelId);

  void setDirectory(HostelDirectory d) {
    _directory = d;
    // A saved hostel that is no longer active must be re-selected.
    if (_draft.hostelId != null && !d.isFallback && d.byId(_draft.hostelId) == null) {
      _draft = _draft.copyWith(hostelId: null);
    }
    notifyListeners();
  }

  void _update(ProfileDraft d) {
    _draft = d;
    notifyListeners();
  }

  void setName(String v) => _update(_draft.copyWith(displayName: v));

  void setHostel(String? id) {
    final h = _directory?.byId(id);
    _update(_draft.copyWith(hostelId: id, block: h?.block ?? ''));
  }

  void setBlock(String v) => _update(_draft.copyWith(block: v));
  void setFitness(FitnessLevel v) => _update(_draft.copyWith(fitnessLevel: v));

  void toggleSport(String sport) {
    final list = [..._draft.sportsInterests];
    list.contains(sport) ? list.remove(sport) : list.add(sport);
    _update(_draft.copyWith(sportsInterests: list));
  }

  void setPreferredActivity(String? v) => _update(_draft.copyWith(preferredActivity: v));
  void setPreferredTime(PreferredTime v) => _update(_draft.copyWith(preferredTime: v));
  void setBuddyType(BuddyType v) => _update(_draft.copyWith(buddyType: v));
  void setBio(String v) => _update(_draft.copyWith(bio: v));
  void setPhoto(String? path) => _update(_draft.copyWith(photoLocalPath: path));

  /// Error message for [field] (or null when valid). Fields: `name`,
  /// `hostel`, `fitness`, `sports`, `activity`, `time`, `buddy`, `bio`.
  String? errorFor(String field, {bool includeName = true}) {
    switch (field) {
      case 'name':
        return includeName ? Validators.fullName(_draft.displayName) : null;
      case 'hostel':
        return Validators.required(_draft.hostelId, 'Choose your hostel');
      case 'fitness':
        return Validators.required(_draft.fitnessLevel, 'Choose your fitness level');
      case 'sports':
        return Validators.required(_draft.sportsInterests, 'Pick at least one sport');
      case 'activity':
        return Validators.required(_draft.preferredActivity, 'Choose a preferred activity');
      case 'time':
        return Validators.required(_draft.preferredTime, 'Choose a preferred time');
      case 'buddy':
        return Validators.required(_draft.buddyType, 'Choose a buddy type');
      case 'bio':
        return Validators.bio(_draft.bio);
    }
    return null;
  }

  static const List<String> fields = [
    'name', 'hostel', 'fitness', 'sports', 'activity', 'time', 'buddy', 'bio',
  ];

  /// Shows inline errors and returns true when the form is valid.
  bool validate({bool includeName = true}) {
    _showErrors = true;
    notifyListeners();
    return fields.every((f) => errorFor(f, includeName: includeName) == null);
  }

  /// Replace everything (used after loading a saved draft).
  void load(ProfileDraft d) => _update(d);
}
