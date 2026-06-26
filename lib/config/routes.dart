import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/login_screen.dart';
import '../screens/home_shell.dart';
import '../screens/downloads_screen.dart';

/* * VERSÃO: 1.1.3
 * PROJETO: CONTROLE TOTAL
 * DESCRIÇÃO: Gerenciamento centralizado de rotas para evitar quebras de navegação.
 */

class AppRoutes {
  static const String login = '/';
  static const String home = '/home';
  static const String downloads = '/downloads';

  static Map<String, WidgetBuilder> get routes {
    return {
      login: (context) => const LoginScreen(),
      home: (context) => const _HomeRoute(),
      downloads: (context) => const DownloadsScreen(),
    };
  }

  // Função para navegar com animação premium (opcional)
  static void goToHome(BuildContext context) {
    Navigator.pushReplacementNamed(context, home);
  }
}

class _HomeRoute extends StatelessWidget {
  const _HomeRoute();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginScreen();
    return HomeShell(
      key: ValueKey<String>(user.uid),
      uid: user.uid,
    );
  }
}