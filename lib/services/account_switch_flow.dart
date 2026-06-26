import 'package:flutter/material.dart';

import '../screens/landing_screen.dart';
import 'app_session_cache.dart';
import 'auth_service.dart';
import 'delegate_access_service.dart';
import 'login_preferences.dart';
import 'session_restore_service.dart';

/// Único fluxo de «sair / trocar conta»: encerra sessão e abre a landing com login expresso.
class AccountSwitchFlow {
  AccountSwitchFlow._();

  static Future<void> confirmAndOpenLogin(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entrar com outra conta'),
        content: const Text(
          'Encerramos a sessão neste aparelho. '
          'Na tela inicial, use Google ou Apple para entrar com outra conta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trocar conta'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await LoginPreferences.prepareForAccountSwitch(preferEmailForm: false);
      await AppSessionCache.clear();
      await AuthService().signOut(forAccountSwitch: true);
      await DelegateAccessService.clear();
      SessionRestoreService.resetAttemptFlag();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const LandingScreen(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível sair agora: ${e.toString().split('\n').first}',
            ),
          ),
        );
      }
    }
  }
}
