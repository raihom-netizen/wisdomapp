import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/user_profile.dart';
import '../services/goal_deposit_service.dart';
import '../utils/premium_upgrade.dart';
import '../utils/date_picker_a11y.dart';
import 'goal_finance_account_field.dart';
import 'brl_amount_text_field.dart';
import 'sheet_voltar_controls.dart';

/// Abre o diálogo «Registrar depósito» (meta clássica ou complemento).
Future<bool> showRegistrarDepositoDialog({
  required BuildContext context,
  required DocumentReference<Map<String, dynamic>> goalRef,
  required String goalId,
  required String goalTitle,
  required String uid,
  required UserProfile profile,
  double? initialAmount,
  List<int>? weekNumbers,
  String? initialFinanceAccountId,
}) async {
  if (!profile.hasActiveLicense) {
    mostrarAvisoSeLicencaInativa(context, profile);
    return false;
  }
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RegistrarDepositoDialogContent(
      goalRef: goalRef,
      goalId: goalId,
      goalTitle: goalTitle,
      uid: uid,
      initialAmount: initialAmount,
      weekNumbers: weekNumbers,
      initialFinanceAccountId: initialFinanceAccountId,
    ),
  );
  return saved == true;
}

/// Compatibilidade com chamadas antigas.
Future<bool> showRegistrarAporteDialog({
  required BuildContext context,
  required DocumentReference<Map<String, dynamic>> goalRef,
  required UserProfile profile,
  double? initialAmount,
  int? weekNumber,
  String? goalId,
  String? goalTitle,
  String? uid,
}) {
  final gSnap = goalRef.parent.parent;
  return showRegistrarDepositoDialog(
    context: context,
    goalRef: goalRef,
    goalId: goalId ?? goalRef.id,
    goalTitle: goalTitle ?? 'Objetivo',
    uid: uid ?? gSnap?.id ?? '',
    profile: profile,
    initialAmount: initialAmount,
    weekNumbers: weekNumber != null ? [weekNumber] : null,
  );
}

class _RegistrarDepositoDialogContent extends StatefulWidget {
  const _RegistrarDepositoDialogContent({
    required this.goalRef,
    required this.goalId,
    required this.goalTitle,
    required this.uid,
    this.initialAmount,
    this.weekNumbers,
    this.initialFinanceAccountId,
  });

  final DocumentReference<Map<String, dynamic>> goalRef;
  final String goalId;
  final String goalTitle;
  final String uid;
  final double? initialAmount;
  final List<int>? weekNumbers;
  final String? initialFinanceAccountId;

  @override
  State<_RegistrarDepositoDialogContent> createState() =>
      _RegistrarDepositoDialogContentState();
}

class _RegistrarDepositoDialogContentState
    extends State<_RegistrarDepositoDialogContent> {
  final TextEditingController _amountCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  DateTime _date = DateTime.now();
  String? _financeAccountId;
  double? _accountBalance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seedAccount = widget.initialFinanceAccountId?.trim();
    if (seedAccount != null && seedAccount.isNotEmpty) {
      _financeAccountId = seedAccount;
    }
    final seed = widget.initialAmount;
    if (seed != null && seed > 0) {
      _amountCtrl.text = CurrencyFormats.formatBRLInput(seed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
      if (_financeAccountId != null) _loadBalance(_financeAccountId);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _focusNode.dispose();
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

  Future<void> _loadBalance(String? accountId) async {
    if (accountId == null || accountId.isEmpty) {
      setState(() {
        _accountBalance = null;
      });
      return;
    }
    final bal = await GoalDepositService.accountBalanceAllTime(
      uid: widget.uid,
      financeAccountId: accountId,
    );
    if (mounted) setState(() => _accountBalance = bal);
  }

  Future<void> _salvar() async {
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await GoalDepositService.saveDeposit(
        uid: widget.uid,
        goalRef: widget.goalRef,
        goalId: widget.goalId,
        goalTitle: widget.goalTitle,
        amount: amount,
        date: _date,
        financeAccountId: _financeAccountId,
        weekNumbers: widget.weekNumbers,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao registrar depósito: ${e.toString().split('\n').first}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF0D9488)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.savings_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Registrar depósito', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sheetWideVoltarButton(
              context,
              onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            ),
            if (widget.weekNumbers != null && widget.weekNumbers!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  widget.weekNumbers!.length == 1
                      ? 'Semana ${widget.weekNumbers!.first}'
                      : '${widget.weekNumbers!.length} semanas: ${widget.weekNumbers!.join(', ')}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ),
            BrlAmountTextField(
              controller: _amountCtrl,
              focusNode: _focusNode,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _salvar(),
              decoration: const InputDecoration(
                labelText: 'Valor (R\$)',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            GoalFinanceAccountField(
              uid: widget.uid,
              selectedAccountId: _financeAccountId,
              onChanged: (v) {
                setState(() => _financeAccountId = v);
                _loadBalance(v);
              },
            ),
            if (_accountBalance != null) ...[
              const SizedBox(height: 8),
              Text(
                'Saldo atual da conta: ${CurrencyFormats.formatBRL(_accountBalance!)}',
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
              dense: true,
              title: const Text('Data do depósito'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)),
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
          onPressed: _saving ? null : _salvar,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
