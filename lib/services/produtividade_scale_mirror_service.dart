import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/color_palette.dart';
import '../models/scale_entry.dart';
import '../utils/firestore_user_doc_id.dart';
import 'ocorrencias_service.dart';

/// Padrão «Folga · Produtividade» no calendário de Escalas (= plantão Ordinário, mesmo azul da lista).
const String kProdutividadeFolgaDefaultColorHex =
    kProdutividadeFolgaCalendarDefaultHex;

/// Espelho em `users/{uid}/scales` quando o utilizador marca folga no módulo
/// Produtividade — mesmo padrão do espelho da Agenda (`agenda_*`).
///
/// Doc ID determinístico: `produtividade_folga_{ano}_{mês}_{dia}` (um lançamento por dia de folga).
class ProdutividadeScaleMirrorService {
  ProdutividadeScaleMirrorService._();

  static String docIdForFolgaDate(DateTime folgaDay) {
    final d = DateTime(folgaDay.year, folgaDay.month, folgaDay.day);
    return 'produtividade_folga_${d.year}_${d.month}_${d.day}';
  }

  static bool isProdutividadeFolgaScaleDocId(String? scaleDocId) {
    final id = (scaleDocId ?? '').trim();
    return id.startsWith('produtividade_folga_');
  }

  static bool isProdutividadeFolgaEntry(ScaleEntry e) {
    if (e.isProdutividadeFolgaMirror) return true;
    if (isProdutividadeFolgaScaleDocId(e.id)) return true;
    final src = (e.source ?? e.lancamentoOrigem ?? '').toString().toLowerCase();
    return src == 'produtividade_folga';
  }

  static DocumentReference<Map<String, dynamic>> _ref({
    required String userDocId,
    required DateTime folgaDay,
  }) {
    final uid = firestoreUserDocIdForAppShell(userDocId);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scales')
        .doc(docIdForFolgaDate(folgaDay));
  }

  static CollectionReference<Map<String, dynamic>> _ocorrenciasCol(
      String userDocId) {
    final uid = firestoreUserDocIdForAppShell(userDocId);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ocorrencias');
  }

  static String _normalizeColor(String colorHex) {
    var h = colorHex.replaceFirst('#', '').trim();
    if (h.length == 8) h = h.substring(2);
    if (h.length == 6) return '#${h.toUpperCase()}';
    return kProdutividadeFolgaDefaultColorHex;
  }

  static DateTime _calendarDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime? _folgaDayFromData(Map<String, dynamic> data) {
    final raw = data['folgaDate'];
    if (raw is! Timestamp) return null;
    final t = raw.toDate();
    return _calendarDay(t);
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Cria ou atualiza o compromisso espelho no calendário de Escalas.
  static Future<void> upsert({
    required String userDocId,
    required DateTime folgaDate,
    required String colorHex,
    String startHHmm = '08:00',
    String endHHmm = '18:00',
  }) async {
    if (userDocId.isEmpty) return;
    final day = _calendarDay(folgaDate);
    final corFinal = colorHex.trim().isEmpty
        ? kProdutividadeFolgaDefaultColorHex
        : _normalizeColor(colorHex);
    final dateUtcNoon = DateTime.utc(day.year, day.month, day.day, 12, 0, 0);
    final payload = <String, dynamic>{
      'date': Timestamp.fromDate(dateUtcNoon),
      'start': startHHmm,
      'end': endHHmm,
      'label': 'Folga · Produtividade',
      'abbreviation': '',
      'colorHex': corFinal,
      'paid': false,
      'isCompromisso': true,
      'totalValue': 0,
      'dayRate': 0,
      'nightRate': 0,
      'hoursDay': 0,
      'hoursNight': 0,
      'employerType': 'private',
      'notes':
          'Marcado no módulo Produtividade / Ocorrências. Para alterar ou remover, limpe a data da folga nas ocorrências ou limpe o dia no calendário de Escalas.',
      'scaleNumber': '',
      'reminder': '',
      'reminderLeads': <int>[],
      'isAgendaMirror': false,
      'isProdutividadeFolgaMirror': true,
      'agendaType': 'produtividade_folga',
      'produtividadeFolgaDayKey':
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      'source': 'produtividade_folga',
      'lancamentoOrigem': 'produtividade_folga',
      'createdByLancamentoExpresso': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = _ref(userDocId: userDocId, folgaDay: day);
    final existing = await ref.get();
    if (!existing.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }
    await ref.set(payload, SetOptions(merge: true));
  }

  /// Remove o espelho do dia (sem verificar ocorrências).
  static Future<void> deleteMirrorForDay({
    required String userDocId,
    required DateTime folgaDay,
  }) async {
    if (userDocId.isEmpty) return;
    try {
      await _ref(userDocId: userDocId, folgaDay: folgaDay).delete();
    } catch (_) {}
  }

  /// Após limpar `folgaDate` em ocorrências: remove o espelho se já não existir nenhuma
  /// ocorrência com essa data de folga.
  static Future<void> deleteMirrorIfNoOccurrences({
    required String userDocId,
    required DateTime folgaDay,
  }) async {
    if (userDocId.isEmpty) return;
    final day = _calendarDay(folgaDay);
    try {
      final snap = await _ocorrenciasCol(userDocId).get();
      for (final doc in snap.docs) {
        final fd = _folgaDayFromData(doc.data());
        if (fd != null && _sameCalendarDay(fd, day)) return;
      }
      await deleteMirrorForDay(userDocId: userDocId, folgaDay: day);
    } catch (_) {}
  }

  /// Limpar dia no calendário de Escalas → remove espelho e libera ocorrências.
  static Future<int> removeFromCalendarAndClearOcorrencias({
    required String userDocId,
    required DateTime folgaDay,
  }) async {
    if (userDocId.isEmpty) return 0;
    final day = _calendarDay(folgaDay);
    final cleared =
        await OcorrenciasService().clearFolgaForCalendarDay(userDocId, day);
    await deleteMirrorForDay(userDocId: userDocId, folgaDay: day);
    return cleared.length;
  }
}
