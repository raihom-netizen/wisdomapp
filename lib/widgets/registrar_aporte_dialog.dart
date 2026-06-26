import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import 'brl_amount_text_field.dart';
import '../models/user_profile.dart';
import '../utils/premium_upgrade.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/fifty_two_weeks_plan.dart';

/// Abre o diálogo de aporte com parse BRL correto e foco no campo após 1 frame (teclado mais fluido).
Future<bool> showRegistrarAporteDialog({
  required BuildContext context,
  required DocumentReference<Map<String, dynamic>> goalRef,
  required UserProfile profile,
  double? initialAmount,
  int? weekNumber,
}) async {
  if (!profile.hasActiveLicense) {
    mostrarAvisoSeLicencaInativa(context, profile);
    return false;
  }
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RegistrarAporteDialogContent(
      goalRef: goalRef,
      initialAmount: initialAmount,
      weekNumber: weekNumber,
    ),
  );
  return saved == true;
}

class _RegistrarAporteDialogContent extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> goalRef;
  final double? initialAmount;
  final int? weekNumber;

  const _RegistrarAporteDialogContent({
    required this.goalRef,
    this.initialAmount,
    this.weekNumber,
  });

  @override
  State<_RegistrarAporteDialogContent> createState() => _RegistrarAporteDialogContentState();
}

class _RegistrarAporteDialogContentState extends State<_RegistrarAporteDialogContent> {
  final TextEditingController _amountCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    final seed = widget.initialAmount;
    if (seed != null && seed > 0) {
      _amountCtrl.text = CurrencyFormats.formatBRLInput(seed);
    }
    // Evita competir com a animação do diálogo no mesmo frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
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

  Future<void> _salvar() async {
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero.')),
      );
      return;
    }
    try {
      await widget.goalRef.collection('contributions').add({
        'amount': amount,
        'date': Timestamp.fromDate(_date),
        'createdAt': FieldValue.serverTimestamp(),
        if (widget.weekNumber != null) 'weekNumber': widget.weekNumber,
      });
      if (widget.weekNumber != null) {
        final goalSnap = await widget.goalRef.get();
        final paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalSnap.data() ?? {});
        if (!paid.contains(widget.weekNumber)) {
          paid.add(widget.weekNumber!);
          paid.sort();
          await widget.goalRef.update({'weeksPaid': paid});
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao registrar aporte: ${e.toString().split('\n').first}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar aporte'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Data do aporte'),
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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvar,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
