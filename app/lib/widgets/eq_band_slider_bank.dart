import 'package:flutter/material.dart';

import '../models/eq_band.dart';

/// Compact, touch-friendly gain faders for the same PEQ bands shown on the
/// response graph. Frequency and Q remain editable in the detailed controls.
class EqBandSliderBank extends StatelessWidget {
  const EqBandSliderBank({
    super.key,
    required this.bands,
    required this.selectedIndex,
    required this.accent,
    required this.onSelectionChanged,
    required this.onGainChanged,
  });

  final List<EqBand> bands;
  final int selectedIndex;
  final Color accent;
  final ValueChanged<int> onSelectionChanged;
  final void Function(int index, double gainDb) onGainChanged;

  @override
  Widget build(BuildContext context) {
    if (bands.isEmpty) return const SizedBox.shrink();
    final selected = selectedIndex.clamp(0, bands.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Band gain',
                style: TextStyle(
                  color: Color(0xFFA1A1A6),
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              '${bands[selected].gainDb.toStringAsFixed(1)} dB',
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontFamily: 'monospace',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final faderWidth = constraints.maxWidth / bands.length;
          return SizedBox(
            height: 148,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(bands.length, (index) {
                final band = bands[index];
                return SizedBox(
                  width: faderWidth,
                  child: _BandGainFader(
                    key: ValueKey('eq-band-fader-$index'),
                    index: index,
                    frequencyHz: band.frequencyHz,
                    gainDb: band.enabled ? band.gainDb : 0,
                    enabled: band.enabled,
                    selected: index == selectedIndex,
                    accent: accent,
                    onSelected: () => onSelectionChanged(index),
                    onChanged: (gain) => onGainChanged(index, gain),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }
}

class _BandGainFader extends StatelessWidget {
  const _BandGainFader({
    super.key,
    required this.index,
    required this.frequencyHz,
    required this.gainDb,
    required this.enabled,
    required this.selected,
    required this.accent,
    required this.onSelected,
    required this.onChanged,
  });

  static const _minimumDb = -24.0;
  static const _maximumDb = 12.0;

  final int index;
  final double frequencyHz;
  final double gainDb;
  final bool enabled;
  final bool selected;
  final Color accent;
  final VoidCallback onSelected;
  final ValueChanged<double> onChanged;

  String get _frequencyLabel {
    if (frequencyHz >= 1000) {
      final khz = frequencyHz / 1000;
      return '${khz >= 10 ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1)}k';
    }
    return frequencyHz.round().toString();
  }

  void _setAt(double y, double height) {
    onSelected();
    final normalized = (1 - y / height).clamp(0.0, 1.0).toDouble();
    onChanged(_minimumDb + normalized * (_maximumDb - _minimumDb));
  }

  @override
  Widget build(BuildContext context) {
    final height = 116.0;
    final currentGain = enabled ? gainDb : 0.0;
    return Semantics(
      key: ValueKey('eq-band-fader-semantics-$index'),
      label: 'Band ${index + 1} gain at $_frequencyLabel hertz',
      value: '${currentGain.toStringAsFixed(1)} decibels',
      increasedValue:
          '${(currentGain + 0.5).clamp(_minimumDb, _maximumDb).toStringAsFixed(1)} decibels',
      decreasedValue:
          '${(currentGain - 0.5).clamp(_minimumDb, _maximumDb).toStringAsFixed(1)} decibels',
      slider: true,
      onIncrease: () {
        onSelected();
        onChanged(
          (currentGain + 0.5).clamp(_minimumDb, _maximumDb).toDouble(),
        );
      },
      onDecrease: () {
        onSelected();
        onChanged(
          (currentGain - 0.5).clamp(_minimumDb, _maximumDb).toDouble(),
        );
      },
      child: Column(
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _setAt(details.localPosition.dy, height),
              onVerticalDragStart: (details) =>
                  _setAt(details.localPosition.dy, height),
              onVerticalDragUpdate: (details) =>
                  _setAt(details.localPosition.dy, height),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GainFaderPainter(
                    gainDb: currentGain,
                    selected: selected,
                    accent: accent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _frequencyLabel,
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFEDEDED)
                      : const Color(0xFF85858B),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GainFaderPainter extends CustomPainter {
  const _GainFaderPainter({
    required this.gainDb,
    required this.selected,
    required this.accent,
  });

  final double gainDb;
  final bool selected;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const inset = 8.0;
    final centerX = size.width / 2;
    final trackTop = inset;
    final trackBottom = size.height - inset;
    final trackHeight = trackBottom - trackTop;
    final zeroY = trackTop + trackHeight * (12 / 36);
    final gain = gainDb.clamp(-24.0, 12.0).toDouble();
    final thumbY = trackTop + trackHeight * ((12 - gain) / 36);

    canvas.drawLine(
      Offset(centerX, trackTop),
      Offset(centerX, trackBottom),
      Paint()
        ..color = const Color(0xFF48484B)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(centerX - 5, zeroY),
      Offset(centerX + 5, zeroY),
      Paint()
        ..color = const Color(0xFF85858B)
        ..strokeWidth = 1.2,
    );

    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(centerX, thumbY), width: 18, height: 12),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      thumb,
      Paint()..color = selected ? accent : const Color(0xFF77777B),
    );
    if (selected) {
      canvas.drawRRect(
        thumb,
        Paint()
          ..color = accent.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GainFaderPainter oldDelegate) =>
      oldDelegate.gainDb != gainDb ||
      oldDelegate.selected != selected ||
      oldDelegate.accent != accent;
}
