import 'package:firebase_auth/firebase_auth.dart';

/// MASTER do Painel Admin (02/10/2026, pedido do dono): SOMENTE estes dois
/// e-mails, conferidos no login (e-mail verificado). `users.role == 'master'`
/// no Firestore NÃO torna ninguém master — quem tem esse papel sem ser dono
/// vale como «Administrador». O servidor confere o mesmo pelo token
/// (`functions/admin_auth.js`) e as regras (`isDonoPorEmail()`).
class AdminMasterConfig {
  AdminMasterConfig._();

  static const Set<String> kMasterEmails = {
    'raihom@gmail.com',
    'isabelle.krdoso@gmail.com',
  };

  static bool isMasterEmail(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isNotEmpty && kMasterEmails.contains(e);
  }

  /// Usuário logado agora é master (e-mail do login + verificado).
  static bool currentUserIsMaster() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    return u.emailVerified && isMasterEmail(u.email);
  }
}
