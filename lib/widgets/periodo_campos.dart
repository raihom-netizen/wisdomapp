import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../utils/date_picker_a11y.dart' as cal;
import 'br_datetime_input.dart';

/// Período por dois campos NA PRÓPRIA TELA: data inicial e data final.
///
/// Dá para digitar (dd/mm/aaaa, com máscara) ou tocar no ícone e escolher no
/// calendário PADRÃO do app (o mesmo de todo o sistema, com feriados e fins de
/// semana em destaque). Substitui o seletor de intervalo do Material, que
/// abria um calendário de tela inteira com meses empilhados — difícil de usar
/// e diferente de todo o resto do app.
///
/// Só avisa ([onAplicar]) quando as duas datas são válidas e a inicial não
/// passa da final; se o usuário inverter, as duas são trocadas de lugar.
class PeriodoCampos extends StatefulWidget {
  const PeriodoCampos({
    super.key,
    required this.de,
    required this.ate,
    required this.onAplicar,
    this.cor,
  });

  final DateTime de;
  final DateTime ate;
  final void Function(DateTime de, DateTime ate) onAplicar;

  /// Cor de destaque do botão Aplicar (padrão: o neón do app).
  final Color? cor;

  @override
  State<PeriodoCampos> createState() => _PeriodoCamposState();
}

class _PeriodoCamposState extends State<PeriodoCampos> {
  late final _deCtrl = TextEditingController(text: _fmt(widget.de));
  late final _ateCtrl = TextEditingController(text: _fmt(widget.ate));
  String? _erro;

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void dispose() {
    _deCtrl.dispose();
    _ateCtrl.dispose();
    super.dispose();
  }

  Future<void> _calendario(TextEditingController ctrl) async {
    final atual = parseBrDateInput(ctrl.text) ?? DateTime.now();
    final d = await cal.showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    setState(() => ctrl.text = _fmt(d));
    _tentarAplicar();
  }

  /// Aplica quando as duas estão completas — sem botão extra no caminho feliz.
  void _tentarAplicar({bool avisar = false}) {
    final de = parseBrDateInput(_deCtrl.text);
    final ate = parseBrDateInput(_ateCtrl.text);
    if (de == null || ate == null) {
      if (avisar) setState(() => _erro = 'Informe as duas datas no formato dd/mm/aaaa.');
      return;
    }
    setState(() => _erro = null);
    // Invertidas: o usuário quis o intervalo entre as duas.
    if (ate.isBefore(de)) {
      widget.onAplicar(ate, de);
    } else {
      widget.onAplicar(de, ate);
    }
  }

  Widget _campo(BuildContext ctx, TextEditingController c, String rotulo) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [BrDateInputFormatter()],
          onChanged: (v) {
            if (v.length == 10) _tentarAplicar();
          },
          onSubmitted: (_) => _tentarAplicar(avisar: true),
          decoration: InputDecoration(
            labelText: rotulo,
            hintText: 'dd/mm/aaaa',
            isDense: true,
            filled: true,
            fillColor: ctx.appInputFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(
              tooltip: 'Escolher no calendário',
              icon: const Icon(Icons.calendar_month_rounded, size: 20),
              onPressed: () => _calendario(c),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          _campo(ctx, _deCtrl, 'Data inicial'),
          const SizedBox(width: 8),
          _campo(ctx, _ateCtrl, 'Data final'),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.cor ?? ctx.appNeon,
              foregroundColor: widget.cor == null ? ctx.appNeonOn : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            ),
            onPressed: () => _tentarAplicar(avisar: true),
            child: const Text('Aplicar'),
          ),
        ]),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_erro!, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.error)),
          ),
      ],
    );
  }
}
