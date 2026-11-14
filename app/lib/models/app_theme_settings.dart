import 'package:flutter/material.dart';

@immutable
class AppThemeSettings {
  const AppThemeSettings({
    this.accentValue = 0xFFFFB000,
    this.wallpaperPath,
    this.tintValue = 0xFF121214,
    this.tintStrength = 0.72,
    this.saturation = 0.9,
    this.brightness = 0,
  });

  final int accentValue;
  final String? wallpaperPath;
  final int tintValue;
  final double tintStrength;
  final double saturation;
  final double brightness;

  Color get accent => Color(accentValue);
  Color get tint => Color(tintValue);

  AppThemeSettings copyWith({
    int? accentValue,
    String? wallpaperPath,
    bool clearWallpaper = false,
    int? tintValue,
    double? tintStrength,
    double? saturation,
    double? brightness,
  }) =>
      AppThemeSettings(
        accentValue: accentValue ?? this.accentValue,
        wallpaperPath:
            clearWallpaper ? null : wallpaperPath ?? this.wallpaperPath,
        tintValue: tintValue ?? this.tintValue,
        tintStrength: tintStrength ?? this.tintStrength,
        saturation: saturation ?? this.saturation,
        brightness: brightness ?? this.brightness,
      );

  Map<String, Object?> toJson() => {
        'accentValue': accentValue,
        'wallpaperPath': wallpaperPath,
        'tintValue': tintValue,
        'tintStrength': tintStrength,
        'saturation': saturation,
        'brightness': brightness,
      };

  factory AppThemeSettings.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback) {
      final value = json[key];
      return value is num && value.isFinite ? value.toDouble() : fallback;
    }

    return AppThemeSettings(
      accentValue:
          json['accentValue'] is int ? json['accentValue'] as int : 0xFFFFB000,
      wallpaperPath: json['wallpaperPath'] is String
          ? json['wallpaperPath'] as String
          : null,
      tintValue:
          json['tintValue'] is int ? json['tintValue'] as int : 0xFF121214,
      tintStrength: number('tintStrength', 0.72).clamp(0, 1).toDouble(),
      saturation: number('saturation', 0.9).clamp(0, 2).toDouble(),
      brightness: number('brightness', 0).clamp(-0.3, 0.3).toDouble(),
    );
  }
}

ColorFilter colorGradeFilter(AppThemeSettings settings) {
  final saturation = settings.saturation;
  final inverseSaturation = 1 - saturation;
  final red = 0.2126 * inverseSaturation;
  final green = 0.7152 * inverseSaturation;
  final blue = 0.0722 * inverseSaturation;
  final brightnessOffset = settings.brightness * 255;
  return ColorFilter.matrix([
    red + saturation,
    green,
    blue,
    0,
    brightnessOffset,
    red,
    green + saturation,
    blue,
    0,
    brightnessOffset,
    red,
    green,
    blue + saturation,
    0,
    brightnessOffset,
    0,
    0,
    0,
    1,
    0,
  ]);
}
