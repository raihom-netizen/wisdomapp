import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/currency_formats.dart';
import '../theme/theme_context.dart';

/// Uma fatia do gráfico de categorias.
class CategoriaFatia {
  CategoriaFatia({required this.nome, required this.valor, this.qtd = 0, this.categoriaReal = '', this.semCategoria = false});

  final String nome;
  double valor;
  int qtd;

  /// Categoria gravada no lançamento (para abrir a lista certa ao tocar).
  final String categoriaReal;

  /// Lançamento sem categoria de verdade (agrupado pela forma de pagamento).
  final bool semCategoria;
}

bool _generica(String c) {
  final t = c.trim().toLowerCase();
  return t.isEmpty || t == 'outros' || t == 'outras' || t == 'sem categoria';
}

/// Nome da fatia para um lançamento.
///
/// Lançamento com categoria de verdade vai na categoria. Os «Outros» (quase
/// sempre vindos do banco conectado, que não informa categoria: Pix enviado,
/// boleto, saque) eram UMA fatia de 97% que não dizia nada — agora saem
/// separados pela forma de pagamento, marcados como «sem categoria».
({String nome, String real, bool semCategoria}) categoriaDoGrafico(Map<String, dynamic> d) {
  final real = '${d['category'] ?? ''}'.trim();
  if (!_generica(real)) return (nome: real, real: real, semCategoria: false);
  final desc = '${d['description'] ?? ''} ${d['openFinanceDescription'] ?? ''}'.toUpperCase();
  final forma = '${d['formaPagamentoRotulo'] ?? d['formaPagamento'] ?? ''}'.toLowerCase();
  final bruto = '${d['openFinanceRawCategory'] ?? ''}'.toUpperCase();
  final realOuOutros = real.isEmpty ? 'Outros' : real;
  String nome;
  if (desc.contains('SAQUE')) {
    nome = 'Saques';
  } else if (forma.contains('boleto') || desc.contains('BOLETO')) {
    nome = 'Boletos';
  } else if (desc.contains('QR COD') || desc.contains('COMPRA CARTAO') || desc.contains('DEBITO')) {
    nome = 'Pix/débito em lojas';
  } else if (forma.contains('pix') || desc.contains('PIX') || bruto.startsWith('TRANSFER') || desc.contains('TRANSFER')) {
    nome = 'Pix e transferências';
  } else {
    nome = 'Outros';
  }
  return (nome: nome, real: realOuOutros, semCategoria: true);
}

/// Agrupa despesas por [categoriaDoGrafico], da maior para a menor.
List<CategoriaFatia> agruparCategorias(Iterable<Map<String, dynamic>> despesas) {
  final mapa = <String, CategoriaFatia>{};
  for (final d in despesas) {
    // Fixa quitada como controle (Finance Pro no Controle Total): fora do gráfico.
    if ((d['status'] ?? 'paid').toString() == 'paid' && d['baixaSemSaldo'] == true) continue;
    final c = categoriaDoGrafico(d);
    final v = ((d['amount'] as num?) ?? 0).toDouble().abs();
    final f = mapa.putIfAbsent(
        c.nome, () => CategoriaFatia(nome: c.nome, valor: 0, categoriaReal: c.real, semCategoria: c.semCategoria));
    f.valor += v;
    f.qtd++;
  }
  return mapa.values.where((f) => f.valor > 0).toList()..sort((a, b) => b.valor.compareTo(a.valor));
}

