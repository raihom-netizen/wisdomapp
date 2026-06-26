import 'dart:typed_data';

/// Stub: não faz nada em plataformas não-web.
void openPdfFallback(Uint8List bytes, {String? filename}) {
  // Em mobile/desktop o Printing.layoutPdf normalmente funciona.
  // Este stub é usado apenas quando a importação condicional não resolve para web.
}
