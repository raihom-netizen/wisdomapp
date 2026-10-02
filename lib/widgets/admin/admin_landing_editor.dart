import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/landing_public_content.dart';
import '../../screens/landing_screen.dart';
import '../../screens/tela_divulgacao_page.dart';
import '../../services/mp_checkout_pricing_service.dart';
import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import '../fast_text_field.dart';
import 'admin_ui_kit.dart';

/// Editor do Admin «Landing / Divulgação».
///
/// - Abre com TODOS os campos preenchidos: valor salvo em `landing_content/main`
///   ou, se vazio, o texto padrão do código (`lib/constants/landing_defaults.dart`)
///   — a mesma fonte que a página pública usa.
/// - Preços em `app_config/mp_checkout_prices` (o mesmo doc que o checkout das
///   Cloud Functions, a escolha de plano e a landing leem).
/// - Barra fixa no rodapé: «Sincronizar» e «Salvar». Mudou aqui → site muda na
///   hora (as páginas escutam o Firestore), sem deploy.
class AdminLandingEditor extends StatefulWidget {
  const AdminLandingEditor({super.key, required this.uid});

  final String uid;

  @override
  State<AdminLandingEditor> createState() => _AdminLandingEditorState();
}

class _AdminLandingEditorState extends State<AdminLandingEditor> {
  final _landingDoc =
      FirebaseFirestore.instance.collection('landing_content').doc('main');
  final _pricesDoc = FirebaseFirestore.instance
      .collection('app_config')
      .doc('mp_checkout_prices');

  final Map<String, TextEditingController> _ctrls = {};
  final _premMCtrl = TextEditingController();
  final _premACtrl = TextEditingController();
  final _extraMCtrl = TextEditingController();
  final _extraACtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _googleAgendaEnabled = true;
  MpCheckoutPricingSnapshot _savedPrices = MpCheckoutPricingSnapshot.defaults();

  bool _loading = true;
  Object? _loadError;
  String? _pricesLoadWarning;
  bool _saving = false;
  bool _dirty = false;
  bool _filling = false;

  static const Map<String, IconData> _sectionIcons = {
    'home_top': Icons.download_rounded,
    'home_hero': Icons.auto_awesome_rounded,
    'home_login': Icons.login_rounded,
    'home_modules': Icons.view_module_rounded,
    'home_quote': Icons.format_quote_rounded,
    'home_plan': Icons.workspace_premium_rounded,
    'home_footer': Icons.vertical_align_bottom_rounded,
    'express': Icons.flash_on_rounded,
    'channels': Icons.hub_rounded,
    'promo': Icons.local_offer_rounded,
    'div_hero': Icons.campaign_rounded,
    'div_book': Icons.menu_book_rounded,
    'div_steps': Icons.format_list_numbered_rounded,
    'div_license': Icons.verified_user_rounded,
    'div_plans': Icons.sell_rounded,
    'div_footer': Icons.link_rounded,
    'config': Icons.palette_rounded,
    'unused': Icons.inventory_2_outlined,
  };

