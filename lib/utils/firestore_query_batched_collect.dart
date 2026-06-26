import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firestore_reliable_read.dart';

/// Tamanho de página ao paginar `.get()` na mesma consulta ordenada (Firestore).
const int kFirestoreBatchedCollectPageSize = 2500;

/// Limite de segurança para não ficar em loop se algo correr mal.
const int kFirestoreBatchedCollectMaxDocs = 100000;

/// Percorre uma [Query] já filtrada e **ordenada** com várias leituras `[limit]` + [startAfterDocument].
///
/// Evita um único [.get()] muito grande na Web (timeouts, pressão de memória no cliente JS)
/// e permite ultrapassar o limite artificial de 10k docs por `.get()` onde existia.
///
/// A [baseQuery] não deve incluir [.limit] final — este método aplica o paginamento.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> firestoreQueryCollectDocumentsBatched(
  Query<Map<String, dynamic>> baseQuery, {
  int pageSize = kFirestoreBatchedCollectPageSize,
  int maxDocuments = kFirestoreBatchedCollectMaxDocs,
}) async {
  assert(pageSize >= 1 && pageSize <= 10000);
  assert(maxDocuments >= 1);
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  while (out.length < maxDocuments) {
    var q = baseQuery.limit(pageSize);
    if (cursor != null) {
      q = q.startAfterDocument(cursor);
    }
    final snap = await firestoreQueryGetReliable(q);
    if (snap.docs.isEmpty) break;
    out.addAll(snap.docs);
    if (snap.docs.length < pageSize) break;
    cursor = snap.docs.last;
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return out;
}

/// Igual a [firestoreQueryCollectDocumentsBatched], mas notifica após cada página (UI pode atualizar cedo).
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> firestoreQueryCollectDocumentsBatchedWithProgress(
  Query<Map<String, dynamic>> baseQuery, {
  int pageSize = kFirestoreBatchedCollectPageSize,
  int maxDocuments = kFirestoreBatchedCollectMaxDocs,
  void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>> chunk, int runningTotal, bool isLast)? onBatch,
}) async {
  assert(pageSize >= 1 && pageSize <= 10000);
  assert(maxDocuments >= 1);
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  while (out.length < maxDocuments) {
    var q = baseQuery.limit(pageSize);
    if (cursor != null) {
      q = q.startAfterDocument(cursor);
    }
    final snap = await firestoreQueryGetReliable(q);
    if (snap.docs.isEmpty) {
      onBatch?.call(<QueryDocumentSnapshot<Map<String, dynamic>>>[], out.length, true);
      break;
    }
    out.addAll(snap.docs);
    final isLast = snap.docs.length < pageSize || out.length >= maxDocuments;
    onBatch?.call(snap.docs, out.length, isLast);
    if (isLast) break;
    cursor = snap.docs.last;
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return out;
}
