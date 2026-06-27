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

  /// Origens JavaScript autorizadas (Console Google Cloud → cliente OAuth Web).
  static const List<String> authorizedJavaScriptOrigins = [
    'https://wisdomapp-b9e98.web.app',
    'https://wisdomapp-b9e98.firebaseapp.com',
    'http://localhost',
    'http://localhost:5000',
    'http://localhost:8080',
    'http://127.0.0.1',
    'http://127.0.0.1:5000',
  ];

  /// URIs de redirecionamento autorizados (fluxo OAuth Web redirect).
  static const List<String> authorizedRedirectUris = [
    'https://wisdomapp-b9e98.web.app/google_calendar_oauth.html',
    'https://wisdomapp-b9e98.firebaseapp.com/google_calendar_oauth.html',
    'http://localhost/google_calendar_oauth.html',
    'http://localhost:5000/google_calendar_oauth.html',
    'http://127.0.0.1/google_calendar_oauth.html',
  ];
}
