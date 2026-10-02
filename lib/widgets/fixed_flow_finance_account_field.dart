import 'package:flutter/material.dart';

import '../models/finance_account.dart';
import '../services/finance_accounts_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import 'finance_bank_brand_thumb.dart';

/// Seletor de banco/caixa para despesas e receitas fixas (cadastro Financeiro).
class FixedFlowFinanceAccountField extends StatefulWidget {
  const FixedFlowFinanceAccountField({
    super.key,
    required this.uid,
    required this.selectedAccountId,
    required this.onChanged,
    this.decorationBuilder,
  });

  final String uid;
  final String? selectedAccountId;
  final ValueChanged<String?> onChanged;
  final InputDecoration Function(BuildContext context, {required Widget prefixIcon})?
      decorationBuilder;

  @override
  State<FixedFlowFinanceAccountField> createState() => _FixedFlowFinanceAccountFieldState();
}

class _FixedFlowFinanceAccountFieldState extends State<FixedFlowFinanceAccountField> {
  // Stream guardado: criar um novo a cada rebuild (o formulário de venda
  // redesenha a cada tecla) reabria o listener do Firestore toda vez — na Web
  // isso dá «Target ID already exists».
  late Stream<List<FinanceAccount>> _contas = FinanceAccountsService().streamAccounts(widget.uid);

  @override
  void didUpdateWidget(covariant FixedFlowFinanceAccountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _contas = FinanceAccountsService().streamAccounts(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedAccountId = widget.selectedAccountId;
    final decorationBuilder = widget.decorationBuilder;
    final onChanged = widget.onChanged;
    return StreamBuilder<List<FinanceAccount>>(
      stream: _contas,
      builder: (context, snap) {
        final accounts = snap.data ?? const <FinanceAccount>[];
        final ids = accounts.map((a) => a.id).toSet();
        final value = selectedAccountId != null && ids.contains(selectedAccountId)
            ? selectedAccountId
            : null;
        final prefix = Icon(
          Icons.account_balance_rounded,
          color: AppColors.primary.withValues(alpha: 0.88),
        );
        final deco = decorationBuilder?.call(context, prefixIcon: prefix) ??
            InputDecoration(
              labelText: 'Banco ou caixa',
              filled: true,
              fillColor: context.appInputFill,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              prefixIcon: prefix,
            );

        if (accounts.isEmpty) {
          return InputDecorator(
            decoration: deco.copyWith(
              labelText: 'Banco ou caixa',
              helperText:
                  'Cadastre bancos em Financeiro → Bancos e cartões.',
            ),
            child: Text(
              'Nenhuma conta cadastrada',
              style: TextStyle(
                color: context.appTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return DropdownButtonFormField<String?>(
          key: ValueKey('fixed_acc_${value ?? 'none'}'),
          isExpanded: true,
          initialValue: value,
          decoration: deco.copyWith(
            labelText: 'Banco ou caixa',
            helperText: 'Padrão do cadastro de bancos, se definido.',
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Sem conta vinculada'),
            ),
            ...accounts.map((a) {
              return DropdownMenuItem<String?>(
                value: a.id,
                child: Row(
                  children: [
                    FinanceBankBrandThumb(preset: a.preset, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}
