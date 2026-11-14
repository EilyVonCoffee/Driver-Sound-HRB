import 'dart:math' as math;
import 'dart:typed_data';

import '../models/eq_band.dart';

/// Ten-band parametric EQ using cascaded biquads in Direct Form II Transposed.
///
/// [process] mutates interleaved Float32 PCM in place. Configure the engine
/// between audio blocks; a platform audio callback should own one engine
/// instance and call process for each block.
class ParametricEqEngine {
  ParametricEqEngine({
    required int sampleRateHz,
    required int channelCount,
    required List<EqBand> bands,
    double preampDb = 0,
  })  : _sampleRateHz = sampleRateHz,
        _channelCount = channelCount {
    configure(
      sampleRateHz: sampleRateHz,
      channelCount: channelCount,
      bands: bands,
      preampDb: preampDb,
    );
  }

  int _sampleRateHz;
  int _channelCount;
  double _preampLinear = 1;
  List<_BiquadStage> _stages = const [];

  int get sampleRateHz => _sampleRateHz;
  int get channelCount => _channelCount;

  /// Returns the cascaded magnitude response at one frequency in dB.
  ///
  /// This reads the same coefficients used by [process], so auto-preamp and
  /// the response graph can reason about the filters actually being applied.
  double responseDbAt(double frequencyHz) {
    if (!frequencyHz.isFinite || frequencyHz <= 0) {
      throw ArgumentError.value(frequencyHz, 'frequencyHz', 'Must be positive');
    }
    final omega = 2 * math.pi * frequencyHz / _sampleRateHz;
    final cosine1 = math.cos(omega);
    final sine1 = math.sin(omega);
    final cosine2 = math.cos(2 * omega);
    final sine2 = math.sin(2 * omega);
    var response = 20 * math.log(_preampLinear) / math.ln10;
    for (final stage in _stages) {
      final c = stage.coefficients;
      final numeratorReal = c.b0 + c.b1 * cosine1 + c.b2 * cosine2;
      final numeratorImaginary = -c.b1 * sine1 - c.b2 * sine2;
      final denominatorReal = 1 + c.a1 * cosine1 + c.a2 * cosine2;
      final denominatorImaginary = -c.a1 * sine1 - c.a2 * sine2;
      final numerator = math.sqrt(
        numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary,
      );
      final denominator = math.sqrt(
        denominatorReal * denominatorReal +
            denominatorImaginary * denominatorImaginary,
      );
      response +=
          20 * math.log(math.max(numerator / denominator, 1e-12)) / math.ln10;
    }
    return response;
  }

  /// Rebuilds coefficients and clears filter history. Call outside processing.
  void configure({
    required int sampleRateHz,
    required int channelCount,
    required List<EqBand> bands,
    double preampDb = 0,
  }) {
    if (sampleRateHz < 8000) {
      throw ArgumentError.value(
          sampleRateHz, 'sampleRateHz', 'Must be at least 8000 Hz');
    }
    if (channelCount < 1 || channelCount > 8) {
      throw ArgumentError.value(
          channelCount, 'channelCount', 'Must be between 1 and 8');
    }
    if (bands.length != 10) {
      throw ArgumentError.value(
          bands.length, 'bands', 'Exactly 10 bands are required');
    }
    if (!preampDb.isFinite) {
      throw ArgumentError.value(preampDb, 'preampDb', 'Must be finite');
    }

    _sampleRateHz = sampleRateHz;
    _channelCount = channelCount;
    _preampLinear = math.pow(10, preampDb.clamp(-24.0, 12.0) / 20).toDouble();
    _stages = List<_BiquadStage>.unmodifiable(
      bands.map((band) => _BiquadStage(_coefficients(band), channelCount)),
    );
  }

  /// Processes interleaved PCM in place without per-sample allocations.
  void process(Float32List interleavedPcm) {
    if (interleavedPcm.length % _channelCount != 0) {
      throw ArgumentError.value(
        interleavedPcm.length,
        'interleavedPcm.length',
        'Must be divisible by channelCount ($_channelCount)',
      );
    }

    for (var frame = 0; frame < interleavedPcm.length; frame += _channelCount) {
      for (var channel = 0; channel < _channelCount; channel++) {
        final sampleIndex = frame + channel;
        var sample = interleavedPcm[sampleIndex] * _preampLinear;
        for (final stage in _stages) {
          sample = stage.process(sample, channel);
        }
        interleavedPcm[sampleIndex] = sample;
      }
    }
  }

