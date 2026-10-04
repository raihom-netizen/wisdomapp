// Peças visuais e diálogos compartilhados pelas telas da carteira.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/currency_formats.dart';
import '../../models/finance_account.dart';
import '../../services/finance_accounts_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_context.dart';
import 'investimentos_calculo.dart';

const String kAvisoEstimativa =
    'Estimativa com as taxas oficiais do Banco Central; o valor do banco pode variar alguns centavos.';

/// Cores por tipo (gráficos e ícones) — mesma família das cores do app.
const Map<String, Color> kCorPorTipo = {
  'cdb': Color(0xFF2D5BFF),
  'lci': Color(0xFF12B5A5),
  'lca': Color(0xFF16A34A),
  'lc': Color(0xFF4B3DF0),
  'caixinha': Color(0xFF8B5CF6),
  'tesouro_selic': Color(0xFFF59E0B),
  'tesouro_prefixado': Color(0xFFF97316),
  'tesouro_ipca': Color(0xFFEF4444),
  'poupanca': Color(0xFF0EA5E9),
  'previdencia': Color(0xFF64748B),
  'fundo': Color(0xFFEC4899),
  'acoes': Color(0xFF0B1F4B),
  'fii': Color(0xFF84CC16),
  'outro': Color(0xFF94A3B8),
};

const List<Color> kCoresBancos = [
  Color(0xFF2D5BFF),
  Color(0xFF12B5A5),
  Color(0xFFF59E0B),
  Color(0xFF8B5CF6),
  Color(0xFFEF4444),
  Color(0xFF16A34A),
  Color(0xFFF97316),
  Color(0xFF0EA5E9),
  Color(0xFFEC4899),
  Color(0xFF64748B),
];

IconData iconeDoTipo(String tipo) {
  switch (tipo) {
    case 'caixinha':
      return Icons.savings_rounded;
    case 'poupanca':
      return Icons.account_balance_wallet_rounded;
    case 'tesouro_selic':
    case 'tesouro_prefixado':
    case 'tesouro_ipca':
      return Icons.account_balance_rounded;
    case 'acoes':
    case 'fii':
      return Icons.candlestick_chart_rounded;
    case 'previdencia':
      return Icons.elderly_rounded;
    case 'fundo':
      return Icons.pie_chart_rounded;
    default:
      return Icons.trending_up_rounded;
  }
}

String dataBr(String iso) {
  if (iso.length < 10) return iso;
  return '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
}

String brl(num? v) => CurrencyFormats.formatBRL(v ?? 0);

/// Texto do aviso de estimativa (sempre visível nas telas da carteira).
class AvisoEstimativa extends StatelessWidget {
  const AvisoEstimativa({super.key, this.ultimaTaxa = ''});
  final String ultimaTaxa;

  @override
  Widget build(BuildContext context) {
    final extra = ultimaTaxa.isEmpty ? '' : ' Taxas até ${dataBr(ultimaTaxa)}.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: context.appTextMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('$kAvisoEstimativa$extra',
                style: TextStyle(fontSize: 12, color: context.appTextMuted, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// Linha «rótulo ……… valor».
class LinhaValor extends StatelessWidget {
  const LinhaValor(this.rotulo, this.valor, {super.key, this.cor, this.negrito = false});
  final String rotulo, valor;
  final Color? cor;
  final bool negrito;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(rotulo, style: TextStyle(color: context.appTextSecondary, fontSize: 13.5))),
            Text(valor,
                style: TextStyle(
                  fontWeight: negrito ? FontWeight.w800 : FontWeight.w600,
                  fontSize: negrito ? 15 : 13.5,
                  color: cor ?? context.appTextPrimary,
                )),
          ],
        ),
      );
}

Color corDoValor(BuildContext context, double? v) {
  if (v == null || v.abs() < 0.005) return context.appTextSecondary;
  return v > 0 ? AppColors.financeReceita : AppColors.financeDespesa;
}

/// Contas que podem pagar/receber (sem cartão de crédito puro).
Future<List<FinanceAccount>> contasParaInvestir(String uid) async {
  try {
    final l = await FinanceAccountsService().listOnce(uid);
    return l.where((c) => !c.isCreditCardProduct).toList();
  } catch (_) {
    return const [];
  }
}

Future<String?> escolherData(BuildContext context, String atual) async {
  final d = parseIso(atual) ?? DateTime.now();
  final r = await showDatePicker(
    context: context,
    initialDate: DateTime(d.year, d.month, d.day),
    firstDate: DateTime(2000),
    lastDate: DateTime.now().add(const Duration(days: 365 * 40)),
  );
  return r == null ? null : isoDe(DateTime.utc(r.year, r.month, r.day));
}

