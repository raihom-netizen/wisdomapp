import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/painting.dart';

/// Web: quadro do vídeo pelo próprio navegador — `<video>` fora da tela
/// posicionado em ~1 s, desenhado num `<canvas>` e salvo em JPEG.
///
/// [anonimo]: vídeo de outro domínio (Storage) — pede CORS para o canvas não
/// ficar «sujo» (sem isso o `toBlob` falha).
Future<Uint8List?> _quadroDoVideo(String src, {bool anonimo = false}) async {
  final video = html.VideoElement()
    ..muted = true
    ..preload = anonimo ? 'metadata' : 'auto';
  video.setAttribute('playsinline', 'true');
  video.setAttribute('muted', 'true');
  if (anonimo) video.crossOrigin = 'anonymous';
  final subs = <StreamSubscription<dynamic>>[];
  try {
    final carregou = Completer<bool>();
    subs
      ..add(video.onLoadedMetadata.listen((_) {
        if (!carregou.isCompleted) carregou.complete(true);
      }))
      ..add(video.onError.listen((_) {
        if (!carregou.isCompleted) carregou.complete(false);
      }));
    video.src = src;
    final ok = await carregou.future
        .timeout(const Duration(seconds: 20), onTimeout: () => false);
    if (!ok) return null;

    // ~1 s (ou 10% de vídeos curtos): foge do 1º quadro preto/fade.
    final dur = video.duration.toDouble();
    final alvo = (dur.isFinite && dur > 0) ? math.min(1.0, dur * 0.1) : 0.05;
    final pronto = Completer<bool>();
    subs
      ..add(video.onSeeked.listen((_) {
        if (!pronto.isCompleted) pronto.complete(true);
      }))
      ..add(video.onError.listen((_) {
        if (!pronto.isCompleted) pronto.complete(false);
      }));
    video.currentTime = alvo;
    final temQuadro = await pronto.future
        .timeout(const Duration(seconds: 15), onTimeout: () => false);
    if (!temQuadro) return null;

    final vw = video.videoWidth;
    final vh = video.videoHeight;
    if (vw <= 0 || vh <= 0) return null;
    // Alta resolução sem exagero: até 1280 px de largura.
    final escala = vw > 1280 ? 1280 / vw : 1.0;
    final cw = (vw * escala).round();
    final ch = (vh * escala).round();
    final canvas = html.CanvasElement(width: cw, height: ch);
    final ctx = canvas.context2D
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high';
    ctx.drawImageScaled(video, 0, 0, cw, ch);
    final jpeg = await canvas.toBlob('image/jpeg', 0.86);
    final reader = html.FileReader();
    final lido = reader.onLoadEnd.first;
    reader.readAsArrayBuffer(jpeg);
    await lido.timeout(const Duration(seconds: 10));
    final r = reader.result;
    if (r is Uint8List) return r.isEmpty ? null : r;
    if (r is ByteBuffer) return r.asUint8List();
    return null;
  } catch (_) {
    return null;
  } finally {
    for (final s in subs) {
      unawaited(s.cancel());
    }
    try {
      video
        ..pause()
        ..removeAttribute('src')
        ..load();
    } catch (_) {}
  }
}

Future<Uint8List?> courseVideoPosterFromBytes(
  Uint8List bytes,
  String mimeType,
) async {
  if (bytes.isEmpty) return null;
  String? objectUrl;
  try {
    final blob = html.Blob(
        [bytes], mimeType.trim().isEmpty ? 'video/mp4' : mimeType.trim());
    objectUrl = html.Url.createObjectUrlFromBlob(blob);
    return await _quadroDoVideo(objectUrl);
  } catch (_) {
    return null;
  } finally {
    if (objectUrl != null) {
      try {
        html.Url.revokeObjectUrl(objectUrl);
      } catch (_) {}
    }
  }
}

/// Web não tem caminho de arquivo (o envio usa bytes).
Future<Uint8List?> courseVideoPosterFromFilePath(String path) async => null;

/// Uma geração por URL nesta aba; no máximo 2 ao mesmo tempo.
final Map<String, Future<Uint8List?>> _emAndamento = {};
int _ativos = 0;
final List<Completer<void>> _fila = [];

Future<Uint8List?> _comLimite(String url) async {
  if (_ativos >= 2) {
    final c = Completer<void>();
    _fila.add(c);
    await c.future;
  }
  _ativos++;
  try {
    return await _quadroDoVideo(url, anonimo: true);
  } finally {
    _ativos--;
    if (_fila.isNotEmpty) _fila.removeAt(0).complete();
  }
}

Future<ImageProvider?> courseVideoFrameImage(String videoUrl) async {
  final url = videoUrl.trim();
  if (!url.startsWith('http')) return null;
  final bytes = await _emAndamento.putIfAbsent(url, () => _comLimite(url));
  return bytes == null ? null : MemoryImage(bytes);
}
