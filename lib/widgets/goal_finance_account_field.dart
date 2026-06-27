import 'package:flutter/material.dart';

import '../constants/finance_bank_presets.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../services/finance_accounts_service.dart';
import '../utils/finance_account_balance_utils.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import '../widgets/fast_text_field.dart';

/// Conta onde o dinheiro da meta será guardado — integrado ao Financeiro.
class GoalFinanceAccountField extends StatelessWidget {
  const GoalFinanceAccountField({
    super.key,
    required this.uid,
    required this.selectedAccountId,
    required this.onChanged,
    this.compact = false,
  });

  final String uid;
  final String? selectedAccountId;
  final ValueChanged<String?> onChanged;
  final bool compact;

  static List<FinanceAccount> goalEligibleAccounts(List<FinanceAccount> all) {
    final debit = FinanceAccountBalanceUtils.debitBankAccounts(all);
    final ids = debit.map((a) => a.id).toSet();
    for (final a in all) {
      if (a.presetId == 'caixa_pessoal' && !ids.contains(a.id)) {
        debit.add(a);
      }
    }
    return debit;
  }

  static FinanceAccount? findCaixaPessoal(List<FinanceAccount> accounts) {
    for (final a in accounts) {
      if (a.presetId == 'caixa_pessoal') return a;
      final nick = (a.nickname ?? '').toLowerCase();
      if (nick.contains('caixa pessoal') || nick.contains('dinheiro em casa')) {
        return a;
      }
    }
    return null;
  }

