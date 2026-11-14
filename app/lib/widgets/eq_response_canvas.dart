import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/eq_band.dart';

export '../models/eq_band.dart';

class EqResponseCanvas extends StatefulWidget {
  const EqResponseCanvas({
    super.key,
    required this.bands,
    required this.selectedIndex,
    required this.onBandChanged,
    this.onSelectionChanged,
    this.preampDb = 0,
    this.sampleRateHz = 48000,
    this.accent = const Color(0xFFFFB000),
    this.height = 320,
  });

  final List<EqBand> bands;
  final int selectedIndex;
  final ValueChanged<int>? onSelectionChanged;
  final void Function(int index, EqBand band) onBandChanged;
  final double preampDb;
  final double sampleRateHz;
  final Color accent;
  final double height;

  @override
  State<EqResponseCanvas> createState() => _EqResponseCanvasState();
}

class _EqResponseCanvasState extends State<EqResponseCanvas> {
  int? _draggingBandIndex;

  Rect _plotRect(Size size) => Rect.fromLTRB(
        52,
        16,
        math.max(72.0, size.width - 20).toDouble(),
        math.max(48.0, size.height - 32).toDouble(),
      );

  Offset _nodePosition(EqBand band, Rect plot) {
    final frequency = band.frequencyHz;
    final gain = band.enabled ? band.gainDb : 0.0;
    final x = (math.log(frequency / 20.0) / (math.ln10 * 3))
        .clamp(0.0, 1.0)
        .toDouble();
    final y = ((12.0 - gain) / 36.0).clamp(0.0, 1.0).toDouble();
    return Offset(plot.left + plot.width * x, plot.top + plot.height * y);
  }

  int? _nearestBand(Offset point, Size size) {
    if (widget.bands.isEmpty) return null;
    final plot = _plotRect(size);
    var bestIndex = -1;
    var bestDistance = 24.0;
    for (var i = 0; i < widget.bands.length; i++) {
      final distance = (point - _nodePosition(widget.bands[i], plot)).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex < 0 ? null : bestIndex;
  }

  void _selectAt(Offset point, Size size) {
    final index = _nearestBand(point, size);
    if (index == null || index == widget.selectedIndex) return;
    widget.onSelectionChanged?.call(index);
  }

  void _onPanStart(DragStartDetails details, Size size) {
    final index = _nearestBand(details.localPosition, size);
    if (index == null) return;
    _draggingBandIndex = index;
    if (index != widget.selectedIndex) {
      widget.onSelectionChanged?.call(index);
    }
    _moveBand(index, details.localPosition, size);
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final index = _draggingBandIndex;
    if (index != null) _moveBand(index, details.localPosition, size);
  }

  void _moveBand(int index, Offset point, Size size) {
    if (index < 0 || index >= widget.bands.length) return;
    final plot = _plotRect(size);
    final x = ((point.dx - plot.left) / plot.width).clamp(0.0, 1.0).toDouble();
    final y = ((point.dy - plot.top) / plot.height).clamp(0.0, 1.0).toDouble();
    final frequency = (20.0 * math.pow(1000.0, x)).toDouble();
    final gain = (12.0 - y * 36.0).clamp(-24.0, 12.0).toDouble();
    final band = widget.bands[index].copyWith(
      enabled: true,
      frequencyHz: frequency,
      gainDb: gain,
    );
    widget.onBandChanged(index, band);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, widget.height);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _selectAt(details.localPosition, size),
        onPanStart: (details) => _onPanStart(details, size),
        onPanUpdate: (details) => _onPanUpdate(details, size),
        onPanEnd: (_) => _draggingBandIndex = null,
        onPanCancel: () => _draggingBandIndex = null,
        child: RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: _EqResponsePainter(
              bands: widget.bands,
              selectedIndex: widget.selectedIndex,
              preampDb: widget.preampDb,
              sampleRateHz: widget.sampleRateHz,
              accent: widget.accent,
            ),
          ),
        ),
      );
    });
  }
}

class _Biquad {
  const _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  const _Biquad.identity() : this(1, 0, 0, 0, 0);

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;
}

class _EqResponsePainter extends CustomPainter {
  _EqResponsePainter({
    required this.bands,
    required this.selectedIndex,
    required this.preampDb,
    required this.sampleRateHz,
    required this.accent,
  });

  final List<EqBand> bands;
  final int selectedIndex;
  final double preampDb;
  final double sampleRateHz;
  final Color accent;

  static const _primary = Color(0xFFEDEDED);
  static const _secondary = Color(0xFFA1A1A6);
  static const _muted = Color(0xFF85858B);
  static const _hairline = Color(0x1AFFFFFF);

