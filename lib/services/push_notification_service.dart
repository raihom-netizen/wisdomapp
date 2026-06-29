import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';

import '../utils/url_launcher_helper.dart';
import '../utils/admin_user_search.dart';
import '../utils/firestore_user_doc_id.dart';
import 'in_app_floating_message_service.dart';
import 'fcm_local_notification_presenter.dart';
import 'notification_audio_player.dart';
import 'notification_message_builder.dart';
import 'notification_module_theme.dart';
import 'notification_sound_preferences.dart';
import 'scale_notifications_service.dart';

/// VAPID KEY para Push Web (PWA no celular ou navegador).
/// Firebase Console → Project Settings → Cloud Messaging → Web configuration → Web Push certificates → Generate key pair → copiar chave pública.
/// Ver também: docs/ESTRATEGIA_ESCALA_15K_PUSH_EMAIL.md
const String kFcmVapidKeyWeb = 'COLE_AQUI_SUA_VAPID_KEY';

/// Chave do ScaffoldMessenger raiz para mostrar notificações na tela quando o app está em primeiro plano.
GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

/// Evita registrar os mesmos listeners de FCM mais de uma vez (ex.: novo HomeShell após navegação).
bool _pushMessagingListenersAttached = false;
bool _pushTokenRefreshListenerAttached = false;
bool _pushInitialized = false;
Future<void>? _pushInitFuture;
StreamSubscription<User?>? _pushAuthTokenSub;
Timer? _pushTokenRetryTimer;
int _pushTokenRetryCount = 0;
DateTime? _lastTokenWriteAt;
String? _lastTokenWriteUid;
String? _lastTokenWriteToken;

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Define a chave do ScaffoldMessenger raiz (chamar do main.dart) para exibir mensagens na tela em foreground.
  static void setScaffoldMessengerKey(GlobalKey<ScaffoldMessengerState>? key) {
    _scaffoldMessengerKey = key;
  }

  static bool _isNativeMobile() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  static bool _permissionAllowsPush(NotificationSettings settings) {
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// URL em [message.data] (promo, manutenção, broadcast, lembretes). Caminhos relativos viram site oficial.
  static String? linkFromRemoteMessage(RemoteMessage message) {
    final d = message.data;
    final raw = (d['url'] ?? d['link'] ?? d['linkUrl'] ?? d['openUrl'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) {
      return Uri.https('wisdomapp-b9e98.web.app', raw).toString();
    }
    return null;
  }

  static Future<void> openNotificationLinkIfPresent(RemoteMessage message) async {
    final url = linkFromRemoteMessage(message);
    if (url == null || url.isEmpty) return;
    try {
      await openPromoMaintenanceLink(url);
    } catch (_) {}
  }

  /// Exibe notificação na tela (SnackBar) quando push chega com app aberto (avisos na tela).
  static void showMessageOnScreen(String? title, String? body) {
    final t = (title ?? '').toString().trim();
    final b = (body ?? '').toString().trim();
    final text = t.isEmpty ? b : (b.isEmpty ? t : '$t — $b');
    if (text.isEmpty) return;
    try {
      _scaffoldMessengerKey?.currentState?.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {}
  }

  /// Toca áudio de lembrete de agenda quando push chega com app aberto (paridade Yahweh).
  static Future<void> playAgendaReminderAudioIfPresent(RemoteMessage message) async {
    final d = message.data;
    if ((d['type'] ?? '').toString() != 'agenda_reminder') return;
    try {
      final soundId = (d['soundId'] ?? '').toString().trim();
      if (soundId.isNotEmpty) {
        await NotificationAudioPlayer.instance.playBundledById(soundId);
        return;
      }
      final kind = (d['channelKind'] ?? '').toString().toLowerCase();
      final cat = switch (kind) {
        'audiencia' => NotificationSoundCategory.audiencia,
        'compromisso' => NotificationSoundCategory.compromisso,
        'escala' => NotificationSoundCategory.escala,
        'financeiro' => NotificationSoundCategory.financeiro,
        _ => null,
      };
      if (cat != null) {
        await NotificationAudioPlayer.instance.playForCategory(cat);
      }
    } catch (_) {}
  }

  /// Foreground: SnackBar com ação **Abrir link** (iOS / Android / Web instalada).
  static void showForegroundPushWithOptionalLink(RemoteMessage message) {
    final d = message.data;
    final title = (message.notification?.title ?? d['title'])?.toString();
    final body = (message.notification?.body ?? d['body'])?.toString();
    final link = linkFromRemoteMessage(message);
    final t = (title ?? '').trim();
    final b = (body ?? '').trim();
    if (t.isEmpty && b.isEmpty && link == null) return;

    final isAgenda = (d['type'] ?? '').toString() == 'agenda_reminder';
    final channelKind =
        NotificationModuleTheme.normalizeKind((d['channelKind'] ?? 'escala').toString());
    final theme = NotificationModuleTheme.forKind(channelKind);
    try {
      _scaffoldMessengerKey?.currentState?.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E293B),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                margin: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
                decoration: BoxDecoration(
                  color: Color(theme.colorArgb),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: isAgenda && b.contains('\n')
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (t.isNotEmpty)
                            Text(
                              t,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          if (b.isNotEmpty) ...[
                            if (t.isNotEmpty) const SizedBox(height: 6),
                            Text(
                              b,
                              style: const TextStyle(
                                height: 1.35,
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Text(
                        t.isEmpty && b.isEmpty && link != null
                            ? 'Toque em "Abrir link" para ver no navegador.'
                            : (t.isEmpty ? b : (b.isEmpty ? t : '$t\n$b')),
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            ],
          ),
          duration: Duration(seconds: link != null ? 12 : 5),
          behavior: SnackBarBehavior.floating,
          action: link != null
              ? SnackBarAction(
                  label: 'Abrir',
                  onPressed: () {
                    openNotificationLinkIfPresent(message);
                  },
                )
              : null,
        ),
      );
    } catch (_) {}
  }

  static String _fcmTokenDocId(String token) {
    final clean = token.trim();
    if (clean.isNotEmpty && clean.length <= 512 && !clean.contains('/')) {
      return clean;
    }
    return sha256.convert(utf8.encode(clean)).toString();
  }

  /// Plataforma atual (web, android, ios) sem usar dart:io para não quebrar build web.
  static String get _platform {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    return 'unknown';
  }

  /// Re-registra token após voltar do background (usuário pode ter ativado notificações no SO).
  static Future<void> ensureRegisteredAfterResume() async {
    if (kIsWeb) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final svc = PushNotificationService();
    await svc.inicializar();
    await svc.salvarTokenNoBanco();
  }

  /// Inicializa push: permissão, token, listeners. Chamar após login ou ao abrir o app logado.
  Future<void> inicializar() async {
    if (_pushInitialized) {
      _attachAuthTokenListener();
      _attachMessagingListeners();
      return;
    }
    final inFlight = _pushInitFuture;
    if (inFlight != null) return inFlight;
    _pushInitFuture = _inicializarInternal().whenComplete(() {
      _pushInitFuture = null;
    });
    return _pushInitFuture!;
  }

  Future<void> _inicializarInternal() async {
    try {
      if (_isNativeMobile()) {
        // Canais Android + permissão local antes do token FCM.
        await ScaleNotificationsService().init();
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await _fcm.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
          try {
            await _fcm.getAPNSToken().timeout(const Duration(seconds: 12));
          } catch (_) {}
        }
      }

      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
        criticalAlert: false,
        announcement: false,
        carPlay: false,
      );

      final permissionOk = _permissionAllowsPush(settings);

      if (permissionOk || defaultTargetPlatform == TargetPlatform.android) {
        await _registerTokenWithRetry(immediate: true);
      }

      _attachAuthTokenListener();

      if (!permissionOk && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        _attachMessagingListeners();
        _pushInitialized = true;
        return;
      }

      if (!permissionOk && kIsWeb) {
        _pushInitialized = true;
        return;
      }

      _attachMessagingListeners();
      _pushInitialized = true;
    } catch (e, st) {
      debugPrint('PushNotificationService.inicializar: $e\n$st');
    }
  }

  void _attachAuthTokenListener() {
    if (_pushAuthTokenSub != null) return;
    _pushAuthTokenSub =
        FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null || user.uid.isEmpty) return;
      await _registerTokenWithRetry(immediate: true);
    });
  }

  Future<void> _registerTokenWithRetry({bool immediate = false}) async {
    if (immediate) {
      _pushTokenRetryCount = 0;
      _pushTokenRetryTimer?.cancel();
    }
    final fsUid = firestoreUserDocIdStrictFromSession();
    if (fsUid.isEmpty) {
      _scheduleTokenRetry();
      return;
    }
    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        _scheduleTokenRetry();
        return;
      }
      await _salvarToken(token, fsUid);
      _pushTokenRetryCount = 0;
      _pushTokenRetryTimer?.cancel();
    } catch (e, st) {
      debugPrint('PushNotificationService._registerTokenWithRetry: $e\n$st');
      _scheduleTokenRetry();
    }
  }

  void _scheduleTokenRetry() {
    if (_pushTokenRetryCount >= 8) return;
    _pushTokenRetryTimer?.cancel();
    final delay = Duration(seconds: 2 + _pushTokenRetryCount);
    _pushTokenRetryCount++;
    _pushTokenRetryTimer = Timer(delay, () {
      unawaited(_registerTokenWithRetry());
    });
  }

  /// Persiste o token sempre que o FCM o renova (idempotente — só anexa uma vez).
  void _attachTokenRefreshListener() {
    if (_pushTokenRefreshListenerAttached) return;
    _pushTokenRefreshListenerAttached = true;
    _fcm.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      final fsUid = firestoreUserDocIdStrictFromSession();
      if (fsUid.isNotEmpty) await _salvarToken(newToken, fsUid);
    });
  }

  void _attachMessagingListeners() {
    if (_pushMessagingListenersAttached) return;
    _pushMessagingListenersAttached = true;

    _attachTokenRefreshListener();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      unawaited(_handleForegroundMessage(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      openNotificationLinkIfPresent(message);
    });

    unawaited(_handleInitialMessage());
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    await playAgendaReminderAudioIfPresent(message);
    final d = message.data;
    final title = (message.notification?.title ?? d['title'])?.toString();
    final body = (message.notification?.body ?? d['body'])?.toString();
    final floating = d['inAppFloating'] == '1' ||
        d['floating'] == '1' ||
        d['floatingBanner'] == '1';

    if (floating) {
      final t = (title ?? '').trim();
      final b = (body ?? '').trim();
      if (t.isEmpty && b.isEmpty) {
        if (kIsWeb) showForegroundPushWithOptionalLink(message);
        return;
      }
      final url = linkFromRemoteMessage(message);
      final id = (d['messageId'] ??
              d['campaignId'] ??
              DateTime.now().millisecondsSinceEpoch)
          .toString();
      final payload = InAppFloatingPayload(
        id: 'push_$id',
        kind: InAppFloatingKind.pushOrPromo,
        title: t.isEmpty ? kNotificationBrandApp : t,
        body: b.isEmpty && url != null
            ? 'Toque em Abrir para ver no navegador.'
            : b,
        openUrl: url,
      );
      if (!InAppFloatingMessageService.tryShowPushPromo(payload)) {
        if (kIsWeb) showForegroundPushWithOptionalLink(message);
      }
      return;
    }

    if (_isNativeMobile()) {
      await FcmLocalNotificationPresenter.showRemoteMessage(message);
      unawaited(playAgendaReminderAudioIfPresent(message));
      return;
    }

    showForegroundPushWithOptionalLink(message);
  }

  Future<void> _handleInitialMessage() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          openNotificationLinkIfPresent(initial);
        });
      }
    } catch (_) {}
  }

  Future<String?> _getToken() async {
    if (kIsWeb) {
      final vapid = kFcmVapidKeyWeb.trim();
      if (vapid.isNotEmpty && vapid != 'COLE_AQUI_SUA_VAPID_KEY') {
        return _fcm.getToken(vapidKey: vapid);
      }
      return _fcm.getToken();
    }
    return _fcm.getToken();
  }

  /// Atualiza o token no Firestore (chamar após login/cadastro).
  /// Reforço: garante os listeners de refresh/auth já no login, sem depender do
  /// init completo do HomeShell (que só roda alguns segundos depois).
  Future<void> salvarTokenNoBanco() async {
    _attachAuthTokenListener();
    _attachTokenRefreshListener();
    await _registerTokenWithRetry(immediate: true);
  }

  Future<void> _salvarToken(String token, [String? targetUid]) async {
    final uid = targetUid ?? firestoreUserDocIdStrictFromSession();
    if (uid.isEmpty) return;

    final now = DateTime.now();
    if (_lastTokenWriteUid == uid &&
        _lastTokenWriteToken == token &&
        _lastTokenWriteAt != null &&
        now.difference(_lastTokenWriteAt!) < const Duration(minutes: 30)) {
      return;
    }

    final tokenDocId = _fcmTokenDocId(token);
    final tokenFields = {
      'token': token,
      'platform': _platform,
      'authUid': FirebaseAuth.instance.currentUser?.uid ?? uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Caminho oficial: users/{uid}/fcmTokens/{tokenId}
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(tokenDocId)
        .set(tokenFields, SetOptions(merge: true));

    // Legado (functions leem as duas subcoleções).
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('deviceTokens')
        .doc(tokenDocId)
        .set(tokenFields, SetOptions(merge: true));

    // Campo legado no doc do usuário — só se o perfil real já existir (evita fantasma).
    try {
      final userSnap = await _firestore.collection('users').doc(uid).get();
      if (!userSnap.exists) return;
      if (!adminUserHasCompleteEmail(userSnap.data() ?? const {})) return;
      await _firestore.collection('users').doc(uid).set({
        'fcmToken': token,
        'pushEnabled': true,
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
    _lastTokenWriteUid = uid;
    _lastTokenWriteToken = token;
    _lastTokenWriteAt = now;
  }

  /// Remove o token do Firestore ao fazer logout (evita enviar push para dispositivo deslogado).
  static Future<void> removeToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    final fsUid = firestoreUserDocIdStrictFromSession();
    if (fsUid.isEmpty) return;

    final tokenDocId = _fcmTokenDocId(token);
    final userRef = FirebaseFirestore.instance.collection('users').doc(fsUid);
    await userRef.collection('deviceTokens').doc(tokenDocId).delete();
    await userRef.collection('fcmTokens').doc(tokenDocId).delete();

    try {
      final snap = await userRef.get();
      final legacy = (snap.data()?['fcmToken'] ?? '').toString().trim();
      if (legacy == token) {
        await userRef.set({
          'fcmToken': FieldValue.delete(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }
}
