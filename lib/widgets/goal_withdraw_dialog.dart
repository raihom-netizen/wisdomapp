import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../services/goal_deposit_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/date_picker_a11y.dart';
import 'brl_amount_text_field.dart';
import 'goal_finance_account_field.dart';

/// «Resgatar / Retirar da meta»: tira dinheiro guardado da meta e (por
/// padrão) devolve para a conta escolhida no Financeiro — como entrada fora
/// dos totais de receita ([GoalDepositService.withdraw]).
Future<bool> showGoalWithdrawDialog({
  required BuildContext context,
  required DocumentReference<Map<String, dynamic>> goalRef,
  required String goalTitle,
  required String uid,
  required double savedAmount,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> contribDocs,
  String? initialFinanceAccountId,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _GoalWithdrawDialog(
      goalRef: goalRef,
      goalTitle: goalTitle,
      uid: uid,
      savedAmount: savedAmount,
      hasLegacyIncomeDeposits: contribDocs
          .any((d) => GoalDepositService.isLegacyIncomeContrib(d.data())),
      initialFinanceAccountId: initialFinanceAccountId,
    ),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resgate registrado.')),
    );
  }
  return ok == true;
}

class _GoalWithdrawDialog extends StatefulWidget {
  const _GoalWithdrawDialog({
    required this.goalRef,
    required this.goalTitle,
    required this.uid,
    required this.savedAmount,
    required this.hasLegacyIncomeDeposits,
    this.initialFinanceAccountId,
  });

  final DocumentReference<Map<String, dynamic>> goalRef;
  final String goalTitle;
  final String uid;
  final double savedAmount;
  final bool hasLegacyIncomeDeposits;
  final String? initialFinanceAccountId;

  @override
  State<_GoalWithdrawDialog> createState() => _GoalWithdrawDialogState();
}

class _GoalWithdrawDialogState extends State<_GoalWithdrawDialog> {
  final _amountCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String? _accountId;
  late bool _backToAccount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accountId = widget.initialFinanceAccountId;
    // Depósitos antigos entraram como receita e nunca saíram da conta:
    // devolver de novo somaria duas vezes — começa desligado nesse caso.
    _backToAccount = !widget.hasLegacyIncomeDeposits;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    String? erro;
    if (amount <= 0) erro = 'Informe um valor maior que zero.';
    if (amount > widget.savedAmount + 0.004) {
      erro = 'A meta tem ${CurrencyFormats.formatBRL(widget.savedAmount)} guardado.';
    }
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    setState(() => _saving = true);
    try {
      await GoalDepositService.withdraw(
        uid: widget.uid,
        goalRef: widget.goalRef,
        goalId: widget.goalRef.id,
        goalTitle: widget.goalTitle,
        amount: amount,
        date: _date,
        financeAccountId: _accountId,
        createFinanceTx: _backToAccount,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700;
    return AlertDialog(
      backgroundColor: context.isDarkMode ? context.appSurface : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.undo_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Resgatar da meta',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: context.appTextPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '«${widget.goalTitle}» tem '
              '${CurrencyFormats.formatBRL(widget.savedAmount)} guardado.',
              style: TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            BrlAmountTextField(
              controller: _amountCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Valor a retirar (R\$)',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _amountCtrl.text =
                    CurrencyFormats.formatBRLInput(widget.savedAmount),
                child: const Text('Retirar tudo'),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _backToAccount,
              onChanged: (v) => setState(() => _backToAccount = v),
              title: Text(
                'Devolver o valor para a conta',
                style: TextStyle(color: context.appTextPrimary, fontSize: 14),
              ),
              subtitle: Text(
                'Lança uma entrada no Financeiro (não conta como receita).',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
            if (widget.hasLegacyIncomeDeposits)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Atenção: depósitos antigos desta meta entraram como receita '
                  'e não saíram da conta. Se o dinheiro desses depósitos ainda '
                  'está na conta, deixe desligado para não somar duas vezes.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: context.isDarkMode
                        ? Colors.orange.shade200
                        : Colors.orange.shade900,
                  ),
                ),
              ),
            if (_backToAccount)
              GoalFinanceAccountField(
                uid: widget.uid,
                selectedAccountId: _accountId,
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Data do resgate',
                  style: TextStyle(color: context.appTextPrimary)),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_date),
                  style: TextStyle(color: muted)),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Alterar'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Resgatar'),
        ),
      ],
    );
  }
}
