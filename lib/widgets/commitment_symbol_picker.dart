import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/commitment_symbols.dart';
import '../theme/theme_context.dart';

/// Resultado do seletor: [symbol] nulo = voltar ao automático (pelo título).
class CommitmentSymbolPick {
  const CommitmentSymbolPick(this.symbol);
  final CommitmentSymbol? symbol;
}

const String _kRecentesKey = 'commitment_symbol_recentes_v1';
const int _kMaxRecentes = 18;

Future<List<CommitmentSymbol>> _lerRecentes() async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kRecentesKey) ?? const <String>[];
    return raw
        .map(CommitmentSymbol.parse)
        .whereType<CommitmentSymbol>()
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Future<void> _gravarRecente(CommitmentSymbol s) async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kRecentesKey) ?? <String>[];
    final nova = [s.raw, ...raw.where((e) => e != s.raw)];
    await p.setStringList(
        _kRecentesKey, nova.take(_kMaxRecentes).toList(growable: false));
  } catch (_) {}
}

/// Seletor de emoji ou ícone moderno do compromisso. Devolve `null` quando o
/// usuário volta sem escolher. Em tela larga abre como diálogo centralizado.
Future<CommitmentSymbolPick?> showCommitmentSymbolPicker(
  BuildContext context, {
  CommitmentSymbol? atual,
  String? title,
  Color? cor,
}) async {
  final recentes = await _lerRecentes();
  if (!context.mounted) return null;
  final largo = MediaQuery.sizeOf(context).width >= 720;
  final sheet = _CommitmentSymbolSheet(
    atual: atual,
    title: title,
    cor: cor,
    recentes: recentes,
    emDialogo: largo,
  );
  final CommitmentSymbolPick? pick;
  if (largo) {
    pick = await showDialog<CommitmentSymbolPick>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: sheet,
        ),
      ),
    );
  } else {
    pick = await showModalBottomSheet<CommitmentSymbolPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }
  final s = pick?.symbol;
  if (s != null) await _gravarRecente(s);
  return pick;
}

class _CommitmentSymbolSheet extends StatefulWidget {
  const _CommitmentSymbolSheet({
    this.atual,
    this.title,
    this.cor,
    required this.recentes,
    required this.emDialogo,
  });

  final CommitmentSymbol? atual;
  final String? title;
  final Color? cor;
  final List<CommitmentSymbol> recentes;
  final bool emDialogo;

  @override
  State<_CommitmentSymbolSheet> createState() => _CommitmentSymbolSheetState();
}

class _CommitmentSymbolSheetState extends State<_CommitmentSymbolSheet> {
  final TextEditingController _busca = TextEditingController();
  String _termo = '';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Color get _accent => widget.cor ?? const Color(0xFF0D9488);

  void _escolher(CommitmentSymbol s) =>
      Navigator.pop(context, CommitmentSymbolPick(s));

  bool _casa(String palavras, String extra) {
    if (_termo.isEmpty) return true;
    final alvo = commitmentSearchNormalize('$palavras $extra');
    return _termo
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(alvo.contains);
  }

