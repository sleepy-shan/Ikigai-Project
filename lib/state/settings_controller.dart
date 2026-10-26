import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/design_tokens.dart';
import 'providers.dart';

/// Theme preference persisted to localStorage.
enum ThemePreference { system, light, dark }

/// Loads/stores app-level preferences (theme + accent color).
class SettingsController extends Notifier<ThemePreference> {
  static const _themeKey = 'ikigai.theme';
  static const _legacyThemeKey = 'sandwich.theme';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  ThemePreference build() {
    final stored =
        _prefs.getString(_themeKey) ?? _prefs.getString(_legacyThemeKey);
    return ThemePreference.values.firstWhere(
      (p) => p.name == stored,
      orElse: () => ThemePreference.system,
    );
  }

  ThemeMode get themeMode => switch (state) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };

  Future<void> setThemePreference(ThemePreference preference) async {
    state = preference;
    await _prefs.setString(_themeKey, preference.name);
  }

  Future<void> toggleDark(bool isDark) =>
      setThemePreference(isDark ? ThemePreference.dark : ThemePreference.light);
}

/// Accent color preference, persisted separately so theme + color compose.
class AccentController extends Notifier<AppAccent> {
  static const _accentKey = 'ikigai.accent';
  static const _legacyAccentKey = 'sandwich.accent';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppAccent build() {
    final stored =
        _prefs.getString(_accentKey) ?? _prefs.getString(_legacyAccentKey);
    return AppAccent.fromName(stored);
  }

  Future<void> setAccent(AppAccent accent) async {
    state = accent;
    await _prefs.setString(_accentKey, accent.name);
  }
}

/// Whether the desktop sidebar is collapsed to icons. Starts collapsed; after
/// that it stays the way the user left it.
class SidebarController extends Notifier<bool> {
  static const _key = 'ikigai.sidebar.collapsed';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  bool build() => _prefs.getBool(_key) ?? true;

  Future<void> toggle() async {
    state = !state;
    await _prefs.setBool(_key, state);
  }
}

final sidebarCollapsedProvider = NotifierProvider<SidebarController, bool>(
  SidebarController.new,
);

final settingsControllerProvider =
    NotifierProvider<SettingsController, ThemePreference>(
      SettingsController.new,
    );

final accentControllerProvider = NotifierProvider<AccentController, AppAccent>(
  AccentController.new,
);

/// Convenience provider for widgets that only need the resolved ThemeMode.
///
/// Uses `select` so consumers rebuild only when the preference changes,
/// not on unrelated [ProviderScope] updates.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final preference = ref.watch(
    settingsControllerProvider.select((value) => value),
  );
  return switch (preference) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };
});
