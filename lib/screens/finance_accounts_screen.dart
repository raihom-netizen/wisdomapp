import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:intl/intl.dart';
import '../constants/finance_bank_presets.dart';
import '../constants/finance_account_card_colors.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import '../theme/app_colors.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/finance_bank_brand_thumb.dart';

/// Cadastro de contas corrente, poupança e cartões.
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
      backgroundColor: const Color(0xFFF4FBF6),
      appBar: AppBar(
        title: const Text('Bancos e cartões', style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: StreamBuilder<List<FinanceAccount>>(
        stream: FinanceAccountsService().streamAccounts(uid),
        builder: (context, snap) {
          final list = snap.data ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary.withValues(alpha: 0.12), const Color(0xFFE0F2FE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: const Text(
                    'Escolha o tipo, a instituição, a cor do card no Financeiro e um apelido. A prévia mostra como ficará na faixa de contas. Toque no card para editar; arraste ≡ para reordenar.',
                    style: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Suas contas (${list.length})', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary)),
              ),
              Expanded(
                child: list.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        children: [
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('Nenhuma conta cadastrada. Toque no botão + para adicionar.'),
                            ),
                          ),
                        ],
                      )
                    : profile.hasActiveLicense
                        ? ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            buildDefaultDragHandles: false,
                            itemCount: list.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (newIndex > oldIndex) newIndex--;
                              final copy = List<FinanceAccount>.from(list);
                              final item = copy.removeAt(oldIndex);
                              copy.insert(newIndex, item);
                              await FinanceAccountsService().setAccountOrder(uid, copy.map((e) => e.id).toList());
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
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final a = list[i];
                              return _AccountTile(
                                key: ValueKey(a.id),
                                index: null,
                                uid: uid,
                                account: a,
                                canEdit: false,
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: profile.hasActiveLicense
          ? FloatingActionButton.extended(
              onPressed: () => _AccountEditorSheet.open(context, uid: uid, account: null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : FloatingActionButton.extended(
              onPressed: () => mostrarAvisoSeLicencaInativa(context, profile),
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('Assine para cadastrar'),
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
  bool _defaultParaLancamentos = false;
  bool _trackStatementClosing = false;
  int _statementClosingDay = 10;
  String _cardColorId = kFinanceAccountCardColorAuto;

  bool get _isEdit => widget.account != null;

  bool get _isCardProduct =>
      _productType == FinanceAccount.kCard || _productType == FinanceAccount.kBankAndCard;

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
    _cardColorId = financeAccountCardColorIdForUi(a?.cardColorId);
    if (a != null) {
      final sc = a.statementClosingDay;
      _trackStatementClosing = sc != null;
      if (sc != null && sc >= 1 && sc <= 31) {
        _statementClosingDay = sc;
      }
    }
    if (_isEdit && a != null) {
      FinanceAdvancedSettingsService().getDefaultFinanceAccountId(widget.uid).then((id) {
        if (!mounted) return;
        setState(() => _defaultParaLancamentos = id == a.id);
      });
    }
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
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

  Future<void> _save() async {
    if (_selected == null) return;
    final nick = _nickCtrl.text.trim();
    try {
      late final String savedAccountId;
      final statementClosing = _isCardProduct && _trackStatementClosing ? _statementClosingDay : null;
      final cardColorId = financeAccountCardColorIdForSave(_cardColorId);
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
        );
      } else {
        savedAccountId = await FinanceAccountsService().addAccount(
          uid: widget.uid,
          presetId: _selected!.id,
          productType: _productType,
          nickname: nick.isEmpty ? null : nick,
          statementClosingDay: statementClosing,
          cardColorId: cardColorId,
        );
      }
      final prefs = FinanceAdvancedSettingsService();
      if (_defaultParaLancamentos) {
        await prefs.setDefaultFinanceAccountId(widget.uid, savedAccountId);
      } else if (_isEdit) {
        await prefs.clearDefaultFinanceAccountIfMatches(widget.uid, widget.account!.id);
      }
      if (mounted) {
        final sm = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        sm.showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Conta atualizada.' : 'Conta salva.'),
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

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final safeBottom = MediaQuery.paddingOf(ctx).bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBF6),
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
          icon: const Icon(Icons.close_rounded),
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
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.maybePop(ctx),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
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
            const SizedBox(height: 18),
            _sectionTitle('Tipo de produto'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _typeOption(
                      FinanceAccount.kChecking, 'Corrente', 'Conta corrente', Icons.account_balance_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _typeOption(
                      FinanceAccount.kSavings, 'Poupança', 'Poupança', Icons.savings_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _typeOption(FinanceAccount.kCard, 'Cartão', 'Só cartão de crédito', Icons.credit_card_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _typeOption(
                    FinanceAccount.kBankAndCard,
                    'Conta + cartão',
                    'Mesma instituição, conta e cartão',
                    Icons.credit_score_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _sectionTitle('Instituição'),
            const SizedBox(height: 6),
            _buildBankSelectorButton(ctx),
            const SizedBox(height: 16),
            _buildCardColorSection(),
            const SizedBox(height: 16),
            _sectionTitle('Apelido'),
            const SizedBox(height: 8),
            FastTextField(
              controller: _nickCtrl,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nome curto (opcional)',
                hintText: 'Ex.: Nubank tudo, Conta mãe',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Preferências'),
            const SizedBox(height: 8),
            if (_isCardProduct) ...[
              _buildPremiumStatementClosingCard(),
              const SizedBox(height: 12),
            ],
            Material(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              child: SwitchListTile.adaptive(
                value: _defaultParaLancamentos,
                onChanged: (v) => setState(() => _defaultParaLancamentos = v),
                activeThumbColor: AppColors.primary,
                title: const Text(
                  'Conta principal nos lançamentos',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                subtitle: const Text(
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
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
        color: AppColors.textSecondary,
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
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
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
                    const SizedBox(height: 2),
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
      decoration: BoxDecoration(
        color: Colors.white,
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
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Cor do card',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Como aparece na faixa de contas do Financeiro (corrente, poupança, cartão ou conta + cartão).',
            style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kFinanceAccountCardColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                          color: sel ? AppColors.primary : const Color(0xFFE2E8F0),
                          width: sel ? 2.2 : 1,
                        ),
                        color: sel ? AppColors.primary.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
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
                              color: sel ? AppColors.primary : AppColors.textSecondary,
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
            color: hasSelection ? null : const Color(0xFFF8FAFC),
            border: Border.all(
              color: hasSelection ? Colors.transparent : Colors.grey.shade300,
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
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.account_balance_rounded, color: Colors.grey.shade600),
                      ),
              ),
              const SizedBox(width: 12),
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
                        color: hasSelection ? Colors.white : const Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSelection ? 'Toque para trocar de banco' : 'Toque para escolher o banco',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasSelection
                            ? Colors.white.withValues(alpha: 0.9)
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: hasSelection ? Colors.white : Colors.grey.shade500,
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
                        child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF1A1408), size: 22),
                      ),
                      const SizedBox(width: 12),
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
                            const SizedBox(height: 4),
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
                  const SizedBox(height: 14),
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
                    const SizedBox(height: 4),
                    Text(
                      'Dia do mês',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        itemCount: 31,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
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
                      const SizedBox(height: 12),
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
                            const SizedBox(width: 10),
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
                                  const SizedBox(height: 2),
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
    IconData icon,
  ) {
    final sel = _productType == value;
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
            color: sel ? AppColors.primary.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
            border: Border.all(
              color: sel ? AppColors.primary : Colors.transparent,
              width: sel ? 2 : 0,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: sel ? AppColors.primary : const Color(0xFF64748B)),
              const SizedBox(width: 6),
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
                        color: sel ? AppColors.primary : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: StreamBuilder<String?>(
        stream: FinanceAdvancedSettingsService().watchDefaultFinanceAccountId(uid),
        builder: (context, snap) {
          final defaultId = snap.data;
          final isPadrao = defaultId != null && defaultId == account.id;
          return ListTile(
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
                style: TextStyle(fontWeight: FontWeight.w800, color: financeAccountListTitleColor(p)),
              ),
            ),
            if (isPadrao)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.82)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
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
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (account.isCardProduct && account.statementClosingDay != null) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.event_repeat_rounded, size: 14, color: AppColors.primary.withValues(alpha: 0.95)),
                  const SizedBox(width: 5),
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
                    icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                    onPressed: () => _AccountEditorSheet.open(context, uid: uid, account: account),
                  ),
                  IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Excluir conta?'),
                      content: const Text('Lançamentos antigos podem continuar com esta conta no histórico; novos não poderão usá-la.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                          child: const Text('Excluir'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      await FinanceAccountsService().deleteAccount(uid, account.id);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error));
                      }
                    }
                  }
                },
                  ),
                ],
              )
            : null,
          );
        },
      ),
    );
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

  List<FinanceBankPreset> get _filtered {
    if (_query.isEmpty) return kFinanceBankPresets;
    final q = _norm(_query);
    return kFinanceBankPresets
        .where((p) => _norm(p.name).contains(q) || _norm(p.initials).contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
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
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'Não encontramos esse banco.\nUse "Outro banco" ou "Outro cartão".',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final sel = widget.initialSelected?.id == p.id;
                        return Material(
                          color: Colors.white,
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
                                  color: sel ? AppColors.primary : Colors.grey.shade200,
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
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: Color(0xFF1E293B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          p.initials,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textMuted,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (sel)
                                    Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 26)
                                  else
                                    Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 24),
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
