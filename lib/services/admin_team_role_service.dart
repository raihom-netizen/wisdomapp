import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/team_role_config.dart';
import '../utils/admin_load_guard.dart';
import 'logs_service.dart';

/// Papel da equipe (role/adminLevel) — SÓ o master muda (02/10/2026).
///
/// Caminho principal: callable `ctAdminSetUserRole` (confere o master pelo
/// e-mail verificado do token, grava pelo Admin SDK e registra em
/// `activity_logs`). Enquanto a função não estiver publicada (not-found /
/// unimplemented), cai na gravação direta — as regras do Firestore só
/// deixam o master (e-mail dono) mexer em role/adminLevel.
class AdminTeamRoleService {
  const AdminTeamRoleService();

  static const _callable = 'ctAdminSetUserRole';

  bool _funcaoAusente(FirebaseFunctionsException e) =>
      e.code == 'not-found' || e.code == 'unimplemented';

  /// Promove/troca o papel. [role] null = rebaixar a usuário comum.
  Future<void> definirPapel({
    required String uid,
    required TeamRole? role,
    String? nome,
    String? emailAlvo,
  }) async {
    final firestoreRole =
        role == null ? 'user' : TeamRoleConfig.firestoreRoleFor(role);
    final nivel = role == null ? null : TeamRoleConfig.adminLevelFor(role);
    if (firestoreRole == 'master') {
      throw StateError('Ninguém vira master pelo painel: master é só o e-mail '
          'dos donos.');
    }
    try {
      await AdminLoadGuard.comPrazo(
        FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable(_callable)
            .call<dynamic>({
          'uid': uid,
          'role': firestoreRole,
          'adminLevel': nivel,
          if (nome != null) 'name': nome,
        }),
        prazo: AdminLoadGuard.callable,
        oQue: 'a alteração de papel',
      );
      return;
    } on FirebaseFunctionsException catch (e) {
      if (!_funcaoAusente(e)) rethrow;
    }
    // Função ainda não publicada: grava direto (regras: só master).
    final payload = <String, dynamic>{
      'role': firestoreRole,
      'adminLevel': nivel ?? FieldValue.delete(),
      'adminCapability': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (nome != null) 'name': nome,
    };
    await AdminLoadGuard.comPrazo(
      FirebaseFirestore.instance.collection('users').doc(uid).update(payload),
      oQue: 'a alteração de papel',
    );
    await LogsService().saveLog(
      modulo: 'Admin',
      acao: role == null ? 'Removeu da equipe' : 'Definiu papel na equipe',
      detalhes: '${emailAlvo ?? uid} → '
          '${role == null ? 'Usuário' : TeamRoleConfig.label(role)}',
    );
  }
}
