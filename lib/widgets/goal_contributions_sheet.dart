import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../services/goal_deposit_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/premium_upgrade.dart';
import 'brl_amount_text_field.dart';
import 'sheet_voltar_controls.dart';

/// Sheet «Ver / Editar lançamentos» — compartilhado entre Início e módulo Objetivo.
Future<void> showGoalContributionsSheet({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required String goalTitle,
  required String uid,
  required UserProfile profile,
}) async {
  if (!profile.hasActiveLicense) {
    mostrarAvisoSeLicencaInativa(context, profile);
    return;
  }
  final contribRef = goalDoc.reference.collection('contributions');
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            previewSheetTopBar(ctx),
            sheetWideVoltarButton(ctx),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.list_alt_rounded, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lançamentos · $goalTitle',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A237E),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: contribRef.orderBy('date', descending: true).snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Erro: ${snap.error}',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum depósito ainda',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Use "Depositar" no card da meta.',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        sheetWideVoltarButton(context, footer: true),
                      ],
                    );
                  }
                  return StreamBuilder<List<FinanceAccount>>(
                    stream: FinanceAccountsService().streamAccounts(uid),
                    builder: (context, accSnap) {
                      final accounts = accSnap.data ?? const <FinanceAccount>[];
                      final accById = {for (final a in accounts) a.id: a};
                      return ListView.builder(
                        controller: scrollController,
                        cacheExtent: 400,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: docs.length + 1,
                        itemBuilder: (context, i) {
                          if (i == docs.length) {
                            return sheetWideVoltarButton(context, footer: true);
                          }
                          final doc = docs[i];
                          final d = doc.data();
                          final amount = (d['amount'] ?? 0).toDouble();
                          final dateTs = d['date'] as Timestamp?;
                          final date = dateTs?.toDate() ?? DateTime.now();
                          final week = d['weekNumber'] as int?;
                          final weeks =
                              (d['weekNumbers'] as List?)?.whereType<int>().toList() ?? [];
                          final accountId = (d['financeAccountId'] ?? '').toString();
                          final account = accountId.isNotEmpty ? accById[accountId] : null;
                          final preset = account?.preset;
                          final accent = preset?.color1 ?? AppColors.primary;
                          final grad = [
                            accent,
                            preset?.color2 ?? accent.withValues(alpha: 0.75),
                          ];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                colors: [
                                  grad[0].withValues(alpha: 0.12),
                                  grad[1].withValues(alpha: 0.06),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: accent.withValues(alpha: 0.35)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: grad),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.savings_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                CurrencyFormats.formatBRL(amount),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  color: accent,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('dd/MM/yyyy').format(date),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (week != null || weeks.isNotEmpty)
                                    Text(
                                      week != null
                                          ? 'Semana $week'
                                          : 'Semanas ${weeks.join(', ')}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: accent,
                                      ),
                                    ),
                                  if (account != null)
                                    Text(
                                      '🏦 ${account.displayName}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit_rounded, size: 22, color: accent),
                                    onPressed: () => _editGoalDeposit(
                                      ctx,
                                      doc: doc,
                                      goalDoc: goalDoc,
                                      uid: uid,
                                      initialAccountId: accountId,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 22,
                                      color: AppColors.error,
                                    ),
                                    onPressed: () => _deleteGoalDeposit(
                                      ctx,
                                      doc: doc,
                                      goalDoc: goalDoc,
                                      uid: uid,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _editGoalDeposit(
  BuildContext context, {
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required String uid,
  required String initialAccountId,
}) async {
  final d = doc.data();
  final amountCtrl =
      TextEditingController(text: CurrencyFormats.formatBRLInput((d['amount'] ?? 0) as num));
  DateTime date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
  String? financeAccountId = initialAccountId.isEmpty ? null : initialAccountId;
  double? accountBalance;

  if (financeAccountId != null && financeAccountId!.isNotEmpty) {
    accountBalance = await GoalDepositService.accountBalanceAllTime(
      uid: uid,
      financeAccountId: financeAccountId!,
    );
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Editar depósito', style: TextStyle(fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrlAmountTextField(
                controller: amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor (R\$)',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<FinanceAccount>>(
                stream: FinanceAccountsService().streamAccounts(uid),
                builder: (context, snap) {
                  final accounts = snap.data ?? const <FinanceAccount>[];
                  return DropdownButtonFormField<String?>(
                    value: financeAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Conta vinculada',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Sem conta')),
                      for (final a in accounts)
                        DropdownMenuItem<String?>(value: a.id, child: Text(a.displayName)),
                    ],
                    onChanged: (v) async {
                      setState(() => financeAccountId = v);
                      if (v != null && v.isNotEmpty) {
                        final bal = await GoalDepositService.accountBalanceAllTime(
                          uid: uid,
                          financeAccountId: v,
                        );
                        if (ctx.mounted) setState(() => accountBalance = bal);
                      } else {
                        setState(() => accountBalance = null);
                      }
                    },
                  );
                },
              ),
              if (accountBalance != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Saldo atual: ${CurrencyFormats.formatBRL(accountBalance!)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                  child: const Text('Alterar'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    ),
  );

  try {
    if (ok != true) return;
    final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    if (amount <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um valor maior que zero.')),
        );
      }
      return;
    }
    await GoalDepositService.updateDeposit(
      uid: uid,
      contribDoc: doc,
      amount: amount,
      date: date,
      financeAccountId: financeAccountId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Depósito atualizado!')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
      );
    }
  } finally {
    amountCtrl.dispose();
  }
}

Future<void> _deleteGoalDeposit(
  BuildContext context, {
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required String uid,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir depósito?'),
      content: const Text(
        'O valor será descontado da meta e removido do Financeiro, se vinculado.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (confirm != true) return;
  try {
    await GoalDepositService.deleteDeposit(
      uid: uid,
      contribDoc: doc,
      goalRef: goalDoc.reference,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lançamento excluído.')),
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
