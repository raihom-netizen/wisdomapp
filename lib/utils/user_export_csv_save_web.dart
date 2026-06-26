import 'dart:convert';
import 'dart:html' as html;

/// Web: download do CSV na pasta escolhida pelo navegador (geralmente “Downloads”).
Future<bool> saveCsvContent(
  String filename,
  String csvContent, {
  String dialogTitle = '',
  String shareSubject = '',
  String shareText = '',
}) async {
  final withBom = '\uFEFF$csvContent';
  final bytes = utf8.encode(withBom);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}

Future<bool> saveUserExportCsv(String filename, String csvContent) {
  return saveCsvContent(filename, csvContent);
}
