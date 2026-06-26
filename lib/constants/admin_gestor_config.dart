import '../widgets/admin_menu_lateral.dart';

/// Gestores — conteúdo + relatórios/recebimentos + usuários (sem licenças).
class AdminGestorConfig {
  AdminGestorConfig._();

  /// Fallback se `role` ainda não estiver no Firestore.
  static const Set<String> kGestorEmails = {
    'tarleypmgo@gmail.com',
  };

  /// Menu do gestor (Tarley e demais gestores).
  static const List<AdminMenuItem> kAllowedMenuItems = [
    AdminMenuItem.resumo,
    AdminMenuItem.usuarios,
    AdminMenuItem.usuarios360,
    AdminMenuItem.relatorios,
    AdminMenuItem.mercadopago,
    AdminMenuItem.dicasFinanceiras,
    AdminMenuItem.cursos,
    AdminMenuItem.landing,
  ];

  static const AdminMenuItem kDefaultMenuItem = AdminMenuItem.resumo;

  static bool isGestorEmail(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    if (e.isEmpty) return false;
    return kGestorEmails.contains(e);
  }

  static bool isGestorRole(String role) =>
      role.trim().toLowerCase() == 'gestor';

  static bool isGestorAccount({required String role, String? email}) =>
      isGestorRole(role) || isGestorEmail(email);
}
