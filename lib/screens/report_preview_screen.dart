import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../services/pdf_launcher.dart';
import '../services/relatorio_service.dart';
import '../theme/app_colors.dart';

/// Tela de pré-visualização do relatório PDF: usuário vê o preview primeiro,
/// pode ampliar/reduzir livremente (pinch ou botões), depois compartilhar, imprimir ou salvar.
/// Sempre abre com zoom padrão (1.0); configurações da tela de relatórios são preservadas.
class ReportPreviewScreen extends StatefulWidget {
  final Uint8List bytes;
  final String filename;

  const ReportPreviewScreen({
    super.key,
    required this.bytes,
    required this.filename,
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  final TransformationController _transformationController = TransformationController();
  static const double _minScale = 0.4;
  static const double _maxScale = 4.0;
  static const double _zoomStep = 1.25;

  static String _sanitizeFilename(String name) {
    String s = name.trim();
    if (!s.toLowerCase().endsWith('.pdf')) s = '$s.pdf';
    return s.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  double _getCurrentScale() {
    final m = _transformationController.value.getMaxScaleOnAxis();
    return m.clamp(_minScale, _maxScale);
  }

  void _zoomIn() {
    final scale = (_getCurrentScale() * _zoomStep).clamp(_minScale, _maxScale);
    _transformationController.value = Matrix4.identity()..scale(scale);
  }

  void _zoomOut() {
    final scale = (_getCurrentScale() / _zoomStep).clamp(_minScale, _maxScale);
    _transformationController.value = Matrix4.identity()..scale(scale);
  }

  void _zoomReset() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  static const _iconBtnStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(48, 48)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final name = _sanitizeFilename(widget.filename);
    final isNarrow = MediaQuery.sizeOf(context).width < 560;

    /// Em telas estreitas (Android/iPhone), evita overflow na AppBar — mesmo padrão da tela Relatórios.
    Widget narrowActionsMenu() {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
        tooltip: 'Zoom, compartilhar, imprimir, salvar',
        color: Colors.white,
        surfaceTintColor: Colors.white,
        onSelected: (value) {
          switch (value) {
            case 'zoom_out':
              _zoomOut();
              break;
            case 'zoom_in':
              _zoomIn();
              break;
            case 'zoom_reset':
              _zoomReset();
              break;
            case 'share':
              _share(context);
              break;
            case 'print':
              _print(context);
              break;
            case 'save':
              _save(context);
              break;
          }
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(
            value: 'zoom_out',
            child: ListTile(leading: Icon(Icons.zoom_out_rounded), title: Text('Reduzir zoom'), contentPadding: EdgeInsets.zero),
          ),
          PopupMenuItem(
            value: 'zoom_in',
            child: ListTile(leading: Icon(Icons.zoom_in_rounded), title: Text('Ampliar zoom'), contentPadding: EdgeInsets.zero),
          ),
          PopupMenuItem(
            value: 'zoom_reset',
            child: ListTile(leading: Icon(Icons.fit_screen_rounded), title: Text('Zoom padrão'), contentPadding: EdgeInsets.zero),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: 'share',
            child: ListTile(leading: Icon(Icons.share_rounded), title: Text('Compartilhar'), contentPadding: EdgeInsets.zero),
          ),
          PopupMenuItem(
            value: 'print',
            child: ListTile(leading: Icon(Icons.print_rounded), title: Text('Imprimir'), contentPadding: EdgeInsets.zero),
          ),
          PopupMenuItem(
            value: 'save',
            child: ListTile(leading: Icon(Icons.save_alt_rounded), title: Text('Salvar / abrir PDF'), contentPadding: EdgeInsets.zero),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          style: _iconBtnStyle,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        title: Text(
          name.length > 40 ? '${name.substring(0, 37)}...' : name,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
        actions: isNarrow
            ? [narrowActionsMenu()]
            : [
                IconButton(
                  style: _iconBtnStyle,
                  icon: const Icon(Icons.zoom_out_rounded),
                  tooltip: 'Reduzir',
                  onPressed: _zoomOut,
                ),
                IconButton(
                  style: _iconBtnStyle,
                  icon: const Icon(Icons.zoom_in_rounded),
                  tooltip: 'Ampliar',
                  onPressed: _zoomIn,
                ),
                IconButton(
                  style: _iconBtnStyle,
                  icon: const Icon(Icons.fit_screen_rounded),
                  tooltip: 'Zoom padrão',
                  onPressed: _zoomReset,
                ),
                IconButton(
                  style: _iconBtnStyle,
                  icon: const Icon(Icons.share_rounded),
                  tooltip: 'Compartilhar',
                  onPressed: () => _share(context),
                ),
                IconButton(
                  style: _iconBtnStyle,
                  icon: const Icon(Icons.print_rounded),
                  tooltip: 'Imprimir',
                  onPressed: () => _print(context),
                ),
                IconButton(
                  style: _iconBtnStyle,
                  icon: const Icon(Icons.save_alt_rounded),
                  tooltip: 'Salvar na pasta local',
                  onPressed: () => _save(context),
                ),
              ],
      ),
      body: ColoredBox(
        color: Colors.white,
        child: SafeArea(
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: _minScale,
            maxScale: _maxScale,
            clipBehavior: Clip.none,
            child: PdfPreview(
              build: (PdfPageFormat format) => Future.value(widget.bytes),
              allowPrinting: false,
              allowSharing: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              initialPageFormat: PdfPageFormat.a4,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    try {
      final name = _sanitizeFilename(widget.filename);
      if (context.mounted) {
        await RelatorioService.sharePdfBytes(widget.bytes, name);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao compartilhar: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _print(BuildContext context) async {
    final name = _sanitizeFilename(widget.filename);
    try {
      await Printing.layoutPdf(name: name, onLayout: (_) async => widget.bytes);
    } catch (e) {
      if (e.toString().contains('MissingPluginException') ||
          e.toString().contains('printPdf') ||
          e.toString().contains('No implementation') ||
          e.toString().contains('layoutPdf')) {
        openPdfFallback(widget.bytes, filename: name);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impressão: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _save(BuildContext context) {
    final name = _sanitizeFilename(widget.filename);
    openPdfFallback(widget.bytes, filename: name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salvo. Verifique a pasta de downloads.')),
      );
    }
  }
}
