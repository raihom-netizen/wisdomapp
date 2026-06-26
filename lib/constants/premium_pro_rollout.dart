/// Controle de exposição do Open Finance / Premium PRO.
/// `requireTesterEmailForOpenFinance`: se true, só e-mails em [_testerEmailsLowercase] veem o fluxo (além de [UserProfile.hasPremiumProEntitlement]).
class PremiumProRollout {
  PremiumProRollout._();

  /// false = qualquer usuário com Premium PRO no Firestore vê bancos e automação (recomendado em produção).
  /// true = só testadores (útil para homologação antes do lançamento).
  static const bool requireTesterEmailForOpenFinance = false;

  static const Set<String> _testerEmailsLowercase = {
    'raihom@gmail.com',
  };

  static bool isTesterEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return _testerEmailsLowercase.contains(email.trim().toLowerCase());
  }
}
