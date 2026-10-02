import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// Ação do card do «Resumo do dia» (ícone + toque).
class AgendaDiaResumoAcao {
  const AgendaDiaResumoAcao({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;
}

/// Paleta pastel derivada da cor do item (mesma regra do Controle Total:
/// barra forte + fundo pastel; no escuro, a cor misturada ao fundo escuro).
({Color barra, Color fundoInicio, Color fundoFim, Color iconeBg, Color iconeFg})
    agendaPaletaPastel(BuildContext context, Color barra) {
  if (context.isDarkMode) {
    const base = Color(0xFF1A1F2E);
    const baseEnd = Color(0xFF141820);
    return (
      barra: barra,
      fundoInicio: Color.alphaBlend(barra.withValues(alpha: 0.22), base),
      fundoFim: Color.alphaBlend(barra.withValues(alpha: 0.10), baseEnd),
      iconeBg: barra.withValues(alpha: 0.30),
      iconeFg: barra.withValues(alpha: 0.95),
    );
  }
  final hsl = HSLColor.fromColor(barra);
  final escura = hsl
      .withLightness((hsl.lightness * 0.55).clamp(0.12, 0.40))
      .toColor();
  return (
    barra: barra,
    fundoInicio: Color.lerp(Colors.white, barra, 0.14) ?? barra,
    fundoFim: Color.lerp(Colors.white, barra, 0.06) ?? barra,
    iconeBg: barra.withValues(alpha: 0.22),
    iconeFg: escura,
  );
}

/// Card colorido de UM item do dia (compromisso, evento do Google ou conta
/// pendente) — padrão «Card do resumo» do Controle Total: as ações moram no
/// próprio card e chegam por parâmetro (cada tela decide as suas).
class AgendaDiaResumoCard extends StatelessWidget {
  const AgendaDiaResumoCard({
    super.key,
    required this.cor,
    required this.simbolo,
    required this.titulo,
    this.etiqueta,
    this.horario,
    this.valor,
    this.notas,
    this.acoes = const [],
    this.onTap,
  });

  final Color cor;

  /// Emoji/ícone do item (já resolvido pela tela).
  final Widget simbolo;
  final String titulo;

  /// Ex.: «Compromisso», «Google», «Receita pendente».
  final String? etiqueta;
  final String? horario;
  final String? valor;
  final String? notas;
  final List<AgendaDiaResumoAcao> acoes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = agendaPaletaPastel(context, cor);
    final texto =
        context.isDarkMode ? context.appTextPrimary : const Color(0xFF1A237E);
    final textoSec =
        context.isDarkMode ? context.appTextSecondary : const Color(0xFF546E7A);
    final estreito = MediaQuery.sizeOf(context).width < 380;

    Widget pill(IconData icon, String label, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: fg.withValues(alpha: 0.26)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.fundoInicio, p.fundoFim],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cor.withValues(alpha: 0.32)),
              boxShadow: [
                BoxShadow(
                  color: cor.withValues(alpha: context.isDarkMode ? 0.18 : 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 7, color: p.barra),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 4, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: p.iconeBg,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: IconTheme(
                                    data: IconThemeData(
                                        color: p.iconeFg, size: 20),
                                    child: simbolo,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if ((etiqueta ?? '').isNotEmpty)
                                        Text(
                                          etiqueta!.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.6,
                                            color: p.iconeFg,
                                          ),
                                        ),
                                      Text(
                                        titulo,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w900,
                                          color: texto,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if ((horario ?? '').isNotEmpty ||
                                (valor ?? '').isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if ((horario ?? '').isNotEmpty)
                                    pill(Icons.schedule_rounded, horario!,
                                        p.iconeFg),
                                  if ((valor ?? '').isNotEmpty)
                                    pill(Icons.payments_rounded, valor!,
                                        p.iconeFg),
                                ],
                              ),
                            ],
                            if ((notas ?? '').isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                notas!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: textoSec,
                                  height: 1.35,
                                ),
                              ),
                            ],
                            if (acoes.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: estreito ? 0 : 2,
                                  children: [
                                    for (final a in acoes)
                                      IconButton(
                                        tooltip: a.tooltip,
                                        visualDensity: VisualDensity.compact,
                                        onPressed: a.onPressed,
                                        icon: Icon(a.icon,
                                            size: 20, color: a.color),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
