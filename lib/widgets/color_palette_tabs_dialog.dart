import 'package:flutter/material.dart';

import '../constants/color_palette.dart';
import '../theme/theme_context.dart';

/// Seletor de cor padrão do app — paleta completa dividida em Paleta 01/02/03.
///
/// Usado por todos os módulos que escolhem cor de calendário (escala, plantão,
/// compromisso, audiência, produtividade, financeiro, lançamento expresso), para
/// que a experiência seja a mesma em qualquer tela.
///
/// Uso:
/// ```dart
/// final hex = await mostrarSeletorDeCores(context, selecionadaHex: _corHex);
/// if (hex != null) setState(() => _corHex = hex);
/// ```
class ColorPaletteTabsDialog extends StatefulWidget {
  const ColorPaletteTabsDialog({
    super.key,
    this.titulo = 'Escolha a cor',
    this.selecionadaHex,
    this.cores,
  });

  final String titulo;
  final String? selecionadaHex;

  /// Paleta alternativa (padrão: a paleta completa do app).
  final List<String>? cores;

  /// Cor usada quando o dado salvo não dá para interpretar.
  static const Color _corPadrao = Color(0xFF2D5BFF);

  /// Converte o hex guardado no banco em cor, aceitando tudo que já existe
  /// lançado: `#2E7D32`, `2E7D32`, `0xFF2E7D32`, `FF2E7D32`.
  ///
  /// Duas armadilhas dos dados antigos são tratadas aqui:
  ///
  ///  • Valor com alfa (8 dígitos) — precisa dos ÚLTIMOS seis. Pegar os
  ///    primeiros transformava `FF2E7D32` em `FF2E7D`, uma cor diferente da
  ///    que o usuário escolheu.
  ///  • Valor vazio, nulo ou com lixo — `int.parse` lançaria e derrubaria a
  ///    tela inteira. Nenhuma cor salva errada pode impedir alguém de abrir
  ///    seu compromisso.
  static Color corDeHex(String? hex) {
    final limpo = (hex ?? '')
        .trim()
        .replaceAll('#', '')
        .replaceAll(RegExp('^0x', caseSensitive: false), '');
    if (limpo.isEmpty) return _corPadrao;
    final base = limpo.length > 6 ? limpo.substring(limpo.length - 6) : limpo;
    if (base.length != 6 || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(base)) {
      return _corPadrao;
    }
    return Color(0xFF000000 + int.parse(base, radix: 16));
  }

  /// Compara duas cores pelos seis dígitos finais, ignorando `#`, `0x` e alfa.
  static bool mesmaCor(String? a, String? b) {
    String seis(String? v) {
      final s = (v ?? '')
          .trim()
          .replaceAll('#', '')
          .replaceAll(RegExp('^0x', caseSensitive: false), '')
          .toUpperCase();
      return s.length > 6 ? s.substring(s.length - 6) : s;
    }

    final x = seis(a);
    return x.isNotEmpty && x == seis(b);
  }

  @override
  State<ColorPaletteTabsDialog> createState() => _ColorPaletteTabsDialogState();
}

class _ColorPaletteTabsDialogState extends State<ColorPaletteTabsDialog> {
  /// Cores por página. Seis colunas × seis linhas cabem sem rolagem apertada.
  static const int _porPagina = 36;

  late final List<List<String>> _paginas;
  late final PageController _pageCtrl;
  int _pagina = 0;

