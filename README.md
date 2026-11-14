# Driver-Sound-HRB

IEM Driver is a Flutter-based 10-band parametric EQ controller and audio test
utility for Android and Windows. The project is currently an **expert preview**,
not a validated production system-wide equalizer.

## Current capabilities

- Interactive logarithmic PEQ response graph with draggable bands and linked
  gain faders; low-pass, high-pass, shelves, and peaking filters.
- Eight local preset slots, compact share/import codes, JSON import, and
  AutoEQ/Squiglink text import/export.
- Sampled biquad response and automatic negative preamp recommendation to
  reduce positive peak gain.
- Custom accent and wallpaper with color grading; wallpaper overlay is kept
  opaque for graph legibility.
- Native low-level sine and pink-noise test signals with a live spectrum of the
  app-owned test stream.
- On Windows, a user-started, read-only WASAPI loopback mode displays a live
  spectrum of the current default playback endpoint without changing its audio.

## Platform status and limitations

| Platform | Implemented path | Important limitation |
| --- | --- | --- |
| Android 13+ (API 33; min API 28) | `AudioDeviceCallback` route detection; Oboe test signal; opt-in best-effort global `DynamicsProcessing` with `Equalizer` fallback | Session-0 effects may be denied by the ROM/OEM. These APIs expose graphic bands, not the full PEQ Q/filter/preamp model. Spectrum is from the app test signal, not other apps. |
| Windows 11 | MMDevice endpoint notifications; WASAPI test signal and read-only loopback spectrum; opt-in Equalizer APO managed include/config updates | Loopback follows the endpoint active when capture starts; after a route change, stop and restart monitoring. APO must be installed/configured for the active endpoint, and editing its Program Files config may require elevation. Hardware/APO behavior still needs PC validation. |

The UI reports whether the best-effort Android effect or APO include is active;
that status is not a guarantee of identical system-wide behavior on every
device. Real-device and APO-enabled Windows testing is still required.

## Build and test

From `app/`:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

The APK can be found at
`app/build/app/outputs/flutter-apk/app-debug.apk`. It is debug-signed and is
intended for sideloaded expert testing only.

Android release builds require JDK 17 or newer. Configure a private release
keystore via `IEM_RELEASE_STORE_FILE`, `IEM_RELEASE_STORE_PASSWORD`,
`IEM_RELEASE_KEY_ALIAS`, and `IEM_RELEASE_KEY_PASSWORD` before running
`flutter build apk --release`. Never commit the keystore or its passwords.

Windows builds require Visual Studio C++ tools, Windows SDK, CMake, and
Flutter plugin symlink support. If Flutter reports that symlinks are disabled,
enable Windows Developer Mode, then run `flutter build windows --release`.

## GitHub release workflow

`.github/workflows/release.yml` builds and attaches a signed Android APK, a
Windows installer, and a portable Windows archive when a `v*` tag is pushed.
Configure these GitHub Actions secrets first:

- `IEM_RELEASE_KEYSTORE_BASE64`
- `IEM_RELEASE_STORE_PASSWORD`
- `IEM_RELEASE_KEY_ALIAS`
- `IEM_RELEASE_KEY_PASSWORD`

The Windows installer warns if Equalizer APO is not detected. The application
folder is packaged separately from its source; do not publish the unsigned
local release APK as a distribution artifact.
