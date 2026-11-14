import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'models/app_theme_settings.dart';
import 'models/eq_preset.dart';
import 'services/app_storage.dart';
import 'services/audio_test_service.dart';
import 'services/audio_route_service.dart';
import 'services/auto_eq_text_parser.dart';
import 'services/equalizer_apo_service.dart';
import 'services/wallpaper_store.dart';
import 'widgets/appearance_settings_dialog.dart';
import 'widgets/eq_band_slider_bank.dart';
import 'widgets/eq_response_canvas.dart';
import 'widgets/route_device_icon.dart';

void main() => runApp(const IemDriverApp());

class IemDriverApp extends StatefulWidget {
  const IemDriverApp({super.key});

  @override
  State<IemDriverApp> createState() => _IemDriverAppState();
}

class _IemDriverAppState extends State<IemDriverApp> {
  static const _background = Color(0xFF121214);
  static const _surface = Color(0xFF19191B);
  static const _raised = Color(0xFF232325);
  static const _hairline = Color(0x1AFFFFFF);
  static const _primary = Color(0xFFEDEDED);

  AppThemeSettings _themeSettings = const AppThemeSettings();

  @override
  Widget build(BuildContext context) {
    final accent = _themeSettings.accent;
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: _background,
      secondary: accent,
      onSecondary: _background,
      surface: _surface,
      onSurface: _primary,
      error: Color(0xFFE5484D),
      onError: _background,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IEM Driver',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: _background,
        fontFamily: 'Roboto',
        sliderTheme: SliderThemeData(
          activeTrackColor: accent,
          inactiveTrackColor: _raised,
          thumbColor: _primary,
          overlayColor: accent.withValues(alpha: 0.12),
          trackHeight: 2,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _raised,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      home: EqDashboard(
        themeSettings: _themeSettings,
        onThemeChanged: (settings) => setState(() => _themeSettings = settings),
      ),
    );
  }
}

class EqDashboard extends StatefulWidget {
  const EqDashboard(
      {super.key, required this.themeSettings, required this.onThemeChanged});

  final AppThemeSettings themeSettings;
  final ValueChanged<AppThemeSettings> onThemeChanged;

  @override
  State<EqDashboard> createState() => _EqDashboardState();
}

class _EqDashboardState extends State<EqDashboard> with WidgetsBindingObserver {
  static const _surface = Color(0xFF19191B);
  static const _raised = Color(0xFF232325);
  static const _hairline = Color(0x1AFFFFFF);
  static const _primary = Color(0xFFEDEDED);
  static const _secondary = Color(0xFFA1A1A6);
  static const _muted = Color(0xFF85858B);

  final AppStorage _storage = AppStorage();
  final AudioRouteService _routeService = AudioRouteService();
  final AudioTestService _audioTestService = AudioTestService();
  final EqualizerApoService _apoService = EqualizerApoService();
  static const AutoEqTextParser _autoEqParser = AutoEqTextParser();
  StreamSubscription<AudioRouteSnapshot>? _routeSubscription;
  Timer? _nativeEqTimer;
  Timer? _testFrequencyTimer;
  Timer? _spectrumTimer;
  Timer? _audioHealthTimer;
  late List<EqBand> _bands;
  List<EqPreset?> _presets = List<EqPreset?>.filled(8, null);
  AudioRouteSnapshot _routeSnapshot = const AudioRouteSnapshot(routes: []);
  Uint8List? _wallpaperBytes;
  int _selectedBand = 3;
  int _selectedSlot = 0;
  double _preampDb = 0;
  String? _activePresetName;
  bool _profileModified = false;
  bool _testAudioRunning = false;
  bool _systemSpectrumRunning = false;
  bool _spectrumReadPending = false;
  double _testFrequencyHz = 1000;
  bool _pinkNoiseEnabled = false;
  List<double>? _spectrumBins;
  String _systemEqMessage = 'Checking system EQ support';
  bool _systemEqAvailable = false;
  EqualizerApoStatus? _apoStatus;

  Color get _accent => widget.themeSettings.accent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bands = List.generate(10, (index) {
      final frequency = (20.0 * math.pow(1000.0, index / 9.0)).toDouble();
      return EqBand(
        enabled: index == 1 || index == 4 || index == 7,
        type: EqFilterType.peaking,
        frequencyHz: frequency,
        gainDb: index == 1 ? 2.5 : (index == 4 ? -1.8 : 1.2),
        q: 0.9,
      );
    });
    _loadSavedSettings();
    _routeSubscription = _routeService.watch().listen(
          _onRouteSnapshot,
          onError: (Object _) {},
        );
    unawaited(_refreshSystemEqStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeSubscription?.cancel();
    _nativeEqTimer?.cancel();
    _testFrequencyTimer?.cancel();
    _spectrumTimer?.cancel();
    _audioHealthTimer?.cancel();
    unawaited(_audioTestService.stopTestAudio());
    unawaited(_audioTestService.stopSystemSpectrumCapture());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (defaultTargetPlatform == TargetPlatform.android &&
        state != AppLifecycleState.resumed &&
        _testAudioRunning) {
      unawaited(_stopTestTone());
    }
  }

