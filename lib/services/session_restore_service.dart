import 'dart:async';



import 'package:firebase_auth/firebase_auth.dart';



import 'auth_service.dart';

import 'login_preferences.dart';



/// Restaura sessão Firebase no cold start (disco lento ou Google silencioso).

class SessionRestoreService {

  SessionRestoreService._();



  static bool _restoreAttempted = false;



  static Future<User?> tryRestoreIfNeeded() async {

    final sync = FirebaseAuth.instance.currentUser;

    if (sync != null) return sync;



    await LoginPreferences.warmUpForStartup();

    if (LoginPreferences.startupAccountSwitchPending == true) return null;

    if (LoginPreferences.startupReturningUser != true &&

        !await LoginPreferences.hasReturningLoginOnDevice()) {

      return null;

    }



    if (!_restoreAttempted) {

      _restoreAttempted = true;

      // Disco Firebase Auth: tentativas rápidas (Android/iOS cold start).

      for (var i = 0; i < 8; i++) {

        if (i > 0) {

          await Future<void>.delayed(const Duration(milliseconds: 25));

        }

        final u = FirebaseAuth.instance.currentUser;

        if (u != null) return u;

      }



      final provider = await LoginPreferences.getLastOAuthProvider();

      if (provider == 'google') {

        try {

          await AuthService()

              .signInWithGoogleSilently()

              .timeout(const Duration(seconds: 8));

        } catch (_) {}

      }

    }



    return FirebaseAuth.instance.currentUser;

  }



  static void resetAttemptFlag() {

    _restoreAttempted = false;

  }

}


