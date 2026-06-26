import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum AdminMenuItem { resumo, usuarios, usuarios360, equipe, logs, relatorios, sugestoes, dicasFinanceiras, downloads, landing, acessosDominio, escala, drive, mercadopago, cursos, pluggy, openFinanceExtras, premiumProMonitor, promocoes, convenios, lojas, migracaoEmail, email, manutencao, voltar }

/// Cor de destaque por módulo — menu admin moderno e colorido.
Color adminMenuAccentColor(AdminMenuItem item) {
  switch (item) {
    case AdminMenuItem.resumo:
      return const Color(0xFF6366F1);
    case AdminMenuItem.usuarios:
      return const Color(0xFF2D5BFF);
    case AdminMenuItem.usuarios360:
      return const Color(0xFF0EA5E9);
    case AdminMenuItem.equipe:
      return const Color(0xFF8B5CF6);
    case AdminMenuItem.logs:
      return const Color(0xFF64748B);
    case AdminMenuItem.relatorios:
      return const Color(0xFF14B8A6);
    case AdminMenuItem.sugestoes:
      return const Color(0xFFF59E0B);
    case AdminMenuItem.dicasFinanceiras:
      return const Color(0xFFEAB308);
    case AdminMenuItem.downloads:
      return const Color(0xFF06B6D4);
    case AdminMenuItem.landing:
      return const Color(0xFFEC4899);
    case AdminMenuItem.acessosDominio:
      return const Color(0xFFA855F7);
    case AdminMenuItem.escala:
      return const Color(0xFF10B981);
    case AdminMenuItem.drive:
      return const Color(0xFF3B82F6);
    case AdminMenuItem.mercadopago:
      return const Color(0xFF00B1EA);
    case AdminMenuItem.cursos:
      return const Color(0xFFEF4444);
    case AdminMenuItem.promocoes:
      return const Color(0xFFF97316);
    case AdminMenuItem.convenios:
      return const Color(0xFF6366F1);
    case AdminMenuItem.lojas:
      return const Color(0xFF22C55E);
    case AdminMenuItem.migracaoEmail:
      return const Color(0xFF78716C);
    case AdminMenuItem.email:
      return const Color(0xFF0D9488);
    case AdminMenuItem.manutencao:
      return const Color(0xFFDC2626);
    case AdminMenuItem.voltar:
      return const Color(0xFF94A3B8);
    default:
      return AppColors.primary;
  }
}

class AdminMenuLateral extends StatelessWidget {
  final AdminMenuItem selectedItem;
  final void Function(AdminMenuItem) onItemSelected;
  final bool isCollapsed;
  /// No celular: quando true, o menu é exibido dentro de um Drawer e fecha após seleção.
  final bool asDrawer;
  /// Callback para fechar o drawer (Scaffold.closeDrawer). Obrigatório quando asDrawer true — Navigator.pop pode fechar o painel inteiro.
  final VoidCallback? onCloseDrawer;
  /// Se informado, só estes itens aparecem (ex.: gestor de conteúdo).
  final List<AdminMenuItem>? allowedItems;
  final String? accountEmail;
  final String? accountSubtitle;
  final Map<AdminMenuItem, String>? titleOverrides;

  const AdminMenuLateral({
    super.key,
    required this.selectedItem,
    required this.onItemSelected,
    this.isCollapsed = false,
    this.asDrawer = false,
    this.onCloseDrawer,
    this.allowedItems,
    this.accountEmail,
    this.accountSubtitle,
    this.titleOverrides,
  });