  Widget _celula({
    required Widget child,
    required bool marcado,
    required VoidCallback onTap,
  }) {
    final dark = context.isDarkMode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: marcado
                ? _accent.withValues(alpha: dark ? 0.28 : 0.16)
                : (dark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF3F5F9)),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: marcado ? _accent : context.appBorderSubtle,
              width: marcado ? 2.4 : 1,
            ),
            boxShadow: marcado
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              child,
              if (marcado)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration:
                        BoxDecoration(color: _accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const _grade = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 68,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
  );

  Widget _tituloSecao(String t, {IconData? icone}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Row(
        children: [
          if (icone != null) ...[
            Icon(icone, size: 18, color: _accent),
            const SizedBox(width: 6),
          ],
          Text(
            t,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: context.appTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeEmojis(List<String> emojis) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: _grade,
      itemCount: emojis.length,
      itemBuilder: (_, i) {
        final e = emojis[i];
        return _celula(
          marcado: widget.atual?.emoji == e,
          onTap: () => _escolher(CommitmentSymbol.emoji(e)),
          child: Text(e, style: const TextStyle(fontSize: 36, height: 1)),
        );
      },
    );
  }

  Widget _gradeIcones(List<String> keys) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: _grade,
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final k = keys[i];
        return _celula(
          marcado: widget.atual?.iconKey == k,
          onTap: () => _escolher(CommitmentSymbol.icon(k)),
          child: Icon(kCommitmentIcons[k], color: _accent, size: 34),
        );
      },
    );
  }

  Widget _vazio() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded,
                size: 40, color: context.appTextMuted),
            const SizedBox(height: 8),
            Text(
              'Nada encontrado para «${_busca.text.trim()}».',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: context.appTextMuted),
            ),
          ],
        ),
      );

  Widget _abaEmojis() {
    final filhos = <Widget>[];
    final recentesEmoji = widget.recentes
        .where((s) => s.emoji != null)
        .map((s) => s.emoji!)
        .toList();
    if (_termo.isEmpty && recentesEmoji.isNotEmpty) {
      filhos
        ..add(_tituloSecao('Recentes', icone: Icons.history_rounded))
        ..add(_gradeEmojis(recentesEmoji));
    }
    final vistos = <String>{};
    for (final g in kCommitmentEmojiGroups) {
      final itens = g.itens
          .where((e) => _casa(e.palavras, g.titulo))
          .map((e) => e.emoji)
          .where((e) => _termo.isEmpty || vistos.add(e))
          .toList();
      if (itens.isEmpty) continue;
      filhos
        ..add(_tituloSecao(g.titulo, icone: g.icone))
        ..add(_gradeEmojis(itens));
    }
    if (filhos.isEmpty) filhos.add(_vazio());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: filhos,
    );
  }

  Widget _abaIcones() {
    final filhos = <Widget>[];
    final recentesIcone = widget.recentes
        .where((s) => s.iconKey != null)
        .map((s) => s.iconKey!)
        .toList();
    if (_termo.isEmpty && recentesIcone.isNotEmpty) {
      filhos
        ..add(_tituloSecao('Recentes', icone: Icons.history_rounded))
        ..add(_gradeIcones(recentesIcone));
    }
    final vistos = <String>{};
    for (final g in kCommitmentIconGroups) {
      final keys = g.itens
          .where((e) => kCommitmentIcons.containsKey(e.key))
          .where((e) => _casa(e.palavras, '${g.titulo} ${e.key}'))
          .map((e) => e.key)
          .where((k) => _termo.isEmpty || vistos.add(k))
          .toList();
      if (keys.isEmpty) continue;
      filhos
        ..add(_tituloSecao(g.titulo))
        ..add(_gradeIcones(keys));
    }
    if (filhos.isEmpty) filhos.add(_vazio());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: filhos,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final dark = context.isDarkMode;

    final corpo = DefaultTabController(
      length: 2,
      child: Column(
        children: [
          if (!widget.emDialogo) ...[
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: context.appBorderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 10, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Voltar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: context.appTextPrimary,
                ),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.emoji_emotions_rounded,
                      color: _accent, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Emoji ou ícone',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      Navigator.pop(context, const CommitmentSymbolPick(null)),
                  icon: Icon(
                      widget.atual == null
                          ? Icons.auto_awesome_rounded
                          : Icons.backspace_outlined,
                      size: 18),
                  label: Text(widget.atual == null ? 'Automático' : 'Remover'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              controller: _busca,
              onChanged: (v) =>
                  setState(() => _termo = commitmentSearchNormalize(v)),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar: aniversário, médico, igreja, viagem…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _termo.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _busca.clear();
                          setState(() => _termo = '');
                        },
                      ),
                filled: true,
                fillColor: dark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF3F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          TabBar(
            labelColor: _accent,
            indicatorColor: _accent,
            indicatorWeight: 3,
            unselectedLabelColor: context.appTextSecondary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            tabs: const [
              Tab(icon: Icon(Icons.emoji_emotions_outlined), text: 'Emojis'),
              Tab(
                  icon: Icon(Icons.auto_awesome_mosaic_rounded),
                  text: 'Ícones modernos'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_abaEmojis(), _abaIcones()],
            ),
          ),
        ],
      ),
    );

    return Container(
      height: widget.emDialogo ? mq.height * 0.82 : mq.height * 0.86,
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: widget.emDialogo
            ? null
            : const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: corpo,
    );
  }
}
