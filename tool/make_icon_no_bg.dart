import 'dart:io';

import 'package:image/image.dart' as img;

bool _isDarkBg(img.Pixel p) {
  final r = p.r.toInt();
  final g = p.g.toInt();
  final b = p.b.toInt();
  return r < 26 && g < 32 && b < 52;
}

void main() {
  final input = File('assets/images/icon.png');
  if (!input.existsSync()) {
    stderr.writeln('Arquivo não encontrado: ${input.path}');
    exitCode = 2;
    return;
  }

  final src = img.decodeImage(input.readAsBytesSync());
  if (src == null) {
    stderr.writeln('Falha ao decodificar PNG: ${input.path}');
    exitCode = 2;
    return;
  }

  final out = img.Image.from(src);
  final w = out.width;
  final h = out.height;

  final visited = List<bool>.filled(w * h, false);
  final queue = <(int, int)>[];

  void enqueueIfBg(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final idx = y * w + x;
    if (visited[idx]) return;
    visited[idx] = true;
    final p = out.getPixel(x, y);
    if (_isDarkBg(p)) {
      queue.add((x, y));
    }
  }

  for (var x = 0; x < w; x++) {
    enqueueIfBg(x, 0);
    enqueueIfBg(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    enqueueIfBg(0, y);
    enqueueIfBg(w - 1, y);
  }

  var head = 0;
  while (head < queue.length) {
    final (x, y) = queue[head++];
    final px = out.getPixel(x, y);
    out.setPixelRgba(x, y, px.r.toInt(), px.g.toInt(), px.b.toInt(), 0);
    enqueueIfBg(x + 1, y);
    enqueueIfBg(x - 1, y);
    enqueueIfBg(x, y + 1);
    enqueueIfBg(x, y - 1);
  }

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = out.getPixel(x, y);
      if (p.a.toInt() > 0) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < minX || maxY < minY) {
    stderr.writeln('Nenhum conteúdo visível após remoção do fundo.');
    exitCode = 2;
    return;
  }

  const contentScale = 0.84;
  final crop = img.copyCrop(
    out,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );

  const size = 1024;
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final target = (size * contentScale).round();
  final fitted = img.copyResize(
    crop,
    width: target,
    height: target,
    interpolation: img.Interpolation.cubic,
  );

  final dx = ((size - fitted.width) / 2).round();
  final dy = ((size - fitted.height) / 2).round();
  img.compositeImage(canvas, fitted, dstX: dx, dstY: dy);

  final noBg = File('assets/images/icon_no_bg.png');
  final fg = File('assets/images/icon_adaptive_foreground.png');
  noBg.writeAsBytesSync(img.encodePng(canvas, level: 6));
  fg.writeAsBytesSync(img.encodePng(canvas, level: 6));

  stdout.writeln('Gerado: ${noBg.path}');
  stdout.writeln('Gerado: ${fg.path}');
}
