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
}
