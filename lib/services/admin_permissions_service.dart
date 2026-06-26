import '../constants/premium_pro_limits.dart';
import '../constants/admin_gestor_config.dart';
import '../constants/admin_partner_config.dart';
import '../widgets/admin_menu_lateral.dart';

/// Níveis de permissão do painel admin (granular sobre `role` Firestore).
enum AdminCapability {
  /// Gestor de conteúdo: dicas, cursos YouTube, landing/divulgação (canais).
  contentGestor,

  /// Sócio: usuários/licenças/receitas da própria parte — somente leitura.
  partner,

  /// Só visualização (resumo, listas, 360° leitura).
  readonly,

  /// Editar vencimento, prorrogar, reativar, notas internas.
  support,

  /// Mercado Pago, relatórios financeiros, exportações.
  finance,

  /// Tudo: exclusão total, equipe, forçar versão, migração.
  superAdmin,
}

/// Mapeia `users.role` (+ override opcional `adminCapability`) para capacidades.
class AdminPermissionsService {
  const AdminPermissionsService();

  AdminCapability capabilityFor({
    required String role,
    String? email,
    String? adminCapabilityOverride,
  }) {
    final emailNorm = (email ?? '').trim().toLowerCase();
    if (PremiumProLimits.kHighIncludedConnectionsEmails.contains(emailNorm)) {
      return AdminCapability.superAdmin;
    }

    if (AdminPartnerConfig.isPartnerAccount(role: role, email: emailNorm)) {
      return AdminCapability.partner;
    }

    if (AdminGestorConfig.isGestorAccount(role: role, email: emailNorm)) {
      return AdminCapability.contentGestor;
    }

    final override = (adminCapabilityOverride ?? '').trim().toLowerCase();
    if (override.isNotEmpty) {
      switch (override) {
        case 'gestor':
        case 'conteudo':
        case 'content':
          return AdminCapability.contentGestor;
        case 'readonly':
        case 'leitura':
          return AdminCapability.readonly;
        case 'support':
        case 'suporte':
          return AdminCapability.support;
        case 'finance':
        case 'financeiro':
          return AdminCapability.finance;
        case 'super':
        case 'superadmin':
        case 'master':
          return AdminCapability.superAdmin;
        case 'partner':
        case 'socio':
          return AdminCapability.partner;
      }
    }
    switch (role.trim().toLowerCase()) {
      case 'gestor':
        return AdminCapability.contentGestor;
      case 'partner':
      case 'socio':
        return AdminCapability.partner;
      case 'master':
      case 'superadmin':
      case 'super_admin':
        return AdminCapability.superAdmin;
      case 'admin':
        return AdminCapability.support;
      default:
        return AdminCapability.readonly;
    }
  }

  bool canViewResumo(AdminCapability c) => true;

  bool canEditUserLicense(AdminCapability c) =>
      c == AdminCapability.support || c == AdminCapability.superAdmin;

  bool isPartner(AdminCapability c) => c == AdminCapability.partner;

  bool canBulkActions(AdminCapability c) =>
      c == AdminCapability.support || c == AdminCapability.superAdmin;

  bool canDeleteUserPermanent(AdminCapability c) =>
      c == AdminCapability.superAdmin;

  bool canRemoveUser(AdminCapability c) =>
      c == AdminCapability.support || c == AdminCapability.superAdmin;

  bool canAccessMercadoPago(AdminCapability c) =>
      c == AdminCapability.finance ||
      c == AdminCapability.superAdmin ||
      c == AdminCapability.partner ||
      c == AdminCapability.contentGestor;

  bool canEditMercadoPagoConfig(AdminCapability c) =>
      c == AdminCapability.finance || c == AdminCapability.superAdmin;

  bool canForceAppVersion(AdminCapability c) =>
      c == AdminCapability.superAdmin;

  bool canManageTeam(AdminCapability c) => c == AdminCapability.superAdmin;

  bool isContentGestor(AdminCapability c) =>
      c == AdminCapability.contentGestor;

  /// Itens do menu lateral permitidos para a capacidade atual.
  List<AdminMenuItem> allowedMenuItems(AdminCapability c) {
    if (c == AdminCapability.contentGestor) {
      return AdminGestorConfig.kAllowedMenuItems;
    }
    if (c == AdminCapability.partner) {
      return AdminPartnerConfig.kAllowedMenuItems;
    }
    return AdminMenuItem.values
        .where((i) =>
            i != AdminMenuItem.voltar &&
            i != AdminMenuItem.pluggy &&
            i != AdminMenuItem.openFinanceExtras &&
            i != AdminMenuItem.premiumProMonitor)
        .toList();
  }

  bool canAccessMenuItem(AdminCapability c, AdminMenuItem item) {
    if (item == AdminMenuItem.voltar) return true;
    return allowedMenuItems(c).contains(item);
  }

  AdminMenuItem defaultMenuItem(AdminCapability c) {
    if (c == AdminCapability.contentGestor) {
      return AdminGestorConfig.kDefaultMenuItem;
    }
    if (c == AdminCapability.partner) {
      return AdminPartnerConfig.kDefaultMenuItem;
    }
    return AdminMenuItem.resumo;
  }

  String label(AdminCapability c) {
    switch (c) {
      case AdminCapability.contentGestor:
        return 'Gestor';
      case AdminCapability.partner:
        return 'Sócio · ${AdminPartnerConfig.displayName}';
      case AdminCapability.readonly:
        return 'Somente leitura';
      case AdminCapability.support:
        return 'Suporte';
      case AdminCapability.finance:
        return 'Financeiro';
      case AdminCapability.superAdmin:
        return 'Super admin';
    }
  }
}
