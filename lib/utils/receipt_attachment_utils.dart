import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'receipt_file_reader.dart';

enum _ReceiptPickSource { camera, gallery, file }

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

  /// Seleciona PDF/PNG/JPG (câmera, galeria ou arquivo) com validação.
  static Future<({Uint8List bytes, String name, String mime})?> pickValidated(
    BuildContext context, {
    bool showSnack = true,
    bool showSourceChooser = true,
  }) async {
    try {
      if (showSourceChooser) {
        final source = await _askSource(context);
        if (source == null) return null;
        switch (source) {
          case _ReceiptPickSource.camera:
            return _pickFromImage(ImageSource.camera, context, showSnack: showSnack);
          case _ReceiptPickSource.gallery:
            return _pickFromImage(ImageSource.gallery, context, showSnack: showSnack);
          case _ReceiptPickSource.file:
            return _pickFromFilePicker(context, showSnack: showSnack);
        }
      }
      return _pickFromFilePicker(context, showSnack: showSnack);
    } catch (e) {
      if (showSnack && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao selecionar arquivo: ${e.toString().split('\n').first}',
            ),
          ),
        );
      }
      return null;
    }
  }

  static Future<_ReceiptPickSource?> _askSource(BuildContext context) {
    return showModalBottomSheet<_ReceiptPickSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  'Anexar comprovante',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'PDF, foto, print ou imagem da galeria (até 5 MB)',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Tirar foto'),
                subtitle: const Text('Câmera do aparelho'),
                onTap: () => Navigator.pop(ctx, _ReceiptPickSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Galeria / imagem'),
                subtitle: const Text('Print ou foto salva'),
                onTap: () => Navigator.pop(ctx, _ReceiptPickSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: const Text('PDF ou arquivo'),
                subtitle: const Text('PDF, PNG ou JPG'),
                onTap: () => Navigator.pop(ctx, _ReceiptPickSource.file),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<({Uint8List bytes, String name, String mime})?> _pickFromImage(
    ImageSource source,
    BuildContext context, {
    required bool showSnack,
  }) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      maxWidth: 2400,
      imageQuality: 88,
    );
    if (xfile == null) return null;

    final bytes = await xfile.readAsBytes();
    var name = xfile.name.trim();
    if (name.isEmpty) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      name = source == ImageSource.camera ? 'comprovante_$ts.jpg' : 'imagem_$ts.jpg';
    }
    if (!name.toLowerCase().endsWith('.jpg') &&
        !name.toLowerCase().endsWith('.jpeg') &&
        !name.toLowerCase().endsWith('.png')) {
      name = '$name.jpg';
    }

    return _packValidated(
      bytes: bytes,
      name: name,
      context: context,
      showSnack: showSnack,
    );
  }

  static Future<({Uint8List bytes, String name, String mime})?> _pickFromFilePicker(
    BuildContext context, {
    required bool showSnack,
  }) async {
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

    final bytes = await _resolvePlatformFileBytes(f);
    if (bytes == null || bytes.isEmpty) {
      if (showSnack && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível ler o arquivo. Conceda acesso à galeria/arquivos ou tente outro.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return null;
    }

    final name = f.name.trim().isNotEmpty ? f.name.trim() : 'comprovante.$ext';
    return _packValidated(
      bytes: bytes,
      name: name,
      context: context,
      showSnack: showSnack,
    );
  }

  static Future<Uint8List?> _resolvePlatformFileBytes(PlatformFile f) async {
    if (f.bytes != null && f.bytes!.isNotEmpty) return f.bytes;
    return readLocalFileBytes(f.path);
  }

  static Future<({Uint8List bytes, String name, String mime})?> _packValidated({
    required Uint8List bytes,
    required String name,
    required BuildContext context,
    required bool showSnack,
  }) async {
    if (bytes.isEmpty) {
      if (showSnack && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivo vazio.')),
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

    var ext = extensionFromName(name);
    if (ext.isEmpty) ext = 'jpg';
    if (ext == 'jpeg') ext = 'jpg';
    if (!allowedExtensions.contains(ext)) {
      if (showSnack && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arquivo inválido. Use PDF, PNG ou JPG.')),
        );
      }
      return null;
    }

    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');
    return (bytes: bytes, name: name, mime: mime);
  }
}
