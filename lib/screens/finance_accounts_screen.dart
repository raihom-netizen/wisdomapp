import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme_context.dart';
import '../widgets/fast_text_field.dart';
import 'package:intl/intl.dart';
import '../constants/finance_bank_presets.dart';
import '../constants/finance_account_card_colors.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import '../services/finance_pix_service.dart';
import '../theme/app_colors.dart';
import '../widgets/modern_module_ui.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import '../widgets/finance_delete_account_dialog.dart';
import '../widgets/navy_back_app_bar.dart';

/// Aviso de lançamentos presos a bancos já excluídos, com limpeza confirmada.
///
/// Só aparece quando o resumo mensal mostra saldo de conta que não existe mais.
/// No toque o servidor conta de verdade, a pessoa vê quantos e quanto somam e
/// só então confirma — a remoção é permanente.
class FinanceAccountsScreen extends StatelessWidget {
  final String uid;
  final UserProfile profile;

  const FinanceAccountsScreen({
    super.key,
    required this.uid,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        title: Text('Bancos e cartões', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
        backgroundColor: kAppNavyBar,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 118,
        leading: const NavyBackButton(),
        actions: [
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
      body: StreamBuilder<List<FinanceAccount>>(
        stream: FinanceAccountsService().streamAccounts(uid),
        builder: (context, snap) {
          final list = snap.data ?? [];
          // Tudo numa rolagem só. Antes o topo (explicação + Pro Finance +
          // bancos excluídos) era fixo e só a lista rolava: em tela de celular
          // o cabeçalho comia quase toda a altura e as contas ficavam
          // espremidas atrás dele — era o «está tampando a tela dos bancos».
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: context.isDarkMode
                        ? context.appPanelDecoration(
                            radius: 18,
                            borderAccent: AppColors.primary,
                          )
                        : BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.12),
                                const Color(0xFFE0F2FE),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.tips_and_updates_rounded,
                            color: AppColors.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Escolha o tipo, a instituição, a cor do card no Financeiro e um apelido. '
                            'A prévia mostra como ficará na faixa de contas. Toque no card para editar; '
                            'arraste ≡ para reordenar.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text('Suas contas (${list.length})',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: context.isDarkMode
                                  ? AppColors.accent
                                  : AppColors.primary)),
                      const Spacer(),
                      if (list.isNotEmpty && profile.hasActiveLicense)
                        Text('arraste ≡ para reordenar',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.appTextMuted,
                            )),
                    ],
                  ),
                ),
              ),
              if (list.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                          Card(
                            elevation: 0,
                            color: ModernModuleUI.cardBg(context),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: context.isDarkMode
                                    ? AppColors.primary.withValues(alpha: 0.28)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Nenhuma conta cadastrada. Toque no botão + para adicionar.',
                                style: TextStyle(
                                  color: context.appTextSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                    ]),
                  ),
                )
              else if (profile.hasActiveLicense)
                // `SliverReorderableList` (e não `ReorderableListView`) é o que
                // permite arrastar para reordenar DENTRO da mesma rolagem do
                // cabeçalho.
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverReorderableList(
                    itemCount: list.length,
                    // `onReorder` (e não o `onReorderItem` novo): o build do
                    // iOS/Android roda num Flutter que pode ser anterior ao
                    // que trouxe o substituto, e um aviso de depreciação custa
                    // menos que um build quebrado.
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex--;
                      final copy = List<FinanceAccount>.from(list);
                      final item = copy.removeAt(oldIndex);
                      copy.insert(newIndex, item);
                      await FinanceAccountsService()
                          .setAccountOrder(uid, copy.map((e) => e.id).toList());
                    },
                    itemBuilder: (context, i) {
                      final a = list[i];
                      return _AccountTile(
                        key: ValueKey(a.id),
                        index: i,
                        uid: uid,
                        account: a,
                        canEdit: profile.hasActiveLicense,
                      );
                    },
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final a = list[i];
                        return _AccountTile(
                          key: ValueKey(a.id),
                          index: null,
                          uid: uid,
                          account: a,
                          canEdit: false,
                        );
                      },
                      childCount: list.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: profile.hasActiveLicense
          ? FloatingActionButton.extended(
              onPressed: () => _AccountEditorSheet.open(context, uid: uid, account: null),
              icon: Icon(Icons.add_rounded),
              label: Text('Adicionar'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : FloatingActionButton.extended(
              onPressed: () => mostrarAvisoSeLicencaInativa(context, profile),
              icon: Icon(Icons.lock_outline_rounded),
              label: Text('Assine para cadastrar'),
            ),
    );
  }
}

/// Cadastro ou edição de conta — agora **tela full-screen** (em vez de bottom
/// sheet), para iOS/Android/Web instalável: o usuário vê todos os campos sem
/// precisar rolar metade da tela e o teclado não disputa espaço com a barra
/// inferior. Mantido o nome da classe (`_AccountEditorSheet`) para não tocar
/// nos call-sites; o que mudou foi apenas o transport (sheet → page).
class _AccountEditorSheet extends StatefulWidget {
  const _AccountEditorSheet({required this.uid, this.account});

  final String uid;
  final FinanceAccount? account;

  static Future<void> open(
    BuildContext context, {
    required String uid,
    FinanceAccount? account,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _AccountEditorSheet(uid: uid, account: account),
      ),
    );
  }

  @override
  State<_AccountEditorSheet> createState() => _AccountEditorSheetState();
}

class _AccountEditorSheetState extends State<_AccountEditorSheet> {
  late String _productType;
  late FinanceBankPreset? _selected;
  late final TextEditingController _nickCtrl;
  late final TextEditingController _holderDocCtrl;
  late final TextEditingController _holderNameCtrl;
  // Dados bancários digitados à mão — ficam prontos para quando a conta for
  // conectada ao Open Finance (o Finance Pro sobrescreve com o que vier do
  // banco de verdade; até lá, valem os que o usuário digitou aqui).
  late final TextEditingController _agenciaCtrl;
  late final TextEditingController _contaCtrl;
  late final TextEditingController _operacaoCtrl;
  late final TextEditingController _pixCtrl;

  /// Chaves Pix desta conta (a padrão do banco primeiro) e se esta conta dá
  /// o PIX PADRÃO do app (cobranças do Financeiro).
  List<String> _chavesPix = [];
  String _chavePadraoConta = '';
  bool _pixPadraoApp = false;
  bool _pixPadraoAppAntes = false;
  String? _erroPix;
  late final TextEditingController _numeroCartaoCtrl;
  late final TextEditingController _cardDueDayCtrl;

