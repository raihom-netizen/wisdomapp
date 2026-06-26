import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions, HttpsCallableOptions;
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../constants/premium_pro_limits.dart';
import '../models/user_profile.dart';
import '../services/admin_audit_service.dart';
import '../services/billing_service.dart';
import '../services/logs_service.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../theme/app_colors.dart';
import '../utils/debounced_text_controller.dart';
import '../widgets/brl_amount_text_field.dart';

/// Parâmetros de custo estimado (editáveis no próprio painel → `app_config/premium_pro_monitor`).
class _ProMonitorEconomics {
  const _ProMonitorEconomics({
    required this.pluggyCostPerItemMonthBrl,
    required this.firebaseEstimatePerUserMonthBrl,
    required this.mercadoPagoFeePercent,
  });

  final double pluggyCostPerItemMonthBrl;
  final double firebaseEstimatePerUserMonthBrl;
  final double mercadoPagoFeePercent;

  static _ProMonitorEconomics fromFirestore(Map<String, dynamic>? raw) {
    double pick(String k, double def) {
      final v = raw?[k];
      if (v is num && v.isFinite) return v.toDouble();
      if (v is String) {
        final n = double.tryParse(v.replaceAll(',', '.'));
        if (n != null && n.isFinite) return n;
      }
      return def;
    }

    return _ProMonitorEconomics(
      pluggyCostPerItemMonthBrl: pick('pluggyCostPerItemMonthBrl', 12),
      firebaseEstimatePerUserMonthBrl: pick('firebaseEstimatePerUserMonthBrl', 0.85),
      mercadoPagoFeePercent: pick('mercadoPagoFeePercent', 4.98),
    );
  }

  Map<String, dynamic> toMap() => {
        'pluggyCostPerItemMonthBrl': pluggyCostPerItemMonthBrl,
        'firebaseEstimatePerUserMonthBrl': firebaseEstimatePerUserMonthBrl,
        'mercadoPagoFeePercent': mercadoPagoFeePercent,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// KPIs globais de add-on Open Finance (MP + `bank_connection_entitlements`).
class _ProAddonKpis {
  const _ProAddonKpis({
    this.extrasVigentes,
    this.pagamentosAddOnAprovados,
    this.negadoPorTeto,
    this.negadoSemPro,
    this.error,
  });

  final int? extrasVigentes;
  /// `mp_payments` com campo `entitlementType` = extra_bank_connection.
  final int? pagamentosAddOnAprovados;
  final int? negadoPorTeto;
  final int? negadoSemPro;
  final String? error;
}

UserProfile _profileFromUserDoc(String uid, Map<String, dynamic> d) {
  DateTime? licenseExpiresAt;
  final exp = d['licenseExpiresAt'];
  if (exp is Timestamp) licenseExpiresAt = exp.toDate();
  final createdAt = d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null;
  final rawPid = d['partnershipId'];
  final partnershipId = rawPid == null || rawPid.toString().trim().isEmpty
      ? null
      : rawPid.toString().trim();
  return UserProfile(
    uid: uid,
    cpf: (d['cpf'] ?? '') as String,
    cpfMasked: (d['cpfMasked'] ?? '') as String,
    email: (d['email'] ?? '') as String,
    name: (d['name'] ?? '') as String,
    role: (d['role'] ?? 'user') as String,
    plan: (d['plan'] ?? 'premium') as String,
    planStatus: (d['planStatus'] ?? 'active') as String,
    licenseExpiresAt: licenseExpiresAt,
    createdAt: createdAt,
    profileComplete: d['profileComplete'] != false,
    premiumPro: d['premiumPro'] == true,
    isPremiumPro: d['isPremiumPro'] == true,
    partnershipId: partnershipId,
    premiumProIncludedBankConnections:
        PremiumProLimits.parseAdminIncludedSlotsOverride(d['premiumProIncludedBankConnections']),
  );
}

bool _isProEntitlementMap(Map<String, dynamic> d) {
  final plan = (d['plan'] ?? '').toString().toLowerCase();
  if (plan == 'premium_pro' || plan.contains('premium_pro')) return true;
  if (d['premiumPro'] == true) return true;
  if (d['isPremiumPro'] == true) return true;
  return false;
}

String _planDropdownValue(String plan) {
  final p = plan.toLowerCase();
  if (p == 'free') return 'free';
  if (p == 'premium_assego') return 'premium_assego';
  if (p == 'premium_pro') return 'premium_pro';
  if (p == 'basic' || p == 'basico') return 'basic';
  if (p == 'master' || p == 'master_monthly' || p == 'master_annual') return 'master';
  if (p == 'premium' || p == 'premium_monthly' || p == 'premium_annual') return 'premium';
  return 'premium';
}

List<DropdownMenuItem<String>> _planDropdownItems(String currentPlan) {
  final p = currentPlan.toLowerCase();
  final items = <DropdownMenuItem<String>>[
    const DropdownMenuItem(value: 'free', child: Text('Free')),
    const DropdownMenuItem(value: 'premium', child: Text('Premium')),
    const DropdownMenuItem(value: 'premium_assego', child: Text('Premium ASSEGO')),
    const DropdownMenuItem(value: 'premium_pro', child: Text('Plano legado (dashboard)')),
  ];
  if (p == 'basic' || p == 'basico') {
    items.insert(1, const DropdownMenuItem(value: 'basic', child: Text('Básico (legado — migrar)')));
  }
  if (p == 'master' || p == 'master_monthly' || p == 'master_annual') {
    items.insert(2, const DropdownMenuItem(value: 'master', child: Text('Master plano (legado — migrar)')));
  }
  return items;
}

/// Painel interno: utilizadores com plano legado no Firestore, conexões e custos estimados.
class AdminPremiumProMonitorTab extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;
  final String currentAdminUid;

  const AdminPremiumProMonitorTab({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
    required this.currentAdminUid,
  });

  @override
  State<AdminPremiumProMonitorTab> createState() => _AdminPremiumProMonitorTabState();
}

class _AdminPremiumProMonitorTabState extends State<AdminPremiumProMonitorTab> {
  final _searchCtrl = TextEditingController();
  final _pluggyCtrl = TextEditingController();
  final _fbCtrl = TextEditingController();
  final _mpFeeCtrl = TextEditingController();
  VoidCallback? _detachSearchListener;