  @override
  void initState() {
    super.initState();
    final paleta = widget.cores ?? kColorPaletteHex;
    _paginas = [
      for (var i = 0; i < paleta.length; i += _porPagina)
        paleta.sublist(
            i, i + _porPagina > paleta.length ? paleta.length : i + _porPagina),
    ];
    if (_paginas.isEmpty) _paginas.add(const <String>[]);

    // Abre na página que contém a cor atual — reabrir o seletor e cair numa
    // página onde a cor escolhida não está deixa o usuário sem referência.
    final atual = widget.selecionadaHex;
    if (atual != null && atual.isNotEmpty) {
      for (var p = 0; p < _paginas.length; p++) {
        if (_paginas[p].any((h) => ColorPaletteTabsDialog.mesmaCor(h, atual))) {
          _pagina = p;
          break;
        }
      }
    }
    _pageCtrl = PageController(initialPage: _pagina);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _irPara(int i) {
    setState(() => _pagina = i);
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final escuro = context.isDarkMode;
    final fundo = escuro ? const Color(0xFF161C2A) : Colors.white;
    final largura = MediaQuery.of(context).size.width;
    final larguraDialogo = largura < 420 ? largura - 32 : 388.0;

    return Dialog(
      backgroundColor: fundo,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: larguraDialogo,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cabecalho(escuro),
            if (_paginas.length > 1) _seletorDePagina(escuro),
            const SizedBox(height: 4),
            SizedBox(
              height: 340,
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _pagina = i),
                itemCount: _paginas.length,
                itemBuilder: (_, i) => _grade(_paginas[i], escuro),
              ),
            ),
            _rodape(escuro),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho(bool escuro) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.palette_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              widget.titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16.5,
                letterSpacing: -0.2,
                color: escuro ? const Color(0xFFE8ECF5) : const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Controle segmentado: três botões de largura igual, com o ativo em
  /// degradê. Feito com Row + Expanded em vez de TabBar porque o TabBar
  /// dimensiona a aba pelo texto e, em telas estreitas, "Paleta 02" saía
  /// para fora da pílula.
  Widget _seletorDePagina(bool escuro) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: escuro ? const Color(0xFF0F1420) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _paginas.length; i++)
              Expanded(child: _botaoPagina(i, escuro)),
          ],
        ),
      ),
    );
  }

  Widget _botaoPagina(int i, bool escuro) {
    final ativo = i == _pagina;
    final rotulo = 'Paleta ${(i + 1).toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => _irPara(i),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: ativo
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          boxShadow: ativo
              ? [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        // FittedBox garante que o rótulo caiba inteiro em telas estreitas em
        // vez de vazar para fora do botão.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              rotulo,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: -0.1,
                color: ativo
                    ? Colors.white
                    : (escuro
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grade(List<String> grupo, bool escuro) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      itemCount: grupo.length,
      itemBuilder: (_, i) {
        final hex = grupo[i];
        final cor = ColorPaletteTabsDialog.corDeHex(hex);
        final escolhida =
            ColorPaletteTabsDialog.mesmaCor(hex, widget.selecionadaHex);
        return _Bolinha(cor: cor, escolhida: escolhida, escuro: escuro,
            aoTocar: () => Navigator.pop(context, hex));
      },
    );
  }

  Widget _rodape(bool escuro) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: escuro ? const Color(0xFF243044) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 19),
          label: const Text('Retornar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6366F1),
            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.09),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ),
    );
  }
}

/// Amostra de cor da grade.
///
/// Sem halo colorido: a versão anterior punha uma sombra na própria cor da
/// bolinha, e esse borrão em volta de cada círculo é o que dava a impressão de
/// imagem de baixa resolução. Aqui a borda é nítida e a sombra é neutra e
/// discreta, só para dar relevo.
class _Bolinha extends StatelessWidget {
  const _Bolinha({
    required this.cor,
    required this.escolhida,
    required this.escuro,
    required this.aoTocar,
  });

  final Color cor;
  final bool escolhida;
  final bool escuro;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    // Marca de seleção precisa contrastar com a própria cor: check branco some
    // em amarelo claro, check escuro some em azul-marinho.
    final claro = cor.computeLuminance() > 0.6;
    final corDoCheck = claro ? const Color(0xFF0F172A) : Colors.white;

    return GestureDetector(
      onTap: aoTocar,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.all(escolhida ? 3 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Anel externo marca a escolhida sem borrar a cor.
          border: escolhida
              ? Border.all(color: const Color(0xFF6366F1), width: 2.5)
              : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: cor,
            shape: BoxShape.circle,
            border: Border.all(
              color: escuro
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.10),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: escuro ? 0.34 : 0.12),
                blurRadius: 3,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: escolhida
              ? Icon(Icons.check_rounded, color: corDoCheck, size: 19)
              : null,
        ),
      ),
    );
  }
}

/// Abre o seletor e devolve o hex escolhido (ou null se o usuário fechar).
Future<String?> mostrarSeletorDeCores(
  BuildContext context, {
  String titulo = 'Escolha a cor',
  String? selecionadaHex,
  List<String>? cores,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => ColorPaletteTabsDialog(
      titulo: titulo,
      selecionadaHex: selecionadaHex,
      cores: cores,
    ),
  );
}
