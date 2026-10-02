import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firestore_query_batched_collect.dart';
import 'firestore_retry.dart';

/// Leitura de relatórios por MÊS: o período vira faixas mensais pequenas
/// (ano = 12 consultas), lidas em paralelo controlado, cada uma com prazo e
/// nova tentativa (backoff) quando o Firestore responde «indisponível» /
/// «prazo esgotado». Antes o relatório fazia UMA leitura do período inteiro
/// (e outra do histórico inteiro para a abertura) sem nova tentativa: na Web
/// sem cache em disco o «Serviço temporariamente indisponível» derrubava
/// tudo e o esqueleto ficava para sempre.

/// Faixas `[início, fimExclusivo)` de cada mês civil que cobre o período.
List<(DateTime, DateTime)> reportMonthChunks(DateTime from, DateTime to) {
  final start = DateTime(from.year, from.month, from.day);
  final endExcl = DateTime(to.year, to.month, to.day + 1);
  final out = <(DateTime, DateTime)>[];
  var cur = start;
  while (cur.isBefore(endExcl)) {
    final nextMonth = DateTime(cur.year, cur.month + 1, 1);
    final chunkEnd = nextMonth.isBefore(endExcl) ? nextMonth : endExcl;
    out.add((cur, chunkEnd));
    cur = chunkEnd;
  }
  return out;
}

/// Progresso: [done] de [total] faixas lidas.
typedef ReportLoadProgress = void Function(int done, int total);

/// Lê uma faixa com prazo e até [attempts] tentativas (backoff 1 s, 2 s, 4 s…).
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _readChunk(
  Query<Map<String, dynamic>> q, {
  required Duration timeout,
  int attempts = 3,
}) async {
  Object? last;
  StackTrace? lastSt;
  for (var i = 0; i < attempts; i++) {
    try {
      return await runFirestoreWithRetry(
        () => firestoreQueryCollectDocumentsBatched(q, pageSize: 500),
        maxAttempts: 3,
      ).timeout(timeout);
    } catch (e, st) {
      last = e;
      lastSt = st;
      final transient = e is TimeoutException ||
          (e is FirebaseException &&
              (e.code == 'unavailable' ||
                  e.code == 'deadline-exceeded' ||
                  e.code == 'resource-exhausted' ||
                  e.code == 'aborted')) ||
          e.toString().toLowerCase().contains('unavailable');
      if (!transient || i == attempts - 1) break;
      await Future<void>.delayed(Duration(seconds: 1 << i));
    }
  }
  Error.throwWithStackTrace(last!, lastSt ?? StackTrace.current);
}

/// Junta os documentos de todas as faixas mensais, na ordem do período, sem
/// repetir documento. [buildQuery] recebe `(início, fimExclusivo)` e devolve a
/// consulta JÁ filtrada por data no servidor (sem `.limit`).
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> reportCollectByMonth({
  required DateTime from,
  required DateTime to,
  required Query<Map<String, dynamic>> Function(DateTime start, DateTime endExclusive) buildQuery,
  int? concurrency,
  Duration chunkTimeout = const Duration(seconds: 40),
  ReportLoadProgress? onProgress,
}) async {
  final chunks = reportMonthChunks(from, to);
  if (chunks.isEmpty) return const [];
  // Web: o SDK JS sofre com muitas leituras simultâneas na mesma coleção.
  final par = (concurrency ?? (kIsWeb ? 2 : 4)).clamp(1, chunks.length);
  final results = List<List<QueryDocumentSnapshot<Map<String, dynamic>>>?>.filled(chunks.length, null);
  var next = 0;
  var done = 0;
  onProgress?.call(0, chunks.length);

  Future<void> worker() async {
    while (true) {
      final i = next;
      if (i >= chunks.length) return;
      next++;
      final (s, e) = chunks[i];
      results[i] = await _readChunk(buildQuery(s, e), timeout: chunkTimeout);
      done++;
      onProgress?.call(done, chunks.length);
    }
  }

  await Future.wait([for (var w = 0; w < par; w++) worker()]);
  final seen = <String>{};
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final list in results) {
    for (final d in list ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
      if (seen.add(d.reference.path)) out.add(d);
    }
  }
  return out;
}
