import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalFileBytes(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
