import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Baixa o PDF na web usando anchor com download — evita erro "Verifique a conexão"
/// causado por revogar o blob URL antes da aba carregar.
void openPdfFallback(Uint8List bytes, {String? filename}) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final name = (filename ?? 'RELATORIO_CONTROLE_TOTAL_APP').replaceAll(' ', '_');
  final pdfName = name.endsWith('.pdf') ? name : '$name.pdf';
  final a = html.AnchorElement(href: url)
    ..download = pdfName
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
  // Revogar após delay para o download iniciar — evita erro de conexão
  Timer(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
}
