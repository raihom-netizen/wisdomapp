import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../constants/google_oauth_config.dart';
import '../utils/firestore_web_guard.dart';
import 'google_calendar_auth_helper.dart';
import 'google_calendar_oauth_bridge.dart';

/// Evento do Google Calendar exibido na Agenda (editável quando integração ativa).
class GoogleCalendarEventItem {
  const GoogleCalendarEventItem({
    required this.id,
    required this.title,
    required this.day,
    this.timeStart = '',
    this.timeEnd = '',
    this.notes = '',
    this.recurringEventId,
    this.eventType,
  });

  final String id;
  final String title;
  final DateTime day;
  final String timeStart;
  final String timeEnd;
  final String notes;
  /// Id da série recorrente (instâncias expandidas com `singleEvents=true`).
  final String? recurringEventId;
  /// `birthday`, `default`, etc. — aniversários de contatos costumam ser somente leitura.
  final String? eventType;

  bool get isRecurringInstance =>
      recurringEventId != null && recurringEventId!.isNotEmpty;

  bool get isLikelyReadOnlyGoogleEvent =>
      eventType == 'birthday' || eventType == 'fromGmail';

  String get horarioLabel {
    if (timeStart.isEmpty) return 'Dia inteiro';
    if (timeEnd.isNotEmpty) return '$timeStart – $timeEnd';
    return timeStart;
  }
}

class GoogleCalendarEnableResult {
  const GoogleCalendarEnableResult._({
    required this.ok,
    this.email,
    this.message,
    this.cancelled = false,
    this.needsInteractiveAuth = false,
  });

  final bool ok;
  final String? email;
  final String? message;
  final bool cancelled;
  final bool needsInteractiveAuth;

  factory GoogleCalendarEnableResult.success(String email) =>
      GoogleCalendarEnableResult._(ok: true, email: email);

  factory GoogleCalendarEnableResult.fail(String message) =>
      GoogleCalendarEnableResult._(ok: false, message: message);

  factory GoogleCalendarEnableResult.cancelledByUser() =>
      const GoogleCalendarEnableResult._(ok: false, cancelled: true);

  factory GoogleCalendarEnableResult.needsAuth(String? preferredEmail) =>
      GoogleCalendarEnableResult._(
        ok: false,
        needsInteractiveAuth: true,
        email: preferredEmail,
        message: 'Autorize o Google Calendar para continuar.',
      );
}

/// Integração Google Calendar: leitura para colorir dias e escrita ao salvar compromissos.
class GoogleCalendarSyncService {
  GoogleCalendarSyncService._();

  static const calendarScope = GoogleOAuthConfig.calendarScope;
  static const googleEventColor = Color(0xFF4285F4);

  static String? _activeConnectedEmail;

  /// Só importa/sincroniza a partir desta data — evita encher a Agenda com histórico antigo.
  static final DateTime syncMinDate = DateTime(2026, 6, 1);

  static bool isOnOrAfterSyncMin(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(syncMinDate);
  }

  static List<GoogleCalendarEventItem> _filterEventsFromSyncMin(
    List<GoogleCalendarEventItem> events,
  ) {
    return events.where((e) => isOnOrAfterSyncMin(e.day)).toList();
  }

  static DocumentReference<Map<String, dynamic>> _settingsRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('google_calendar_integration');

