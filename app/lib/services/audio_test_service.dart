import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

import '../models/eq_band.dart';

/// Flutter control-plane bridge to the native Android Oboe and Windows WASAPI
/// test-output engines. Browser previews deliberately report unsupported.
class AudioTestService {
  static const _channel = MethodChannel('iem_driver/audio_engine');

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  Future<bool> startTestTone(
    double frequencyHz, {
    bool pinkNoise = false,
  }) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'startTestTone',
          {'frequencyHz': frequencyHz, 'pinkNoise': pinkNoise},
        ) ??
        false;
  }

  Future<void> stopTestAudio() async {
    if (isSupported) await _channel.invokeMethod<Object?>('stopTestAudio');
  }

  Future<bool> isTestAudioActive() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('isTestAudioActive') ?? false;
  }

  Future<bool> setTestFrequency(double frequencyHz) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'setTestFrequency',
          {'frequencyHz': frequencyHz},
        ) ??
        false;
  }

  Future<bool> configureEq({
    required List<EqBand> bands,
    required double preampDb,
  }) async {
    if (!isSupported || bands.length != 10) return false;
    final configuration = <String, Object>{
      'preampDb': preampDb,
      'bands': bands
          .map((band) => <String, Object>{
                'enabled': band.enabled,
                'type': band.type.index,
                'frequencyHz': band.frequencyHz,
                'gainDb': band.gainDb,
                'q': band.q,
              })
          .toList(growable: false),
    };
    return await _channel.invokeMethod<bool>('configureEq', configuration) ??
        false;
  }

  Future<List<double>> readSpectrum() async {
    if (!isSupported) return const [];
    final bins = await _channel.invokeMethod<List<Object?>>('readSpectrum');
    return bins
            ?.whereType<num>()
            .map((value) => value.toDouble())
            .toList(growable: false) ??
        const [];
  }

  Future<Map<String, Object?>> readSystemEqStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const {};
    }
    return await _channel.invokeMapMethod<String, Object?>(
          'getSystemEqStatus',
        ) ??
        const {};
  }

  Future<void> disableAndroidSystemEq() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<Object?>('disableSystemEq');
    }
  }
}
