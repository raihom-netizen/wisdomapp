import 'package:flutter/material.dart';
import '../theme/theme_context.dart';

import '../models/finance_account.dart';
import '../theme/app_colors.dart';
import 'finance_bank_brand_thumb.dart';

/// Confirma exclusão de banco/cartão — aviso em vermelho sobre lançamentos vinculados.
Future<bool> showConfirmDeleteFinanceAccountDialog(
  BuildContext context, {
  required FinanceAccount account,
  required int linkedTransactionsCount,
  bool openFinanceLinked = false,
}) async {
  final name = account.displayName;
  final countLabel = linkedTransactionsCount == 1
      ? '1 lançamento vinculado'
      : '$linkedTransactionsCount lançamentos vinculados';

  // Banco conectado: diálogo próprio, com «Cancelar» em destaque — excluir
  // por engano o cartão do Nubank fez as faturas pararem de bater (23/09).
  if (openFinanceLinked) {
    return _confirmarExclusaoConectada(context, account: account, linkedTransactionsCount: linkedTransactionsCount);
  }

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(
        Icons.warning_amber_rounded,
        color: AppColors.error,
        size: 44,
      ),
      iconPadding: const EdgeInsets.only(top: 20),
      title: Text(
        'Excluir «$name»?',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 18,
          color: ctx.isDarkMode ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ATENÇÃO: ao confirmar, o sistema removerá permanentemente '
            'todos os lançamentos financeiros ligados a este banco/cartão.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w800,
              color: AppColors.error,
            ),
          ),
          if (openFinanceLinked) ...[
            SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.38),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sync_disabled_rounded,
                      size: 20,
                      color: ctx.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFB45309)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Este banco veio do Open Finance. Excluindo, ele para de '
                      'sincronizar e os lançamentos dele saem do saldo. As outras '
                      'contas desse banco que você manteve continuam. Se não sobrar '
                      'nenhuma conta dele, a integração com o banco é cancelada '
                      'automaticamente.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: ctx.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 12),
          if (linkedTransactionsCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: AppColors.error, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      countLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Nenhum lançamento vinculado foi encontrado; apenas o cadastro do banco será removido.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: context.appTextSecondary,
              ),
            ),
          SizedBox(height: 10),
          Text(
            'Esta ação não pode ser desfeita.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.appTextSecondary,
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(120, 44),
            foregroundColor: AppColors.primary,
          ),
          child: Text('Não', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(120, 44),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          child: Text('Sim, excluir', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    ),
  );
  return result == true;
}

/// Excluir conta/cartão CONECTADO ao banco (Open Finance).
///
/// Deixa claro o que é (nome, conta ou cartão, «conectado»), o que acontece
/// (a sincronização para e o histórico sai) e que dá para desfazer. Não existe
/// «só esconder» para conta conectada, então «Cancelar» é o botão grande e
/// «Excluir mesmo assim» fica discreto.
Future<bool> _confirmarExclusaoConectada(
  BuildContext context, {
  required FinanceAccount account,
  required int linkedTransactionsCount,
}) async {
  final nome = account.displayName;
  final tipo = account.productType == FinanceAccount.kCard
      ? 'Cartão'
      : account.productType == FinanceAccount.kBankAndCard
          ? 'Conta + cartão'
          : 'Conta';
  final preset = account.preset;
  final historico = linkedTransactionsCount == 0
      ? 'O histórico importado do banco sai do app.'
      : linkedTransactionsCount == 1
          ? '1 lançamento sai do app e do saldo.'
          : '$linkedTransactionsCount lançamentos saem do app e do saldo.';

  Widget linha(IconData icone, Color cor, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: cor.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, size: 17, color: cor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Builder(
                builder: (ctx) => Text(texto,
                    style: TextStyle(fontSize: 13.2, height: 1.35, fontWeight: FontWeight.w600, color: ctx.appTextPrimary)),
              ),
            ),
          ),
        ]),
      );

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Cabeçalho: o banco, com o selo «conectado».
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF0D9488)],
                ),
              ),
              child: Row(children: [
                Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: preset != null
                      ? FinanceBankBrandThumb(preset: preset, size: 40)
                      : const Icon(Icons.account_balance_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Excluir $nome?',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _selo(Icons.link_rounded, 'Banco conectado', const Color(0xFF22C55E)),
                      _selo(account.isCardProduct ? Icons.credit_card_rounded : Icons.account_balance_wallet_rounded,
                          tipo, const Color(0xFF93C5FD)),
                    ]),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                linha(Icons.sync_disabled_rounded, const Color(0xFFD97706),
                    '$nome · ${tipo.toLowerCase()} vem direto do banco pelo Open Finance. Excluindo, a sincronização com o banco para.'),
                linha(Icons.receipt_long_rounded, AppColors.error, historico),
                linha(Icons.undo_rounded, const Color(0xFF2563EB),
                    'Se foi sem querer, dá para desfazer logo em seguida ou reconectar depois pelo aviso no Financeiro.'),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(
                  autofocus: true,
                  onPressed: () => Navigator.pop(ctx, false),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.shield_rounded),
                  label: const Text('Cancelar — manter conectado', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: AppColors.error,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  label: const Text('Excluir mesmo assim', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
  return result == true;
}

Widget _selo(IconData icone, String texto, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: cor.withValues(alpha: 0.7)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, size: 13, color: Colors.white),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
      ]),
    );