  /// BLINDAGEM: primeiro atualiza estado (módulo abre); depois fecha drawer com onCloseDrawer (nunca Navigator.pop no context da tela).
  void _onTap(AdminMenuItem item) {
    onItemSelected(item);
    if (asDrawer && item != AdminMenuItem.voltar && onCloseDrawer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onCloseDrawer!();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = allowedItems?.toSet();
    final filteredEntries = <({AdminMenuItem item, String title, IconData icon})>[
      (item: AdminMenuItem.resumo, title: 'Resumo', icon: Icons.dashboard_rounded),
      (item: AdminMenuItem.usuarios, title: 'Usuários', icon: Icons.people_rounded),
      (item: AdminMenuItem.usuarios360, title: 'Usuários 360°', icon: Icons.hub_rounded),
      (item: AdminMenuItem.equipe, title: 'Equipe', icon: Icons.groups_rounded),
      (item: AdminMenuItem.logs, title: 'Logs', icon: Icons.history_rounded),
      (item: AdminMenuItem.relatorios, title: 'Relatórios', icon: Icons.bar_chart_rounded),
      (item: AdminMenuItem.sugestoes, title: 'Sugestões', icon: Icons.feedback_rounded),
      (item: AdminMenuItem.dicasFinanceiras, title: 'Dicas financeiras', icon: Icons.lightbulb_rounded),
      (item: AdminMenuItem.downloads, title: 'Downloads', icon: Icons.download_rounded),
      (item: AdminMenuItem.landing, title: 'Landing / Divulgação', icon: Icons.web_rounded),
      (item: AdminMenuItem.acessosDominio, title: 'Acessos domínio', icon: Icons.analytics_rounded),
      (item: AdminMenuItem.escala, title: 'Escala', icon: Icons.calendar_month_rounded),
      (item: AdminMenuItem.drive, title: 'Backups', icon: Icons.cloud_rounded),
      (item: AdminMenuItem.mercadopago, title: 'Mercado Pago', icon: Icons.payment_rounded),
      (item: AdminMenuItem.cursos, title: 'Cursos em vídeo', icon: Icons.ondemand_video_rounded),
      (item: AdminMenuItem.promocoes, title: 'Promoções', icon: Icons.local_offer_rounded),
      (item: AdminMenuItem.convenios, title: 'Convênios', icon: Icons.handshake_rounded),
      (item: AdminMenuItem.lojas, title: 'Publicar nas Lojas', icon: Icons.store_rounded),
      (item: AdminMenuItem.migracaoEmail, title: 'Migração e-mail', icon: Icons.swap_horiz_rounded),
      (item: AdminMenuItem.email, title: 'E-mail', icon: Icons.email_rounded),
      (item: AdminMenuItem.manutencao, title: 'Manutenção', icon: Icons.construction_rounded),
    ];
    final visibleMenu = allowed == null
        ? filteredEntries
        : filteredEntries.where((e) => allowed.contains(e.item)).toList();
    final menuWidgets = visibleMenu
        .map((e) => _menuItem(
              context,
              e.item,
              titleOverrides?[e.item] ?? e.title,
              e.icon,
            ))
        .toList();
    final content = Container(
      width: asDrawer ? null : (isCollapsed ? 72 : 260),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0E21),
        border: Border(right: BorderSide(color: Color(0xFF1D2B4D), width: 1)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF2D5BFF), Color(0xFF12B5A5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              accountName: Text(
                'Painel Admin WISDOMAPP',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: asDrawer ? 18 : 16,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              accountEmail: Text(
                accountSubtitle ??
                    (accountEmail != null
                        ? '$accountEmail · gestão completa'
                        : 'raihom@gmail.com · MP · usuários · licenças'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.15),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white70),
              ),
            ),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: menuWidgets,
              ),
            ),
            const Divider(color: Colors.white10),
            _menuItem(context, AdminMenuItem.voltar, 'Voltar ao aplicativo', Icons.arrow_back_rounded),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (asDrawer) {
      return Drawer(
        child: content,
      );
    }
    return content;
  }

  /// BLINDAGEM: InkWell com área mínima 48px (ver blindagem-ux-menus-touch.mdc).
  Widget _menuItem(BuildContext context, AdminMenuItem item, String title, IconData icon) {
    final selected = selectedItem == item;
    final accent = adminMenuAccentColor(item);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _onTap(item),
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? LinearGradient(
                              colors: [
                                accent.withValues(alpha: 0.55),
                                accent.withValues(alpha: 0.25),
                              ],
                            )
                          : null,
                      color: selected ? null : accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? accent.withValues(alpha: 0.65)
                            : accent.withValues(alpha: 0.22),
                        width: selected ? 1.2 : 1,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: selected ? Colors.white : accent.withValues(alpha: 0.95),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.82),
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: asDrawer ? 15 : 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
