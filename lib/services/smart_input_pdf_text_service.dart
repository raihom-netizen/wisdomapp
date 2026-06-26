import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';

import 'bank_notification_parser.dart';
import 'smart_input_image_ocr_service.dart';
import '../utils/smart_input_ocr_recognized_postprocess.dart';

/// Extrai texto de PDF (fatura / extrato) para o fluxo de lançamento expresso.
abstract final class SmartInputPdfTextService {
  SmartInputPdfTextService._();

  static bool _pdfrxReady = false;

  static Future<void> _ensurePdfrx() async {
    if (_pdfrxReady) return;
    await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
    _pdfrxReady = true;
  }

  /// Heurística: nome do ficheiro → [FinanceBankPreset.id] quando reconhecido.
  static String? presetIdFromFileName(String fileName) {
    final u = fileName.toUpperCase();
    if (u.contains('BRADESCO')) return 'bradesco';
    if (u.contains('ITAU') || u.contains('ITAÚ')) return 'itau';
    if (u.contains('SANTANDER')) return 'santander';
    if (u.contains('NUBANK')) return 'nubank';
    if (u.contains('CAIXA')) return 'caixa';
    if (u.contains('BANCO DO BRASIL') || u.contains('_BB_')) return 'bb';
    if (u.contains('INTER')) return 'inter';
    if (u.contains('C6')) return 'c6';
    if (u.contains('PICPAY')) return 'picpay';
    if (u.contains('MERCADO PAGO')) return 'mercadopago';
    return null;
  }

  /// Texto ainda parece binário / estrutura PDF (falha comum quando o ficheiro é lido como UTF-8 em vez de PDF).
  /// Público para o ecrã de lançamento expresso evitar regex sobre megabytes e limpar o campo.
  static bool textLooksLikePdfBinary(String s) => _looksLikeRawPdfOrBinary(s);

  static bool _looksLikeRawPdfOrBinary(String s) {
    final t = s.trim();
    if (t.length < 32) return false;
    if (t.startsWith('%PDF')) return true;
    if (t.contains('endstream') && t.contains('FlateDecode')) return true;
    var ctrl = 0;
    for (var i = 0; i < t.length && i < 4000; i++) {
      final c = t.codeUnitAt(i);
      if (c < 9 || (c > 13 && c < 32)) ctrl++;
    }
    return ctrl > 80;
  }

  static Future<String> extractPlainText(Uint8List bytes, {String sourceName = 'documento.pdf'}) async {
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(bytes, sourceName: sourceName);
    try {
      await doc.loadPagesProgressively();
      final sb = StringBuffer();
      for (final page in doc.pages) {
        final loaded = await page.waitForLoaded(timeout: const Duration(seconds: 12));
        final p = loaded ?? page;
        final raw = await p.loadText();
        if (raw != null && raw.fullText.trim().isNotEmpty) {
          sb.writeln(raw.fullText);
        }
      }
      var plain = sb.toString();
      if (plain.trim().isEmpty || _looksLikeRawPdfOrBinary(plain)) {
        try {
          final ocr = await extractTextWithOcrOnFirstPages(bytes, sourceName: sourceName);
          if (ocr.trim().length > plain.trim().length) plain = ocr;
        } catch (_) {}
      }
      return plain;
    } finally {
      await doc.dispose();
    }
  }

  /// Primeiras [maxPages] páginas renderizadas + OCR (faturas escaneadas sem texto embutido).
  static Future<String> extractTextWithOcrOnFirstPages(
    Uint8List bytes, {
    String sourceName = 'documento.pdf',
    int maxPages = 5,
  }) async {
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(bytes, sourceName: sourceName);
    TextRecognizer? rec;
    final sb = StringBuffer();
    try {
      if (SmartInputImageOcrService.mlKitTextRecognitionSupported) {
        rec = TextRecognizer(script: TextRecognitionScript.latin);
      }
      await doc.loadPagesProgressively();
      final total = doc.pages.length;
      final n = total > maxPages ? maxPages : total;
      for (var i = 0; i < n; i++) {
        try {
          final page = doc.pages[i];
          final loaded = await page.waitForLoaded(timeout: const Duration(seconds: 15));
          final p = loaded ?? page;
          final img = await p.render(fullWidth: 1100);
          if (img == null) continue;
          try {
            String pageText = '';
            if (rec != null) {
              final input = InputImage.fromBytes(
                bytes: img.pixels,
                metadata: InputImageMetadata(
                  size: Size(img.width.toDouble(), img.height.toDouble()),
                  rotation: InputImageRotation.rotation0deg,
                  format: InputImageFormat.bgra8888,
                  bytesPerRow: img.width * 4,
                ),
              );
              final recognized = await rec.processImage(input);
              pageText = SmartInputOcrRecognizedPostprocess.apply(recognized.text.trim());
            } else {
              pageText = await SmartInputImageOcrService.recognizeWithTextifyFromBgra8888(
                pixels: img.pixels,
                width: img.width,
                height: img.height,
              );
            }
            if (pageText.isNotEmpty) sb.writeln(pageText);
          } finally {
            img.dispose();
          }
        } catch (_) {}
      }
    } finally {
      try {
        await rec?.close();
      } catch (_) {}
      await doc.dispose();
    }
    return sb.toString();
  }

  /// Extrai texto e tenta montar lançamentos (zona de compras da fatura, etc.).
  /// Se o PDF não tiver camada de texto, tenta OCR nas primeiras páginas.
  static Future<List<BankNotificationParseResult>> parseTransactionsFromPdfBytes(
    Uint8List bytes, {
    String sourceName = 'documento.pdf',
  }) async {
    final plain = await extractPlainText(bytes, sourceName: sourceName);
    final preset = presetIdFromFileName(sourceName);
    var rows = BankNotificationParser.parseFromFaturaPdfPlainText(plain);
    if (rows.length < 2) {
      rows = BankNotificationParser.parseManyForBatch(plain);
    }
    if (rows.length < 2) {
      try {
        final ocrText = await extractTextWithOcrOnFirstPages(bytes, sourceName: sourceName);
        if (ocrText.trim().isNotEmpty) {
          var r2 = BankNotificationParser.parseFromFaturaPdfPlainText(ocrText);
          if (r2.length < 2) r2 = BankNotificationParser.parseManyForBatch(ocrText);
          if (r2.length > rows.length) rows = r2;
        }
      } catch (_) {}
    }
    if (preset == null) return rows;
    return rows.map((r) => r.copyWith(suggestedPresetId: preset)).toList();
  }
}