/// Ícone da categoria pelo nome — Material Icons, que vêm DENTRO do app.
/// Emoji dependia da fonte do aparelho/navegador e, no celular, podia sair
/// como quadrado vazio; o ícone aparece igual em web, Android e iOS.
IconData iconeDaCategoria(String nome) {
  const trocas = {'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c'};
  var n = nome.toLowerCase();
  trocas.forEach((k, v) => n = n.replaceAll(k, v));
  const mapa = <String, IconData>{
    'combust': Icons.local_gas_station_rounded, 'gasolina': Icons.local_gas_station_rounded, 'posto': Icons.local_gas_station_rounded,
    'supermerc': Icons.shopping_cart_rounded, 'mercado': Icons.shopping_cart_rounded, 'feira': Icons.eco_rounded,
    'padaria': Icons.bakery_dining_rounded,
    'aliment': Icons.restaurant_rounded, 'restaur': Icons.restaurant_rounded, 'lanche': Icons.lunch_dining_rounded,
    'ifood': Icons.delivery_dining_rounded, 'delivery': Icons.delivery_dining_rounded, 'cafe': Icons.local_cafe_rounded,
    'uber': Icons.local_taxi_rounded, 'taxi': Icons.local_taxi_rounded, 'transporte': Icons.directions_bus_rounded,
    'onibus': Icons.directions_bus_rounded, 'estacion': Icons.local_parking_rounded, 'pedagio': Icons.toll_rounded,
    'veicul': Icons.directions_car_rounded, 'carro': Icons.directions_car_rounded, 'moto': Icons.two_wheeler_rounded,
    'manutenc': Icons.build_rounded, 'oficina': Icons.build_rounded,
    'farmac': Icons.medication_rounded, 'plano de saude': Icons.local_hospital_rounded, 'saude': Icons.health_and_safety_rounded,
    'medic': Icons.medical_services_rounded, 'dentist': Icons.medical_services_rounded, 'hospital': Icons.local_hospital_rounded,
    'academia': Icons.fitness_center_rounded, 'esporte': Icons.sports_soccer_rounded,
    'educac': Icons.school_rounded, 'escola': Icons.school_rounded, 'curso': Icons.school_rounded,
    'faculdade': Icons.school_rounded, 'livro': Icons.menu_book_rounded,
    'aluguel': Icons.home_rounded, 'moradia': Icons.home_rounded, 'casa': Icons.home_rounded,
    'condominio': Icons.apartment_rounded, 'reforma': Icons.handyman_rounded, 'construc': Icons.construction_rounded,
    'energia': Icons.bolt_rounded, 'luz': Icons.lightbulb_rounded, 'agua': Icons.water_drop_rounded,
    'gas': Icons.local_fire_department_rounded, 'internet': Icons.wifi_rounded, 'telefon': Icons.phone_iphone_rounded,
    'celular': Icons.phone_iphone_rounded,
    'assinatura': Icons.subscriptions_rounded, 'streaming': Icons.live_tv_rounded, 'tv': Icons.live_tv_rounded,
    'netflix': Icons.live_tv_rounded, 'spotify': Icons.music_note_rounded,
    'lazer': Icons.celebration_rounded, 'viage': Icons.flight_rounded, 'hotel': Icons.hotel_rounded,
    'cinema': Icons.movie_rounded, 'bar': Icons.sports_bar_rounded, 'festa': Icons.celebration_rounded,
    'roupa': Icons.checkroom_rounded, 'vestuar': Icons.checkroom_rounded, 'calcad': Icons.checkroom_rounded,
    'beleza': Icons.face_retouching_natural_rounded, 'cabelo': Icons.content_cut_rounded,
    'cuidados': Icons.spa_rounded, 'cosmet': Icons.spa_rounded,
    'pet': Icons.pets_rounded, 'veterin': Icons.pets_rounded, 'racao': Icons.pets_rounded,
    'seguro': Icons.shield_rounded, 'imposto': Icons.receipt_long_rounded, 'taxa': Icons.receipt_long_rounded,
    'tarifa': Icons.account_balance_rounded, 'iof': Icons.receipt_long_rounded, 'ipva': Icons.directions_car_rounded,
    'iptu': Icons.home_work_rounded,
    'emprest': Icons.request_quote_rounded, 'juros': Icons.trending_up_rounded, 'financiament': Icons.account_balance_rounded,
    'consorcio': Icons.handshake_rounded, 'cartao': Icons.credit_card_rounded, 'fatura': Icons.credit_card_rounded,
    'investim': Icons.show_chart_rounded, 'poupanc': Icons.savings_rounded, 'doac': Icons.volunteer_activism_rounded,
    'dizimo': Icons.church_rounded, 'oferta': Icons.church_rounded, 'igreja': Icons.church_rounded,
    'contribu': Icons.volunteer_activism_rounded, 'presente': Icons.card_giftcard_rounded,
    'compras online': Icons.shopping_bag_rounded, 'pix/debito': Icons.point_of_sale_rounded, 'compras': Icons.shopping_bag_rounded,
    'shopee': Icons.shopping_bag_rounded, 'amazon': Icons.local_shipping_rounded, 'eletron': Icons.devices_rounded,
    'pix e transfer': Icons.swap_horiz_rounded, 'transfer': Icons.swap_horiz_rounded, 'boleto': Icons.receipt_rounded,
    'saque': Icons.atm_rounded,
    'salario': Icons.payments_rounded, 'freela': Icons.work_rounded, 'venda': Icons.sell_rounded,
    'comiss': Icons.percent_rounded, 'bonus': Icons.emoji_events_rounded, 'plantao': Icons.local_police_rounded,
    'geral': Icons.inventory_2_rounded, 'outros': Icons.category_rounded,
  };
  for (final e in mapa.entries) {
    if (n.contains(e.key)) return e.value;
  }
  return Icons.label_rounded;
}

