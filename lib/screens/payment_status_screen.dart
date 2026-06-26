import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/functions_service.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../theme/app_colors.dart';
import '../utils/navigator_safe_pop.dart';
import '../widgets/checkout_embed_web.dart';

/// Checkout: Pix (código copia e cola no app) ou Cartão (WebView no app — não abre o app Mercado Pago).
class CheckoutScreen extends StatefulWidget {
  final String? initialPlanCode;
  /// Documento em `promotions/{id}` — enviado ao MP em metadata; webhook aplica duração e estoque.
  final String? initialPromoId;
  /// 'pix' = gera PIX e mostra código para copiar; 'cartao' = abre checkout em WebView no app.
  final String? paymentMethod;

  const CheckoutScreen({super.key, this.initialPlanCode, this.initialPromoId, this.paymentMethod});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late String _planCode;
  String? _promoId;
  bool _loading = true;
  String? _error;
  // Pix
  String? _pixCode;
  String? _pixQrBase64;
  /// Valor enviado ao Mercado Pago (retorno da function — confere promo vs plano).
  double? _pixAmountBrl;
  // Cartão: URL do checkout para abrir dentro do app
  String? _checkoutUrl;

  @override
  void initState() {
    super.initState();
    final code = (widget.initialPlanCode ?? '').trim().toLowerCase();
    if (code == 'premium_monthly' || code == 'premium_annual') {
      _planCode = code;
    } else {
      _planCode = 'premium_monthly';
    }
    _promoId = widget.initialPromoId?.trim();
    if (kIsWeb && (_promoId == null || _promoId!.isEmpty)) {
      final q = Uri.base.queryParameters['promo']?.trim();
      if (q != null && q.isNotEmpty) _promoId = q;
    }
    final method = (widget.paymentMethod ?? '').toLowerCase();
    if (method == 'pix') {
      _gerarPix();
    } else if (method == 'cartao') {
      _abrirCheckoutCartao();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _gerarPix() async {
    setState(() { _loading = true; _error = null; _pixCode = null; });
    try {
      final res = await FunctionsService().createPixPayment(plan: _planCode, promoId: _promoId);
      final code = (res['qr_code'] ?? res['ticket_url'] ?? '').toString();
      if (code.isEmpty) throw Exception('Código PIX não retornado');
      if (mounted) {
        final rawAmt = res['transaction_amount'];
        double? amt;
        if (rawAmt is num) {
          amt = rawAmt.toDouble();
        } else if (rawAmt != null) {
          amt = double.tryParse(rawAmt.toString().replaceAll(',', '.'));
        }
        setState(() {
          _pixCode = code;
          _pixQrBase64 = res['qr_code_base64']?.toString();
          _pixAmountBrl = amt;
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FocusManager.instance.primaryFocus?.unfocus();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
          _loading = false;
        });
      }
    }
  }

  String _extractError(dynamic e) {
    if (e is FirebaseFunctionsException) {
      final msg = (e.message ?? e.code).toString();
      if (msg.isNotEmpty) return msg;
    }
    final s = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
    return s.isNotEmpty ? s : 'Erro ao processar pagamento. Tente novamente.';
  }

  Future<void> _abrirCheckoutCartao() async {
    setState(() { _loading = true; _error = null; _checkoutUrl = null; });
    try {
      final res = await FunctionsService().createCheckout(plan: _planCode, promoId: _promoId);
      final url = (res['init_point'] ?? res['sandbox_init_point'] ?? '').toString();
      if (url.isEmpty) throw Exception('Link de pagamento não disponível');
      if (mounted) {
        setState(() {
          _checkoutUrl = url;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _extractError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cartão: checkout na mesma tela — iframe na web, WebView no app (dados do cartão, parcelas e pagar aqui).
    if (_checkoutUrl != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          title: const Text('Dados do cartão'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => popOrGoHome(context),
          ),
        ),
        body: SafeArea(
          top: true,
          bottom: true,
          left: true,
          right: true,
          child: kIsWeb
              ? buildCheckoutEmbed(_checkoutUrl!)
              : WebViewWidget(
                  controller: WebViewController()
                    ..setJavaScriptMode(JavaScriptMode.unrestricted)
                    ..loadRequest(Uri.parse(_checkoutUrl!)),
                ),
        ),
      );
    }

    // PIX: código copia e cola (sem SelectableText na web — evita foco/hit-test preso com SelectionArea raiz).
    if (_pixCode != null) {
      final amt = _pixAmountBrl;
      final amtLabel = amt != null
          ? 'Valor deste PIX: R\$ ${amt.toStringAsFixed(2).replaceAll('.', ',')}'
          : null;
      return PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0E21),
          appBar: AppBar(
            title: const Text('Pagar com PIX'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                popOrGoHome(context);
              },
            ),
          ),
          body: SafeArea(
            top: true,
            bottom: true,
            left: true,
            right: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF14B8A6), Color(0xFF059669)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF14B8A6).withValues(alpha: 0.4),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.pix_rounded, size: 38, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Pague com PIX',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Copie o código PIX e cole no app do seu banco para pagar. Não é preciso abrir o Mercado Pago.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                  if (amtLabel != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          amtLabel,
                          style: const TextStyle(
                            color: Color(0xFF2DD4BF),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_pixQrBase64 != null && _pixQrBase64!.isNotEmpty)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Image.memory(
                          base64Decode(_pixQrBase64!),
                          width: 220,
                          height: 220,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1E33),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.5)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        _pixCode!,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF14B8A6), Color(0xFF059669)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF14B8A6).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _pixCode ?? ''));
                        FocusManager.instance.primaryFocus?.unfocus();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código PIX copiado. Cole no app do seu banco.')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copiar código PIX', style: TextStyle(fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      popOrGoHome(context);
                    },
                    child: const Text(
                      'Voltar aos planos',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Após pagar, seu plano será ativado em instantes. Você pode fechar esta tela.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Erro ao gerar PIX
    if (_error != null && (widget.paymentMethod ?? '').toLowerCase() == 'pix') {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          title: const Text('PIX'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => popOrGoHome(context),
          ),
        ),
        body: SafeArea(
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _gerarPix(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              ),
            ],
          ),
        ),
        ),
      );
    }

    // Erro ao gerar checkout cartão
    if (_error != null && (widget.paymentMethod ?? '').toLowerCase() == 'cartao') {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          title: const Text('Pagamento com cartão'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => popOrGoHome(context),
          ),
        ),
        body: SafeArea(
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.credit_card_off_rounded, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                'Verifique se o Mercado Pago está configurado e tente novamente. '
                'Se o banco recusar, use PIX ou tente outro cartão/dispositivo que costuma usar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _abrirCheckoutCartao(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              ),
            ],
          ),
        ),
        ),
      );
    }

    // Loading
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          title: const Text('Assinar plano'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => popOrGoHome(context),
          ),
        ),
        body: const SafeArea(
          child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Gerando pagamento...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        ),
      );
    }

    // Tela sem método definido: escolher plano e depois Pix ou Cartão
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return StreamBuilder<MpCheckoutPricingSnapshot>(
      stream: MpCheckoutPricingService.watch(),
      initialData: MpCheckoutPricingSnapshot.defaults(),
      builder: (context, pricingSnap) {
        final plans =
            (pricingSnap.data ?? MpCheckoutPricingSnapshot.defaults()).premiumPlanRowsForCheckout();
        return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        title: const Text('Assinar plano'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => popOrGoHome(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Escolha o plano e a forma de pagamento. PIX: código aqui no app. Cartão: tela segura aqui mesmo.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ...plans.map((p) {
              final selected = _planCode == p.code;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _planCode = p.code),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accent.withValues(alpha: 0.15) : const Color(0xFF1D1E33),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? AppColors.accent : Colors.white.withValues(alpha: 0.06),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: selected ? AppColors.accent : Colors.white54,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(p.price, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                              if (p.subtitle.isNotEmpty)
                                Text(p.subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF14B8A6), Color(0xFF059669)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF14B8A6).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CheckoutScreen(
                      initialPlanCode: _planCode,
                      initialPromoId: _promoId,
                      paymentMethod: 'pix',
                    ),
                  ),
                ),
                icon: const Icon(Icons.pix_rounded),
                label: const Text('Pagar com PIX (código aqui)', style: TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF2962FF), Color(0xFF6D4DFF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2962FF).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CheckoutScreen(
                      initialPlanCode: _planCode,
                      initialPromoId: _promoId,
                      paymentMethod: 'cartao',
                    ),
                  ),
                ),
                icon: const Icon(Icons.credit_card_rounded),
                label: const Text('Pagar com cartão (tela aqui)', style: TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
      },
    );
  }
}
