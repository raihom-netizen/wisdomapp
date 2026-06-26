import 'dart:convert';
import 'dart:html' as html;

/// No web: dispara o download do arquivo para a pasta que o usuário escolher.
Future<void> saveBackupFile(String filename, String jsonContent) async {
  final bytes = utf8.encode(jsonContent);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
