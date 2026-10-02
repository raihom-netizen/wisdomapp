import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'firestore_web_fatal_stub.dart'
    if (dart.library.js_interop) 'firestore_web_fatal_web.dart';

/// Blindagem Web: `INTERNAL ASSERTION FAILED` / `WatchChangeAggregator` ao trocar
/// sessão Auth (login Google) com listeners `snapshots()` ativos + cache IndexedDB.
class FirestoreWebGuard {
  FirestoreWebGuard._();

  static bool isInternalAssertionError(Object e) {
    final msg = e.toString();
    return msg.contains('INTERNAL ASSERTION') ||
        msg.contains('Unexpected state') ||
        msg.contains('WatchChangeAggregator') ||
        msg.contains('PersistentListenStream') ||
        msg.contains('__PRIVATE__TargetState');
  }

  /// Web: depois do `INTERNAL ASSERTION FAILED` (ca9/b815) a fila interna do
  /// SDK JS falha para sempre — nenhuma escuta ou gravação volta sem recarregar
  /// a página. Mostra o aviso «Conexão com o banco reiniciando…» e recarrega 1x
  /// (proteção contra loop em `web/index.html`). Devolve `true` se era esse erro.
  static bool reportIfFatalWebError(Object? e) {
    if (!kIsWeb || e == null) return false;
    if (!isInternalAssertionError(e)) return false;
    final msg = e.toString();
    if (!msg.contains('INTERNAL ASSERTION')) return false;
    debugPrint(
        'FirestoreWebGuard: assert fatal do SDK JS — recarregando: $msg');
    reportFirestoreWebFatal(msg);
    return true;
  }

  /// Erros do SDK Web que exigem `terminate()` + nova tentativa (não chamar recovery antes da operação).
  static bool isRecoverableFirestoreWebError(Object e) {
    if (isInternalAssertionError(e)) return true;
    final msg = e.toString().toLowerCase();
    if (msg.contains('client has already been terminated') ||
        msg.contains('already been terminated')) {
      return true;
    }
    if (e is FirebaseException &&
        e.code == 'failed-precondition' &&
        msg.contains('terminated')) {
      return true;
    }
    return false;
  }

  static void applyWebFirestoreSettings() {
    if (!kIsWeb) return;
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        // 02/10/2026: long-polling FORÇADO é gatilho conhecido do assert ca9/b815
        // (firebase-js-sdk #10310) mesmo no SDK 12.x — auto-detecção usa o
        // WebChannel normal e só cai p/ long-polling quando a rede exige.
        webExperimentalForceLongPolling: false,
        webExperimentalAutoDetectLongPolling: true,
      );
    } catch (e, st) {
      debugPrint('FirestoreWebGuard.applyWebFirestoreSettings: $e\n$st');
    }
  }

  static bool isClientTerminatedError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('already been terminated') ||
        msg.contains('client has already been terminated')) {
      return true;
    }
    if (e is FirebaseException &&
        e.code == 'failed-precondition' &&
        msg.contains('terminated')) {
      return true;
    }
    return false;
  }

  /// Leituras/gravações pontuais (Calendar, settings): **nunca** `terminate()`.
  static Future<T> runFirestoreOpSafe<T>(
    Future<T> Function() fn, {
    int maxAttempts = 5,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (e, st) {
        if (isClientTerminatedError(e) || reportIfFatalWebError(e)) {
          Error.throwWithStackTrace(e, st);
        }
        final retry = attempt < maxAttempts - 1 &&
            (isInternalAssertionError(e) ||
                (e is FirebaseException &&
                    const {
                      'unavailable',
                      'deadline-exceeded',
                      'aborted',
                      'resource-exhausted',
                    }.contains(e.code)));
        if (!retry) {
          Error.throwWithStackTrace(e, st);
        }
        if (kIsWeb) {
          try {
            await FirebaseFirestore.instance.enableNetwork();
          } catch (_) {}
        }
        await Future<void>.delayed(Duration(milliseconds: 180 * (attempt + 1)));
      }
    }
    throw StateError('runFirestoreOpSafe: exhausted attempts');
  }

  /// Antes de gravar (Calendar OAuth): alinha Auth token sem desligar Firestore.
  static Future<void> prepareForPublishWrite() async {
    if (!kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.getIdToken(false);
      } catch (_) {}
    }
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
  }

  /// Antes do popup Google: reduz corrida com listeners públicos (landing/divulgação).
  static Future<void> prepareBeforeWebSignIn() async {
    if (!kIsWeb) return;
    try {
      await FirebaseFirestore.instance.disableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 48));
  }

  /// Após Auth OK: token alinhado antes de leituras/gravações em `users/{uid}`.
  static Future<void> stabilizeAfterWebSignIn() async {
    if (!kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.getIdToken(true);
      } catch (_) {}
      try {
        await user.reload();
      } catch (_) {}
    }
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 140));
  }

  /// Recupera o canal de escuta do SDK JS **sem** `terminate()`.
  ///
  /// 02/10/2026: antes fazia `terminate()` + `clearPersistence()`. No
  /// cloud_firestore_web a instância JS fica guardada (`_webFirestore`), então
  /// depois do `terminate()` TODAS as escutas morriam e qualquer leitura nova
  /// dava «client has already been terminated» até recarregar a página (ex.:
  /// sair e entrar de novo sem F5 → telas girando para sempre). Na Web o cache
  /// é só em memória (`persistenceEnabled: false`), então `clearPersistence()`
  /// não tinha o que limpar. Também NÃO desliga/religa a rede: perder/voltar a
  /// rede com escutas abertas é um dos gatilhos do assert ca9 do SDK JS
  /// (firebase-js-sdk #9172). Só garante rede ligada + token alinhado; se o
  /// SDK já tiver dado o assert fatal, [reportIfFatalWebError] recarrega.
  static Future<void> recoverFirestoreWebSession() async {
    if (!kIsWeb) return;
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await stabilizeAfterWebSignIn();
  }

  /// Executa [fn]; em erro recuperável do Firestore Web, recupera e tenta de novo (1x).
  /// Não chama `terminate()` se o cliente já foi encerrado (evita loop fatal).
  static Future<T> runWithWebRecovery<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      if (!kIsWeb || !isRecoverableFirestoreWebError(e)) {
        Error.throwWithStackTrace(e, st);
      }
      if (reportIfFatalWebError(e)) {
        Error.throwWithStackTrace(e, st);
      }
      if (isClientTerminatedError(e)) {
        Error.throwWithStackTrace(e, st);
      }
      debugPrint('FirestoreWebGuard: recuperando sessão Web após erro…');
      await recoverFirestoreWebSession();
      return await fn();
    }
  }

  static bool _googleSignInFlowActive = false;

  /// Fluxo completo login Google na Web (popup + perfil Firestore).
  static Future<T> runWebGoogleSignInFlow<T>(Future<T> Function() fn) async {
    if (!kIsWeb) return fn();
    if (_googleSignInFlowActive) {
      return fn();
    }
    _googleSignInFlowActive = true;
    await prepareBeforeWebSignIn();
    try {
      final result = await runWithWebRecovery(fn);
      await stabilizeAfterWebSignIn();
      return result;
    } finally {
      _googleSignInFlowActive = false;
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await stabilizeAfterWebSignIn();
    }
  }
}
