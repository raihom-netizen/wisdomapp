import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import '../widgets/finance_confirm_payment_sheet.dart';
import '../widgets/finance_credit_card_fatura_sheet.dart';
import '../widgets/finance_premium_ui.dart';

/// Callbacks compartilhados entre Financeiro e Painel para o sheet da fatura.
class FinanceFaturaSheetHandlers {
  final Future<void> Function(
    BuildContext context,
    List<String> docIds, {
    required FinanceConfirmPaymentSheetResult result,
    required String cardAccountId,
  }) onConfirmFaturaPayment;
  final Future<void> Function(
    BuildContext context,
    String docId,
    Map<String, dynamic> current,
    String type,
  ) onEditTransaction;
  final Future<void> Function(BuildContext context, String docId) onDeleteTransaction;
  final Future<void> Function(BuildContext context, List<String> docIds) onDeleteBatch;
  final Future<void> Function(BuildContext context, String docId) onAttachReceipt;

  const FinanceFaturaSheetHandlers({
    required this.onConfirmFaturaPayment,
    required this.onEditTransaction,
    required this.onDeleteTransaction,
    required this.onDeleteBatch,
    required this.onAttachReceipt,
  });
}

/// Abre a fatura do cartão (ou escolhe qual cartão se houver mais de um).
class FinanceFaturaEmAbertoHub {
  FinanceFaturaEmAbertoHub._();

  static Future<void> open(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required List<FinanceAccount> allAccounts,
    required Map<String, double> faturaByCardId,
    required FinanceFaturaSheetHandlers handlers,
    Set<String> optimisticPaidIds = const {},
  }) async {
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return;
    }

    final cards = FinanceAccountBalanceUtils.creditCardProducts(allAccounts);
    if (cards.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cadastre um cartão de crédito em Bancos e cartões.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (cards.length == 1) {
      await FinanceCreditCardFaturaSheet.show(
        context,
        uid: uid,
        profile: profile,
        cardAccount: cards.first,
        allAccounts: allAccounts,
        optimisticPaidIds: optimisticPaidIds,
        onConfirmFaturaPayment: handlers.onConfirmFaturaPayment,
        onEditTransaction: handlers.onEditTransaction,
        onDeleteTransaction: handlers.onDeleteTransaction,
        onDeleteBatch: handlers.onDeleteBatch,
        onAttachReceipt: handlers.onAttachReceipt,
      );
      return;
    }

    if (!context.mounted) return;
    final total = FinanceAccountBalanceUtils.totalFaturaEmAberto(faturaByCardId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _FinanceFaturaCardPickerSheet(
        cards: cards,
        faturaByCardId: faturaByCardId,
        totalFatura: total,
        onCardSelected: (card) async {
          Navigator.pop(sheetCtx);
          if (!context.mounted) return;
          await FinanceCreditCardFaturaSheet.show(
            context,
            uid: uid,
            profile: profile,
            cardAccount: card,
            allAccounts: allAccounts,
            optimisticPaidIds: optimisticPaidIds,
            onConfirmFaturaPayment: handlers.onConfirmFaturaPayment,
            onEditTransaction: handlers.onEditTransaction,
            onDeleteTransaction: handlers.onDeleteTransaction,
            onDeleteBatch: handlers.onDeleteBatch,
            onAttachReceipt: handlers.onAttachReceipt,
          );
        },
      ),
    );
  }
}

/// Lista colorida de cartões — escolha rápida antes de abrir a fatura.
class _FinanceFaturaCardPickerSheet extends StatelessWidget {
  const _FinanceFaturaCardPickerSheet({
    required this.cards,
    required this.faturaByCardId,
    required this.totalFatura,
    required this.onCardSelected,
  });

  final List<FinanceAccount> cards;
  final Map<String, double> faturaByCardId;
  final double totalFatura;
  final ValueChanged<FinanceAccount> onCardSelected;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    const purpleDark = Color(0xFF5B21B6);

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.38,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: financePremiumSheetDecoration(surfaceTint: purple),
          child: Column(
            children: [
              FinancePremiumSheetHeader(
                title: 'Escolha o cartão',
                subtitle: '${cards.length} cartões · Toque para ver fatura, editar e pagar',
                icon: Icons.credit_card_rounded,
                iconGradient: const [purple, Color(0xFF4F46E5)],
                onBack: () => Navigator.pop(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {},
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [purple, Color(0xFF6D28D9), purpleDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: purple.withValues(alpha: 0.32),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total em aberto',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(alpha: 0.88),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    CurrencyFormats.formatBRL(totalFatura),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final card = cards[i];
                    final fatura = faturaByCardId[card.id] ?? 0;
                    return _FinanceFaturaCardPickerTile(
                      account: card,
                      faturaAmount: fatura,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        onCardSelected(card);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FinanceFaturaCardPickerTile extends StatelessWidget {
  const _FinanceFaturaCardPickerTile({
    required this.account,
    required this.faturaAmount,
    required this.onTap,
  });

  final FinanceAccount account;
  final double faturaAmount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vis = financeAccountVisualFor(account);
    final hasFatura = faturaAmount > 0.0001;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: vis.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: vis.gradient.first.withValues(alpha: 0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                if (vis.isCreditCardStyle)
                  const Positioned.fill(child: FinanceCreditCardPattern()),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      FinanceBankBrandThumb(
                        preset: account.preset,
                        size: 48,
                        fallbackIcon: vis.icon,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: vis.badgeColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                vis.badgeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: vis.badgeTextColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasFatura
                                  ? 'Fatura em aberto · toque para pagar'
                                  : 'Sem lançamentos na fatura',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            CurrencyFormats.formatBRL(faturaAmount),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: hasFatura ? const Color(0xFFFDE68A) : Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Abrir',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card roxo: valor total da fatura em aberto (todos os cartões).
class FinanceFaturaEmAbertoBand extends StatelessWidget {
  const FinanceFaturaEmAbertoBand({
    super.key,
    required this.totalFatura,
    required this.lancamentoCount,
    required this.cartaoCount,
    required this.onTap,
    this.compact = false,
    this.hideAmount = false,
    this.amountFormatter,
  });

  final double totalFatura;
  final int lancamentoCount;
  final int cartaoCount;
  final VoidCallback onTap;
  final bool compact;
  final bool hideAmount;
  final String Function(double amount, {required bool hidden})? amountFormatter;

  String _formatAmount(double v) {
    if (amountFormatter != null) return amountFormatter!(v, hidden: hideAmount);
    return CurrencyFormats.formatBRL(v);
  }

  String _subtitle() {
    if (cartaoCount > 1) {
      if (totalFatura > 0.0001) {
        return '$lancamentoCount lançamento(s) · $cartaoCount cartões · Toque para escolher';
      }
      return '$cartaoCount cartões cadastrados · Toque para escolher';
    }
    if (totalFatura > 0.0001) {
      return '$lancamentoCount lançamento(s) · Toque para pagar';
    }
    return '$lancamentoCount lançamento(s) · Toque para ver fatura';
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    const purpleDark = Color(0xFF5B21B6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 18 : 20,
            vertical: compact ? 15 : 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [purple, purple.withValues(alpha: 0.92), purpleDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: purple.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.credit_card_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Fatura em aberto',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.98),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              FittedBox(
                child: Text(
                  _formatAmount(totalFatura),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
