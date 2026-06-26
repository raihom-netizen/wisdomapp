// ignore_for_file: avoid_print
// Gera WAVs **modernos e longos** (1.0–2.5 s) em
// `assets/sounds/notifications/` para o catálogo offline (preview ouvível /
// agradável). Padrão *super premium*: harmônicas, envelopes ADSR, glissandos
// e reverb sintético simples — não são bipes "Atari".
//
// Executar na pasta `flutter_app`:
//   dart run tool/generate_notification_wavs.dart
//
// Mantém os **IDs** do catálogo (`notification_sound_catalog.dart`) para não
// quebrar escolhas antigas dos usuários — apenas o desenho do som muda.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int kSampleRate = 32000;
const double kHeadroom = 0.78;

void main() {
  final root = Directory.current;
  final outDir = Directory('${root.path}/assets/sounds/notifications');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  _save('${outDir.path}/pop_curto.wav', _popCurto());
  _save('${outDir.path}/aviso_suave.wav', _avisoSuave());
  _save('${outDir.path}/sino_curto.wav', _sinoCurto());
  _save('${outDir.path}/sino_triplo.wav', _sinoTriplo());
  _save('${outDir.path}/alerta.wav', _alerta());
  _save('${outDir.path}/beep_classico.wav', _beepClassico());
  _save('${outDir.path}/duo_curto.wav', _duoCurto());
  _save('${outDir.path}/plim.wav', _plim());
  _save('${outDir.path}/whatsapp_like.wav', _notificacaoModerna());
  _save('${outDir.path}/sino_grave.wav', _sinoGrave());
  _save('${outDir.path}/chime.wav', _chimeAscendente());
  _save('${outDir.path}/urgente.wav', _urgentePremium());

  print('OK: WAVs premium gerados em ${outDir.path}');
}

// =====================================================================
// HELPERS DE SÍNTESE
// =====================================================================

/// Buffer mono de samples float em [-1.0, 1.0], depois quantizado.
class _Buf {
  _Buf(double durationSec)
      : data = Float64List((kSampleRate * durationSec).round());
  final Float64List data;
  int get length => data.length;
}

/// Adiciona uma "nota" senoidal com harmônicas e envelope ADSR ao buffer.
///
/// - [startSec]   início (em segundos) no buffer
/// - [durSec]     duração total da nota (sem release)
/// - [freq]       fundamental (Hz)
/// - [vol]        amplitude máxima (0.0–1.0)
/// - [harmonics]  lista de pares [parcial, ganho] — ex.: `[[2, 0.4], [3, 0.18]]`
/// - [attack]     fade-in (s)
/// - [decay]      curva exponencial (s) até [sustain]
/// - [sustain]    nível mantido (0.0–1.0)
/// - [release]    fade-out (s) — soma a [durSec]
void _addNote(
  _Buf buf, {
  required double startSec,
  required double durSec,
  required double freq,
  required double vol,
  List<List<double>> harmonics = const [],
  double attack = 0.005,
  double decay = 0.08,
  double sustain = 0.55,
  double release = 0.25,
}) {
  final startIdx = (startSec * kSampleRate).round();
  final coreSamples = (durSec * kSampleRate).round();
  final releaseSamples = (release * kSampleRate).round();
  final attackSamples = (attack * kSampleRate).round();
  final decaySamples = (decay * kSampleRate).round();
  final total = coreSamples + releaseSamples;
  for (var i = 0; i < total; i++) {
    final idx = startIdx + i;
    if (idx < 0 || idx >= buf.length) continue;
    final t = i / kSampleRate;
    double env;
    if (i < attackSamples) {
      env = i / math.max(1, attackSamples);
    } else if (i < attackSamples + decaySamples) {
      final dt = (i - attackSamples) / math.max(1, decaySamples);
      env = 1.0 + (sustain - 1.0) * dt;
    } else if (i < coreSamples) {
      env = sustain;
    } else {
      final rt = (i - coreSamples) / math.max(1, releaseSamples);
      env = sustain * math.exp(-rt * 4.5);
    }
    double s = math.sin(2 * math.pi * freq * t);
    for (final h in harmonics) {
      final partial = h[0];
      final gain = h[1];
      s += gain * math.sin(2 * math.pi * freq * partial * t);
    }
    s = s / (1.0 + _harmonicNorm(harmonics));
    buf.data[idx] += vol * env * s;
  }
}