  Future<void> _createCaixaPessoal(BuildContext context) async {
    final existing = await FinanceAccountsService().listOnce(uid);
    final found = findCaixaPessoal(existing);
    if (found != null) {
      onChanged(found.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conta «${found.displayName}» selecionada.')),
        );
      }
      return;
    }
    try {
      final id = await FinanceAccountsService().addAccount(
        uid: uid,
        presetId: 'caixa_pessoal',
        productType: FinanceAccount.kChecking,
        nickname: 'Caixa pessoal',
      );
      onChanged(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cofrinho / caixa pessoal criado e vinculado à meta.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<void> _openQuickBankSheet(BuildContext context) async {
    final nickCtrl = TextEditingController();
    var preset = kFinanceBankPresets.firstWhere((p) => p.id == 'nubank');
    final created = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Cadastrar conta bancária',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A conta aparece no Financeiro e recebe os depósitos desta meta.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                      ),
                      const SizedBox(height: 14),
                      FastTextField(
                        controller: nickCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Apelido (opcional)',
                          hintText: 'Ex: Nubank poupança',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Instituição', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in kFinanceBankPresets.where((e) =>
                              e.id != 'outro_cartao' && e.id != 'caixa_pessoal'))
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => setLocal(() => preset = p),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: preset.id == p.id
                                        ? p.color1.withValues(alpha: 0.18)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: preset.id == p.id ? p.color1 : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: preset.id == p.id ? p.color1 : Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          try {
                            final id = await FinanceAccountsService().addAccount(
                              uid: uid,
                              presetId: preset.id,
                              productType: FinanceAccount.kChecking,
                              nickname: nickCtrl.text.trim().isEmpty ? null : nickCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx, id);
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Erro: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Salvar conta'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    nickCtrl.dispose();
    if (created != null) onChanged(created);
  }

  Widget _accountDropdownItem(FinanceAccount account) {
    final vis = financeAccountVisualFor(account);
    return Row(
      children: [
        FinanceBankBrandThumb(preset: account.preset, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                account.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: vis.color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                account.productTypeLabel,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _effectiveSelectedId(List<FinanceAccount> accounts) {
    if (selectedAccountId == null) return null;
    if (accounts.any((a) => a.id == selectedAccountId)) return selectedAccountId;
    return null;
  }

  Widget _buildAccountDropdown(
    BuildContext context,
    List<FinanceAccount> accounts, {
    bool dense = false,
  }) {
    return DropdownButtonFormField<String?>(
      value: _effectiveSelectedId(accounts),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Conta que guarda o dinheiro',
        hintText: 'Escolha banco ou cofrinho',
        prefixIcon: Icon(Icons.savings_rounded, color: Colors.teal.shade700, size: 22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.white,
        isDense: dense,
      ),
      items: [
        for (final a in accounts)
          DropdownMenuItem<String?>(
            value: a.id,
            child: _accountDropdownItem(a),
          ),
      ],
      onChanged: accounts.isEmpty ? null : onChanged,
    );
  }

  Widget _buildEmptyAccountActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nenhuma conta cadastrada. Crie um cofrinho ou cadastre seu banco.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _modernAddTile(
            onTap: () => _createCaixaPessoal(context),
            gradient: const [Color(0xFF059669), Color(0xFF10B981)],
            icon: Icons.savings_rounded,
            title: 'Cofrinho / Caixa pessoal',
            subtitle: 'Dinheiro em casa, sem banco',
            light: true,
          ),
          const SizedBox(height: 10),
          _modernAddTile(
            onTap: () => _openQuickBankSheet(context),
            borderColor: const Color(0xFF6366F1),
            icon: Icons.account_balance_rounded,
            title: 'Cadastrar banco',
            subtitle: 'Nubank, Bradesco, Caixa...',
            light: false,
          ),
        ],
      ),
    );
  }

  Widget _modernAddTile({
    required VoidCallback onTap,
    List<Color>? gradient,
    Color? borderColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool light,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient != null
                ? LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
            color: gradient == null ? Colors.white : null,
            borderRadius: BorderRadius.circular(16),
            border: borderColor != null ? Border.all(color: borderColor.withValues(alpha: 0.45), width: 2) : null,
            boxShadow: gradient != null
                ? [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: light
                        ? Colors.white.withValues(alpha: 0.22)
                        : borderColor!.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: light ? Colors.white : borderColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: light ? Colors.white : borderColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: light ? Colors.white70 : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_circle_rounded,
                  color: light ? Colors.white : borderColor,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddAccountRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _createCaixaPessoal(context),
            icon: Icon(Icons.savings_rounded, size: 18, color: Colors.green.shade700),
            label: Text(
              'Cofrinho',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade800),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: BorderSide(color: Colors.green.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _openQuickBankSheet(context),
            icon: Icon(Icons.add_business_rounded, size: 18, color: Colors.indigo.shade700),
            label: Text(
              'Novo banco',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.indigo.shade800),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: BorderSide(color: Colors.indigo.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D9488).withValues(alpha: 0.08),
            const Color(0xFF6366F1).withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.28)),
      ),
      child: child,
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF14B8A6), Color(0xFF6366F1)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.savings_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Onde guardar o dinheiro',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              Text(
                'Vinculado ao Financeiro - depósitos entram nesta conta.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinanceAccount>>(
      stream: FinanceAccountsService().streamAccounts(uid),
      builder: (context, snap) {
        final all = snap.data ?? const <FinanceAccount>[];
        final accounts = goalEligibleAccounts(all);

        if (compact) {
          if (accounts.isEmpty) {
            return _buildFieldShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderRow(),
                  const SizedBox(height: 12),
                  _buildEmptyAccountActions(context),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAccountDropdown(context, accounts, dense: true),
              const SizedBox(height: 8),
              _buildAddAccountRow(context),
            ],
          );
        }

        return _buildFieldShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderRow(),
              const SizedBox(height: 12),
              if (accounts.isEmpty)
                _buildEmptyAccountActions(context)
              else ...[
                _buildAccountDropdown(context, accounts),
                const SizedBox(height: 10),
                _buildAddAccountRow(context),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Cabeçalho moderno dos diálogos de meta (cofrinho).
Widget goalFormDialogHeader({
  required String title,
  required IconData icon,
  String? subtitle,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF0D9488), Color(0xFFEC4899)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0B1B4B),
                height: 1.2,
              ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
