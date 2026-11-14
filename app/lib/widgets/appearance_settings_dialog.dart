import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/app_theme_settings.dart';
import '../services/wallpaper_store.dart';

class AppearanceSettingsDialog extends StatefulWidget {
  const AppearanceSettingsDialog({
    super.key,
    required this.initialSettings,
    required this.initialWallpaperBytes,
  });

  final AppThemeSettings initialSettings;
  final Uint8List? initialWallpaperBytes;

  @override
  State<AppearanceSettingsDialog> createState() =>
      _AppearanceSettingsDialogState();
}

class _AppearanceSettingsDialogState extends State<AppearanceSettingsDialog> {
  late AppThemeSettings _draft;
  Uint8List? _wallpaperBytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSettings;
    _wallpaperBytes = widget.initialWallpaperBytes;
  }

  Future<void> _pickWallpaper() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > 15 * 1024 * 1024 ||
          !_isSupportedImage(bytes)) {
        throw const FormatException(
            'Choose a valid JPG or PNG image under 15 MB');
      }
      final extension = file.extension?.toLowerCase() == 'png' ? 'png' : 'jpg';
      final path = await saveWallpaperBytes(bytes, extension);
      if (!mounted) return;
      setState(() {
        _wallpaperBytes = bytes;
        _draft = _draft.copyWith(wallpaperPath: path);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallpaper could not be loaded: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isSupportedImage(Uint8List bytes) {
    const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length >= pngSignature.length &&
        List<int>.generate(pngSignature.length, (index) => bytes[index])
                .toString() ==
            pngSignature.toString()) {
      return true;
    }
    return bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
  }

  void _updateAccent({double? hue, double? saturation, double? brightness}) {
    final hsv = HSVColor.fromColor(_draft.accent);
    final next = hsv
        .withHue(hue ?? hsv.hue)
        .withSaturation(saturation ?? hsv.saturation)
        .withValue(brightness ?? hsv.value)
        .toColor();
    setState(() => _draft = _draft.copyWith(accentValue: next.toARGB32()));
  }

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(_draft.accent);
    return AlertDialog(
      backgroundColor: const Color(0xFF19191B),
      title: const Text('Appearance'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_wallpaperBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 132,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(
                          colorFilter: colorGradeFilter(_draft),
                          child:
                              Image.memory(_wallpaperBytes!, fit: BoxFit.cover),
                        ),
                        const ColoredBox(color: Color(0xC7121214)),
                        ColoredBox(
                          color: _draft.tint
                              .withValues(alpha: _draft.tintStrength * 0.18),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _wallpaperBytes == null
                          ? 'No wallpaper selected'
                          : 'JPG / PNG wallpaper',
                      style: const TextStyle(
                          color: Color(0xFFA1A1A6), fontSize: 13),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _pickWallpaper,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                        _wallpaperBytes == null ? 'Choose image' : 'Replace'),
                  ),
                  if (_wallpaperBytes != null)
                    IconButton(
                      tooltip: 'Remove wallpaper',
                      onPressed: () => setState(() {
                        _wallpaperBytes = null;
                        _draft = _draft.copyWith(clearWallpaper: true);
                      }),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Accent color', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              _sliderRow('Hue', hsv.hue, 0, 360,
                  (value) => _updateAccent(hue: value), '${hsv.hue.round()}°'),
              _sliderRow(
                  'Saturation',
                  hsv.saturation,
                  0.35,
                  1,
                  (value) => _updateAccent(saturation: value),
                  '${(hsv.saturation * 100).round()}%'),
              _sliderRow(
                  'Brightness',
                  hsv.value,
                  0.65,
                  1,
                  (value) => _updateAccent(brightness: value),
                  '${(hsv.value * 100).round()}%'),
              const SizedBox(height: 12),
              const Text('Color grading', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: const [
                  Color(0xFF121214),
                  Color(0xFF17232A),
                  Color(0xFF302819),
                  Color(0xFF1B2922),
                ]
                    .map((color) => _TintSwatch(
                          color: color,
                          onTap: () => setState(() => _draft =
                              _draft.copyWith(tintValue: color.toARGB32())),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              _sliderRow(
                'Tint strength',
                _draft.tintStrength,
                0,
                0.9,
                (value) => setState(
                    () => _draft = _draft.copyWith(tintStrength: value)),
                '${(_draft.tintStrength * 100).round()}%',
              ),
              _sliderRow(
                'Saturation',
                _draft.saturation,
                0,
                1.5,
                (value) =>
                    setState(() => _draft = _draft.copyWith(saturation: value)),
                '${(_draft.saturation * 100).round()}%',
              ),
              _sliderRow(
                'Brightness',
                _draft.brightness,
                -0.3,
                0.3,
                (value) =>
                    setState(() => _draft = _draft.copyWith(brightness: value)),
                '${(_draft.brightness * 100).round()}%',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : () => Navigator.pop(context, _draft),
            child: const Text('Apply')),
      ],
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String valueText,
  ) {
    return Row(
      children: [
        SizedBox(
            width: 84,
            child: Text(label,
                style:
                    const TextStyle(color: Color(0xFFA1A1A6), fontSize: 12))),
        Expanded(
            child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                onChanged: onChanged)),
        SizedBox(
            width: 44,
            child: Text(valueText,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
      ],
    );
  }
}

class _TintSwatch extends StatelessWidget {
  const _TintSwatch({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
        ),
      );
}
