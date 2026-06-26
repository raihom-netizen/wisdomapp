import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scale_rates.dart';
import '../models/scale_rates_period.dart';
import '../utils/firestore_user_doc_id.dart';
import 'scale_rates_service.dart';

/// Períodos personalizados do usuário (linha do tempo início/fim) em `scale_rates.ratePeriods`.
class UserScaleRatesPeriodService {
  UserScaleRatesPeriodService._();
  factory UserScaleRatesPeriodService() => _instance;
  static final UserScaleRatesPeriodService _instance =
      UserScaleRatesPeriodService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('scale_rates');

  static List<ScaleRatesPeriod> _parseUserPeriods(dynamic raw) {
    if (raw is! List || raw.isEmpty) return [];
    final out = <ScaleRatesPeriod>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        out.add(ScaleRatesPeriod.fromMap(item));
      } else if (item is Map) {
        out.add(ScaleRatesPeriod.fromMap(Map<String, dynamic>.from(item)));
      }
    }
    return ScaleRatesPeriod.sortAsc(out);
  }

  Future<List<ScaleRatesPeriod>> getPeriods(String uid) async {
    if (uid.isEmpty) return [];
    try {
      final snap = await _doc(uid).get();
      final data = snap.data();
      if (data == null) return [];
      final parsed = _parseUserPeriods(data['ratePeriods']);
      if (parsed.isEmpty) return [];
      return parsed;
    } catch (_) {
      return [];
    }
  }

  Stream<List<ScaleRatesPeriod>> watchPeriods(String uid) {
    if (uid.isEmpty) {
      return Stream.value(const <ScaleRatesPeriod>[]);
    }
    return _doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return <ScaleRatesPeriod>[];
      return _parseUserPeriods(data['ratePeriods']);
    });
  }

  Future<void> savePeriods(String uid, List<ScaleRatesPeriod> periods) async {
    if (uid.isEmpty) return;
    final sorted = ScaleRatesPeriod.sortAsc(periods);
    final active =
        ScaleRatesPeriod.resolveAt(DateTime.now(), sorted) ?? sorted.first;
    await _doc(uid).set({
      'ratePeriods': sorted.map((p) => p.toMap()).toList(),
      ...active.rates.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    ScaleRatesService().invalidateMemory(uid);
  }

  Future<ScaleRates> ratesForServiceDay(String uid, DateTime serviceDay) async {
    final periods = await getPeriods(uid);
    if (periods.isEmpty) {
      return ScaleRatesService().getRates(uid: uid);
    }
    final hit = ScaleRatesPeriod.resolveAt(serviceDay, periods);
    return hit?.rates ?? periods.first.rates;
  }
}