/// Abas do gráfico de categorias.
enum CategoriasModo { icones, pizza, barras, meses }

/// Última aba escolhida — uma só no app inteiro, lembrada no aparelho.
final ValueNotifier<CategoriasModo> categoriasModo = ValueNotifier(CategoriasModo.icones);
bool _modoCarregado = false;

Future<void> _carregarModo() async {
  if (_modoCarregado) return;
  _modoCarregado = true;
  await _carregarOrdem();
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('grafico_categorias_modo2');
    for (final m in CategoriasModo.values) {
      if (m.name == s) categoriasModo.value = m;
    }
  } catch (_) {}
}

/// Ordem das abas — o usuário arrasta para reordenar; fica salva.
final ValueNotifier<List<CategoriasModo>> categoriasOrdem = ValueNotifier(List.of(CategoriasModo.values));

Future<void> _carregarOrdem() async {
  try {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('grafico_categorias_ordem');
    if (l == null) return;
    final lidos = <CategoriasModo>[];
    for (final n in l) {
      for (final m in CategoriasModo.values) {
        if (m.name == n && !lidos.contains(m)) lidos.add(m);
      }
    }
    // Aba nova (de versão futura) entra no fim.
    for (final m in CategoriasModo.values) {
      if (!lidos.contains(m)) lidos.add(m);
    }
    categoriasOrdem.value = lidos;
  } catch (_) {}
}

Future<void> _gravarOrdem(List<CategoriasModo> ordem) async {
  categoriasOrdem.value = ordem;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('grafico_categorias_ordem', [for (final m in ordem) m.name]);
  } catch (_) {}
}

Future<void> _gravarModo(CategoriasModo m) async {
  categoriasModo.value = m;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('grafico_categorias_modo2', m.name);
  } catch (_) {}
}

Color _clarear(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _escurecer(Color c, double t) => Color.lerp(c, Colors.black, t)!;

/// Cores vivas por categoria; sem categoria em ardósia.
const _kPaleta = [
  Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFFF59E0B), Color(0xFF10B981),
  Color(0xFF3B82F6), Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF06B6D4),
  Color(0xFFF97316), Color(0xFF84CC16), Color(0xFFD946EF), Color(0xFF0EA5E9),
];
const _kCinzas = [Color(0xFF64748B), Color(0xFF94A3B8), Color(0xFF475569), Color(0xFF7C8BA1)];

List<Color> coresDasFatias(List<CategoriaFatia> fatias) {
  var iReal = 0, iCinza = 0;
  return [
    for (final f in fatias)
      f.semCategoria ? _kCinzas[iCinza++ % _kCinzas.length] : _kPaleta[iReal++ % _kPaleta.length],
  ];
}

String _pct(double v, double total) =>
    '${(total > 0 ? v / total * 100 : 0).toStringAsFixed(1).replaceAll('.', ',')}%';

/// Gráfico de categorias com 3 abas (Ícones · Pizza · Barras) e, quando o
/// painel passa [mesAMes], a 4ª aba do comparativo. As categorias rolam na
/// horizontal (não empurram a tela) e há o botão de tela cheia. Tocar numa
/// categoria chama [onAbrir] — o dono abre a lista de lançamentos editável.
class CategoriasRoscaModerna extends StatefulWidget {
  const CategoriasRoscaModerna({
    super.key,
    required this.fatias,
    this.onAbrir,
    this.titulo = 'Despesas',
    this.mesAMes,
    this.cabecalho,
    this.telaCheia = false,
    this.textoVazio,
  });

  /// Texto quando não há fatias. Nulo = «Nenhuma despesa/receita no período»
  /// (o do Financeiro); Vendas passa o seu («Nenhum recebimento…»).
  final String? textoVazio;

  /// Já está na tela cheia: sem o botão de abrir de novo.
  final bool telaCheia;

