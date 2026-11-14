import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> saveWallpaperBytes(Uint8List bytes, String extension) async {
  final safeExtension = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
  final supportDirectory = await getApplicationSupportDirectory();
  final wallpaperDirectory =
      Directory('${supportDirectory.path}${Platform.pathSeparator}appearance');
  await wallpaperDirectory.create(recursive: true);
  final destination = File(
      '${wallpaperDirectory.path}${Platform.pathSeparator}wallpaper.$safeExtension');
  final temporary = File('${destination.path}.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  if (await destination.exists()) await destination.delete();
  return (await temporary.rename(destination.path)).path;
}

Future<Uint8List?> loadWallpaperBytes(String? path) async {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}
