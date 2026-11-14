import 'dart:math' as math;

import '../models/eq_band.dart';
import '../models/eq_preset.dart';
import 'parametric_eq_engine.dart';

/// Reads and writes the common AutoEQ/Squiglink parametric filter text format.
class AutoEqTextParser {
  static final _number = r'([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)';
  static final _preampPattern = RegExp(
    '^\\s*Preamp\\s*:\\s*$_number\\s*dB\\s*\$',
    caseSensitive: false,
  );
  static final _filterPattern = RegExp(
    '^\\s*Filter\\s+(\\d+)\\s*:\\s*(ON|OFF)\\s+'
    '(PK|PE|PEAKING|LP|LOWPASS|HP|HIGHPASS|LS|LOWSHELF|HS|HIGHSHELF)\\s+'
    'Fc\\s*$_number\\s*Hz\\s+Gain\\s*$_number\\s*dB\\s+'
    'Q\\s*$_number\\s*\$',
    caseSensitive: false,
  );

  const AutoEqTextParser();

  EqPreset parse(
    String text, {
    String name = 'Imported EQ',
    List<EqBand>? baseBands,
  }) {
    if (baseBands != null && baseBands.length != 10) {
      throw const FormatException('Base EQ must contain exactly 10 bands');
    }
    final bands = baseBands == null
        ? List<EqBand>.generate(10, (index) {
            final frequency = 20.0 * math.pow(1000.0, index / 9.0);
            return EqBand(
              enabled: false,
              type: EqFilterType.peaking,
              frequencyHz: frequency,
              gainDb: 0,
              q: 0.9,
            );
          })
        : List<EqBand>.of(baseBands);
    final seen = <int>{};
    var preampDb = 0.0;
    var sawDirective = false;
    var lineNumber = 0;

    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      lineNumber++;
      final line = rawLine.trim();
      if (line.isEmpty ||
          line.startsWith('#') ||
          line.startsWith(';') ||
          line.startsWith('//')) {
        continue;
      }

      final preampMatch = _preampPattern.firstMatch(line);
      if (preampMatch != null) {
        preampDb = _parseNumber(preampMatch[1]!, lineNumber, 'preamp');
        _validateRange(preampDb, -24, 12, lineNumber, 'preamp dB');
        sawDirective = true;
        continue;
      }

      final filterMatch = _filterPattern.firstMatch(line);
      if (filterMatch == null) {
        if (RegExp(r'^Filter\s+\d+\s*:', caseSensitive: false).hasMatch(line)) {
          throw FormatException('Invalid filter directive on line $lineNumber');
        }
        continue; // AutoEQ exports may contain headings and source metadata.
      }

      final number = int.tryParse(filterMatch[1]!);
      if (number == null || number < 1 || number > 10) {
        throw FormatException('Filter number on line $lineNumber must be 1–10');
      }
      final index = number - 1;
      if (!seen.add(index)) {
        throw FormatException('Filter $number appears more than once');
      }

      final type = _parseType(filterMatch[3]!, lineNumber);
      final frequencyHz =
          _parseNumber(filterMatch[4]!, lineNumber, 'frequency');
      final gainDb = _parseNumber(filterMatch[5]!, lineNumber, 'gain');
      final q = _parseNumber(filterMatch[6]!, lineNumber, 'Q');
      _validateRange(frequencyHz, 20, 20000, lineNumber, 'frequency Hz');
      _validateRange(gainDb, -24, 12, lineNumber, 'gain dB');
      _validateRange(q, 0.1, 10, lineNumber, 'Q');

      bands[index] = bands[index].copyWith(
        enabled: filterMatch[2]!.toUpperCase() == 'ON',
        type: type,
        frequencyHz: frequencyHz,
        gainDb: gainDb,
        q: q,
      );
      sawDirective = true;
    }

    if (!sawDirective) {
      throw const FormatException('No Preamp or Filter directives were found');
    }
    return EqPreset(
      name: name.trim().isEmpty ? 'Imported EQ' : name.trim(),
      bands: List.unmodifiable(bands),
      preampDb: preampDb,
    );
  }

  String encode({required List<EqBand> bands, required double preampDb}) {
    if (bands.length != 10) {
      throw const FormatException('An export requires exactly 10 EQ bands');
    }
    if (!preampDb.isFinite || preampDb < -24 || preampDb > 12) {
      throw const FormatException('Preamp must be between -24 and +12 dB');
    }
    final lines = <String>['Preamp: ${preampDb.toStringAsFixed(2)} dB'];
    for (var index = 0; index < bands.length; index++) {
      final band = bands[index];
      if (!band.frequencyHz.isFinite ||
          band.frequencyHz < 20 ||
          band.frequencyHz > 20000 ||
          !band.gainDb.isFinite ||
          band.gainDb < -24 ||
          band.gainDb > 12 ||
          !band.q.isFinite ||
          band.q < 0.1 ||
          band.q > 10) {
        throw FormatException('Band ${index + 1} contains an invalid value');
      }
      lines.add(
        'Filter ${index + 1}: ${band.enabled ? 'ON' : 'OFF'} '
        '${_typeToken(band.type)} Fc ${band.frequencyHz.toStringAsFixed(2)} Hz '
        'Gain ${band.gainDb.toStringAsFixed(2)} dB Q ${band.q.toStringAsFixed(3)}',
      );
    }
    return '${lines.join('\n')}\n';
  }

  static double peakGainDb(
    List<EqBand> bands, {
    int sampleRateHz = 48000,
    int samplesPerOctave = 256,
  }) {
    if (bands.length != 10) {
      throw const FormatException('Exactly 10 bands are required');
    }
    final engine = ParametricEqEngine(
      sampleRateHz: sampleRateHz,
      channelCount: 1,
      bands: bands,
    );
    final octaveCount = (math.log(20000 / 20) / math.ln2).ceil();
    final count = octaveCount * samplesPerOctave;
    var peak = double.negativeInfinity;
    for (var index = 0; index <= count; index++) {
      final t = index / count;
      final frequency = 20.0 * math.pow(1000.0, t);
      peak = math.max(peak, engine.responseDbAt(frequency));
    }
    return peak;
  }

  static double recommendedPreampDb(List<EqBand> bands) =>
      (-math.max(0.0, peakGainDb(bands))).clamp(-24.0, 0.0).toDouble();

  static EqFilterType _parseType(String value, int lineNumber) {
    switch (value.toUpperCase()) {
      case 'PK':
      case 'PE':
      case 'PEAKING':
        return EqFilterType.peaking;
      case 'LP':
      case 'LOWPASS':
        return EqFilterType.lowPass;
      case 'HP':
      case 'HIGHPASS':
        return EqFilterType.highPass;
      case 'LS':
      case 'LOWSHELF':
        return EqFilterType.lowShelf;
      case 'HS':
      case 'HIGHSHELF':
        return EqFilterType.highShelf;
      default:
        throw FormatException('Unknown filter type on line $lineNumber');
    }
  }

  static String _typeToken(EqFilterType type) => switch (type) {
        EqFilterType.peaking => 'PK',
        EqFilterType.lowPass => 'LP',
        EqFilterType.highPass => 'HP',
        EqFilterType.lowShelf => 'LS',
        EqFilterType.highShelf => 'HS',
      };

  static double _parseNumber(String text, int line, String label) {
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) {
      throw FormatException('Invalid $label on line $line');
    }
    return value;
  }

  static void _validateRange(
    double value,
    double minimum,
    double maximum,
    int line,
    String label,
  ) {
    if (value < minimum || value > maximum) {
      throw FormatException('$label on line $line must be $minimum–$maximum');
    }
  }
}
