import 'dart:convert';
import 'dart:math' as math;

import 'eq_band.dart';

class EqPreset {
  static const _shareCodePrefix = 'IEM1-';
  static const _shareCodeByteLength = 43;
  static const _shareCodeDataLength = 41;

  const EqPreset({
    required this.name,
    required this.bands,
    this.preampDb = 0,
    this.deviceKey,
  });

  final String name;
  final List<EqBand> bands;
  final double preampDb;
  final String? deviceKey;

  Map<String, Object?> toJson() => {
        'format': 'iem-driver-preset',
        'version': 1,
        'name': name,
        'preampDb': preampDb,
        'deviceKey': deviceKey,
        'bands': bands.map((band) => band.toJson()).toList(growable: false),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Encodes the EQ into a compact, self-contained code that needs no server.
  ///
  /// Center frequency and Q are logarithmically quantized; gain and preamp use
  /// 0.5 dB steps. The device binding and preset name are deliberately omitted.
  String encodeShareCode() {
    if (bands.length != 10) {
      throw const FormatException('A share code requires exactly 10 EQ bands');
    }

    final bytes = List<int>.filled(_shareCodeByteLength, 0);
    for (var index = 0; index < bands.length; index++) {
      final band = bands[index];
      final frequency = band.frequencyHz.clamp(20.0, 20000.0).toDouble();
      final gain = band.gainDb.clamp(-24.0, 12.0).toDouble();
      final q = band.q.clamp(0.1, 10.0).toDouble();
      final frequencyCode =
          (math.log(frequency / 20.0) / (math.ln10 * 3) * 8191).round();
      final gainCode = ((gain + 24.0) * 2).round();
      final qCode = (math.log(q / 0.1) / (math.ln10 * 2) * 255).round();
      final packed = (band.enabled ? 1 : 0) |
          (band.type.index << 1) |
          (frequencyCode << 4) |
          (gainCode << 17) |
          (qCode << 24);
      final offset = index * 4;
      bytes[offset] = packed & 0xff;
      bytes[offset + 1] = (packed >> 8) & 0xff;
      bytes[offset + 2] = (packed >> 16) & 0xff;
      bytes[offset + 3] = (packed >> 24) & 0xff;
    }

    bytes[40] = ((preampDb.clamp(-24.0, 12.0).toDouble() + 24.0) * 2).round();
    final checksum = _crc16(bytes, _shareCodeDataLength);
    bytes[41] = checksum & 0xff;
    bytes[42] = (checksum >> 8) & 0xff;
    final payload = base64Url.encode(bytes).replaceAll('=', '');
    return '$_shareCodePrefix$payload';
  }

  factory EqPreset.fromShareCode(String input) {
    final code = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (!code.startsWith(_shareCodePrefix)) {
      throw const FormatException('This is not an IEM Driver share code');
    }

    final payload = code.substring(_shareCodePrefix.length);
    late final List<int> bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(payload));
    } on FormatException {
      throw const FormatException('Share code contains invalid characters');
    }
    if (bytes.length != _shareCodeByteLength) {
      throw const FormatException('Share code has an invalid length');
    }

    final expectedChecksum = bytes[41] | (bytes[42] << 8);
    if (_crc16(bytes, _shareCodeDataLength) != expectedChecksum) {
      throw const FormatException('Share code is damaged or mistyped');
    }

    final bands = <EqBand>[];
    for (var index = 0; index < 10; index++) {
      final offset = index * 4;
      final packed = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      final typeIndex = (packed >> 1) & 0x7;
      final gainCode = (packed >> 17) & 0x7f;
      if (typeIndex >= EqFilterType.values.length || gainCode > 72) {
        throw const FormatException('Share code contains invalid EQ settings');
      }

      final frequencyCode = (packed >> 4) & 0x1fff;
      final qCode = (packed >> 24) & 0xff;
      bands.add(EqBand(
        enabled: (packed & 1) != 0,
        type: EqFilterType.values[typeIndex],
        frequencyHz: 20.0 * math.pow(1000.0, frequencyCode / 8191),
        gainDb: -24.0 + gainCode * 0.5,
        q: 0.1 * math.pow(100.0, qCode / 255),
      ));
    }

    if (bytes[40] > 72) {
      throw const FormatException('Share code contains an invalid preamp');
    }
    return EqPreset(
      name: 'Shared preset',
      bands: bands,
      preampDb: -24.0 + bytes[40] * 0.5,
    );
  }

  static int _crc16(List<int> bytes, int length) {
    var crc = 0xffff;
    for (var index = 0; index < length; index++) {
      crc ^= bytes[index] << 8;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xffff
            : (crc << 1) & 0xffff;
      }
    }
    return crc;
  }

  factory EqPreset.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'iem-driver-preset' || json['version'] != 1) {
      throw const FormatException('Unsupported IEM Driver preset format');
    }
    final rawBands = json['bands'];
    if (rawBands is! List || rawBands.length != 10) {
      throw const FormatException('A preset must contain exactly 10 EQ bands');
    }
    final name = json['name'];
    final preamp = json['preampDb'];
    final deviceKey = json['deviceKey'];
    return EqPreset(
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'Imported preset',
      bands: rawBands.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid EQ band in preset');
        }
        return EqBand.fromJson(item);
      }).toList(growable: false),
      preampDb: preamp is num && preamp.isFinite
          ? preamp.toDouble().clamp(-24, 12).toDouble()
          : 0,
      deviceKey: deviceKey is String && deviceKey.isNotEmpty ? deviceKey : null,
    );
  }
}
