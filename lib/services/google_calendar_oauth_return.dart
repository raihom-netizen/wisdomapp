import 'dart:async';

import 'google_calendar_sync_service.dart';

/// Eventos após retorno OAuth Web (Agenda / toggle escutam para atualizar UI).
class GoogleCalendarOAuthReturn {
  GoogleCalendarOAuthReturn._();

  static final StreamController<GoogleCalendarEnableResult> _controller =
      StreamController<GoogleCalendarEnableResult>.broadcast();

  static Stream<GoogleCalendarEnableResult> get stream => _controller.stream;

  static void notify(GoogleCalendarEnableResult result) {
    if (!_controller.isClosed) {
      _controller.add(result);
    }
  }

  static void notifyError(String code) {
    notify(
      GoogleCalendarEnableResult.fail(
        friendlyOAuthError(code),
      ),
    );
  }

  static String friendlyOAuthError(String code) {
    final c = code.toLowerCase();
    if (c.contains('access_denied') || c.contains('cancel')) {
      return 'Autorização cancelada. Toque no interruptor para tentar de novo.';
    }
    if (c.contains('redirect_uri_mismatch')) {
      return 'Erro de configuração OAuth (redirect). Contacte o suporte.';
    }
    if (c.contains('interaction_required') || c.contains('login_required')) {
      return 'Autorize o Google Calendar uma vez — depois a sync fica automática.';
    }
    return 'Não foi possível conectar ao Google Calendar ($code).';
  }
}
