import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:intl/intl.dart';

import '../services/pro_open_finance_config_service.dart';
import '../theme/app_colors.dart';

/// Admin: teto global de conexões + listagem de add-ons (Mercado Pago) por utilizador.
class AdminOpenFinanceExtrasTab extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;
  final String currentAdminUid;

  const AdminOpenFinanceExtrasTab({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
    required this.currentAdminUid,
  });

  @override
  State<AdminOpenFinanceExtrasTab> createState() => _AdminOpenFinanceExtrasTabState();
}

class _AdminOpenFinanceExtrasTabState extends State<AdminOpenFinanceExtrasTab> {
  final _maxCtrl = TextEditingController();
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    try {
      final c = await ProOpenFinanceConfigService.getOnce();
      if (mounted) _maxCtrl.text = c.maxTotalBankConnections.toString();
    } catch (_) {
      if (mounted) _maxCtrl.text = '${ProOpenFinanceConfig.defaultMaxTotal}';
    }
  }

  Future<void> _saveMax() async {
    final n = int.tryParse(_maxCtrl.text.trim());
    if (n == null || n < 1 || n > 99) {
      setState(() => _saveError = 'Indique um número entre 1 e 99 (ex.: 5).');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('pro_open_finance').set(
        {
          'maxTotalBankConnections': n,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': widget.currentAdminUid,
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Teto de $n conexão(ões) guardado. O app e as Cloud Functions passam a usar o valor (cache ~1 min).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _saveError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _userIdFromPath(String path) {
    // users/UID/bank_connection_entitlements/DOC
    final p = path.split('/');
    final i = p.indexOf('users');
    if (i >= 0 && i + 1 < p.length) return p[i + 1];
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: widget.brandTeal.withValues(alpha: 0.35)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: widget.brandTeal, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Teto de conexões (Open Finance)',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Número máximo de bancos/cartões que um utilizador PRO pode ter ligado ao mesmo tempo, '
                      'somatório do que o plano inclui (geralmente 2) e das conexões extra pagas (até atingir este teto). '
                      'O valor fica em app_config/pro_open_finance e é aplicado no app, no checkout MP e no webhook.',
                      style: TextStyle(height: 1.4, fontSize: 13.5),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 200,
                          child: FastTextField(
                            controller: _maxCtrl,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: const InputDecoration(
                              labelText: 'Máx. conexões simultâneas',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _saving ? null : _saveMax,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Guardar'),
                        ),
                      ],
                    ),
                    if (_saveError != null) ...[
                      const SizedBox(height: 8),
                      Text(_saveError!, style: TextStyle(color: Colors.red.shade800, fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Registos de conexão extra (pagas)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collectionGroup('bank_connection_entitlements')
              .orderBy('createdAt', descending: true)
              .limit(400)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Erro ao listar: ${snap.error}'),
                ),
              );
            }
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const SliverToBoxAdapter(
                child: Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Ainda não há documentos de add-on. Após aprovar pagamentos (extra_bank_connection_*), eles surgem aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, height: 1.4),
                    ),
                  ),
                ),
              );
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final d = docs[i];
                  final path = d.reference.path;
                  final uid = _userIdFromPath(path);
                  final data = d.data();
                  final planCode = (data['planCode'] ?? '—').toString();
                  final payId = (data['paymentId'] ?? d.id).toString();
                  final exp = data['expiresAt'] is Timestamp ? (data['expiresAt'] as Timestamp).toDate() : null;
                  final cre = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;
                  return Card(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: ListTile(
                      isThreeLine: true,
                      title: Text('UID: $uid', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: uid.isEmpty
                          ? Text(
                              'Plano: $planCode · MP: $payId\nVálido até: ${exp != null ? df.format(exp) : "—"}',
                              style: const TextStyle(height: 1.35, fontSize: 12.5),
                            )
                          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                              builder: (context, uSnap) {
                                final em = (uSnap.data?.data()?['email'] ?? '—').toString();
                                return Text(
                                  '$em\nPlano: $planCode · MP: $payId\nVálido até: ${exp != null ? df.format(exp) : "—"} · Criado: ${cre != null ? df.format(cre) : "—"}',
                                  style: const TextStyle(height: 1.35, fontSize: 12.5),
                                );
                              },
                            ),
                      leading: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF0D9488)),
                    ),
                  );
                },
                childCount: docs.length,
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}