  _ProMonitorEconomics _econ = _ProMonitorEconomics.fromFirestore(null);
  List<({QueryDocumentSnapshot<Map<String, dynamic>> doc, int bankCount, UserProfile profile})> _rows = [];
  bool _loading = true;
  String? _error;
  _ProAddonKpis _addonKpis = const _ProAddonKpis();

  @override
  void initState() {
    super.initState();
    _pluggyCtrl.text = CurrencyFormats.formatBRLInput(_econ.pluggyCostPerItemMonthBrl);
    _fbCtrl.text = CurrencyFormats.formatBRLInput(_econ.firebaseEstimatePerUserMonthBrl);
    _mpFeeCtrl.text = _econ.mercadoPagoFeePercent.toStringAsFixed(2).replaceAll('.', ',');
    // Debounce na busca de usuários PRO — sem rebuild por keystroke.
    _detachSearchListener = attachDebouncedRebuild(_searchCtrl, () {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _detachSearchListener?.call();
    _searchCtrl.dispose();
    _pluggyCtrl.dispose();
    _fbCtrl.dispose();
    _mpFeeCtrl.dispose();
    super.dispose();
  }

  Future<_ProAddonKpis> _fetchAddonKpis(FirebaseFirestore db) async {
    final now = Timestamp.now();
    try {
      final snaps = await Future.wait<AggregateQuerySnapshot>([
        db
            .collectionGroup('bank_connection_entitlements')
            .where('expiresAt', isGreaterThan: now)
            .count()
            .get(),
        db
            .collection('mp_payments')
            .where('entitlementDeniedReason', isEqualTo: 'max_total_bank_connections')
            .count()
            .get(),
        db
            .collection('mp_payments')
            .where('entitlementDeniedReason', isEqualTo: 'not_premium_pro')
            .count()
            .get(),
        db
            .collection('mp_payments')
            .where('entitlementType', isEqualTo: 'extra_bank_connection')
            .count()
            .get(),
      ]);
      return _ProAddonKpis(
        extrasVigentes: snaps[0].count,
        negadoPorTeto: snaps[1].count,
        negadoSemPro: snaps[2].count,
        pagamentosAddOnAprovados: snaps[3].count,
      );
    } catch (e) {
      return _ProAddonKpis(error: e.toString());
    }
  }

  String _kpiIntOrDash(int? n) => n == null ? '—' : '$n';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final addonFuture = _fetchAddonKpis(db);
      final proLoad = await Future.wait<dynamic>([
        db.doc('app_config/premium_pro_monitor').get(),
        db.collection('users').where('plan', isEqualTo: 'premium_pro').limit(500).get(),
        db.collection('users').where('premiumPro', isEqualTo: true).limit(500).get(),
        db.collection('users').where('isPremiumPro', isEqualTo: true).limit(500).get(),
      ]);
      final econSnap = proLoad[0] as DocumentSnapshot<Map<String, dynamic>>;
      final s1 = proLoad[1] as QuerySnapshot<Map<String, dynamic>>;
      final s2 = proLoad[2] as QuerySnapshot<Map<String, dynamic>>;
      final s3 = proLoad[3] as QuerySnapshot<Map<String, dynamic>>;
      _econ = _ProMonitorEconomics.fromFirestore(econSnap.data());
      _pluggyCtrl.text = CurrencyFormats.formatBRLInput(_econ.pluggyCostPerItemMonthBrl);
      _fbCtrl.text = CurrencyFormats.formatBRLInput(_econ.firebaseEstimatePerUserMonthBrl);
      _mpFeeCtrl.text = _econ.mercadoPagoFeePercent.toStringAsFixed(2).replaceAll('.', ',');
      final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in s1.docs) {
        merged[d.id] = d;
      }
      for (final d in s2.docs) {
        merged[d.id] = d;
      }
      for (final d in s3.docs) {
        merged[d.id] = d;
      }
      final docs = merged.values.where((d) => _isProEntitlementMap(d.data())).toList();

      final rows = <({QueryDocumentSnapshot<Map<String, dynamic>> doc, int bankCount, UserProfile profile})>[];
      const batch = 30;
      for (var i = 0; i < docs.length; i += batch) {
        final end = i + batch > docs.length ? docs.length : i + batch;
        final slice = docs.sublist(i, end);
        final partial = await Future.wait(slice.map((doc) async {
          final agg = await db.collection('users').doc(doc.id).collection('bank_connections').count().get();
          final n = agg.count ?? 0;
          final profile = _profileFromUserDoc(doc.id, doc.data());
          return (doc: doc, bankCount: n, profile: profile);
        }));
        rows.addAll(partial);
      }
      rows.sort((a, b) => a.profile.name.toLowerCase().compareTo(b.profile.name.toLowerCase()));
      final addonKpis = await addonFuture;
      if (mounted) {
        setState(() {
          _rows = rows;
          _addonKpis = addonKpis;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _addonKpis = _ProAddonKpis(error: e.toString());
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveEconomics() async {
    double parseFeePercent(String s) =>
        double.tryParse(s.trim().replaceAll(',', '.')) ?? double.nan;
    final plug = CurrencyFormats.parseBRLInput(_pluggyCtrl.text) ?? double.nan;
    final fb = CurrencyFormats.parseBRLInput(_fbCtrl.text) ?? double.nan;
    final fee = parseFeePercent(_mpFeeCtrl.text);
    if (plug.isNaN || fb.isNaN || fee.isNaN || plug < 0 || fb < 0 || fee < 0 || fee > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valores inválidos. Use vírgula como decimal (ex.: 12,50).')),
      );
      return;
    }
    final next = _ProMonitorEconomics(
      pluggyCostPerItemMonthBrl: plug,
      firebaseEstimatePerUserMonthBrl: fb,
      mercadoPagoFeePercent: fee,
    );
    await FirebaseFirestore.instance.doc('app_config/premium_pro_monitor').set(next.toMap(), SetOptions(merge: true));
    if (mounted) {
      setState(() => _econ = next);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parâmetros de custo salvos.')));
    }
  }

  double _baseRevenueMid(MpCheckoutPricingSnapshot p) {
    return (p.premiumProMonthly + MpCheckoutPricingSnapshot.premiumAnnualEquivalentMonthlyFloor(p.premiumProAnnual)) / 2;
  }

  double _extrasRevenue(int bankCount, UserProfile profile) {
    final inc = PremiumProLimits.includedBankConnections(
      email: profile.email,
      adminPerUserOverride: profile.premiumProIncludedBankConnections,
    );
    final extra = bankCount - inc;
    if (extra <= 0) return 0;
    return extra * PremiumProLimits.extraConnectionMonthlyBrl;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MpCheckoutPricingSnapshot>(
      stream: MpCheckoutPricingService.watch(),
      builder: (context, priceSnap) {
        final prices = priceSnap.data ?? MpCheckoutPricingSnapshot.defaults();
        final q = _searchCtrl.text.trim().toLowerCase();
        final filtered = q.isEmpty
            ? _rows
            : _rows.where((r) {
                final n = r.profile.name.toLowerCase();
                final e = r.profile.email.toLowerCase();
                return n.contains(q) || e.contains(q) || r.doc.id.contains(q);
              }).toList();

        final blocked = filtered.where((r) => r.profile.licenseAccessState == 'BLOQUEADO').length;
        final withExtras = filtered.where((r) {
          final inc = PremiumProLimits.includedBankConnections(
            email: r.profile.email,
            adminPerUserOverride: r.profile.premiumProIncludedBankConnections,
          );
          return r.bankCount > inc;
        }).length;
        final totalBanks = filtered.fold<int>(0, (s, r) => s + r.bankCount);
        final totalExtraSlots = filtered.fold<int>(0, (s, r) {
          final inc = PremiumProLimits.includedBankConnections(
            email: r.profile.email,
            adminPerUserOverride: r.profile.premiumProIncludedBankConnections,
          );
          if (r.bankCount <= inc) return s;
          return s + (r.bankCount - inc);
        });

        final baseMid = _baseRevenueMid(prices);
        double sumRev = 0, sumPluggy = 0, sumFb = 0, sumMpFee = 0, sumNet = 0;
        for (final r in filtered) {
          final rev = baseMid + _extrasRevenue(r.bankCount, r.profile);
          final pluggy = r.bankCount * _econ.pluggyCostPerItemMonthBrl;
          final fb = _econ.firebaseEstimatePerUserMonthBrl;
          final mp = rev * (_econ.mercadoPagoFeePercent / 100);
          final net = rev - pluggy - fb - mp;
          sumRev += rev;
          sumPluggy += pluggy;
          sumFb += fb;
          sumMpFee += mp;
          sumNet += net;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroHeader(
              filtered.length,
              blocked,
              withExtras,
              totalBanks,
              totalExtraSlots,
              sumRev,
              sumPluggy,
              sumFb,
              sumMpFee,
              sumNet,
              _addonKpis,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: [
                              _economicsCard(),
                              const SizedBox(height: 12),
                              FastTextField(
                                controller: _searchCtrl,
                                autocorrect: false,
                                enableSuggestions: false,
                                enableIMEPersonalizedLearning: false,
                                spellCheckConfiguration:
                                    const SpellCheckConfiguration.disabled(),
                                smartDashesType: SmartDashesType.disabled,
                                smartQuotesType: SmartQuotesType.disabled,
                                textInputAction: TextInputAction.search,
                                onTapOutside: (_) =>
                                    FocusManager.instance.primaryFocus?.unfocus(),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  hintText: 'Buscar por nome, e-mail ou UID',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                // Debounce via listener — sem onChanged: setState.
                              ),
                              const SizedBox(height: 12),
                              ...filtered.map((r) => _userCard(context, r, baseMid)),
                              if (filtered.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    q.isEmpty ? 'Nenhum utilizador com plano legado encontrado.' : 'Nenhum resultado para a busca.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.blueGrey.shade600),
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _heroHeader(
    int userCount,
    int blocked,
    int withExtras,
    int totalBanks,
    int totalExtraSlots,
    double sumRev,
    double sumPluggy,
    double sumFb,
    double sumMpFee,
    double sumNet,
    _ProAddonKpis addOnKpis,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [const Color(0xFF0F172A), widget.brandTeal.withValues(alpha: 0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: widget.brandBlue.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: Colors.amber.shade300, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Monitor legado · API bancos & custos',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, height: 1.15),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Incluso: ${PremiumProLimits.defaultIncludedBankConnections} (padrão) ou ${PremiumProLimits.vipIncludedBankConnections} (lista VIP no app). Extra: ${PremiumProLimits.extraConnectionPriceLabel}/mês por conexão acima do incluso.',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.88), height: 1.35),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _kpiChip(Icons.people_rounded, 'Usuários PRO', '$userCount'),
              _kpiChip(Icons.block_rounded, 'Bloqueados', '$blocked'),
              _kpiChip(Icons.add_card_rounded, 'Com extras', '$withExtras'),
              _kpiChip(Icons.hub_rounded, 'Conexões totais', '$totalBanks'),
              _kpiChip(Icons.layers_rounded, 'Slots extras', '$totalExtraSlots'),
              _kpiChip(Icons.trending_up_rounded, 'Rec. estim. /mês', _brl(sumRev)),
              _kpiChip(Icons.account_balance_wallet_rounded, 'Pluggy (est.)', _brl(sumPluggy)),
              _kpiChip(Icons.cloud_rounded, 'Firebase (est.)', _brl(sumFb)),
              _kpiChip(Icons.payment_rounded, 'Taxa MP (est.)', _brl(sumMpFee)),
              _kpiChip(Icons.savings_rounded, 'Líquido (est.)', _brl(sumNet), highlight: true),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Add-on conexão extra (Mercado Pago)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.92),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cada “extra vigente” = 1 registo em users/…/bank_connection_entitlements com validade ativa. Negados: webhook processou o pagamento mas não libertou o slot (ver functions).',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75), height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _kpiChip(Icons.bolt_rounded, 'Extras vigentes', _kpiIntOrDash(addOnKpis.extrasVigentes)),
              _kpiChip(Icons.verified_outlined, 'Add-on aprov. (MP)', _kpiIntOrDash(addOnKpis.pagamentosAddOnAprovados)),
              _kpiChip(Icons.trending_down_rounded, 'Negado: teto', _kpiIntOrDash(addOnKpis.negadoPorTeto)),
              _kpiChip(Icons.gpp_bad_outlined, 'Negado: s/ PRO', _kpiIntOrDash(addOnKpis.negadoSemPro)),
            ],
          ),
          if (addOnKpis.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'KPIs add-on: ${addOnKpis.error}',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade200, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kpiChip(IconData icon, String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? Colors.amber.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: highlight ? Colors.amber.shade200 : Colors.white70),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: highlight ? Colors.amber.shade100 : Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _economicsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: widget.brandTeal.withValues(alpha: 0.35))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Parâmetros de custo (Firestore: app_config/premium_pro_monitor)', style: TextStyle(fontWeight: FontWeight.w800, color: widget.brandBlue)),
            const SizedBox(height: 4),
            Text(
              'Valores são estimativas para acompanhar margem. Ajuste conforme sua fatura Pluggy, uso Firestore e taxa real Mercado Pago.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: BrlAmountTextField(
                    controller: _pluggyCtrl,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    decoration: const InputDecoration(
                        labelText: 'Pluggy R\$/item/mês'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BrlAmountTextField(
                    controller: _fbCtrl,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    decoration: const InputDecoration(
                        labelText: 'Firebase R\$/usuário/mês'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FastTextField(
                    controller: _mpFeeCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(labelText: 'Taxa MP %'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveEconomics,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Salvar parâmetros'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userCard(
    BuildContext context,
    ({QueryDocumentSnapshot<Map<String, dynamic>> doc, int bankCount, UserProfile profile}) r,
    double baseMid,
  ) {
    final d = r.doc.data();
    final uid = r.doc.id;
    final name = r.profile.name.isEmpty ? 'Sem nome' : r.profile.name;
    final email = r.profile.email;
    final plan = r.profile.plan;
    final lic = r.profile.licenseExpiresAt;
    final licStr = lic == null ? '—' : DateFormat('dd/MM/yyyy').format(lic);
    final state = r.profile.licenseAccessState;
    final incN = PremiumProLimits.includedBankConnections(
      email: email,
      adminPerUserOverride: r.profile.premiumProIncludedBankConnections,
    );
    final extraSlots = r.bankCount > incN ? r.bankCount - incN : 0;
    final rev = baseMid + _extrasRevenue(r.bankCount, r.profile);
    final pluggy = r.bankCount * _econ.pluggyCostPerItemMonthBrl;
    final fb = _econ.firebaseEstimatePerUserMonthBrl;
    final mpFee = rev * (_econ.mercadoPagoFeePercent / 100);
    final net = rev - pluggy - fb - mpFee;
    final isSelf = uid == widget.currentAdminUid;
    final removed = d['removedByAdminAt'] != null;

    Color stateColor;
    String stateLabel;
    switch (state) {
      case 'BLOQUEADO':
        stateColor = AppColors.error;
        stateLabel = 'Bloqueado';
        break;
      case 'CARENCIA':
        stateColor = Colors.orange.shade800;
        stateLabel = 'Carência';
        break;
      default:
        stateColor = AppColors.success;
        stateLabel = state == 'ATIVO' ? 'Ativo' : state;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.blueGrey.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: widget.brandTeal.withValues(alpha: 0.2),
                  child: Icon(Icons.person_rounded, color: widget.brandTeal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      Text(email, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600)),
                      Text('UID: $uid', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade400)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: stateColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(stateLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: stateColor)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _miniStat(Icons.credit_card_rounded, 'Conexões', '${r.bankCount} ($incN inclusas)'),
                if (extraSlots > 0)
                  _miniStat(Icons.add_circle_outline_rounded, 'Extras pagos', '$extraSlots × ${PremiumProLimits.extraConnectionPriceLabel}'),
                _miniStat(Icons.payments_rounded, 'Rec. média est.', _brl(rev)),
                _miniStat(Icons.trending_down_rounded, 'Custos est.', _brl(pluggy + fb + mpFee)),
                _miniStat(Icons.savings_outlined, 'Líquido est.', _brl(net)),
                _miniStat(Icons.event_rounded, 'Vencimento', licStr),
              ],
            ),
            const Divider(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!removed) ...[
                  DropdownButton<String>(
                    value: _planDropdownValue(plan),
                    items: _planDropdownItems(plan),
                    onChanged: (newPlan) async {
                      if (newPlan == null) return;
                      final before = <String, dynamic>{'plan': plan};
                      if (newPlan == 'free') {
                        await BillingService().setUserToFree(uid);
                      } else {
                        await r.doc.reference.update({
                          'plan': newPlan,
                          'planStatus': 'active',
                          'updatedAt': FieldValue.serverTimestamp(),
                          'removedByAdminAt': FieldValue.delete(),
                        });
                      }
                      await AdminAuditService().logAdminAction(
                        action: alterarPlano,
                        targetUserId: uid,
                        targetUserEmail: email.isNotEmpty ? email : null,
                        before: before,
                        after: <String, dynamic>{'plan': newPlan},
                      );
                      await LogsService().saveLog(modulo: 'Admin PRO Monitor', acao: 'Alterou plano', detalhes: '$name → $newPlan');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Plano: $newPlan')));
                      await _load();
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editExpiry(context, r.doc),
                    icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    label: const Text('Vencimento'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _plus15(context, uid, name, email),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('+15 dias'),
                  ),
                ],
                if (!removed && !isSelf)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.person_remove_rounded, size: 18),
                    label: const Text('Remover'),
                    onPressed: () => _confirmRemoverUsuario(context, uid, name, email),
                  ),
                if (removed)
                  FilledButton.icon(
                    onPressed: () async {
                      await BillingService().reativarUsuario(uid);
                      await AdminAuditService().logAdminAction(action: reativarUsuario, targetUserId: uid, targetUserEmail: email.isNotEmpty ? email : null);
                      if (mounted) await _load();
                    },
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('Reativar'),
                  ),
                if (!isSelf)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    onPressed: () => _confirmDeleteTotal(context, uid, name, email),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('Excluir total'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: widget.brandBlue),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _plus15(BuildContext context, String uid, String name, String email) async {
    await BillingService().prorrogarPrazo(uid, 15);
    await AdminAuditService().logAdminAction(action: prorrogarPrazo, targetUserId: uid, targetUserEmail: email.isNotEmpty ? email : null, details: '+15 dias (monitor PRO)');
    await LogsService().saveLog(modulo: 'Admin PRO Monitor', acao: 'Prorrogou 15 dias', detalhes: name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prazo +15 dias.')));
    await _load();
  }

  Future<void> _editExpiry(BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data() ?? {};
    DateTime? licenseExpiresAt;
    final exp = d['licenseExpiresAt'];
    if (exp is Timestamp) licenseExpiresAt = exp.toDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: licenseExpiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;
    final endOfDay = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    final graceEnd = endOfDay.add(const Duration(days: UserProfile.licenseGracePeriodDays));
    final before = licenseExpiresAt != null ? <String, dynamic>{'licenseExpiresAt': licenseExpiresAt.toIso8601String()} : <String, dynamic>{};
    await doc.reference.update({
      'licenseExpiresAt': Timestamp.fromDate(endOfDay),
      'licenseValidUntilIncludingGrace': Timestamp.fromDate(graceEnd),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await AdminAuditService().logAdminAction(
      action: alterarVencimento,
      targetUserId: doc.id,
      targetUserEmail: (d['email'] ?? '').toString().isNotEmpty ? d['email'].toString() : null,
      before: before,
      after: <String, dynamic>{'licenseExpiresAt': endOfDay.toIso8601String()},
      details: DateFormat('dd/MM/yyyy').format(picked),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vencimento atualizado.')));
    await _load();
  }

  Future<void> _confirmRemoverUsuario(BuildContext context, String uid, String name, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover usuário?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tem certeza de que deseja remover este usuário? Ele perderá acesso ao app. Você pode reativar depois com o botão Reativar.',
              ),
              const SizedBox(height: 12),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(email, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              SelectableText('UID: $uid', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final logLabel = email.trim().isNotEmpty ? '$name <$email> [$uid]' : '$name [$uid]';
    await BillingService().removerUsuario(uid);
    await AdminAuditService().logAdminAction(
      action: removerUsuario,
      targetUserId: uid,
      targetUserEmail: email.trim().isNotEmpty ? email.trim() : null,
      details: logLabel,
    );
    await LogsService().saveLog(modulo: 'Admin PRO Monitor', acao: 'Removeu usuário (soft)', detalhes: logLabel);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Usuário removido (sai desta lista). Reative na aba Usuários (filtro Removidos) e ajuste o plano, se necessário.',
        ),
      ),
    );
    await _load();
  }

  Future<void> _confirmDeleteTotal(BuildContext context, String targetUid, String name, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir permanentemente?'),
        content: Text('Apaga login e dados de $name ($targetUid). Irreversível.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'ctDeleteUserTotal',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 280)),
      );
      await callable.call<Map<String, dynamic>>({'uid': targetUid});
      await AdminAuditService().logAdminAction(
        action: excluirUsuario,
        targetUserId: targetUid,
        targetUserEmail: email.trim().isNotEmpty ? email.trim() : null,
        details: 'Monitor PRO: $name',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuário excluído.')));
      await _load();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha: $e'), backgroundColor: AppColors.error));
    }
  }

  String _brl(double v) => MpCheckoutPricingSnapshot.formatBrl(v);
}
