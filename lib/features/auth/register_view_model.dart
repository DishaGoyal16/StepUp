import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/auth/auth_repository.dart';
import '../../data/firestore/hostel_repository.dart';
import '../../data/profile/photo_services.dart';
import '../../data/profile/profile_draft_store.dart';
import '../../domain/thapar_email.dart';
import '../onboarding/profile_form_controller.dart';

/// Two-step registration: (1) account, (2) profile answers.
///
/// Flow on [submit]: create the Auth account -> save the step-2 answers on the
/// device -> send the verification e-mail. The router then shows the
/// "Check your inbox" screen; after verification onboarding picks the saved
/// answers up and calls `createProfile`.
class RegisterViewModel extends ChangeNotifier {
  RegisterViewModel({
    required AuthRepository auth,
    required ProfileDraftStore draftStore,
    required HostelRepository hostels,
    required PhotoPicker photoPicker,
  })  : _auth = auth,
        _draftStore = draftStore,
        _hostels = hostels,
        _picker = photoPicker;

  final AuthRepository _auth;
  final ProfileDraftStore _draftStore;
  final HostelRepository _hostels;
  final PhotoPicker _picker;

  final ProfileFormController form = ProfileFormController();

  int _step = 0;
  bool _busy = false;
  String? _error;
  bool _disposed = false;
  bool _hostelsRequested = false;

  int get step => _step;
  bool get busy => _busy;
  String? get error => _error;

  void goToProfileStep() {
    _step = 1;
    _error = null;
    _notify();
    if (!_hostelsRequested) {
      _hostelsRequested = true;
      _hostels.load().then((d) {
        if (!_disposed) form.setDirectory(d);
      });
    }
  }

  void backToAccountStep() {
    _step = 0;
    _error = null;
    _notify();
  }

  Future<void> pickPhoto() async {
    try {
      final p = await _picker.pickAvatar();
      if (p != null) form.setPhoto(p);
    } catch (_) {
      _error = 'Could not open your photos.';
      _notify();
    }
  }

  /// Creates the account. Returns true when the account exists afterwards.
  Future<bool> submit({
    required String name,
    required String email,
    required String password,
  }) async {
    if (_busy) return false;
    _error = null;
    if (!ThaparEmail.isValid(email)) {
      _error = 'Only @thapar.edu email addresses can register.';
      _notify();
      return false;
    }
    if (!form.validate(includeName: false)) {
      _error = 'Please fix the highlighted answers.';
      _notify();
      return false;
    }
    _busy = true;
    _notify();
    try {
      final user = await _auth.register(email: email, password: password, displayName: name);
      final draft = form.draft.copyWith(displayName: name.trim());
      try {
        await _draftStore.save(user.uid, draft);
      } catch (_) {
        // Onboarding will simply ask again.
      }
      try {
        await _auth.sendVerificationEmail();
      } on AppException {
        // The verification screen offers "Resend".
      }
      return true;
    } on AppException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    form.dispose();
    super.dispose();
  }
}
