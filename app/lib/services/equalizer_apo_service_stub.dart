import '../models/eq_band.dart';

class EqualizerApoStatus {
  const EqualizerApoStatus({
    required this.installed,
    required this.enabled,
    required this.message,
    this.configPath,
  });

  final bool installed;
  final bool enabled;
  final String message;
  final String? configPath;
}

class EqualizerApoService {
  Future<EqualizerApoStatus> inspect() async => const EqualizerApoStatus(
        installed: false,
        enabled: false,
        message: 'Equalizer APO integration is available in the Windows build',
      );

  Future<EqualizerApoStatus> enable({
    required List<EqBand> bands,
    required double preampDb,
  }) async =>
      inspect();

  Future<EqualizerApoStatus> apply({
    required List<EqBand> bands,
    required double preampDb,
  }) async =>
      inspect();

  Future<EqualizerApoStatus> disable() async => inspect();
}
