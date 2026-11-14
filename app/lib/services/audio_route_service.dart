import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class AudioRoute {
  const AudioRoute({
    required this.id,
    required this.kind,
    required this.name,
    this.persistentKey,
    this.bluetoothMac,
    this.vendorId,
    this.productId,
    this.isCharging,
    this.active = false,
  });

  final String id;
  final String kind;
  final String name;
  final String? persistentKey;
  final String? bluetoothMac;
  final int? vendorId;
  final int? productId;

  /// Null means the platform or device does not expose charging state.
  final bool? isCharging;
  final bool active;

  String get profileKey => persistentKey ?? _fallbackProfileKey;

  Iterable<String> get matchingProfileKeys sync* {
    yield profileKey;
    yield '$kind:${name.trim().toLowerCase()}';
    if (bluetoothMac != null) yield 'bluetooth:${bluetoothMac!.toLowerCase()}';
    if (vendorId != null && productId != null) yield 'usb:$vendorId:$productId';
  }

  String get _fallbackProfileKey {
    if (bluetoothMac != null) return 'bluetooth:${bluetoothMac!.toLowerCase()}';
    if (vendorId != null && productId != null) {
      return 'usb:$vendorId:$productId';
    }
    return '$kind:${name.trim().toLowerCase()}';
  }

  String get deviceLabel {
    if (kind == 'usb') return 'DAC';
    if (kind == 'bluetooth') {
      final nameToCheck = name.toLowerCase();
      if (nameToCheck.contains('tws') ||
          nameToCheck.contains('earbud') ||
          nameToCheck.contains('airpod') ||
          nameToCheck.contains('buds')) {
        return 'TWS';
      }
      return 'Bluetooth';
    }
    if (kind == 'jack') return 'IEM / wired';
    return 'Audio output';
  }

  factory AudioRoute.fromJson(Map<dynamic, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final kind = json['kind']?.toString() ?? 'other';
    final name = json['name']?.toString() ?? 'Audio output';
    return AudioRoute(
      id: id,
      kind: kind,
      name: name,
      persistentKey: json['profileKey']?.toString(),
      bluetoothMac: json['bluetoothMac']?.toString(),
      vendorId:
          json['vendorId'] is num ? (json['vendorId'] as num).toInt() : null,
      productId:
          json['productId'] is num ? (json['productId'] as num).toInt() : null,
      isCharging:
          json['isCharging'] is bool ? json['isCharging'] as bool : null,
      active: json['active'] == true,
    );
  }
}

class AudioRouteSnapshot {
  const AudioRouteSnapshot({required this.routes, this.activeOutputId});

  final List<AudioRoute> routes;
  final String? activeOutputId;

  AudioRoute? get activeRoute {
    final active = routes.where((route) => route.active).firstOrNull;
    if (active != null) return active;
    if (activeOutputId != null) {
      for (final route in routes) {
        if (route.id == activeOutputId) return route;
      }
    }
    return null;
  }

  /// Best available endpoint for display when the platform cannot report the
  /// current media route until this app opens its own output stream.
  AudioRoute? get detectedRoute {
    final active = activeRoute;
    if (active != null) return active;
    for (final preferredKind in const ['usb', 'bluetooth', 'jack']) {
      final externalRoute =
          routes.where((route) => route.kind == preferredKind).firstOrNull;
      if (externalRoute != null) return externalRoute;
    }
    return routes.firstOrNull;
  }

  factory AudioRouteSnapshot.fromJson(Map<dynamic, dynamic> json) {
    final rawRoutes = json['availableOutputs'];
    final routes = rawRoutes is List
        ? rawRoutes
            .whereType<Map<dynamic, dynamic>>()
            .map(AudioRoute.fromJson)
            .toList(growable: false)
        : const <AudioRoute>[];
    return AudioRouteSnapshot(
      routes: routes,
      activeOutputId: json['activeOutputId']?.toString(),
    );
  }
}

class AudioRouteService {
  static const _channel = EventChannel('iem_driver/audio_routes');

  Stream<AudioRouteSnapshot> watch() {
    if (kIsWeb) return const Stream<AudioRouteSnapshot>.empty();
    return _channel
        .receiveBroadcastStream()
        .where((event) => event is Map<dynamic, dynamic>)
        .map((event) =>
            AudioRouteSnapshot.fromJson(event as Map<dynamic, dynamic>));
  }
}
