import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../models/finance_account.dart';
import '../utils/firestore_user_doc_id.dart';
import 'finance_advanced_settings_service.dart';
import '../utils/finance_transactions_hub.dart';

class FinanceAccountsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('finance_accounts');

  /// Mesma ordenação em todo o app: [sortOrder] crescente, empate por data de criação.
  static void sortFinanceAccounts(List<FinanceAccount> list) {
    list.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      final da = a.createdAt ?? DateTime(2000);
      final db = b.createdAt ?? DateTime(2000);
      return da.compareTo(db);
    });
  }

  /// Contas: mesma regra de sessão — sem [currentUser] não abrir leitura (erro de permissão na web).
  /// Usa o mesmo caminho que [listOnce]/[setAccountOrder] (`_col`) para a ordem gravada coincidir com o stream.
  ///
  /// **Performance**: para evitar tela vazia "Cadastre contas em Financeiro"
  /// enquanto o servidor responde, lemos do **cache local primeiro**
  /// (`Source.cache`) e emitimos imediatamente — depois deixa o snapshot
  /// listener com o servidor entregar a versão fresca. Em iOS/Android/Web
  /// isso deixa a abertura do bottom sheet **instantânea** quando o usuário
  /// já tem contas cadastradas.
  Stream<List<FinanceAccount>> streamAccounts(String uid) async* {
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Tentativa de seed instantâneo via cache local (IndexedDB / disk).
      try {
        final cachedSnap =
            await _col(uid).get(const GetOptions(source: Source.cache));
        if (cachedSnap.docs.isNotEmpty) {
          final list =
              cachedSnap.docs.map(FinanceAccount.fromDoc).toList();
          sortFinanceAccounts(list);
          yield list;
        }
      } catch (_) {
        // Cache miss ou indisponível — segue para o snapshot listener.
      }
    }
    yield* fa.FirebaseAuth.instance.authStateChanges().asyncExpand((u) {
      if (u == null) {
        return Stream<List<FinanceAccount>>.value(const <FinanceAccount>[]);
      }
      return _col(uid).snapshots().map((snap) {
        final list = snap.docs.map(FinanceAccount.fromDoc).toList();
        sortFinanceAccounts(list);
        return list;
      });
    });
  }

  Future<List<FinanceAccount>> listOnce(String uid) async {
    if (firestoreUserDocIdStrictFromSession().isEmpty) return const [];
    final snap = await _col(uid).get();
    final list = snap.docs.map(FinanceAccount.fromDoc).toList();
    sortFinanceAccounts(list);
    return list;
  }

  static String _normalizeProductType(String productType) {
    if (productType == FinanceAccount.kChecking ||
        productType == FinanceAccount.kSavings ||
        productType == FinanceAccount.kCard ||
        productType == FinanceAccount.kBankAndCard) {
      return productType;
    }
    return FinanceAccount.kChecking;
  }

  Future<String> addAccount({
    required String uid,
    required String presetId,
    required String productType,
    String? nickname,
    int? statementClosingDay,
    String? cardColorId,
  }) async {
    final pt = _normalizeProductType(productType);
    final ref = _col(uid).doc();
    final sc = _normalizeStatementClosingDay(statementClosingDay, productType: pt);
    final cc = _normalizeCardColorId(cardColorId);
    await ref.set({
      ...FinanceAccount(
        id: ref.id,
        presetId: presetId,
        productType: pt,
        nickname: nickname,
        sortOrder: DateTime.now().millisecondsSinceEpoch % 1000000,
        statementClosingDay: sc,
        cardColorId: cc,
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static String? _normalizeCardColorId(String? id) {
    final t = id?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static int? _normalizeStatementClosingDay(int? day, {required String productType}) {
    if (day == null) return null;
    if (productType != FinanceAccount.kCard && productType != FinanceAccount.kBankAndCard) return null;
    if (day < 1 || day > 31) return null;
    return day;
  }

  Future<void> updateAccount({
    required String uid,
    required String accountId,
    required String presetId,
    required String productType,
    String? nickname,
    int? statementClosingDay,
    String? cardColorId,
  }) async {
    final pt = _normalizeProductType(productType);
    final sc = _normalizeStatementClosingDay(statementClosingDay, productType: pt);
    final cc = _normalizeCardColorId(cardColorId);
    final acc = FinanceAccount(
      id: accountId,
      presetId: presetId,
      productType: pt,
      nickname: nickname?.trim().isEmpty == true ? null : nickname?.trim(),
      statementClosingDay: sc,
      cardColorId: cc,
    );
    final data = <String, dynamic>{
      'presetId': acc.presetId,
      'productType': acc.productType,
      'kind': acc.kind,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (acc.nickname == null) {
      data['nickname'] = FieldValue.delete();
    } else {
      data['nickname'] = acc.nickname;
    }
    if (sc != null) {
      data['statementClosingDay'] = sc;
    } else {
      data['statementClosingDay'] = FieldValue.delete();
    }
    if (cc != null) {
      data['cardColorId'] = cc;
    } else {
      data['cardColorId'] = FieldValue.delete();
    }
    await _col(uid).doc(accountId).update(data);
  }

  CollectionReference<Map<String, dynamic>> _txCol(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('transactions');

  /// Lançamentos com [financeAccountId] ou [paidFromFinanceAccountId] + pares de transferência.
  Future<int> countLinkedTransactions(String uid, String accountId) async {
    final ids = await _collectLinkedTransactionIds(uid, accountId);
    return ids.length;
  }

  Future<void> _forEachTxByField(
    String uid,
    String field,
    String value,
    void Function(String docId) onId,
  ) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      Query<Map<String, dynamic>> q =
          _txCol(uid).where(field, isEqualTo: value).limit(500);
      if (last != null) q = q.startAfterDocument(last);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      for (final doc in snap.docs) {
        onId(doc.id);
      }
      last = snap.docs.last;
      if (snap.docs.length < 500) break;
    }
  }

  Future<Set<String>> _collectLinkedTransactionIds(String uid, String accountId) async {
    final ids = <String>{};
    await _forEachTxByField(uid, 'financeAccountId', accountId, ids.add);
    await _forEachTxByField(uid, 'paidFromFinanceAccountId', accountId, ids.add);

    final pairIds = <String>{};
    final idList = ids.toList();
    for (var i = 0; i < idList.length; i += 25) {
      final chunk = idList.sublist(i, i + 25 > idList.length ? idList.length : i + 25);
      final snaps = await Future.wait(chunk.map((id) => _txCol(uid).doc(id).get()));
      for (final snap in snaps) {
        final pair = (snap.data()?['transferPairId'] ?? '').toString().trim();
        if (pair.isNotEmpty) pairIds.add(pair);
      }
    }
    for (final pairId in pairIds) {
      final pairSnap =
          await _txCol(uid).where('transferPairId', isEqualTo: pairId).get();
      for (final doc in pairSnap.docs) {
        ids.add(doc.id);
      }
    }
    return ids;
  }

  Future<void> _deleteTransactionsByIds(String uid, Set<String> ids) async {
    if (ids.isEmpty) return;
    final col = _txCol(uid);
    var batch = _db.batch();
    var n = 0;
    for (final id in ids) {
      batch.delete(col.doc(id));
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = _db.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }

  /// Remove a conta e **todos** os lançamentos vinculados (inclui transferências relacionadas).
  Future<int> deleteAccount(String uid, String accountId) async {
    final linkedIds = await _collectLinkedTransactionIds(uid, accountId);
    await _deleteTransactionsByIds(uid, linkedIds);
    await _col(uid).doc(accountId).delete();
    await FinanceAdvancedSettingsService().clearDefaultFinanceAccountIfMatches(uid, accountId);
    FinanceTransactionsHub.notifyMutated(uid: firestoreUserDocIdForAppShell(uid));
    return linkedIds.length;
  }

  /// Persiste a ordem exibida (campo [FinanceAccount.sortOrder]).
  Future<void> setAccountOrder(String uid, List<String> orderedAccountIds) async {
    if (orderedAccountIds.isEmpty || firestoreUserDocIdStrictFromSession().isEmpty) return;
    final batch = _db.batch();
    for (var i = 0; i < orderedAccountIds.length; i++) {
      batch.update(_col(uid).doc(orderedAccountIds[i]), {
        'sortOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> updateNickname(String uid, String accountId, String? nickname) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (nickname == null || nickname.trim().isEmpty) {
      data['nickname'] = FieldValue.delete();
    } else {
      data['nickname'] = nickname.trim();
    }
    await _col(uid).doc(accountId).update(data);
  }
}
