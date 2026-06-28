/// OAuth Google — projeto Firebase `wisdomapp-b9e98` (WISDOMAPP).
class GoogleOAuthConfig {
  GoogleOAuthConfig._();

  /// Cliente Web (tipo 3) — obrigatório no Flutter Web + meta tag em index.html.
  static const String webClientId =
      '766524666378-ce9albkkvn01si77s6ofcqvoaatn29s0.apps.googleusercontent.com';

  /// Cliente iOS (GoogleService-Info.plist).
  static const String iosClientId =
      '766524666378-glgtv4te1i3s4fr67v1t89q57d2hcm9l.apps.googleusercontent.com';

  static const String calendarScope =
      'https://www.googleapis.com/auth/calendar.events';

  /// Domínio canônico do OAuth (redirect fixo — evita redirect_uri_mismatch).
  static const String primaryOrigin = 'https://wisdomapp-b9e98.web.app';

  /// URI de redirect **única** registrada no Google Cloud Console (obrigatória).
  static const String oauthRedirectUri =
      '$primaryOrigin/google_calendar_oauth.html';

  /// Página de início do fluxo OAuth (sempre no domínio canônico).
  static const String oauthStartPage = oauthRedirectUri;

  /// Origens JavaScript autorizadas (Console Google Cloud → cliente OAuth Web).
  static const List<String> authorizedJavaScriptOrigins = [
    primaryOrigin,
    'https://wisdomapp-b9e98.firebaseapp.com',
    'http://localhost',
    'http://localhost:5000',
    'http://localhost:8080',
    'http://127.0.0.1',
    'http://127.0.0.1:5000',
  ];

  /// URIs de redirecionamento autorizados (fluxo OAuth Web redirect).
  static const List<String> authorizedRedirectUris = [
    oauthRedirectUri,
    'https://wisdomapp-b9e98.firebaseapp.com/google_calendar_oauth.html',
    'http://localhost/google_calendar_oauth.html',
    'http://localhost:5000/google_calendar_oauth.html',
    'http://127.0.0.1/google_calendar_oauth.html',
  ];

  /// Resolve redirect para a origem atual (fallback = canônico).
  static String redirectUriForOrigin(String origin) {
    final o = origin.replaceAll(RegExp(r'/+$'), '');
    for (final uri in authorizedRedirectUris) {
      if (uri.startsWith('$o/')) return uri;
    }
    return oauthRedirectUri;
  }

  /// Monta URL absoluta de início OAuth no domínio canônico.
  static String buildOAuthStartUrl(Map<String, String> params) {
    final qs = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$oauthStartPage?$qs';
  }
}
