import 'package:flutter/material.dart';

import '../models/finance_account.dart';
import 'finance_account_card_colors.dart';

/// Estilo visual de uma conta/cartão (cores, ícone e rótulo do tipo).
class FinanceAccountVisual {
  final List<Color> gradient;
  final IconData icon;
  final String badgeLabel;
  final bool isCreditCardStyle;
  final Color badgeColor;
  final Color badgeTextColor;

  const FinanceAccountVisual({
    required this.gradient,
    required this.icon,
    required this.badgeLabel,
    this.isCreditCardStyle = false,
    this.badgeColor = Colors.white24,
    this.badgeTextColor = Colors.white,
  });

  /// Cor principal (primeiro tom do gradiente) para chips, bordas e ícones.
  Color get color => gradient.first;
}

/// Cores e rótulos distintos: conta corrente/poupança (débito) vs cartão de crédito.
FinanceAccountVisual financeAccountVisualFor(FinanceAccount account) {
  final preset = account.preset;
  final bankC1 = preset?.color1 ?? const Color(0xFF1E3A5F);
  final bankC2 = preset?.color2 ?? const Color(0xFF0F172A);
  final custom = financeAccountCardColorById(account.cardColorId);

  List<Color> gradientFor(List<Color> defaultGradient) {
    if (custom == null) return defaultGradient;
    if (account.productType == FinanceAccount.kCard) {
      return [
        Color.lerp(custom.color1, const Color(0xFF0F172A), 0.15)!,
        Color.lerp(custom.color2, const Color(0xFF312E81), 0.12)!,
        custom.color2!,
      ];
    }
    return custom.gradient;
  }

  switch (account.productType) {
    case FinanceAccount.kCard:
      return FinanceAccountVisual(
        gradient: gradientFor([
          Color.lerp(const Color(0xFF0F172A), bankC1, 0.22)!,
          Color.lerp(const Color(0xFF1E1B4B), bankC2, 0.28)!,
          const Color(0xFF312E81),
        ]),
        icon: Icons.credit_card_rounded,
        badgeLabel: 'Crédito',
        isCreditCardStyle: true,
        badgeColor: const Color(0xFFFBBF24).withValues(alpha: 0.22),
        badgeTextColor: const Color(0xFFFDE68A),
      );
    case FinanceAccount.kSavings:
      return FinanceAccountVisual(
        gradient: gradientFor([
          Color.lerp(bankC1, const Color(0xFF059669), 0.32)!,
          Color.lerp(bankC2, const Color(0xFF047857), 0.25)!,
        ]),
        icon: Icons.savings_outlined,
        badgeLabel: 'Poupança',
        badgeColor: Colors.white.withValues(alpha: 0.18),
        badgeTextColor: Colors.white,
      );
    case FinanceAccount.kBankAndCard:
      return FinanceAccountVisual(
        gradient: gradientFor([
          bankC1,
          Color.lerp(bankC2, const Color(0xFF4F46E5), 0.42)!,
        ]),
        icon: Icons.account_balance_wallet_rounded,
        badgeLabel: 'Conta + cartão',
        badgeColor: Colors.white.withValues(alpha: 0.18),
        badgeTextColor: Colors.white,
      );
    case FinanceAccount.kChecking:
    default:
      return FinanceAccountVisual(
        gradient: gradientFor([bankC1, bankC2]),
        icon: preset?.icon ?? Icons.account_balance_rounded,
        badgeLabel: 'Corrente',
        badgeColor: Colors.white.withValues(alpha: 0.18),
        badgeTextColor: Colors.white,
      );
  }
}

/// Fundo decorativo premium para cartões de crédito (listras diagonais suaves).
class FinanceCreditCardPattern extends StatelessWidget {
  final Color stripeColor;

  const FinanceCreditCardPattern({super.key, this.stripeColor = const Color(0xFFFBBF24)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CreditStripePainter(stripeColor.withValues(alpha: 0.14)),
      child: const SizedBox.expand(),
    );
  }
}

class _CreditStripePainter extends CustomPainter {
  _CreditStripePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const gap = 14.0;
    for (var x = -size.height; x < size.width + size.height; x += gap) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CreditStripePainter oldDelegate) => oldDelegate.color != color;
}
