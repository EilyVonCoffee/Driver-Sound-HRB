# IEM Driver — expert test build

This build combines the Flutter PEQ UI, native test-signal engine, device-route
status, preset sharing, and AutoEQ text tools. It is for expert evaluation; it
has not yet passed physical-device or Windows installer qualification.

## Android test APK

The debug-signed APK is at:

`build/app/outputs/flutter-apk/app-debug.apk`

For a smaller, optimized internal test package, use
`build/app/outputs/flutter-apk/app-release-test.apk`. It is release-mode code
signed with the Android debug certificate solely for sideloaded evaluation; it
is not an official distribution build and must not be published as the app's
release signature.

Transfer it to an Android 10+ device (min API 28; target API 34) and install it
for sideloaded testing. It includes Oboe sine/pink-noise test output and
best-effort session-0 system EQ. Many Android ROMs may refuse the global effect;
even when granted, it is graphic EQ and does not apply PEQ Q/filter shape or
preamp. On Android, spectrum currently analyzes the app-owned test signal, not
Spotify, YouTube, games, or other apps.

Lower system volume before starting a test signal. It is low-level digitally,
but that does not guarantee a safe acoustic SPL at the listener's ear.

## Windows 11

The Windows route listener, WASAPI test engine, and read-only WASAPI loopback
spectrum capture compile as a standalone native target. The loopback monitor
captures the current default playback endpoint only while enabled; stop and
restart it after changing Windows output devices. A full Flutter Windows release
build and Inno Setup installer compile have succeeded locally. Equalizer APO
integration manages a dedicated include and backs up `config.txt`; the active
APO endpoint and write permissions must be verified on the test PC. Running
IEM Driver elevated may be required to change the APO configuration.

Windows spectrum now has a read-only WASAPI loopback source in addition to the
app-owned test signal. Native and full Flutter compilation are verified, but
live capture and route-change behavior still require testing on Windows audio.

## Checks completed in the current workspace

- `flutter analyze`: clean after loopback UI integration.
- `flutter test`: all 17 tests passed.
- Android release APK compilation: succeeded, but the local APK is unsigned
  because no release keystore was configured; do not distribute it.
- A separate release-mode test APK was signed with the debug certificate and
  verified with `apksigner`; it is suitable for internal installation only.
- Android debug APK: built and signature verified with the development key.
- Windows `iem_windows_endpoint` native CMake target, including loopback capture:
  compiled successfully.
- Full Flutter Windows release build: succeeded after enabling Developer Mode.
- Inno Setup compiled `dist/IEM-Driver-Setup-v0.1.0.exe`; the portable archive
  was also assembled. Installation and live Windows audio/APO behavior remain
  untested.

For a signed Android release, provide `IEM_RELEASE_STORE_FILE`,
`IEM_RELEASE_STORE_PASSWORD`, `IEM_RELEASE_KEY_ALIAS`, and
`IEM_RELEASE_KEY_PASSWORD`. The GitHub release workflow additionally expects
the base64-encoded keystore secret `IEM_RELEASE_KEYSTORE_BASE64`.
