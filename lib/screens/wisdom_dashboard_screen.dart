import 'package:flutter/material.dart';

import '../screens/financial_tips_fullscreen_page.dart';
import '../services/financial_tips_catalog_service.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/home_painel_resumo.dart';
import '../utils/user_display_name.dart';
import '../constants/agenda_module_icons.dart';
import '../constants/anotacoes_module_icons.dart';
import '../constants/app_brand.dart';
import '../constants/calculator_module_icons.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../widgets/finance_tip_modern_card.dart';
import '../widgets/home_finance_overview_panel.dart';
import '../widgets/home_objective_finance_panel.dart';
import '../widgets/home_pendentes_cards.dart';

/// Último catálogo de dicas recebido — volta ao Início sem piscar.
HomeTipsCatalogSnapshot? _ultimoCatalogo;

/// Início do WISDOMAPP (índice 0 do shell) — padrão do painel do Controle
/// Total: cabeçalho com saudação e data, atalhos dos módulos, dica do dia,
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

            return ListView(
              controller: widget.shellScrollController,
              padding: EdgeInsets.fromLTRB(lateral, 12, lateral, 28),
              children: [
                _Cabecalho(profile: widget.profile),
                const SizedBox(height: 16),
                _AtalhosModulos(onTap: _ir),
                const SizedBox(height: 22),
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

/// Atalhos de TODOS os módulos que o WISDOMAPP tem (mesmos índices do shell
/// e do menu lateral). Grade responsiva: 4 por linha no celular, até 9 na
/// tela larga.
class _AtalhosModulos extends StatelessWidget {
  const _AtalhosModulos({required this.onTap});

  final void Function(int index) onTap;

  static final _modulos =
      <({int idx, String rotulo, IconData icone, List<Color> cores})>[
    (
      idx: 1,
      rotulo: 'Financeiro',
      icone: Icons.account_balance_wallet_rounded,
      cores: const [Color(0xFF0F766E), Color(0xFF14B8A6)]
    ),
    (
      idx: 2,
      rotulo: 'Objetivos',
      icone: Icons.flag_rounded,
      cores: const [Color(0xFFBE185D), Color(0xFFEC4899)]
    ),
    (
      idx: 3,
      rotulo: 'Agenda',
      icone: AgendaModuleIcons.nav,
      cores: const [Color(0xFF0E7490), Color(0xFF22D3EE)]
    ),
    (
      idx: 7,
      rotulo: 'Cursos',
      icone: Icons.ondemand_video_rounded,
      cores: const [Color(0xFF1D4ED8), Color(0xFF38BDF8)]
    ),
    (
      idx: 5,
      rotulo: 'Dicas',
      icone: Icons.menu_book_rounded,
      cores: const [Color(0xFF6D28D9), Color(0xFFA78BFA)]
    ),
    (
      idx: 6,
      rotulo: 'Relatórios',
      icone: Icons.assessment_rounded,
      cores: const [Color(0xFF15803D), Color(0xFF4ADE80)]
    ),
    (
      idx: 4,
      rotulo: 'Calculadora',
      icone: CalculatorModuleIcons.nav,
      cores: const [Color(0xFFC2410C), Color(0xFFFB923C)]
    ),
    (
      idx: 8,
      rotulo: 'Anotações',
      icone: AnotacoesModuleIcons.nav,
      cores: const [Color(0xFF0369A1), Color(0xFF7DD3FC)]
    ),
    (
      idx: 9,
      rotulo: 'Ajustes',
      icone: Icons.settings_rounded,
      cores: const [Color(0xFF334155), Color(0xFF94A3B8)]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const espaco = 10.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: context.appPanelDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Row(
              children: [
                Icon(Icons.apps_rounded,
                    size: 18, color: context.appTextSecondary),
                const SizedBox(width: 6),
                Text(
                  'Acesso rápido',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: context.appTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(builder: (context, c) {
            final largura = c.maxWidth;
            final porLinha = largura >= 940
                ? 9
                : largura >= 600
                    ? 5
                    : 4;
            // floor: sem isso a soma passa da largura por fração de pixel e o
            // último atalho da linha desce sozinho.
            final t = ((largura - espaco * (porLinha - 1)) / porLinha)
                .floorToDouble()
                .clamp(56.0, 400.0);
            return Wrap(
              spacing: espaco,
              runSpacing: 12,
              children: [
                for (final m in _modulos)
                  SizedBox(
                    width: t,
                    child: _AtalhoTile(
                      rotulo: m.rotulo,
                      icone: m.icone,
                      cores: m.cores,
                      onTap: () => onTap(m.idx),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _AtalhoTile extends StatelessWidget {
  const _AtalhoTile({
    required this.rotulo,
    required this.icone,
    required this.cores,
    required this.onTap,
  });

  final String rotulo;
  final IconData icone;
  final List<Color> cores;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: rotulo,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: cores,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: cores.first.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icone, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 6),
              // Reduz a fonte em vez de cortar («Calculadora» no celular).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  rotulo,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