  Rect _plotRect(Size size) => Rect.fromLTRB(
        52,
        16,
        math.max(72.0, size.width - 20).toDouble(),
        math.max(48.0, size.height - 32).toDouble(),
      );

  double _xForFrequency(double frequency, Rect plot) {
    final normalized = math.log(frequency / 20.0) / (math.ln10 * 3);
    return plot.left + plot.width * normalized;
  }

  double _yForGain(double gain, Rect plot) {
    return plot.top + plot.height * ((12.0 - gain) / 36.0);
  }

  _Biquad _coefficients(EqBand band) {
    if (!band.enabled) return const _Biquad.identity();
    final sampleRate = sampleRateHz;
    final frequency = band.frequencyHz
        .clamp(20.0, 20000.0)
        .clamp(20.0, sampleRate * 0.49)
        .toDouble();
    final gainDb = band.gainDb.clamp(-24.0, 12.0).toDouble();
    final q = band.q.clamp(0.1, 10.0).toDouble();
    final omega = 2.0 * math.pi * frequency / sampleRate;
    final cosine = math.cos(omega);
    final sine = math.sin(omega);
    final a = math.pow(10.0, gainDb / 40.0).toDouble();
    final alpha = sine / (2.0 * q);

    List<double> normalized(
        double b0, double b1, double b2, double a0, double a1, double a2) {
      return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];
    }

