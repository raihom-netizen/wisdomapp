import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/pdf_launcher.dart';
import '../theme/app_colors.dart';
import '../utils/receipt_attachment_utils.dart';
import 'anexo_viewer_stub.dart' if (dart.library.html) 'anexo_viewer_web.dart' as anexo_web;

/// Exibe comprovante (PDF ou imagem) dentro do app.
class AnexoViewerScreen extends StatefulWidget {
  final String url;
  final String? fileName;
  final String? storagePath;
  final String? mimeType;
  final Future<http.Response>? prefetchResponse;

  const AnexoViewerScreen({
    super.key,
    required this.url,
    this.fileName,
    this.storagePath,
    this.mimeType,
    this.prefetchResponse,
  });

  @override
  State<AnexoViewerScreen> createState() => _AnexoViewerScreenState();
}

class _AnexoViewerScreenState extends State<AnexoViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  bool _webEmbedFallback = false;

  bool get _isPdf {
    final name = _resolvedFileName.toLowerCase();
    if (name.endsWith('.pdf')) return true;
    final mime = (widget.mimeType ?? '').toLowerCase();
    if (mime == 'application/pdf') return true;
    if (_bytes != null && _bytes!.length >= 5) {
      return _bytes![0] == 0x25 &&
          _bytes![1] == 0x50 &&
          _bytes![2] == 0x44 &&
          _bytes![3] == 0x46;
    }
    return false;
  }

  String get _resolvedFileName {
    final n = (widget.fileName ?? '').trim();
    if (n.isNotEmpty) return n;
    return _isPdf ? 'comprovante.pdf' : 'comprovante.jpg';
  }

  String get _mimeType {
    final fromWidget = (widget.mimeType ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    return ReceiptAttachmentUtils.mimeFromFileName(_resolvedFileName);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Uint8List?> _loadViaStorageSdk(String path) async {
    try {
      final data = await FirebaseStorage.instance.ref(path).getData(ReceiptAttachmentUtils.maxBytes);
      if (data != null && data.isNotEmpty) return data;
    } catch (e) {
      debugPrint('AnexoViewer storage getData: $e');
    }
    return null;
  }

  Future<Uint8List?> _loadViaHttp(String url) async {
    if (url.trim().isEmpty) return null;
    try {
      final resp = widget.prefetchResponse != null
          ? await widget.prefetchResponse!
          : await http.get(Uri.parse(url));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
      debugPrint('AnexoViewer http ${resp.statusCode}');
    } catch (e) {
      debugPrint('AnexoViewer http: $e');
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _bytes = null;
      _webEmbedFallback = false;
    });

    final path = (widget.storagePath ?? '').trim();
    final url = widget.url.trim();

    if (path.isNotEmpty) {
      final fromSdk = await _loadViaStorageSdk(path);
      if (fromSdk != null && mounted) {
        setState(() {
          _bytes = fromSdk;
          _loading = false;
        });
        return;
      }
    }

    if (url.isNotEmpty) {
      final fromHttp = await _loadViaHttp(url);
      if (fromHttp != null && mounted) {
        setState(() {
          _bytes = fromHttp;
          _loading = false;
        });
        return;
      }
    }

    if (!mounted) return;
    if (kIsWeb && url.isNotEmpty) {
      setState(() {
        _loading = false;
        _webEmbedFallback = true;
      });
      return;
    }

    setState(() {
      _loading = false;
      _error = 'Não foi possível visualizar o arquivo.\nHouve um problema na exibição deste anexo.';
    });
  }

  Future<void> _abrirEmNovaAba() async {
    final url = widget.url.trim();
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link do anexo indisponível.')),
        );
      }
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link. Copie e cole no navegador.')),
      );
    }
  }

  Future<void> _compartilhar(BuildContext context) async {
    if (_bytes == null || _bytes!.isEmpty) return;
    try {
      final xfile = XFile.fromData(_bytes!, name: _resolvedFileName, mimeType: _mimeType);
      await Share.shareXFiles([xfile], text: 'Comprovante WISDOMAPP');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao compartilhar: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _baixar(BuildContext context) {
    if (_bytes == null || _bytes!.isEmpty) return;
    try {
      if (_isPdf) {
        openPdfFallback(_bytes!, filename: _resolvedFileName);
      } else {
        Share.shareXFiles(
          [XFile.fromData(_bytes!, name: _resolvedFileName, mimeType: _mimeType)],
          text: 'Comprovante',
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao baixar: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _resolvedFileName;
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextButton.icon(
            onPressed: () {
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            label: const Text('Voltar'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ),
        leadingWidth: 100,
        title: Text(
          title.length > 35 ? '${title.substring(0, 32)}...' : title,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
        actions: [
          if (kIsWeb || widget.url.trim().isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Abrir em nova aba',
              onPressed: _abrirEmNovaAba,
            ),
          if (_bytes != null && _bytes!.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: () => _compartilhar(context),
              tooltip: 'Compartilhar',
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () => _baixar(context),
              tooltip: 'Baixar',
            ),
          ],
          if (_error != null || _webEmbedFallback)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
              tooltip: 'Tentar novamente',
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white70),
            SizedBox(height: 16),
            Text('Carregando anexo...', style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      );
    }

    if (_webEmbedFallback) {
      return anexo_web.buildAnexoWebViewer(
        widget.url,
        fileName: _resolvedFileName,
        onRetry: _load,
      );
    }

    if (_error != null) {
      return _errorPanel(
        title: 'Não foi possível visualizar o arquivo',
        subtitle: _error!,
        showRetry: true,
      );
    }

    if (_bytes == null || _bytes!.isEmpty) {
      return _errorPanel(
        title: 'Arquivo vazio',
        subtitle: 'O comprovante não contém dados.',
        showRetry: true,
      );
    }

    if (_isPdf) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: PdfPreview(
          build: (PdfPageFormat format) => Future.value(_bytes!),
          allowPrinting: false,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          initialPageFormat: PdfPageFormat.a4,
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.memory(
              _bytes!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _errorPanel(
                title: 'Não foi possível visualizar o arquivo',
                subtitle: 'Houve um problema na exibição desta imagem.',
                showRetry: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorPanel({
    required String title,
    required String subtitle,
    bool showRetry = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (showRetry) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
              if (widget.url.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _abrirEmNovaAba,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Abrir em nova aba'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
