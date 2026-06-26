// Navegador: imagem na área de transferência (print / recorte) + paste em captura.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

/// PNG / JPEG / GIF / WebP / BMP pelos magic bytes (tipo MIME vazio no paste).
bool _sniffRasterImageBytes(Uint8List b) {
  if (b.length < 12) return false;
  if (b[0] == 0xff && b[1] == 0xd8) return true;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) return true;
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b.length > 11 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return true;
  }
  if (b[0] == 0x42 && b[1] == 0x4d) return true;
  return false;
}

Future<Uint8List?> _readFileAsUint8(html.File file) async {
  final reader = html.FileReader();
  final done = reader.onLoadEnd.first;
  reader.readAsArrayBuffer(file);
  await done;
  final r = reader.result;
  if (r is ByteBuffer) return Uint8List.fromList(Uint8List.view(r));
  return null;
}

Future<Uint8List?> _bytesFromDataTransfer(html.DataTransfer? dt) async {
  if (dt == null) return null;
  final items = dt.items;
  if (items != null) {
    final n = items.length ?? 0;
    for (var i = 0; i < n; i++) {
      final it = items[i];
      final ty = it.type ?? '';
      if (ty.startsWith('image/')) {
        final file = it.getAsFile();
        if (file != null) {
          final b = await _readFileAsUint8(file);
          if (b != null && b.isNotEmpty) return b;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      final it = items[i];
      if (it.kind != 'file') continue;
      final ty = it.type ?? '';
      if (ty.startsWith('image/')) continue;
      if (ty.isNotEmpty && !ty.startsWith('image/')) continue;
      final file = it.getAsFile();
      if (file == null) continue;
      final b = await _readFileAsUint8(file);
      if (b != null && b.isNotEmpty && _sniffRasterImageBytes(b)) return b;
    }
  }
  final files = dt.files;
  if (files != null && files.isNotEmpty) {
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final ty = f.type;
      if (ty.startsWith('image/')) {
        final b = await _readFileAsUint8(f);
        if (b != null && b.isNotEmpty) return b;
      }
    }
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (f.type.isNotEmpty) continue;
      final b = await _readFileAsUint8(f);
      if (b != null && b.isNotEmpty && _sniffRasterImageBytes(b)) return b;
    }
  }
  return null;
}

/// Chrome/Edge: [navigator.clipboard.read] devolve [ClipboardItem], não [DataTransfer].
/// O binding Dart antigo tipa como DataTransfer e falha a ler itens — usamos interop.
Future<Uint8List?> _bytesFromClipboardReadModern() async {
  try {
    final clip = html.window.navigator.clipboard;
    if (clip == null) return null;
    final read = js_util.getProperty(clip, 'read');
    if (read == null) return null;
    final promise = js_util.callMethod<Object>(read, 'call', [clip]);
    final resolved = await js_util.promiseToFuture<Object>(promise);
    final items = js_util.dartify(resolved);
    if (items is! List) return null;
    for (final item in items) {
      if (item == null) continue;
      final typesRaw = js_util.getProperty(item as Object, 'types');
      final types = js_util.dartify(typesRaw);
      if (types is! List) continue;
      for (final mime in types) {
        final typeStr = mime?.toString() ?? '';
        if (!typeStr.startsWith('image/')) continue;
        final getType = js_util.getProperty(item, 'getType');
        if (getType == null) continue;
        final blobPromise = js_util.callMethod<Object>(getType, 'call', [item, typeStr]);
        final blob = await js_util.promiseToFuture<Object>(blobPromise);
        if (blob == null) continue;
        final bytes = await _blobToUint8(blob);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      }
    }
  } catch (_) {}
  return null;
}

