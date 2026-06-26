import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_user_doc_id.dart';

/// CRUD de ocorrências (produtividade). users/{uid}/ocorrencias.
/// Campos: date, pontuacao, numeroOcorrencia, naturezaId, naturezaLabel, folgaDate (opcional).
class OcorrenciasService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('ocorrencias');

  Future<String> add(String uid, {
    required DateTime date,
    required int pontuacao,
    required String numeroOcorrencia,
    required String naturezaId,
    required String naturezaLabel,
    DateTime? folgaDate,
    String? observacao,
    String? anexoUrl,
    String? anexoFileName,
    String? anexoContentType,
    int? anexoSizeBytes,
    String? anexoStoragePath,
  }) async {
    final payload = <String, dynamic>{
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'pontuacao': pontuacao,
      'numeroOcorrencia': numeroOcorrencia.trim(),
      'naturezaId': naturezaId,
      'naturezaLabel': naturezaLabel,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (folgaDate != null) {
      payload['folgaDate'] = Timestamp.fromDate(DateTime(folgaDate.year, folgaDate.month, folgaDate.day));
    }
    if (observacao != null && observacao.trim().isNotEmpty) {
      payload['observacao'] = observacao.trim();
    }
    if (anexoUrl != null && anexoUrl.trim().isNotEmpty) {
      payload['anexoUrl'] = anexoUrl.trim();
    }
    if (anexoFileName != null && anexoFileName.trim().isNotEmpty) {
      payload['anexoFileName'] = anexoFileName.trim();
    }
    if (anexoContentType != null && anexoContentType.trim().isNotEmpty) {
      payload['anexoContentType'] = anexoContentType.trim();
    }
    if (anexoSizeBytes != null && anexoSizeBytes > 0) {
      payload['anexoSizeBytes'] = anexoSizeBytes;
    }
    if (anexoStoragePath != null && anexoStoragePath.trim().isNotEmpty) {
      payload['anexoStoragePath'] = anexoStoragePath.trim();
    }
    final ref = await _col(uid).add(payload);
    return ref.id;
  }

  Future<void> update(String uid, String docId, {
    required DateTime date,
    required int pontuacao,
    required String numeroOcorrencia,
    required String naturezaId,
    required String naturezaLabel,
    DateTime? folgaDate,
    /// Se true, aplica [folgaDate]: valor define a data; `null` remove o campo (cancelar folga).
    /// Se false (padrão), o campo `folgaDate` no Firestore **não é alterado** — evita apagar folga ao editar observação/anexo.
    bool patchFolgaDate = false,
    bool limparAnexo = false,
    String? anexoUrl,
    String? anexoFileName,
    String? anexoContentType,
    int? anexoSizeBytes,
    String? anexoStoragePath,
    String? observacao,
  }) async {
    final payload = <String, dynamic>{
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'pontuacao': pontuacao,
      'numeroOcorrencia': numeroOcorrencia.trim(),
      'naturezaId': naturezaId,
      'naturezaLabel': naturezaLabel,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (patchFolgaDate) {
      if (folgaDate != null) {
        payload['folgaDate'] = Timestamp.fromDate(DateTime(folgaDate.year, folgaDate.month, folgaDate.day));
      } else {
        payload['folgaDate'] = FieldValue.delete();
      }
    }
    if (observacao != null) {
      final obs = observacao.trim();
      if (obs.isEmpty) {
        payload['observacao'] = FieldValue.delete();
      } else {
        payload['observacao'] = obs;
      }
    }
    if (limparAnexo) {
      payload['anexoUrl'] = FieldValue.delete();
      payload['anexoFileName'] = FieldValue.delete();
      payload['anexoContentType'] = FieldValue.delete();
      payload['anexoSizeBytes'] = FieldValue.delete();
      payload['anexoStoragePath'] = FieldValue.delete();
    } else if (anexoUrl != null && anexoUrl.trim().isNotEmpty) {
      payload['anexoUrl'] = anexoUrl.trim();
      payload['anexoFileName'] = (anexoFileName ?? '').trim();
      payload['anexoContentType'] = (anexoContentType ?? '').trim();
      payload['anexoSizeBytes'] = anexoSizeBytes ?? 0;
      payload['anexoStoragePath'] = (anexoStoragePath ?? '').trim();
    }
    await _col(uid).doc(docId).update(payload);
  }

  /// Remove `folgaDate` em lote (ex.: cancelou a folga ou vai remarcar noutro dia).
  Future<void> limparDatasFolga(String uid, List<String> docIds) async {
    if (docIds.isEmpty) return;
    const maxBatch = 400;
    for (var i = 0; i < docIds.length; i += maxBatch) {
      final batch = _db.batch();
      final col = _col(uid);
      final slice = docIds.skip(i).take(maxBatch);
      for (final id in slice) {
        batch.update(col.doc(id), {
          'folgaDate': FieldValue.delete(),
          'folgaCalendarColorHex': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  /// Todas as ocorrências com folga num dia — usado ao limpar o calendário de Escalas.
  Future<List<String>> clearFolgaForCalendarDay(
    String uid,
    DateTime folgaDay,
  ) async {
    final target = DateTime(folgaDay.year, folgaDay.month, folgaDay.day);
    final snap = await _col(uid).get();
    final ids = <String>[];
    for (final doc in snap.docs) {
      final fd = doc.data()['folgaDate'];
      if (fd is! Timestamp) continue;
      final t = fd.toDate();
      final d = DateTime(t.year, t.month, t.day);
      if (d == target) ids.add(doc.id);
    }
    if (ids.isNotEmpty) await limparDatasFolga(uid, ids);
    return ids;
  }

  Future<void> delete(String uid, String docId) async {
    await _col(uid).doc(docId).delete();
  }

  /// Marca ocorrências como usadas para folga na data [folgaDate].
  Future<void> marcarFolga(
    String uid,
    List<String> docIds,
    DateTime folgaDate, {
    String? folgaCalendarColorHex,
  }) async {
    final batch = _db.batch();
    final col = _col(uid);
    final day = DateTime(folgaDate.year, folgaDate.month, folgaDate.day);
    for (final id in docIds) {
      final payload = <String, dynamic>{
        'folgaDate': Timestamp.fromDate(day),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final cor = (folgaCalendarColorHex ?? '').trim();
      if (cor.isNotEmpty) {
        payload['folgaCalendarColorHex'] = cor;
      }
      batch.update(col.doc(id), payload);
    }
    await batch.commit();
  }

  /// Ocorrências ordenadas por data: menor para maior (mais antiga primeiro).
  ///
  /// **Cache-first**: tenta entregar imediatamente o snapshot do cache local
  /// (Firestore persistence) — isso faz a lista de ocorrências "antigas"
  /// aparecer instantaneamente mesmo quando a rede está lenta ou offline,
  /// e depois liga o `snapshots()` real-time para receber atualizações do
  /// servidor. Mesma estratégia usada em `finance_accounts_service.dart`
  /// e em `LocationsScreen` (plantões recorrentes).
  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String uid) async* {
    final col = _col(uid);
    try {
      final cached = await col.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        yield cached;
      }
    } catch (_) {
      // sem cache local ainda — segue direto para o snapshots() abaixo
    }
    // Evita falhas intermitentes do SDK Web com orderBy em cenários de
    // cache/index local. A ordenação final da grid é feita no cliente.
    yield* col.snapshots();
  }

  Future<List<Map<String, dynamic>>> getByPeriod(String uid, DateTime start, DateTime end) async {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    final snap = await _col(uid)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDay))
        .get();
    final list = snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      return m;
    }).toList();
    list.sort((a, b) {
      final da = a['date'];
      final db = b['date'];
      final ta = da is Timestamp ? da.toDate() : DateTime(2000, 1, 1);
      final tb = db is Timestamp ? db.toDate() : DateTime(2000, 1, 1);
      return ta.compareTo(tb);
    });
    return list;
  }

  Future<List<Map<String, dynamic>>> getAll(String uid) async {
    final snap = await _col(uid).get();
    final list = snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      return m;
    }).toList();
    list.sort((a, b) {
      final da = a['date'];
      final db = b['date'];
      final ta = da is Timestamp ? da.toDate() : DateTime(2000, 1, 1);
      final tb = db is Timestamp ? db.toDate() : DateTime(2000, 1, 1);
      return ta.compareTo(tb);
    });
    return list;
  }
}
