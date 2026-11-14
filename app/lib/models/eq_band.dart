import 'package:flutter/foundation.dart';

enum EqFilterType { lowPass, highPass, lowShelf, highShelf, peaking }

@immutable
class EqBand {
  const EqBand({
    required this.enabled,
    required this.type,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
  });

  final bool enabled;
  final EqFilterType type;
  final double frequencyHz;
  final double gainDb;
  final double q;

  EqBand copyWith({
    bool? enabled,
    EqFilterType? type,
    double? frequencyHz,
    double? gainDb,
    double? q,
  }) =>
      EqBand(
        enabled: enabled ?? this.enabled,
        type: type ?? this.type,
        frequencyHz: frequencyHz ?? this.frequencyHz,
        gainDb: gainDb ?? this.gainDb,
        q: q ?? this.q,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqBand &&
          enabled == other.enabled &&
          type == other.type &&
          frequencyHz == other.frequencyHz &&
          gainDb == other.gainDb &&
          q == other.q;

  @override
  int get hashCode => Object.hash(enabled, type, frequencyHz, gainDb, q);

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'type': type.name,
        'frequencyHz': frequencyHz,
        'gainDb': gainDb,
        'q': q,
      };

  factory EqBand.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'];
    final type = EqFilterType.values.firstWhere(
      (candidate) => candidate.name == typeName,
      orElse: () => EqFilterType.peaking,
    );
    double number(String key, double fallback) {
      final value = json[key];
      return value is num && value.isFinite ? value.toDouble() : fallback;
    }

    return EqBand(
      enabled: json['enabled'] == true,
      type: type,
      frequencyHz: number('frequencyHz', 1000).clamp(20, 20000).toDouble(),
      gainDb: number('gainDb', 0).clamp(-24, 12).toDouble(),
      q: number('q', 0.9).clamp(0.1, 10).toDouble(),
    );
  }
}
