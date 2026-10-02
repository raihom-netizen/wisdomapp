import '../widgets/admin_menu_lateral.dart';

/// Editor de conteúdo (02/10/2026, pedido do dono): só grava/edita/exclui os
/// vídeos dos Cursos (inclui dicas em vídeo) e as Dicas financeiras pelo
/// Painel Admin — NADA mais (usuários, financeiro, equipe, logs, relatórios,
/// configurações ficam ocultos E bloqueados no servidor).
///
/// Papel no Firestore: `users/{uid}.role = 'editor_conteudo'`.
/// Servidor que respeita o papel:
///  - functions: `requireCourseContentEditor` (ctAdminUpsertCourseVideo,
///    ctAdminDeleteCourseVideos) e `ctGenerateFinancialTipWithAI`;
///    `ctAdminSaveWisdomCoursesModuleConfig` (textos do módulo) NÃO aceita;
///  - firestore.rules: `financial_tips` (CRUD) e `app_config/financial_tips_home`;
///  - storage.rules: `wisdomapp/course_videos/**` (MP4 e capas).
/// Não lê `users` de outros, `mp_payments`, `course_stats`, logs etc.
class AdminContentEditorConfig {
  AdminContentEditorConfig._();

  static const String role = 'editor_conteudo';

  static const List<AdminMenuItem> kAllowedMenuItems = [
    AdminMenuItem.cursos,
    AdminMenuItem.dicasFinanceiras,
  ];

  static const AdminMenuItem kDefaultMenuItem = AdminMenuItem.cursos;

  static bool isContentEditorRole(String role) =>
      role.trim().toLowerCase() == AdminContentEditorConfig.role;
}
