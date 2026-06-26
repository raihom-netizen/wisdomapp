import 'package:flutter/material.dart';

/// Papéis da equipe WISDOMAPP (Painel Admin).
enum TeamRole {
  master,
  admin,
  gestor,
  partner,
  suporte,
  editor,
}

class TeamRoleConfig {
  TeamRoleConfig._();

  static const firestoreRoles = {'admin', 'master', 'gestor', 'partner', 'socio'};

  static TeamRole fromFirestore({
    required String role,
    String? adminLevel,
  }) {
    final r = role.trim().toLowerCase();
    if (r == 'master') return TeamRole.master;
    if (r == 'gestor') return TeamRole.gestor;
    if (r == 'partner' || r == 'socio') return TeamRole.partner;
    if (r == 'admin') {
      final lvl = (adminLevel ?? '').trim().toLowerCase();
      if (lvl == 'editor') return TeamRole.editor;
      if (lvl == 'suporte') return TeamRole.suporte;
      return TeamRole.admin;
    }
    return TeamRole.admin;
  }

  static String firestoreRoleFor(TeamRole role) {
    switch (role) {
      case TeamRole.master:
        return 'master';
      case TeamRole.gestor:
        return 'gestor';
      case TeamRole.partner:
        return 'partner';
      case TeamRole.admin:
      case TeamRole.suporte:
      case TeamRole.editor:
        return 'admin';
    }
  }

  static String? adminLevelFor(TeamRole role) {
    switch (role) {
      case TeamRole.suporte:
        return 'suporte';
      case TeamRole.editor:
        return 'editor';
      default:
        return null;
    }
  }

  static String label(TeamRole role) {
    switch (role) {
      case TeamRole.master:
        return 'Master';
      case TeamRole.admin:
        return 'Administrador';
      case TeamRole.gestor:
        return 'Gestor';
      case TeamRole.partner:
        return 'Sócio';
      case TeamRole.suporte:
        return 'Suporte';
      case TeamRole.editor:
        return 'Editor';
    }
  }

  static String description(TeamRole role) {
    switch (role) {
      case TeamRole.master:
        return 'Acesso total, faturamento, equipe e exclusão de outros ADMs.';
      case TeamRole.admin:
        return 'Painel completo: usuários, licenças, Mercado Pago, deploy e configurações.';
      case TeamRole.gestor:
        return 'Dicas, vídeos dos cursos, relatórios e recebimentos. '
            'Usuários somente leitura — sem editar licenças.';
      case TeamRole.partner:
        return 'Resumo financeiro da própria parte, usuários e recebimentos — somente leitura.';
      case TeamRole.suporte:
        return 'Usuários e licenças; sem chaves do Mercado Pago.';
      case TeamRole.editor:
        return 'Divulgação e escalas; sem backups nem financeiro.';
    }
  }

  static Color color(TeamRole role) {
    switch (role) {
      case TeamRole.master:
        return const Color(0xFFD97706);
      case TeamRole.admin:
        return const Color(0xFF2563EB);
      case TeamRole.gestor:
        return const Color(0xFF7C3AED);
      case TeamRole.partner:
        return const Color(0xFF0F766E);
      case TeamRole.suporte:
        return const Color(0xFF1D4ED8);
      case TeamRole.editor:
        return const Color(0xFF0EA5E9);
    }
  }

  static IconData icon(TeamRole role) {
    switch (role) {
      case TeamRole.master:
        return Icons.workspace_premium_rounded;
      case TeamRole.admin:
        return Icons.admin_panel_settings_rounded;
      case TeamRole.gestor:
        return Icons.manage_accounts_rounded;
      case TeamRole.partner:
        return Icons.handshake_rounded;
      case TeamRole.suporte:
        return Icons.support_agent_rounded;
      case TeamRole.editor:
        return Icons.edit_note_rounded;
    }
  }

  /// Papéis que o Master pode atribuir ao criar membro.
  static const creatableRoles = [
    TeamRole.admin,
    TeamRole.gestor,
    TeamRole.partner,
    TeamRole.suporte,
    TeamRole.editor,
  ];
}
