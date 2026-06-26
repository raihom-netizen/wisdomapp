import 'dart:typed_data';

/// Colagem de imagem via clipboard rico desativada no mobile/desktop.
/// Mantemos apenas import por ficheiro/CSV/texto para evitar dependência nativa incompatível com 16 KB.
Future<Uint8List?> smartInputReadClipboardImageBytesForPaste() async => null;

/// Colagem por teclado / atalhos é tratada na web; em mobile use [ContentInsertionConfiguration] + botão Colar.
Object? smartInputRegisterWebPasteImageListener(void Function(Uint8List bytes) onImage) => null;

void smartInputUnregisterWebPasteImageListener(Object? handle) {}
