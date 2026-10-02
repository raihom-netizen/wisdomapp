import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

bool get _temFfmpeg => Platform.isAndroid || Platform.isIOS;

/// Extrai UM quadro (JPEG, até 1280 px de largura) de um vídeo local.
/// Tenta em ~1 s (foge do 1º quadro preto) e, se o vídeo for curto ou o
/// trecho não existir, no começo. `null` se não deu.
Future<Uint8List?> _quadroDoArquivo(String entrada) async {
  if (!_temFfmpeg) return null;
  final tmp = await getTemporaryDirectory();
  final saida = File(
      '${tmp.path}/ct_quadro_${DateTime.now().microsecondsSinceEpoch}.jpg');
  try {
    for (final ss in const ['1', '']) {
      final args = <String>[
        '-y',
        if (ss.isNotEmpty) ...['-ss', ss],
        '-i',
        entrada,
        '-frames:v',
        '1',
        '-vf',
        r'scale=w=min(iw\,1280):h=-2',
        '-q:v',
        '3',
        saida.path,
      ];
      final sessao = await FFmpegKit.executeWithArguments(args)
          .timeout(const Duration(seconds: 40));
      final rc = await sessao.getReturnCode();
      if (ReturnCode.isSuccess(rc) &&
          saida.existsSync() &&
          saida.lengthSync() > 0) {
        return await saida.readAsBytes();
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    try {
      if (saida.existsSync()) saida.deleteSync();
    } catch (_) {}
  }
}

Future<Uint8List?> courseVideoPosterFromFilePath(String path) =>
    _quadroDoArquivo(path);

Future<Uint8List?> courseVideoPosterFromBytes(
  Uint8List bytes,
  String mimeType,
) async {
  if (!_temFfmpeg || bytes.isEmpty) return null;
  final tmp = await getTemporaryDirectory();
  final ext = mimeType.contains('webm')
      ? 'webm'
      : (mimeType.contains('quicktime') ? 'mov' : 'mp4');
  final f = File(
      '${tmp.path}/ct_video_${DateTime.now().microsecondsSinceEpoch}.$ext');
  try {
    await f.writeAsBytes(bytes, flush: true);
    return await _quadroDoArquivo(f.path);
  } catch (_) {
    return null;
  } finally {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

// ── Prévia de vídeos antigos (sem quadro gravado) ───────────────────────────

/// Uma geração por URL (cards repetidos esperam a mesma).
final Map<String, Future<String?>> _emAndamento = {};

/// No máximo 2 gerações ao mesmo tempo (vitrine com vários cursos).
int _ativos = 0;
final List<Completer<void>> _fila = [];

Future<void> _entrar() async {
  if (_ativos < 2) {
    _ativos++;
    return;
  }
  final c = Completer<void>();
  _fila.add(c);
  await c.future;
  _ativos++;
}

void _sair() {
  _ativos--;
  if (_fila.isNotEmpty) _fila.removeAt(0).complete();
}

/// Começo do MP4 baixado (o bastante para o 1º segundo de vídeo).
const _kCabeca = 4 * 1024 * 1024;

/// Índice (`moov`) no FIM do arquivo: só baixa se for até este tamanho.
const _kMaxIndice = 12 * 1024 * 1024;

/// Android/iOS: JPEG (cache local) com um quadro do vídeo.
///
/// Não baixa o vídeo inteiro: pega os primeiros 4 MB (HTTP Range) e, quando o
/// índice do MP4 (`moov`) fica no fim do arquivo (comum em vídeo de celular),
/// baixa só o índice e grava cada pedaço na MESMA posição de um arquivo
/// esparso — o FFmpeg lê o índice e decodifica o 1º quadro do começo.
Future<ImageProvider?> courseVideoFrameImage(String videoUrl) async {
  final url = videoUrl.trim();
  if (!_temFfmpeg || !url.startsWith('http')) return null;
  final p = await _emAndamento.putIfAbsent(url, () => _gerarQuadro(url));
  return p == null ? null : FileImage(File(p));
}

Future<String?> _gerarQuadro(String url) async {
  final base = await getTemporaryDirectory();
  final dir = Directory('${base.path}/course_frames');
  final nome = sha1.convert(utf8.encode(url)).toString();
  final jpg = File('${dir.path}/$nome.jpg');
  try {
    if (jpg.existsSync() && jpg.lengthSync() > 0) return jpg.path;
  } catch (_) {}

  await _entrar();
  final parte = File('${dir.path}/$nome.part');
  final client = http.Client();
  try {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final cabeca = await _baixarFaixa(client, url, 0, _kCabeca - 1);
    if (cabeca == null || cabeca.bytes.isEmpty) return null;
    final total = cabeca.total ?? cabeca.bytes.length;

    final raf = parte.openSync(mode: FileMode.write);
    try {
      raf.writeFromSync(cabeca.bytes);
      final faixa = _faixaDoIndice(cabeca.bytes, total);
      if (faixa != null) {
        final (ini, fim) = faixa;
        if (fim - ini + 1 > _kMaxIndice) return null;
        final indice = await _baixarFaixa(client, url, ini, fim);
        if (indice == null || indice.bytes.isEmpty) return null;
        raf.setPositionSync(ini);
        raf.writeFromSync(indice.bytes);
      }
    } finally {
      raf.closeSync();
    }

    final bytes = await _quadroDoArquivo(parte.path);
    if (bytes == null || bytes.isEmpty) return null;
    await jpg.writeAsBytes(bytes, flush: true);
    return jpg.path;
  } catch (_) {
    return null;
  } finally {
    client.close();
    try {
      if (parte.existsSync()) parte.deleteSync();
    } catch (_) {}
    _sair();
  }
}

class _Faixa {
  _Faixa(this.bytes, this.total);
  final Uint8List bytes;
  final int? total;
}

/// GET com `Range` (lê no máximo o tamanho pedido, mesmo se o servidor
/// ignorar o Range e mandar o arquivo todo).
Future<_Faixa?> _baixarFaixa(
  http.Client client,
  String url,
  int inicio,
  int fim,
) async {
  final req = http.Request('GET', Uri.parse(url))
    ..headers['Range'] = 'bytes=$inicio-$fim';
  final resp = await client.send(req).timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200 && resp.statusCode != 206) return null;
  if (resp.statusCode == 200 && inicio > 0) return null; // sem Range
  int? total;
  final cr = resp.headers['content-range'];
  if (cr != null && cr.contains('/')) {
    total = int.tryParse(cr.split('/').last.trim());
  } else if (resp.statusCode == 200) {
    total = resp.contentLength;
  }
  final max = fim - inicio + 1;
  final out = BytesBuilder(copy: false);
  final done = Completer<void>();
  late final StreamSubscription<List<int>> sub;
  sub = resp.stream.listen(
    (chunk) {
      final falta = max - out.length;
      if (chunk.length >= falta) {
        out.add(chunk.sublist(0, falta));
        sub.cancel();
        if (!done.isCompleted) done.complete();
      } else {
        out.add(chunk);
      }
    },
    onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );
  await done.future.timeout(const Duration(seconds: 60));
  return _Faixa(out.takeBytes(), total);
}

/// Percorre as caixas de topo do MP4 no começo baixado. Se o `moov` já está
/// inteiro no começo → `null` (nada mais a baixar). Se começa no trecho mas
/// não termina, ou está depois do `mdat` → (início, fim) a baixar.
(int, int)? _faixaDoIndice(Uint8List b, int total) {
  final bd = ByteData.sublistView(b);
  var off = 0;
  while (off + 8 <= b.length) {
    var tam = bd.getUint32(off);
    final tipo = String.fromCharCodes(b.sublist(off + 4, off + 8));
    var cab = 8;
    if (tam == 1) {
      if (off + 16 > b.length) break;
      tam = bd.getUint64(off + 8);
      cab = 16;
    } else if (tam == 0) {
      tam = total - off;
    }
    if (tam < cab) return null; // arquivo estranho: tenta só com o começo
    if (tipo == 'moov') {
      if (off + tam <= b.length) return null;
      return (b.length, off + tam - 1);
    }
    off += tam;
  }
  // Passou do trecho baixado sem achar o índice: ele vem depois (fim).
  if (off >= b.length && off < total) return (off, total - 1);
  return null;
}
