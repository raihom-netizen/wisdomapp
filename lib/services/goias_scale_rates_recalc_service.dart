import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scale_entry.dart';
import '../models/scale_rates.dart';
import '../utils/firestore_user_doc_id.dart';
import 'scale_rates_period_service.dart';
import 'scale_rates_service.dart';

/// Recalcula plantões GO (padrão global) após mudança de período no histórico.
class GoiasScaleRatesRecalcService {
  GoiasScaleRatesRecalcService._();
  factory GoiasScaleRatesRecalcService() => _instance;
  static final GoiasScaleRatesRecalcService _instance =
      GoiasScaleRatesRecalcService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ScaleRatesPeriodService _periods = ScaleRatesPeriodService();

  /// Roda em background ao abrir o app / escalas (idempotente por versão).
  Future<void> runIfNeeded(String uid) async {
    if (uid.isEmpty) return;
    await _periods.ensureLoaded();
    final recalcVersion = _periods.recalcVersionKey;
    if (recalcVersion.isEmpty) return;
    if (!await ScaleRatesService().usesGlobalGoiasRates(uid)) return;

    final fromDate = _periods.recalcFromDate;
    if (fromDate == null) return;

    final fsId = firestoreUserDocIdForAppShell(uid);
    final flagRef = _db
        .collection('users')
        .doc(fsId)
        .collection('settings')
        .doc('goias_rates_recalc');

    try {
      final flagSnap = await flagRef.get();
      if (flagSnap.exists &&
          (flagSnap.data()?['version'] ?? '').toString() == recalcVersion) {
        return;
      }

      final scalesCol = _db.collection('users').doc(fsId).collection('scales');
      final fromTs = Timestamp.fromDate(fromDate);
      final snap = await scalesCol
          .where('date', isGreaterThanOrEqualTo: fromTs)
          .limit(500)
          .get();

      if (snap.docs.isEmpty) {
        await flagRef.set({
          'version': recalcVersion,
          'updatedAt': FieldValue.serverTimestamp(),
          'recalculated': 0,
        });
        return;
      }

      var updated = 0;
      WriteBatch? batch;
      var ops = 0;

      for (final doc in snap.docs) {
        final entry = ScaleEntry.fromDoc(doc);
        if (entry.isCompromisso || entry.totalValue <= 0) continue;

        final (startDt, endDt) = _shiftBounds(entry);
        final res = await ScaleRatesService().computeShiftForUid(
          uid: uid,
          start: startDt,
          end: endDt,
          entryDate: entry.date,
        );
        final newTotal = (res['total'] ?? 0).toDouble();
        final newHoursDay = (res['hoursDay'] ?? 0).toDouble();
        final newHoursNight = (res['hoursNight'] ?? 0).toDouble();
        final ratesDay =
            await ScaleRatesService().getRatesForServiceDay(uid, entry.date);
        final wd = ScaleRates.weekdayToIndex(entry.date.weekday);
        final newDayRate = ratesDay.diurnoForWeekday(wd);
        final newNightRate = ratesDay.noturnoForWeekday(wd);

        final changed = (newTotal - entry.totalValue).abs() > 0.009 ||
            (newHoursDay - entry.hoursDay).abs() > 0.009 ||
            (newHoursNight - entry.hoursNight).abs() > 0.009;

        if (!changed) continue;

        batch ??= _db.batch();
        batch.update(doc.reference, {
          'totalValue': newTotal,
          'hoursDay': newHoursDay,
          'hoursNight': newHoursNight,
          'dayRate': newDayRate,
          'nightRate': newNightRate,
          'goiasRatesRecalcAt': FieldValue.serverTimestamp(),
          'goiasRatesRecalcVersion': recalcVersion,
        });
        updated++;
        ops++;
        if (ops >= 400) {
          await batch.commit();
          batch = null;
          ops = 0;
        }
      }

      if (batch != null && ops > 0) {
        await batch.commit();
      }

      await flagRef.set({
        'version': recalcVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        'recalculated': updated,
      });

      if (updated > 0) {
        ScaleRatesService().invalidateMemory(uid);
      }
    } catch (_) {
      // Falha silenciosa — tenta na próxima abertura.
    }
  }

  (DateTime, DateTime) _shiftBounds(ScaleEntry e) {
    final partsStart = e.start.split(':');
    final partsEnd = e.end.split(':');
    final sh = int.tryParse(partsStart.first) ?? 8;
    final sm = partsStart.length > 1 ? int.tryParse(partsStart[1]) ?? 0 : 0;
    final eh = int.tryParse(partsEnd.first) ?? 18;
    final em = partsEnd.length > 1 ? int.tryParse(partsEnd[1]) ?? 0 : 0;
    var startDt = DateTime(e.date.year, e.date.month, e.date.day, sh, sm);
    var endDt = DateTime(e.date.year, e.date.month, e.date.day, eh, em);
    if (!endDt.isAfter(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }
    return (startDt, endDt);
  }
}
