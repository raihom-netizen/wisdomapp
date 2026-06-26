import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Utilitários centralizados para comprovantes (upload, URL, nome, validação).
class ReceiptAttachmentUtils {
  ReceiptAttachmentUtils._();

  static const int maxBytes = 5 * 1024 * 1024;
  static const allowedExtensions = ['pdf', 'png', 'jpg', 'jpeg'];

  static String viewUrl(Map<String, dynamic>? receipt) {
    if (receipt == null || receipt.isEmpty) return '';
    return (receipt['downloadUrl'] ??
            receipt['webViewLink'] ??
            receipt['webContentLink'] ??
            '')
        .toString()
        .trim();
  }

  static String storagePath(Map<String, dynamic>? receipt) {
    if (receipt == null || receipt.isEmpty) return '';
    return (receipt['storagePath'] ?? '').toString().trim();
  }

  static String fileName(Map<String, dynamic>? receipt) {
    if (receipt == null || receipt.isEmpty) return 'Comprovante';
    final name = (receipt['originalName'] ?? receipt['name'] ?? 'Comprovante').toString().trim();
    return name.isEmpty ? 'Comprovante' : name;
  }

  static String mimeType(Map<String, dynamic>? receipt) {
    if (receipt == null || receipt.isEmpty) return '';
    final mime = (receipt['mimeType'] ?? '').toString().trim();
    if (mime.isNotEmpty) return mime;
    return mimeFromFileName(fileName(receipt));
  }

  static String mimeFromFileName(String name) {
    final ext = extensionFromName(name);
    if (ext == 'pdf') return 'application/pdf';
    if (ext == 'png') return 'image/png';
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    return 'application/octet-stream';
  }

  static String extensionFromName(String name) {
    final n = name.trim().toLowerCase();
    final dot = n.lastIndexOf('.');
    if (dot < 0 || dot >= n.length - 1) return '';
    var ext = n.substring(dot + 1);
    if (ext == 'jpeg') ext = 'jpg';
    return ext;
  }

  static bool hasViewableReceipt(Map<String, dynamic>? receipt) {
    return viewUrl(receipt).isNotEmpty || storagePath(receipt).isNotEmpty;
  }

  /// Seleciona PDF/PNG/JPG com validação. Retorna null se cancelado ou inválido.
  static Future<({Uint8List bytes, String name, String mime})?> pickValidated(
    BuildContext context, {
    bool showSnack = true,
  }) async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return null;

      final f = pick.files.first;
      var ext = (f.extension ?? extensionFromName(f.name)).toLowerCase();
      if (ext == 'jpeg') ext = 'jpg';
      if (!allowedExtensions.contains(ext)) {
        if (showSnack && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arquivo inválido. Use PDF, PNG ou JPG.')),
          );
        }
        return null;
      }

      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (showSnack && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível ler o arquivo. Tente outro ou um tamanho menor.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return null;
      }
      if (bytes.lengthInBytes > maxBytes) {
        if (showSnack && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arquivo grande demais. Limite: 5 MB.')),
          );
        }
        return null;
      }

      final mime = ext == 'pdf'
          ? 'application/pdf'
          : (ext == 'png' ? 'image/png' : 'image/jpeg');
      final name = f.name.trim().isNotEmpty ? f.name.trim() : 'comprovante.$ext';
      return (bytes: bytes, name: name, mime: mime);
    } catch (e) {
      if (showSnack && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar arquivo: ${e.toString().split('\n').first}')),
        );
      }
      return null;
    }
  }
}
