import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/finance_bank_presets.dart';

/// Conta bancária ou cartão cadastrado pelo usuário.
class FinanceAccount {
  static const String kChecking = 'checking';
  static const String kSavings = 'savings';
  static const String kCard = 'card';
  /// Mesma instituição com conta bancária e cartão (um cadastro; útil p.ex. Nubank corrente + crédito).
  static const String kBankAndCard = 'bank_and_card';
  /// Reserva separada (dinheiro físico / emergência) — Cofre pessoal.
  static const String kVault = 'vault';
  static const String kVaultPresetId = 'cofre_pessoal';

  final String id;
  final String presetId;
  /// Conta corrente, poupança ou cartão (`kChecking` / `kSavings` / `kCard`).
  final String productType;
  final String? nickname;
  final int sortOrder;
  final DateTime? createdAt;
  /// Dia do mês em que a fatura do cartão fecha (1–31), para conferir com o app do banco.
  final int? statementClosingDay;
  /// Tema de cor do card no Financeiro (`ocean`, `violet`, …). Null = automática (banco + tipo).
  final String? cardColorId;

  /// Saldo que o próprio banco informou na última sincronização do Open
  /// Finance. Null quando a conta não é integrada.
  ///
  /// O app calcula saldo somando lançamentos; numa conta integrada esse cálculo
  /// só bate com o extrato do banco se absolutamente tudo tiver sido importado.
  /// Para o usuário, o número certo é o do banco — é o que ele confere no app
  /// da instituição.
  final double? bankBalance;

  /// Quando o saldo do banco foi lido (mostrado junto, para dar contexto).
  final DateTime? bankBalanceAt;

  /// Fatura do cartão informada pelo banco — separada de [bankBalance] para
  /// que, num cadastro "conta + cartão", uma não apague a outra (os dois
  /// dividem o mesmo documento). Null quando a conta não tem cartão integrado.
  final double? cardBillBalance;

  /// Fatura ATUAL igual à do app do banco (limite usado − faturas futuras),
  /// gravada pela sincronização. É o «quanto estou devendo agora».
  final double? faturaAtualBanco;

  /// AAAA-MM da fatura de [faturaAtualBanco] (a fechada ainda não paga ou a
  /// aberta) — gravado pela sincronização; dá as datas certas no card.
  final String? faturaAtualRef;

  /// Limite do cartão informado pelo banco (Open Finance).
  final double? limiteTotal;
  final double? limiteUsado;
  final double? limiteDisponivel;

  /// `true` quando fechamento/vencimento foram DEDUZIDOS das faturas do banco
  /// (sincronização) em vez de digitados no cadastro — mostrado na ficha do
  /// cartão pra o usuário saber a origem do dado.
  final bool cicloInferidoDoBanco;

  /// Agência, número, dígito, tipo (`checking`/`savings`) e código COMPE do
  /// banco. Numa conta ligada ao Open Finance vêm da sincronização (só
  /// leitura na tela); numa conta manual, o que o usuário digitou — fica
  /// pronto para quando ela for conectada ao Finance Pro no futuro.
  final String? bankBranchCode;
  final String? bankAccountNumber;
  final String? bankAccountCheckDigit;
  final String? bankAccountType;
  final String? bankCompeCode;

  /// "Operação" — 3 dígitos que bancos como a Caixa usam junto da conta.
  final String? bankOperationCode;

  /// Chave PIX PADRÃO da conta — só cadastro manual (o Open Finance não
  /// devolve isso hoje). É a que sai quando ninguém escolhe outra.
  final String? pixKey;

  /// Todas as chaves Pix da conta (CPF, celular, e-mail, aleatória…). A
  /// padrão ([pixKey]) sempre vem primeiro. Contas antigas só têm `pixKey`.
  final List<String> pixKeys;