  _Coefficients _coefficients(EqBand band) {
    if (!band.enabled) return const _Coefficients.identity();

    final frequency = band.frequencyHz
        .clamp(20.0, math.min(20000.0, _sampleRateHz * 0.49))
        .toDouble();
    final gain = band.gainDb.clamp(-24.0, 12.0).toDouble();
    final q = band.q.clamp(0.1, 10.0).toDouble();
    final omega = 2 * math.pi * frequency / _sampleRateHz;
    final cosine = math.cos(omega);
    final sine = math.sin(omega);
    final amplitude = math.pow(10, gain / 40).toDouble();
    final alpha = sine / (2 * q);

    List<double> normalize(
      double b0,
      double b1,
      double b2,
      double a0,
      double a1,
      double a2,
    ) =>
        [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];

    late final List<double> values;
    switch (band.type) {
      case EqFilterType.lowPass:
        values = normalize(
          (1 - cosine) / 2,
          1 - cosine,
          (1 - cosine) / 2,
          1 + alpha,
          -2 * cosine,
          1 - alpha,
        );
      case EqFilterType.highPass:
        values = normalize(
          (1 + cosine) / 2,
          -(1 + cosine),
          (1 + cosine) / 2,
          1 + alpha,
          -2 * cosine,
          1 - alpha,
        );
      case EqFilterType.peaking:
        values = normalize(
          1 + alpha * amplitude,
          -2 * cosine,
          1 - alpha * amplitude,
          1 + alpha / amplitude,
          -2 * cosine,
          1 - alpha / amplitude,
        );
      case EqFilterType.lowShelf:
      case EqFilterType.highShelf:
        final slope = q.clamp(0.1, 1.0).toDouble();
        final shelfAlpha = sine /
            2 *
            math.sqrt(
              math.max(0.0, (amplitude + 1 / amplitude) * (1 / slope - 1) + 2),
            );
        final twoRootAmplitudeAlpha = 2 * math.sqrt(amplitude) * shelfAlpha;
        if (band.type == EqFilterType.lowShelf) {
          values = normalize(
            amplitude *
                ((amplitude + 1) -
                    (amplitude - 1) * cosine +
                    twoRootAmplitudeAlpha),
            2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
            amplitude *
                ((amplitude + 1) -
                    (amplitude - 1) * cosine -
                    twoRootAmplitudeAlpha),
            (amplitude + 1) + (amplitude - 1) * cosine + twoRootAmplitudeAlpha,
            -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
            (amplitude + 1) + (amplitude - 1) * cosine - twoRootAmplitudeAlpha,
          );
        } else {
          values = normalize(
            amplitude *
                ((amplitude + 1) +
                    (amplitude - 1) * cosine +
                    twoRootAmplitudeAlpha),
            -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
            amplitude *
                ((amplitude + 1) +
                    (amplitude - 1) * cosine -
                    twoRootAmplitudeAlpha),
            (amplitude + 1) - (amplitude - 1) * cosine + twoRootAmplitudeAlpha,
            2 * ((amplitude - 1) - (amplitude + 1) * cosine),
            (amplitude + 1) - (amplitude - 1) * cosine - twoRootAmplitudeAlpha,
          );
        }
    }

    return _Coefficients(values[0], values[1], values[2], values[3], values[4]);
  }
}

class _Coefficients {
  const _Coefficients(this.b0, this.b1, this.b2, this.a1, this.a2);

  const _Coefficients.identity() : this(1, 0, 0, 0, 0);

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;
}

class _BiquadStage {
  _BiquadStage(this.coefficients, int channels)
      : _z1 = List<double>.filled(channels, 0),
        _z2 = List<double>.filled(channels, 0);

  final _Coefficients coefficients;
  final List<double> _z1;
  final List<double> _z2;

  double process(double input, int channel) {
    final output = coefficients.b0 * input + _z1[channel];
    _z1[channel] =
        coefficients.b1 * input - coefficients.a1 * output + _z2[channel];
    _z2[channel] = coefficients.b2 * input - coefficients.a2 * output;
    return output;
  }
}