  final List<CategoriaFatia> fatias;
  final void Function(CategoriaFatia fatia)? onAbrir;
  final String titulo;

  /// Comparativo mês a mês (4ª aba). Nulo = a aba não aparece.
  final Widget? mesAMes;

  /// Linha extra acima das abas (o seletor de período do painel).
  final Widget? cabecalho;

  @override
  State<CategoriasRoscaModerna> createState() => _CategoriasRoscaModernaState();
}

class _CategoriasRoscaModernaState extends State<CategoriasRoscaModerna> {
  int _tocada = -1;

  @override
  void initState() {
    super.initState();
    _carregarModo();
  }

  void _abrir(int i, CategoriaFatia f) {
    setState(() => _tocada = i);
    widget.onAbrir?.call(f);
  }

  void _telaCheia(List<CategoriaFatia> fatias, List<Color> cores, double total) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CategoriasTelaCheia(
        titulo: widget.titulo,
        fatias: fatias,
        cores: cores,
        total: total,
        onAbrir: widget.onAbrir,
        mesAMes: widget.mesAMes,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fatias = widget.fatias;
    final total = fatias.fold<double>(0, (s, f) => s + f.valor);
    final cores = coresDasFatias(fatias);
    final semCat = fatias.where((f) => f.semCategoria).toList();
    final semCatValor = semCat.fold<double>(0, (s, f) => s + f.valor);
    final semCatQtd = semCat.fold<int>(0, (s, f) => s + f.qtd);

    return ValueListenableBuilder<CategoriasModo>(
      valueListenable: categoriasModo,
      builder: (context, modoGravado, _) {
        final modo = modoGravado == CategoriasModo.meses && widget.mesAMes == null ? CategoriasModo.icones : modoGravado;
        Widget corpo;
        if (modo == CategoriasModo.meses) {
          corpo = widget.mesAMes!;
        } else if (fatias.isEmpty) {
          corpo = Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
                child: Text(
                    widget.textoVazio ??
                        'Nenhuma ${widget.titulo.toLowerCase() == 'receitas' ? 'receita' : 'despesa'} no período.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, color: context.appTextMuted))),
          );
        } else {
          corpo = switch (modo) {
            CategoriasModo.pizza => _pizza(context, fatias, cores, total),
            CategoriasModo.barras => _barras(context, fatias, cores, total),
            _ => _icones(context, fatias, cores, total),
          };
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (widget.cabecalho != null) ...[widget.cabecalho!, const SizedBox(height: 10)],
          Row(children: [
            Expanded(
              child: Text('${widget.titulo} · ${CurrencyFormats.formatBRL(total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
            ),
            if (fatias.isNotEmpty && modo != CategoriasModo.meses && !widget.telaCheia)
              IconButton(
                tooltip: 'Ver em tela cheia',
                visualDensity: VisualDensity.compact,
                onPressed: () => _telaCheia(fatias, cores, total),
                icon: const Icon(Icons.open_in_full_rounded, size: 20),
              ),
          ]),
          const SizedBox(height: 6),
          _Abas(modo: modo, comMeses: widget.mesAMes != null, onModo: _gravarModo),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: KeyedSubtree(key: ValueKey(modo), child: corpo),
          ),
          if (modo != CategoriasModo.meses && semCatValor > 0 && total > 0 && semCatValor / total >= 0.2)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFFF59E0B).withValues(alpha: 0.18),
                    const Color(0xFFF97316).withValues(alpha: 0.08),
                  ]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                ),
                child: Row(children: [
                  const Icon(Icons.label_off_rounded, size: 20, color: Color(0xFFD97706)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${CurrencyFormats.formatBRL(semCatValor)} em $semCatQtd lançamento${semCatQtd == 1 ? '' : 's'} sem categoria '
                      '(o banco não informa: Pix, boleto, saque). Toque num item cinza para categorizar.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.appTextPrimary, height: 1.3),
                    ),
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  // ── 1) Ícones ─────────────────────────────────────────────────────────────

  Widget _icones(BuildContext context, List<CategoriaFatia> fatias, List<Color> cores, double total) {
    // Duas linhas que rolam na horizontal: cabem muitas categorias sem
    // empurrar o resto da tela.
    final linhas = fatias.length > 4 ? 2 : 1;
    return SizedBox(
      height: linhas == 2 ? 262 : 128,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: linhas,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 124,
        ),
        itemCount: fatias.length,
        itemBuilder: (context, i) => _TileIcone(
          fatia: fatias[i],
          cor: cores[i],
          pct: _pct(fatias[i].valor, total),
          ativo: i == _tocada,
          onTap: () => _abrir(i, fatias[i]),
        ),
      ),
    );
  }

  // ── 2) Pizza 3D ───────────────────────────────────────────────────────────

  Widget _pizza(BuildContext context, List<CategoriaFatia> fatias, List<Color> cores, double total) {
    final sel = _tocada >= 0 && _tocada < fatias.length ? fatias[_tocada] : null;
    List<PieChartSectionData> secoes({required bool fundo}) => [
          for (var i = 0; i < fatias.length; i++)
            PieChartSectionData(
              value: fatias[i].valor,
              radius: i == _tocada ? 36 : 28,
              showTitle: !fundo && total > 0 && fatias[i].valor / total >= 0.07,
              title: '${(fatias[i].valor / total * 100).round()}%',
              titleStyle: const TextStyle(
                  color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, shadows: [Shadow(blurRadius: 3)]),
              titlePositionPercentageOffset: 0.55,
              gradient: fundo
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_clarear(cores[i], 0.28), cores[i], _escurecer(cores[i], 0.18)],
                    ),
              color: fundo ? _escurecer(cores[i], 0.42) : cores[i],
              borderSide: fundo ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
            ),
        ];
    final rosca = SizedBox(
      width: 210,
      height: 222,
      child: Stack(alignment: Alignment.topCenter, children: [
        Positioned(
          bottom: 0,
          child: Container(
            width: 170,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, spreadRadius: 2)],
            ),
          ),
        ),
        Positioned(
          top: 9,
          child: SizedBox(
            width: 210,
            height: 204,
            child: IgnorePointer(
              child: PieChart(
                PieChartData(sectionsSpace: 2.5, centerSpaceRadius: 62, startDegreeOffset: -90, sections: secoes(fundo: true)),
                duration: const Duration(milliseconds: 260),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 210,
          height: 204,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2.5,
                centerSpaceRadius: 62,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(touchCallback: (e, r) {
                  if (!e.isInterestedForInteractions) return;
                  final i = r?.touchedSection?.touchedSectionIndex ?? -1;
                  setState(() => _tocada = i);
                  if (e is FlTapUpEvent && i >= 0 && i < fatias.length) widget.onAbrir?.call(fatias[i]);
                }),
                sections: secoes(fundo: false),
              ),
              duration: const Duration(milliseconds: 260),
            ),
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.appSurface,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(sel == null ? widget.titulo : sel.nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
                FittedBox(
                  child: Text(CurrencyFormats.formatBRL(sel?.valor ?? total),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
                ),
                if (sel != null)
                  Text(_pct(sel.valor, total),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: cores[_tocada])),
              ]),
            ),
          ]),
        ),
      ]),
    );
    // Legenda em faixa horizontal: não ocupa a tela toda.
    final faixa = SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: fatias.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _ChipCategoria(
          fatia: fatias[i],
          cor: cores[i],
          pct: _pct(fatias[i].valor, total),
          ativo: i == _tocada,
          onTap: () => _abrir(i, fatias[i]),
        ),
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [Center(child: rosca), const SizedBox(height: 12), faixa]);
  }

  // ── 3) Barras 3D ──────────────────────────────────────────────────────────

  Widget _barras(BuildContext context, List<CategoriaFatia> fatias, List<Color> cores, double total) {
    final limite = math.min(6, fatias.length);
    final maior = fatias.first.valor <= 0 ? 1.0 : fatias.first.valor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < limite; i++)
        LinhaBarra3d(
          fatia: fatias[i],
          cor: cores[i],
          fracao: fatias[i].valor / maior,
          pct: _pct(fatias[i].valor, total),
          ativo: i == _tocada,
          atraso: i,
          onTap: () => _abrir(i, fatias[i]),
        ),
      if (fatias.length > limite)
        TextButton.icon(
          onPressed: () => _telaCheia(fatias, cores, total),
          icon: const Icon(Icons.open_in_full_rounded, size: 18),
          label: Text('Ver todas as ${fatias.length} em tela cheia'),
        ),
    ]);
  }
}

