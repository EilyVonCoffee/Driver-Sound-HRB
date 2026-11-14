import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iem_driver/models/eq_band.dart';
import 'package:iem_driver/services/parametric_eq_engine.dart';

void main() {
  List<EqBand> bands({int? activeBand, double gainDb = 0}) => List.generate(
        10,
        (index) => EqBand(
          enabled: index == activeBand,
          type: EqFilterType.peaking,
          frequencyHz: 1000,
          gainDb: gainDb,
          q: 1,
        ),
      );

  test('disabled bands and zero preamp leave samples unchanged', () {
    final engine = ParametricEqEngine(
      sampleRateHz: 48000,
      channelCount: 2,
      bands: bands(),
    );
    final samples = Float32List.fromList([0.25, -0.25, 0.5, -0.5]);

    engine.process(samples);

    expect(samples, [0.25, -0.25, 0.5, -0.5]);
  });

  test('peaking band applies its expected gain at center frequency', () {
    const sampleRate = 48000;
    final engine = ParametricEqEngine(
      sampleRateHz: sampleRate,
      channelCount: 1,
      bands: bands(activeBand: 0, gainDb: 6),
    );
    final input = Float32List(48000);
    for (var sample = 0; sample < input.length; sample++) {
      input[sample] = math.sin(2 * math.pi * 1000 * sample / sampleRate);
    }
    final source = Float64List.fromList(
        input.sublist(24000).map((value) => value.toDouble()).toList());

    engine.process(input);

    var inputEnergy = 0.0;
    var outputEnergy = 0.0;
    for (var sample = 24000; sample < input.length; sample++) {
      inputEnergy += source[sample - 24000] * source[sample - 24000];
      outputEnergy += input[sample] * input[sample];
    }
    final rmsRatio = math.sqrt(outputEnergy / inputEnergy);
    expect(rmsRatio, closeTo(math.pow(10, 6 / 20), 0.015));
  });

  test('rejects malformed interleaved buffers', () {
    final engine = ParametricEqEngine(
      sampleRateHz: 48000,
      channelCount: 2,
      bands: bands(),
    );

    expect(() => engine.process(Float32List(3)), throwsArgumentError);
  });
}
