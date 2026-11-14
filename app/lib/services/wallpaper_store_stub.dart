import 'dart:typed_data';

Future<String> saveWallpaperBytes(Uint8List bytes, String extension) =>
    Future.error(UnsupportedError(
        'Custom wallpaper files are unavailable on this platform'));

Future<Uint8List?> loadWallpaperBytes(String? path) async => null;
