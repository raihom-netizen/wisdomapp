import 'package:flutter/material.dart';

import '../screens/financial_tips_fullscreen_page.dart';
import '../services/financial_tips_catalog_service.dart';
import '../utils/user_display_name.dart';
import '../constants/app_brand.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/finance_tip_modern_card.dart';
import '../widgets/home_finance_overview_panel.dart';
import '../widgets/home_objective_finance_panel.dart';

class WisdomDashboardScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (onlyTips) {
      return StreamBuilder<HomeTipsCatalogSnapshot>(
        stream: FinancialTipsCatalogService.watchHomeTips(),
        builder: (context, snap) {
          final catalog = snap.data ??
              HomeTipsCatalogSnapshot(tips: FinancialTipsCatalogService.biblicalCatalog());
          final tips = catalog.tips.isNotEmpty
              ? catalog.tips
              : FinancialTipsCatalogService.biblicalCatalog();
          return FinancialTipsFullscreenPage(
            tips: tips,
            config: catalog.config,
            embeddedInShell: true,
            onReturn: () => onNavigateTo?.call(0),
          );
        },
      );
    }

    return StreamBuilder<HomeTipsCatalogSnapshot>(
      stream: FinancialTipsCatalogService.watchHomeTips(),
      builder: (context, snap) {
        final catalog = snap.data ??
            HomeTipsCatalogSnapshot(tips: FinancialTipsCatalogService.biblicalCatalog());
        final allTips = catalog.tips.isNotEmpty
            ? catalog.tips
            : FinancialTipsCatalogService.biblicalCatalog();
        final preview = FinancialTipsCatalogService.partitionForHome(
          allTips,
          config: catalog.config,
        );
        final syncing = snap.connectionState == ConnectionState.waiting &&
            snap.data == null;

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF0F4FF), Color(0xFFF8FAFC), Color(0xFFEFFDF9)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: ListView(
            controller: shellScrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _HeroCard(
                profile: profile,
                onOpenFinanceiro: () => onNavigateTo?.call(1),
                onOpenObjetivo: () => onNavigateTo?.call(2),
                onOpenAgenda: () => onNavigateTo?.call(3),
                onOpenCursos: () => onNavigateTo?.call(7),
              ),
              const SizedBox(height: 18),
              _TipsSectionHeader(
                syncing: syncing,
                dayLabel: preview.dayLabel,
              ),
              const SizedBox(height: 12),
              FinanceTipModernCard(
                tip: preview.tipOfDay,
                index: 0,
                isTipOfDay: true,
                showFullText: true,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    if (onNavigateTo != null) {
                      onNavigateTo!.call(5);
                    } else {
                      openFinancialTipsFullscreen(
                        context,
                        tips: allTips,
                        config: catalog.config,
                      );
                    }
                  },
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
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              HomeFinanceOverviewPanel(
                uid: uid,
                profile: profile,
                onOpenFinanceiro: () => onNavigateTo?.call(1),
              ),
              const SizedBox(height: 22),
              HomeObjectiveFinancePanel(
                uid: uid,
                profile: profile,
                onOpenObjetivoModule: () => onNavigateTo?.call(2),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TipsSectionHeader extends StatelessWidget {
  const _TipsSectionHeader({required this.syncing, required this.dayLabel});

  final bool syncing;
  final String dayLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.accent.withValues(alpha: 0.85)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dica financeira do dia',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0B1B4B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                syncing
                    ? 'A sincronizar com a nuvem…'
                    : 'Sabedoria bíblica para suas finanças · $dayLabel',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
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

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.profile,
    required this.onOpenFinanceiro,
    required this.onOpenObjetivo,
    required this.onOpenAgenda,
    required this.onOpenCursos,
  });

  final UserProfile profile;
  final VoidCallback onOpenFinanceiro;
  final VoidCallback onOpenObjetivo;
  final VoidCallback onOpenAgenda;
  final VoidCallback onOpenCursos;

  @override
  Widget build(BuildContext context) {
    final name = resolveUserDisplayName(profile);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF0D878), Color(0xFFD4AF37), Color(0xFFB8941F)],
            ).createShader(bounds),
            child: Text(
              AppBrand.displayName,
              style: TextStyle(
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
          const SizedBox(height: 14),
          Text(
            'Olá, $name',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sabedoria financeira com base na Bíblia',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickChip(
                label: 'Financeiro',
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFF5EEAD4),
                onTap: onOpenFinanceiro,
              ),
              _QuickChip(
                label: 'Objetivos Financeiros',
                icon: Icons.flag_rounded,
                color: const Color(0xFFF9A8D4),
                onTap: onOpenObjetivo,
              ),
              _QuickChip(
                label: 'Agenda',
                icon: Icons.event_note_rounded,
                color: const Color(0xFFC4B5FD),
                onTap: onOpenAgenda,
              ),
              _QuickChip(
                label: 'Cursos',
                icon: Icons.ondemand_video_rounded,
                color: const Color(0xFF7DD3FC),
                onTap: onOpenCursos,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
