import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/landing_public_content.dart';
import '../models/user_profile.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../utils/navigator_safe_pop.dart';
import '../widgets/divulgacao_public_promo_card.dart';
import '../widgets/plan_change_acknowledgment_card.dart';
import '../widgets/plan_change_contract_sheet.dart';
import 'payment_status_screen.dart';

/// Paywall: Premium — preços em `app_config/mp_checkout_prices`; textos em `landing_content/main`.
class EscolhaPlanoPage extends StatefulWidget {
  const EscolhaPlanoPage({super.key});

  @override
  State<EscolhaPlanoPage> createState() => _EscolhaPlanoPageState();
}

class _EscolhaPlanoPageState extends State<EscolhaPlanoPage> {
  bool _isAnual = true;
  String _planoSelecionado = 'Premium';
  String _formaPagamento = 'pix'; // 'pix' | 'cartao'
  final ScrollController _scrollController = ScrollController();
  bool _acceptedPlanChangeTerms = false;

  /// Link web: `?promo=id_do_firestore`
  String? _promoIdFromUrl;
  Map<String, dynamic>? _promoData;
  bool _promoLoading = false;
  String? _promoError;
  bool _routePromoChecked = false;
  bool _openMpCheckoutAfterPromoLoad = false;
  bool _autoPromoCheckoutOpened = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      final q = Uri.base.queryParameters['promo']?.trim();
      if (q != null && q.isNotEmpty) {
        _promoIdFromUrl = q;
        _loadPromo(q);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routePromoChecked) return;
    _routePromoChecked = true;
    if (_promoIdFromUrl != null) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final id = args['promoId']?.toString().trim();
      if (id != null && id.isNotEmpty) {
        _promoIdFromUrl = id;
        _loadPromo(id);
      }
      if (args['openMpCheckoutAfterPromoLoad'] == true) {
        _openMpCheckoutAfterPromoLoad = true;
      }
    }
  }

  Future<void> _loadPromo(String id) async {
    setState(() {
      _promoLoading = true;
      _promoError = null;
      _promoData = null;
    });
    try {
      final snap = await FirebaseFirestore.instance.collection('promotions').doc(id).get();
      if (!snap.exists) {
        setState(() {
          _promoError = 'Promoção não encontrada.';
          _promoLoading = false;
        });
        return;
      }
      final m = snap.data()!;
      final active = m['active'] != false;
      final total = (m['quantityTotal'] as num?)?.toInt() ?? 0;
      final sold = (m['quantitySold'] as num?)?.toInt() ?? 0;
      if (!active || sold >= total) {
        setState(() {
          _promoError = 'Promoção indisponível ou esgotada.';
          _promoLoading = false;
        });
        return;
      }
      final pc = (m['planCode'] ?? 'premium_monthly').toString().toLowerCase();
      final anual = pc.contains('annual') || pc.contains('yearly');
      setState(() {
        _promoData = m;
        _promoLoading = false;
        _isAnual = anual;
      });
      if (_openMpCheckoutAfterPromoLoad &&
          !_autoPromoCheckoutOpened) {
        _autoPromoCheckoutOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final promo = PublicDivulgacaoPromo.fromLoadedPromotionDoc(id, m);
          openPublicPromoMercadoPagoCheckout(context, promo);
        });
      }
    } catch (e) {
      setState(() {
        _promoError = e.toString();
        _promoLoading = false;
      });
    }
  }

  String _getPlanCode() {
    return _isAnual ? 'premium_annual' : 'premium_monthly';
  }

  String _precoExibicao(MpCheckoutPricingSnapshot p) {
    if (_promoData != null) {
      final pb = _promoData!['priceBrl'];
      if (pb != null && pb is num) {
        final s = pb.toDouble().toStringAsFixed(2).replaceAll('.', ',');
        return 'R\$ $s';
      }
    }
    return _isAnual ? MpCheckoutPricingSnapshot.formatBrl(p.premiumAnnual) : MpCheckoutPricingSnapshot.formatBrl(p.premiumMonthly);
  }

  String _periodoExibicao() {
    if (_promoData != null) {
      final d = (_promoData!['durationDays'] as num?)?.toInt() ?? 30;
      return '/ promoção (+$d dias)';
    }
    return _isAnual ? '/ ANO' : '/mês';
  }

  String _precoPlanoCard(MpCheckoutPricingSnapshot p) {
    if (_promoData != null) return _precoExibicao(p);
    return _isAnual
        ? MpCheckoutPricingSnapshot.formatBrl(p.premiumAnnual)
        : MpCheckoutPricingSnapshot.formatBrl(p.premiumMonthly);
  }

  Widget _buildPromoBanner() {
    if (_promoIdFromUrl == null) return const SizedBox.shrink();
    if (_promoLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_promoError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_promoError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
          ),
        ),
      );
    }
    if (_promoData == null) return const SizedBox.shrink();
    final m = _promoData!;
    final title = (m['title'] ?? 'Promoção').toString();
    final total = (m['quantityTotal'] as num?)?.toInt() ?? 0;
    final sold = (m['quantitySold'] as num?)?.toInt() ?? 0;
    final days = (m['durationDays'] as num?)?.toInt() ?? 30;
    final restam = total - sold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.local_offer_rounded, color: Colors.green.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Após o pagamento aprovado, sua licença será estendida em $days dias. Restam $restam vagas.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      appBar: AppBar(
        title: const Text('Seu Plano'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => popOrGoHome(context),
        ),
      ),
      body: Container(
        // Fundo moderno em gradiente suave (azul/lavanda) em vez de cinza chapado.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEEF2F7),
              Color(0xFFE7EEFF),
              Color(0xFFF3EEFF),
            ],
          ),
        ),
        child: SafeArea(
        top: true,
        bottom: true,
        left: true,
        right: true,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('landing_content').doc('main').snapshots(),
          builder: (context, landSnap) {
            return StreamBuilder<MpCheckoutPricingSnapshot>(
              stream: MpCheckoutPricingService.watch(),
              initialData: MpCheckoutPricingSnapshot.defaults(),
              builder: (context, pricingSnap) {
                final p = pricingSnap.data ?? MpCheckoutPricingSnapshot.defaults();
                final landing = LandingPublicContent.fromMap(landSnap.data?.data()).applyPremiumTextsFromCheckoutPricing(p);
                return SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.sizeOf(context).height -
                          MediaQuery.paddingOf(context).top -
                          MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        16,
                        20,
                        16 +
                            (MediaQuery.paddingOf(context).bottom > 0
                                ? MediaQuery.paddingOf(context).bottom
                                : 24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Escolha o plano ideal para sua gestão',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Seu período de teste de ${UserProfile.newUserTrialDays} dias termina em breve. Mantenha seu controle total!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sem propagandas indesejáveis. Limpo e seguro.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF2E7D32), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Use onde for mais prático para si — a mesma conta em todos os acessos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF1A237E), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              landing.divPlanosSubtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildPromoBanner(),
                          const SizedBox(height: 14),
                          if (_promoData != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                'Esta promoção define o plano e a extensão da licença; o seletor abaixo fica desativado.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade700, height: 1.3),
                              ),
                            ),
                          AbsorbPointer(
                            absorbing: _promoData != null,
                            child: Opacity(
                                opacity: _promoData != null ? 0.45 : 1, child: _buildPeriodSelector()),
                          ),
                          if (_promoData == null && !_isAnual) ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Frisando: no plano anual (${p.premiumAnnualLine}) o valor equivale a ${MpCheckoutPricingSnapshot.formatBrl(MpCheckoutPricingSnapshot.premiumAnnualEquivalentMonthlyFloor(p.premiumAnnual))} por mês — ótimo negócio. Recomendamos comprar anual.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 30),
                          _buildPlanoCard(
                            nome: 'Premium',
                            preco: _precoPlanoCard(p),
                            periodo: _periodoExibicao(),
                            notaAnual: _promoData != null
                                ? null
                                : (_isAnual
                                    ? 'Plano anual: ${p.premiumAnnualLine} — equivale a ${p.premiumAnnualEquivPerMonthLine}; ótimo negócio em relação ao mensal.'
                                    : null),
                            beneficios: landing.divPremiumBeneficiosList.isNotEmpty
                                ? landing.divPremiumBeneficiosList
                                : const [
                                    'Finanças, metas e escalas: lançamentos e controles completos',
                                    'Gráficos, relatórios e comprovantes',
                                    'Gestão completa num só lugar',
                                  ],
                            isPremium: true,
                          ),
                          const SizedBox(height: 24),
                          PlanChangeAcknowledgmentCard(
                            accepted: _acceptedPlanChangeTerms,
                            onAcceptedChanged: (v) => setState(() => _acceptedPlanChangeTerms = v),
                          ),
                          const SizedBox(height: 24),
                          _buildPaymentSelection(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          _periodButton('Mensal', !_isAnual),
          _periodButton('Anual (Economize 20%)', _isAnual),
        ],
      ),
    );
  }

  Widget _periodButton(String label, bool selected) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _isAnual = label.contains('Anual')),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2962FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlanoSelected(String nome) {
    setState(() {
      _planoSelecionado = nome;
    });
    // Rola até a seção de pagamento (Pix/Cartão) para ficar visível
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Widget _buildPlanoCard({
    required String nome,
    required String preco,
    required String periodo,
    required List<String> beneficios,
    required bool isPremium,
    String? notaAnual,
  }) {
    final selecionado = _planoSelecionado == nome;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onPlanoSelected(nome),
        borderRadius: BorderRadius.circular(25),
        child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // Premium: gradiente vibrante (índigo → azul → violeta) + brilho colorido.
          gradient: isPremium
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A237E),
                    Color(0xFF2962FF),
                    Color(0xFF6D4DFF),
                  ],
                )
              : null,
          color: isPremium ? null : Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: selecionado ? Border.all(color: const Color(0xFF6D4DFF), width: 3) : null,
          boxShadow: [
            if (isPremium)
              BoxShadow(color: const Color(0xFF2962FF).withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10))
            else
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
            if (selecionado) BoxShadow(color: const Color(0xFF6D4DFF).withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPremium)
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'MAIS VENDIDO',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (isPremium) const SizedBox(height: 4),
            Text(
              nome,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.bold,
                color: isPremium ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  preco,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isPremium ? Colors.white : const Color(0xFF2962FF),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  periodo,
                  style: TextStyle(
                    fontSize: 14,
                    color: isPremium ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ),
            if (notaAnual != null && notaAnual.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notaAnual,
                style: TextStyle(
                  fontSize: 12,
                  color: isPremium ? Colors.white70 : Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Divider(color: isPremium ? Colors.white24 : Colors.grey.shade300),
            ...beneficios.map((b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: isPremium ? Colors.greenAccent : Colors.green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b,
                          style: TextStyle(
                            color: isPremium ? Colors.white : Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildPaymentSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Forma de Pagamento',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
        ),
        const SizedBox(height: 8),
        Text(
          'Selecione Pix ou Cartão de Crédito para continuar.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 15),
        _paymentTile(
          'Pix (Aprovação Instantânea)',
          Icons.qr_code_2_rounded,
          Colors.teal,
          selected: _formaPagamento == 'pix',
          onTap: () => setState(() => _formaPagamento = 'pix'),
        ),
        const SizedBox(height: 10),
        _paymentTile(
          _isAnual ? 'Cartão de crédito (anual em até 6x no Mercado Pago)' : 'Cartão de crédito',
          Icons.credit_card_rounded,
          Colors.blue,
          selected: _formaPagamento == 'cartao',
          onTap: () => setState(() => _formaPagamento = 'cartao'),
        ),
        const SizedBox(height: 30),
        // CTA moderno com gradiente e brilho.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF2962FF), Color(0xFF6D4DFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2962FF).withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _acceptedPlanChangeTerms ? _confirmarPagamento : _onAssinarSemAceite,
              child: Container(
                width: double.infinity,
                height: 56,
                alignment: Alignment.center,
                child: Text(
                  _acceptedPlanChangeTerms ? 'Assinar agora' : 'Assinar agora (aceite o termo acima)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onAssinarSemAceite() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Marque a confirmação no quadro acima e, se quiser, leia o termo completo antes de pagar.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blueGrey.shade800,
        action: SnackBarAction(
          label: 'Ver termo',
          textColor: Colors.amberAccent,
          onPressed: () => showPlanChangeContractBottomSheet(context),
        ),
      ),
    );
  }

  Widget _paymentTile(String title, IconData icon, Color color, {required bool selected, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? const Color(0xFF2962FF) : Colors.transparent,
            width: selected ? 2.5 : 0,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10),
            if (selected) BoxShadow(color: const Color(0xFF2962FF).withOpacity(0.15), blurRadius: 12),
          ],
        ),
        child: ListTile(
          leading: Icon(icon, color: color, size: 26),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? const Color(0xFF2962FF) : Colors.grey,
            size: 26,
          ),
        ),
      ),
      ),
    );
  }

  void _confirmarPagamento() {
    if (_promoData != null && _promoIdFromUrl != null) {
      final promo = PublicDivulgacaoPromo.fromLoadedPromotionDoc(_promoIdFromUrl!, _promoData!);
      openPublicPromoMercadoPagoCheckout(context, promo);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          initialPlanCode: _getPlanCode(),
          initialPromoId: _promoIdFromUrl,
          paymentMethod: _formaPagamento,
        ),
      ),
    );
  }
}
