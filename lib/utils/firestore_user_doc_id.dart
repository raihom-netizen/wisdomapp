import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/app_session_cache.dart';
import '../services/delegate_access_service.dart';

/// Sessão Firebase (se existir). Regras do Firestore com `request.auth` exigem leitura só com
/// o mesmo uid — não aceder a `users/{id}/…` com outro [passedFromShell] se isto for null.
String? firestoreSessionUid() => fa.FirebaseAuth.instance.currentUser?.uid;

/// ID do documento `users/{id}/…` só com [fa.FirebaseAuth.instance.currentUser].
/// **Sem fallback** ao uid do widget/shell: evita `permission-denied` na web quando a auth
/// ainda não estabilizou. Retorna `''` — o chamador deve evitar `.get`/streams até haver sessão
/// (ex.: `authStateChanges` + `setState`).
String firestoreUserDocIdStrictFromSession() {
  final s = firestoreSessionUid();
  if (s == null || s.isEmpty) return '';
  final owner = DelegateAccessService.dataOwnerUid;
  if (owner != null && owner.isNotEmpty && owner != s) return owner;
  return s;
}

/// ID do documento `users/{id}/…` alinhado a [request.auth.uid] nas regras do Firestore.
///
/// Com acesso delegado, retorna o UID do titular (dados compartilhados). Caso contrário, sessão.
///
/// Não usar quando o alvo for explicitamente outro utilizador (p. ex. painel admin noutro `uid`).
String firestoreUserDocIdForAppShell(String passedFromShell) {
  final strict = firestoreUserDocIdStrictFromSession();
  if (strict.isNotEmpty) return strict;

  final passed = passedFromShell.trim();
  if (passed.isEmpty) return '';

  // Web: só com sessão ativa (evita permission-denied).
  if (kIsWeb) return '';

  final owner = DelegateAccessService.dataOwnerUid;
  if (owner != null && owner.isNotEmpty) return owner;

  // Android/iOS: reabertura otimista antes do Auth restaurar do disco.
  final cached = AppSessionCache.cachedUidSync();
  if (cached != null && cached.isNotEmpty && cached == passed) return passed;

  return '';
}
