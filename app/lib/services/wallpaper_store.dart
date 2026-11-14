import 'dart:typed_data';

import 'wallpaper_store_stub.dart'
    if (dart.library.io) 'wallpaper_store_io.dart' as platform;

Future<String> saveWallpaperBytes(Uint8List bytes, String extension) =>
    platform.saveWallpaperBytes(bytes, extension);

Future<Uint8List?> loadWallpaperBytes(String? path) =>
    platform.loadWallpaperBytes(path);
