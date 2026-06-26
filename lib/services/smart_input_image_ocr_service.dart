import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, debugPrint, kDebugMode, kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:textify/models/textify_config.dart';
import 'package:textify/textify.dart';

import '../utils/smart_input_ocr_recognized_postprocess.dart';
import 'functions_service.dart';

/// OCR para o lançamento expresso: **web** = Cloud Vision (Google) com login, **móvel** = ML Kit e, se ainda
/// vazio, **Cloud Vision**; fallback **Textify** (e desktop).
abstract final class SmartInputImageOcrService {
  SmartInputImageOcrService._();

  /// Maior lado da imagem antes do Textify (menos RAM, mais estável que foto a 12 MP em raw).
  static const List<int> _kDecodeMaxEdgePx = [1680, 1200, 880];

  /// O plugin `google_mlkit_text_recognition` só expõe implementação nativa em Android/iOS.
  static bool get mlKitTextRecognitionSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  static Textify? _textifyBalanced;
  static Textify? _textifyFast;

  static Future<Textify> _ensureBalanced() async {
    _textifyBalanced ??= Textify(config: TextifyConfig.balanced);
    await _textifyBalanced!.init();
    return _textifyBalanced!;
  }

  static Future<Textify> _ensureFast() async {
    _textifyFast ??= Textify(config: TextifyConfig.fast);
    await _textifyFast!.init();
    return _textifyFast!;
  }

  static bool _bytesLookLikeJpeg(Uint8List b) => b.length >= 2 && b[0] == 0xff && b[1] == 0xd8;

  static bool _bytesLookLikePng(Uint8List b) =>
      b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47;

  static bool _bytesLookLikeGif(Uint8List b) =>
      b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38;

  static bool _bytesLookLikeWebp(Uint8List b) =>
      b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;

  /// BMP clássico (ex.: alguns prints no Windows).
  static bool _bytesLookLikeBmp(Uint8List b) => b.length >= 14 && b[0] == 0x42 && b[1] == 0x4d;

  /// Garante formato raster comum; evita descodificar lixo e mensagens crípticas.
  static void _throwIfNotRasterImage(Uint8List bytes) {
    if (bytes.length < 12) {
      throw FormatException('Ficheiro demasiado pequeno para ser uma imagem.');
    }
    if (_bytesLookLikeJpeg(bytes) ||
        _bytesLookLikePng(bytes) ||
        _bytesLookLikeGif(bytes) ||
        _bytesLookLikeWebp(bytes) ||
        _bytesLookLikeBmp(bytes)) {
      return;
    }
    throw FormatException('Use JPEG, PNG, GIF, WebP ou BMP (não PDF).');
  }

  /// Descodifica com limite no maior lado (decode nativo mais leve que pixel buffer a tamanho completo).
  /// Na web, [ImmutableBuffer]/[ImageDescriptor] pode falhar com alguns PNG — cai para [instantiateImageCodec].
  static Future<ui.Image> _decodeBounded(Uint8List bytes, int maxEdge) async {
    try {
      return await _decodeBoundedViaDescriptor(bytes, maxEdge);
    } catch (_) {
      return _decodeBoundedLegacy(bytes, maxEdge);
    }
  }