/// Abas Ícones · Pizza · Barras (· Mês a mês). Toque escolhe; segurar e
/// arrastar muda a ordem — a ordem fica salva no aparelho.
class _Abas extends StatelessWidget {
  const _Abas({required this.modo, required this.comMeses, required this.onModo});
  final CategoriasModo modo;
  final bool comMeses;
  final void Function(CategoriasModo) onModo;

  static const _visual = <CategoriasModo, (IconData, String, List<Color>)>{
    CategoriasModo.icones: (Icons.grid_view_rounded, 'Ícones', [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
    CategoriasModo.pizza: (Icons.donut_large_rounded, 'Pizza', [Color(0xFFEC4899), Color(0xFFF97316)]),
    CategoriasModo.barras: (Icons.bar_chart_rounded, 'Barras', [Color(0xFF0EA5E9), Color(0xFF10B981)]),
    CategoriasModo.meses: (Icons.calendar_month_rounded, 'Comparativo', [Color(0xFFF59E0B), Color(0xFFEF4444)]),
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CategoriasModo>>(
      valueListenable: categoriasOrdem,
      builder: (context, ordemTodas, _) {
        final ordem = [for (final m in ordemTodas) if (comMeses || m != CategoriasModo.meses) m];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          LayoutBuilder(builder: (context, c) {
            const gap = 6.0;
            final w = (c.maxWidth - gap * (ordem.length - 1)) / ordem.length;
            return SizedBox(
              height: 40,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ordem.length,
                proxyDecorator: (child, _, __) => Material(color: Colors.transparent, elevation: 6, child: child),
                // onReorderItem já desconta o item retirado do índice novo.
                onReorderItem: (de, para) {
                  final nova = List.of(ordem);
                  final m = nova.removeAt(de);
                  nova.insert(para, m);
                  // Abas escondidas (comparativo fora do painel) mantêm o lugar no fim.
                  for (final x in ordemTodas) {
                    if (!nova.contains(x)) nova.add(x);
                  }
                  _gravarOrdem(nova);
                },
                itemBuilder: (context, i) {
                  final m = ordem[i];
                  final (icone, rotulo, g) = _visual[m]!;
                  final sel = m == modo;
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(m),
                    index: i,
                    child: Padding(
                      padding: EdgeInsets.only(right: i == ordem.length - 1 ? 0 : gap),
                      child: SizedBox(
                        width: w,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onModo(m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: sel ? LinearGradient(colors: g) : null,
                              color: sel ? null : context.appChipIdleBg,
                              border: Border.all(color: sel ? Colors.transparent : context.appChipIdleBorder),
                              boxShadow: sel
                                  ? [BoxShadow(color: g.first.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))]
                                  : null,
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(icone, size: 16, color: sel ? Colors.white : g.first),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(rotulo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: sel ? Colors.white : context.appTextSecondary)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Segure e arraste para mudar a ordem das abas.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: context.appTextMuted)),
          ),
        ]);
      },
    );
  }
}

/// Quadrado da aba Ícones: emoji grande numa bolha colorida, nome, valor e %.
class _TileIcone extends StatelessWidget {
  const _TileIcone({required this.fatia, required this.cor, required this.pct, required this.ativo, required this.onTap});
  final CategoriaFatia fatia;
  final Color cor;
  final String pct;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cor.withValues(alpha: ativo ? 0.30 : 0.18), cor.withValues(alpha: 0.06)],
            ),
            border: Border.all(color: cor.withValues(alpha: ativo ? 0.9 : 0.35), width: ativo ? 2 : 1),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_clarear(cor, 0.25), _escurecer(cor, 0.15)],
                  ),
                  boxShadow: [BoxShadow(color: cor.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Icon(iconeDaCategoria(fatia.nome), size: 24, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(fatia.nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.appTextPrimary)),
              FittedBox(
                child: Text(CurrencyFormats.formatBRL(fatia.valor),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
              ),
              Text(pct, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: _escurecer(cor, 0.1))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Chip da legenda da pizza (faixa horizontal).
class _ChipCategoria extends StatelessWidget {
  const _ChipCategoria({required this.fatia, required this.cor, required this.pct, required this.ativo, required this.onTap});
  final CategoriaFatia fatia;
  final Color cor;
  final String pct;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cor.withValues(alpha: ativo ? 0.22 : 0.10),
          border: Border.all(color: cor.withValues(alpha: ativo ? 0.9 : 0.35), width: ativo ? 1.6 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(iconeDaCategoria(fatia.nome), size: 18, color: cor),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(fatia.nome, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.appTextPrimary)),
            Text('${CurrencyFormats.formatBRL(fatia.valor)} · $pct',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
          ]),
        ]),
      ),
    );
  }
}

