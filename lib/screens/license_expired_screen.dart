import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/account_switch_flow.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../services/ios_payments_gate.dart';
import 'payment_status_screen.dart';

/// Tela de bloqueio quando a licença venceu e passou o período de carência (3 dias).
/// Valores exibidos seguem `app_config/mp_checkout_prices` (fallback: tabela padrão do app).
///
/// Layout Safari/iPhone vertical: SafeArea + SingleChildScrollView + ConstrainedBox(minHeight)
/// para evitar overflow e conteúdo atrás do notch. Sem OrientationBuilder (não fica lento).
class LicenseExpiredScreen extends StatelessWidget {
  final DateTime expirationDate;
  final VoidCallback? onRenew;
  final String? userEmail;
  /// Plano no Firestore no momento do bloqueio (renovação via Premium).
  final String blockedPlan;
  /// Sub-login: segue bloqueio da licença do titular (sem renovar por aqui).
  final bool isDelegateSession;
  final String? principalEmail;

  const LicenseExpiredScreen({
    super.key,
    required this.expirationDate,
    this.onRenew,
    this.userEmail,
    this.blockedPlan = 'premium',
    this.isDelegateSession = false,
    this.principalEmail,
  });

  static const _bgDark = Color(0xFF020617);
  static const _slate400 = Color(0xFF94a3b8);
  static const _slate500 = Color(0xFF64748b);
  static const _slate800 = Color(0xFF1e293b);
  static const _slate900 = Color(0xFF0f172a);
  static const _blue600 = Color(0xFF2563eb);
  void _openCheckout(BuildContext context, String planCode) {
    if (IosPaymentsGate.shouldHidePayments && IosPaymentsGate.isIosNative) {
      IosPaymentsGate.openReaderPlansInSafari(source: 'license_expired_screen');
      return;
    }
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _slate900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        top: false,
        bottom: true,
        left: true,
        right: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Forma de pagamento',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),
              _paymentOption(
                ctx,
                label: 'PIX (Aprovação Instantânea)',
                icon: Icons.qr_code_2_rounded,
                onTap: () {
                  Navigator.pop(ctx);
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CheckoutScreen(initialPlanCode: planCode, paymentMethod: 'pix'),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _paymentOption(
                ctx,
                label: 'Cartão de crédito (Mercado Pago)',
                icon: Icons.credit_card_rounded,
                onTap: () {
                  Navigator.pop(ctx);
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CheckoutScreen(initialPlanCode: planCode, paymentMethod: 'cartao'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentOption(BuildContext context, {required String label, required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: _slate800,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: _blue600, size: 28),
                const SizedBox(width: 16),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w500))),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = userEmail ?? '';
    final mq = MediaQuery.of(context);
    final insets = mq.padding;
    final isNarrow = mq.size.width < 360 || mq.size.shortestSide < 400;
    final isVeryNarrow = mq.size.width < 320 || mq.size.shortestSide < 360;
    final padding = isVeryNarrow ? 12.0 : (isNarrow ? 16.0 : 24.0);
    final bottomPadding = insets.bottom > 0 ? insets.bottom : 16.0;

    final viewHeight = mq.size.height - insets.top - insets.bottom;
    final minHeight = viewHeight > 0 ? viewHeight : 400.0;
    // Blindagem: sair somente pelo botão "Sair do sistema" (logout).
    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: _bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgDark, _slate900, _bgDark],
          ),
        ),
        child: SafeArea(
        top: true,
        bottom: true,
        left: true,
        right: true,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + bottomPadding),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                              blurRadius: 26,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.lock_clock_rounded, size: 44, color: Colors.white),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        isDelegateSession
                            ? 'Licença do titular bloqueada'
                            : 'Sistema Bloqueado',
                        style: TextStyle(
                          fontSize: isVeryNarrow ? 22 : (isNarrow ? 24 : 28),
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isDelegateSession
                            ? 'A licença de ${(principalEmail ?? email).isNotEmpty ? (principalEmail ?? email) : 'quem autorizou seu acesso'} está vencida ou sem pagamento. '
                                'O acesso fica bloqueado até o titular renovar — igual ao usuário principal. '
                                'Quando a licença for renovada, você entra automaticamente.'
                            : email.isNotEmpty
                                ? 'Renove sua licença ($email). Após o vencimento você teve ${UserProfile.licenseGracePeriodDays} dias de carência; agora o sistema está bloqueado até a renovação.'
                                : 'Renove sua licença. Você teve ${UserProfile.licenseGracePeriodDays} dias após o vencimento para pagar; agora só esta tela de renovação está disponível.',
                        style: TextStyle(fontSize: isVeryNarrow ? 14 : 15, color: _slate400, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      if (!isDelegateSession) ...[
                        StreamBuilder<MpCheckoutPricingSnapshot>(
                          stream: MpCheckoutPricingService.watch(),
                          initialData: MpCheckoutPricingSnapshot.defaults(),
                          builder: (context, snap) {
                            final p = snap.data ?? MpCheckoutPricingSnapshot.defaults();
                            return _buildPlanCardPremium(context, isNarrow, isVeryNarrow, p);
                          },
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Premium: escolha PIX ou cartão ao renovar mensal ou anual.',
                          style: TextStyle(fontSize: isVeryNarrow ? 11 : 12, color: _slate500, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Liberação imediata após aprovação do pagamento',
                          style: TextStyle(fontSize: isVeryNarrow ? 10 : 11, fontWeight: FontWeight.w700, color: _slate500, letterSpacing: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ] else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _slate900,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _slate800),
                          ),
                          child: Text(
                            'Peça ao titular da licença que renove o plano. '
                            'Assim que o pagamento for aprovado, seu acesso volta sozinho.',
                            style: TextStyle(
                              fontSize: isVeryNarrow ? 13 : 14,
                              color: _slate400,
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: TextButton.icon(
                          onPressed: () =>
                              AccountSwitchFlow.confirmAndOpenLogin(context),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Sair do sistema'),
                          style: TextButton.styleFrom(
                            foregroundColor: _slate400,
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ),
      ),
    ),
    );
  }

  Widget _buildPlanCardPremium(
    BuildContext context,
    bool isNarrow, [
    bool isVeryNarrow = false,
    MpCheckoutPricingSnapshot? pricing,
  ]) {
    final p = pricing ?? MpCheckoutPricingSnapshot.defaults();
    final cardPadding = isVeryNarrow ? 16.0 : (isNarrow ? 20.0 : 28.0);
    final fontSize = isVeryNarrow ? 10.0 : (isNarrow ? 11.0 : 13.0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF2962FF), Color(0xFF6D4DFF)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: _blue600.withValues(alpha: 0.4), blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -8,
            right: -8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'RECOMENDADO',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Plano Premium',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                p.licenseExpiredParagraph,
                style: TextStyle(fontSize: fontSize, color: Colors.white.withValues(alpha: 0.9), height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    MpCheckoutPricingSnapshot.formatBrl(p.premiumMonthly),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Text('/mês', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.normal)),
                ],
              ),
              const SizedBox(height: 16),
              if (isNarrow || isVeryNarrow) ...[
                _planButton(context, p.planButtonLabelMonthly(), 'premium_monthly', isNarrow, isVeryNarrow),
                const SizedBox(height: 10),
                _planButton(context, p.planButtonLabelAnnual(), 'premium_annual', isNarrow, isVeryNarrow),
              ] else
                Row(
                  children: [
                    Expanded(child: _planButton(context, p.planButtonLabelMonthly(), 'premium_monthly', isNarrow, isVeryNarrow)),
                    const SizedBox(width: 12),
                    Expanded(child: _planButton(context, p.planButtonLabelAnnual(), 'premium_annual', isNarrow, isVeryNarrow)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planButton(BuildContext context, String label, String planCode, bool isNarrow, [bool isVeryNarrow = false]) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: () {
          if (onRenew != null) {
            onRenew!();
          } else {
            _openCheckout(context, planCode);
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _blue600,
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.2),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: isVeryNarrow ? 11 : (isNarrow ? 12 : 13), fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }
}