  static Future<ui.Image> _decodeBoundedViaDescriptor(Uint8List bytes, int maxEdge) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      buffer.dispose();
      rethrow;
    }

    final ui.Codec codec;
    try {
      final w = descriptor.width;
      final h = descriptor.height;
      if (w <= 0 || h <= 0) {
        throw FormatException('Imagem com dimensões inválidas.');
      }
      final int longEdge = w > h ? w : h;
      if (longEdge <= maxEdge) {
        codec = await descriptor.instantiateCodec();
      } else if (w >= h) {
        codec = await descriptor.instantiateCodec(targetWidth: maxEdge);
      } else {
        codec = await descriptor.instantiateCodec(targetHeight: maxEdge);
      }
    } finally {
      descriptor.dispose();
    }

    try {
      if (codec.frameCount < 1) {
        throw FormatException('Não foi possível ler esta imagem (sem frames).');
      }
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      buffer.dispose();
    }
  }

  /// Fallback se [ImageDescriptor.encoded] falhar (formatos menos comuns).
  static Future<ui.Image> _decodeBoundedLegacy(Uint8List bytes, int maxEdge) async {
    final codec = await ui.instantiateImageCodec(bytes);
    ui.Image? img;
    try {
      if (codec.frameCount < 1) {
        throw FormatException('Não foi possível ler esta imagem.');
      }
      img = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    return _scaleDownToMaxEdge(img, maxEdge);
  }

  static Future<ui.Image> _scaleDownToMaxEdge(ui.Image img, int maxEdge) async {
    final m = img.width > img.height ? img.width : img.height;
    if (m <= maxEdge) return img;

    final scale = maxEdge / m;
    final nw = max(1, (img.width * scale).round());
    final nh = max(1, (img.height * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, nw.toDouble(), nh.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final pic = recorder.endRecording();
    final out = await pic.toImage(nw, nh);
    pic.dispose();
    img.dispose();
    return out;
  }

  /// Textify pode lançar `StateError` («Bad state: No element») com bandas vazias; tratamos e tentamos outra config/tamanho.
  static Future<String> _textifyExtractBalancedThenFast(ui.Image image) async {
    for (final Future<Textify> Function() ensure in <Future<Textify> Function()>[
      _ensureBalanced,
      _ensureFast,
    ]) {
      try {
        final t = await ensure();
        t.clear();
        final s = (await t.getTextFromImage(image: image)).trim();
        if (s.isNotEmpty) return SmartInputOcrRecognizedPostprocess.apply(s);
      } on StateError {
        continue;
      } catch (_) {
        continue;
      }
    }
    return '';
  }

  static Future<String> _recognizeWithTextifyPipeline(Uint8List bytes) async {
    _throwIfNotRasterImage(bytes);
    for (final maxEdge in _kDecodeMaxEdgePx) {
      ui.Image? img;
      try {
        img = await _decodeBounded(bytes, maxEdge);
        final s = await _textifyExtractBalancedThenFast(img);
        if (s.isNotEmpty) return s;
      } finally {
        img?.dispose();
      }
    }
    return '';
  }

  /// JPEG/PNG (galeria, `readAsBytes` da web, etc.).
  static Future<String> recognizeWithTextifyFromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return '';
    // Cópia contígua: buffers vindos do FileReader/clipboard podem ser revistos pelo GC antes do OCR terminar.
    final owned = Uint8List.fromList(bytes);
    try {
      return await _recognizeWithTextifyPipeline(owned);
    } on FormatException {
      rethrow;
    } catch (e) {
      final hint = kDebugMode ? ' (${e.runtimeType})' : '';
      throw FormatException(
        'Não foi possível abrir ou processar esta imagem. '
        'Tente PNG ou JPEG (Ficheiro / print) ou copie o texto dos lançamentos.$hint',
      );
    }
  }

  /// Pixels BGRA8888 (ex.: render de página PDF).
  static Future<String> recognizeWithTextifyFromBgra8888({
    required Uint8List pixels,
    required int width,
    required int height,
  }) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.bgra8888,
      (ui.Image result) {
        if (!c.isCompleted) c.complete(result);
      },
    );
    ui.Image? img;
    try {
      img = await c.future;
      img = await _scaleDownToMaxEdge(img, _kDecodeMaxEdgePx.first);
      return await _textifyExtractBalancedThenFast(img);
    } on StateError {
      return '';
    } finally {
      img?.dispose();
    }
  }

  static Future<String> _recognizeWithMlKitFilePath(String filePath) async {
    final input = InputImage.fromFilePath(filePath);
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final r = await rec.processImage(input);
      return SmartInputOcrRecognizedPostprocess.apply(r.text.trim());
    } finally {
      try {
        await rec.close();
      } catch (_) {}
    }
  }

  static String? _sniffImageMime(Uint8List b) {
    if (_bytesLookLikeJpeg(b)) return 'image/jpeg';
    if (_bytesLookLikePng(b)) return 'image/png';
    if (_bytesLookLikeWebp(b)) return 'image/webp';
    if (_bytesLookLikeGif(b)) return 'image/gif';
    return null;
  }

  /// Com sessão: leitura via Google Cloud Vision (dicas pt/en; alinhada ao stack Lens/Document AI).
  static Future<String?> _tryCloudVisionIfLoggedIn(Uint8List bytes) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return null;
      final mime = _sniffImageMime(bytes) ?? 'image/jpeg';
      final b64 = base64Encode(bytes);
      return await FunctionsService().ocrImageForSmartInput(base64: b64, mimeType: mime);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Cloud Vision indisponível, fallback: $e');
      }
      return null;
    }
  }

  /// Web: Vision primeiro. Móvel: ML Kit, depois Vision (se ainda vazio) e servidores Google; no fim Textify.
  static Future<String> recognizeFromGalleryBytes({
    required Uint8List bytes,
    required String? filePath,
  }) async {
    if (kIsWeb) {
      final cloud = await _tryCloudVisionIfLoggedIn(bytes);
      if (cloud != null && cloud.isNotEmpty) {
        return SmartInputOcrRecognizedPostprocess.apply(cloud);
      }
    }
    if (mlKitTextRecognitionSupported && filePath != null && filePath.isNotEmpty) {
      try {
        final t = await _recognizeWithMlKitFilePath(filePath);
        if (t.isNotEmpty) return t;
      } catch (_) {}
    }
    if (!kIsWeb) {
      final cloud2 = await _tryCloudVisionIfLoggedIn(bytes);
      if (cloud2 != null && cloud2.isNotEmpty) {
        return SmartInputOcrRecognizedPostprocess.apply(cloud2);
      }
    }
    return recognizeWithTextifyFromBytes(bytes);
  }
}
