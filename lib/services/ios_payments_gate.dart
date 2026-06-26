import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fluxo de pagamento unificado: iOS usa o MESMO checkout in-app do Android/Web
/// (PIX/cartão dentro do app). O redirecionamento ao Safari foi desativado a
/// pedido do produto — ver [paymentsAllowed]. Os helpers de Safari permanecem
/// apenas como fallback caso a política seja revertida no futuro.
class IosPaymentsGate {
  IosPaymentsGate._();

  static bool _initialized = false;

  static bool get isIosNative {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Decisão do produto: iOS usa o MESMO fluxo in-app do Android/Web
  /// (PIX/cartão dentro do app) — não redireciona mais ao Safari.
  /// O checkout in-app fica sempre habilitado em todas as plataformas.
  static bool get paymentsAllowed => true;

  static bool get shouldHidePayments => !paymentsAllowed;

  /// Mantido por compatibilidade com `main.dart`. O checkout in-app está sempre
  /// habilitado (ver [paymentsAllowed]); não há mais decisão por Remote Config.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  /// Site oficial (PWA Flutter web). Hash routing: fragmento `/login?...`.
  static const String publicWebHost = 'wisdomapp-b9e98.web.app';

  /// Login web + pós-login em escolha de plano (PIX/cartão no site).
  static Uri readerIosWebLoginThenEscolhaPlanoUri({
    String utmMedium = 'manage_subscription',
    String? email,
  }) {
    final qp = <String, String>{
      'after': '/escolha-plano',
      'from': 'ios_app',
      'utm_source': 'app_ios',
      'utm_medium': utmMedium,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    final q = Uri(queryParameters: qp).query;
    return Uri(
      scheme: 'https',
      host: publicWebHost,
      fragment: '/login?$q',
    );
  }

  static Future<bool> openReaderPlansInSafari({String source = 'ios_app'}) async {
    final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
    final uri = readerIosWebLoginThenEscolhaPlanoUri(
      utmMedium: source,
      email: email.isEmpty ? null : email,
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Abre planos no app (Android/Web/desktop) ou Safari (iOS Reader).
  static Future<void> pushEscolhaPlano(BuildContext context) async {
    if (shouldHidePayments && isIosNative) {
      await openReaderPlansInSafari(source: 'push_escolha_plano');
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pushNamed('/escolha-plano');
  }
}
