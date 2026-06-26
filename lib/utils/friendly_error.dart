/// Converte exceções técnicas em mensagens amigáveis para o usuário.
String friendlyMessage(Object error, {String? context}) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('google_web_client_id_not_configured')) {
    return 'Entrar com Google: configure o Web Client ID no Firebase. Clique em "Entrar com Google" de novo para ver as instruções.';
  }
  if (msg.contains('network') || msg.contains('socket') || msg.contains('connection') || msg.contains('unavailable')) {
    return 'Sem conexão. Verifique a internet e tente novamente.';
  }
  if (msg.contains('out of memory') || msg.contains('out_of_memory')) {
    return 'Memória insuficiente para gerar este PDF. Use período menor, modo compacto (balanceta) ou menos filtros.';
  }
  if (msg.contains('permission-denied') || msg.contains('permission_denied')) {
    return 'Você não tem permissão para esta ação.';
  }
  if (msg.contains('unauthenticated') || msg.contains('user-not-found') || msg.contains('wrong-password') ||
      msg.contains('not-found') || msg.contains('cpf não cadastrado')) {
    return 'E-mail/CPF ou senha incorretos. Tente novamente.';
  }
  if (msg.contains('email-already-in-use') || msg.contains('email_already_in_use')) {
    return 'Este e-mail já está em uso. Faça login ou use outro e-mail.';
  }
  if (msg.contains('weak-password') || msg.contains('invalid-email')) {
    return 'Dados inválidos. Use um e-mail válido e senha com no mínimo 6 caracteres.';
  }
  if (msg.contains('internal') || msg.contains('firebase_functions')) {
    if (context != null) return context;
    return 'Serviço temporariamente indisponível. Tente em alguns instantes.';
  }
  if (msg.contains('timeout') || msg.contains('deadline')) {
    return 'A operação demorou demais. Tente novamente.';
  }
  if (msg.contains('cancel') || msg.contains('cancelled') || msg.contains('canceled')) {
    return 'Operação cancelada.';
  }
  if (msg.contains('invalid-credential') || msg.contains('invalid_credential') || msg.contains('account-exists-with-different-credential')) {
    return 'Credenciais inválidas ou conta já existe com outro método de login.';
  }
  if (msg.contains('user-disabled')) {
    return 'Esta conta foi desativada. Entre em contato com o suporte.';
  }
  if (msg.contains('operation-not-allowed') || (msg.contains('provider') && msg.contains('disabled'))) {
    return 'Login com este provedor não está ativo. Ative no Firebase Console > Authentication.';
  }
  if (msg.contains('not available') || msg.contains('not supported') || msg.contains('platform')) {
    return 'Login não disponível nesta plataforma.';
  }
  if (msg.contains('missingpluginexception') || msg.contains('no implementation found')) {
    return 'Login com Google na web: ative o provedor Google no Firebase (Authentication > Sign-in method) e configure o Web Client ID (veja instruções ao clicar em "Entrar com Google").';
  }
  if (msg.contains('popup_blocked') || msg.contains('popup') && msg.contains('closed')) {
    return 'A janela do Google foi bloqueada ou fechada. Permita pop-ups para este site e tente de novo.';
  }
  if (msg.length > 120) {
    return 'Algo deu errado. Tente novamente ou entre em contato com o suporte.';
  }
  return msg;
}
