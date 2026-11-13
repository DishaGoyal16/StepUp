import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/profile_draft.dart';

/// Keeps the registration step-2 answers on the device between account
/// creation and the first verified login (nothing is sent to the server
/// until `createProfile`).
abstract class ProfileDraftStore {
  Future<ProfileDraft?> load(String uid);
  Future<void> save(String uid, ProfileDraft draft);
  Future<void> clear(String uid);
}

class SharedPrefsProfileDraftStore implements ProfileDraftStore {
  static String _key(String uid) => 'profile_draft_v1_$uid';

  @override
  Future<ProfileDraft?> load(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      if (raw == null) return null;
      return ProfileDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String uid, ProfileDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), jsonEncode(draft.toJson()));
  }

  @override
  Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }
}
