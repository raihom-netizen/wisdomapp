import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:share_plus/share_plus.dart';

/// Desktop: diálogo “Salvar como”. Android/iOS: compartilhar arquivo CSV (pode salvar em Downloads ou enviar ao PC).
///
/// Retorna `false` se o usuário cancelar o diálogo de salvar (somente desktop).
Future<bool> saveCsvContent(
  String filename,
  String csvContent, {
  String dialogTitle = 'Salvar arquivo CSV',
  String shareSubject = 'Exportação CSV',
  String shareText = 'Abra no Excel ou salve na pasta desejada.',
}) async {
  final withBom = '\uFEFF$csvContent';
  final bytes = utf8.encode(withBom);

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path != null && path.isNotEmpty) {
      final target =
          path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
      final file = File(target);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    }
    return false;
  }

  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: filename,
        mimeType: 'text/csv',
      ),
    ],
    subject: shareSubject,
    text: shareText,
  );
  return true;
}

Future<bool> saveUserExportCsv(String filename, String csvContent) {
  return saveCsvContent(
    filename,
    csvContent,
    dialogTitle: 'Salvar lista de usuários (CSV)',
    shareSubject: 'Exportação de usuários — CSV',
    shareText:
        'Lista: nome, e-mail, plano e vencimento da licença. Salve na pasta desejada (Downloads, PC, etc.).',
  );
}
