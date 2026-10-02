import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/call_block_service.dart';
import '../theme/theme_context.dart';
import '../widgets/modern_module_ui.dart';
import 'call_block_config_page.dart';

/// Relatório das chamadas recusadas pelo «Bloquear chamadas de
/// desconhecidos»: resumo de hoje, do mês e do ano, gráfico do período,
/// quem mais ligou e a lista dos números — tudo lido do próprio aparelho.
/// «Limpar registros» apaga o histórico e zera o contador.
class CallBlockRelatorioPage extends StatefulWidget {
  const CallBlockRelatorioPage({super.key});

  static Future<void> abrir(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CallBlockRelatorioPage()),
      );

  @override
  State<CallBlockRelatorioPage> createState() => _CallBlockRelatorioPageState();
}

enum _Periodo { dia, mes, ano }

const _grad = [Color(0xFFEF4444), Color(0xFFF97316)];
const _mesesCurtos = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const _mesesLongos = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// «(62) 99999-9999» para números do Brasil; o resto como veio.
String callBlockFormatarNumero(String bruto) {
  if (bruto.trim().isEmpty) return 'Número oculto';
  var d = bruto.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('55') && d.length >= 12) d = d.substring(2);
  if (d.startsWith('0') && d.length >= 11) d = d.substring(1);
  if (d.length == 11) return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  if (d.length == 10) return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  return bruto.trim();
}

