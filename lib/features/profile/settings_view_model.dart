import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../data/auth/auth_repository.dart';
import '../../data/functions/callables.dart';
import '../../data/functions/functions_client.dart';
import '../../domain/user_profile.dart';

/// Which map of the user document a switch belongs to.
enum SettingsGroup {
  notificationPrefs('notificationPrefs'),
  privacy('privacy');

  const SettingsGroup(this.field);

  /// The `updateProfile` field name.
  final String field;
}

/// Keys of `notificationPrefs` (all default to `true` on the server).
const List<String> kNotificationKeys = ['buddy', 'challenges', 'bets', 'leaderboard', 'reminders'];

/// Keys of `privacy` (all default to `true` on the server).
const List<String> kPrivacyKeys = ['discoverable', 'showHostel', 'showWeeklySteps', 'showOnLeaderboards'];

/// A one-shot message for a snackbar.
class SettingsFeedback {
  const SettingsFeedback(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

/// Settings logic: optimistic switches with rollback, password reset,
/// logout and the account-deletion REQUEST (processed by an admin).
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required Callables callables,
    required FunctionsClient functions,
    required AuthRepository auth,
    required Future<void> Function() signOut,
  })  : _callables = callables,
        _functions = functions,
        _auth = auth,
        _signOut = signOut;

  final Callables _callables;
  final FunctionsClient _functions;
  final AuthRepository _auth;
  final Future<void> Function() _signOut;

  /// Values the user toggled that the live profile may not show yet.
  final Map<SettingsGroup, Map<String, bool>> _overrides = {
    for (final g in SettingsGroup.values) g: <String, bool>{},
  };

  bool _resetting = false;
  bool _deleting = false;
  bool _loggingOut = false;
  bool _deletionRequested = false;
  bool _disposed = false;
  SettingsFeedback? _feedback;

  bool get resettingPassword => _resetting;
  bool get requestingDeletion => _deleting;
  bool get loggingOut => _loggingOut;

  /// Set after a successful `requestAccountDeletion` in this session.
  bool get deletionRequested => _deletionRequested;

  SettingsFeedback? takeFeedback() {
    final f = _feedback;
    _feedback = null;
    return f;
  }

  /// Current value of a switch: pending local choice, else the profile, else
  /// the server default (`true`).
  bool valueOf(UserProfile profile, SettingsGroup group, String key) {
    final local = _overrides[group]![key];
    if (local != null) return local;
    final stored = group == SettingsGroup.privacy ? profile.privacy : profile.notificationPrefs;
    return stored[key] ?? true;
  }

  /// Drops local choices the live profile has caught up with. Safe to call
  /// from `build` (it never notifies: [valueOf] gives the same answer before
  /// and after).
  void reconcile(UserProfile profile) {
    for (final g in SettingsGroup.values) {
      final stored = g == SettingsGroup.privacy ? profile.privacy : profile.notificationPrefs;
      _overrides[g]!.removeWhere((key, v) => stored[key] == v);
    }
  }

  /// Flips a switch immediately, saves it through `updateProfile`, and rolls
  /// it back (with an error message) if the server rejects it.
  Future<void> setSwitch(UserProfile profile, SettingsGroup group, String key, bool value) async {
    final previous = valueOf(profile, group, key);
    if (previous == value) return;
    _overrides[group]![key] = value;
    _notify();
    try {
      await _callables.updateProfile({
        group.field: {key: value},
      });
    } catch (e) {
      // Roll back only if nothing newer changed this switch meanwhile.
      if (_overrides[group]![key] == value) {
        _overrides[group]![key] = previous;
      }
      _feedback = SettingsFeedback(
        e is AppException ? e.message : 'Could not save that setting. Please try again.',
        isError: true,
      );
      _notify();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    if (_resetting) return;
    _resetting = true;
    _notify();
    try {
      await _auth.sendPasswordReset(email);
      _feedback = SettingsFeedback('Password reset email sent to $email.');
    } on AppException catch (e) {
      _feedback = SettingsFeedback(e.message, isError: true);
    } catch (_) {
      _feedback = const SettingsFeedback('Could not send the email. Please try again.', isError: true);
    } finally {
      _resetting = false;
      _notify();
    }
  }

  /// Asks the server to queue the account for deletion. It does NOT delete
  /// anything immediately: an admin processes the request.
  Future<bool> requestDeletion() async {
    if (_deleting) return false;
    _deleting = true;
    _notify();
    try {
      await _functions.call('requestAccountDeletion', const {});
      _deletionRequested = true;
      _feedback = const SettingsFeedback(
        'Deletion requested. An admin will review it; your account stays as is until then.',
      );
      return true;
    } on AppException catch (e) {
      _feedback = SettingsFeedback(e.message, isError: true);
      return false;
    } catch (_) {
      _feedback = const SettingsFeedback('Could not send the request. Please try again.', isError: true);
      return false;
    } finally {
      _deleting = false;
      _notify();
    }
  }

  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    _notify();
    try {
      await _signOut();
    } on AppException catch (e) {
      _feedback = SettingsFeedback(e.message, isError: true);
    } catch (_) {
      _feedback = const SettingsFeedback('Could not log out. Please try again.', isError: true);
    } finally {
      _loggingOut = false;
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
