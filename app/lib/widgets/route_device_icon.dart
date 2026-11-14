import 'package:flutter/material.dart';

import '../services/audio_route_service.dart';

/// A quiet route indicator: route changes fade in, with no inferred battery
/// animation or motion that suggests unsupported TWS charging telemetry.
class RouteDeviceIcon extends StatelessWidget {
  const RouteDeviceIcon({
    super.key,
    required this.route,
    required this.accent,
    this.isActive = false,
  });

  final AudioRoute? route;
  final Color accent;
  final bool isActive;

  IconData _iconForRoute(AudioRoute? value) {
    if (value == null) return Icons.headphones_outlined;
    if (value.deviceLabel == 'TWS') return Icons.earbuds_outlined;
    return switch (value.kind) {
      'usb' => Icons.usb_outlined,
      'bluetooth' => Icons.bluetooth_audio_outlined,
      'jack' => Icons.headphones_outlined,
      _ => Icons.speaker_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final current = route;
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: Container(
            key: ValueKey(current?.id ?? 'no-audio-route'),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF232325),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            alignment: Alignment.center,
            child: Icon(
              _iconForRoute(current),
              color: current == null ? const Color(0xFF85858B) : accent,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current?.deviceLabel ?? 'Audio route',
                style: const TextStyle(color: Color(0xFFA1A1A6), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                current?.name ?? 'Waiting for a connected device',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF4CC38A)
                    : const Color(0xFF85858B),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isActive
                  ? 'Connected'
                  : (current == null ? 'Offline' : 'Detected'),
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF4CC38A)
                    : const Color(0xFF85858B),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
