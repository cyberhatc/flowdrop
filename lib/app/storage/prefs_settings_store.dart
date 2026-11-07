import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/settings.dart';

/// Settings persisted as a single JSON string in `shared_preferences`.
class PrefsSettingsStore implements SettingsStore {
  static const String _key = 'flowdrop.settings.v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<AppSettings> load() async {
    try {
      final raw = (await _instance).getString(_key);
      if (raw == null || raw.isEmpty) return const AppSettings();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromJson(decoded);
      }
    } on Object {
      // Corrupt settings fall back to defaults instead of blocking startup.
    }
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) async {
    await (await _instance).setString(_key, jsonEncode(settings.toJson()));
  }
}
