import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_business_rules.dart';
import '../utils/firestore_user_doc_id.dart';

/// Preferências de exibição das receitas fixas: contas pendentes e quantos meses à frente.
class FixedIncomePreferencesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _showInPendingKey = 'showInPending';
  static const int _defaultPendingMonthsAhead = AppBusinessRules.pendingMonthsAheadDefault;
  static const String _pendingMonthsAheadKey = 'pendingMonthsAhead';

  DocumentReference<Map<String, dynamic>> _settingsRef(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('fixed_incomes');

  Future<bool> getShowInPending(String uid) async {
    final snap = await _settingsRef(uid).get();
    final data = snap.data();
    if (data == null) return true;
    return data[_showInPendingKey] as bool? ?? true;
  }

  Future<int> getPendingMonthsAhead(String uid) async {
    final snap = await _settingsRef(uid).get();
    final data = snap.data();
    if (data == null) return _defaultPendingMonthsAhead;
    final v = data[_pendingMonthsAheadKey];
    if (v is num) return (v.toInt()).clamp(1, 12);
    return _defaultPendingMonthsAhead;
  }

  Future<void> set(String uid, {bool? showInPending, int? pendingMonthsAhead}) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (showInPending != null) data[_showInPendingKey] = showInPending;
    if (pendingMonthsAhead != null) data[_pendingMonthsAheadKey] = pendingMonthsAhead.clamp(1, 12);
    await _settingsRef(uid).set(data, SetOptions(merge: true));
  }

  Stream<Map<String, dynamic>> watch(String uid) {
    return _settingsRef(uid).snapshots().map((s) {
      final d = s.data();
      return {
        _showInPendingKey: d?[_showInPendingKey] as bool? ?? true,
        _pendingMonthsAheadKey: (d?[_pendingMonthsAheadKey] as num?)?.toInt().clamp(1, 12) ?? _defaultPendingMonthsAhead,
      };
    });
  }
}