  /// Melhor dia de compra no cartão (vazio = dia seguinte ao fechamento).
  late final TextEditingController _melhorDiaCtrl;
  bool _defaultParaLancamentos = false;

  /// Conta padrão que estava valendo ao abrir a tela (null = nenhuma).
  String? _padraoAnteriorId;
  bool _trackStatementClosing = false;
  int _statementClosingDay = 10;
  bool _trackCardDueDay = false;
  int _cardDueDay = 10;
  String _cardColorId = kFinanceAccountCardColorAuto;

  bool get _isEdit => widget.account != null;

  bool get _isCardProduct =>
      _productType == FinanceAccount.kCard || _productType == FinanceAccount.kBankAndCard;

  /// Corrente, poupança ou "conta + cartão" — tem dados de conta pra pedir.
  bool get _isBankProduct =>
      _productType == FinanceAccount.kChecking ||
      _productType == FinanceAccount.kSavings ||
      _productType == FinanceAccount.kBankAndCard;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _productType = a != null
        ? a.productType
        : FinanceAccount.kChecking;
    _selected = a != null
        ? (financeBankPresetById(a.presetId) ?? kFinanceBankPresets.first)
        : kFinanceBankPresets.first;
    _nickCtrl = TextEditingController(text: a?.nickname ?? '');
    _holderDocCtrl = TextEditingController(text: a?.holderDocument ?? '');
    _holderNameCtrl = TextEditingController(text: a?.holderName ?? '');
    _agenciaCtrl = TextEditingController(text: a?.bankBranchCode ?? '');
    _contaCtrl = TextEditingController(text: a?.bankAccountNumber ?? '');
    _operacaoCtrl = TextEditingController(text: a?.bankOperationCode ?? '');
    _pixCtrl = TextEditingController();
    _chavesPix = List<String>.from(a?.chavesPix ?? const <String>[]);
    _chavePadraoConta = _chavesPix.isEmpty ? '' : _chavesPix.first;
    if (a != null) {
      FinancePixService.instance.pixPadrao(widget.uid).then((pp) {
        if (!mounted || pp == null || pp.contaId != a.id) return;
        setState(() {
          _pixPadraoApp = true;
          _pixPadraoAppAntes = true;
          if (_chavesPix.contains(pp.chave)) _chavePadraoConta = pp.chave;
        });
      }).catchError((_) {});
    }
    _numeroCartaoCtrl = TextEditingController(text: a?.bankCardNumber ?? '');
    _cardColorId = financeAccountCardColorIdForUi(a?.cardColorId);
    if (a != null) {
      final sc = a.statementClosingDay;
      _trackStatementClosing = sc != null;
      if (sc != null && sc >= 1 && sc <= 31) {
        _statementClosingDay = sc;
      }
      final dv = a.cardDueDay;
      _trackCardDueDay = dv != null;
      if (dv != null && dv >= 1 && dv <= 31) {
        _cardDueDay = dv;
      }
    }
    _cardDueDayCtrl = TextEditingController(text: _cardDueDay.toString());
    _melhorDiaCtrl = TextEditingController(text: a?.bestPurchaseDay?.toString() ?? '');
    // A conta padrão de antes é o que permite oferecer a migração dos
    // pendentes quando o padrão muda de banco.
    FinanceAdvancedSettingsService()
        .getDefaultFinanceAccountId(widget.uid)
        .then((id) {
      if (!mounted) return;
      setState(() {
        _padraoAnteriorId = id;
        if (_isEdit && a != null) _defaultParaLancamentos = id == a.id;
      });
    });
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _holderDocCtrl.dispose();
    _holderNameCtrl.dispose();
    _agenciaCtrl.dispose();
    _contaCtrl.dispose();
    _operacaoCtrl.dispose();
    _pixCtrl.dispose();
    _numeroCartaoCtrl.dispose();
    _cardDueDayCtrl.dispose();
    _melhorDiaCtrl.dispose();
    super.dispose();
  }

  FinanceAccount _draftAccount() {
    final nick = _nickCtrl.text.trim();
    return FinanceAccount(
      id: widget.account?.id ?? 'preview',
      presetId: _selected?.id ?? 'outro_banco',
      productType: _productType,
      nickname: nick.isEmpty ? null : nick,
      cardColorId: financeAccountCardColorIdForSave(_cardColorId),
      statementClosingDay: _isCardProduct && _trackStatementClosing ? _statementClosingDay : null,
    );
  }

  /// Pergunta se as contas a pagar do banco antigo passam para o novo.
  ///
  /// Retorna quantos lançamentos foram movidos (0 se o usuário recusar ou não
  /// houver pendentes).
  Future<int> _ofertarMigrarPendentes(String deId, String paraId) async {
    final svc = FinanceAccountsService();
    final quantos = await svc.countPendingTransactions(widget.uid, deId);
    if (quantos == 0 || !mounted) return 0;

    final contas = await svc.listOnce(widget.uid);
    String nome(String id) {
      for (final c in contas) {
        if (c.id == id) return c.displayName;
      }
      return 'conta';
    }

    if (!mounted) return 0;
    final mover = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar as pendentes de banco?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Você tem $quantos lançamento(s) pendente(s) em ${nome(deId)}. '
              'Quer que passem a sair de ${nome(paraId)}?',
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 10),
            Text(
              'Os já pagos não mudam — para mover valor entre bancos, use '
              'Transferência.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: ctx.appTextSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Manter como está'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Mover $quantos'),
          ),
        ],
      ),
    );
    if (mover != true) return 0;

    return svc.movePendingTransactions(
      uid: widget.uid,
      fromAccountId: deId,
      toAccountId: paraId,
    );
  }

  Future<void> _save() async {
    if (_selected == null) return;
    // Chave digitada e não adicionada: entra na lista (é o que o usuário quis).
    if (_pixCtrl.text.trim().isNotEmpty && !_adicionarChavePix()) return;
    final nick = _nickCtrl.text.trim();
    try {
      late final String savedAccountId;
      final statementClosing = _isCardProduct && _trackStatementClosing ? _statementClosingDay : null;
      final cardDueDay = _isCardProduct && _trackCardDueDay ? _cardDueDay : null;
      final cardColorId = financeAccountCardColorIdForSave(_cardColorId);
      // Conta já ligada ao banco: quem manda nesses campos é a sincronização,
      // não reenvia o que está no formulário (evita sobrescrever com um valor
      // desatualizado se um sync rodou com a tela já aberta).
      final jaLigada = widget.account?.isOpenFinanceLinked ?? false;
      if (_isEdit) {
        savedAccountId = widget.account!.id;
        await FinanceAccountsService().updateAccount(
          uid: widget.uid,
          accountId: savedAccountId,
          presetId: _selected!.id,
          productType: _productType,
          nickname: nick.isEmpty ? null : nick,
          statementClosingDay: statementClosing,
          cardColorId: cardColorId,
          holderDocument: _holderDocCtrl.text,
          holderName: _holderNameCtrl.text,
          bankBranchCode: _agenciaCtrl.text,
          bankAccountNumber: _contaCtrl.text,
          bankOperationCode: _operacaoCtrl.text,
          pixKey: _chavePadraoConta,
          pixKeys: _chavesPix,
          bankCardNumber: _numeroCartaoCtrl.text,
          cardDueDay: cardDueDay,
          bestPurchaseDay: _isCardProduct ? int.tryParse(_melhorDiaCtrl.text.trim()) : null,
          touchBankManualFields: !jaLigada,
        );
      } else {
        savedAccountId = await FinanceAccountsService().addAccount(
          uid: widget.uid,
          presetId: _selected!.id,
          productType: _productType,
          nickname: nick.isEmpty ? null : nick,
          statementClosingDay: statementClosing,
          cardColorId: cardColorId,
          holderDocument: _holderDocCtrl.text,
          holderName: _holderNameCtrl.text,
          bankBranchCode: _agenciaCtrl.text,
          bankAccountNumber: _contaCtrl.text,
          bankOperationCode: _operacaoCtrl.text,
          pixKey: _chavePadraoConta,
          pixKeys: _chavesPix,
          bankCardNumber: _numeroCartaoCtrl.text,
          cardDueDay: cardDueDay,
          bestPurchaseDay: _isCardProduct ? int.tryParse(_melhorDiaCtrl.text.trim()) : null,
        );
      }
      // Pix padrão do app: liga nesta conta ou solta se era ela.
      if (_pixPadraoApp && _chavePadraoConta.isNotEmpty) {
        await FinancePixService.instance.definirPixPadrao(widget.uid, savedAccountId, _chavePadraoConta);
      } else if (_pixPadraoAppAntes) {
        await FinancePixService.instance.limparPixPadrao(widget.uid);
      }
      final prefs = FinanceAdvancedSettingsService();
      var movidos = 0;
      if (_defaultParaLancamentos) {
        final anterior = (_padraoAnteriorId ?? '').trim();
        await prefs.setDefaultFinanceAccountId(widget.uid, savedAccountId);
        // Mudou o banco padrão: as contas a pagar ainda apontam para o banco
        // antigo. Perguntamos porque só o usuário sabe se elas vão debitar no
        // banco novo — e as já pagas nunca mudam, senão o extrato do banco que
        // pagou ficaria errado.
        if (anterior.isNotEmpty && anterior != savedAccountId && mounted) {
          movidos = await _ofertarMigrarPendentes(anterior, savedAccountId);
        }
      } else if (_isEdit) {
        await prefs.clearDefaultFinanceAccountIfMatches(widget.uid, widget.account!.id);
      }
      if (mounted) {
        final sm = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        sm.showSnackBar(
          SnackBar(
            content: Text(
              movidos > 0
                  ? '${_isEdit ? 'Conta atualizada' : 'Conta salva'} · $movidos pendente(s) movido(s) para o banco novo.'
                  : (_isEdit ? 'Conta atualizada.' : 'Conta salva.'),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildTitularSection(BuildContext ctx) {
    final a = widget.account;
    final ligada = a?.isOpenFinanceLinked ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Titular e dados da conta'),
        SizedBox(height: 8),
        if (ligada) ...[
          _buildBankDetailsChips(a!),
          SizedBox(height: 10),
        ],
        FastTextField(
          controller: _holderNameCtrl,
          readOnly: ligada,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nome ou razão social do titular (opcional)',
            hintText: 'Ex.: Maria da Silva, ou Padaria Pão Quente Ltda',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            fillColor: ctx.appInputFill,
          ),
        ),
        SizedBox(height: 10),
        FastTextField(
          controller: _holderDocCtrl,
          readOnly: ligada,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(14),
          ],
          decoration: InputDecoration(
            labelText: 'CPF ou CNPJ do titular (opcional)',
            hintText: 'Só números',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            fillColor: ctx.appInputFill,
          ),
        ),
        // «Meu Pix» fica FORA do bloco de conta não conectada: agência e conta
        // vêm do banco quando há Open Finance, mas a chave Pix é do usuário.
        // Antes ela sumia justamente nas contas conectadas (o Nubank do
        // Raihom), e o «Receber via Pix» não tinha chave para gerar o QR.
        if (_isBankProduct) ...[
          SizedBox(height: 12),
          _campoMeuPix(ctx),
        ],
        if (!ligada) ...[
          if (_isBankProduct) ...[
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FastTextField(
                    controller: _agenciaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Agência',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      filled: true,
                      fillColor: ctx.appInputFill,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FastTextField(
                    controller: _contaCtrl,
                    decoration: InputDecoration(
                      labelText: 'Conta (com dígito)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      filled: true,
                      fillColor: ctx.appInputFill,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FastTextField(
                    controller: _operacaoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Operação (opcional)',
                      hintText: 'Ex.: 013 (Caixa)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      filled: true,
                      fillColor: ctx.appInputFill,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_isCardProduct) ...[
            SizedBox(height: 10),
            FastTextField(
              controller: _numeroCartaoCtrl,
              decoration: InputDecoration(
                labelText: 'Número do cartão (opcional)',
                hintText: 'Ex.: **** **** **** 1234',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: ctx.appInputFill,
              ),
            ),
            SizedBox(height: 10),
            _buildCardDueDayField(ctx),
          ],
        ],
        // Fica fora do bloco de conta manual: vale também para cartão
        // conectado ao banco (o Open Finance não informa esse dia).
        if (_isCardProduct) ...[
          SizedBox(height: 10),
          _campoMelhorDiaCompra(ctx),
        ],
        SizedBox(height: 16),
      ],
    );
  }

  /// Dia de vencimento da fatura (quando ela é paga) — diferente do
  /// fechamento, que é quando ela para de somar compras novas.
  /// «Meu Pix»: a chave com que o app gera o QR e o link de pagamento no
  /// «Receber Pix»/«Gerar Pix» do Financeiro.
  Widget _campoMeuPix(BuildContext ctx) {
    const verde = Color(0xFF0D9488);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: verde.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: verde.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: verde, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.pix_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Meu Pix',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: ctx.appTextPrimary)),
                Text('Para receber: gera o QR Code e o copia e cola no Financeiro (Gerar Pix / Receber Pix).',
                    style: TextStyle(fontSize: 12, color: ctx.appTextSecondary)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          for (final k in _chavesPix) _linhaChavePix(ctx, k, verde),
          Row(children: [
            Expanded(
              child: FastTextField(
                controller: _pixCtrl,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => setState(() => _adicionarChavePix()),
                decoration: InputDecoration(
                  labelText: _chavesPix.isEmpty ? 'Minha chave PIX (para receber)' : 'Adicionar outra chave',
                  hintText: 'CPF, CNPJ, celular, e-mail ou aleatória',
                  errorText: _erroPix,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: ctx.appInputFill,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: verde,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              ),
              onPressed: () => setState(() => _adicionarChavePix()),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Adicionar'),
            ),
          ]),
          if (_chavesPix.isNotEmpty) ...[
            const SizedBox(height: 8),
            Material(
              color: _pixPadraoApp ? verde.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: SwitchListTile.adaptive(
                dense: true,
                value: _pixPadraoApp,
                activeThumbColor: verde,
                onChanged: (v) => setState(() => _pixPadraoApp = v),
                title: const Text('Pix padrão do app', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(
                  _pixPadraoApp
                      ? 'Sai sozinho nas cobranças: ${FinancePixService.tipoDaChave(_chavePadraoConta)} $_chavePadraoConta'
                      : 'Ligue para este banco e a chave com ★ saírem sozinhas nas cobranças do Financeiro.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Valida e põe a chave digitada na lista. Devolve false se for inválida.
  bool _adicionarChavePix() {
    final k = _pixCtrl.text.trim();
    if (k.isEmpty) return true;
    if (!FinancePixService.chaveValida(k)) {
      _erroPix = 'Chave inválida: use CPF, CNPJ, celular, e-mail ou chave aleatória.';
      if (mounted) setState(() {});
      return false;
    }
    _erroPix = null;
    if (!_chavesPix.contains(k)) _chavesPix.add(k);
    if (_chavePadraoConta.isEmpty) _chavePadraoConta = k;
    _pixCtrl.clear();
    return true;
  }

  Widget _linhaChavePix(BuildContext ctx, String k, Color verde) {
    final padrao = k == _chavePadraoConta;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: padrao ? verde.withValues(alpha: 0.14) : ctx.appSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: padrao ? verde : ctx.appBorderSubtle, width: padrao ? 1.6 : 1),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: verde.withValues(alpha: padrao ? 1 : 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(FinancePixService.tipoDaChave(k),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: padrao ? Colors.white : verde)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, color: ctx.appTextPrimary)),
            if (padrao)
              Text('Padrão deste banco', style: TextStyle(fontSize: 11, color: verde, fontWeight: FontWeight.w700)),
          ]),
        ),
        IconButton(
          tooltip: padrao ? 'Chave padrão deste banco' : 'Tornar padrão deste banco',
          icon: Icon(padrao ? Icons.star_rounded : Icons.star_border_rounded,
              color: padrao ? const Color(0xFFF59E0B) : ctx.appTextMuted),
          onPressed: () => setState(() => _chavePadraoConta = k),
        ),
        IconButton(
          tooltip: 'Remover chave',
          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
          onPressed: () => setState(() {
            _chavesPix.remove(k);
            if (padrao) _chavePadraoConta = _chavesPix.isEmpty ? '' : _chavesPix.first;
            if (_chavesPix.isEmpty) _pixPadraoApp = false;
          }),
        ),
      ]),
    );
  }

  /// «Melhor dia de compra»: aparece no card do cartão junto do fechamento.
  Widget _campoMelhorDiaCompra(BuildContext ctx) {
    const ambar = Color(0xFFD97706);
    final sugestao = _trackStatementClosing ? (_statementClosingDay >= 31 ? 1 : _statementClosingDay + 1) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: ambar.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ambar.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: ambar, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Melhor dia de compra',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: ctx.appTextPrimary)),
              Text('Comprando a partir deste dia a compra cai na próxima fatura (mais prazo).',
                  style: TextStyle(fontSize: 12, color: ctx.appTextSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(
            width: 110,
            child: FastTextField(
              controller: _melhorDiaCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              decoration: InputDecoration(
                labelText: 'Dia',
                hintText: sugestao?.toString() ?? '1–31',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: ctx.appInputFill,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (sugestao != null)
            Flexible(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: ambar, side: const BorderSide(color: ambar)),
                onPressed: () => setState(() => _melhorDiaCtrl.text = '$sugestao'),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text('Usar dia $sugestao (após o fechamento)', overflow: TextOverflow.ellipsis),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _buildCardDueDayField(BuildContext ctx) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: SwitchListTile.adaptive(
        value: _trackCardDueDay,
        onChanged: (v) => setState(() => _trackCardDueDay = v),
        activeThumbColor: AppColors.primary,
        title: Text('Vencimento da fatura', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        subtitle: _trackCardDueDay
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final dia in [5, 10, 15, 20, 25])
                      ChoiceChip(
                        label: Text('Dia $dia'),
                        selected: _cardDueDay == dia,
                        onSelected: (_) => setState(() {
                          _cardDueDay = dia;
                          _cardDueDayCtrl.text = dia.toString();
                        }),
                      ),
                    SizedBox(
                      width: 84,
                      child: FastTextField(
                        controller: _cardDueDayCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n >= 1 && n <= 31) setState(() => _cardDueDay = n);
                        },
                        decoration: InputDecoration(
                          labelText: 'Outro dia',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Text('Ative para eu lembrar quando a fatura vence.', style: TextStyle(fontSize: 12.5)),
        secondary: Icon(Icons.event_available_rounded, color: AppColors.primary.withValues(alpha: 0.9)),
      ),
    );
  }

  Widget _buildBankDetailsChips(FinanceAccount a) {
    final chips = <String>[
      if (a.bankAccountTypeLabel != null) a.bankAccountTypeLabel!,
      if ((a.bankBranchCode ?? '').isNotEmpty) 'Agência ${a.bankBranchCode}',
      if ((a.bankAccountNumber ?? '').isNotEmpty)
        'Conta ${a.bankAccountNumber}${(a.bankAccountCheckDigit ?? '').isNotEmpty ? '-${a.bankAccountCheckDigit}' : ''}',
      if ((a.bankOperationCode ?? '').isNotEmpty) 'Operação ${a.bankOperationCode}',
      if ((a.bankCardNumber ?? '').isNotEmpty) 'Cartão ${a.bankCardNumber}',
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final texto in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
            ),
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final safeBottom = MediaQuery.paddingOf(ctx).bottom;
    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Editar conta' : 'Nova conta',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.deepBlue.withValues(alpha: 0.92),
                AppColors.primary.withValues(alpha: 0.88),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Fechar',
          icon: Icon(Icons.close_rounded),
          onPressed: () => Navigator.maybePop(ctx),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      // Footer fixo (Cancelar / Salvar) — visível sempre, separado do scroll.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: context.appScaffold,
            border: Border(
              top: BorderSide(
                color: context.isDarkMode
                    ? AppColors.primary.withValues(alpha: 0.22)
                    : Colors.grey.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.maybePop(ctx),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: context.appTextPrimary,
                    side: BorderSide(
                      color: context.isDarkMode
                          ? AppColors.primary.withValues(alpha: 0.45)
                          : Colors.grey.shade400,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _selected == null ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: Icon(_isEdit ? Icons.save_rounded : Icons.add_rounded),
                  label: Text(
                    _isEdit ? 'Salvar alterações' : 'Criar conta',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + safeBottom),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _buildLivePreviewCard(),
            SizedBox(height: 18),
            _sectionTitle('Tipo de produto'),
            SizedBox(height: 8),
            // Duas opções: BANCO (conta) ou CARTÃO — cada um vira o seu card
            // no Financeiro. No cartão aparecem fechamento, vencimento e melhor
            // dia de compra (pedido de 21/09/2026).
            Row(
              children: [
                Expanded(
                  child: _typeOption(
                    FinanceAccount.kChecking,
                    'Banco',
                    'Conta corrente ou poupança',
                    Icons.account_balance_rounded,
                    selecionado: _productType == FinanceAccount.kChecking ||
                        _productType == FinanceAccount.kSavings,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _typeOption(FinanceAccount.kCard, 'Cartão', 'Cartão de crédito', Icons.credit_card_rounded),
                ),
              ],
            ),
            if (_productType == FinanceAccount.kChecking || _productType == FinanceAccount.kSavings) ...[
              SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: const Text('Conta corrente'),
                  selected: _productType == FinanceAccount.kChecking,
                  onSelected: (_) => setState(() => _productType = FinanceAccount.kChecking),
                ),
                ChoiceChip(
                  label: const Text('Poupança'),
                  selected: _productType == FinanceAccount.kSavings,
                  onSelected: (_) => setState(() => _productType = FinanceAccount.kSavings),
                ),
              ]),
            ],
            // «Conta + cartão» só para quem JÁ tem uma assim (no Financeiro ela
            // aparece como dois cards: conta e fatura).
            if (widget.account?.productType == FinanceAccount.kBankAndCard) ...[
              SizedBox(height: 8),
              _typeOption(
                FinanceAccount.kBankAndCard,
                'Conta + cartão',
                'Mesma instituição, conta e cartão',
                Icons.credit_score_outlined,
              ),
            ],
            SizedBox(height: 14),
            _sectionTitle('Instituição'),
            SizedBox(height: 6),
            _buildBankSelectorButton(ctx),
            SizedBox(height: 16),
            _buildCardColorSection(),
            SizedBox(height: 16),
            _buildTitularSection(ctx),
            _sectionTitle('Apelido'),
            SizedBox(height: 8),
            FastTextField(
              controller: _nickCtrl,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nome curto (opcional)',
                hintText: 'Ex.: Nubank tudo, Conta mãe',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: context.appInputFill,
              ),
            ),
            SizedBox(height: 16),
            _sectionTitle('Preferências'),
            SizedBox(height: 8),
            if (_isCardProduct) ...[
              _buildPremiumStatementClosingCard(),
              SizedBox(height: 12),
            ],
            Material(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              child: SwitchListTile.adaptive(
                value: _defaultParaLancamentos,
                onChanged: (v) => setState(() => _defaultParaLancamentos = v),
                activeThumbColor: AppColors.primary,
                title: Text(
                  'Conta principal nos lançamentos',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                subtitle: Text(
                  'Novas despesas e receitas abrem já com esta conta selecionada.',
                  style: TextStyle(fontSize: 13, height: 1.3),
                ),
                secondary: Icon(Icons.star_rounded, color: AppColors.primary.withValues(alpha: 0.9)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
        color: context.appTextSecondary,
      ),
    );
  }

  Widget _buildLivePreviewCard() {
    final draft = _draftAccount();
    final vis = financeAccountVisualFor(draft);
    final p = draft.preset;
    final title = draft.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prévia no Financeiro',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: context.appTextMuted,
            letterSpacing: 0.3,
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: Container(
            width: 168,
            height: 112,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: vis.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white24, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: vis.gradient.first.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (vis.isCreditCardStyle) const FinanceCreditCardPattern(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: FinanceBankBrandThumb(
                            preset: p,
                            size: 26,
                            onBrandGradient: true,
                            fallbackIcon: vis.icon,
                          ),
                        ),
                        const Spacer(),
                        if (vis.badgeLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: vis.badgeColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              vis.badgeLabel,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: vis.badgeTextColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      draft.productTypeLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardColorSection() {
    final bankGrad = _selected == null
        ? const [Color(0xFF64748B), Color(0xFF475569)]
        : [_selected!.color1, _selected!.color2];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.isDarkMode
          ? context.appPanelDecoration(radius: 18, borderAccent: AppColors.primary)
          : BoxDecoration(
        color: ModernModuleUI.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cor do card',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'Como aparece na faixa de contas do Financeiro (corrente, poupança, cartão ou conta + cartão).',
            style: TextStyle(fontSize: 12, height: 1.35, color: context.appTextMuted),
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kFinanceAccountCardColors.length,
              separatorBuilder: (_, __) => SizedBox(width: 10),
              itemBuilder: (_, i) {
                final c = kFinanceAccountCardColors[i];
                final sel = _cardColorId == c.id;
                final grad = c.isAuto
                    ? bankGrad
                    : [c.color1!, c.color2!];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _cardColorId = c.id),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 72,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel
                              ? AppColors.primary
                              : (context.isDarkMode
                                  ? context.appTextMuted.withValues(alpha: 0.35)
                                  : const Color(0xFFE2E8F0)),
                          width: sel ? 2.2 : 1,
                        ),
                        color: sel ? AppColors.primary.withValues(alpha: 0.06) : context.appChipIdleBg,
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 34,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: LinearGradient(
                                colors: grad,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: grad.first.withValues(alpha: 0.28),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: c.isAuto
                                ? Icon(Icons.auto_awesome_rounded, color: Colors.white.withValues(alpha: 0.9), size: 16)
                                : null,
                          ),
                          const Spacer(),
                          Text(
                            c.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: sel
                                  ? AppColors.primary
                                  : context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Botão grande que mostra o banco atual e abre a tela full-screen
  /// de seleção (com pesquisa). Funciona igual em iOS, Android e Web.
  Widget _buildBankSelectorButton(BuildContext ctx) {
    final p = _selected;
    final hasSelection = p != null;
    final color1 = hasSelection ? p.color1 : const Color(0xFF64748B);
    final color2 = hasSelection ? p.color2 : const Color(0xFF475569);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final picked = await Navigator.of(ctx).push<FinanceBankPreset>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _BankPickerScreen(initialSelected: _selected),
            ),
          );
          if (picked != null && mounted) {
            setState(() => _selected = picked);
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: hasSelection
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color1, color2],
                  )
                : null,
            color: hasSelection ? null : context.appChipIdleBg,
            border: Border.all(
              color: hasSelection
                  ? Colors.transparent
                  : (context.isDarkMode ? context.appChipIdleBorder : Colors.grey.shade300),
              width: hasSelection ? 0 : 1,
            ),
            boxShadow: hasSelection
                ? [BoxShadow(color: color1.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: hasSelection
                    ? FinanceBankBrandThumb(
                        preset: p,
                        size: 44,
                        onBrandGradient: true,
                        fallbackIcon: p.icon,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: context.isDarkMode ? context.appSurfaceHigh : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.account_balance_rounded, color: context.appTextSecondary),
                      ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasSelection ? p.name : 'Selecionar instituição',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: hasSelection
                            ? Colors.white
                            : (context.isDarkMode ? context.appTextPrimary : const Color(0xFF1E293B)),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      hasSelection ? 'Toque para trocar de banco' : 'Toque para escolher o banco',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasSelection
                            ? Colors.white.withValues(alpha: 0.9)
                            : context.appTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: hasSelection
                    ? Colors.white
                    : (context.isDarkMode ? context.appTextMuted : Colors.grey.shade500),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumStatementClosingCard() {
    const ink = Color(0xFF0B1220);
    const edge = Color(0xFF1E293B);
    const gold = Color(0xFFE8C547);
    const goldDeep = Color(0xFFC9A227);
    final nextClose =
        _trackStatementClosing ? FinanceAccount.computeNextStatementClosing(_statementClosingDay) : null;
    final dateFmt = DateFormat('dd/MM/yyyy');

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ink,
              edge,
              const Color(0xFF0F2847),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: gold.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            width: 1.2,
            color: gold.withValues(alpha: 0.35),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -24,
              child: Icon(
                Icons.blur_on_rounded,
                size: 120,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [gold.withValues(alpha: 0.95), goldDeep],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: goldDeep.withValues(alpha: 0.45),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(Icons.calendar_month_rounded, color: Color(0xFF1A1408), size: 22),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fechamento da fatura',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: -0.2,
                                color: Colors.white.withValues(alpha: 0.98),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Registre o mesmo dia do app do banco e compare com as datas do WISDOMAPP.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _trackStatementClosing,
                    onChanged: (v) {
                      setState(() {
                        _trackStatementClosing = v;
                        if (v && (_statementClosingDay < 1 || _statementClosingDay > 31)) {
                          _statementClosingDay = 10;
                        }
                      });
                    },
                    activeThumbColor: gold,
                    activeTrackColor: gold.withValues(alpha: 0.45),
                    inactiveThumbColor: Colors.white54,
                    inactiveTrackColor: Colors.white24,
                    title: Text(
                      'Definir dia de fechamento',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    subtitle: Text(
                      'Opcional — ajuda a alinhar lembretes com o ciclo real do cartão.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    secondary: Icon(Icons.sync_alt_rounded, color: gold.withValues(alpha: 0.9), size: 22),
                  ),
                  if (_trackStatementClosing) ...[
                    SizedBox(height: 4),
                    Text(
                      'Dia do mês',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        itemCount: 31,
                        separatorBuilder: (_, __) => SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final day = i + 1;
                          final sel = _statementClosingDay == day;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _statementClosingDay = day),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: sel
                                      ? LinearGradient(colors: [gold, goldDeep])
                                      : null,
                                  color: sel ? null : Colors.white.withValues(alpha: 0.08),
                                  border: Border.all(
                                    color: sel ? Colors.transparent : Colors.white.withValues(alpha: 0.14),
                                  ),
                                  boxShadow: sel
                                      ? [
                                          BoxShadow(
                                            color: goldDeep.withValues(alpha: 0.5),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$day',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: sel ? const Color(0xFF1A1408) : Colors.white.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (nextClose != null) ...[
                      SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_available_rounded, color: gold.withValues(alpha: 0.95), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Próximo fechamento (referência)',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                      color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    dateFmt.format(nextClose),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                      color: Colors.white.withValues(alpha: 0.98),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.verified_outlined, color: gold.withValues(alpha: 0.65), size: 22),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeOption(
    String value,
    String title,
    String subtitle,
    IconData icon, {
    bool? selecionado,
  }) {
    final sel = selecionado ?? _productType == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _productType = value),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: sel ? AppColors.primary.withValues(alpha: 0.1) : context.appInputFill,
            border: Border.all(
              color: sel
                  ? AppColors.primary
                  : (context.isDarkMode
                      ? context.appTextMuted.withValues(alpha: 0.28)
                      : Colors.transparent),
              width: sel ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: sel ? AppColors.primary : const Color(0xFF64748B)),
              SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: sel
                            ? AppColors.primary
                            : context.appTextPrimary,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final String uid;
  final FinanceAccount account;
  final bool canEdit;
  /// Índice na lista (só com licença + reorder); exibe alça de arrastar.
  final int? index;

  const _AccountTile({
    super.key,
    required this.uid,
    required this.account,
    required this.canEdit,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    final vis = financeAccountVisualFor(account);
    final p = account.preset;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: ModernModuleUI.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: context.isDarkMode
              ? AppColors.primary.withValues(alpha: 0.22)
              : Colors.grey.shade200,
        ),
      ),
      child: StreamBuilder<String?>(
        stream: FinanceAdvancedSettingsService().watchDefaultFinanceAccountId(uid),
        builder: (context, snap) {
          final defaultId = snap.data;
          final isPadrao = defaultId != null && defaultId == account.id;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
        onTap: canEdit ? () => _AccountEditorSheet.open(context, uid: uid, account: account) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: index != null
            ? ReorderableDragStartListener(
                index: index!,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: vis.gradient.length >= 2 ? vis.gradient.sublist(0, 2) : vis.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: vis.isCreditCardStyle
                        ? Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5), width: 1.2)
                        : null,
                    boxShadow: [BoxShadow(color: vis.gradient.first.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (vis.isCreditCardStyle) const FinanceCreditCardPattern(),
                      Center(
                        child: FinanceBankBrandThumb(
                          preset: p,
                          size: 34,
                          onBrandGradient: true,
                          fallbackIcon: vis.icon,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: vis.gradient.length >= 2 ? vis.gradient.sublist(0, 2) : vis.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: vis.isCreditCardStyle
                ? Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5), width: 1.2)
                : null,
            boxShadow: [BoxShadow(color: vis.gradient.first.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (vis.isCreditCardStyle) const FinanceCreditCardPattern(),
              Center(
                child: FinanceBankBrandThumb(
                  preset: p,
                  size: 34,
                  onBrandGradient: true,
                  fallbackIcon: vis.icon,
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                account.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: context.isDarkMode
                      ? context.appTextPrimary
                      : financeAccountListTitleColor(p),
                ),
              ),
            ),
            if (isPadrao)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.82)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Padrão',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${account.productTypeLabel} • ${p?.name ?? account.presetId}',
              style: TextStyle(fontSize: 12, color: context.appTextSecondary),
            ),
            if (account.isCardProduct && account.statementClosingDay != null) ...[
              SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.event_repeat_rounded, size: 14, color: AppColors.primary.withValues(alpha: 0.95)),
                  SizedBox(width: 5),
                  Text(
                    'Fatura fecha dia ${account.statementClosingDay}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: canEdit
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Editar conta',
                    icon: Icon(Icons.edit_outlined, color: AppColors.primary),
                    onPressed: () => _AccountEditorSheet.open(context, uid: uid, account: account),
                  ),
                  IconButton(
                tooltip: 'Excluir',
                icon: Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                onPressed: account.isVaultProduct
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'O Cofre pessoal é reserva separada e não pode ser excluído. '
                              'Você pode renomeá-lo na edição.',
                            ),
                          ),
                        );
                      }
                    : () => excluirContaFinanceiraComConfirmacao(context, uid: uid, account: account),
                  ),
                ],
              )
            : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Abre o editor para cadastrar um banco/cartão novo (usado pelo «Meu Pix»).
Future<void> abrirNovaContaFinanceira(BuildContext context, {required String uid}) =>
    _AccountEditorSheet.open(context, uid: uid, account: null);

/// Abre o editor completo do banco/cartão (mesma tela de «Cadastrar bancos»).
/// Usado também pelo lápis no card do Financeiro.
Future<void> abrirEditorContaFinanceira(BuildContext context, {required String uid, required FinanceAccount account}) =>
    _AccountEditorSheet.open(context, uid: uid, account: account);

/// Lixeira do banco/cartão: avisa quantos lançamentos serão removidos junto
/// (e se está conectado ao banco) e só apaga depois do «sim». Usado na lista
/// de contas e na lixeira do card do Financeiro — um fluxo só.
Future<bool> excluirContaFinanceiraComConfirmacao(BuildContext context,
    {required String uid, required FinanceAccount account}) async {
  if (account.isVaultProduct) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('O Cofre pessoal é reserva separada e não pode ser excluído. Você pode renomeá-lo na edição.'),
      ),
    );
    return false;
  }
  final service = FinanceAccountsService();
  final linked = await service.countLinkedTransactions(uid, account.id);
  final integrado = account.isOpenFinanceLinked;
  if (!context.mounted) return false;
  final ok = await showConfirmDeleteFinanceAccountDialog(
    context,
    account: account,
    linkedTransactionsCount: linked,
    openFinanceLinked: integrado,
  );
  if (ok != true || !context.mounted) return false;
  try {
    final removed = await service.deleteAccount(uid, account.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(removed > 0 ? 'Banco excluído e $removed lançamento(s) removido(s).' : 'Banco excluído.'),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
      );
    }
    return false;
  }
}

/// Tela full-screen de seleção de banco com campo de pesquisa.
///
/// Substitui o antigo grid compacto: lista vertical com logo grande + nome,
/// pesquisa em tempo real (filtra por nome ou iniciais).
/// Mesma experiência em iOS, Android e Web.
class _BankPickerScreen extends StatefulWidget {
  final FinanceBankPreset? initialSelected;

  const _BankPickerScreen({this.initialSelected});

  @override
  State<_BankPickerScreen> createState() => _BankPickerScreenState();
}

class _BankPickerScreenState extends State<_BankPickerScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Normaliza removendo acentos para a busca casar "itau" com "Itaú".
  String _norm(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    final buf = StringBuffer();
    for (final c in s.runes) {
      final ch = String.fromCharCode(c);
      final idx = from.indexOf(ch);
      buf.write(idx >= 0 ? to[idx] : ch);
    }
    return buf.toString().toLowerCase().trim();
  }

  /// Cadastra um banco/cartão que não está na lista fixa.
  ///
  /// Não cria coleção nova: o nome vira um `presetId` sintético (`custom:c:…`)
  /// que `financeBankPresetById` sabe reconstruir. Assim a lista de contas, o
  /// extrato, o PDF e a leitura do SMS do banco já entendem o cartão novo sem
  /// nenhuma mudança neles.
  Future<void> _cadastrarPersonalizado(BuildContext context) async {
    final nomeCtrl = TextEditingController(text: _query.trim());
    var cartao = true;

    final criado = await showDialog<FinanceBankPreset>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final nome = nomeCtrl.text.trim();
          final previa = nome.isEmpty
              ? null
              : financeBankPresetCustom(financePresetCustomId(nome, cartao: cartao));
          return AlertDialog(
            title: const Text('Novo banco ou cartão'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nomeCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 28,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    hintText: 'Ex.: Cartão do Posto, Banco da Firma',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.credit_card_rounded, size: 18),
                      label: Text('Cartão'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.account_balance_rounded, size: 18),
                      label: Text('Banco'),
                    ),
                  ],
                  selected: {cartao},
                  onSelectionChanged: (v) => setLocal(() => cartao = v.first),
                ),
                if (previa != null) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [previa.color1, previa.color2]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(previa.initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(previa.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('A cor sai do nome — este cartão vai ter sempre a mesma.',
                      style: TextStyle(fontSize: 11.5, color: ctx.appTextSecondary)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: previa == null ? null : () => Navigator.pop(ctx, previa),
                child: const Text('Usar este'),
              ),
            ],
          );
        },
      ),
    );

    nomeCtrl.dispose();
    if (criado != null && context.mounted) Navigator.of(context).pop(criado);
  }

  /// Filtro rápido da lista.
  ///
  /// «Cartões de loja» é o que tem nome começando em «Cartão » — os de varejo,
  /// posto e benefício. O resto é banco. Nubank e C6 ficam em bancos mesmo
  /// tendo cartão: é lá que a pessoa procura por eles.
  String _grupo = 'todos';

  static bool _ehCartaoDeLoja(FinanceBankPreset p) =>
      p.name.startsWith('Cartão ') || p.name.startsWith('Cartao ');

  /// Os que ficam no fim da lista: não são instituição, são saída de escape.
  static const _noFim = {'outro_banco', 'outro_cartao', 'cofre_pessoal'};

  List<FinanceBankPreset> get _filtered {
    final q = _norm(_query);
    final lista = kFinanceBankPresets.where((p) {
      if (q.isNotEmpty &&
          !_norm(p.name).contains(q) &&
          !_norm(p.initials).contains(q)) {
        return false;
      }
      return switch (_grupo) {
        'cartoes' => _ehCartaoDeLoja(p),
        'bancos' => !_ehCartaoDeLoja(p) && !_noFim.contains(p.id),
        _ => true,
      };
    }).toList();

    // Ordem alfabética, com as saídas de escape sempre no fim — senão «Outro
    // banco» apareceria no meio do O e a pessoa não acharia quando precisasse.
    lista.sort((a, b) {
      final fimA = _noFim.contains(a.id);
      final fimB = _noFim.contains(b.id);
      if (fimA != fimB) return fimA ? 1 : -1;
      return _norm(a.name).compareTo(_norm(b.name));
    });
    return lista;
  }

  Widget _chipGrupo(BuildContext context, String id, String rotulo, IconData icone) {
    final ativo = _grupo == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: ativo ? AppColors.primary : context.appChipIdleBg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _grupo = id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icone, size: 16, color: ativo ? Colors.white : context.appTextSecondary),
              const SizedBox(width: 6),
              Text(rotulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: ativo ? Colors.white : context.appTextSecondary,
                  )),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        backgroundColor: kAppNavyBar,
        foregroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 118,
        leading: const NavyBackButton(),
        title: Text(
          'Selecionar instituição',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FastTextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Pesquisar banco (ex.: Nubank, Itaú, Caixa)',
                  prefixIcon: Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          icon: Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: context.appInputFill,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.isDarkMode ? context.appChipIdleBorder : Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.isDarkMode ? context.appChipIdleBorder : Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                children: [
                  _chipGrupo(context, 'todos', 'Todos', Icons.apps_rounded),
                  _chipGrupo(context, 'bancos', 'Bancos', Icons.account_balance_rounded),
                  _chipGrupo(context, 'cartoes', 'Cartões de loja', Icons.credit_card_rounded),
                ],
              ),
            ),
            // Nem todo cartão de loja cabe numa lista fixa. Aqui o usuário
            // cadastra o dele — mesma ideia das categorias personalizadas.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Material(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _cadastrarPersonalizado(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(children: [
                      const Icon(Icons.add_circle_rounded, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Cadastrar outro banco ou cartão',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: AppColors.primary)),
                            Text('Não está na lista? Crie com o nome que você usa.',
                                style: TextStyle(
                                    fontSize: 12, color: context.appTextSecondary)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: context.appTextMuted),
                    ]),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  filtered.isEmpty
                      ? 'Nenhum banco encontrado'
                      : '${filtered.length} ${filtered.length == 1 ? 'instituição' : 'instituições'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.appTextMuted,
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded,
                                size: 56,
                                color: context.isDarkMode ? context.appTextMuted : Colors.grey.shade400),
                            SizedBox(height: 12),
                            Text(
                              'Não encontramos esse banco.\nToque em «Cadastrar outro banco ou cartão» acima.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: context.appTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final sel = widget.initialSelected?.id == p.id;
                        return Material(
                          color: context.isDarkMode ? context.appSurface : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          elevation: 0,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(context).pop(p),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: sel
                                      ? AppColors.primary
                                      : (context.isDarkMode ? context.appChipIdleBorder : Colors.grey.shade200),
                                  width: sel ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: FinanceBankBrandThumb(
                                      preset: p,
                                      size: 44,
                                      onBrandGradient: false,
                                      fallbackIcon: p.icon,
                                    ),
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          p.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: context.isDarkMode
                                                ? context.appTextPrimary
                                                : const Color(0xFF1E293B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          p.initials,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.appTextMuted,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (sel)
                                    Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 26)
                                  else
                                    Icon(Icons.chevron_right_rounded,
                                        color: context.isDarkMode ? context.appTextMuted : Colors.grey.shade400,
                                        size: 24),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