  /// Chaves da conta sem repetir, a padrão primeiro.
  List<String> get chavesPix {
    final out = <String>[];
    for (final k in [pixKey ?? '', ...pixKeys]) {
      final t = k.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  /// Número (mascarado ou como o usuário digitou) do cartão de crédito.
  final String? bankCardNumber;

  /// Nome completo (pessoa física) ou razão social (pessoa jurídica) do
  /// titular — vem do Open Finance quando o banco informa, ou digitado no
  /// cadastro manual. Complementa [holderDocument] (CPF/CNPJ).
  final String? holderName;

  /// Dia do mês em que a fatura do cartão VENCE (paga) — diferente de
  /// [statementClosingDay], que é quando ela FECHA.
  final int? cardDueDay;

  /// Melhor dia de compra no cartão (compra a partir dele cai na fatura
  /// seguinte — mais prazo). Normalmente o dia seguinte ao fechamento; o
  /// usuário informa no cadastro.
  final int? bestPurchaseDay;

  /// Melhor dia de compra informado ou, sem ele, o dia seguinte ao fechamento.
  int? get melhorDiaCompra {
    if (bestPurchaseDay != null) return bestPurchaseDay;
    final f = statementClosingDay;
    if (f == null) return null;
    return f >= 31 ? 1 : f + 1;
  }

  /// CPF ou CNPJ do titular — vem do Open Finance ou digitado no cadastro manual.
  final String? holderDocument;

  /// Recurso do Open Finance vinculado — vazio quando a conta é manual.
  final String externalResourceId;

  /// Conexão (consentimento) dona deste recurso — usado para sincronizar só
  /// este banco em vez de todos os conectados.
  final String consentId;

  bool get isOpenFinanceLinked => externalResourceId.trim().isNotEmpty;

  /// Rótulo amigável de [bankAccountType] ("Conta corrente"/"Conta poupança").
  String? get bankAccountTypeLabel {
    switch (bankAccountType) {
      case kSavings:
        return 'Conta poupança';
      case kChecking:
        return 'Conta corrente';
      default:
        return null;
    }
  }

  const FinanceAccount({
    required this.id,
    required this.presetId,
    required this.productType,
    this.nickname,
    this.sortOrder = 0,
    this.createdAt,
    this.statementClosingDay,
    this.cardColorId,
    this.bankBalance,
    this.bankBalanceAt,
    this.cardBillBalance,
    this.faturaAtualBanco,
    this.faturaAtualRef,
    this.limiteTotal,
    this.limiteUsado,
    this.limiteDisponivel,
    this.cicloInferidoDoBanco = false,
    this.bankBranchCode,
    this.bankAccountNumber,
    this.bankAccountCheckDigit,
    this.bankAccountType,
    this.bankCompeCode,
    this.bankOperationCode,
    this.pixKey,
    this.pixKeys = const [],
    this.bankCardNumber,
    this.cardDueDay,
    this.bestPurchaseDay,
    this.holderDocument,
    this.holderName,
    this.externalResourceId = '',
    this.consentId = '',
  });

  /// Próxima data de fechimento (só calendário), útil para exibir ao usuário.
  static DateTime? computeNextStatementClosing(int closingDay, [DateTime? from]) {
    if (closingDay < 1 || closingDay > 31) return null;
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastThis = DateTime(now.year, now.month + 1, 0).day;
    final dThis = closingDay > lastThis ? lastThis : closingDay;
    final thisMonthClose = DateTime(now.year, now.month, dThis);
    if (today.isBefore(thisMonthClose)) return thisMonthClose;
    final ny = now.month == 12 ? now.year + 1 : now.year;
    final nm = now.month == 12 ? 1 : now.month + 1;
    final lastNext = DateTime(ny, nm + 1, 0).day;
    final dNext = closingDay > lastNext ? lastNext : closingDay;
    return DateTime(ny, nm, dNext);
  }

  /// Compatível com dados antigos (`kind` no Firestore).
  String get kind {
    if (productType == kVault) return 'vault';
    if (productType == kCard) return 'card';
    if (productType == kBankAndCard) return 'bank_and_card';
    return 'bank';
  }

  bool get isVaultProduct => productType == kVault;

  /// Usado em filtros: esta conta representa movimentação de cartão.
  bool get isCardProduct => productType == kCard || productType == kBankAndCard;

  /// Cartão de crédito (fatura futura — status pendente por padrão em despesas).
  bool get isCreditCardProduct => productType == kCard;

  /// Conta bancária / débito (saída imediata do saldo).
  bool get isDebitBankProduct => productType == kChecking || productType == kSavings;

  /// Despesa em cartão de crédito ou conta+cartão → pagamento futuro (pendente).
  bool get expenseDefaultsToPending =>
      productType == kCard || productType == kBankAndCard;

  /// Inclui corrente, poupança e o modo «conta + cartão» (saldo bancário).
  bool get isBankProduct =>
      productType == kChecking || productType == kSavings || productType == kBankAndCard;

  FinanceBankPreset? get preset => financeBankPresetById(presetId);

  String get displayName {
    final n = nickname?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (isVaultProduct) return 'Cofre pessoal';
    return preset?.name ?? presetId;
  }

  /// Rótulo curto do tipo de produto (lista / edição).
  String get productTypeLabel {
    switch (productType) {
      case kSavings:
        return 'Poupança';
      case kCard:
        return 'Cartão';
      case kBankAndCard:
        return 'Conta + cartão';
      case kVault:
        return 'Cofre pessoal';
      case kChecking:
      default:
        return 'Conta corrente';
    }
  }

  factory FinanceAccount.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final created = d['createdAt'];
    final rawSc = d['statementClosingDay'];
    int? statementClosingDay;
    if (rawSc is num) {
      final v = rawSc.toInt();
      if (v >= 1 && v <= 31) statementClosingDay = v;
    }
    final rawCc = (d['cardColorId'] ?? '').toString().trim();
    final cardColorId = rawCc.isEmpty ? null : rawCc;
    final rawPt = (d['productType'] ?? '').toString().trim();
    String pt;
    if (rawPt == kChecking ||
        rawPt == kSavings ||
        rawPt == kCard ||
        rawPt == kBankAndCard ||
        rawPt == kVault) {
      pt = rawPt;
    } else {
      final legacyKind = (d['kind'] ?? 'bank').toString();
      pt = legacyKind == 'card' ? kCard : kChecking;
    }
    final ext = (d['externalResourceId'] ?? '').toString().trim();
    final rawBalance = d['balance'];
    final rawCardBill = d['cardBillBalance'];
    final updated = d['updatedAt'];
    String? txt(String key) {
      final v = (d[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }
    final rawDue = d['cardDueDay'];
    int? cardDueDay;
    if (rawDue is num) {
      final v = rawDue.toInt();
      if (v >= 1 && v <= 31) cardDueDay = v;
    }
    final rawBest = d['bestPurchaseDay'];
    int? bestPurchaseDay;
    if (rawBest is num && rawBest >= 1 && rawBest <= 31) bestPurchaseDay = rawBest.toInt();
    return FinanceAccount(
      id: doc.id,
      presetId: (d['presetId'] ?? 'outro_banco').toString(),
      productType: pt,
      nickname: (d['nickname'] as String?)?.trim(),
      sortOrder: (d['sortOrder'] is num) ? (d['sortOrder'] as num).toInt() : 0,
      createdAt: created is Timestamp ? created.toDate() : null,
      statementClosingDay: statementClosingDay,
      cardColorId: cardColorId,
      // Só conta integrada tem saldo do banco: numa conta manual o campo
      // `balance` não existe, e um zero ali apagaria o saldo calculado.
      bankBalance: ext.isNotEmpty && rawBalance is num
          ? rawBalance.toDouble()
          : null,
      bankBalanceAt: updated is Timestamp ? updated.toDate() : null,
      cardBillBalance: ext.isNotEmpty && rawCardBill is num
          ? rawCardBill.toDouble()
          : null,
      faturaAtualBanco: ext.isNotEmpty && d['faturaAtualBanco'] is num
          ? (d['faturaAtualBanco'] as num).toDouble()
          : null,
      faturaAtualRef: ext.isNotEmpty && RegExp(r'^\d{4}-\d{2}$').hasMatch('${d['faturaAtualRef'] ?? ''}')
          ? '${d['faturaAtualRef']}'
          : null,
      limiteTotal: d['limiteTotal'] is num ? (d['limiteTotal'] as num).toDouble() : null,
      limiteUsado: d['limiteUsado'] is num ? (d['limiteUsado'] as num).toDouble() : null,
      limiteDisponivel: d['limiteDisponivel'] is num ? (d['limiteDisponivel'] as num).toDouble() : null,
      cicloInferidoDoBanco: d['cicloInferidoDoBanco'] == true,
      bankBranchCode: txt('bankBranchCode'),
      bankAccountNumber: txt('bankAccountNumber'),
      bankAccountCheckDigit: txt('bankAccountCheckDigit'),
      bankAccountType: txt('bankAccountType'),
      bankCompeCode: txt('bankCompeCode'),
      bankOperationCode: txt('bankOperationCode'),
      pixKey: txt('pixKey'),
      pixKeys: d['pixKeys'] is List
          ? (d['pixKeys'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
      bankCardNumber: txt('bankCardNumber'),
      cardDueDay: cardDueDay,
      bestPurchaseDay: bestPurchaseDay,
      holderDocument: txt('holderDocument'),
      holderName: txt('holderName'),
      externalResourceId: ext,
      consentId: (d['consentId'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'presetId': presetId,
      'productType': productType,
      'kind': kind,
      if (nickname != null && nickname!.trim().isNotEmpty) 'nickname': nickname!.trim(),
      'sortOrder': sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
      if (statementClosingDay != null) 'statementClosingDay': statementClosingDay,
      if (cardDueDay != null) 'cardDueDay': cardDueDay,
      if (bestPurchaseDay != null) 'bestPurchaseDay': bestPurchaseDay,
      if (cardColorId != null && cardColorId!.isNotEmpty) 'cardColorId': cardColorId,
      if (holderDocument != null && holderDocument!.isNotEmpty) 'holderDocument': holderDocument,
      if (holderName != null && holderName!.trim().isNotEmpty) 'holderName': holderName!.trim(),
      if (bankBranchCode != null && bankBranchCode!.isNotEmpty) 'bankBranchCode': bankBranchCode,
      if (bankAccountNumber != null && bankAccountNumber!.isNotEmpty) 'bankAccountNumber': bankAccountNumber,
      if (bankOperationCode != null && bankOperationCode!.isNotEmpty) 'bankOperationCode': bankOperationCode,
      if (pixKey != null && pixKey!.isNotEmpty) 'pixKey': pixKey,
      if (chavesPix.isNotEmpty) 'pixKeys': chavesPix,
      if (bankCardNumber != null && bankCardNumber!.isNotEmpty) 'bankCardNumber': bankCardNumber,
    };
  }
}
