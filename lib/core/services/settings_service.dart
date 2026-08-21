import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/hive_keys.dart';

// ─────────────────────────────────────────────────────────
// SETTINGS SERVICE
// ─────────────────────────────────────────────────────────
class SettingsService {
  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  ThemeMode get themeMode {
    final stored = _prefs.getString(HiveKeys.themeMode);
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark; // default to dark
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final val = mode == ThemeMode.light ? 'light' : 'dark';
    await _prefs.setString(HiveKeys.themeMode, val);
  }

  int get dailyStepGoal =>
      _prefs.getInt(HiveKeys.dailyStepGoal) ?? 10000;

  Future<void> setDailyStepGoal(int goal) async =>
      _prefs.setInt(HiveKeys.dailyStepGoal, goal);

  bool get notificationsEnabled =>
      _prefs.getBool(HiveKeys.notificationsEnabled) ?? true;

  Future<void> setNotificationsEnabled(bool v) async =>
      _prefs.setBool(HiveKeys.notificationsEnabled, v);

  bool get demoModeEnabled =>
      _prefs.getBool(HiveKeys.demoMode) ?? false;

  Future<void> setDemoMode(bool v) async =>
      _prefs.setBool(HiveKeys.demoMode, v);

  DateTime? get lastSyncTime {
    final s = _prefs.getString(HiveKeys.lastSyncTime);
    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<void> updateLastSyncTime() async =>
      _prefs.setString(HiveKeys.lastSyncTime, DateTime.now().toIso8601String());
}

// ─────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────
final sharedPreferencesProvider =
    FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  // This is synchronous after the app starts
  throw UnimplementedError(
      'SharedPreferences must be initialized before this provider is used');
});

final settingsServiceAsyncProvider =
    FutureProvider<SettingsService>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return SettingsService(prefs);
});

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  return ThemeMode.dark;
});

final dailyStepGoalProvider = StateProvider<int>((ref) => 10000);

final demoModeProvider = StateProvider<bool>((ref) => false);

final lastSyncTimeProvider = StateProvider<DateTime?>((ref) => null);
