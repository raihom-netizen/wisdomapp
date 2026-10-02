import 'package:controle_total_premium/models/notification_center_entry.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationCenterEntry _e(NotificationCenterKind k, DateTime? ev) =>
    NotificationCenterEntry(
      id: 'x',
      kind: k,
      source: NotificationCenterSource.agendaAlert,
      title: 't',
      body: 'b',
      eventAt: ev,
    );

void main() {
  final agora = DateTime(2026, 10, 2, 12);

  test('aviso some 24 h depois do evento', () {
    final c = NotificationCenterKind.compromisso;
    expect(_e(c, DateTime(2026, 10, 1, 13)).expirado(agora), isFalse);
    expect(_e(c, DateTime(2026, 10, 1, 11)).expirado(agora), isTrue);
    expect(_e(c, null).expirado(agora), isFalse);
  });

  test('vencimento só com data vale até o fim do dia', () {
    final f = NotificationCenterKind.financeiro;
    expect(_e(f, DateTime(2026, 10, 1)).expirado(agora), isFalse);
    expect(_e(f, DateTime(2026, 9, 30)).expirado(agora), isTrue);
  });

  test('só Financeiro e Compromissos aparecem', () {
    expect(_e(NotificationCenterKind.escala, agora).tipoVisivel, isFalse);
    expect(_e(NotificationCenterKind.audiencia, agora).tipoVisivel, isFalse);
    expect(_e(NotificationCenterKind.financeiro, agora).tipoVisivel, isTrue);
    expect(_e(NotificationCenterKind.compromisso, agora).tipoVisivel, isTrue);
  });
}
