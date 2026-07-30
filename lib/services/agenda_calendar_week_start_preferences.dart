import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

/// Preferência por usuário para a primeira coluna do calendário da Agenda.
///
/// O padrão é domingo e a escolha fica salva no aparelho e no documento
/// `users/{uid}/settings/planning`, mantendo o mesmo comportamento entre
/// dispositivos.
abstract final class AgendaCalendarWeekStartPreferences {
  static const _uidKey = 'agenda_calendar_week_uid_v1';
  static const _sundayKey = 'agenda_calendar_week_sunday_v1';
  static const fieldName = 'calendarWeekStartsOnSunday';

  static const StartingDayOfWeek defaultValue = StartingDayOfWeek.sunday;

  static Future<StartingDayOfWeek> load(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return defaultValue;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanUid)
          .collection('settings')
          .doc('planning')
          .get(const GetOptions(source: Source.serverAndCache));
      final remote = snapshot.data()?[fieldName];
      if (remote is bool) {
        await _saveLocal(cleanUid, remote);
        return _fromSunday(remote);
      }
    } catch (_) {
      // Sem rede: usa a preferência local.
    }

    final preferences = await SharedPreferences.getInstance();
    final storedUid = (preferences.getString(_uidKey) ?? '').trim();
    if (storedUid.isEmpty || storedUid == cleanUid) {
      final startsOnSunday = preferences.getBool(_sundayKey);
      if (startsOnSunday != null) return _fromSunday(startsOnSunday);
    }
    return defaultValue;
  }

  static Future<void> save(
    String uid, {
    required bool startsOnSunday,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;
    await _saveLocal(cleanUid, startsOnSunday);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanUid)
          .collection('settings')
          .doc('planning')
          .set({
        fieldName: startsOnSunday,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // A preferência local continua válida até a próxima sincronização.
    }
  }

  static StartingDayOfWeek _fromSunday(bool startsOnSunday) =>
      startsOnSunday ? StartingDayOfWeek.sunday : StartingDayOfWeek.monday;

  static Future<void> _saveLocal(String uid, bool startsOnSunday) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_uidKey, uid);
    await preferences.setBool(_sundayKey, startsOnSunday);
  }
}
