import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_user_doc_id.dart';

/// Quando virou o dia e o usuário não marcou o plantão como confirmado,
/// o sistema entende que ele realmente tirou e marca automaticamente como confirmado.
class ScaleAutoConfirmService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DateTime _parseDateOnly(dynamic raw) {
    if (raw is Timestamp) {
      final d = raw.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    return DateTime.now();
  }

  DateTime _parseHorario(DateTime baseDate, dynamic raw, {required String fallback}) {
    final txt = ((raw ?? fallback).toString()).trim();
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(txt);
    if (m == null) {
      final fb = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(fallback)!;
      return DateTime(baseDate.year, baseDate.month, baseDate.day,
          int.parse(fb.group(1)!), int.parse(fb.group(2)!));
    }
    final hh = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    return DateTime(baseDate.year, baseDate.month, baseDate.day, hh, mm);
  }

  DateTime _fimDoServico(Map<String, dynamic> data) {
    final baseDate = _parseDateOnly(data['date']);
    final start = _parseHorario(baseDate, data['start'], fallback: '08:00');
    var end = _parseHorario(baseDate, data['end'], fallback: '18:00');
    // Virada de turno noturno (ex.: 20:00 -> 08:00)
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return end;
  }

  /// Marca automaticamente como confirmado (paid=true) quando:
  /// - Já passou 10 minutos do horário de término do serviço, sem precisar virar o dia.
  /// - Funciona para plantões extras e compromissos.
  ///
  /// Mantém retrocompatibilidade: serviços antigos no passado também entram quando já passaram do corte.
  Future<int> autoConfirmarPlantaoesPassados(String uid) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final windowStart = today.subtract(const Duration(days: 90));
    final id = firestoreUserDocIdForAppShell(uid);
    final ref = _db.collection('users').doc(id).collection('scales');

    final snap = await ref
        .where('paid', isEqualTo: false)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(tomorrow))
        .limit(500)
        .get();

    int count = 0;
    WriteBatch batch = _db.batch();
    int ops = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      // Espelhos da Agenda não devem ser auto-confirmados — o "paid" não tem
      // significado para audiências/compromissos da Agenda (só para plantões).
      // Mantém o doc intacto; o estado real fica no `reminders` original.
      if (data['isAgendaMirror'] == true) continue;
      if (data['isProdutividadeFolgaMirror'] == true) continue;
      final cutoff = _fimDoServico(data).add(const Duration(minutes: 10));
      if (!now.isBefore(cutoff)) {
        batch.update(doc.reference, {'paid': true});
        count++;
        ops++;
      }

      // Evita exceder limite de operações por batch.
      if (ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }
    return count;
  }
}
