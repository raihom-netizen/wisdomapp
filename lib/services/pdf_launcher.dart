import 'dart:typed_data';

import 'pdf_launcher_stub.dart'
    if (dart.library.html) 'pdf_launcher_web.dart' as impl;

/// Abre ou baixa o PDF (web) ou não faz nada (outras plataformas).
/// Usado como fallback quando Printing.layoutPdf falha.
/// [filename] nome sugerido ao salvar (ex: RELATORIO FINANCEIRO CONTROLE TOTAL APP.pdf).
void openPdfFallback(Uint8List bytes, {String? filename}) {
  impl.openPdfFallback(bytes, filename: filename);
}