class _CallBlockRelatorioPageState extends State<CallBlockRelatorioPage> {
  List<CallBlockRegistro> _todos = const [];
  bool _carregando = true;
  _Periodo _periodo = _Periodo.dia;
  DateTime _ref = DateTime.now();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final r = await CallBlockService.registros();
    if (!mounted) return;
    setState(() {
      _todos = r;
      _carregando = false;
    });
  }

  bool _noPeriodo(DateTime d, _Periodo p, DateTime ref) => switch (p) {
        _Periodo.dia => d.year == ref.year && d.month == ref.month && d.day == ref.day,
        _Periodo.mes => d.year == ref.year && d.month == ref.month,
        _Periodo.ano => d.year == ref.year,
      };

  List<CallBlockRegistro> get _doPeriodo =>
      _todos.where((r) => _noPeriodo(r.quando, _periodo, _ref)).toList();

  int _contar(_Periodo p) {
    final agora = DateTime.now();
    return _todos.where((r) => _noPeriodo(r.quando, p, agora)).length;
  }

  String get _tituloPeriodo {
    final agora = DateTime.now();
    switch (_periodo) {
      case _Periodo.dia:
        final hoje = DateTime(agora.year, agora.month, agora.day);
        final d = DateTime(_ref.year, _ref.month, _ref.day);
        final dif = hoje.difference(d).inDays;
        if (dif == 0) return 'Hoje';
        if (dif == 1) return 'Ontem';
        return '${_two(d.day)}/${_two(d.month)}/${d.year}';
      case _Periodo.mes:
        final t = '${_mesesLongos[_ref.month - 1]} de ${_ref.year}';
        return t[0].toUpperCase() + t.substring(1);
      case _Periodo.ano:
        return '${_ref.year}';
    }
  }

  bool get _podeAvancar {
    final agora = DateTime.now();
    return switch (_periodo) {
      _Periodo.dia => DateTime(_ref.year, _ref.month, _ref.day).isBefore(DateTime(agora.year, agora.month, agora.day)),
      _Periodo.mes => _ref.year < agora.year || (_ref.year == agora.year && _ref.month < agora.month),
      _Periodo.ano => _ref.year < agora.year,
    };
  }

  void _mover(int passo) {
    setState(() {
      _ref = switch (_periodo) {
        _Periodo.dia => DateTime(_ref.year, _ref.month, _ref.day + passo),
        _Periodo.mes => DateTime(_ref.year, _ref.month + passo, 1),
        _Periodo.ano => DateTime(_ref.year + passo, 1, 1),
      };
    });
  }

  void _escolher(_Periodo p) => setState(() {
        _periodo = p;
        _ref = DateTime.now();
      });

  Future<void> _limpar() async {
    final ok = await confirmarLimparRegistrosBloqueio(context, _todos.length);
    if (!ok) return;
    await CallBlockService.limparRegistros();
    if (!mounted) return;
    setState(() => _todos = const []);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registros apagados e contador zerado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _doPeriodo;
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text('Chamadas bloqueadas', style: TextStyle(fontWeight: FontWeight.w900)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: _grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Permitidos, bloqueados e silenciar',
            onPressed: () async {
              await CallBlockConfigPage.abrir(context);
              if (mounted) _carregar();
            },
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Limpar registros',
            onPressed: _todos.isEmpty ? null : _limpar,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  _resumoTopo(),
                  const SizedBox(height: 16),
                  _seletorPeriodo(),
                  const SizedBox(height: 12),
                  _cardGrafico(lista),
                  const SizedBox(height: 16),
                  if (lista.isEmpty)
                    _vazio()
                  else ...[
                    _ranking(lista),
                    const SizedBox(height: 16),
                    _listaRegistros(lista),
                  ],
                  if (_todos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFDC2626)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _limpar,
                      icon: const Icon(Icons.delete_sweep_rounded),
                      label: const Text('Limpar registros', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Os registros ficam só neste aparelho. As ligações recusadas '
                    'também continuam no histórico do telefone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: context.appTextMuted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
    );
  }

  /// Hoje · Este mês · Este ano (toque troca o período do relatório).
  Widget _resumoTopo() {
    Widget kpi(String rotulo, int n, _Periodo p, IconData icone) {
      final sel = _periodo == p && _podeAvancar == false;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _escolher(p),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: sel
                  ? const LinearGradient(colors: _grad, begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              color: sel ? null : ModernModuleUI.cardBg(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: sel ? Colors.transparent : _grad.first.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(color: _grad.first.withValues(alpha: sel ? 0.28 : 0.08), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icone, size: 18, color: sel ? Colors.white : _grad.first),
              const SizedBox(height: 6),
              Text('$n',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900, color: sel ? Colors.white : context.appTextPrimary)),
              Text(rotulo,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white.withValues(alpha: 0.9) : context.appTextSecondary)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      kpi('Hoje', _contar(_Periodo.dia), _Periodo.dia, Icons.today_rounded),
      const SizedBox(width: 10),
      kpi('Este mês', _contar(_Periodo.mes), _Periodo.mes, Icons.calendar_view_month_rounded),
      const SizedBox(width: 10),
      kpi('Este ano', _contar(_Periodo.ano), _Periodo.ano, Icons.calendar_month_rounded),
    ]);
  }

  Widget _seletorPeriodo() {
    Widget chip(String t, _Periodo p) {
      final sel = _periodo == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => _escolher(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: sel ? const LinearGradient(colors: _grad) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(t,
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: sel ? Colors.white : context.appTextSecondary)),
          ),
        ),
      );
    }

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ModernModuleUI.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ModernModuleUI.subtleBorder(context)),
        ),
        child: Row(children: [chip('Dia', _Periodo.dia), chip('Mês', _Periodo.mes), chip('Ano', _Periodo.ano)]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        IconButton(onPressed: () => _mover(-1), icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(
          child: Text(_tituloPeriodo,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
        ),
        IconButton(
          onPressed: _podeAvancar ? () => _mover(1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
    ]);
  }

  /// Barras: por hora (dia), por dia (mês) ou por mês (ano).
  Widget _cardGrafico(List<CallBlockRegistro> lista) {
    final int n;
    final String Function(int) rotulo;
    final int Function(DateTime) indice;
    switch (_periodo) {
      case _Periodo.dia:
        n = 24;
        rotulo = (i) => i % 3 == 0 ? '${_two(i)}h' : '';
        indice = (d) => d.hour;
      case _Periodo.mes:
        n = DateUtils.getDaysInMonth(_ref.year, _ref.month);
        rotulo = (i) => (i + 1) == 1 || (i + 1) % 5 == 0 ? '${i + 1}' : '';
        indice = (d) => d.day - 1;
      case _Periodo.ano:
        n = 12;
        rotulo = (i) => _mesesCurtos[i];
        indice = (d) => d.month - 1;
    }
    final valores = List<int>.filled(n, 0);
    for (final r in lista) {
      final i = indice(r.quando);
      if (i >= 0 && i < n) valores[i]++;
    }
    final maior = valores.fold<int>(0, (a, b) => b > a ? b : a);
    var pico = -1;
    for (var i = 0; i < n; i++) {
      if (valores[i] == maior && maior > 0) {
        pico = i;
        break;
      }
    }
    final numeros = lista.map((r) => r.numero.replaceAll(RegExp(r'\D'), '')).toSet().length;
    final ocultos = lista.where((r) => r.numero.trim().isEmpty).length;
    final picoTexto = pico < 0
        ? '—'
        : switch (_periodo) {
            _Periodo.dia => '${_two(pico)}h',
            _Periodo.mes => 'dia ${pico + 1}',
            _Periodo.ano => _mesesCurtos[pico],
          };
    final poucas = n <= 12;

    Widget mini(String t, String v, IconData ic) => Expanded(
          child: Row(children: [
            Icon(ic, size: 16, color: _grad.first),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: context.appTextPrimary)),
                Text(t, style: TextStyle(fontSize: 11, color: context.appTextSecondary, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: ModernModuleUI.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ModernModuleUI.subtleBorder(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('${lista.length}',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _grad.first)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(lista.length == 1 ? 'chamada bloqueada' : 'chamadas bloqueadas',
                style: TextStyle(fontWeight: FontWeight.w800, color: context.appTextSecondary)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          mini('números', '$numeros', Icons.dialpad_rounded),
          mini('ocultos', '$ocultos', Icons.visibility_off_rounded),
          mini('pico', picoTexto, Icons.trending_up_rounded),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 190,
          child: BarChart(
            BarChartData(
              maxY: maior <= 0 ? 1 : maior * 1.1,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: context.appBorderSubtle, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF0F172A),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (g, gi, rod, ri) {
                    final quando = switch (_periodo) {
                      _Periodo.dia => '${_two(gi)}h às ${_two(gi)}h59',
                      _Periodo.mes => '${_two(gi + 1)}/${_two(_ref.month)}',
                      _Periodo.ano => '${_mesesCurtos[gi]}/${_ref.year}',
                    };
                    final v = valores[gi];
                    return BarTooltipItem(
                      '$quando\n$v ${v == 1 ? 'chamada' : 'chamadas'}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                // Quantidade em cima de cada barra (no ano, sempre visível).
                topTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: poucas,
                    reservedSize: 18,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= n || valores[i] == 0) return const SizedBox.shrink();
                      return Text('${valores[i]}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: context.appTextPrimary));
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= n) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(rotulo(i),
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < n; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: valores[i].toDouble(),
                      width: poucas ? 16 : (n > 24 ? 5 : 7),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      gradient: const LinearGradient(
                        colors: _grad,
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  /// Quem mais ligou no período (top 5).
  Widget _ranking(List<CallBlockRegistro> lista) {
    final porNumero = <String, List<CallBlockRegistro>>{};
    for (final r in lista) {
      porNumero.putIfAbsent(r.numero.trim(), () => []).add(r);
    }
    final top = porNumero.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final maior = top.isEmpty ? 1 : top.first.value.length;
    return _secao(
      'Quem mais ligou',
      Icons.leaderboard_rounded,
      Column(children: [
        for (final (i, e) in top.take(5).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: i == 0 ? const LinearGradient(colors: _grad) : null,
                  color: i == 0 ? null : _grad.first.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 12, color: i == 0 ? Colors.white : _grad.first)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(callBlockFormatarNumero(e.key),
                          style: TextStyle(fontWeight: FontWeight.w800, color: context.appTextPrimary)),
                    ),
                    Text('${e.value.length}×',
                        style: TextStyle(fontWeight: FontWeight.w900, color: _grad.first)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: e.value.length / maior,
                      minHeight: 6,
                      backgroundColor: _grad.first.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation(_grad.last),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  /// Lista do período, agrupada por dia (mais recentes primeiro).
  Widget _listaRegistros(List<CallBlockRegistro> lista) {
    final itens = <Widget>[];
    String? diaAtual;
    for (final r in lista) {
      final d = r.quando;
      final dia = '${_two(d.day)}/${_two(d.month)}/${d.year}';
      if (dia != diaAtual) {
        diaAtual = dia;
        itens.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(dia,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: context.appTextSecondary)),
        ));
      }
      final oculto = r.numero.trim().isEmpty;
      itens.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _grad.first.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _grad.first.withValues(alpha: 0.15)),
        ),
        child: Column(children: [
          ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: _grad.first.withValues(alpha: 0.14),
            child: Icon(oculto ? Icons.visibility_off_rounded : Icons.call_end_rounded, size: 17, color: _grad.first),
          ),
          title: Text(callBlockFormatarNumero(r.numero),
              style: TextStyle(fontWeight: FontWeight.w800, color: context.appTextPrimary)),
          subtitle: Text('Recusada às ${_two(d.hour)}:${_two(d.minute)}',
              style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
          trailing: oculto
              ? null
              : IconButton(
                  tooltip: 'Copiar número',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: r.numero));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Número copiado.')),
                    );
                  },
                ),
          ),
          // Número conhecido? «Permitir» ou «Adicionar aos contatos» — ele sai
          // da lista na hora.
          if (!oculto)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(children: [
                Expanded(
                  child: _botaoAcao('Permitir', Icons.check_circle_rounded,
                      const [Color(0xFF10B981), Color(0xFF34D399)], () => _permitir(r.numero)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _botaoAcao('Adicionar aos contatos', Icons.person_add_alt_1_rounded,
                      const [Color(0xFF2563EB), Color(0xFF38BDF8)], () => _adicionarContato(r.numero)),
                ),
              ]),
            ),
        ]),
      ));
    }
    return _secao('Números bloqueados', Icons.phone_disabled_rounded, Column(children: itens));
  }

  Widget _botaoAcao(String t, IconData i, List<Color> grad, VoidCallback onTap) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: grad),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: grad.first.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onTap,
          icon: Icon(i, size: 17),
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
          ),
        ),
      );

  Future<void> _permitir(String numero) async {
    await CallBlockService.permitirNumero(numero);
    if (!mounted) return;
    await _carregar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${callBlockFormatarNumero(numero)} agora pode ligar e saiu da lista.'),
    ));
  }

  Future<void> _adicionarContato(String numero) async {
    final virou = await CallBlockService.adicionarAosContatos(numero);
    if (!mounted) return;
    await _carregar();
    if (!mounted || !virou) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${callBlockFormatarNumero(numero)} salvo nos contatos e saiu da lista.'),
    ));
  }

  Widget _secao(String titulo, IconData icone, Widget filho) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        decoration: BoxDecoration(
          color: ModernModuleUI.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ModernModuleUI.subtleBorder(context)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icone, size: 18, color: _grad.first),
            const SizedBox(width: 8),
            Text(titulo, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
          ]),
          const SizedBox(height: 10),
          filho,
        ]),
      );

  Widget _vazio() => Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: ModernModuleUI.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ModernModuleUI.subtleBorder(context)),
        ),
        child: Column(children: [
          Icon(Icons.verified_user_rounded, size: 40, color: Colors.green.shade500),
          const SizedBox(height: 8),
          Text('Nenhuma chamada bloqueada neste período',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, color: context.appTextPrimary)),
        ]),
      );
}

/// Prévia moderna antes de apagar: quantos registros saem e o aviso de que
/// não tem volta. Devolve true se a pessoa confirmou.
Future<bool> confirmarLimparRegistrosBloqueio(BuildContext context, int total) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: ModernModuleUI.cardBg(context),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: _grad), shape: BoxShape.circle),
            child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 30),
          ),
          Text('Limpar registros?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
          const SizedBox(height: 6),
          Text(
            total == 0
                ? 'O contador de chamadas bloqueadas volta a zero.'
                : 'Apaga ${total == 1 ? 'o registro' : 'os $total registros'} de chamadas bloqueadas e zera o contador. '
                    'O bloqueio continua funcionando.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ctx.appTextSecondary, height: 1.35),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Limpar agora', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ]),
      ),
    ),
  );
  return ok == true;
}
