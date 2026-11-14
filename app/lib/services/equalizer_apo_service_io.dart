import 'dart:io';

import '../models/eq_band.dart';
import 'equalizer_apo_service_stub.dart' show EqualizerApoStatus;

export 'equalizer_apo_service_stub.dart' show EqualizerApoStatus;

class EqualizerApoService {
  static const _managedName = 'IEMDriver-managed.txt';
  static const _includeLine = 'Include: IEMDriver-managed.txt';
  static const _backupSuffix = '.iem-driver.bak';

  File? get _configFile {
    final roots = <String?>[
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)'],
      r'C:\Program Files',
      r'C:\Program Files (x86)',
    ].whereType<String>().toSet();
    for (final root in roots) {
      final candidate = File('$root\\EqualizerAPO\\config\\config.txt');
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }

  Future<EqualizerApoStatus> inspect() async {
    final config = _configFile;
    if (config == null) {
      return const EqualizerApoStatus(
        installed: false,
        enabled: false,
        message: 'Equalizer APO was not found in the standard install folders',
      );
    }
    try {
      final source = await config.readAsString();
      final enabled = _containsInclude(source);
      return EqualizerApoStatus(
        installed: true,
        enabled: enabled,
        configPath: config.path,
        message: enabled
            ? 'Equalizer APO is connected to the managed IEM Driver config'
            : 'Equalizer APO is installed; system EQ is not connected yet',
      );
    } on FileSystemException catch (error) {
      return EqualizerApoStatus(
        installed: true,
        enabled: false,
        configPath: config.path,
        message: 'Cannot read Equalizer APO config: ${error.message}',
      );
    }
  }

  Future<EqualizerApoStatus> enable({
    required List<EqBand> bands,
    required double preampDb,
  }) async {
    final config = _configFile;
    if (config == null) return inspect();
    try {
      final source = await config.readAsString();
      final managed = File('${config.parent.path}\\$_managedName');
      await _replaceFile(managed, _encodeConfig(bands, preampDb));
      if (!_containsInclude(source)) {
        final backup = File('${config.path}$_backupSuffix');
        if (!await backup.exists()) await config.copy(backup.path);
        final newline = source.contains('\r\n') ? '\r\n' : '\n';
        final separator =
            source.isEmpty || source.endsWith('\n') ? '' : newline;
        await _replaceFile(config, '$source$separator$_includeLine$newline');
      }
      return EqualizerApoStatus(
        installed: true,
        enabled: true,
        configPath: config.path,
        message: 'Equalizer APO connected; managed PEQ is active',
      );
    } on FileSystemException catch (error) {
      return EqualizerApoStatus(
        installed: true,
        enabled: false,
        configPath: config.path,
        message:
            'Cannot update Equalizer APO files. Run IEM Driver as administrator once: ${error.message}',
      );
    } on FormatException catch (error) {
      return EqualizerApoStatus(
        installed: true,
        enabled: false,
        configPath: config.path,
        message: error.message,
      );
    }
  }

  Future<EqualizerApoStatus> apply({
    required List<EqBand> bands,
    required double preampDb,
  }) async {
    final config = _configFile;
    if (config == null) return inspect();
    try {
      final source = await config.readAsString();
      if (!_containsInclude(source)) {
        return EqualizerApoStatus(
          installed: true,
          enabled: false,
          configPath: config.path,
          message: 'Connect Equalizer APO before applying system EQ',
        );
      }
      final managed = File('${config.parent.path}\\$_managedName');
      await _replaceFile(managed, _encodeConfig(bands, preampDb));
      return EqualizerApoStatus(
        installed: true,
        enabled: true,
        configPath: config.path,
        message: 'Equalizer APO managed config updated',
      );
    } on FileSystemException catch (error) {
      return EqualizerApoStatus(
        installed: true,
        enabled: false,
        configPath: config.path,
        message: 'Cannot write managed Equalizer APO config: ${error.message}',
      );
    } on FormatException catch (error) {
      return EqualizerApoStatus(
        installed: true,
        enabled: false,
        configPath: config.path,
        message: error.message,
      );
    }
  }

  Future<EqualizerApoStatus> disable() async {
    final config = _configFile;
    if (config == null) return inspect();
    try {
      final source = await config.readAsString();
      final lines = source.split(RegExp(r'\r?\n'));
      final filtered = lines.where((line) => !_isManagedInclude(line)).toList();
      if (filtered.length != lines.length) {
        await _replaceFile(config, '${filtered.join('\n').trimRight()}\n');
      }
      return EqualizerApoStatus(
        installed: true,
        enabled: false,
        configPath: config.path,
        message:
            'IEM Driver include removed; managed file and backup were kept',
      );
    } on FileSystemException catch (error) {
      return EqualizerApoStatus(
        installed: true,
        enabled: false,
        configPath: config.path,
        message: 'Cannot disconnect Equalizer APO config: ${error.message}',
      );
    }
  }

  static bool _containsInclude(String source) =>
      source.split(RegExp(r'\r?\n')).any(_isManagedInclude);

  static bool _isManagedInclude(String line) => RegExp(
        r'^\s*Include\s*:\s*"?IEMDriver-managed\.txt"?\s*(?:#.*)?$',
        caseSensitive: false,
      ).hasMatch(line);

  static String _encodeConfig(List<EqBand> bands, double preampDb) {
    if (bands.length != 10) {
      throw const FormatException('Exactly 10 EQ bands are required');
    }
    if (!preampDb.isFinite || preampDb < -24 || preampDb > 12) {
      throw const FormatException('Preamp must be between -24 and +12 dB');
    }
    final lines = <String>[
      '# Generated by IEM Driver. Edit EQ bands in the app.',
      'Preamp: ${preampDb.toStringAsFixed(2)} dB',
    ];
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
      final type = switch (band.type) {
        EqFilterType.peaking => 'PK',
        EqFilterType.lowPass => 'LP',
        EqFilterType.highPass => 'HP',
        EqFilterType.lowShelf => 'LS',
        EqFilterType.highShelf => 'HS',
      };
      lines.add(
        'Filter ${index + 1}: ${band.enabled ? 'ON' : 'OFF'} $type '
        'Fc ${band.frequencyHz.toStringAsFixed(2)} Hz '
        'Gain ${band.gainDb.toStringAsFixed(2)} dB Q ${band.q.toStringAsFixed(3)}',
      );
    }
    return '${lines.join('\r\n')}\r\n';
  }

  static Future<void> _replaceFile(File destination, String content) async {
    final temporary = File('${destination.path}.iem-driver.tmp');
    await temporary.writeAsString(content, flush: true);
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      await temporary.copy(destination.path);
      await temporary.delete();
    }
  }
}