double _harmonicNorm(List<List<double>> harmonics) {
  var sum = 0.0;
  for (final h in harmonics) {
    sum += h[1];
  }
  return sum * 0.8;
}

/// Adiciona um "pop" curto com forma de envelope rápido — pulse + harmônica.
void _addPop(_Buf buf, double startSec, double freq, double vol) {
  final startIdx = (startSec * kSampleRate).round();
  final n = (0.18 * kSampleRate).round();
  for (var i = 0; i < n; i++) {
    final idx = startIdx + i;
    if (idx < 0 || idx >= buf.length) continue;
    final t = i / kSampleRate;
    final env = math.exp(-t * 22);
    final core = math.sin(2 * math.pi * freq * t) +
        0.5 * math.sin(2 * math.pi * freq * 2 * t) +
        0.2 * math.sin(2 * math.pi * freq * 3.2 * t);
    buf.data[idx] += vol * env * core / 1.7;
  }
}

/// Glissando senoidal — frequência muda de [fStart] a [fEnd] em [durSec].
void _addGlissando(
  _Buf buf, {
  required double startSec,
  required double durSec,
  required double fStart,
  required double fEnd,
  required double vol,
}) {
  final startIdx = (startSec * kSampleRate).round();
  final n = (durSec * kSampleRate).round();
  double phase = 0.0;
  for (var i = 0; i < n; i++) {
    final idx = startIdx + i;
    if (idx < 0 || idx >= buf.length) continue;
    final dt = i / kSampleRate;
    final f = fStart + (fEnd - fStart) * (dt / durSec);
    phase += 2 * math.pi * f / kSampleRate;
    final env = i < (kSampleRate * 0.02)
        ? i / (kSampleRate * 0.02)
        : math.exp(-(dt - 0.02) * 2.4);
    buf.data[idx] += vol * env * math.sin(phase);
  }
}

/// Reverb sintético muito simples: dois ecos atenuados, sem feedback.
void _applyReverb(_Buf buf, {double delay1 = 0.06, double delay2 = 0.11, double mix = 0.32}) {
  final d1 = (delay1 * kSampleRate).round();
  final d2 = (delay2 * kSampleRate).round();
  final out = Float64List.fromList(buf.data);
  for (var i = 0; i < buf.length; i++) {
    if (i - d1 >= 0) out[i] += buf.data[i - d1] * mix;
    if (i - d2 >= 0) out[i] += buf.data[i - d2] * mix * 0.55;
  }
  for (var i = 0; i < buf.length; i++) {
    buf.data[i] = out[i];
  }
}

void _applyFadeOut(_Buf buf, double tailSec) {
  final n = (tailSec * kSampleRate).round();
  final start = math.max(0, buf.length - n);
  for (var i = start; i < buf.length; i++) {
    final fade = 1.0 - (i - start) / n;
    buf.data[i] *= fade;
  }
}

Uint8List _bufToWav(_Buf buf) {
  final pcm = Int16List(buf.length);
  for (var i = 0; i < buf.length; i++) {
    final clamped = (buf.data[i] * kHeadroom).clamp(-1.0, 1.0);
    pcm[i] = (clamped * 32767).round();
  }
  return _pcmToWav(pcm, kSampleRate);
}

void _save(String path, _Buf buf) {
  final bytes = _bufToWav(buf);
  File(path).writeAsBytesSync(bytes);
}

