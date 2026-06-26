import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_user_doc_id.dart';

/// Preferências opcionais do painel Financeiro (ex.: faixa de contas).

/// Não há mais opção em Configurações para “financeiro avançado”: contas por

/// banco/cartão são sempre ativas; esta classe só guarda prefs complementares.

class FinanceAdvancedSettingsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('finance_prefs');

  static const String _keyStripHideZero = 'financeStripHideZeroBalances';

  /// ID do documento em `finance_accounts` usado como padrão em novos lançamentos.
  static const String keyDefaultFinanceAccountId = 'defaultFinanceAccountId';

  Stream<bool> watchStripHideZeroBalances(String uid) {
    if (uid.isEmpty) return Stream.value(false);
    return _doc(uid).snapshots().map((s) => s.data()?[_keyStripHideZero] == true);
  }

  /// Leitura única (entrada rápida no Financeiro; o stream continua a atualizar).
  Future<bool> getStripHideZeroBalancesOnce(String uid) async {
    if (firestoreUserDocIdStrictFromSession().isEmpty) return false;
    try {
      final snap = await _doc(uid).get();
      return snap.data()?[_keyStripHideZero] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setStripHideZeroBalances(String uid, bool value) async {
    if (uid.isEmpty) return;
    await _doc(uid).set({
      _keyStripHideZero: value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> getDefaultFinanceAccountId(String uid) async {
    if (uid.isEmpty) return null;
    final snap = await _doc(uid).get();
    final v = snap.data()?[keyDefaultFinanceAccountId];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  Stream<String?> watchDefaultFinanceAccountId(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _doc(uid).snapshots().map((s) {
      final v = s.data()?[keyDefaultFinanceAccountId];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    });
  }

  Future<void> setDefaultFinanceAccountId(String uid, String? accountId) async {
    if (uid.isEmpty) return;
    if (accountId == null || accountId.trim().isEmpty) {
      await _doc(uid).set({
        keyDefaultFinanceAccountId: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await _doc(uid).set({
        keyDefaultFinanceAccountId: accountId.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> clearDefaultFinanceAccountIfMatches(String uid, String accountId) async {
    final cur = await getDefaultFinanceAccountId(uid);
    if (cur != null && cur == accountId) {
      await setDefaultFinanceAccountId(uid, null);
    }
  }
}