  Future<void> _loadSavedSettings() async {
    try {
      final results = await Future.wait<Object>([
        _storage.loadPresets(),
        _storage.loadTheme(),
      ]);
      final presets = results[0] as List<EqPreset?>;
      final theme = results[1] as AppThemeSettings;
      final wallpaper = await loadWallpaperBytes(theme.wallpaperPath);
      if (!mounted) return;
      setState(() {
        _presets = presets;
        _wallpaperBytes = wallpaper;
      });
      widget.onThemeChanged(theme);
      final route = _activeRoute;
      if (route != null) {
        final routeKeys = route.matchingProfileKeys.toSet();
        final matchingSlot = _presets.indexWhere(
          (preset) => preset != null && routeKeys.contains(preset.deviceKey),
        );
        if (matchingSlot >= 0) _applyPreset(matchingSlot);
      }
      _scheduleNativeEqUpdate();
    } catch (_) {
      // The EQ remains usable if platform storage is unavailable (for example in a widget test).
    }
  }

  void _onRouteSnapshot(AudioRouteSnapshot next) {
    final previousRoute = _routeSnapshot.activeRoute;
    final nextRoute = next.activeRoute;
    final routeChanged = nextRoute?.profileKey != previousRoute?.profileKey ||
        nextRoute?.id != previousRoute?.id;
    setState(() {
      _routeSnapshot = next;
    });
    if (!routeChanged || nextRoute == null) return;

    final routeKeys = nextRoute.matchingProfileKeys.toSet();
    final matchingSlot = _presets.indexWhere(
      (preset) => preset != null && routeKeys.contains(preset.deviceKey),
    );
    if (matchingSlot >= 0) {
      _applyPreset(matchingSlot);
    } else if (nextRoute.kind == 'jack') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showJackProfilePicker(nextRoute));
      });
    }
  }

  Future<void> _showJackProfilePicker(AudioRoute route) async {
    final availableSlots = [
      for (var index = 0; index < _presets.length; index++)
        if (_presets[index] != null) index,
    ];
    if (!mounted || availableSlots.isEmpty) return;
    final selectedSlot = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose IEM profile',
                style: TextStyle(
                  color: _primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${route.name} connected · select a saved preset',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _secondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              for (final slot in availableSlots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    (slot + 1).toString().padLeft(2, '0'),
                    style: const TextStyle(
                      color: _muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                  title: Text(_presets[slot]!.name),
                  subtitle: Text('${_presets[slot]!.bands.length} PEQ bands'),
                  onTap: () => Navigator.pop(sheetContext, slot),
                ),
            ],
          ),
        ),
      ),
    );
    if (selectedSlot != null && mounted) _applyPreset(selectedSlot);
  }

  EqBand get _activeBand => _bands[_selectedBand];

  void _setBand(int index, EqBand band) {
    setState(() {
      _bands = List.of(_bands);
      _bands[index] = band;
      _profileModified = true;
    });
    _scheduleNativeEqUpdate();
  }

  void _selectBand(int index) {
    setState(() {
      _selectedBand = index;
    });
  }

  void _setSelectedBand(EqBand band) => _setBand(_selectedBand, band);

  void _setPreamp(double value) {
    setState(() {
      _preampDb = value.clamp(-24.0, 12.0).toDouble();
      _profileModified = true;
    });
    _scheduleNativeEqUpdate();
  }

  AudioRoute? get _activeRoute => _routeSnapshot.activeRoute;
  AudioRoute? get _displayRoute => _routeSnapshot.detectedRoute;
  EqPreset? get _selectedPreset => _presets[_selectedSlot];

  void _applyPreset(int slot) {
    final preset = _presets[slot];
    if (preset == null) return;
    setState(() {
      _selectedSlot = slot;
      _bands = List.of(preset.bands);
      _preampDb = preset.preampDb;
      _activePresetName = preset.name;
      _profileModified = false;
    });
    _scheduleNativeEqUpdate();
  }

  void _scheduleNativeEqUpdate() {
    if (!_audioTestService.isSupported) return;
    _nativeEqTimer?.cancel();
    _nativeEqTimer = Timer(const Duration(milliseconds: 140), () {
      unawaited(_sendNativeEqConfiguration());
    });
  }

  Future<void> _sendNativeEqConfiguration() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final status = await _apoService.apply(
          bands: _bands,
          preampDb: _preampDb,
        );
        if (!mounted) return;
        setState(() {
          _apoStatus = status;
          _systemEqAvailable = status.enabled;
          _systemEqMessage = status.message;
        });
        return;
      }
      final accepted = await _audioTestService.configureEq(
        bands: _bands,
        preampDb: _preampDb,
      );
      final status = await _audioTestService.readSystemEqStatus();
      if (!mounted) return;
      setState(() {
        _systemEqAvailable = status['available'] == true && accepted;
        _systemEqMessage = status['message']?.toString() ??
            'Android system output EQ is unavailable';
      });
      if (!accepted && status.isEmpty && mounted) {
        _showMessage('Android system output EQ could not be initialized');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _systemEqAvailable = false;
          _systemEqMessage = 'System EQ update failed: $error';
        });
      }
    }
  }

  Future<void> _refreshSystemEqStatus() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final status = await _apoService.inspect();
        if (!mounted) return;
        setState(() {
          _apoStatus = status;
          _systemEqAvailable = status.enabled;
          _systemEqMessage = status.message;
        });
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await _audioTestService.readSystemEqStatus();
        if (!mounted) return;
        setState(() {
          _systemEqAvailable = status['available'] == true;
          _systemEqMessage = status['message']?.toString() ??
              'Android system output EQ is not active yet';
        });
      } else {
        setState(
            () => _systemEqMessage = 'Available in Android and Windows builds');
      }
    } catch (error) {
      if (mounted) {
        setState(
            () => _systemEqMessage = 'System EQ status unavailable: $error');
      }
    }
  }

  Future<void> _toggleSystemEqConnection() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (_apoStatus?.enabled == true) {
        final status = await _apoService.disable();
        if (!mounted) return;
        setState(() {
          _apoStatus = status;
          _systemEqAvailable = false;
          _systemEqMessage = status.message;
        });
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connect Equalizer APO'),
          content: const Text(
            'IEM Driver will back up config.txt, create a managed PEQ include, '
            'and add one Include line. Windows may require administrator permission. '
            'The original file is preserved for rollback.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Connect'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final status =
          await _apoService.enable(bands: _bands, preampDb: _preampDb);
      if (!mounted) return;
      setState(() {
        _apoStatus = status;
        _systemEqAvailable = status.enabled;
        _systemEqMessage = status.message;
      });
      if (!status.enabled) _showMessage(status.message);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      if (_systemEqAvailable) {
        await _audioTestService.disableAndroidSystemEq();
        if (mounted) {
          setState(() {
            _systemEqAvailable = false;
            _systemEqMessage = 'Android system output EQ is inactive';
          });
        }
      } else {
        await _sendNativeEqConfiguration();
      }
    }
  }

  Future<void> _toggleTestTone() async {
    if (!_audioTestService.isSupported) {
      _showMessage(
          'Live audio testing is available in the Windows or Android build.');
      return;
    }
    if (_testAudioRunning) {
      await _stopTestTone();
      return;
    }

    if (_systemSpectrumRunning) await _stopSystemSpectrum();

    try {
      final started = await _audioTestService.startTestTone(
        _testFrequencyHz,
        pinkNoise: _pinkNoiseEnabled,
      );
      if (!started) throw StateError('No audio output device is available.');
      if (!mounted) {
        await _audioTestService.stopTestAudio();
        return;
      }
      setState(() => _testAudioRunning = true);
      _startSpectrumTimers();
      await _readNativeSpectrum();
    } catch (error) {
      if (mounted) _showMessage('Could not start test tone: $error');
    }
  }

  Future<void> _toggleSystemSpectrum() async {
    if (!_audioTestService.isSystemSpectrumSupported) return;
    if (_systemSpectrumRunning) {
      await _stopSystemSpectrum();
      return;
    }
    if (_testAudioRunning) await _stopTestTone();

    try {
      final started = await _audioTestService.startSystemSpectrumCapture();
      if (!started) {
        throw StateError('No default playback endpoint is available.');
      }
      if (!mounted) {
        await _audioTestService.stopSystemSpectrumCapture();
        return;
      }
      setState(() => _systemSpectrumRunning = true);
      _startSpectrumTimers();
      await _readNativeSpectrum();
    } catch (error) {
      if (mounted) _showMessage('Could not monitor PC audio: $error');
    }
  }

  void _startSpectrumTimers() {
    _spectrumTimer?.cancel();
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      unawaited(_readNativeSpectrum());
    });
    _audioHealthTimer?.cancel();
    _audioHealthTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_checkNativeAudioHealth());
    });
  }

  Future<void> _stopTestTone() async {
    _spectrumTimer?.cancel();
    _spectrumTimer = null;
    _audioHealthTimer?.cancel();
    _audioHealthTimer = null;
    try {
      await _audioTestService.stopTestAudio();
    } catch (error) {
      if (mounted) _showMessage('Could not stop test tone cleanly: $error');
    }
    if (mounted) {
      setState(() {
        _testAudioRunning = false;
        _spectrumBins = null;
      });
    }
  }

  Future<void> _stopSystemSpectrum() async {
    _spectrumTimer?.cancel();
    _spectrumTimer = null;
    _audioHealthTimer?.cancel();
    _audioHealthTimer = null;
    try {
      await _audioTestService.stopSystemSpectrumCapture();
    } catch (error) {
      if (mounted) _showMessage('Could not stop PC audio monitor: $error');
    }
    if (mounted) {
      setState(() {
        _systemSpectrumRunning = false;
        _spectrumBins = null;
      });
    }
  }

  Future<void> _readNativeSpectrum() async {
    if (_spectrumReadPending ||
        (!_testAudioRunning && !_systemSpectrumRunning)) {
      return;
    }
    final readSystemAudio = _systemSpectrumRunning;
    _spectrumReadPending = true;
    try {
      final bins = await _audioTestService.readSpectrum(
        systemAudio: readSystemAudio,
      );
      final sameModeStillActive =
          readSystemAudio ? _systemSpectrumRunning : _testAudioRunning;
      if (mounted && sameModeStillActive && bins.length == 64) {
        setState(() => _spectrumBins = bins);
      }
    } catch (_) {
      // Keep the last valid display if the native analyzer is momentarily busy.
    } finally {
      _spectrumReadPending = false;
    }
  }

  Future<void> _checkNativeAudioHealth() async {
    final checkingSystemAudio = _systemSpectrumRunning;
    if (!_testAudioRunning && !checkingSystemAudio) return;
    try {
      final active = checkingSystemAudio
          ? await _audioTestService.isSystemSpectrumCaptureActive()
          : await _audioTestService.isTestAudioActive();
      final modeStillActive =
          checkingSystemAudio ? _systemSpectrumRunning : _testAudioRunning;
      if (!active && modeStillActive && mounted) {
        _spectrumTimer?.cancel();
        _audioHealthTimer?.cancel();
        setState(() {
          _testAudioRunning = false;
          _systemSpectrumRunning = false;
          _spectrumBins = null;
        });
        _showMessage(checkingSystemAudio
            ? 'PC audio capture stopped. Restart the monitor to retry.'
            : 'Audio output stopped. Reconnect the device and retry.');
      }
    } catch (_) {
      // Keep the active state during a transient method-channel failure.
    }
  }

  void _setTestFrequency(double normalized) {
    final frequency = (20 * math.pow(1000.0, normalized)).toDouble();
    setState(() => _testFrequencyHz = frequency);
    if (!_testAudioRunning) return;
    _testFrequencyTimer?.cancel();
    _testFrequencyTimer = Timer(const Duration(milliseconds: 40), () {
      unawaited(_audioTestService.setTestFrequency(_testFrequencyHz));
    });
  }

  Future<void> _saveSelectedSlot() async {
    final previousPreset = _selectedPreset;
    final nameController = TextEditingController(
        text: previousPreset?.name ?? 'Preset ${_selectedSlot + 1}');
    final activeRouteKeys =
        _activeRoute?.matchingProfileKeys.toSet() ?? const <String>{};
    var bindToDevice = previousPreset?.deviceKey != null &&
        (_activeRoute == null ||
            activeRouteKeys.contains(previousPreset?.deviceKey));
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          title: Text('Save to slot ${_selectedSlot + 1}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 32,
                decoration: const InputDecoration(
                    labelText: 'Preset name', counterText: ''),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: bindToDevice,
                onChanged: _activeRoute == null
                    ? null
                    : (value) =>
                        setDialogState(() => bindToDevice = value ?? false),
                title: const Text('Auto-apply for this device',
                    style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  _activeRoute?.name ?? 'Connect an audio device first',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                activeColor: _accent,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(dialogContext, (name, bindToDevice));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null || !mounted) return;

    final preset = EqPreset(
      name: result.$1,
      bands: List.of(_bands),
      preampDb: _preampDb,
      deviceKey: result.$2
          ? (_activeRoute?.profileKey ?? previousPreset?.deviceKey)
          : null,
    );
    final presets = List<EqPreset?>.of(_presets)..[_selectedSlot] = preset;
    setState(() {
      _presets = presets;
      _activePresetName = preset.name;
      _profileModified = false;
    });
    await _persistPresets();
  }

  Future<void> _persistPresets() async {
    try {
      await _storage.savePresets(_presets);
    } catch (error) {
      if (mounted) _showMessage('Preset could not be saved: $error');
    }
  }

  Future<void> _shareSelectedPreset() async {
    final preset = _selectedPreset;
    if (preset == null) return;
    try {
      if (kIsWeb || Theme.of(context).platform == TargetPlatform.windows) {
        await Clipboard.setData(ClipboardData(text: preset.encodeShareCode()));
        if (mounted) _showMessage('Preset code copied to clipboard');
        return;
      }
      await SharePlus.instance.share(ShareParams(
        text: preset.encodeShareCode(),
        title: 'IEM Driver · ${preset.name}',
        subject: 'IEM Driver EQ preset: ${preset.name}',
      ));
    } catch (error) {
      if (mounted) _showMessage('Preset sharing is unavailable: $error');
    }
  }

  Future<void> _importPreset() async {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: const ['json']);
    if (file == null) return;
    try {
      final content = utf8.decode(await file.readAsBytes());
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Preset file must contain a JSON object');
      }
      final preset = EqPreset.fromJson(Map<String, dynamic>.from(decoded));
      final presets = List<EqPreset?>.of(_presets)..[_selectedSlot] = preset;
      setState(() => _presets = presets);
      _applyPreset(_selectedSlot);
      await _persistPresets();
      if (mounted) {
        _showMessage('Imported ${preset.name} to slot ${_selectedSlot + 1}');
      }
    } catch (error) {
      if (mounted) _showMessage('Preset file could not be imported: $error');
    }
  }

  Future<void> _importAutoEqText() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (file == null) return;
    try {
      final source = utf8.decode(await file.readAsBytes());
      final name =
          file.name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');
      final preset = _autoEqParser.parse(source, name: name);
      final presets = List<EqPreset?>.of(_presets)..[_selectedSlot] = preset;
      setState(() => _presets = presets);
      _applyPreset(_selectedSlot);
      await _persistPresets();
      if (mounted) {
        _showMessage('Imported AutoEQ text to slot ${_selectedSlot + 1}');
      }
    } catch (error) {
      if (mounted) _showMessage('AutoEQ text could not be imported: $error');
    }
  }

  Future<void> _exportAutoEqText() async {
    try {
      final text = _autoEqParser.encode(bands: _bands, preampDb: _preampDb);
      final safeName = (_activePresetName ?? 'iem-driver-eq')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final uri = await FilePicker.saveFile(
        fileName: '${safeName.isEmpty ? 'iem-driver-eq' : safeName}.txt',
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
        dialogTitle: 'Export AutoEQ text',
      );
      if (uri != null && mounted) _showMessage('AutoEQ text exported');
    } catch (error) {
      if (mounted) _showMessage('AutoEQ text could not be exported: $error');
    }
  }

  Future<void> _importPresetCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Import preset code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'IEM Driver code',
            hintText: 'IEM1-...',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || !mounted) return;
    try {
      await _installImportedPreset(EqPreset.fromShareCode(code));
    } catch (error) {
      if (mounted) _showMessage('Preset code could not be imported: $error');
    }
  }

  Future<void> _installImportedPreset(EqPreset preset) async {
    final presets = List<EqPreset?>.of(_presets)..[_selectedSlot] = preset;
    setState(() => _presets = presets);
    _applyPreset(_selectedSlot);
    await _persistPresets();
    if (mounted) {
      _showMessage('Imported ${preset.name} to slot ${_selectedSlot + 1}');
    }
  }

  Future<void> _clearSelectedSlot() async {
    final selectedPreset = _selectedPreset;
    if (selectedPreset == null) return;
    final presets = List<EqPreset?>.of(_presets)..[_selectedSlot] = null;
    setState(() {
      _presets = presets;
      if (_activePresetName == selectedPreset.name) {
        _activePresetName = null;
        _profileModified = true;
      }
    });
    await _persistPresets();
  }

  Future<void> _openAppearance() async {
    final settings = await showDialog<AppThemeSettings>(
      context: context,
      builder: (context) => AppearanceSettingsDialog(
        initialSettings: widget.themeSettings,
        initialWallpaperBytes: _wallpaperBytes,
      ),
    );
    if (settings == null || !mounted) return;
    final wallpaper = await loadWallpaperBytes(settings.wallpaperPath);
    if (!mounted) return;
    setState(() => _wallpaperBytes = wallpaper);
    widget.onThemeChanged(settings);
    try {
      await _storage.saveTheme(settings);
    } catch (error) {
      if (mounted) {
        _showMessage('Appearance settings could not be saved: $error');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_wallpaperBytes != null)
            ColorFiltered(
              colorFilter: colorGradeFilter(widget.themeSettings),
              child: Image.memory(_wallpaperBytes!, fit: BoxFit.cover),
            ),
          ColoredBox(
            color: _wallpaperBytes == null
                ? const Color(0xFF121214)
                : const Color(0xFF121214).withValues(alpha: 0.85),
          ),
          if (_wallpaperBytes != null)
            ColoredBox(
              color: widget.themeSettings.tint
                  .withValues(alpha: widget.themeSettings.tintStrength * 0.18),
            ),
          SafeArea(
            child: LayoutBuilder(builder: (context, viewport) {
              final pageWidth = math.min(viewport.maxWidth, 1440.0).toDouble();
              final horizontalPadding = viewport.maxWidth < 640 ? 16.0 : 32.0;
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: pageWidth,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        horizontalPadding, 28, horizontalPadding, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildDeviceCard(),
                        const SizedBox(height: 16),
                        _buildPresetSlots(),
                        const SizedBox(height: 24),
                        LayoutBuilder(builder: (context, constraints) {
                          if (constraints.maxWidth >= 960) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 7, child: _buildResponseCard()),
                                const SizedBox(width: 24),
                                Expanded(flex: 4, child: _buildBandControls()),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              _buildResponseCard(),
                              const SizedBox(height: 20),
                              _buildBandControls(),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('IEM Driver',
                  style: TextStyle(
                      color: _primary,
                      fontSize: 28,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('Parametric equalizer',
                  style: TextStyle(color: _secondary, fontSize: 14)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Appearance',
          onPressed: _openAppearance,
          icon: Icon(Icons.palette_outlined, color: _accent),
        ),
      ],
    );
  }

  Widget _buildDeviceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final route = RouteDeviceIcon(
          route: _displayRoute,
          accent: _accent,
          isActive: _activeRoute != null,
        );
        final profile = _statusColumn(
          icon: Icons.tune,
          label: 'Profile',
          value: _activePresetName == null
              ? 'Unsaved EQ'
              : '$_activePresetName${_profileModified ? ' · edited' : ''}',
        );
        final routeAndProfile = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [route, const SizedBox(height: 20), profile],
              )
            : Row(children: [
                Expanded(child: route),
                const SizedBox(width: 24),
                Expanded(child: profile),
              ]);
        final isWindows = defaultTargetPlatform == TargetPlatform.windows;
        final isAndroid = defaultTargetPlatform == TargetPlatform.android;
        final connectLabel = _systemEqAvailable
            ? 'Disconnect system EQ'
            : isWindows
                ? 'Connect Equalizer APO'
                : 'Enable Android system EQ';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            routeAndProfile,
            const SizedBox(height: 18),
            const Divider(height: 1, color: _hairline),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'SYSTEM EQ  ${_systemEqAvailable ? 'ACTIVE' : 'INACTIVE'}',
                  style: TextStyle(
                    color: _systemEqAvailable ? _accent : _secondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                if (isAndroid || isWindows)
                  OutlinedButton.icon(
                    onPressed: isWindows && _apoStatus?.installed == false
                        ? null
                        : _toggleSystemEqConnection,
                    icon: Icon(_systemEqAvailable
                        ? Icons.link_off
                        : Icons.link_outlined),
                    label: Text(connectLabel),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _systemEqMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildPresetSlots() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final actions = Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Save current EQ to this slot',
                  onPressed: _saveSelectedSlot,
                  icon: const Icon(Icons.save_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Share selected preset code',
                  onPressed:
                      _selectedPreset == null ? null : _shareSelectedPreset,
                  icon: const Icon(Icons.ios_share_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Import preset code into this slot',
                  onPressed: _importPresetCode,
                  icon: const Icon(Icons.key_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Import preset JSON into this slot',
                  onPressed: _importPreset,
                  icon: const Icon(Icons.file_open_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Import AutoEQ or Squiglink text',
                  onPressed: _importAutoEqText,
                  icon: const Icon(Icons.text_snippet_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Export current EQ as AutoEQ text',
                  onPressed: _exportAutoEqText,
                  icon: const Icon(Icons.save_alt_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Clear selected slot',
                  onPressed:
                      _selectedPreset == null ? null : _clearSelectedSlot,
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
              ],
            );
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Preset slots',
                    style: TextStyle(
                        color: _primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                    'Eight local profiles · select a slot, then save or import',
                    style: TextStyle(color: _secondary, fontSize: 12)),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: actions)
                ],
              );
            }
            return Row(children: [Expanded(child: heading), actions]);
          }),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth < 520 ? 2 : 4;
            final gap = 8.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: List.generate(8, (index) {
                final preset = _presets[index];
                final selected = index == _selectedSlot;
                return SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: () {
                      if (preset == null) {
                        setState(() => _selectedSlot = index);
                      } else {
                        _applyPreset(index);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      height: 58,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            selected ? _accent.withValues(alpha: 0.1) : _raised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: selected
                                ? _accent.withValues(alpha: 0.7)
                                : _hairline),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text('${index + 1}'.padLeft(2, '0'),
                                style: TextStyle(
                                    color: selected ? _accent : _muted,
                                    fontSize: 11,
                                    fontFamily: 'monospace')),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              preset?.name ?? 'Empty slot',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: preset == null ? _muted : _primary,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _statusColumn(
      {required IconData icon, required String label, required String value}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(color: _primary, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResponseCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Frequency response',
                    style: TextStyle(
                        color: _primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
              ),
              Text('10 bands',
                  style: const TextStyle(
                      color: _muted, fontSize: 12, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 4),
          const Text('20 Hz–20 kHz  ·  −24 to +12 dB',
              style: TextStyle(color: _secondary, fontSize: 12)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            return EqResponseCanvas(
              bands: _bands,
              selectedIndex: _selectedBand,
              height: constraints.maxWidth < 480 ? 248 : 320,
              preampDb: _preampDb,
              accent: _accent,
              onSelectionChanged: _selectBand,
              onBandChanged: _setBand,
            );
          }),
          const SizedBox(height: 8),
          EqBandSliderBank(
            bands: _bands,
            selectedIndex: _selectedBand,
            accent: _accent,
            onSelectionChanged: _selectBand,
            onGainChanged: (index, gainDb) => _setBand(
              index,
              _bands[index].copyWith(enabled: true, gainDb: gainDb),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _hairline),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text('Spectrum',
                    style: TextStyle(
                        color: _primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
              Text(
                _systemSpectrumRunning
                    ? 'SYSTEM LOOPBACK'
                    : _testAudioRunning
                        ? 'LIVE TEST'
                        : 'FFT',
                style: const TextStyle(
                    color: _muted, fontSize: 11, fontFamily: 'monospace'),
              ),
              const SizedBox(width: 4),
              if (_audioTestService.isSystemSpectrumSupported)
                IconButton(
                  tooltip: _systemSpectrumRunning
                      ? 'Stop PC audio monitor'
                      : 'Monitor PC audio',
                  onPressed: _toggleSystemSpectrum,
                  icon: Icon(
                    _systemSpectrumRunning
                        ? Icons.stop_circle_outlined
                        : Icons.graphic_eq_outlined,
                    color: _systemSpectrumRunning ? _accent : null,
                  ),
                ),
              IconButton(
                tooltip:
                    _testAudioRunning ? 'Stop test tone' : 'Play test tone',
                onPressed:
                    _audioTestService.isSupported ? _toggleTestTone : null,
                icon: Icon(
                  _testAudioRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
              ),
            ],
          ),
          if (_audioTestService.isSupported) ...[
            Row(
              children: [
                const Expanded(
                  child: Text('Test tone',
                      style: TextStyle(color: _secondary, fontSize: 12)),
                ),
                Text('${_testFrequencyHz.round()} Hz',
                    style: const TextStyle(
                        color: _secondary,
                        fontSize: 12,
                        fontFamily: 'monospace')),
                const SizedBox(width: 8),
                DropdownButton<bool>(
                  value: _pinkNoiseEnabled,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  onChanged: _testAudioRunning || _systemSpectrumRunning
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _pinkNoiseEnabled = value);
                          }
                        },
                  items: const [
                    DropdownMenuItem(value: false, child: Text('Sine')),
                    DropdownMenuItem(value: true, child: Text('Pink noise')),
                  ],
                ),
              ],
            ),
            Slider(
              value: (math.log(_testFrequencyHz / 20) / (math.ln10 * 3))
                  .clamp(0.0, 1.0)
                  .toDouble(),
              onChanged: _setTestFrequency,
            ),
            if (_audioTestService.isSystemSpectrumSupported) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _toggleSystemSpectrum,
                  icon: Icon(_systemSpectrumRunning
                      ? Icons.stop_circle_outlined
                      : Icons.monitor_heart_outlined),
                  label: Text(_systemSpectrumRunning
                      ? 'Stop PC audio monitor'
                      : 'Monitor PC audio'),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Read-only capture from the current Windows playback device.',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            SizedBox(
              height: 72,
              child: SpectrumStrip(
                binsDb: _spectrumBins,
                active: _testAudioRunning || _systemSpectrumRunning,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Low-level tone. Reduce listening volume before playback.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ] else
            const SizedBox(
              height: 72,
              child: SpectrumStrip(binsDb: null, active: false),
            ),
        ],
      ),
    );
  }

  Widget _buildBandControls() {
    final band = _activeBand;
    final gainControlEnabled =
        band.type != EqFilterType.lowPass && band.type != EqFilterType.highPass;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Parametric EQ',
                    style: TextStyle(
                        color: _primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
              ),
              Text('${_selectedBand + 1} / 10',
                  style: const TextStyle(
                      color: _muted, fontSize: 12, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 16),
          _sliderControl(
            title: 'Preamp',
            valueText: '${_preampDb.toStringAsFixed(1)} dB',
            normalizedValue: ((_preampDb + 24) / 36).clamp(0.0, 1.0).toDouble(),
            onChanged: (value) => _setPreamp(-24 + value * 36),
            trailing: TextButton(
              onPressed: () => _setPreamp(
                AutoEqTextParser.recommendedPreampDb(_bands),
              ),
              child: const Text('Auto'),
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<EqFilterType>(
            initialValue: band.type,
            decoration: const InputDecoration(labelText: 'Filter type'),
            dropdownColor: _raised,
            items: EqFilterType.values
                .map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(_filterName(type)),
                    ))
                .toList(),
            onChanged: (type) {
              if (type != null) {
                _setSelectedBand(band.copyWith(type: type, enabled: true));
              }
            },
          ),
          const SizedBox(height: 20),
          _sliderControl(
            title: 'Frequency',
            valueText: '${band.frequencyHz.round()} Hz',
            normalizedValue:
                (math.log(band.frequencyHz.clamp(20.0, 20000.0) / 20.0) /
                        (math.ln10 * 3))
                    .clamp(0.0, 1.0)
                    .toDouble(),
            onChanged: (value) => _setSelectedBand(band.copyWith(
              enabled: true,
              frequencyHz: (20 * math.pow(1000.0, value)).toDouble(),
            )),
          ),
          const SizedBox(height: 16),
          _sliderControl(
            title: 'Gain',
            valueText: gainControlEnabled
                ? '${band.gainDb.toStringAsFixed(1)} dB'
                : 'Not used by this filter',
            normalizedValue:
                ((band.gainDb + 24) / 36).clamp(0.0, 1.0).toDouble(),
            enabled: gainControlEnabled,
            onChanged: (value) => _setSelectedBand(band.copyWith(
              enabled: true,
              gainDb: -24 + value * 36,
            )),
          ),
          const SizedBox(height: 16),
          _sliderControl(
            title: band.type == EqFilterType.lowShelf ||
                    band.type == EqFilterType.highShelf
                ? 'Q / slope'
                : 'Q factor',
            valueText: band.q.toStringAsFixed(2),
            normalizedValue:
                (math.log(band.q.clamp(0.1, 10.0) / 0.1) / (math.ln10 * 2))
                    .clamp(0.0, 1.0)
                    .toDouble(),
            onChanged: (value) => _setSelectedBand(band.copyWith(
              enabled: true,
              q: (0.1 * math.pow(100.0, value)).toDouble(),
            )),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _raised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _hairline),
            ),
            child: Row(
              children: [
                const Expanded(
                    child: Text('Band state',
                        style: TextStyle(color: _secondary, fontSize: 13))),
                Switch(
                  value: band.enabled,
                  activeThumbColor: _accent,
                  onChanged: (enabled) =>
                      _setSelectedBand(band.copyWith(enabled: enabled)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderControl({
    required String title,
    required String valueText,
    required double normalizedValue,
    required ValueChanged<double> onChanged,
    bool enabled = true,
    Widget? trailing,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(color: _secondary, fontSize: 13))),
              if (trailing != null) trailing,
              if (trailing != null) const SizedBox(width: 8),
              Text(valueText,
                  style: const TextStyle(
                      color: _primary, fontSize: 12, fontFamily: 'monospace')),
            ],
          ),
          Slider(
            value: normalizedValue,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  static String _filterName(EqFilterType type) => switch (type) {
        EqFilterType.lowPass => 'Low-pass',
        EqFilterType.highPass => 'High-pass',
        EqFilterType.lowShelf => 'Low shelf',
        EqFilterType.highShelf => 'High shelf',
        EqFilterType.peaking => 'Peaking',
      };
}
