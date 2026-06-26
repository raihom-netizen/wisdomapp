import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/delegate_access_service.dart';
import '../services/ios_payments_gate.dart';
import '../theme/app_colors.dart';
import '../constants/anotacoes_module_icons.dart';
import '../constants/calculator_module_icons.dart';
import 'home_start_module_picker.dart';

/// Menu lateral esquerdo azul escuro — usuário (mesmo padrão admin).
class UserMenuLateral extends StatelessWidget {
  final String uid;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  /// Ao salvar a tela inicial padrão no seletor, aplica a aba atual (mesmo efeito de tocar no menu).
  final ValueChanged<int> onHomeStartModuleSaved;
  final bool isCollapsed;
  /// Quando preenchido (ex.: app iOS nativo), exibe como primeira opção e substitui “Adquirir planos”.
  final VoidCallback? onOpenOfficialSubscriptionSite;

  const UserMenuLateral({
    super.key,
    required this.uid,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onHomeStartModuleSaved,
    this.isCollapsed = false,
    this.onOpenOfficialSubscriptionSite,
  });

  @override
  Widget build(BuildContext context) {
    final width = isCollapsed ? 64.0 : 240.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.deepBlueDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Image.asset('assets/images/icon.png', height: isCollapsed ? 32 : 44, width: isCollapsed ? 32 : 44, errorBuilder: (_, __, ___) => Icon(Icons.apps_rounded, color: Colors.white, size: isCollapsed ? 32 : 44)),
          if (!isCollapsed) ...[
            const SizedBox(height: 10),
            const Text(
              'WISDOMAPP',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 6 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onOpenOfficialSubscriptionSite != null) ...[
                    _officialSiteSubscriptionTile(context, isCollapsed),
                    const SizedBox(height: 8),
                  ],
                  if (onOpenOfficialSubscriptionSite == null &&
                      !DelegateAccessService.isActingAsDelegate) ...[
                    _planosTile(context, isCollapsed),
                    const SizedBox(height: 8),
                  ],
                  _tile(9, Icons.settings_rounded, 'Configurações', isCollapsed,
                      accent: const Color(0xFFCBD5E1),
                      subtitle: 'Backup, notificações e preferências'),
                  const SizedBox(height: 12),
                  _tile(0, Icons.home_rounded, 'Início', isCollapsed,
                      accent: const Color(0xFF93C5FD)),
                  _tile(1, Icons.account_balance_wallet_rounded, 'Financeiro',
                      isCollapsed,
                      accent: const Color(0xFF5EEAD4)),
                  _tile(2, Icons.flag_rounded, 'Objetivo Financeiro',
                      isCollapsed,
                      accent: const Color(0xFFEC4899)),
                  _tile(3, Icons.calendar_month_rounded, kAgendaModuleDisplayName,
                      isCollapsed,
                      accent: const Color(0xFF22D3EE)),
                  _tile(4, CalculatorModuleIcons.nav, 'Calculadora',
                      isCollapsed,
                      accent: const Color(0xFFFDBA74)),
                  _tile(5, Icons.menu_book_rounded, 'Dicas Financeiras',
                      isCollapsed,
                      accent: const Color(0xFFC4B5FD)),
                  _tile(6, Icons.assessment_rounded, 'Relatórios', isCollapsed,
                      accent: const Color(0xFF86EFAC)),
                  _tile(7, Icons.ondemand_video_rounded, 'Cursos em Vídeo',
                      isCollapsed,
                      accent: const Color(0xFF38BDF8)),
                  _tile(8, AnotacoesModuleIcons.nav, 'Minhas Anotações', isCollapsed,
                      accent: const Color(0xFF7DD3FC)),
                  _homeStartDefaultTile(context, isCollapsed),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _officialSiteSubscriptionTile(BuildContext context, bool collapsed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.amber.shade800.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onOpenOfficialSubscriptionSite,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 12, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 24, color: Colors.amber.shade200),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Gerenciamento de licença',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: collapsed ? 12 : 13,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _planosTile(BuildContext context, bool collapsed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: AppColors.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => IosPaymentsGate.pushEscolhaPlano(context),
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 10 : 12,
                vertical: 12,
              ),
              child: Row(
                children: [
                  const Icon(Icons.pix_rounded, size: 24, color: AppColors.amber),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Adquirir planos',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _homeStartDefaultTile(BuildContext context, bool collapsed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: homePlanningRef(uid).snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? <String, dynamic>{};
            final raw = data[kHomeDefaultStartModuleField];
            final sel = normalizeHomeStartModuleIndex(
              raw is num ? raw.toInt() : 1,
            );
            final labelFull =
                kHomeDefaultStartModuleLabels[sel] ??
                    kHomeDefaultStartModuleLabels[1]!;
            final labelShort = labelFull.contains('(')
                ? labelFull.split('(').first.trim()
                : labelFull;
            return Tooltip(
              message: collapsed
                  ? 'Tela inicial ao abrir: $labelFull'
                  : 'Escolher em qual módulo o app abre ao iniciar',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => showHomeStartModulePickerSheet(
                  context,
                  uid: uid,
                  initialSelected: sel,
                  onSaved: onHomeStartModuleSaved,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: collapsed ? 10 : 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.home_work_outlined,
                          size: 24,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        if (!collapsed) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Tela inicial padrão',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Abre em: $labelShort',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: Colors.white54,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tile(
    int index,
    IconData icon,
    String label,
    bool collapsed, {
    required Color accent,
    String? subtitle,
  }) {
    final selected = selectedIndex == index;
    final iconColor = selected ? AppColors.amber : accent;
    final textColor = selected ? AppColors.amber : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.deepBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => onItemSelected(index),
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 10 : 12,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: selected
                          ? null
                          : LinearGradient(
                              colors: [
                                accent.withValues(alpha: 0.35),
                                accent.withValues(alpha: 0.12),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: selected
                          ? Colors.white.withValues(alpha: 0.12)
                          : null,
                      boxShadow: selected
                          ? null
                          : [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Icon(icon, size: 21, color: iconColor),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: textColor,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w600,
                              fontSize: index == 7 ? 12.5 : 14,
                              height: 1.25,
                            ),
                            maxLines: index == 7 ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                                fontSize: 10.5,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
