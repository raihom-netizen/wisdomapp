import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';

/// Peças visuais comuns do Painel Admin (padrão Controle Total): cabeçalho com
/// gradiente, KPIs coloridos, seção, busca, estados de carregando / erro /
/// vazio. Toda aba nova do admin usa estas peças — nada de spinner sem prazo.
class AdminUi {
  AdminUi._();

  static const Color azul = Color(0xFF2563EB);
  static const Color verde = Color(0xFF16A34A);
  static const Color teal = Color(0xFF0D9488);
  static const Color ambar = Color(0xFFD97706);
  static const Color vermelho = Color(0xFFDC2626);
  static const Color roxo = Color(0xFF7C3AED);
  static const Color rosa = Color(0xFFDB2777);
  static const Color cinza = Color(0xFF64748B);
  static const Color tinta = Color(0xFF0F172A);

  /// Tinta de título/valor que segue o tema (claro = [tinta]).
  static Color tintaOf(BuildContext context) =>
      context.isDarkMode ? context.appTextPrimary : tinta;

  /// Fundo de card/campo do admin (claro = branco).
  static Color cardOf(BuildContext context) =>
      context.isDarkMode ? context.appSurface : Colors.white;

  /// Borda fina (claro = grey.shade200).
  static Color bordaOf(BuildContext context) =>
      context.isDarkMode ? context.appChipIdleBorder : Colors.grey.shade200;

  /// Texto de apoio (claro = grey.shade600).
  static Color apoioOf(BuildContext context) =>
      context.isDarkMode ? context.appTextSecondary : Colors.grey.shade600;

  /// Colunas da grade de KPIs pela largura disponível.
  static int colunas(double largura, {int max = 4}) {
    final c = largura >= 1200
        ? 4
        : largura >= 860
            ? 3
            : largura >= 420
                ? 2
                : 1;
    return c > max ? max : c;
  }
}

/// Cabeçalho do módulo: gradiente, ícone, título, subtítulo e ações.
class AdminHero extends StatelessWidget {
  const AdminHero({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    this.cores = const [Color(0xFF0D1B2A), Color(0xFF1D4ED8), Color(0xFF12B5A5)],
    this.carregando = false,
    this.onAtualizar,
    this.acoes = const [],
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final List<Color> cores;
  final bool carregando;
  final VoidCallback? onAtualizar;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: cores,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: cores.last.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icone, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitulo,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          ...acoes,
          if (onAtualizar != null)
            IconButton(
              tooltip: 'Atualizar',
              onPressed: carregando ? null : onAtualizar,
              icon: carregando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

/// KPI compacto com leve gradiente da cor; tocável (filtro / atalho).
class AdminKpi extends StatelessWidget {
  const AdminKpi({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.icone,
    required this.cor,
    this.sub,
    this.onTap,
    this.selecionado = false,
  });

  final String rotulo;
  final String valor;
  final String? sub;
  final IconData icone;
  final Color cor;
  final VoidCallback? onTap;
  final bool selecionado;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.cardOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: selecionado
                  ? [cor.withValues(alpha: 0.95), cor.withValues(alpha: 0.75)]
                  : [cor.withValues(alpha: 0.12), cor.withValues(alpha: 0.02)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: cor.withValues(alpha: selecionado ? 0.9 : 0.28),
              width: selecionado ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: selecionado
                    ? Colors.white.withValues(alpha: 0.22)
                    : cor.withValues(alpha: 0.15),
                child: Icon(icone,
                    color: selecionado ? Colors.white : cor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rotulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: selecionado
                            ? Colors.white.withValues(alpha: 0.9)
                            : (context.isDarkMode
                                ? context.appTextSecondary
                                : Colors.grey.shade700),
                      ),
                    ),
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: selecionado
                            ? Colors.white
                            : AdminUi.tintaOf(context),
                      ),
                    ),
                    if (sub != null && sub!.isNotEmpty)
                      Text(
                        sub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: selecionado
                              ? Colors.white.withValues(alpha: 0.85)
                              : AdminUi.apoioOf(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grade responsiva de KPIs (1 a 4 colunas).
class AdminKpiGrid extends StatelessWidget {
  const AdminKpiGrid({super.key, required this.children, this.maxColunas = 4});

  final List<Widget> children;
  final int maxColunas;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final col = AdminUi.colunas(c.maxWidth, max: maxColunas);
      final w = (c.maxWidth - (col - 1) * 10) / col;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final x in children) SizedBox(width: w, child: x)],
      );
    });
  }
}

/// Título de seção com ícone em gradiente e linha da cor.
class AdminSecao extends StatelessWidget {
  const AdminSecao({
    super.key,
    required this.titulo,
    required this.cor,
    required this.icone,
    this.trailing,
  });

  final String titulo;
  final Color cor;
  final IconData icone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cor.withValues(alpha: 0.9), cor.withValues(alpha: 0.6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              titulo,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AdminUi.tintaOf(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: cor.withValues(alpha: 0.2))),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Campo de busca branco e arredondado.
class AdminBusca extends StatelessWidget {
  const AdminBusca({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Buscar…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: AdminUi.cardOf(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AdminUi.bordaOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AdminUi.bordaOf(context)),
        ),
      ),
    );
  }
}

/// Carregando com texto (sempre acompanhado de prazo no código que o usa).
class AdminCarregando extends StatelessWidget {
  const AdminCarregando({super.key, this.texto = 'Carregando…'});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 12),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: AdminUi.apoioOf(context), fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Erro visível com mensagem amigável e «Tentar de novo».
class AdminErroCard extends StatelessWidget {
  const AdminErroCard({
    super.key,
    required this.erro,
    required this.onTentar,
    this.titulo = 'Não foi possível carregar',
  });

  final Object? erro;
  final VoidCallback onTentar;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 38, color: Colors.red.shade400),
          const SizedBox(height: 8),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          SelectableText(
            AdminLoadGuard.mensagem(erro),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                color: context.isDarkMode
                    ? context.appTextSecondary
                    : Colors.grey.shade800,
                height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onTentar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}

/// Lista vazia.
class AdminVazio extends StatelessWidget {
  const AdminVazio({
    super.key,
    required this.texto,
    this.icone = Icons.inbox_rounded,
    this.acao,
  });

  final String texto;
  final IconData icone;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: AdminUi.apoioOf(context), fontSize: 13),
          ),
          if (acao != null) ...[const SizedBox(height: 12), acao!],
        ],
      ),
    );
  }
}

/// Selo colorido (papel, status, plano).
class AdminSelo extends StatelessWidget {
  const AdminSelo(this.texto, {super.key, required this.cor, this.icone});

  final String texto;
  final Color cor;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 12, color: cor),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: cor),
          ),
        ],
      ),
    );
  }
}
