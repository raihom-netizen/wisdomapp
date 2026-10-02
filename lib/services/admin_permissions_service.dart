import '../constants/admin_content_editor_config.dart';
import '../constants/admin_gestor_config.dart';
import '../constants/admin_master_config.dart';
import '../constants/admin_partner_config.dart';
import '../widgets/admin_menu_lateral.dart';

/// Níveis de permissão do painel admin (granular sobre `role` Firestore).
///
/// 02/10/2026: MASTER = só os e-mails de [AdminMasterConfig] (login
/// verificado). `role: admin` agora respeita `adminLevel` (Suporte/Editor) —
/// antes todo admin virava [support] com o menu completo.
enum AdminCapability {
  /// Gestor de conteúdo: dicas, cursos YouTube, landing/divulgação (canais).
  contentGestor,

  /// Sócio: usuários/licenças/receitas da própria parte — somente leitura.
  partner,

  /// Editor de conteúdo (`role: editor_conteudo`): SÓ Cursos (vídeos) e
  /// Dicas financeiras. Servidor bloqueia o resto (functions + regras).
  contentEditor,

  /// Só visualização (resumo, listas, 360° leitura).
  readonly,

  /// Suporte (`role: admin` + `adminLevel: suporte`): usuários e licenças.
  support,

  /// Editor (`role: admin` + `adminLevel: editor`): divulgação, conteúdo e
  /// escalas — sem usuários, financeiro nem backups.
  editor,

  /// Financeiro (override `adminCapability: finance`): relatórios e receitas.
  finance,

  /// Administrador (`role: admin` sem nível): painel completo MENOS o que é
  /// só do master (backups, restaurar, migração, manutenção, lojas, Mercado
  /// Pago, excluir usuário, equipe).
  admin,

  /// Master (só os e-mails dos donos): tudo.
  superAdmin,
}

/// Mapeia `users.role` + `adminLevel` (+ override `adminCapability`) para capacidades.
class AdminPermissionsService {
  const AdminPermissionsService();

  /// [email] deve ser o e-mail do LOGIN (FirebaseAuth) e [emailVerified] se
  /// ele está verificado — master só por e-mail de dono verificado.
  AdminCapability capabilityFor({
    required String role,
    String? email,
    bool emailVerified = false,
    String? adminLevel,
    String? adminCapabilityOverride,
  }) {
    final emailNorm = (email ?? '').trim().toLowerCase();
    if (emailVerified && AdminMasterConfig.isMasterEmail(emailNorm)) {
      return AdminCapability.superAdmin;
    }

    // Papel explícito vem antes de qualquer fallback por e-mail: quem é
    // editor de conteúdo nunca herda poderes de gestor/sócio.
    if (AdminContentEditorConfig.isContentEditorRole(role)) {
      return AdminCapability.contentEditor;
    }

    if (AdminPartnerConfig.isPartnerAccount(role: role, email: emailNorm)) {
      return AdminCapability.partner;
    }

    if (AdminGestorConfig.isGestorAccount(role: role, email: emailNorm)) {
      return AdminCapability.contentGestor;
    }

    final r = role.trim().toLowerCase();
    // `master`/`superadmin` gravado no Firestore sem ser dono = admin comum.
    final isAdminRole = r == 'admin' ||
        r == 'master' ||
        r == 'superadmin' ||
        r == 'super_admin';
    if (!isAdminRole) return AdminCapability.readonly;

    final lvl = (adminLevel ?? '').trim().toLowerCase();
    if (lvl == 'suporte' || lvl == 'support') return AdminCapability.support;
    if (lvl == 'editor') return AdminCapability.editor;

    final override = (adminCapabilityOverride ?? '').trim().toLowerCase();
    switch (override) {
      case 'readonly':
      case 'leitura':
        return AdminCapability.readonly;
      case 'support':
      case 'suporte':
        return AdminCapability.support;
      case 'finance':
      case 'financeiro':
        return AdminCapability.finance;
      case 'editor':
        return AdminCapability.editor;
      // 'master'/'super' no override NÃO dá master (só e-mail de dono).
    }
    return AdminCapability.admin;
  }

  bool isMaster(AdminCapability c) => c == AdminCapability.superAdmin;

  /// Itens que SÓ o master acessa (menu e rotas).
  static const Set<AdminMenuItem> kMasterOnlyItems = {
    AdminMenuItem.drive,
    AdminMenuItem.migracaoEmail,
    AdminMenuItem.manutencao,
    AdminMenuItem.lojas,
    AdminMenuItem.mercadopago,
    AdminMenuItem.promoverAdmin,
  };

  /// Itens escondidos de todos (módulos desligados no WisdomApp).
  static const Set<AdminMenuItem> _kOcultos = {
    AdminMenuItem.voltar,
    AdminMenuItem.pluggy,
    AdminMenuItem.openFinanceExtras,
    AdminMenuItem.premiumProMonitor,
  };

  bool canViewResumo(AdminCapability c) => true;

  bool _gereUsuarios(AdminCapability c) =>
      c == AdminCapability.support ||
      c == AdminCapability.admin ||
      c == AdminCapability.superAdmin;

