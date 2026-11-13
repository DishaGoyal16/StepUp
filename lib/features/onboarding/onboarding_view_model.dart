import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/firestore/hostel_repository.dart';
import '../../data/profile/photo_services.dart';
import '../../data/profile/profile_draft_store.dart';
import '../../data/profile/profile_repository.dart';
import '../../domain/auth_state.dart';
import '../../domain/profile_draft.dart';
import 'profile_form_controller.dart';

/// Collects the profile fields that are not saved on the server yet (using
/// the answers saved during registration when available) and calls
/// `createProfile`.
class OnboardingViewModel extends ChangeNotifier {
  OnboardingViewModel({
    required this.user,
    required ProfileRepository profiles,
    required ProfileDraftStore draftStore,
    required HostelRepository hostels,
    required PhotoUploader photoUploader,
    required PhotoPicker photoPicker,
  })  : _profiles = profiles,
        _draftStore = draftStore,
        _hostels = hostels,
        _uploader = photoUploader,
        _picker = photoPicker;

  final AuthUser user;
  final ProfileRepository _profiles;
  final ProfileDraftStore _draftStore;
  final HostelRepository _hostels;
  final PhotoUploader _uploader;
  final PhotoPicker _picker;

  final ProfileFormController form = ProfileFormController();

  bool _loading = true;
  bool _busy = false;
  bool _done = false;
  String? _error;
  String? _notice;
  bool _disposed = false;

  bool get loading => _loading;
  bool get busy => _busy;
  bool get done => _done;
  String? get error => _error;

  /// Non-blocking information (e.g. the photo could not be uploaded).
  String? get notice => _notice;

  /// True when answers saved during registration were found.
  bool restoredDraft = false;

  Future<void> load() async {
    final saved = await _draftStore.load(user.uid);
    restoredDraft = saved != null;
    var draft = saved ?? const ProfileDraft();
    if (draft.displayName.trim().isEmpty) {
      draft = draft.copyWith(displayName: user.displayName ?? '');
    }
    form.load(draft);
    final dir = await _hostels.load();
    form.setDirectory(dir);
    _loading = false;
    _safeNotify();
  }

  Future<void> pickPhoto() async {
    try {
      final path = await _picker.pickAvatar();
      if (path != null) form.setPhoto(path);
    } catch (_) {
      _error = 'Could not open your photos.';
      _safeNotify();
    }
  }

  /// Returns true when the profile exists afterwards.
  Future<bool> submit() async {
    if (_busy) return false;
    _error = null;
    _notice = null;
    if (!form.validate()) {
      _error = 'Please fix the highlighted answers.';
      _safeNotify();
      return false;
    }
    _busy = true;
    _safeNotify();
    final draft = form.draft;
    try {
      await _draftStore.save(user.uid, draft);

      String? photoUrl;
      final path = draft.photoLocalPath;
      if (path != null) {
        try {
          photoUrl = await _uploader.uploadAvatar(uid: user.uid, localPath: path);
        } catch (_) {
          _notice = 'Your photo could not be uploaded. You can add it later from your profile.';
        }
      }

      try {
        await _profiles.createProfile(draft, photoUrl: photoUrl);
      } on AppException catch (e) {
        // `createProfile` is idempotent: an existing profile is success.
        if (e.code != 'already-exists') rethrow;
      }
      await _draftStore.clear(user.uid);
      _done = true;
      return true;
    } on AppException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Could not save your profile. Check your connection and try again.';
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    form.dispose();
    super.dispose();
  }
}
