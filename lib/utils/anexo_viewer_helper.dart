import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/anexo_viewer_screen.dart';
import 'receipt_attachment_utils.dart';

/// Exibe o preview do anexo (PDF/imagem) em painel na mesma tela — não abre outra rota.
void mostrarAnexoNaMesmaTela(
  BuildContext context, {
  required String url,
  String fileName = 'Comprovante',
  String? storagePath,
  String? mimeType,
}) {
  if (url.trim().isEmpty && (storagePath == null || storagePath.trim().isEmpty)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há anexo para este lançamento.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final trimmed = url.trim();
  final Future<http.Response>? prefetch =
      (!kIsWeb && trimmed.isNotEmpty) ? http.get(Uri.parse(trimmed)) : null;
  _openAnexoSheet(
    context,
    url: url,
    fileName: fileName,
    storagePath: storagePath,
    mimeType: mimeType,
    prefetchResponse: prefetch,
  );
}

/// Abre comprovante a partir do mapa `receipt` do Firestore.
void mostrarComprovanteReceipt(BuildContext context, Map<String, dynamic> receipt) {
  if (!ReceiptAttachmentUtils.hasViewableReceipt(receipt)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há comprovante anexado.')),
      );
    }
    return;
  }
  mostrarAnexoNaMesmaTela(
    context,
    url: ReceiptAttachmentUtils.viewUrl(receipt),
    fileName: ReceiptAttachmentUtils.fileName(receipt),
    storagePath: ReceiptAttachmentUtils.storagePath(receipt),
    mimeType: ReceiptAttachmentUtils.mimeType(receipt),
  );
}

void _openAnexoSheet(
  BuildContext context, {
  required String url,
  required String fileName,
  String? storagePath,
  String? mimeType,
  Future<http.Response>? prefetchResponse,
}) {
  try {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (_, __) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnexoViewerScreen(
            url: url,
            fileName: fileName,
            storagePath: storagePath,
            mimeType: mimeType,
            prefetchResponse: prefetchResponse,
          ),
        ),
      ),
    );
  } catch (e, st) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o anexo. Tente novamente.'),
          backgroundColor: Color(0xFFB00020),
        ),
      );
    }
    debugPrint('mostrarAnexoNaMesmaTela: $e\n$st');
  }
}
