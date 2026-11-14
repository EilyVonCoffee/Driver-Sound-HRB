import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:iem_driver/models/eq_band.dart';
import 'package:iem_driver/models/eq_preset.dart';

void main() {
  test('preset JSON round-trip preserves EQ parameters and device binding', () {
    final preset = EqPreset(
      name: 'Desk DAC',
      preampDb: -4.5,
      deviceKey: 'usb:1234:5678',
      bands: List.generate(
        10,
        (index) => EqBand(
          enabled: index == 3,
          type: EqFilterType.peaking,
          frequencyHz: (20 * math.pow(1000.0, index / 9)).toDouble(),
          gainDb: index == 3 ? 2.5 : 0,
          q: 0.9,
        ),
      ),
    );

    final decoded = EqPreset.fromJson(preset.toJson());

    expect(decoded.name, preset.name);
    expect(decoded.preampDb, preset.preampDb);
    expect(decoded.deviceKey, preset.deviceKey);
    expect(decoded.bands, preset.bands);
  });

  test('preset import rejects invalid format and band counts', () {
    expect(
      () => EqPreset.fromJson({'format': 'unknown', 'version': 1, 'bands': []}),
      throwsFormatException,
    );
    expect(
      () => EqPreset.fromJson(
          {'format': 'iem-driver-preset', 'version': 1, 'bands': []}),
      throwsFormatException,
    );
  });

  test('compact share code round-trip preserves all EQ controls', () {
    final preset = EqPreset(
      name: 'My IEM',
      preampDb: -3.2,
      deviceKey: 'device:private-key',
      bands: List.generate(
        10,
        (index) => EqBand(
          enabled: index.isEven,
          type: EqFilterType.values[index % EqFilterType.values.length],
          frequencyHz: (20 * math.pow(1000.0, index / 9)).toDouble(),
          gainDb: -12 + index * 2.1,
          q: 0.2 + index * 0.8,
        ),
      ),
    );

    final code = preset.encodeShareCode();
    final decoded = EqPreset.fromShareCode(code);

    expect(code, startsWith('IEM1-'));
    expect(code.length, 63);
    expect(decoded.deviceKey, isNull);
    expect(decoded.preampDb, closeTo(-3.0, 0.25));
    for (var index = 0; index < 10; index++) {
      expect(decoded.bands[index].enabled, preset.bands[index].enabled);
      expect(decoded.bands[index].type, preset.bands[index].type);
      expect(
          decoded.bands[index].frequencyHz,
          closeTo(preset.bands[index].frequencyHz,
              preset.bands[index].frequencyHz * 0.002));
      expect(decoded.bands[index].gainDb,
          closeTo(preset.bands[index].gainDb, 0.25));
      expect(decoded.bands[index].q,
          closeTo(preset.bands[index].q, preset.bands[index].q * 0.012));
    }
  });

  test('share code rejects corruption and invalid length', () {
    const validCode =
        'IEM1-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    expect(() => EqPreset.fromShareCode(validCode), throwsFormatException);
    expect(() => EqPreset.fromShareCode('IEM1-short'), throwsFormatException);
  });
}