// =====================================================================
// CATÁLOGO — desenho de cada som
// =====================================================================

/// "Pop curto" — pop suave moderno com pequeno eco. ~1.0 s.
_Buf _popCurto() {
  final b = _Buf(1.0);
  _addPop(b, 0.0, 880, 0.85);
  _addPop(b, 0.18, 660, 0.55);
  _applyReverb(b, delay1: 0.07, delay2: 0.14, mix: 0.28);
  _applyFadeOut(b, 0.18);
  return b;
}

/// "Aviso suave" — acorde C5/E5 sustentado, ataque lento. ~1.7 s.
_Buf _avisoSuave() {
  final b = _Buf(1.7);
  _addNote(b,
      startSec: 0.0,
      durSec: 0.95,
      freq: 523.25, // C5
      vol: 0.55,
      harmonics: [[2, 0.35], [3, 0.15], [4, 0.07]],
      attack: 0.06,
      decay: 0.25,
      sustain: 0.55,
      release: 0.55);
  _addNote(b,
      startSec: 0.05,
      durSec: 0.95,
      freq: 659.25, // E5
      vol: 0.45,
      harmonics: [[2, 0.32], [3, 0.12]],
      attack: 0.07,
      decay: 0.28,
      sustain: 0.50,
      release: 0.55);
  _applyReverb(b, delay1: 0.08, delay2: 0.16, mix: 0.34);
  return b;
}

/// "Sino cristal" — sino C6 com longa cauda e harmônicas brilhantes. ~1.7 s.
_Buf _sinoCurto() {
  final b = _Buf(1.7);
  _addNote(b,
      startSec: 0.0,
      durSec: 0.05,
      freq: 1046.5, // C6
      vol: 0.95,
      harmonics: [[2.01, 0.55], [3.02, 0.32], [4.05, 0.18], [5.4, 0.10]],
      attack: 0.002,
      decay: 0.55,
      sustain: 0.08,
      release: 1.05);
  _applyReverb(b, delay1: 0.06, delay2: 0.14, mix: 0.42);
  _applyFadeOut(b, 0.12);
  return b;
}

/// "Sino triplo" — três sinos seguidos em C6, E6, G6, com cauda. ~2.2 s.
_Buf _sinoTriplo() {
  final b = _Buf(2.3);
  const t0 = 0.0;
  const t1 = 0.20;
  const t2 = 0.42;
  const harm = [[2.01, 0.50], [3.02, 0.28], [4.05, 0.14]];
  _addNote(b,
      startSec: t0,
      durSec: 0.05,
      freq: 1046.5,
      vol: 0.85,
      harmonics: harm,
      attack: 0.002,
      decay: 0.45,
      sustain: 0.06,
      release: 0.80);
  _addNote(b,
      startSec: t1,
      durSec: 0.05,
      freq: 1318.5,
      vol: 0.80,
      harmonics: harm,
      attack: 0.002,
      decay: 0.45,
      sustain: 0.06,
      release: 0.85);
  _addNote(b,
      startSec: t2,
      durSec: 0.05,
      freq: 1567.98,
      vol: 0.78,
      harmonics: harm,
      attack: 0.002,
      decay: 0.50,
      sustain: 0.06,
      release: 1.10);
  _applyReverb(b, delay1: 0.07, delay2: 0.15, mix: 0.40);
  _applyFadeOut(b, 0.18);
  return b;
}

/// "Alerta" — dois pulsos rápidos com glissando descendente. ~1.6 s.
_Buf _alerta() {
  final b = _Buf(1.6);
  _addGlissando(b, startSec: 0.0, durSec: 0.32, fStart: 1400, fEnd: 1050, vol: 0.85);
  _addGlissando(b, startSec: 0.42, durSec: 0.32, fStart: 1400, fEnd: 1050, vol: 0.80);
  _addNote(b,
      startSec: 0.85,
      durSec: 0.18,
      freq: 880,
      vol: 0.65,
      harmonics: [[2, 0.4], [3, 0.18]],
      attack: 0.01,
      decay: 0.10,
      sustain: 0.35,
      release: 0.40);
  _applyReverb(b, delay1: 0.06, delay2: 0.12, mix: 0.30);
  _applyFadeOut(b, 0.18);
  return b;
}

