import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_theme_settings.dart';
import '../models/eq_preset.dart';

class AppStorage {
  AppStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _presetsKey = 'eq_presets_v1';
  static const _themeKey = 'app_theme_v1';

  final SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  Future<List<EqPreset?>> loadPresets() async {
    final raw = await _store.getString(_presetsKey);
    if (raw == null) return List<EqPreset?>.filled(8, null);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List<EqPreset?>.filled(8, null);
      return List<EqPreset?>.generate(8, (index) {
        if (index >= decoded.length || decoded[index] == null) return null;
        try {
          final item = decoded[index];
          if (item is! Map<String, dynamic>) return null;
          return EqPreset.fromJson(item);
        } on FormatException {
          return null;
        }
      });
    } on FormatException {
      return List<EqPreset?>.filled(8, null);
    }
  }

  Future<void> savePresets(List<EqPreset?> presets) async {
    if (presets.length != 8) {
      throw ArgumentError.value(
          presets.length, 'presets.length', 'Must be exactly 8');
    }
    await _store.setString(
      _presetsKey,
      jsonEncode(
          presets.map((preset) => preset?.toJson()).toList(growable: false)),
    );
  }

  Future<AppThemeSettings> loadTheme() async {
    final raw = await _store.getString(_themeKey);
    if (raw == null) return const AppThemeSettings();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? AppThemeSettings.fromJson(decoded)
          : const AppThemeSettings();
    } on FormatException {
      return const AppThemeSettings();
    }
  }

  Future<void> saveTheme(AppThemeSettings theme) =>
      _store.setString(_themeKey, jsonEncode(theme.toJson()));
}