/// Linha de barra horizontal 3D (rótulo com emoji · barra · % e R$).
class LinhaBarra3d extends StatelessWidget {
  const LinhaBarra3d({
    super.key,
    required this.fatia,
    required this.cor,
    required this.fracao,
    required this.pct,
    this.ativo = false,
    this.atraso = 0,
    this.onTap,
  });
  final CategoriaFatia fatia;
  final Color cor;
  final double fracao;
  final String pct;
  final bool ativo;
  final int atraso;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: LayoutBuilder(builder: (context, c) {
          final rotuloW = c.maxWidth < 420 ? 100.0 : 160.0;
          final valorW = c.maxWidth < 420 ? 80.0 : 120.0;
          final area = math.max(40.0, c.maxWidth - rotuloW - valorW - 20);
          return Row(children: [
            SizedBox(
              width: rotuloW,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Icon(iconeDaCategoria(fatia.nome), size: 16, color: cor),
                const SizedBox(width: 5),
                Flexible(child: Text(fatia.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: ativo ? FontWeight.w900 : FontWeight.w700,
                      color: fatia.semCategoria ? context.appTextMuted : context.appTextPrimary)))]),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: area,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fracao.clamp(0.0, 1.0)),
                  duration: Duration(milliseconds: 450 + atraso * 60),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, __) => barra3d(cor, math.max(6.0, area * t)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: valorW,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pct, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(CurrencyFormats.formatBRL(fatia.valor),
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}

/// Barra horizontal com volume: frente em degradê com faixa de brilho,
/// lateral escura embaixo e sombra.
Widget barra3d(Color cor, double largura, {double altura = 32}) {
  return SizedBox(
    width: largura,
    height: altura,
    child: Stack(children: [
      Positioned(
        left: 3,
        right: 0,
        top: 5,
        bottom: 0,
        child: Container(
          decoration: BoxDecoration(
            color: _escurecer(cor, 0.4),
            borderRadius: BorderRadius.circular(7),
            boxShadow: [BoxShadow(color: cor.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 4))],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 3,
        top: 0,
        bottom: 5,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_clarear(cor, 0.30), cor, _escurecer(cor, 0.12)],
            ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 8,
              margin: const EdgeInsets.fromLTRB(5, 3, 5, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
        ),
      ),
    ]),
  );
}

/// Tela cheia com TODAS as categorias em barras 3D, tocáveis, e Retornar.
class _CategoriasTelaCheia extends StatelessWidget {
  const _CategoriasTelaCheia({
    required this.titulo,
    required this.fatias,
    required this.cores,
    required this.total,
    this.onAbrir,
    this.mesAMes,
  });
  final String titulo;
  final List<CategoriaFatia> fatias;
  final List<Color> cores;
  final double total;
  final void Function(CategoriaFatia)? onAbrir;
  final Widget? mesAMes;

  @override
  Widget build(BuildContext context) {
    final maior = fatias.isEmpty || fatias.first.valor <= 0 ? 1.0 : fatias.first.valor;
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: Text('$titulo por categoria', style: const TextStyle(fontWeight: FontWeight.w900)),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFFDB2777)])),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF312E81)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total de ${titulo.toLowerCase()}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              Text(CurrencyFormats.formatBRL(total),
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              Text('${fatias.length} categorias · toque numa para ver e editar os lançamentos',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 16),
          // As mesmas abas da tela de origem (Ícones · Pizza · Barras ·
          // Comparativo), sem o botão de tela cheia.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: context.appPanelDecoration(radius: 18),
            child: CategoriasRoscaModerna(
              titulo: titulo,
              fatias: fatias,
              onAbrir: onAbrir,
              mesAMes: mesAMes,
              telaCheia: true,
            ),
          ),
          const SizedBox(height: 16),
          Text('Todas as categorias',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
          const SizedBox(height: 10),
          for (var i = 0; i < fatias.length; i++)
            LinhaBarra3d(
              fatia: fatias[i],
              cor: cores[i],
              fracao: fatias[i].valor / maior,
              pct: _pct(fatias[i].valor, total),
              atraso: math.min(i, 10),
              onTap: onAbrir == null ? null : () => onAbrir!(fatias[i]),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), minimumSize: const Size.fromHeight(50)),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Retornar', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
  }
}
