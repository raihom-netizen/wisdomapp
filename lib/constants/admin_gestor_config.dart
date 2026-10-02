import '../widgets/admin_menu_lateral.dart';

/// Gestores — conteúdo + relatórios/recebimentos + usuários (sem licenças).
class AdminGestorConfig {
  AdminGestorConfig._();

  /// Fallback se `role` ainda não estiver no Firestore.
  /// 02/10/2026: tarleypmgo@gmail.com SAIU daqui — ele é editor de conteúdo
  /// (`role: editor_conteudo`, só Cursos + Dicas). Um e-mail aqui daria a ele
  /// o menu do gestor (usuários, relatórios, recebimentos) no app.
  static const Set<String> kGestorEmails = {};

  /// Menu do gestor.
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