/// Resultado do diálogo de aplicação/resgate.
class MovimentoEscolhido {
  MovimentoEscolhido(this.valor, this.data, this.conta, {this.tudo = false});
  final double valor;
  final String data;
  final FinanceAccount? conta;
  final bool tudo;
}

/// Diálogo de aplicar mais / resgatar. No resgate mostra a simulação
/// (principal × rendimento, IR, IOF) antes de confirmar.
Future<MovimentoEscolhido?> dialogoMovimento(
  BuildContext context, {
  required String uid,
  required Investimento inv,
  required bool resgate,
  IndicesBcb? idx,
}) async {
  final contas = await contasParaInvestir(uid);
  if (!context.mounted) return null;
  final ctrl = TextEditingController();
  var data = hojeBrasilia();
  FinanceAccount? conta = contas.where((c) => c.id == inv.contaId).firstOrNull ?? (contas.isEmpty ? null : contas.first);
  var semConta = contas.isEmpty;
  var tudo = false;
  return showDialog<MovimentoEscolhido>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final valor = CurrencyFormats.parseBRLInput(ctrl.text) ?? 0;
      ResultadoResgate? sim;
      if (resgate && idx != null && (valor > 0 || tudo)) {
        sim = simularResgate(inv, idx, data, valor, tudo: tudo);
      }
      return AlertDialog(
        title: Text(resgate ? 'Resgatar' : 'Aplicar mais'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(inv.nomeExibicao, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (!tudo)
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: CurrencyFormats.brlInputFormatters,
                  decoration: InputDecoration(
                    labelText: resgate ? 'Valor que caiu na conta (líquido)' : 'Valor aplicado',
                    prefixText: 'R\$ ',
                  ),
                  onChanged: (_) => setS(() {}),
                ),
              if (resgate)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: tudo,
                  title: const Text('Resgatar tudo'),
                  onChanged: (v) => setS(() => tudo = v ?? false),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Data: ${dataBr(data)}'),
                onPressed: () async {
                  final r = await escolherData(ctx, data);
                  if (r != null) setS(() => data = r);
                },
              ),
              const SizedBox(height: 8),
              if (contas.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: semConta ? '' : conta?.id,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: resgate ? 'Entra na conta' : 'Sai da conta'),
                  items: [
                    for (final c in contas) DropdownMenuItem(value: c.id, child: Text(c.displayName, overflow: TextOverflow.ellipsis)),
                    const DropdownMenuItem(value: '', child: Text('Sem conta (só a carteira)')),
                  ],
                  onChanged: (v) => setS(() {
                    semConta = v == null || v.isEmpty;
                    conta = semConta ? null : contas.firstWhere((c) => c.id == v);
                  }),
                ),
              if (sim != null) ...[
                const SizedBox(height: 12),
                LinhaValor('Devolução do aplicado', brl(sim.principal)),
                LinhaValor('Rendimento líquido', brl(sim.rendimentoLiquido), cor: AppColors.financeReceita),
                if (sim.ir > 0.004) LinhaValor('IR retido', brl(sim.ir)),
                if (sim.iof > 0.004) LinhaValor('IOF retido', brl(sim.iof)),
                if (tudo) LinhaValor('Total líquido', brl(sim.liquido), negrito: true),
                if (sim.excedente > 0.01)
                  Text('O valor passou ${brl(sim.excedente)} do estimado — entra como rendimento.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                const AvisoEstimativa(),
              ],
              if (!resgate)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'O dinheiro sai do saldo da conta e passa a aparecer como patrimônio investido — não conta como despesa.',
                    style: TextStyle(fontSize: 12, color: ctx.appTextMuted),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: (valor > 0 || (tudo && sim != null && sim.liquido > 0))
                ? () => Navigator.pop(
                    ctx,
                    MovimentoEscolhido(tudo && sim != null ? (sim.liquido * 100).round() / 100 : valor, data,
                        semConta ? null : conta,
                        tudo: tudo))
                : null,
            child: const Text('Confirmar'),
          ),
        ],
      );
    }),
  );
}

/// Campo numérico com vírgula (taxas).
class CampoTaxa extends StatelessWidget {
  const CampoTaxa({super.key, required this.controller, required this.rotulo, this.sufixo = '%'});
  final TextEditingController controller;
  final String rotulo, sufixo;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'))],
        decoration: InputDecoration(labelText: rotulo, suffixText: sufixo),
      );
}

/// «6,5» e «6.5» → 6.5; «1.234,5» → 1234.5.
double lerNumero(String s) {
  final t = s.trim();
  final n = t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t;
  return double.tryParse(n) ?? 0;
}