  @override
  void initState() {
    super.initState();
    _filling = true;
    for (final f in kLandingAllFieldsByKey.values) {
      final c = TextEditingController(text: f.defaultValue);
      c.addListener(_markDirty);
      _ctrls[f.key] = c;
    }
    for (final c in [_premMCtrl, _premACtrl, _extraMCtrl, _extraACtrl]) {
      c.addListener(_onPriceTyped);
    }
    _fillPrices(MpCheckoutPricingSnapshot.defaults());
    _refreshPriceDriven();
    _filling = false;
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _premMCtrl.dispose();
    _premACtrl.dispose();
    _extraMCtrl.dispose();
    _extraACtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_filling || _dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  void _onPriceTyped() {
    if (_filling || !mounted) return;
    _refreshPriceDriven();
    // Sempre redesenha: a dica «equivale a X/mês» e as prévias seguem o preço.
    setState(() => _dirty = true);
  }

  // ── Preços ──────────────────────────────────────────────────────────────

  static String _fmtMoney(double v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');

  static double? _parseMoney(TextEditingController c) {
    final raw =
        c.text.trim().replaceAll(RegExp(r'\s+'), '').replaceAll('R\$', '');
    // 1.234,56 → 1234.56 ; 49,90 → 49.90 ; 49.90 → 49.90
    final norm =
        raw.contains(',') ? raw.replaceAll('.', '').replaceAll(',', '.') : raw;
    final v = double.tryParse(norm);
    if (v == null || v <= 0) return null;
    return v;
  }

  void _fillPrices(MpCheckoutPricingSnapshot s) {
    final was = _filling;
    _filling = true;
    _premMCtrl.text = _fmtMoney(s.premiumMonthly);
    _premACtrl.text = _fmtMoney(s.premiumAnnual);
    _extraMCtrl.text = _fmtMoney(s.extraBankConnectionMonthly);
    _extraACtrl.text = _fmtMoney(s.extraBankConnectionAnnual);
    _filling = was;
  }

  /// Preços do formulário (null se algum estiver inválido).
  MpCheckoutPricingSnapshot? _formPrices() {
    final pm = _parseMoney(_premMCtrl);
    final pa = _parseMoney(_premACtrl);
    final em = _parseMoney(_extraMCtrl);
    final ea = _parseMoney(_extraACtrl);
    if (pm == null || pa == null || em == null || ea == null) return null;
    return MpCheckoutPricingSnapshot(
      premiumMonthly: pm,
      premiumAnnual: pa,
      // Premium PRO segue o Premium (mesma regra de antes no Admin).
      premiumProMonthly: pm,
      premiumProAnnual: pa,
      extraBankConnectionMonthly: em,
      extraBankConnectionAnnual: ea,
    );
  }

  MpCheckoutPricingSnapshot get _previewPrices => _formPrices() ?? _savedPrices;

  /// Linhas de valor que o site sempre calcula a partir dos preços.
  void _refreshPriceDriven() {
    final p = _previewPrices;
    final gen = {
      ...p.generatedPremiumLandingFields(),
      ...p.generatedPremiumProLandingFields(),
    };
    final was = _filling;
    _filling = true;
    for (final k in kLandingPriceDrivenKeys) {
      final v = gen[k];
      if (v != null) _ctrls[k]?.text = v;
    }
    _filling = was;
  }

  // ── Carregar ────────────────────────────────────────────────────────────

  static String _pick(Map<String, dynamic>? raw, String key, String def) {
    final v = raw?[key];
    if (v == null) return def;
    if (v is Iterable) {
      final j = v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
      return j.isEmpty ? def : j;
    }
    final t = v.toString().trim();
    return t.isEmpty ? def : t;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _pricesLoadWarning = null;
    });
    Map<String, dynamic>? data;
    try {
      final snap = await AdminLoadGuard.comPrazo(_landingDoc.get(),
          oQue: 'os textos da landing');
      data = snap.data();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
      });
      return;
    }
    MpCheckoutPricingSnapshot prices = MpCheckoutPricingSnapshot.defaults();
    String? warn;
    try {
      final ps = await AdminLoadGuard.comPrazo(_pricesDoc.get(),
          oQue: 'os preços do checkout');
      prices = MpCheckoutPricingSnapshot.fromFirestore(ps.data());
      if (!ps.exists) {
        warn =
            'app_config/mp_checkout_prices ainda não existe: mostrando os preços padrão do app. Salve para criar.';
      }
    } catch (e) {
      warn =
          'Não deu para ler os preços salvos (${AdminLoadGuard.mensagem(e)}). Mostrando os preços padrão do app.';
    }
    if (!mounted) return;
    _filling = true;
    for (final f in kLandingAllFieldsByKey.values) {
      if (kLandingPriceDrivenKeys.contains(f.key)) continue;
      var v = _pick(data, f.key, f.defaultValue);
      // Mesmo filtro da página: texto antigo do Controle Total não vale.
      if ((f.key == 'heroTitle' ||
              f.key == 'heroSubtitle' ||
              f.key == 'divHeroTitle' ||
              f.key == 'divHeroTagline') &&
          v.toLowerCase().contains('controle total')) {
        v = f.defaultValue;
      }
      _ctrls[f.key]!.text = v;
    }
    _googleAgendaEnabled = data?['googleAgendaEnabled'] != false;
    _savedPrices = prices;
    _fillPrices(prices);
    _refreshPriceDriven();
    _filling = false;
    setState(() {
      _loading = false;
      _dirty = false;
      _pricesLoadWarning = warn;
    });
  }

  // ── Salvar ──────────────────────────────────────────────────────────────

  List<String> _parseList(String raw) =>
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Map<String, dynamic> _landingPayload() {
    String txt(String k) => _ctrls[k]?.text.trim() ?? '';
    String orDefault(String k) {
      final v = txt(k);
      return v.isEmpty ? landingDefaultFor(k) : v;
    }

    final payload = <String, dynamic>{};
    for (final k in kLandingAllFieldsByKey.keys) {
      payload[k] = txt(k);
    }
    payload['heroBadges'] = _parseList(txt('heroBadges'));
    final premiumLine = [txt('divPremiumMensal'), txt('divPremiumAnual')]
        .where((s) => s.isNotEmpty)
        .join(' • ');
    payload['premiumPrice'] = premiumLine;
    payload['masterPrice'] = premiumLine;
    payload['premiumPerks'] = _parseList(txt('divPremiumBeneficios'));
    payload['masterPerks'] = _parseList(txt('divPremiumBeneficios'));
    for (final k in const [
      'googleAgendaButtonText',
      'googleAgendaConnectUrl',
      'googleAgendaHintText',
      'divThemePrimaryColor',
      'divThemeAccentColor',
    ]) {
      payload[k] = orDefault(k);
    }
    payload['googleAgendaEnabled'] = _googleAgendaEnabled;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    payload['updatedByUid'] = widget.uid;
    return payload;
  }

  Future<bool> _confirm(String title, String body, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        duration: Duration(seconds: error ? 8 : 4),
      ),
    );
  }

  Future<bool> _writePrices(MpCheckoutPricingSnapshot p) async {
    try {
      await AdminLoadGuard.comPrazo(
        _pricesDoc.set(
          {
            'premium_monthly': p.premiumMonthly,
            'premium_annual': p.premiumAnnual,
            'premium_pro_monthly': p.premiumMonthly,
            'premium_pro_annual': p.premiumAnnual,
            'extra_bank_connection_monthly': p.extraBankConnectionMonthly,
            'extra_bank_connection_annual': p.extraBankConnectionAnnual,
            'basic_monthly': FieldValue.delete(),
            'basic_annual': FieldValue.delete(),
            'master_monthly': FieldValue.delete(),
            'master_annual': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedByUid': widget.uid,
          },
          SetOptions(merge: true),
        ),
        oQue: 'os preços',
      );
      _savedPrices = p;
      return true;
    } catch (e) {
      _snack('Preços NÃO salvos: ${AdminLoadGuard.mensagem(e)}', error: true);
      return false;
    }
  }

  Future<bool> _writeTexts() async {
    try {
      await AdminLoadGuard.comPrazo(
        _landingDoc.set(_landingPayload(), SetOptions(merge: true)),
        oQue: 'os textos',
      );
    } catch (e) {
      _snack('Textos NÃO salvos: ${AdminLoadGuard.mensagem(e)}', error: true);
      return false;
    }
    final playUrl = _ctrls['divPlayStoreUrl']?.text.trim() ?? '';
    if (playUrl.startsWith('http://') || playUrl.startsWith('https://')) {
      try {
        await FirebaseFirestore.instance
            .collection('app_config')
            .doc('version')
            .set({
          'apkDownloadUrl': playUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Só o atalho de atualização do app; os textos já foram salvos.
      }
    }
    return true;
  }

  /// Grava preços + todos os textos. [ask] = mostra confirmação antes.
  Future<void> _saveAll({bool ask = true, String? doneMsg}) async {
    if (_saving) return;
    final p = _formPrices();
    if (p == null) {
      _snack(
          'Confira os preços: use números válidos maiores que zero (ex.: 49,90).',
          error: true);
      return;
    }
    if (ask &&
        !await _confirm(
          'Publicar no site?',
          'Os textos e preços passam a valer na hora na página inicial (/), '
              'na /divulgacao, na escolha de plano e no checkout (as Cloud '
              'Functions usam o preço novo em até ~1 minuto). Não precisa de deploy.',
          'Salvar e publicar',
        )) {
      return;
    }
    setState(() => _saving = true);
    final okPrices = await _writePrices(p);
    final okTexts = await _writeTexts();
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (okPrices && okTexts) _dirty = false;
    });
    if (okPrices && okTexts) {
      _snack(doneMsg ??
          'Salvo! O site já mostra os textos e preços novos (sem deploy).');
    }
  }

  Future<void> _savePricesOnly() async {
    final p = _formPrices();
    if (p == null) {
      _snack(
          'Confira os preços: use números válidos maiores que zero (ex.: 49,90).',
          error: true);
      return;
    }
    if (!await _confirm(
        'Salvar só os preços?',
        'Grava app_config/mp_checkout_prices (valor cobrado no checkout). '
            'As linhas de valor do site mudam junto; os demais textos só mudam '
            'se você tocar em «Sincronizar» ou «Salvar».',
        'Salvar preços')) {
      return;
    }
    setState(() => _saving = true);
    final ok = await _writePrices(p);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _snack(
          'Preços do checkout salvos. As Cloud Functions usam o valor novo em até ~1 minuto.');
    }
  }

  /// Troca nos textos os valores antigos (preço salvo) pelos novos e regera
  /// os parágrafos de preço; depois salva tudo.
  Future<void> _syncPricesIntoTexts() async {
    final next = _formPrices();
    if (next == null) {
      _snack(
          'Confira os preços: use números válidos maiores que zero (ex.: 49,90).',
          error: true);
      return;
    }
    if (!await _confirm(
      'Sincronizar preços nos textos?',
      'Os textos que citam o valor antigo passam a citar o valor novo, as '
          'linhas de preço são recalculadas e tudo é salvo (textos + preços).',
      'Sincronizar e salvar',
    )) {
      return;
    }
    final old = _savedPrices;
    final f = MpCheckoutPricingSnapshot.formatBrl;
    final pairs = <(String, String)>[
      (f(old.premiumMonthly), f(next.premiumMonthly)),
      (f(old.premiumAnnual), f(next.premiumAnnual)),
      (
        f(MpCheckoutPricingSnapshot.premiumAnnualEquivalentMonthlyFloor(
            old.premiumAnnual)),
        f(MpCheckoutPricingSnapshot.premiumAnnualEquivalentMonthlyFloor(
            next.premiumAnnual)),
      ),
      (f(old.extraBankConnectionMonthly), f(next.extraBankConnectionMonthly)),
      (f(old.extraBankConnectionAnnual), f(next.extraBankConnectionAnnual)),
    ];
    final gen = next.generatedPremiumLandingFields();
    var changed = 0;
    _filling = true;
    for (final e in _ctrls.entries) {
      if (kLandingPriceDrivenKeys.contains(e.key)) continue;
      var t = e.value.text;
      final before = t;
      // Duas fases (valor → marca → valor novo) para não trocar em cadeia.
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i].$1 != pairs[i].$2) {
          t = t.replaceAll(pairs[i].$1, '\u0000$i\u0000');
        }
      }
      for (var i = 0; i < pairs.length; i++) {
        t = t.replaceAll('\u0000$i\u0000', pairs[i].$2);
      }
      // Parágrafos de preço sem marcadores: regera como antes.
      final g = gen[e.key];
      if (g != null &&
          !kLandingPriceDrivenKeys.contains(e.key) &&
          e.key != 'divPremiumBeneficios' &&
          !t.contains('{') &&
          t.contains(r'R$')) {
        t = g;
      }
      if (t != before) {
        e.value.text = t;
        changed++;
      }
    }
    _filling = false;
    _refreshPriceDriven();
    setState(() => _dirty = true);
    await _saveAll(
      ask: false,
      doneMsg: changed == 0
          ? 'Preços salvos. Nenhum texto citava o valor antigo (os textos com marcadores já se atualizam sozinhos).'
          : 'Sincronizado: $changed texto(s) atualizados e tudo salvo no site.',
    );
  }

  // ── Restaurar padrão ────────────────────────────────────────────────────

  void _restoreField(String key) {
    _ctrls[key]?.text = landingDefaultFor(key);
  }

  Future<void> _restoreSection(LandingEditorSection s) async {
    if (!await _confirm(
        'Restaurar «${s.title}»?',
        'Todos os campos desta seção voltam ao texto padrão do código. '
            'Nada é publicado até você tocar em «Salvar».',
        'Restaurar')) {
      return;
    }
    for (final k in s.keys) {
      if (kLandingPriceDrivenKeys.contains(k)) continue;
      _restoreField(k);
    }
    if (s.id == 'config') setState(() => _googleAgendaEnabled = true);
  }

  // ── Prévia ──────────────────────────────────────────────────────────────

  void _openPreview(bool divulgacao) {
    if (_dirty) {
      _snack(
          'A prévia mostra o que está SALVO. Salve antes para ver as mudanças.',
          error: true);
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: Text(divulgacao
              ? 'Prévia — /divulgacao'
              : 'Prévia — página inicial (/)'),
        ),
        body: divulgacao
            ? const TelaDivulgacaoPage(preview: true)
            : const LandingScreen(preview: true),
      ),
    ));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Carregando os textos e preços salvos…'),
            ],
          ),
        ),
      );
    }
    if (_loadError != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminErroCard(erro: _loadError, onTentar: _load),
        ],
      );
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _header(context),
              const SizedBox(height: 12),
              _pricesCard(context),
              const SizedBox(height: 12),
              FastTextField(
                controller: _searchCtrl,
                kind: FastTextFieldKind.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Procurar um texto ou campo…',
                  isDense: true,
                  filled: true,
                  fillColor: AdminUi.cardOf(context),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _searchCtrl.clear()),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              for (final s in kLandingEditorSections)
                if (_sectionMatches(s, q)) _sectionCard(context, s, q),
            ],
          ),
        ),
        _bottomBar(context, bottomPad),
      ],
    );
  }

  bool _fieldMatches(String key, String q) {
    if (q.isEmpty) return true;
    final f = kLandingAllFieldsByKey[key];
    return (f?.label.toLowerCase().contains(q) ?? false) ||
        (_ctrls[key]?.text.toLowerCase().contains(q) ?? false) ||
        key.toLowerCase().contains(q);
  }

  bool _sectionMatches(LandingEditorSection s, String q) {
    if (q.isEmpty) return true;
    if (s.title.toLowerCase().contains(q)) return true;
    return s.keys.any((k) => _fieldMatches(k, q));
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.web_rounded, color: AdminUi.azul),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Landing / Divulgação',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: AdminUi.tintaOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Todos os textos da página inicial (/), da /divulgacao, da faixa '
            '«Login expresso» e do cartão de promoção. Cada campo já vem com o '
            'texto que está no site. Campo vazio volta ao texto padrão. '
            'Salvou → o site muda na hora, sem deploy.',
            style: TextStyle(
                fontSize: 12.5, height: 1.35, color: AdminUi.apoioOf(context)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openPreview(false),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Prévia da página inicial'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openPreview(true),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Prévia da /divulgacao'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceField(TextEditingController c, String label, String helper) {
    return SizedBox(
      width: 220,
      child: FastTextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'R\$ ',
          helperText: helper,
          helperMaxLines: 2,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _pricesCard(BuildContext context) {
    final p = _previewPrices;
    final eq = MpCheckoutPricingSnapshot.formatBrl(
        MpCheckoutPricingSnapshot.premiumAnnualEquivalentMonthlyFloor(
            p.premiumAnnual));
    final invalid = _formPrices() == null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: invalid
                ? AdminUi.vermelho
                : AdminUi.verde.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_rounded, color: AdminUi.verde),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Preços checkout (Mercado Pago)',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AdminUi.tintaOf(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'app_config/mp_checkout_prices — o MESMO valor é cobrado no checkout '
            '(Cloud Functions), mostrado na página inicial, na /divulgacao, na '
            'escolha de plano e na tela de licença vencida. Premium PRO acompanha '
            'o Premium. App Store (se houver) continua no App Store Connect.',
            style: TextStyle(
                fontSize: 12, height: 1.35, color: AdminUi.apoioOf(context)),
          ),
          if (_pricesLoadWarning != null) ...[
            const SizedBox(height: 8),
            Text(
              _pricesLoadWarning!,
              style: const TextStyle(
                  fontSize: 12,
                  color: AdminUi.ambar,
                  fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _priceField(_premMCtrl, 'Premium mensal', 'Cobrado por mês'),
              _priceField(
                  _premACtrl, 'Premium anual', 'No site: equivale a $eq/mês'),
              _priceField(_extraMCtrl, 'Conexão bancária extra — mensal',
                  'Add-on Open Finance'),
              _priceField(_extraACtrl, 'Conexão bancária extra — anual',
                  'Add-on Open Finance'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _savePricesOnly,
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: const Text('Salvar preços checkout'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _syncPricesIntoTexts,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('Sincronizar preços nos textos'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdminUi.azul.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Dica: em qualquer texto use {premium_mensal}, {premium_anual}, '
              '{premium_anual_mes}, {extra_mensal}, {extra_anual} ou {dias} '
              '(dias grátis) — o site troca pelo valor atual e o texto nunca '
              'fica com preço velho.',
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: AdminUi.tintaOf(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, LandingEditorSection s, String q) {
    final keys = q.isEmpty || s.title.toLowerCase().contains(q)
        ? s.keys
        : s.keys.where((k) => _fieldMatches(k, q)).toList();
    final changed = s.keys
        .where((k) =>
            !kLandingPriceDrivenKeys.contains(k) &&
            (_ctrls[k]?.text.trim() ?? '') != landingDefaultFor(k).trim())
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('landing_sec_${s.id}_${q.isNotEmpty}'),
          initiallyExpanded: q.isNotEmpty,
          leading: Icon(_sectionIcons[s.id] ?? Icons.notes_rounded,
              color: AdminUi.azul),
          title: Text(
            s.title,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: AdminUi.tintaOf(context)),
          ),
          subtitle: Text(
            [
              if (s.subtitle.isNotEmpty) s.subtitle,
              changed == 0
                  ? 'Tudo no texto padrão'
                  : '$changed campo(s) diferente(s) do padrão',
            ].join(' · '),
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            for (final k in keys) _field(context, k),
            if (s.id == 'config')
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Integração Google Agenda habilitada'),
                subtitle: const Text(
                    'Mostra/oculta o botão no topo do módulo Agenda.'),
                value: _googleAgendaEnabled,
                onChanged: (v) => setState(() {
                  _googleAgendaEnabled = v;
                  _dirty = true;
                }),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _restoreSection(s),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Restaurar padrão da seção'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, String key) {
    final def = kLandingAllFieldsByKey[key];
    final c = _ctrls[key];
    if (def == null || c == null) return const SizedBox.shrink();
    final auto = kLandingPriceDrivenKeys.contains(key);
    // Tipo do teclado fixo por campo (trocar no meio da digitação reinicia o IME).
    final long = def.defaultValue.length > 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: c,
        builder: (context, v, _) {
          final text = v.text;
          final isDefault = text.trim() == def.defaultValue.trim();
          String? helper;
          if (auto) {
            helper = 'Automático: vem dos preços do checkout.';
          } else if (text.contains('{')) {
            helper =
                'No site: ${landingFillPlaceholders(text, _previewPrices)}';
          } else if (text.trim().isEmpty && def.defaultValue.isNotEmpty) {
            helper = 'Vazio → o site usa o padrão: ${def.defaultValue}';
          }
          return FastTextField(
            controller: c,
            readOnly: auto,
            kind: long ? FastTextFieldKind.prose : FastTextFieldKind.standard,
            textInputAction: TextInputAction.newline,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            minLines: 1,
            maxLines: long ? 6 : 3,
            decoration: InputDecoration(
              labelText: def.label,
              helperText: helper,
              helperMaxLines: 3,
              filled: true,
              fillColor: auto
                  ? (context.isDarkMode
                      ? context.appScaffold
                      : Colors.grey.shade100)
                  : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: auto
                  ? const Icon(Icons.lock_outline_rounded, size: 18)
                  : (isDefault
                      ? null
                      : IconButton(
                          tooltip:
                              'Restaurar padrão: ${def.defaultValue.isEmpty ? '(vazio)' : def.defaultValue}',
                          icon: const Icon(Icons.restart_alt_rounded),
                          onPressed: () => _restoreField(key),
                        )),
            ),
          );
        },
      ),
    );
  }

  Widget _bottomBar(BuildContext context, double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPad),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        border: Border(top: BorderSide(color: AdminUi.bordaOf(context))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  _dirty ? Icons.edit_note_rounded : Icons.cloud_done_rounded,
                  size: 18,
                  color: _dirty ? AdminUi.ambar : AdminUi.verde,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _saving
                        ? 'Salvando…'
                        : (_dirty ? 'Alterações não salvas' : 'Tudo salvo'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AdminUi.apoioOf(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _syncPricesIntoTexts,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Sincronizar'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : () => _saveAll(),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
