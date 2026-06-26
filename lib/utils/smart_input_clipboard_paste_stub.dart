import 'dart:typed_data';

/// WASM / plataforma sem `dart:html` nem `dart:io` com clipboard rico.
Future<Uint8List?> smartInputReadClipboardImageBytesForPaste() async => null;

Object? smartInputRegisterWebPasteImageListener(void Function(Uint8List bytes) onImage) => null;

void smartInputUnregisterWebPasteImageListener(Object? handle) {}
