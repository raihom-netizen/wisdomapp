import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

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

  static void applyWebFirestoreSettings() {
    if (!kIsWeb) return;
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        webExperimentalForceLongPolling: true,
      );
    } catch (e, st) {
      debugPrint('FirestoreWebGuard.applyWebFirestoreSettings: $e\n$st');
    }
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

  /// Recupera estado corrompido do SDK JS (terminate + limpar persistência + long-polling).
  static Future<void> recoverFirestoreWebSession() async {
    if (!kIsWeb) return;
    try {
      await FirebaseFirestore.instance.disableNetwork();
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.terminate();
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.clearPersistence();
    } catch (_) {}
    applyWebFirestoreSettings();
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await stabilizeAfterWebSignIn();
  }

  /// Executa [fn]; em erro interno do Firestore Web, recupera e tenta de novo (1x).
  static Future<T> runWithWebRecovery<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      if (!kIsWeb || !isInternalAssertionError(e)) {
        Error.throwWithStackTrace(e, st);
      }
      debugPrint('FirestoreWebGuard: recuperando sessão Web após assert…');
      await recoverFirestoreWebSession();
      return await fn();
    }
  }

  /// Fluxo completo login Google na Web (popup + perfil Firestore).
  static Future<T> runWebGoogleSignInFlow<T>(Future<T> Function() fn) async {
    if (!kIsWeb) return fn();
    await prepareBeforeWebSignIn();
    try {
      return await runWithWebRecovery(fn);
    } finally {
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
    }
  }
}