    late final List<double> c;
    switch (band.type) {
      case EqFilterType.lowPass:
        c = normalized((1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2,
            1 + alpha, -2 * cosine, 1 - alpha);
        break;
      case EqFilterType.highPass:
        c = normalized((1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2,
            1 + alpha, -2 * cosine, 1 - alpha);
        break;
      case EqFilterType.peaking:
        c = normalized(1 + alpha * a, -2 * cosine, 1 - alpha * a, 1 + alpha / a,
            -2 * cosine, 1 - alpha / a);
        break;
      case EqFilterType.lowShelf:
      case EqFilterType.highShelf:
        final slope = q.clamp(0.1, 1.0).toDouble();
        final shelfAlpha = sine /
            2 *
            math.sqrt(math.max(0.0, (a + 1 / a) * (1 / slope - 1) + 2));
        final twoSqrtAAlpha = 2 * math.sqrt(a) * shelfAlpha;
        if (band.type == EqFilterType.lowShelf) {
          c = normalized(
            a * ((a + 1) - (a - 1) * cosine + twoSqrtAAlpha),
            2 * a * ((a - 1) - (a + 1) * cosine),
            a * ((a + 1) - (a - 1) * cosine - twoSqrtAAlpha),
            (a + 1) + (a - 1) * cosine + twoSqrtAAlpha,
            -2 * ((a - 1) + (a + 1) * cosine),
            (a + 1) + (a - 1) * cosine - twoSqrtAAlpha,
          );
        } else {
          c = normalized(
            a * ((a + 1) + (a - 1) * cosine + twoSqrtAAlpha),
            -2 * a * ((a - 1) + (a + 1) * cosine),
            a * ((a + 1) + (a - 1) * cosine - twoSqrtAAlpha),
            (a + 1) - (a - 1) * cosine + twoSqrtAAlpha,
            2 * ((a - 1) - (a + 1) * cosine),
            (a + 1) - (a - 1) * cosine - twoSqrtAAlpha,
          );
        }
        break;
    }
    return _Biquad(c[0], c[1], c[2], c[3], c[4]);
  }

  double _responseDb(double frequency, List<_Biquad> filters) {
    var totalDb = preampDb;
    final omega = 2.0 * math.pi * frequency / sampleRateHz;
    final cos1 = math.cos(omega);
    final sin1 = math.sin(omega);
    final cos2 = math.cos(2.0 * omega);
    final sin2 = math.sin(2.0 * omega);
    for (final c in filters) {
      final numeratorReal = c.b0 + c.b1 * cos1 + c.b2 * cos2;
      final numeratorImaginary = -c.b1 * sin1 - c.b2 * sin2;
      final denominatorReal = 1 + c.a1 * cos1 + c.a2 * cos2;
      final denominatorImaginary = -c.a1 * sin1 - c.a2 * sin2;
      final numerator = math.sqrt(numeratorReal * numeratorReal +
          numeratorImaginary * numeratorImaginary);
      final denominator = math.sqrt(denominatorReal * denominatorReal +
          denominatorImaginary * denominatorImaginary);
      totalDb +=
          20 * math.log(math.max(numerator / denominator, 1e-9)) / math.ln10;
    }
    return totalDb.clamp(-24.0, 12.0).toDouble();
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[math.max(0, i - 1)];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[math.min(points.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawLabel(Canvas canvas, String text, Offset offset,
      {TextAlign align = TextAlign.left}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _muted,
          fontFamily: 'monospace',
          fontSize: 10,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => offset.dx - painter.width,
      TextAlign.center => offset.dx - painter.width / 2,
      _ => offset.dx,
    };
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty || size.width <= 60 || size.height <= 60) return;
    final plot = _plotRect(size);
    final gridPaint = Paint()..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = accent.withValues(alpha: 0.62)
      ..strokeWidth = 1.2;

    for (final gain in const [-24.0, -12.0, 0.0, 12.0]) {
      final y = _yForGain(gain, plot);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y),
          gain == 0 ? zeroPaint : (gridPaint..color = _hairline));
      _drawLabel(canvas, '${gain > 0 ? '+' : ''}${gain.toInt()} dB',
          Offset(plot.left - 8, y - 6),
          align: TextAlign.right);
    }

    const frequencies = <double>[
      20,
      50,
      100,
      200,
      500,
      1000,
      2000,
      5000,
      10000,
      20000
    ];
    for (final frequency in frequencies) {
      final x = _xForFrequency(frequency, plot);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom),
          gridPaint..color = _hairline);
      final label = frequency >= 1000
          ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)}k'
          : frequency.toInt().toString();
      _drawLabel(canvas, label, Offset(x, plot.bottom + 8),
          align: TextAlign.center);
    }

    final filters = bands.map(_coefficients).toList(growable: false);
    const sampleCount = 192;
    final points = <Offset>[];
    for (var i = 0; i < sampleCount; i++) {
      final t = i / (sampleCount - 1);
      final frequency = (20.0 * math.pow(1000.0, t)).toDouble();
      final gain = _responseDb(frequency, filters);
      points.add(Offset(plot.left + plot.width * t, _yForGain(gain, plot)));
    }
    canvas.drawPath(
      _smoothPath(points),
      Paint()
        ..color = _primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      final frequency = band.frequencyHz;
      final gain = band.enabled ? band.gainDb : 0.0;
      final point =
          Offset(_xForFrequency(frequency, plot), _yForGain(gain, plot));
      final selected = i == selectedIndex;
      final fill = selected ? accent : const Color(0xFF19191B);
      final stroke = selected ? accent : (band.enabled ? _secondary : _muted);
      canvas.drawCircle(point, selected ? 7 : 5, Paint()..color = fill);
      canvas.drawCircle(
        point,
        selected ? 7 : 5,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.5 : 1,
      );
      if (selected) {
        final nearRightEdge = point.dx > plot.right - 28;
        _drawLabel(
          canvas,
          '${i + 1}',
          point + Offset(nearRightEdge ? -8 : 10, -7),
          align: nearRightEdge ? TextAlign.right : TextAlign.left,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EqResponsePainter oldDelegate) {
    if (oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.preampDb != preampDb ||
        oldDelegate.sampleRateHz != sampleRateHz ||
        oldDelegate.accent != accent ||
        oldDelegate.bands.length != bands.length) {
      return true;
    }
    for (var i = 0; i < bands.length; i++) {
      if (oldDelegate.bands[i] != bands[i]) return true;
    }
    return false;
  }
}

class SpectrumStrip extends StatelessWidget {
  const SpectrumStrip({
    super.key,
    required this.binsDb,
    required this.active,
    this.accent = const Color(0xFFFFB000),
  });

  final List<double>? binsDb;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bins = binsDb;
    if (!active || bins == null || bins.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Waiting for native PCM',
          style: TextStyle(color: Color(0xFF85858B), fontSize: 12),
        ),
      );
    }
    return SizedBox.expand(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.zero,
          painter: _SpectrumPainter(bins, accent),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter(this.bins, this.accent);

  final List<double> bins;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;
    const gap = 3.0;
    final barWidth = math
        .max(1.0, (size.width - gap * (bins.length - 1)) / bins.length)
        .toDouble();
    final baseline = size.height;
    final paint = Paint()..color = accent;
    for (var i = 0; i < bins.length; i++) {
      final normalized = ((bins[i] + 72) / 78).clamp(0.0, 1.0);
      final height = math.max(2.0, normalized * size.height).toDouble();
      final left = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, baseline - height, barWidth, height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      !identical(oldDelegate.bins, bins) || oldDelegate.accent != accent;
}