Future<Uint8List?> _blobToUint8(Object blob) async {
  try {
    final p = js_util.callMethod<Object>(blob, 'arrayBuffer', []);
    final ab = await js_util.promiseToFuture<Object>(p);
    if (ab is ByteBuffer) return Uint8List.fromList(Uint8List.view(ab));
  } catch (_) {}
  try {
    final reader = html.FileReader();
    final done = reader.onLoadEnd.first;
    reader.readAsArrayBuffer(blob as html.Blob);
    await done;
    final r = reader.result;
    if (r is ByteBuffer) return Uint8List.fromList(Uint8List.view(r));
  } catch (_) {}
  return null;
}

/// Lê imagem (PNG/JPEG/WebP…) via [Navigator.clipboard.read] (ex.: botão «Colar»).
Future<Uint8List?> smartInputReadClipboardImageBytesForPaste() async {
  try {
    final modern = await _bytesFromClipboardReadModern();
    if (modern != null && modern.isNotEmpty) return modern;
    final clip = html.window.navigator.clipboard;
    if (clip == null) return null;
    final dt = await clip.read();
    return _bytesFromDataTransfer(dt);
  } catch (_) {
    return null;
  }
}

class _SmartInputWebPasteCaptureHandle {
  _SmartInputWebPasteCaptureHandle(this.listener);
  final void Function(html.Event) listener;
}

/// Regista `paste` em fase de captura no documento: se houver imagem, evita o default
/// e devolve os bytes (Ctrl+V com print no campo de texto).
Object? smartInputRegisterWebPasteImageListener(void Function(Uint8List bytes) onImage) {
  void listener(html.Event e) {
    final ce = e as html.ClipboardEvent;
    final dt = ce.clipboardData;
    if (dt == null) return;

    Future<void> deliverIfRaster(html.File file, String mime) async {
      final bytes = await _readFileAsUint8(file);
      if (bytes == null || bytes.isEmpty) return;
      if (!mime.startsWith('image/') && !_sniffRasterImageBytes(bytes)) return;
      onImage(bytes);
    }

    html.File? syncImageFile;
    html.File? sniffCandidate;

    final items = dt.items;
    if (items != null) {
      final n = items.length ?? 0;
      for (var i = 0; i < n; i++) {
        final it = items[i];
        final ty = it.type ?? '';
        if (ty.startsWith('image/')) {
          syncImageFile = it.getAsFile();
          if (syncImageFile != null) break;
        }
      }
      if (syncImageFile == null) {
        for (var i = 0; i < n; i++) {
          final it = items[i];
          if (it.kind != 'file') continue;
          final ty = it.type ?? '';
          if (ty.isNotEmpty && !ty.startsWith('image/')) continue;
          final f = it.getAsFile();
          if (f != null) {
            sniffCandidate = f;
            break;
          }
        }
      }
    }

    if (syncImageFile == null) {
      syncImageFile = () {
        final files = dt.files;
        if (files == null || files.isEmpty) return null;
        for (var i = 0; i < files.length; i++) {
          final f = files[i];
          if (f.type.startsWith('image/')) return f;
        }
        return null;
      }();
    }

    if (syncImageFile == null && sniffCandidate == null) {
      sniffCandidate = () {
        final files = dt.files;
        if (files == null || files.isEmpty) return null;
        for (var i = 0; i < files.length; i++) {
          final f = files[i];
          if (f.type.isEmpty) return f;
        }
        return null;
      }();
    }

    if (syncImageFile != null) {
      e.preventDefault();
      e.stopImmediatePropagation();
      unawaited(deliverIfRaster(syncImageFile, syncImageFile.type));
      return;
    }
    if (sniffCandidate != null) {
      e.preventDefault();
      e.stopImmediatePropagation();
      unawaited(deliverIfRaster(sniffCandidate, sniffCandidate.type));
    }
  }

  html.document.addEventListener('paste', listener, true);
  return _SmartInputWebPasteCaptureHandle(listener);
}

void smartInputUnregisterWebPasteImageListener(Object? handle) {
  if (handle is _SmartInputWebPasteCaptureHandle) {
    html.document.removeEventListener('paste', handle.listener, true);
  }
}