  bool canEditUserLicense(AdminCapability c) => _gereUsuarios(c);

  bool isPartner(AdminCapability c) => c == AdminCapability.partner;

  bool canBulkActions(AdminCapability c) => _gereUsuarios(c);

  /// Excluir usuário (total/definitivo) — só master.
  bool canDeleteUserPermanent(AdminCapability c) =>
      c == AdminCapability.superAdmin;

  bool canRemoveUser(AdminCapability c) => _gereUsuarios(c);

  /// Mercado Pago: SÓ master (raihom e isabelle por e-mail). Decisão do dono
  /// 02/10/2026: não aparece para o Tarley nem para sócio/gestor.
  bool canAccessMercadoPago(AdminCapability c) =>
      c == AdminCapability.superAdmin;

  /// Chaves/config do Mercado Pago — só master.
  bool canEditMercadoPagoConfig(AdminCapability c) =>
      c == AdminCapability.superAdmin;

  bool canForceAppVersion(AdminCapability c) =>
      c == AdminCapability.superAdmin;

  bool canManageTeam(AdminCapability c) => c == AdminCapability.superAdmin;

  /// Enviar notificação de teste (push real) — só master.
  bool canSendTestNotifications(AdminCapability c) =>
      c == AdminCapability.superAdmin;

  bool isContentGestor(AdminCapability c) =>
      c == AdminCapability.contentGestor;

  bool isContentEditor(AdminCapability c) =>
      c == AdminCapability.contentEditor;

  static const List<AdminMenuItem> _kSuporte = [
    AdminMenuItem.resumo,
    AdminMenuItem.painelGeral,
    AdminMenuItem.usuarios,
    AdminMenuItem.usuarios360,
    AdminMenuItem.usoModulos,
    AdminMenuItem.usuariosAtivos,
    AdminMenuItem.usuariosPainel,
    AdminMenuItem.sugestoes,
    AdminMenuItem.convenios,
    AdminMenuItem.promocoes,
    AdminMenuItem.emailsProblema,
    AdminMenuItem.notificacoes,
  ];

  static const List<AdminMenuItem> _kEditor = [
    AdminMenuItem.resumo,
    AdminMenuItem.sugestoes,
    AdminMenuItem.cursos,
    AdminMenuItem.dicasFinanceiras,
    AdminMenuItem.landing,
    AdminMenuItem.downloads,
    AdminMenuItem.acessosDominio,
    AdminMenuItem.escala,
  ];

  static const List<AdminMenuItem> _kFinanceiro = [
    AdminMenuItem.resumo,
    AdminMenuItem.painelGeral,
    AdminMenuItem.relatorios,
    AdminMenuItem.receitasDespesas,
    AdminMenuItem.previsaoPlanos,
    AdminMenuItem.usuarios,
    AdminMenuItem.usuarios360,
  ];

  static const List<AdminMenuItem> _kLeitura = [
    AdminMenuItem.resumo,
    AdminMenuItem.painelGeral,
    AdminMenuItem.usuarios,
    AdminMenuItem.usuarios360,
    AdminMenuItem.usoModulos,
    AdminMenuItem.relatorios,
  ];

  /// Itens do menu lateral permitidos para a capacidade atual.
  List<AdminMenuItem> allowedMenuItems(AdminCapability c) {
    switch (c) {
      case AdminCapability.contentGestor:
        return AdminGestorConfig.kAllowedMenuItems;
      case AdminCapability.partner:
        return AdminPartnerConfig.kAllowedMenuItems;
      case AdminCapability.contentEditor:
        return AdminContentEditorConfig.kAllowedMenuItems;
      case AdminCapability.support:
        return _kSuporte;
      case AdminCapability.editor:
        return _kEditor;
      case AdminCapability.finance:
        return _kFinanceiro;
      case AdminCapability.readonly:
        return _kLeitura;
      case AdminCapability.admin:
        return AdminMenuItem.values
            .where((i) => !_kOcultos.contains(i) && !kMasterOnlyItems.contains(i))
            .toList();
      case AdminCapability.superAdmin:
        return AdminMenuItem.values
            .where((i) => !_kOcultos.contains(i))
            .toList();
    }
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
    if (c == AdminCapability.contentEditor) {
      return AdminContentEditorConfig.kDefaultMenuItem;
    }
    return AdminMenuItem.resumo;
  }

  String label(AdminCapability c) {
    switch (c) {
      case AdminCapability.contentGestor:
        return 'Gestor';
      case AdminCapability.partner:
        return 'Sócio · ${AdminPartnerConfig.displayName}';
      case AdminCapability.contentEditor:
        return 'Editor de conteúdo';
      case AdminCapability.readonly:
        return 'Somente leitura';
      case AdminCapability.support:
        return 'Suporte';
      case AdminCapability.editor:
        return 'Editor';
      case AdminCapability.finance:
        return 'Financeiro';
      case AdminCapability.admin:
        return 'Administrador';
      case AdminCapability.superAdmin:
        return 'Master';
    }
  }
}
