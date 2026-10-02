import 'package:flutter/material.dart';

import '../constants/commitment_symbols.dart';
import '../theme/theme_context.dart';

/// Resultado do seletor: [symbol] nulo = voltar ao automático (pelo título).
class CommitmentSymbolPick {
  const CommitmentSymbolPick(this.symbol);
  final CommitmentSymbol? symbol;
}

/// Seletor de emoji ou ícone moderno do compromisso. Devolve `null` quando o
/// usuário fecha sem escolher.
Future<CommitmentSymbolPick?> showCommitmentSymbolPicker(
  BuildContext context, {
  CommitmentSymbol? atual,
  String? title,
  Color? cor,
}) {
  return showModalBottomSheet<CommitmentSymbolPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommitmentSymbolSheet(atual: atual, title: title, cor: cor),
  );
}

class _CommitmentSymbolSheet extends StatelessWidget {
  const _CommitmentSymbolSheet({this.atual, this.title, this.cor});

  final CommitmentSymbol? atual;
  final String? title;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final accent = cor ?? const Color(0xFF0D9488);
    final altura = MediaQuery.sizeOf(context).height * 0.72;

    Widget celula({required Widget child, required bool marcado, required VoidCallback onTap}) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: marcado
                ? accent.withValues(alpha: 0.18)
                : context.appTextPrimary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: marcado ? accent : context.appBorderSubtle,
              width: marcado ? 2 : 1,
            ),
          ),
          child: child,
        ),
      );
    }

    const grade = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 56,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    );

    return Container(
      height: altura,
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: context.appBorderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 4),
              child: Row(
                children: [
                  Icon(Icons.emoji_emotions_rounded, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Emoji ou ícone',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: context.appTextPrimary)),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(
                        context, const CommitmentSymbolPick(null)),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Automático'),
                  ),
                ],
              ),
            ),
            TabBar(
              labelColor: accent,
              indicatorColor: accent,
              unselectedLabelColor: context.appTextSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800),
              tabs: const [Tab(text: 'Emojis'), Tab(text: 'Ícones modernos')],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final g in kCommitmentEmojiGroups) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                          child: Text(g.titulo,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: context.appTextSecondary)),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: grade,
                          itemCount: g.emojis.length,
                          itemBuilder: (_, i) {
                            final e = g.emojis[i];
                            return celula(
                              marcado: atual?.emoji == e,
                              onTap: () => Navigator.pop(context,
                                  CommitmentSymbolPick(CommitmentSymbol.emoji(e))),
                              child: Text(e,
                                  style: const TextStyle(fontSize: 26, height: 1)),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                  GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    gridDelegate: grade,
                    itemCount: kCommitmentIcons.length,
                    itemBuilder: (_, i) {
                      final k = kCommitmentIcons.keys.elementAt(i);
                      return celula(
                        marcado: atual?.iconKey == k,
                        onTap: () => Navigator.pop(context,
                            CommitmentSymbolPick(CommitmentSymbol.icon(k))),
                        child: Icon(kCommitmentIcons[k], color: accent, size: 26),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
