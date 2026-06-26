import '../constants/app_brand.dart';
import '../widgets/admin_menu_lateral.dart';

/// Sócio / partner — painel financeiro e usuários somente leitura (Johnathan Tarley).
class AdminPartnerConfig {
  AdminPartnerConfig._();

  static const Set<String> kPartnerEmails = {
    // Sócios adicionais (somente leitura financeira). Tarley = gestor.
  };

  static const List<AdminMenuItem> kAllowedMenuItems = [
    AdminMenuItem.resumo,
    AdminMenuItem.usuarios,
    AdminMenuItem.usuarios360,
    AdminMenuItem.mercadopago,
    AdminMenuItem.acessosDominio,
  ];

  static const AdminMenuItem kDefaultMenuItem = AdminMenuItem.resumo;

  static bool isPartnerEmail(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    if (e.isEmpty) return false;
    return kPartnerEmails.contains(e);
  }

  static bool isPartnerRole(String role) =>
      role.trim().toLowerCase() == 'partner';

  static bool isPartnerAccount({required String role, String? email}) =>
      isPartnerRole(role) || isPartnerEmail(email);

  static String get displayName => AppBrand.idealizerName;
}
