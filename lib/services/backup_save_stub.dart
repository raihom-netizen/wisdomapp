import 'dart:convert';
import 'package:share_plus/share_plus.dart';

/// Salva o backup para o usuário: no mobile/desktop abre o compartilhamento
/// para ele salvar na pasta que quiser (Arquivos, Drive, etc.).
Future<void> saveBackupFile(String filename, String jsonContent) async {
  final bytes = utf8.encode(jsonContent);
  final xFile = XFile.fromData(
    bytes,
    name: filename,
    mimeType: 'application/json',
  );
  await Share.shareXFiles(
    [xFile],
    subject: 'Backup WISDOMAPP',
    text: 'Seu backup dos dados. Salve este arquivo na pasta que preferir.',
  );
}
