import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Ações que podem ser auditadas no painel admin.
typedef AdminAuditAction = String;

const AdminAuditAction alterarPlano = 'alterar_plano';
const AdminAuditAction alterarPerfil = 'alterar_perfil';
const AdminAuditAction alterarVencimento = 'alterar_vencimento';
const AdminAuditAction prorrogarPrazo = 'prorrogar_prazo';
const AdminAuditAction removerUsuario = 'remover_usuario';
const AdminAuditAction excluirUsuario = 'excluir_usuario';
const AdminAuditAction reativarUsuario = 'reativar_usuario';
const AdminAuditAction alterarSlotsOpenFinance = 'alterar_slots_open_finance';
const AdminAuditAction enviarManutencao = 'enviar_manutencao';
const AdminAuditAction removerManutencao = 'remover_manutencao';
const AdminAuditAction migrarEmailUsuario = 'migrar_email_usuario';

/// Serviço para gravar logs de ações administrativas no Firestore.
class AdminAuditService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Registra uma ação administrativa na coleção admin_audit_log.
  Future<void> logAdminAction({
    required AdminAuditAction action,
    required String targetUserId,
    String? targetUserEmail,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? details,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('admin_audit_log').add({
        'adminId': user.uid,
        'adminEmail': user.email ?? '',
        'action': action,
        'targetUserId': targetUserId,
        'targetUserEmail': targetUserEmail ?? '',
        'details': details ?? '',
        'before': before ?? {},
        'after': after ?? {},
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Log silencioso; não interrompe o fluxo
    }
  }
}
