import 'package:flutter/material.dart';

import '../services/bank_connection_manager.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../services/pro_open_finance_config_service.dart';
import 'payment_status_screen.dart';

/// Compra de +1 conexão Open Finance (além do incluso no PRO) — Mercado Pago (PIX ou cartão).
class ExtraBankConnectionPaywallScreen extends StatefulWidget {
  final String uid;
  final String? accountEmail;
  final int? includedSlotsOverride;

  const ExtraBankConnectionPaywallScreen({
    super.key,
    required this.uid,
    this.accountEmail,
    this.includedSlotsOverride,
  });

  @override
  State<ExtraBankConnectionPaywallScreen> createState() => _ExtraBankConnectionPaywallScreenState();
}

class _ExtraBankConnectionPaywallScreenState extends State<ExtraBankConnectionPaywallScreen> {
  int? _initialCap;
  bool? _canPurchaseMore;
  int _maxTotal = ProOpenFinanceConfig.defaultMaxTotal;
  bool _loadingCap = true;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCap();
  }

  Future<void> _loadCap() async {
    try {
      final cfg = await ProOpenFinanceConfigService.getOnce();
      final c = await BankConnectionManager.totalConnectionCapacity(
        widget.uid,
        accountEmail: widget.accountEmail,
        includedSlotsOverride: widget.includedSlotsOverride,
      );
      final can = await BankConnectionManager.canPurchaseAnotherExtraSlot(
        widget.uid,
        accountEmail: widget.accountEmail,
        includedSlotsOverride: widget.includedSlotsOverride,
      );
      if (mounted) {
        setState(() {
          _initialCap = c;
          _maxTotal = cfg.maxTotalBankConnections;
          _canPurchaseMore = can;
          _loadingCap = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loadingCap = false;
        });
      }
    }
  }

  Future<void> _openCheckout(String planCode, String method) async {
    if (_confirming) return;
    setState(() {
      _error = null;
      _confirming = true;
    });
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CheckoutScreen(
            initialPlanCode: planCode,
            paymentMethod: method,
          ),
        ),
      );
      if (!mounted) return;
      await _pollUnlocked();
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  Future<void> _pollUnlocked() async {
    final cap0 = _initialCap;
    if (cap0 == null) {
      if (mounted) await _loadCap();
    }
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (mounted && DateTime.now().isBefore(end)) {
      final c = await BankConnectionManager.totalConnectionCapacity(
        widget.uid,
        accountEmail: widget.accountEmail,
        includedSlotsOverride: widget.includedSlotsOverride,
      );
      if (c > (cap0 ?? 0)) {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ainda não encontramos a liberação. Se o pagamento foi aprovado, aguarde ~1 minuto e tente conectar o banco de novo.',
          ),
        ),
      );
    }
  }

  Future<void> _retryConfirm() async {
    setState(() => _confirming = true);
    try {
      await _pollUnlocked();
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conexão bancária extra'),
        elevation: 0,
      ),
      body: _loadingCap
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : StreamBuilder<MpCheckoutPricingSnapshot>(
                  stream: MpCheckoutPricingService.watch(),
                  initialData: MpCheckoutPricingSnapshot.defaults(),
                  builder: (context, snap) {
                    final p = snap.data ?? MpCheckoutPricingSnapshot.defaults();
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.account_balance_rounded, size: 48, color: Color(0xFF0D9488)),
                          const SizedBox(height: 12),
                          Text(
                            'Limite de bancos do plano',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Você já usou as conexões incluídas no PRO. Pague um add-on para liberar '
                            'mais uma (3ª, 4ª, …). Cada pagamento libera exatamente 1 conexão adicional, '
                            'válida pelo período escolhido.',
                            textAlign: TextAlign.center,
                            style: TextStyle(height: 1.4),
                          ),
                          if (_initialCap != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Capacidade atual: $_initialCap de no máximo $_maxTotal conexão(ões) simultânea(s).',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                            ),
                          ],
                          if (_canPurchaseMore == false) ...[
                            const SizedBox(height: 16),
                            Material(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.orange.shade900),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Não é possível adicionar mais conexões pagas: o teto de $_maxTotal ligação(ões) '
                                        'por conta (definido pelo WISDOMAPP) já foi atingido. Remova uma conexão existente se quiser trocar de banco.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.35,
                                          color: Colors.brown.shade900,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          _OptionCard(
                            title: 'Mensal',
                            line: '${MpCheckoutPricingSnapshot.formatBrl(p.extraBankConnectionMonthly)}/mês por conexão extra (30 dias)',
                            busy: _confirming,
                            enabled: _canPurchaseMore != false,
                            onPix: () => _openCheckout('extra_bank_connection_monthly', 'pix'),
                            onCartao: () => _openCheckout('extra_bank_connection_monthly', 'cartao'),
                          ),
                          const SizedBox(height: 14),
                          _OptionCard(
                            title: 'Anual',
                            line: '${MpCheckoutPricingSnapshot.formatBrl(p.extraBankConnectionAnnual)}/ano por conexão extra (12 meses)',
                            busy: _confirming,
                            enabled: _canPurchaseMore != false,
                            onPix: () => _openCheckout('extra_bank_connection_annual', 'pix'),
                            onCartao: () => _openCheckout('extra_bank_connection_annual', 'cartao'),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _confirming ? null : _retryConfirm,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Já paguei — verificar de novo'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _confirming ? null : () => Navigator.of(context).pop(false),
                            child: const Text('Agora não'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String title;
  final String line;
  final bool busy;
  final bool enabled;
  final VoidCallback onPix;
  final VoidCallback onCartao;

  const _OptionCard({
    required this.title,
    required this.line,
    required this.busy,
    this.enabled = true,
    required this.onPix,
    required this.onCartao,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.teal.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 6),
            Text(line, style: TextStyle(color: Colors.blueGrey.shade800, height: 1.35)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: (busy || !enabled) ? null : onPix,
                    child: const Text('PIX'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: (busy || !enabled) ? null : onCartao,
                    child: const Text('Cartão'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
