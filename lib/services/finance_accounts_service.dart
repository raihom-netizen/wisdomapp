import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../models/finance_account.dart';
import '../utils/firestore_user_doc_id.dart';
import 'finance_advanced_settings_service.dart';
import 'goal_deposit_service.dart';
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
    final key = firestoreUserDocIdForAppShell(uid);
    // Na Web o Firestore roda SEM cache em disco (persistenceEnabled: false +
    // long-polling): o `Source.cache` abaixo volta vazio e a 1ª lista só vinha
    // do servidor — o Financeiro ficava segundos no esqueleto cinza. A última
    // lista que QUALQUER tela recebeu (o Início já escuta as contas) sai na hora.
    final memo = _lastKnownByUid[key];
    if (user != null && memo != null) {
      yield List<FinanceAccount>.of(memo);
    }
    if (user != null && memo == null) {
      // Tentativa de seed instantâneo via cache local (IndexedDB / disk).
      try {
        final cachedSnap =
            await _col(uid).get(const GetOptions(source: Source.cache));
        if (cachedSnap.docs.isNotEmpty) {
          final list = cachedSnap.docs.map(FinanceAccount.fromDoc).toList();
          sortFinanceAccounts(list);
          _lastKnownByUid[key] = list;
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
        _lastKnownByUid[key] = list;
        return list;
      });
    });
  }

  /// Última lista de contas recebida nesta sessão (memória), por usuário.
  static final Map<String, List<FinanceAccount>> _lastKnownByUid = {};

  /// Contas já conhecidas nesta sessão — pintura instantânea antes do servidor.
  static List<FinanceAccount>? peekLastKnown(String uid) {
    final l = _lastKnownByUid[firestoreUserDocIdForAppShell(uid)];
    return l == null ? null : List<FinanceAccount>.of(l);
  }

  Future<List<FinanceAccount>> listOnce(String uid) async {
    if (firestoreUserDocIdStrictFromSession().isEmpty) return const [];
    final key = firestoreUserDocIdForAppShell(uid);
    // Cache local primeiro — abertura do Financeiro/Agenda sem esperar rede.
    try {
      final cached = await _col(uid).get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        final list = cached.docs.map(FinanceAccount.fromDoc).toList();
        sortFinanceAccounts(list);
        // Atualiza persistence em background.
        // ignore: unawaited_futures
        _col(uid).get(const GetOptions(source: Source.serverAndCache));
        return list;
      }
    } catch (_) {}
    final snap = await _col(uid).get(
      const GetOptions(source: Source.serverAndCache),
    );
    final list = snap.docs.map(FinanceAccount.fromDoc).toList();
    sortFinanceAccounts(list);
    _lastKnownByUid[key] = list;
    return list;
  }

  static String _normalizeProductType(String productType) {
    if (productType == FinanceAccount.kChecking ||
        productType == FinanceAccount.kSavings ||
        productType == FinanceAccount.kCard ||
        productType == FinanceAccount.kBankAndCard ||
        productType == FinanceAccount.kVault) {
      return productType;
    }
    return FinanceAccount.kChecking;
  }

  /// Localiza a conta Cofre pessoal na lista (productType vault).
  static FinanceAccount? findVaultAccount(Iterable<FinanceAccount> accounts) {
    for (final a in accounts) {
      if (a.isVaultProduct) return a;
    }
    return null;
  }

  /// Garante uma conta «Cofre pessoal» por usuário (reserva / dinheiro físico).
  Future<String> ensureVaultAccount(String uid) async {
    if (firestoreUserDocIdStrictFromSession().isEmpty) return '';
    final prefs = FinanceAdvancedSettingsService();
    final savedId = await prefs.getVaultAccountId(uid);
    if (savedId != null && savedId.isNotEmpty) {
      final doc = await _col(uid).doc(savedId).get();
      if (doc.exists) {
        final acc = FinanceAccount.fromDoc(doc);
        if (acc.isVaultProduct) return savedId;
      }
    }
    final all = await listOnce(uid);
    final existing = findVaultAccount(all);
    if (existing != null) {
      await prefs.setVaultAccountId(uid, existing.id);
      return existing.id;
    }
    final ref = _col(uid).doc();
    await ref.set({
      ...FinanceAccount(
        id: ref.id,
        presetId: FinanceAccount.kVaultPresetId,
        productType: FinanceAccount.kVault,
        nickname: 'Cofre pessoal',
        sortOrder: -1000000,
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await prefs.setVaultAccountId(uid, ref.id);
    return ref.id;
  }

  Future<String> addAccount({
    required String uid,
    required String presetId,
    required String productType,
    String? nickname,
    int? statementClosingDay,
    String? cardColorId,
    String? holderDocument,
    String? holderName,
    String? bankBranchCode,
    String? bankAccountNumber,
    String? bankOperationCode,
    String? pixKey,
    List<String>? pixKeys,
    String? bankCardNumber,
    int? cardDueDay,
    int? bestPurchaseDay,
  }) async {
    final pt = _normalizeProductType(productType);
    final ref = _col(uid).doc();
    final sc = _normalizeStatementClosingDay(statementClosingDay, productType: pt);
    final dv = _normalizeStatementClosingDay(cardDueDay, productType: pt);
    final cc = _normalizeCardColorId(cardColorId);
    await ref.set({
      ...FinanceAccount(
        id: ref.id,
        presetId: presetId,
        productType: pt,
        nickname: nickname,
        sortOrder: DateTime.now().millisecondsSinceEpoch % 1000000,
        statementClosingDay: sc,
        cardDueDay: dv,
        bestPurchaseDay: _normalizeStatementClosingDay(bestPurchaseDay, productType: pt),
        cardColorId: cc,
        holderDocument: _normalizeHolderDocument(holderDocument),
        holderName: _normalizeOptionalText(holderName),
        bankBranchCode: _normalizeOptionalText(bankBranchCode),
        bankAccountNumber: _normalizeOptionalText(bankAccountNumber),
        bankOperationCode: _normalizeOptionalText(bankOperationCode),
        pixKey: _normalizeOptionalText(pixKey),
        pixKeys: _chavesPix(pixKey, pixKeys),
        bankCardNumber: _normalizeOptionalText(bankCardNumber),
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static String? _normalizeHolderDocument(String? doc) {
    final digits = (doc ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  /// Lista de chaves sem vazias nem repetidas, a padrão primeiro.
  static List<String> _chavesPix(String? padrao, List<String>? outras) {
    final out = <String>[];
    for (final k in [padrao ?? '', ...?outras]) {
      final t = k.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  static String? _normalizeOptionalText(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
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
    String? holderDocument,
    String? holderName,
    String? bankBranchCode,
    String? bankAccountNumber,
    String? bankOperationCode,
    String? pixKey,
    List<String>? pixKeys,
    String? bankCardNumber,
    int? cardDueDay,
    int? bestPurchaseDay,
    // Conta já ligada ao Open Finance: quem manda nesses campos é a
    // sincronização — reenviar o texto do formulário (que pode estar um
    // passo atrás de um sync que rodou enquanto a tela estava aberta) não
    // pode sobrescrever o dado real do banco.
    bool touchBankManualFields = true,
  }) async {
    final pt = _normalizeProductType(productType);
    final sc = _normalizeStatementClosingDay(statementClosingDay, productType: pt);
    final dv = _normalizeStatementClosingDay(cardDueDay, productType: pt);
    final cc = _normalizeCardColorId(cardColorId);
    final hd = _normalizeHolderDocument(holderDocument);
    final hn = _normalizeOptionalText(holderName);
    final agencia = _normalizeOptionalText(bankBranchCode);
    final conta = _normalizeOptionalText(bankAccountNumber);
    final operacao = _normalizeOptionalText(bankOperationCode);
    final pix = _normalizeOptionalText(pixKey);
    final numeroCartao = _normalizeOptionalText(bankCardNumber);
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
    if (dv != null) {
      data['cardDueDay'] = dv;
    } else {
      data['cardDueDay'] = FieldValue.delete();
    }
    final melhor = _normalizeStatementClosingDay(bestPurchaseDay, productType: pt);
    data['bestPurchaseDay'] = melhor ?? FieldValue.delete();
    if (cc != null) {
      data['cardColorId'] = cc;
    } else {
      data['cardColorId'] = FieldValue.delete();
    }
    if (hd != null) {
      data['holderDocument'] = hd;
    } else {
      data['holderDocument'] = FieldValue.delete();
    }
    if (hn != null) {
      data['holderName'] = hn;
    } else {
      data['holderName'] = FieldValue.delete();
    }
    if (touchBankManualFields) {
      data['bankBranchCode'] = agencia ?? FieldValue.delete();
      data['bankAccountNumber'] = conta ?? FieldValue.delete();
      data['bankOperationCode'] = operacao ?? FieldValue.delete();
      data['bankCardNumber'] = numeroCartao ?? FieldValue.delete();
    }
    // A chave Pix é SEMPRE do usuário, mesmo em conta conectada ao Open
    // Finance (onde agência e conta vêm do banco e não se editam). Antes ela
    // ficava dentro do bloco acima e não era gravada em conta conectada — o
    // campo nem aparecia, e o «Receber via Pix» ficava sem chave.
    data['pixKey'] = pix ?? FieldValue.delete();
    // Nulo = quem chamou não mexe na lista (formulários antigos).
    if (pixKeys != null) {
      final todas = _chavesPix(pix, pixKeys);
      data['pixKeys'] = todas.isEmpty ? FieldValue.delete() : todas;
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

  Future<Set<String>> _collectLinkedTransactionIds(
      String uid, String accountId) async {
    final ids = <String>{};
    await _forEachTxByField(uid, 'financeAccountId', accountId, ids.add);
    await _forEachTxByField(
        uid, 'paidFromFinanceAccountId', accountId, ids.add);

    final pairIds = <String>{};
    final idList = ids.toList();
    for (var i = 0; i < idList.length; i += 25) {
      final chunk =
          idList.sublist(i, i + 25 > idList.length ? idList.length : i + 25);
      final snaps =
          await Future.wait(chunk.map((id) => _txCol(uid).doc(id).get()));
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

    // Desvincula Meta / recalcula semanas antes de apagar cada lançamento.
    for (final id in ids) {
      try {
        final snap = await col.doc(id).get();
        if (!snap.exists) continue;
        await GoalDepositService.unlinkBeforeTransactionDelete(
          uid: uid,
          txId: id,
          txData: snap.data() ?? {},
        );
      } catch (_) {}
    }

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

  /// Remove a conta e todos os lançamentos vinculados (inclui transferências relacionadas).
  /// O Cofre pessoal não pode ser excluído.
  Future<int> deleteAccount(String uid, String accountId) async {
    final doc = await _col(uid).doc(accountId).get();
    if (doc.exists) {
      final acc = FinanceAccount.fromDoc(doc);
      if (acc.isVaultProduct) {
        throw StateError('O Cofre pessoal não pode ser excluído.');
      }
    }
    final linkedIds = await _collectLinkedTransactionIds(uid, accountId);
    await _deleteTransactionsByIds(uid, linkedIds);
    await _col(uid).doc(accountId).delete();
    await FinanceAdvancedSettingsService()
        .clearDefaultFinanceAccountIfMatches(uid, accountId);
    FinanceTransactionsHub.notifyMutated(
        uid: firestoreUserDocIdForAppShell(uid));
    return linkedIds.length;
  }

  /// Quantos lançamentos PENDENTES ainda estão presos a uma conta.
  ///
  /// Serve para perguntar, ao trocar o banco padrão, se as contas a pagar
  /// devem migrar junto — as já pagas ficam onde estão, porque mexer nelas
  /// reescreveria o extrato de um banco que de fato debitou o valor.
  Future<int> countPendingTransactions(String uid, String accountId) async {
    final id = firestoreUserDocIdForAppShell(uid);
    if (id.isEmpty || accountId.trim().isEmpty) return 0;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .collection('transactions')
        .where('financeAccountId', isEqualTo: accountId)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Move os lançamentos pendentes de uma conta para outra.
  ///
  /// Só toca em `status == 'pending'`: quem já foi pago permanece no banco que
  /// pagou. Devolve quantos foram movidos.
  Future<int> movePendingTransactions({
    required String uid,
    required String fromAccountId,
    required String toAccountId,
  }) async {
    final id = firestoreUserDocIdForAppShell(uid);
    if (id.isEmpty || fromAccountId == toAccountId) return 0;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .collection('transactions');

    var movidos = 0;
    // Em blocos: a fila pode ter centenas de contas a pagar.
    while (true) {
      final lote = await col
          .where('financeAccountId', isEqualTo: fromAccountId)
          .where('status', isEqualTo: 'pending')
          .limit(400)
          .get();
      if (lote.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in lote.docs) {
        batch.set(
          d.reference,
          {
            'financeAccountId': toAccountId,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      movidos += lote.docs.length;
      if (lote.docs.length < 400) break;
    }
    return movidos;
  }

  /// A conta veio do Open Finance (e vai parar de sincronizar se for excluída)?
  Future<bool> isOpenFinanceLinked(String uid, String accountId) async {
    try {
      final snap = await _col(uid).doc(accountId).get();
      final d = snap.data() ?? const {};
      return (d['externalResourceId'] ?? '').toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Persiste a ordem exibida (campo [FinanceAccount.sortOrder]).
  Future<void> setAccountOrder(
      String uid, List<String> orderedAccountIds) async {
    if (orderedAccountIds.isEmpty ||
        firestoreUserDocIdStrictFromSession().isEmpty) {
      return;
    }
    final batch = _db.batch();
    for (var i = 0; i < orderedAccountIds.length; i++) {
      batch.update(_col(uid).doc(orderedAccountIds[i]), {
        'sortOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> updateNickname(
      String uid, String accountId, String? nickname) async {
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
