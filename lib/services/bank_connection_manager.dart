import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/premium_pro_limits.dart';
import '../screens/escolha_plano_page.dart';
import 'pro_open_finance_config_service.dart';

/// Regras de negócio para conexões bancárias (legado) + limite por conta.
class BankConnectionManager {
  BankConnectionManager._();

  static Future<int> countActiveConnections(String uid) async {
    try {
      final r = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('bank_connections')
          .count()
          .get();
      return r.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Conexões extra pagas ainda com `expiresAt` no futuro (1 doc = 1 slot, Mercado Pago + webhook).
  static Future<int> countValidExtraEntitlementSlots(String uid) async {
    final now = Timestamp.now();
    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('bank_connection_entitlements')
          .where('expiresAt', isGreaterThan: now)
          .get();
      return q.docs.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<ProOpenFinanceConfig> _proConfig() async {
    try {
      final s = await FirebaseFirestore.instance.collection('app_config').doc('pro_open_finance').get();
      return ProOpenFinanceConfig.fromFirestore(s.data());
    } catch (_) {
      return ProOpenFinanceConfig.fromFirestore(null);
    }
  }

  static Future<int> totalConnectionCapacity(
    String uid, {
    String? accountEmail,
    int? includedSlotsOverride,
  }) async {
    final cfg = await _proConfig();
    final inc = PremiumProLimits.includedBankConnections(
      email: accountEmail,
      adminPerUserOverride: includedSlotsOverride,
    );
    final x = await countValidExtraEntitlementSlots(uid);
    return ProOpenFinanceConfigService.effectiveConnectionCapacity(
      includedSlots: inc,
      validExtraEntitlementCount: x,
      maxTotalBankConnections: cfg.maxTotalBankConnections,
    );
  }

  static Future<bool> canPurchaseAnotherExtraSlot(
    String uid, {
    String? accountEmail,
    int? includedSlotsOverride,
  }) async {
    final cfg = await _proConfig();
    final inc = PremiumProLimits.includedBankConnections(
      email: accountEmail,
      adminPerUserOverride: includedSlotsOverride,
    );
    final x = await countValidExtraEntitlementSlots(uid);
    return ProOpenFinanceConfigService.canPurchaseAnotherExtra(
      includedSlots: inc,
      validExtraEntitlementCount: x,
      maxTotalBankConnections: cfg.maxTotalBankConnections,
    );
  }

  /// Antes de abrir o fluxo Pluggy/Open Finance. Retorna `true` se pode continuar.
  static Future<bool> ensureCanOpenConnectionFlow(
    BuildContext context,
    String uid, {
    String? accountEmail,
    int? includedSlotsOverride,
  }) async {
    final n = await countActiveConnections(uid);
    final cap = await totalConnectionCapacity(
      uid,
      accountEmail: accountEmail,
      includedSlotsOverride: includedSlotsOverride,
    );
    if (n < cap) return true;
    if (!context.mounted) return false;
    final canBuy = await canPurchaseAnotherExtraSlot(
      uid,
      accountEmail: accountEmail,
      includedSlotsOverride: includedSlotsOverride,
    );
    if (!context.mounted) return false;
    final maxT = (await _proConfig()).maxTotalBankConnections;
    if (!context.mounted) return false;
    return _showLimitAndMaybePay(
      context,
      uid: uid,
      accountEmail: accountEmail,
      includedSlotsOverride: includedSlotsOverride,
      canPurchaseExtra: canBuy,
      maxTotalConnections: maxT,
      includedSlots: PremiumProLimits.includedBankConnections(
        email: accountEmail,
        adminPerUserOverride: includedSlotsOverride,
      ),
    );
  }

  static Future<bool> _showLimitAndMaybePay(
    BuildContext context, {
    required String uid,
    String? accountEmail,
    int? includedSlotsOverride,
    required bool canPurchaseExtra,
    required int maxTotalConnections,
    required int includedSlots,
  }) async {
    final root = context;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.orange.shade800, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Limite de conexões',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                canPurchaseExtra
                    ? 'Atingiu o número de bancos ligados permitido nesta conta. '
                        'Não é possível comprar vagas extra — novas ligações automáticas não estão à venda. '
                        'Use o plano Premium com lançamentos manuais ou remova uma conexão antiga em Finanças, se existir.'
                    : 'O WISDOMAPP permite no máximo $maxTotalConnections conexões bancárias '
                        'por conta (incluindo o plano e eventuais extensões já existentes). '
                        'Remova um banco em «Conexões» se precisar associar outro.',
                style: const TextStyle(height: 1.45, fontSize: 14),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (root.mounted) {
                    Navigator.of(root).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const EscolhaPlanoPage()),
                    );
                  }
                },
                child: const Text('Ver plano Premium'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      ),
    );
    return false;
  }
}
