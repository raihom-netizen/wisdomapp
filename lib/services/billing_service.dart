import 'package:cloud_firestore/cloud_firestore.dart';

class BillingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Chamado pelo webhook Mercado Pago ou integração ao confirmar pagamento.
  /// planCode: premium_* = plano premium; premium_pro_* = Premium PRO (quando existir no checkout).
  Future<void> processarPagamento(String userId, String planoSelecionado) async {
    int diasAdicionais = 0;
    String plan = 'premium';
    final p = planoSelecionado.toLowerCase();
    if (p.contains('premium_pro')) {
      plan = 'premium_pro';
      diasAdicionais =
          p.contains('annual') || p.contains('yearly') ? 365 : 30;
    } else if (p.contains('premium_annual') ||
        p.contains('yearly') ||
        p == 'yearly') {
      diasAdicionais = 365;
      plan = 'premium';
    } else if (p.contains('premium') ||
        p.toUpperCase() == 'PRO' ||
        p.contains('monthly') ||
        p.contains('mensal')) {
      diasAdicionais = 30;
      plan = 'premium';
    } else {
      diasAdicionais = 30;
      plan = 'premium';
    }

    final base = DateTime.now().add(Duration(days: diasAdicionais));
    final expirationDate = DateTime(base.year, base.month, base.day, 23, 59, 59);
    final graceEnd = expirationDate.add(const Duration(days: 3));
    // licenseExpiresAt e licenseValidUntilIncludingGrace DEVEM ser Timestamp (não string).
    await _db.collection('users').doc(userId).update({
      'plan': plan,
      'planStatus': 'active',
      'licenseExpiresAt': Timestamp.fromDate(expirationDate),
      'licenseValidUntilIncludingGrace': Timestamp.fromDate(graceEnd),
      'lastPaymentDate': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ADM: prorrogar prazo (teste ou licença) em [dias].
  Future<void> prorrogarPrazo(String userId, int dias) async {
    final doc = await _db.collection('users').doc(userId).get();
    final data = doc.data() ?? {};
    DateTime base = DateTime.now();
    final existing = data['licenseExpiresAt'];
    if (existing is Timestamp) {
      final dt = existing.toDate();
      if (dt.isAfter(DateTime.now())) base = dt;
    }
    final newExp = base.add(Duration(days: dias));
    final endOfDay = DateTime(newExp.year, newExp.month, newExp.day, 23, 59, 59);
    final graceEnd = endOfDay.add(const Duration(days: 3));
    await _db.collection('users').doc(userId).update({
      'licenseExpiresAt': Timestamp.fromDate(endOfDay),
      'licenseValidUntilIncludingGrace': Timestamp.fromDate(graceEnd),
      'planStatus': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ADM: definir usuário como Free (revoga premium).
  Future<void> setUserToFree(String userId) async {
    await _db.collection('users').doc(userId).update({
      'plan': 'free',
      'planStatus': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
      'licenseExpiresAt': FieldValue.delete(),
      'licenseValidUntilIncludingGrace': FieldValue.delete(),
      'partnershipId': FieldValue.delete(),
      'partnershipName': FieldValue.delete(),
    });
  }

  /// ADM: marcar usuário como removido (perde acesso; pode reativar alterando o plano).
  Future<void> removerUsuario(String userId) async {
    await _db.collection('users').doc(userId).update({
      'plan': 'free',
      'planStatus': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
      'licenseExpiresAt': FieldValue.delete(),
      'licenseValidUntilIncludingGrace': FieldValue.delete(),
      'removedByAdminAt': FieldValue.serverTimestamp(),
    });
  }

  /// ADM: excluir usuário permanentemente (deleta o documento; não há como reverter).
  Future<void> excluirUsuario(String userId) async {
    await _db.collection('users').doc(userId).delete();
  }

  /// ADM: reativar usuário removido (limpa o flag de removido).
  Future<void> reativarUsuario(String userId) async {
    await _db.collection('users').doc(userId).update({
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.delete(),
    });
  }
}