/// "Beep clássico moderno" — três beeps curtos com release. ~1.4 s.
_Buf _beepClassico() {
  final b = _Buf(1.4);
  for (var i = 0; i < 3; i++) {
    _addNote(b,
        startSec: 0.0 + i * 0.18,
        durSec: 0.10,
        freq: 880 + i * 110,
        vol: 0.75,
        harmonics: [[2, 0.30], [3, 0.10]],
        attack: 0.003,
        decay: 0.05,
        sustain: 0.45,
        release: 0.25);
  }
  _applyReverb(b, delay1: 0.05, delay2: 0.10, mix: 0.30);
  _applyFadeOut(b, 0.16);
  return b;
}

/// "Duo arpejo" — C5 → G5 ascendente. ~1.1 s.
_Buf _duoCurto() {
  final b = _Buf(1.1);
  _addNote(b,
      startSec: 0.0,
      durSec: 0.18,
      freq: 523.25,
      vol: 0.72,
      harmonics: [[2, 0.35], [3, 0.15]],
      attack: 0.005,
      decay: 0.08,
      sustain: 0.45,
      release: 0.35);
  _addNote(b,
      startSec: 0.20,
      durSec: 0.22,
      freq: 783.99,
      vol: 0.78,
      harmonics: [[2, 0.40], [3, 0.18]],
      attack: 0.005,
      decay: 0.10,
      sustain: 0.45,
      release: 0.45);
  _applyReverb(b, delay1: 0.06, delay2: 0.13, mix: 0.32);
  _applyFadeOut(b, 0.14);
  return b;
}

/// "Plim brilhante" — A6 com decay rápido + harmônicas. ~1.0 s.
_Buf _plim() {
  final b = _Buf(1.0);
  _addNote(b,
      startSec: 0.0,
      durSec: 0.04,
      freq: 1760, // A6
      vol: 0.85,
      harmonics: [[2.02, 0.45], [3.05, 0.22], [4.1, 0.10]],
      attack: 0.002,
      decay: 0.20,
      sustain: 0.08,
      release: 0.55);
  _applyReverb(b, delay1: 0.05, delay2: 0.11, mix: 0.38);
  _applyFadeOut(b, 0.12);
  return b;
}

/// "Notificação moderna" — dois tons curtos com brilho. ~1.2 s.
_Buf _notificacaoModerna() {
  final b = _Buf(1.2);
  _addNote(b,
      startSec: 0.0,
      durSec: 0.10,
      freq: 988, // B5
      vol: 0.80,
      harmonics: [[2, 0.42], [3, 0.18]],
      attack: 0.003,
      decay: 0.10,
      sustain: 0.40,
      release: 0.30);
  _addNote(b,
      startSec: 0.18,
      durSec: 0.14,
      freq: 1318.5, // E6
      vol: 0.85,
      harmonics: [[2, 0.45], [3, 0.20]],
      attack: 0.003,
      decay: 0.12,
      sustain: 0.40,
      release: 0.45);
  _applyReverb(b, delay1: 0.06, delay2: 0.13, mix: 0.34);
  _applyFadeOut(b, 0.16);
  return b;
}

/// "Sino grave" — G3 com longo reverb. ~2.0 s.
_Buf _sinoGrave() {
  final b = _Buf(2.0);
  _addNote(b,
      startSec: 0.0,
      durSec: 0.06,
      freq: 196, // G3
      vol: 0.90,
      harmonics: [[2.01, 0.55], [3.02, 0.30], [4.05, 0.15], [5.5, 0.07]],
      attack: 0.003,
      decay: 0.60,
      sustain: 0.08,
      release: 1.20);
  _applyReverb(b, delay1: 0.09, delay2: 0.18, mix: 0.45);
  _applyFadeOut(b, 0.22);
  return b;
}

