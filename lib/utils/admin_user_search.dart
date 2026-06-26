/// Busca de utilizadores no painel admin (lista, 360° e busca global).
library;

/// Nome apresentável — Firestore pode ter `name` ou `displayName`.
String adminUserDisplayName(Map<String, dynamic> data) {
  final name = (data['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  return (data['displayName'] ?? '').toString().trim();
}

String normalizeAdminUserSearch(String s) {
  var t = s.toLowerCase().trim();
  const pairs = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  for (final e in pairs.entries) {
    t = t.replaceAll(e.key, e.value);
  }
  return t;
}

/// Verifica se o documento corresponde ao texto de busca (nome, e-mail, UID, CPF…).
bool adminUserMatchesSearch(
  Map<String, dynamic> data,
  String docId,
  String rawQuery,
) {
  final query = normalizeAdminUserSearch(rawQuery);
  if (query.isEmpty) return true;

  final name = normalizeAdminUserSearch(adminUserDisplayName(data));
  final email = normalizeAdminUserSearch((data['email'] ?? '').toString());
  final cpf =
      (data['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  final cpfMasked =
      normalizeAdminUserSearch((data['cpfMasked'] ?? '').toString());
  final uid = docId.toLowerCase();
  final partnership =
      normalizeAdminUserSearch((data['partnershipName'] ?? '').toString());
  final delegate = normalizeAdminUserSearch(
      (data['authorizedDelegateEmail'] ?? '').toString());
  // Plano (ex.: "premium", "premium_assego") e telefone também ficam pesquisáveis.
  final plan = normalizeAdminUserSearch(
      (data['plan'] ?? data['licensePlan'] ?? '').toString());
  final phone =
      (data['phone'] ?? data['telefone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  final digits = query.replaceAll(RegExp(r'[^0-9]'), '');

  return name.contains(query) ||
      email.contains(query) ||
      uid.contains(query) ||
      partnership.contains(query) ||
      delegate.contains(query) ||
      plan.contains(query) ||
      (digits.length >= 3 && cpf.contains(digits)) ||
      (digits.length >= 3 && phone.contains(digits)) ||
      (cpfMasked.isNotEmpty && cpfMasked.contains(query));
}
