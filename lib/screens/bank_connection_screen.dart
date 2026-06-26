import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';

import '../constants/pluggy_sync_schedule.dart';
import '../constants/open_finance_br_institutions.dart';
import '../services/bank_connection_manager.dart';
import '../services/pluggy_service.dart';
import '../theme/app_colors.dart';
import '../widgets/open_finance_entitlement_guard.dart';
import '../widgets/premium_pro_value_copy.dart';
import '../utils/debounced_text_controller.dart';
import '../utils/firestore_user_doc_id.dart';

/// Seleção de instituição + fluxo seguro (Pluggy/Open Finance) — integração real via widget/link nas Cloud Functions.
class BankConnectionScreen extends StatefulWidget {
  final String uid;
  /// E-mail da conta (define limite incluso: 2 ou 5 VIP antes do custo extra).
  final String? accountEmail;
  /// `users.premiumProIncludedBankConnections` (opcional, painel Admin).
  final int? includedBankSlotsOverride;

  const BankConnectionScreen({
    super.key,
    required this.uid,
    this.accountEmail,
    this.includedBankSlotsOverride,
  });

  @override
  State<BankConnectionScreen> createState() => _BankConnectionScreenState();
}

class _BankConnectionScreenState extends State<BankConnectionScreen> {
  final _searchCtrl = TextEditingController();
  VoidCallback? _detachSearchListener;
  bool _opening = false;
  StreamSubscription<fa.User?>? _authUidSub;

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    // Debounce: lista de instituições é grande (Open Finance BR).
    _detachSearchListener = attachDebouncedRebuild(_searchCtrl, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authUidSub?.cancel();
    _detachSearchListener?.call();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<OpenFinanceBrInstitution> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    List<OpenFinanceBrInstitution> base;
    if (q.isEmpty) {
      base = kOpenFinanceBrInstitutions.toList();
      base.sort((a, b) {
        final ap = kOpenFinancePopularInstitutionIds.contains(a.id) ? 0 : 1;
        final bp = kOpenFinancePopularInstitutionIds.contains(b.id) ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return base;
    }
    base = kOpenFinanceBrInstitutions.where((b) {
      if (b.name.toLowerCase().contains(q)) return true;
      return b.searchTokens.any((t) => t.contains(q) || q.contains(t));
    }).toList();
    base.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return base;
  }

  Future<void> _onSelectBank(OpenFinanceBrInstitution bank) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final ok = await BankConnectionManager.ensureCanOpenConnectionFlow(
        context,
        firestoreUserDocIdForAppShell(widget.uid),
        accountEmail: widget.accountEmail,
        includedSlotsOverride: widget.includedBankSlotsOverride,
      );
      if (!ok || !mounted) return;

      final go = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PluggyConsentSheet(bankName: bank.name),
      );
      if (go != true || !mounted) return;
    } catch (e, st) {
      if (mounted) {
        debugPrint('Conectar banco (início do fluxo): $e $st');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível iniciar a conexão. Tente de novo. ($e)')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _opening = false);
    }

    if (!mounted) return;
    try {
      final pluggyResult = await PluggyService.instance.openConnectWebView(context);
      if (!mounted) return;
      if (pluggyResult == null || pluggyResult['ok'] != true) {
        final extra = (pluggyResult?['message'] != null) ? ' ${pluggyResult!['message']}' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              extra.isEmpty
                  ? 'Conexão cancelada ou não concluída.'
                  : 'Não concluiu. $extra',
            ),
          ),
        );
        return;
      }

      final itemId = _parsePluggyItemId(pluggyResult['data']) ??
          'pending_pluggy_${DateTime.now().millisecondsSinceEpoch}';

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(widget.uid))
          .collection('bank_connections')
          .doc();
      await ref.set({
        'provider': 'pluggy',
        'bankName': bank.name,
        'institutionId': bank.id,
        'status': 'connected',
        'itemId': itemId,
        'lastSync': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${bank.name} — banco conectado com sucesso.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (mounted) {
        debugPrint('Conectar banco (Pluggy/Firestore): $e $st');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao concluir a conexão. Tente de novo. ($e)')),
        );
      }
    }
  }

  String? _parsePluggyItemId(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final item = m['item'];
    if (item is Map && item['id'] != null) return item['id'].toString().trim();
    if (m['itemId'] != null) return m['itemId'].toString().trim();
    if (m['id'] != null) return m['id'].toString().trim();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return OpenFinanceEntitlementGuard(
      uid: widget.uid,
      appBarTitle: 'Conectar banco',
      entitledBuilder: (context, _) {
        return Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        title: const Text('Conectar banco'),
      ),
      body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: AppColors.primary.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_user_outlined, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Open Finance (Pluggy ou similar)',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Você não informa senha do app aqui. Ao continuar, abriremos o ambiente seguro da instituição '
                        'para você autorizar extrato, cartão, Pix e saldo — conforme o que o banco permitir na API.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const PremiumProDiferencialChips(),
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  PluggySyncSchedule.connectFlowNotice,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
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
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
                  labelText: 'Digite o nome do seu banco',
                  hintText: 'Ex.: Nubank, Itaú, Caixa…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A cobertura real depende do agregador (Pluggy, Belvo, etc.): na prática a maioria dos bancos '
                'usados no Brasil fica disponível. Com a busca vazia, os mais populares aparecem primeiro.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
              ),
              const SizedBox(height: 12),
              Text(
                'Instituições',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Nenhum banco encontrado. Tente outro nome.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...list.map((b) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        child: Icon(Icons.account_balance_rounded, color: AppColors.primary),
                      ),
                      title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                        'Login seguro no site do banco · você autoriza o compartilhamento',
                        style: TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _onSelectBank(b),
                    ),
                  );
                }),
            ],
          ),
        ),
        if (_opening)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.6),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('A preparar conexão…', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
      },
    );
  }
}

class _PluggyConsentSheet extends StatelessWidget {
  final String bankName;

  const _PluggyConsentSheet({required this.bankName});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.52,
      minChildSize: 0.38,
      maxChildSize: 0.92,
      builder: (context, scroll) {
        return Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                bankName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Próximo passo: abrir o fluxo oficial Pluggy Connect (Open Finance) numa janela segura. '
                'Faça login e autorize o compartilhamento diretamente no ambiente do banco.',
                style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Text('Dados que você pode autorizar:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...['Extrato e movimentações', 'Cartão de crédito/débito', 'Pix', 'Saldo e limites']
                  .map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t, style: const TextStyle(fontSize: 14))),
                          ],
                        ),
                      )),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Autorizar e conectar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        );
      },
    );
  }
}