/// "Chime ascendente" — C5-E5-G5-C6 (acorde Cmaj arpejado). ~2.0 s.
_Buf _chimeAscendente() {
  final b = _Buf(2.0);
  const harm = [[2.01, 0.42], [3.02, 0.20], [4.05, 0.10]];
  _addNote(b,
      startSec: 0.0,
      durSec: 0.06,
      freq: 523.25,
      vol: 0.78,
      harmonics: harm,
      attack: 0.003,
      decay: 0.45,
      sustain: 0.10,
      release: 0.95);
  _addNote(b,
      startSec: 0.18,
      durSec: 0.06,
      freq: 659.25,
      vol: 0.78,
      harmonics: harm,
      attack: 0.003,
      decay: 0.45,
      sustain: 0.10,
      release: 0.95);
  _addNote(b,
      startSec: 0.36,
      durSec: 0.06,
      freq: 783.99,
      vol: 0.80,
      harmonics: harm,
      attack: 0.003,
      decay: 0.50,
      sustain: 0.10,
      release: 1.05);
  _addNote(b,
      startSec: 0.55,
      durSec: 0.06,
      freq: 1046.5,
      vol: 0.85,
      harmonics: harm,
      attack: 0.003,
      decay: 0.55,
      sustain: 0.10,
      release: 1.10);
  _applyReverb(b, delay1: 0.07, delay2: 0.15, mix: 0.40);
  _applyFadeOut(b, 0.20);
  return b;
}

/// "Urgente premium" — três pulsos rápidos + tom sustentado final. ~1.8 s.
_Buf _urgentePremium() {
  final b = _Buf(1.8);
  for (var i = 0; i < 3; i++) {
    _addNote(b,
        startSec: 0.0 + i * 0.15,
        durSec: 0.08,
        freq: 1320,
        vol: 0.85,
        harmonics: [[2, 0.40], [3, 0.20]],
        attack: 0.003,
        decay: 0.05,
        sustain: 0.50,
        release: 0.10);
  }
  _addGlissando(b, startSec: 0.55, durSec: 0.45, fStart: 1100, fEnd: 1650, vol: 0.80);
  _addNote(b,
      startSec: 1.05,
      durSec: 0.20,
      freq: 1320,
      vol: 0.75,
      harmonics: [[2, 0.40], [3, 0.18]],
      attack: 0.005,
      decay: 0.10,
      sustain: 0.50,
      release: 0.45);
  _applyReverb(b, delay1: 0.06, delay2: 0.12, mix: 0.32);
  _applyFadeOut(b, 0.18);
  return b;
}

// =====================================================================
// PCM → WAV (RIFF) MONO 16-bit
// =====================================================================

Uint8List _pcmToWav(Int16List pcm, int sampleRate) {
  const bitsPerSample = 16;
  const channels = 1;
  final dataSize = pcm.length * 2;
  final fileSize = 36 + dataSize;
  final b = BytesBuilder(copy: false);
  void wStr(String s) => b.add(s.codeUnits);
  void u32(int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);

  wStr('RIFF');
  u32(fileSize);
  wStr('WAVE');
  wStr('fmt ');
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bitsPerSample ~/ 8);
  u16(channels * bitsPerSample ~/ 8);
  u16(bitsPerSample);
  wStr('data');
  u32(dataSize);
  final le = ByteData(pcm.length * 2);
  for (var i = 0; i < pcm.length; i++) {
    le.setInt16(i * 2, pcm[i], Endian.little);
  }
  b.add(le.buffer.asUint8List());
  return b.toBytes();
}
