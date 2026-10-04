import 'package:flutter/material.dart';

import '../screens/financial_tips_fullscreen_page.dart';
import '../services/financial_tips_catalog_service.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/home_painel_resumo.dart';
import '../utils/user_display_name.dart';
import '../constants/app_brand.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../widgets/finance_tip_modern_card.dart';
import '../widgets/home_finance_overview_panel.dart';
import '../widgets/home_objective_finance_panel.dart';
import '../widgets/home_pendentes_cards.dart';
import '../features/investimentos/investimentos_atalho_card.dart';

/// Último catálogo de dicas recebido — volta ao Início sem piscar.
HomeTipsCatalogSnapshot? _ultimoCatalogo;

/// Início do WISDOMAPP (índice 0 do shell) — padrão do painel do Controle
/// Total: cabeçalho com saudação e data, dica do dia,
/// financeiro completo (saldo, contas, pendentes, fixas, gráficos) e
/// objetivos. Grade responsiva: 1 coluna no celular, 2 na tela larga.
///
/// Performance: todas as escutas ficam guardadas no estado (nada de
/// `.snapshots()` no build) e a 1ª pintura usa o último valor conhecido.
class WisdomDashboardScreen extends StatefulWidget {
  const WisdomDashboardScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.onNavigateTo,
    this.shellScrollController,
    this.onlyTips = false,
  });

  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;
  final ScrollController? shellScrollController;
  final bool onlyTips;

  @override
  State<WisdomDashboardScreen> createState() => _WisdomDashboardScreenState();
}

class _WisdomDashboardScreenState extends State<WisdomDashboardScreen> {
  // Uma escuta só, criada uma vez (antes era recriada a cada build do shell).
  late final Stream<HomeTipsCatalogSnapshot> _tips =
      FinancialTipsCatalogService.watchHomeTips().map((c) {
    _ultimoCatalogo = c;
    return c;
  });

  void _ir(int i) => widget.onNavigateTo?.call(i);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HomeTipsCatalogSnapshot>(
      stream: _tips,
      initialData: _ultimoCatalogo,
      builder: (context, snap) {
        final catalog = snap.data ??
            HomeTipsCatalogSnapshot(
                tips: FinancialTipsCatalogService.biblicalCatalog());
        final allTips = catalog.tips.isNotEmpty
            ? catalog.tips
            : FinancialTipsCatalogService.biblicalCatalog();

        if (widget.onlyTips) {
          return FinancialTipsFullscreenPage(
            tips: allTips,
            config: catalog.config,
            embeddedInShell: true,
            onReturn: () => _ir(0),
          );
        }

        final preview = FinancialTipsCatalogService.partitionForHome(
          allTips,
          config: catalog.config,
        );
        final syncing = snap.connectionState == ConnectionState.waiting &&
            _ultimoCatalogo == null;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: context.appBodyGradient,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final largo = w >= 1100;
            final lateral =
                w >= 1400 ? (w - 1400) / 2 + 24 : (w >= 700 ? 24.0 : 16.0);

            final dica = _SecaoDica(
              preview: preview,
              syncing: syncing,
              onVerMais: () {
                if (widget.onNavigateTo != null) {
                  _ir(5);
                } else {
                  openFinancialTipsFullscreen(
                    context,
                    tips: allTips,
                    config: catalog.config,
                  );
                }
              },
            );
            final financeiro = HomeFinanceOverviewPanel(
              uid: widget.uid,
              profile: widget.profile,
              onOpenFinanceiro: () => _ir(1),
              pendentesBuilder: (ctx, contas, ocultar) => HomePendentesSecao(
                key: ValueKey('pend_${widget.uid}'),
                uid: firestoreUserDocIdForAppShell(widget.uid),
                profile: widget.profile,
                contas: contas,
                ocultarValores: ocultar,
                onAbrirFinanceiro: () => _ir(1),
              ),
            );
            final objetivos = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SecaoTitulo(
                  titulo: 'Objetivos Financeiros',
                  subtitulo: 'Projeto 52 semanas e suas metas',
                  icone: Icons.flag_rounded,
                  cores: [Color(0xFF4F46E5), Color(0xFFEC4899)],
                ),
                const SizedBox(height: 12),
                HomeObjectiveFinancePanel(
                  uid: widget.uid,
                  profile: widget.profile,
                  onOpenObjetivoModule: () => _ir(2),
                ),
              ],
            );
            final investimentos = InvestimentosAtalhoCard(
              uid: widget.uid,
              profile: widget.profile,
            );

            return ListView(
              controller: widget.shellScrollController,
              padding: EdgeInsets.fromLTRB(lateral, 12, lateral, 28),
              children: [
                _Cabecalho(profile: widget.profile),
                const SizedBox(height: 20),
                if (largo)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: financeiro),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            dica,
                            const SizedBox(height: 24),
                            objetivos,
                            const SizedBox(height: 24),
                            investimentos,
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  dica,
                  const SizedBox(height: 24),
                  financeiro,
                  const SizedBox(height: 24),
                  objetivos,
                  const SizedBox(height: 24),
                  investimentos,
                ],
              ],
            );
          }),
        );
      },
    );
  }
}

/// Título de seção: ícone em degradê + título + subtítulo.
class _SecaoTitulo extends StatelessWidget {
  const _SecaoTitulo({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.cores,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final List<Color> cores;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: cores),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: cores.first.withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icone, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: context.appDeepTitle,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitulo,
                style: TextStyle(
                  color: context.appTextSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dica financeira do dia (mantida do Início anterior).
class _SecaoDica extends StatelessWidget {
  const _SecaoDica({
    required this.preview,
    required this.syncing,
    required this.onVerMais,
  });

  final HomeTipsPreview preview;
  final bool syncing;
  final VoidCallback onVerMais;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SecaoTitulo(
          titulo: 'Dica financeira do dia',
          subtitulo: syncing
              ? 'A sincronizar com a nuvem…'
              : 'Sabedoria bíblica para suas finanças · ${preview.dayLabel}',
          icone: Icons.menu_book_rounded,
          cores: [AppColors.primary, AppColors.accent.withValues(alpha: 0.85)],
        ),
        const SizedBox(height: 12),
        FinanceTipModernCard(
          tip: preview.tipOfDay,
          index: 0,
          isTipOfDay: true,
          showFullText: true,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onVerMais,
          icon: const Icon(Icons.auto_stories_rounded),
          label: const Text('Veja mais'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0B1B4B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'No módulo Dicas você vê só os últimos '
            '${FinancialTipsCatalogService.kModuleHistoryDays} dias.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appTextMuted,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Cabeçalho: marca, saudação pela hora, data por extenso.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final name = resolveUserDisplayName(profile);
    final agora = DateTime.now();
    final data = dataPorExtenso(agora);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1B4B), Color(0xFF134074), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B4B).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Brilho decorativo no canto (sem imagem — leve).
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFF0D878),
                                Color(0xFFD4AF37),
                                Color(0xFFB8941F)
                              ],
                            ).createShader(bounds),
                            child: Text(
                              AppBrand.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                                fontSize: 20,
                                height: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppBrand.idealizerName.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.today_rounded,
                              size: 14, color: Color(0xFF5EEAD4)),
                          const SizedBox(width: 5),
                          Text(
                            '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${saudacaoPorHora(agora)}, $name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 21,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data[0].toUpperCase() + data.substring(1),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sabedoria financeira com base na Bíblia',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