  static Future<bool> isEnabled(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final snap = await FirestoreWebGuard.runFirestoreOpSafe(
        () => _settingsRef(uid).get(),
      );
      return snap.data()?['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> enabledStream(String uid) {
    if (uid.isEmpty) return Stream<bool>.value(false);
    return _settingsRef(uid)
        .snapshots()
        .map((s) => s.data()?['enabled'] == true);
  }

  static Stream<String?> connectedEmailStream(String uid) {
    if (uid.isEmpty) return Stream<String?>.value(null);
    return _settingsRef(uid).snapshots().map(
          (s) => (s.data()?['connectedEmail'] ?? '').toString().trim().isEmpty
              ? null
              : (s.data()?['connectedEmail'] ?? '').toString().trim(),
        );
  }

  /// Leitura pontual (UI do toggle) — evita `snapshots()` durante OAuth Calendar.
  static Future<({bool enabled, String? email})> readIntegrationState(
    String uid,
  ) async {
    if (uid.isEmpty) return (enabled: false, email: null);
    try {
      final snap = await FirestoreWebGuard.runFirestoreOpSafe(
        () => _settingsRef(uid).get(),
      );
      final data = snap.data() ?? const <String, dynamic>{};
      final emailRaw = (data['connectedEmail'] ?? '').toString().trim();
      return (
        enabled: data['enabled'] == true,
        email: emailRaw.isEmpty ? null : emailRaw,
      );
    } catch (_) {
      return (enabled: false, email: null);
    }
  }

  /// Config pública da landing (hint/cores do card Calendário Google).
  static Future<Map<String, dynamic>> readLandingAgendaConfig() async {
    try {
      final snap = await FirestoreWebGuard.runFirestoreOpSafe(
        () => FirebaseFirestore.instance
            .collection('landing_content')
            .doc('main')
            .get(),
      );
      return snap.data() ?? const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// Ativa: silent-first; popup só se necessário.
  static Future<GoogleCalendarEnableResult> enable(
    String uid, {
    bool forceNewCredentials = false,
    bool skipSilent = false,
  }) async {
    if (uid.isEmpty) {
      return GoogleCalendarEnableResult.fail('Sessão inválida. Entre novamente.');
    }
    return _enableCore(
      uid,
      forceNewCredentials: forceNewCredentials,
      skipSilent: skipSilent,
    );
  }

  /// Reativa só com credencial já salva (toggle ON após desligar).
  static Future<GoogleCalendarEnableResult> tryEnableSilent(String uid) async {
    if (uid.isEmpty) {
      return GoogleCalendarEnableResult.fail('Sessão inválida. Entre novamente.');
    }
    await completeWebOAuthReturnIfNeeded();
    return _enableCore(uid, forceNewCredentials: false, skipSilent: false);
  }

  /// Web: após redirect OAuth, grava token e ativa integração se pendente.
  static Future<void> completeWebOAuthReturnIfNeeded() async {
    if (!kIsWeb) return;

    final gcalError = _readWebOAuthErrorQuery();
    if (gcalError != null) {
      debugPrint('Google Calendar OAuth error: $gcalError');
      GoogleCalendarAuthHelper.clearPendingWebEnableUserDocId();
      return;
    }

    final consumed = await GoogleCalendarAuthHelper.consumeWebOAuthReturn();
    if (!consumed) return;
    final uid = GoogleCalendarAuthHelper.pendingWebEnableUserDocId();
    if (uid == null || uid.isEmpty) return;
    GoogleCalendarAuthHelper.clearPendingWebEnableUserDocId();
    await enable(uid, skipSilent: false);
  }

  static String? _readWebOAuthErrorQuery() {
    if (!kIsWeb) return null;
    final err = Uri.base.queryParameters['gcal_error']?.trim();
    if (err != null && err.isNotEmpty) return err;
    return null;
  }

  /// Renova token silenciosamente se a integração já está ativa (boot / abrir Agenda).
  static Future<bool> warmUpIfEnabled(String uid) async {
    if (uid.isEmpty || !await isEnabled(uid)) return false;
    await completeWebOAuthReturnIfNeeded();
    try {
      final snap = await FirestoreWebGuard.runFirestoreOpSafe(
        () => _settingsRef(uid).get(),
      );
      final e = (snap.data()?['connectedEmail'] ?? '').toString().trim();
      if (e.isNotEmpty) _activeConnectedEmail = e;
    } catch (_) {}

    await GoogleCalendarAuthHelper.bootstrapSession(
      preferredEmail: _activeConnectedEmail,
    );

    final auth = await GoogleCalendarAuthHelper.requestSilent(
      preferredEmail: _activeConnectedEmail,
    );
    if (auth.ok) {
      _activeConnectedEmail = auth.email ?? _activeConnectedEmail;
      return true;
    }
    return false;
  }

  /// Limpa credencial Google Calendar para escolher outra conta Gmail.
  static Future<void> prepareGoogleAccountChange(String uid) async {
    if (uid.isEmpty) return;
    await GoogleCalendarAuthHelper.signOutCalendarSession();
    _activeConnectedEmail = null;
    await disable(uid, keepLocalCredentials: false);
    await FirestoreWebGuard.runFirestoreOpSafe(() async {
      await _settingsRef(uid).set({
        'connectedEmail': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<GoogleCalendarEnableResult> _enableCore(
    String uid, {
    required bool forceNewCredentials,
    required bool skipSilent,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final loginEmail = (firebaseUser?.email ?? '').trim();

    String storedEmail = '';
    try {
      final settingsSnap = await FirestoreWebGuard.runFirestoreOpSafe(
        () => _settingsRef(uid).get(),
      );
      storedEmail =
          (settingsSnap.data()?['connectedEmail'] ?? '').toString().trim();
    } catch (_) {}

    final preferredEmail = storedEmail.isNotEmpty
        ? storedEmail
        : (GoogleCalendarAuthHelper.isApplePrimaryLogin() ? null : loginEmail);
    final emailHint = (preferredEmail == null || preferredEmail.isEmpty)
        ? null
        : preferredEmail;

    try {
      final GoogleCalendarAuthResult auth;
      if (skipSilent || forceNewCredentials) {
        auth = await GoogleCalendarAuthHelper.requestInteractive(
          preferredEmail: forceNewCredentials ? null : emailHint,
          forceNewCredentials: forceNewCredentials,
        );
      } else {
        auth = await GoogleCalendarAuthHelper.requestSilent(
          preferredEmail: emailHint,
        );
        if (!auth.ok) {
          if (auth.needsInteractive) {
            return GoogleCalendarEnableResult.needsAuth(emailHint);
          }
          return GoogleCalendarEnableResult.fail(
            auth.errorMessage ?? 'Não foi possível conectar ao Google Calendar.',
          );
        }
      }

      if (auth.cancelled) {
        return GoogleCalendarEnableResult.cancelledByUser();
      }
      if (!auth.ok) {
        return GoogleCalendarEnableResult.fail(
          auth.errorMessage ?? 'Não foi possível conectar ao Google Calendar.',
        );
      }

      final token = auth.accessToken!;
      if (!await _testCalendarAccess(token)) {
        return GoogleCalendarEnableResult.fail(
          'Sem acesso ao Google Calendar. Verifique se a conta '
          '${auth.email ?? 'Google'} autorizou o WISDOMAPP.',
        );
      }

      final connectedEmail = (auth.email ?? preferredEmail ?? loginEmail).trim();
      _activeConnectedEmail = connectedEmail.isEmpty ? null : connectedEmail;

      await FirestoreWebGuard.prepareForPublishWrite();
      await FirestoreWebGuard.runFirestoreOpSafe(() async {
        await _settingsRef(uid).set({
          'enabled': true,
          'provider': 'google_calendar',
          'connectedEmail': _activeConnectedEmail ?? '',
          'loginProviderApple': GoogleCalendarAuthHelper.isApplePrimaryLogin(),
          'connectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'disabledAt': FieldValue.delete(),
          'disabledByUser': false,
        }, SetOptions(merge: true));
      });

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 600), () async {
          try {
            await FirestoreWebGuard.runFirestoreOpSafe(
              () => syncAllLocalReminders(userDocId: uid),
            );
          } catch (e, st) {
            debugPrint('syncAllLocalReminders após enable: $e\n$st');
          }
        }),
      );

      return GoogleCalendarEnableResult.success(
        _activeConnectedEmail ?? connectedEmail,
      );
    } catch (e, st) {
      debugPrint('GoogleCalendarSyncService.enable: $e\n$st');
      if (FirestoreWebGuard.isClientTerminatedError(e)) {
        return GoogleCalendarEnableResult.fail(
          'Conexão com o banco foi encerrada. Atualize a página (F5) e tente de novo.',
        );
      }
      return GoogleCalendarEnableResult.fail(
        'Erro ao conectar: ${e.toString().split('\n').first}',
      );
    }
  }

  static Future<bool> _testCalendarAccess(String token) async {
    // Usa a mesma API dos eventos (escopo calendar.events) — calendarList exige outro escopo.
    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=1',
    );
    try {
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      debugPrint(
        'GoogleCalendar _testCalendarAccess HTTP ${res.statusCode}: '
        '${res.body.length > 200 ? res.body.substring(0, 200) : res.body}',
      );
      return false;
    } catch (e) {
      debugPrint('GoogleCalendar _testCalendarAccess: $e');
      return false;
    }
  }

  /// Desativa integração — revoga refresh token no servidor (Web) e para sync.
  static Future<void> disable(
    String uid, {
    bool keepLocalCredentials = true,
  }) async {
    if (uid.isEmpty) return;
    _activeConnectedEmail = null;
    await GoogleCalendarAuthHelper.clearCache();
    if (kIsWeb) {
      await GoogleCalendarOAuthBridge.disconnectServerSession();
    } else if (!keepLocalCredentials) {
      await GoogleCalendarAuthHelper.signOutCalendarSession();
    }
    await FirestoreWebGuard.runFirestoreOpSafe(() async {
      await _settingsRef(uid).set({
        'enabled': false,
        'disabledByUser': true,
        'hasRefreshToken': false,
        'disabledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<String?> _accessToken([String? uid]) async {
    if (_activeConnectedEmail == null && uid != null && uid.isNotEmpty) {
      try {
        final snap = await _settingsRef(uid).get();
        final e = (snap.data()?['connectedEmail'] ?? '').toString().trim();
        if (e.isNotEmpty) _activeConnectedEmail = e;
      } catch (_) {}
    }

    final email = _activeConnectedEmail ??
        await GoogleCalendarAuthHelper.storedCalendarEmail();

    final auth = await GoogleCalendarAuthHelper.requestSilent(
      preferredEmail: email,
    );
    if (auth.ok) {
      _activeConnectedEmail = auth.email ?? _activeConnectedEmail;
      return auth.accessToken;
    }
    return null;
  }

  static Future<http.Response> _authorizedRequest(
    Future<http.Response> Function(String token) request, {
    String? userDocId,
  }) async {
    var token = await _accessToken(userDocId);
    if (token == null) {
      return http.Response('', 401);
    }
    var res = await request(token);
    if (res.statusCode == 401) {
      final refreshed = await GoogleCalendarAuthHelper.refreshAfterUnauthorized(
        preferredEmail: _activeConnectedEmail,
      );
      token = refreshed.accessToken;
      if (token != null && token.isNotEmpty) {
        _activeConnectedEmail = refreshed.email ?? _activeConnectedEmail;
        res = await request(token);
      }
    }
    return res;
  }

  static Future<http.Response> _authorizedGet(Uri uri, {String? userDocId}) async {
    return _authorizedRequest(
      (token) => http.get(uri, headers: {'Authorization': 'Bearer $token'}),
      userDocId: userDocId,
    );
  }

  static DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<GoogleCalendarEventItem> _parseEventsResponse(
    Map<String, dynamic> body,
  ) {
    final items = (body['items'] as List<dynamic>?) ?? [];
    final out = <GoogleCalendarEventItem>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final id = (raw['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final title = (raw['summary'] ?? 'Evento Google').toString();
      final notes = (raw['description'] ?? '').toString();
      final startObj = raw['start'] as Map<String, dynamic>?;
      if (startObj == null) continue;

      DateTime? day;
      String timeStart = '';
      String timeEnd = '';
      final endObj = raw['end'] as Map<String, dynamic>?;

      if (startObj['date'] != null) {
        final p = DateTime.tryParse(startObj['date'].toString());
        if (p != null) day = _dayKey(p);
      } else if (startObj['dateTime'] != null) {
        final p = DateTime.tryParse(startObj['dateTime'].toString());
        if (p != null) {
          day = _dayKey(p);
          timeStart = DateFormat('HH:mm').format(p.toLocal());
        }
      }
      if (endObj != null && endObj['dateTime'] != null) {
        final p = DateTime.tryParse(endObj['dateTime'].toString());
        if (p != null) timeEnd = DateFormat('HH:mm').format(p.toLocal());
      }
      if (day == null) continue;

      out.add(
        GoogleCalendarEventItem(
          id: id,
          title: title,
          day: day,
          timeStart: timeStart,
          timeEnd: timeEnd,
          notes: notes,
          recurringEventId: (raw['recurringEventId'] ?? '').toString().trim().isEmpty
              ? null
              : (raw['recurringEventId'] ?? '').toString().trim(),
          eventType: (raw['eventType'] ?? 'default').toString().trim(),
        ),
      );
    }
    return out;
  }

  /// Eventos do mês (primary calendar), apenas a partir de [syncMinDate] (jun/2026+).
  static Future<List<GoogleCalendarEventItem>> fetchEventsForMonth(
    DateTime month, {
    String? userDocId,
  }) async {
    final monthEnd = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    if (monthEnd.isBefore(syncMinDate)) return [];

    final monthStart = DateTime(month.year, month.month, 1);
    final start = monthStart.isBefore(syncMinDate) ? syncMinDate : monthStart;
    final end = monthEnd;
    final fmt = DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events'
      '?singleEvents=true'
      '&orderBy=startTime'
      '&timeMin=${Uri.encodeComponent(fmt.format(start.toUtc()))}'
      '&timeMax=${Uri.encodeComponent(fmt.format(end.toUtc()))}',
    );

    try {
      final res = await _authorizedGet(uri, userDocId: userDocId)
          .timeout(const Duration(seconds: 25));
      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final events = _filterEventsFromSyncMin(_parseEventsResponse(body));
      if (userDocId == null || userDocId.isEmpty) return events;
      final hidden = await _loadHiddenGoogleEventKeys(userDocId);
      return events.where((e) => !_isGoogleEventHidden(e, hidden)).toList();
    } catch (e) {
      debugPrint('fetchEventsForMonth: $e');
      return [];
    }
  }

  static Future<Set<String>> _loadHiddenGoogleEventKeys(String uid) async {
    if (uid.isEmpty) return {};
    try {
      final snap = await FirestoreWebGuard.runFirestoreOpSafe(
        () => _settingsRef(uid).get(),
      );
      final raw = snap.data()?['hiddenGoogleEventKeys'];
      if (raw is! List) return {};
      return raw.map((e) => e.toString().trim()).where((k) => k.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  static bool _isGoogleEventHidden(
    GoogleCalendarEventItem event,
    Set<String> hidden,
  ) {
    if (hidden.contains(event.id)) return true;
    final recurring = event.recurringEventId;
    if (recurring != null && recurring.isNotEmpty && hidden.contains(recurring)) {
      return true;
    }
    final inferred = _inferRecurringEventId(event.id);
    if (inferred != null && hidden.contains(inferred)) return true;
    return false;
  }

  /// Instâncias expandidas: `{recurringEventId}_{YYYYMMDD}` ou `…T…Z`.
  static String? _inferRecurringEventId(String instanceId) {
    final m = RegExp(r'^(.+)_(\d{8}(T\d{6}Z)?)$').firstMatch(instanceId.trim());
    return m?.group(1)?.trim().isEmpty == true ? null : m?.group(1)?.trim();
  }

  /// Oculta evento Google da Agenda WISDOMAPP (mesmo se a API bloquear exclusão).
  static Future<void> hideGoogleEventFromAgenda({
    required String userDocId,
    required String eventId,
    String? recurringEventId,
  }) async {
    if (userDocId.isEmpty || eventId.trim().isEmpty) return;
    final keys = <String>{eventId.trim()};
    final recurring = (recurringEventId ?? '').trim();
    if (recurring.isNotEmpty) keys.add(recurring);
    final inferred = _inferRecurringEventId(eventId);
    if (inferred != null && inferred.isNotEmpty) keys.add(inferred);

    await FirestoreWebGuard.runFirestoreOpSafe(() async {
      await _settingsRef(userDocId).set({
        'hiddenGoogleEventKeys': FieldValue.arrayUnion(keys.toList()),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static bool _deleteHttpOk(int status) =>
      status == 200 || status == 204 || status == 410 || status == 404;

  static Future<bool> _deleteGoogleEventHttp({
    required String userDocId,
    required String eventId,
  }) async {
    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events/${Uri.encodeComponent(eventId)}',
    );
    final res = await _authorizedRequest(
      (token) => http.delete(uri, headers: {'Authorization': 'Bearer $token'}),
      userDocId: userDocId,
    );
    if (!_deleteHttpOk(res.statusCode)) {
      debugPrint(
        'DELETE google event $eventId → HTTP ${res.statusCode}: '
        '${res.body.length > 280 ? res.body.substring(0, 280) : res.body}',
      );
    }
    return _deleteHttpOk(res.statusCode);
  }

  static Future<bool> _cancelGoogleEventHttp({
    required String userDocId,
    required String eventId,
  }) async {
    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events/${Uri.encodeComponent(eventId)}',
    );
    final res = await _authorizedRequest(
      (token) => http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': 'cancelled'}),
      ),
      userDocId: userDocId,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint(
        'PATCH cancel google event $eventId → HTTP ${res.statusCode}: '
        '${res.body.length > 280 ? res.body.substring(0, 280) : res.body}',
      );
      return false;
    }
    return true;
  }

  /// Dias do mês visível que possuem eventos no Google Calendar (primary).
  static Future<Set<DateTime>> fetchBusyDaysForMonth(DateTime month) async {
    final events = await fetchEventsForMonth(month);
    return events.map((e) => e.day).toSet();
  }

  static Map<DateTime, List<GoogleCalendarEventItem>> groupEventsByDay(
    List<GoogleCalendarEventItem> events,
  ) {
    final map = <DateTime, List<GoogleCalendarEventItem>>{};
    for (final e in events) {
      map.putIfAbsent(e.day, () => []).add(e);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.timeStart.compareTo(b.timeStart));
    }
    return map;
  }

  /// Eventos Google do dia que ainda não estão espelhados em `reminders.googleEventId`.
  static List<GoogleCalendarEventItem> externalEventsForDay({
    required DateTime day,
    required List<GoogleCalendarEventItem> googleEvents,
    required Set<String> linkedGoogleEventIds,
  }) {
    final key = _dayKey(day);
    return googleEvents
        .where((e) => _dayKey(e.day) == key && !linkedGoogleEventIds.contains(e.id))
        .toList();
  }

  static String _isoLocal(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final dt = DateTime(date.year, date.month, date.day, h, m);
    final off = dt.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final oh = off.inHours.abs().toString().padLeft(2, '0');
    final om = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(dt)}$sign$oh:$om';
  }

  /// Envia todos os compromissos locais sem `googleEventId` para o Google Calendar.
  static Future<int> syncAllLocalReminders({required String userDocId}) async {
    if (userDocId.isEmpty || !await isEnabled(userDocId)) return 0;
    final snap = await FirestoreWebGuard.runFirestoreOpSafe(
      () => FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('reminders')
          .get(),
    );
    var n = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final type = (data['type'] ?? 'compromisso').toString().toLowerCase();
      if (type != 'compromisso') continue;
      final existing = (data['googleEventId'] ?? '').toString().trim();
      if (existing.isNotEmpty) continue;
      final dateRaw = data['date'];
      DateTime? date;
      if (dateRaw is Timestamp) date = dateRaw.toDate();
      if (date == null || !isOnOrAfterSyncMin(date)) continue;
      await syncReminderToGoogle(
        userDocId: userDocId,
        reminderDocId: doc.id,
        title: (data['title'] ?? 'Compromisso').toString(),
        notes: (data['notes'] ?? '').toString(),
        date: date,
        timeHHmm: (data['time'] ?? '09:00').toString(),
        endTimeHHmm: (data['endTime'] ?? '10:00').toString(),
      );
      n++;
    }
    return n;
  }

  static const _googleImportColorHex = '#4285F4';

  /// Google Calendar → Agenda: cria reminders locais para eventos ainda não vinculados.
  static Future<int> importExternalGoogleEvents({
    required String userDocId,
    required List<GoogleCalendarEventItem> events,
  }) async {
    if (userDocId.isEmpty || !await isEnabled(userDocId)) return 0;

    var imported = 0;
    for (final event in events) {
      if (event.isLikelyReadOnlyGoogleEvent) continue;
      if (!isOnOrAfterSyncMin(event.day)) continue;

      final eventId = event.id.trim();
      if (eventId.isEmpty) continue;

      try {
        final linked = await FirestoreWebGuard.runFirestoreOpSafe(
          () => FirebaseFirestore.instance
              .collection('users')
              .doc(userDocId)
              .collection('reminders')
              .where('googleEventId', isEqualTo: eventId)
              .limit(1)
              .get(),
        );
        if (linked.docs.isNotEmpty) continue;

        final day = _dayKey(event.day);
        final start = event.timeStart.trim().isEmpty ? '09:00' : event.timeStart.trim();
        final end = event.timeEnd.trim().isEmpty
            ? _defaultEndFromStart(start)
            : event.timeEnd.trim();

        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .collection('reminders')
            .doc();

        await FirestoreWebGuard.runFirestoreOpSafe(() async {
          await ref.set({
            'type': 'compromisso',
            'agendaKind': 'compromisso_particular',
            'title': event.title.trim().isEmpty ? 'Evento Google' : event.title.trim(),
            'notes': event.notes.trim(),
            'date': Timestamp.fromDate(day),
            'time': start,
            'endTime': end,
            'colorHex': _googleImportColorHex,
            'status': 'EM_ABERTO',
            'done': false,
            'googleEventId': eventId,
            'googleSyncedAt': FieldValue.serverTimestamp(),
            'source': 'google_calendar_import',
            'createdAt': FieldValue.serverTimestamp(),
            'agendaLoginDaySyncAt': FieldValue.serverTimestamp(),
          });
        });

        imported++;
      } catch (e) {
        debugPrint('importExternalGoogleEvents $eventId: $e');
      }
    }
    return imported;
  }

  static String _defaultEndFromStart(String startHHmm) {
    final parts = startHHmm.split(':');
    final h = int.tryParse(parts.first) ?? 9;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final end = DateTime(2000, 1, 1, h, m).add(const Duration(hours: 1));
    return '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  }

  /// Sincronização bidirecional: envia locais pendentes + importa novos do Google.
  static Future<({int pushed, int pulled})> syncBidirectional({
    required String userDocId,
    required List<GoogleCalendarEventItem> googleEvents,
  }) async {
    if (userDocId.isEmpty || !await isEnabled(userDocId)) {
      return (pushed: 0, pulled: 0);
    }
    await warmUpIfEnabled(userDocId);
    final pushed = await syncAllLocalReminders(userDocId: userDocId);
    final pulled = await importExternalGoogleEvents(
      userDocId: userDocId,
      events: googleEvents,
    );
    return (pushed: pushed, pulled: pulled);
  }

  /// Cria/atualiza evento no Google Calendar e grava `googleEventId` no reminder.
  /// Retorna `true` se o Google confirmou o evento.
  static Future<bool> syncReminderToGoogle({
    required String userDocId,
    required String reminderDocId,
    required String title,
    required String notes,
    required DateTime date,
    required String timeHHmm,
    required String endTimeHHmm,
  }) async {
    if (userDocId.isEmpty || reminderDocId.isEmpty) return false;
    if (!await isEnabled(userDocId)) return false;
    if (!isOnOrAfterSyncMin(date)) return false;

    final payload = _eventPayload(
      title: title,
      notes: notes,
      date: date,
      timeHHmm: timeHHmm,
      endTimeHHmm: endTimeHHmm,
    );

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocId)
        .collection('reminders')
        .doc(reminderDocId);

    DocumentSnapshot<Map<String, dynamic>> existing;
    try {
      existing = await FirestoreWebGuard.runFirestoreOpSafe(() => ref.get());
    } catch (e) {
      debugPrint('syncReminderToGoogle read reminder: $e');
      return false;
    }

    final oldEventId = (existing.data()?['googleEventId'] ?? '').toString().trim();

    final uri = oldEventId.isNotEmpty
        ? Uri.parse(
            'https://www.googleapis.com/calendar/v3/calendars/primary/events/${Uri.encodeComponent(oldEventId)}',
          )
        : Uri.parse(
            'https://www.googleapis.com/calendar/v3/calendars/primary/events',
          );

    final res = await _authorizedRequest(
      (token) => oldEventId.isNotEmpty
          ? http.put(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
          : http.post(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            ),
      userDocId: userDocId,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('syncReminderToGoogle HTTP ${res.statusCode}: ${res.body}');
      return false;
    }

    try {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final eventId = (decoded['id'] ?? '').toString();
      if (eventId.isEmpty) return false;

      await FirestoreWebGuard.runFirestoreOpSafe(() async {
        await ref.set({
          'googleEventId': eventId,
          'googleSyncedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      return true;
    } catch (e) {
      debugPrint('syncReminderToGoogle persist googleEventId: $e');
      return false;
    }
  }

  static Map<String, dynamic> _eventPayload({
    required String title,
    required String notes,
    required DateTime date,
    required String timeHHmm,
    required String endTimeHHmm,
  }) {
    final allDay = timeHHmm.trim().isEmpty;
    if (allDay) {
      final dayStr = DateFormat('yyyy-MM-dd').format(date);
      final nextDay = date.add(const Duration(days: 1));
      return {
        'summary': title,
        'description': notes.isEmpty ? 'Compromisso WISDOMAPP' : notes,
        'start': {'date': dayStr},
        'end': {'date': DateFormat('yyyy-MM-dd').format(nextDay)},
        'colorId': '7',
      };
    }
    return {
      'summary': title,
      'description': notes.isEmpty ? 'Compromisso WISDOMAPP' : notes,
      'start': {
        'dateTime': _isoLocal(date, timeHHmm),
        'timeZone': 'America/Sao_Paulo',
      },
      'end': {
        'dateTime': _isoLocal(date, endTimeHHmm),
        'timeZone': 'America/Sao_Paulo',
      },
      'colorId': '7',
    };
  }

  /// Atualiza evento existente no Google Calendar pelo id do evento.
  static Future<bool> updateGoogleEventById({
    required String userDocId,
    required String eventId,
    required String title,
    required String notes,
    required DateTime date,
    required String timeHHmm,
    required String endTimeHHmm,
  }) async {
    if (userDocId.isEmpty || eventId.trim().isEmpty) return false;
    if (!await isEnabled(userDocId)) return false;
    if (!isOnOrAfterSyncMin(date)) return false;

    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events/${Uri.encodeComponent(eventId)}',
    );
    final payload = _eventPayload(
      title: title,
      notes: notes,
      date: date,
      timeHHmm: timeHHmm,
      endTimeHHmm: endTimeHHmm,
    );

    try {
      final res = await _authorizedRequest(
        (token) => http.put(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        ),
        userDocId: userDocId,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('updateGoogleEventById HTTP ${res.statusCode}: ${res.body}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('updateGoogleEventById: $e');
      return false;
    }
  }

  /// Remove evento do Google Calendar (instância, série recorrente ou cancelamento).
  static Future<bool> deleteGoogleEventById({
    required String userDocId,
    required String eventId,
    String? recurringEventId,
    bool tryDeleteEntireSeries = true,
  }) async {
    if (userDocId.isEmpty || eventId.trim().isEmpty) return false;
    if (!await isEnabled(userDocId)) return false;

    final id = eventId.trim();
    final seriesId = (recurringEventId ?? '').trim().isNotEmpty
        ? recurringEventId!.trim()
        : _inferRecurringEventId(id);

    try {
      if (await _deleteGoogleEventHttp(userDocId: userDocId, eventId: id)) {
        return true;
      }
      if (await _cancelGoogleEventHttp(userDocId: userDocId, eventId: id)) {
        return true;
      }
      if (tryDeleteEntireSeries &&
          seriesId != null &&
          seriesId.isNotEmpty &&
          seriesId != id) {
        if (await _deleteGoogleEventHttp(userDocId: userDocId, eventId: seriesId)) {
          return true;
        }
        if (await _cancelGoogleEventHttp(userDocId: userDocId, eventId: seriesId)) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('deleteGoogleEventById: $e');
      return false;
    }
  }

  /// Exclui no Google (se possível) e **sempre** oculta na Agenda WISDOMAPP.
  static Future<bool> removeGoogleEventFromAgenda({
    required String userDocId,
    required String eventId,
    String? recurringEventId,
    bool tryDeleteEntireSeries = true,
  }) async {
    final deleted = await deleteGoogleEventById(
      userDocId: userDocId,
      eventId: eventId,
      recurringEventId: recurringEventId,
      tryDeleteEntireSeries: tryDeleteEntireSeries,
    );
    await hideGoogleEventFromAgenda(
      userDocId: userDocId,
      eventId: eventId,
      recurringEventId: recurringEventId,
    );
    return deleted;
  }

  static Future<void> deleteGoogleEventForReminder({
    required String userDocId,
    required String reminderDocId,
    String? googleEventId,
    String? recurringEventId,
    bool tryDeleteEntireSeries = true,
  }) async {
    if (userDocId.isEmpty) return;
    var eventId = (googleEventId ?? '').trim();
    if (eventId.isEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('reminders')
          .doc(reminderDocId)
          .get();
      eventId = (snap.data()?['googleEventId'] ?? '').toString().trim();
    }
    if (eventId.isEmpty) return;
    await removeGoogleEventFromAgenda(
      userDocId: userDocId,
      eventId: eventId,
      recurringEventId: recurringEventId,
      tryDeleteEntireSeries: tryDeleteEntireSeries,
    );
  }
}
