import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firestore_retry.dart';

bool _firestoreWebFlakyGet(Object e) {
  final msg = e.toString();
  return msg.contains('INTERNAL ASSERTION') ||
      msg.contains('Unexpected state') ||
      msg.contains('WatchChangeAggregator') ||
      msg.contains('PersistentListenStream');
}

/// Leituras pontuais `.get()` na mesma coleção onde há `snapshots()` — na Web o SDK JS
/// pode disparar `INTERNAL ASSERTION` / estado inesperado no agregador de watch.
/// Várias tentativas com backoff; na Web tenta primeiro [Source.serverAndCache] (menos choque com o pipeline de watch).
Future<QuerySnapshot<Map<String, dynamic>>> firestoreQueryGetReliable(
  Query<Map<String, dynamic>> query,
) {
  return runFirestoreWithRetry(() async {
    final sources = kIsWeb
        ? <Source>[Source.serverAndCache, Source.server]
        : <Source>[Source.server];

    Object? lastError;
    for (final src in sources) {
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          return await query.get(GetOptions(source: src));
        } catch (e) {
          lastError = e;
          if (!_firestoreWebFlakyGet(e)) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 120 * (1 << attempt)));
        }
      }
    }
    Error.throwWithStackTrace(lastError!, StackTrace.current);
  });
}
